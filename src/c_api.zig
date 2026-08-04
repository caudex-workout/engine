const std = @import("std");
const canonical = @import("canonical.zig");
const canonical_json = @import("canonical_json.zig");
const double_progression = @import("double_progression.zig");
const engine = @import("engine.zig");
const methodology = @import("methodology.zig");
const primitives = @import("primitives.zig");
const rpe_top_set_backoff = @import("rpe_top_set_backoff.zig");
const training = @import("training.zig");

pub const abi_version: u32 = 2;
const max_result_bytes: usize = 1024 * 1024;

pub const Status = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    out_of_memory = 2,
    invalid_request = 3,
    unsupported_version = 4,
    unsupported_methodology = 5,
    output_limit_reached = 6,
    insufficient_output = 7,
    internal_error = 255,
};

const OwnedBuffer = struct {
    data: ?[*]u8 = null,
    len: usize = 0,
    capacity: usize = 0,
};

const RuntimeAllocator = std.heap.DebugAllocator(.{});

pub const Runtime = struct {
    debug_allocator: RuntimeAllocator,

    fn allocator(self: *Runtime) std.mem.Allocator {
        return self.debug_allocator.allocator();
    }
};

pub export fn caudex_abi_version() callconv(.c) u32 {
    return abi_version;
}

pub export fn caudex_runtime_create(
    out_runtime: ?*?*Runtime,
) callconv(.c) Status {
    const destination = out_runtime orelse return .invalid_argument;
    const runtime = std.heap.page_allocator.create(Runtime) catch
        return .out_of_memory;
    runtime.* = .{ .debug_allocator = .init };
    destination.* = runtime;
    return .ok;
}

pub export fn caudex_runtime_destroy(runtime: ?*Runtime) callconv(.c) void {
    if (runtime) |value| {
        _ = value.debug_allocator.deinit();
        std.heap.page_allocator.destroy(value);
    }
}

pub export fn caudex_runtime_execute(
    runtime: ?*Runtime,
    request_data: ?[*]const u8,
    request_len: usize,
    output_data: ?[*]u8,
    output_capacity: usize,
    out_required: ?*usize,
) callconv(.c) Status {
    const active = runtime orelse return .invalid_argument;
    const required = out_required orelse return .invalid_argument;
    required.* = 0;
    if (request_data == null and request_len != 0) return .invalid_argument;
    if (output_data == null and output_capacity != 0) return .invalid_argument;
    const input = if (request_len == 0)
        @as([]const u8, &.{})
    else
        request_data.?[0..request_len];

    var result: OwnedBuffer = .{};
    executeDispatch(active, input, &result) catch |err| return statusForError(err);
    defer if (result.data) |data| active.allocator().free(data[0..result.capacity]);
    required.* = result.len;
    if (output_capacity < result.len) return .insufficient_output;
    if (result.len != 0) @memcpy(output_data.?[0..result.len], result.data.?[0..result.len]);
    return .ok;
}

const ExecuteError = canonical_json.DecodeError || engine.RecommendError ||
    error{InvalidRequest};

const Operation = enum {
    recommend,
    evaluate,
};

const ExecutionRequest = struct {
    schemaVersion: u32,
    operation: Operation,
    payload: std.json.Value,
};

fn executeDispatch(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const document = try canonical_json.decodeValue(ExecutionRequest, runtime.allocator(), input, .{});
    defer document.deinit();
    if (document.value.schemaVersion != 1) return error.UnsupportedVersion;
    const payload = runtime.allocator().alloc(u8, (canonical_json.Limits{}).max_input_bytes) catch return error.OutOfMemory;
    defer runtime.allocator().free(payload);
    var writer: std.Io.Writer = .fixed(payload);
    std.json.Stringify.value(document.value.payload, .{}, &writer) catch return error.InvalidRequest;
    return switch (document.value.operation) {
        .recommend => executeRecommendation(runtime, writer.buffered(), out),
        .evaluate => executeEvaluation(runtime, writer.buffered(), out),
    };
}

fn statusForError(err: ExecuteError) Status {
    return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.UnsupportedVersion => .unsupported_version,
        error.UnsupportedMethodology => .unsupported_methodology,
        error.OutputLimitReached => .output_limit_reached,
        error.InvalidRequest,
        error.InputTooLarge,
        error.InvalidUtf8,
        error.MalformedJson,
        error.NestingLimitExceeded,
        error.CollectionLimitExceeded,
        error.ValueTooLarge,
        error.InvalidDecimal,
        => .invalid_request,
    };
}

fn executeRecommendation(
    runtime: *Runtime,
    input: []const u8,
    out: *OwnedBuffer,
) ExecuteError!void {
    const document = try canonical_json.decodeRecommendationRequest(
        runtime.allocator(),
        input,
        .{},
    );
    defer document.deinit();

    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    if (std.mem.eql(
        u8,
        document.value.methodology.id,
        rpe_top_set_backoff.methodology_id,
    )) {
        return executeRpeRecommendation(
            runtime,
            arena.allocator(),
            document.value,
            out,
        );
    }
    const request = try translateRequest(arena.allocator(), document.value);
    var engine_output: engine.Output = .{};
    const result = try engine.recommendSession(request, &engine_output);

    const bytes = runtime.allocator().alloc(u8, max_result_bytes) catch
        return error.OutOfMemory;
    errdefer runtime.allocator().free(bytes);
    const encoded = canonical_json.encode(result, bytes) catch
        return error.OutputLimitReached;
    out.* = .{
        .data = bytes.ptr,
        .len = encoded.len,
        .capacity = bytes.len,
    };
}

const RpeWireResult = struct {
    ok: bool = true,
    recommendation: canonical.SessionRecommendation,
    explanations: []const canonical.Explanation,
    warnings: []const canonical.ValidationIssue,
    issues: []const canonical.ValidationIssue = &.{},
    metadata: canonical.ResultMetadata,
};

fn executeRpeRecommendation(
    runtime: *Runtime,
    allocator: std.mem.Allocator,
    source: canonical.RecommendationRequest,
    out: *OwnedBuffer,
) ExecuteError!void {
    if (source.methodology.configVersion != rpe_top_set_backoff.config_version) {
        return error.UnsupportedVersion;
    }
    _ = try resolvedVersion(source.methodology.versionRequirement);
    if (source.catalog.len != 1) return error.InvalidRequest;
    const config = std.json.parseFromValueLeaky(
        rpe_top_set_backoff.Config,
        allocator,
        source.methodology.config,
        .{ .ignore_unknown_fields = false },
    ) catch return error.InvalidRequest;
    const state = try translateRpeState(allocator, source.methodologyState);
    const catalog = try translateCatalog(allocator, source.catalog);
    const history = try translateHistory(allocator, source.history);
    const exercise = catalog.exercises[0];
    const available = try translateIds(
        allocator,
        source.session.availableEquipmentIds,
    );
    for (exercise.equipment_ids) |required| {
        for (available) |candidate| {
            if (required.eql(candidate)) break;
        } else return error.InvalidRequest;
    }
    const top = rpe_top_set_backoff.recommendTopSet(
        config,
        state,
        history,
        exercise.id,
    ) catch return error.InvalidRequest;
    const backoff = rpe_top_set_backoff.recommendBackoffs(
        config,
        top,
    ) catch return error.InvalidRequest;

    const set_count: usize = @as(usize, backoff.set_count) + 1;
    const sets = allocator.alloc(canonical.SetRecommendation, set_count) catch
        return error.OutOfMemory;
    const metrics = allocator.alloc(canonical.Metric, 3 + backoff.set_count * 2) catch
        return error.OutOfMemory;
    const top_refs = try allocator.alloc([]const u8, 2);
    top_refs[0] = "explanation-1";
    top_refs[1] = "explanation-2";
    const backoff_refs = try allocator.alloc([]const u8, 1);
    backoff_refs[0] = "explanation-3";
    metrics[0] = .{ .code = "load", .value = try boundaryMeasurement(allocator, top.load) };
    metrics[1] = .{
        .code = "repetitions",
        .value = .{ .amount = try std.fmt.allocPrint(allocator, "{d}", .{top.repetitions}), .unit = "count" },
    };
    metrics[2] = .{
        .code = "rpe",
        .value = .{ .amount = try formatDecimal(allocator, top.target_rpe), .unit = "rpe" },
    };
    sets[0] = .{
        .kind = "top",
        .targetMetrics = metrics[0..3],
        .explanationRefs = top_refs,
    };
    var metric_index: usize = 3;
    for (1..set_count) |set_index| {
        metrics[metric_index] = .{
            .code = "load",
            .value = try boundaryMeasurement(allocator, backoff.load),
        };
        metrics[metric_index + 1] = .{
            .code = "repetitions",
            .value = .{
                .amount = try std.fmt.allocPrint(allocator, "{d}", .{backoff.repetitions}),
                .unit = "count",
            },
        };
        sets[set_index] = .{
            .kind = "backoff",
            .targetMetrics = metrics[metric_index .. metric_index + 2],
            .explanationRefs = backoff_refs,
        };
        metric_index += 2;
    }
    const selection_refs = [_][]const u8{ "explanation-1", "explanation-2", "explanation-3" };
    const exercises = [_]canonical.ExerciseRecommendation{.{
        .exerciseId = exercise.id.bytes,
        .sets = sets,
        .explanationRefs = &selection_refs,
    }};
    const explanations = [_]canonical.Explanation{
        .{
            .id = "explanation-1",
            .code = "exercise.selected.available_equipment",
            .category = "selection",
            .summary = "Available equipment supported the exercise selection.",
            .subject = .{ .exerciseId = exercise.id.bytes },
            .severity = .info,
        },
        .{
            .id = "explanation-2",
            .code = top.explanation.code,
            .category = "load",
            .summary = top.explanation.summary,
            .subject = .{ .exerciseId = exercise.id.bytes },
            .ruleId = top.explanation.rule_id,
            .severity = .info,
        },
        .{
            .id = "explanation-3",
            .code = backoff.explanation.code,
            .category = "load",
            .summary = backoff.explanation.summary,
            .subject = .{ .exerciseId = exercise.id.bytes },
            .ruleId = backoff.explanation.rule_id,
            .severity = .info,
        },
    };
    const warnings: []const canonical.ValidationIssue = if (top.warning) |warning|
        try allocator.dupe(canonical.ValidationIssue, &.{warning})
    else
        &.{};
    const canonical_storage = try allocator.alloc(u8, max_result_bytes);
    const canonical_input = canonical_json.encode(source, canonical_storage) catch
        return error.OutputLimitReached;
    var input_fingerprint: [64]u8 = undefined;
    var result_fingerprint: [64]u8 = undefined;
    fingerprintBytes("caudex:recommendation-request:v1\x00", canonical_input, &input_fingerprint);
    var result_hash = std.crypto.hash.sha2.Sha256.init(.{});
    result_hash.update("caudex:recommendation-result:v1\x00");
    result_hash.update(&input_fingerprint);
    result_hash.update(exercise.id.bytes);
    result_hash.update(top.explanation.code);
    result_hash.update(backoff.explanation.code);
    finishHex(&result_hash, &result_fingerprint);
    const wire = RpeWireResult{
        .recommendation = .{ .exercises = &exercises },
        .explanations = &explanations,
        .warnings = warnings,
        .metadata = .{
            .engineVersion = engine.engine_version,
            .schemaVersion = engine.schema_version,
            .methodology = .{
                .id = rpe_top_set_backoff.methodology_id,
                .version = "0.1.0",
                .configVersion = rpe_top_set_backoff.config_version,
            },
            .inputFingerprint = &input_fingerprint,
            .resultFingerprint = &result_fingerprint,
        },
    };
    const bytes = runtime.allocator().alloc(u8, max_result_bytes) catch
        return error.OutOfMemory;
    errdefer runtime.allocator().free(bytes);
    const encoded = canonical_json.encode(wire, bytes) catch
        return error.OutputLimitReached;
    out.* = .{ .data = bytes.ptr, .len = encoded.len, .capacity = bytes.len };
}

fn boundaryMeasurement(
    allocator: std.mem.Allocator,
    measurement: primitives.Measurement,
) ExecuteError!canonical.Measurement {
    return .{
        .amount = try formatDecimal(allocator, measurement.value),
        .unit = measurement.unit.code(),
    };
}

fn formatDecimal(
    allocator: std.mem.Allocator,
    decimal: primitives.Decimal,
) ExecuteError![]const u8 {
    const storage = try allocator.alloc(u8, 64);
    return decimal.format(storage) catch return error.OutputLimitReached;
}

fn translateRpeState(
    allocator: std.mem.Allocator,
    source: ?canonical.MethodologyState,
) ExecuteError!?rpe_top_set_backoff.State {
    const state = source orelse return null;
    if (state.schemaVersion != rpe_top_set_backoff.state_schema_version) {
        return error.UnsupportedVersion;
    }
    const data = std.json.parseFromValueLeaky(
        rpe_top_set_backoff.StateData,
        allocator,
        state.data,
        .{ .ignore_unknown_fields = false },
    ) catch return error.InvalidRequest;
    return .{ .schemaVersion = state.schemaVersion, .data = data };
}

const EvaluationWireResult = struct {
    ok: bool = true,
    evaluation: canonical.PerformanceEvaluation,
    nextMethodologyState: double_progression.State,
    explanations: []const canonical.Explanation,
    warnings: []const canonical.ValidationIssue,
    issues: []const canonical.ValidationIssue = &.{},
    metadata: canonical.ResultMetadata,
};

fn executeEvaluation(
    runtime: *Runtime,
    input: []const u8,
    out: *OwnedBuffer,
) ExecuteError!void {
    const document = try canonical_json.decodeEvaluationRequest(
        runtime.allocator(),
        input,
        .{},
    );
    defer document.deinit();

    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const request = try translateEvaluationRequest(
        arena.allocator(),
        document.value,
    );
    var engine_output: engine.EvaluationOutput = .{};
    const evaluation = try engine.evaluatePerformance(request, &engine_output);

    const exercise_count = evaluation.exercises.len;
    const exercises = arena.allocator().alloc(
        canonical.ExerciseEvaluation,
        exercise_count,
    ) catch return error.OutOfMemory;
    const explanations = arena.allocator().alloc(
        canonical.Explanation,
        exercise_count,
    ) catch return error.OutOfMemory;
    const warning_storage = arena.allocator().alloc(
        canonical.ValidationIssue,
        exercise_count,
    ) catch return error.OutOfMemory;
    const reference_storage = arena.allocator().alloc(
        [1][]const u8,
        exercise_count,
    ) catch return error.OutOfMemory;
    var warning_len: usize = 0;
    for (evaluation.exercises, 0..) |item, index| {
        const explanation_id = std.fmt.allocPrint(
            arena.allocator(),
            "explanation-{d}",
            .{index + 1},
        ) catch return error.OutOfMemory;
        reference_storage[index] = .{explanation_id};
        exercises[index] = .{
            .exerciseId = item.exercise_id,
            .outcome = item.outcome,
            .explanationRefs = &reference_storage[index],
        };
        explanations[index] = .{
            .id = explanation_id,
            .code = item.explanation.code,
            .category = "progression",
            .summary = item.explanation.summary,
            .subject = .{ .exerciseId = item.exercise_id },
            .evidence = &.{.{ .path = "/completedWorkout" }},
            .ruleId = item.explanation.rule_id,
            .severity = .info,
        };
        if (item.warning) |warning| {
            warning_storage[warning_len] = warning;
            warning_len += 1;
        }
    }

    var input_fingerprint: [64]u8 = undefined;
    var result_fingerprint: [64]u8 = undefined;
    const canonical_input_storage = arena.allocator().alloc(
        u8,
        max_result_bytes,
    ) catch return error.OutOfMemory;
    const canonical_input = canonical_json.encode(
        document.value,
        canonical_input_storage,
    ) catch return error.OutputLimitReached;
    fingerprintBytes(
        "caudex:evaluation-request:v1\x00",
        canonical_input,
        &input_fingerprint,
    );
    var result_hash = std.crypto.hash.sha2.Sha256.init(.{});
    result_hash.update("caudex:evaluation-result:v1\x00");
    result_hash.update(&input_fingerprint);
    result_hash.update(evaluation.outcome);
    for (evaluation.exercises) |item| {
        result_hash.update(item.exercise_id);
        result_hash.update(item.outcome);
        result_hash.update(item.explanation.code);
    }
    finishHex(&result_hash, &result_fingerprint);

    const wire = EvaluationWireResult{
        .evaluation = .{
            .outcome = evaluation.outcome,
            .exercises = exercises,
        },
        .nextMethodologyState = evaluation.next_state,
        .explanations = explanations,
        .warnings = warning_storage[0..warning_len],
        .metadata = .{
            .engineVersion = engine.engine_version,
            .schemaVersion = engine.schema_version,
            .methodology = .{
                .id = request.methodology_id.bytes,
                .version = "0.1.0",
                .configVersion = double_progression.config_version,
            },
            .inputFingerprint = &input_fingerprint,
            .resultFingerprint = &result_fingerprint,
        },
    };
    const bytes = runtime.allocator().alloc(u8, max_result_bytes) catch
        return error.OutOfMemory;
    errdefer runtime.allocator().free(bytes);
    const encoded = canonical_json.encode(wire, bytes) catch
        return error.OutputLimitReached;
    out.* = .{
        .data = bytes.ptr,
        .len = encoded.len,
        .capacity = bytes.len,
    };
}

fn translateEvaluationRequest(
    allocator: std.mem.Allocator,
    request: canonical.EvaluationRequest,
) ExecuteError!engine.EvaluationRequest {
    if (!std.mem.eql(
        u8,
        request.methodology.id,
        double_progression.methodology_id,
    )) {
        return error.UnsupportedMethodology;
    }
    if (request.methodology.configVersion != double_progression.config_version) {
        return error.UnsupportedVersion;
    }
    const config = std.json.parseFromValueLeaky(
        double_progression.Config,
        allocator,
        request.methodology.config,
        .{ .ignore_unknown_fields = false },
    ) catch return error.InvalidRequest;
    const completed_workout = allocator.create(training.CompletedWorkout) catch
        return error.OutOfMemory;
    completed_workout.* = .{
        .id = primitives.Id.parse(request.completedWorkout.id) catch
            return error.InvalidRequest,
        .started_at = primitives.Timestamp.parse(
            request.completedWorkout.startedAt,
        ) catch return error.InvalidRequest,
        .completed_at = primitives.Timestamp.parse(
            request.completedWorkout.completedAt,
        ) catch return error.InvalidRequest,
        .exercises = try translateCompletedExercises(
            allocator,
            request.completedWorkout.exercises,
        ),
    };
    return .{
        .as_of = primitives.Timestamp.parse(request.asOf) catch
            return error.InvalidRequest,
        .methodology_id = primitives.Id.parse(request.methodology.id) catch
            return error.InvalidRequest,
        .methodology_version = try resolvedVersion(
            request.methodology.versionRequirement,
        ),
        .config = config,
        .methodology_state = try translateState(
            allocator,
            request.methodologyState,
            config,
        ),
        .catalog = try translateCatalog(allocator, request.catalog),
        .completed_workout = completed_workout,
    };
}

fn fingerprintBytes(
    domain: []const u8,
    bytes: []const u8,
    out: *[64]u8,
) void {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(domain);
    hash.update(bytes);
    finishHex(&hash, out);
}

fn finishHex(hash: *std.crypto.hash.sha2.Sha256, out: *[64]u8) void {
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const alphabet = "0123456789abcdef";
    for (digest, 0..) |byte, index| {
        out[index * 2] = alphabet[byte >> 4];
        out[index * 2 + 1] = alphabet[byte & 0x0f];
    }
}

fn translateRequest(
    allocator: std.mem.Allocator,
    request: canonical.RecommendationRequest,
) ExecuteError!engine.RecommendationRequest {
    if (!std.mem.eql(
        u8,
        request.methodology.id,
        double_progression.methodology_id,
    )) {
        return error.UnsupportedMethodology;
    }
    if (request.methodology.configVersion != double_progression.config_version) {
        return error.UnsupportedVersion;
    }
    const config = std.json.parseFromValueLeaky(
        double_progression.Config,
        allocator,
        request.methodology.config,
        .{ .ignore_unknown_fields = false },
    ) catch return error.InvalidRequest;
    const catalog = try translateCatalog(allocator, request.catalog);
    const history = try translateHistory(allocator, request.history);
    const equipment = try translateIds(
        allocator,
        request.session.availableEquipmentIds,
    );
    return .{
        .as_of = primitives.Timestamp.parse(request.asOf) catch
            return error.InvalidRequest,
        .methodology_id = primitives.Id.parse(request.methodology.id) catch
            return error.InvalidRequest,
        .methodology_version = try resolvedVersion(
            request.methodology.versionRequirement,
        ),
        .config = config,
        .methodology_state = try translateState(
            allocator,
            request.methodologyState,
            config,
        ),
        .catalog = catalog,
        .history = history,
        .available_equipment_ids = equipment,
        .max_working_sets = request.session.maxSets,
    };
}

fn resolvedVersion(requirement: ?[]const u8) ExecuteError!methodology.Version {
    if (requirement) |value| {
        if (!std.mem.eql(u8, value, "^0.1.0") and
            !std.mem.eql(u8, value, "0.1.0"))
        {
            return error.UnsupportedVersion;
        }
    }
    return .{ .major = 0, .minor = 1, .patch = 0 };
}

fn translateCatalog(
    allocator: std.mem.Allocator,
    source: []const canonical.Exercise,
) ExecuteError!training.ExerciseCatalog {
    const exercises = allocator.alloc(training.Exercise, source.len) catch
        return error.OutOfMemory;
    for (source, exercises) |input, *output| {
        output.* = .{
            .id = primitives.Id.parse(input.id) catch return error.InvalidRequest,
            .name = input.name,
            .equipment_ids = try translateIds(allocator, input.equipmentIds),
            .movement_tags = try translateIds(allocator, input.movementTags),
            .unilateral = input.unilateral,
            .aliases = input.aliases,
        };
    }
    return .{ .exercises = exercises };
}

fn translateIds(
    allocator: std.mem.Allocator,
    source: []const []const u8,
) ExecuteError![]const primitives.Id {
    const ids = allocator.alloc(primitives.Id, source.len) catch
        return error.OutOfMemory;
    for (source, ids) |input, *output| {
        output.* = primitives.Id.parse(input) catch return error.InvalidRequest;
    }
    return ids;
}

fn translateHistory(
    allocator: std.mem.Allocator,
    source: canonical.HistorySnapshot,
) ExecuteError!training.HistorySnapshot {
    const workouts = allocator.alloc(training.CompletedWorkout, source.workouts.len) catch
        return error.OutOfMemory;
    for (source.workouts, workouts) |input, *output| {
        output.* = .{
            .id = primitives.Id.parse(input.id) catch return error.InvalidRequest,
            .started_at = primitives.Timestamp.parse(input.startedAt) catch
                return error.InvalidRequest,
            .completed_at = primitives.Timestamp.parse(input.completedAt) catch
                return error.InvalidRequest,
            .exercises = try translateCompletedExercises(allocator, input.exercises),
        };
    }
    return .{ .workouts = workouts };
}

fn translateCompletedExercises(
    allocator: std.mem.Allocator,
    source: []const canonical.CompletedExercise,
) ExecuteError![]const training.CompletedExercise {
    const exercises = allocator.alloc(training.CompletedExercise, source.len) catch
        return error.OutOfMemory;
    for (source, exercises) |input, *output| {
        output.* = .{
            .exercise_id = primitives.Id.parse(input.exerciseId) catch
                return error.InvalidRequest,
            .sets = try translateSets(allocator, input.sets),
            .tags = try translateIds(allocator, input.tags),
            .notes = input.notes,
        };
    }
    return exercises;
}

fn translateSets(
    allocator: std.mem.Allocator,
    source: []const canonical.CompletedSet,
) ExecuteError![]const training.CompletedSet {
    const sets = allocator.alloc(training.CompletedSet, source.len) catch
        return error.OutOfMemory;
    for (source, sets) |input, *output| {
        output.* = .{
            .id = if (input.id) |id|
                primitives.Id.parse(id) catch return error.InvalidRequest
            else
                null,
            .kind = primitives.Id.parse(input.kind) catch
                return error.InvalidRequest,
            .actual_metrics = try translateMetrics(allocator, input.actualMetrics),
            .target_metrics = try translateMetrics(allocator, input.targetMetrics),
            .completed_at = if (input.completedAt) |timestamp|
                primitives.Timestamp.parse(timestamp) catch return error.InvalidRequest
            else
                null,
            .status = @enumFromInt(@intFromEnum(input.status)),
        };
    }
    return sets;
}

fn translateMetrics(
    allocator: std.mem.Allocator,
    source: []const canonical.Metric,
) ExecuteError![]const training.Metric {
    const metrics = allocator.alloc(training.Metric, source.len) catch
        return error.OutOfMemory;
    for (source, metrics) |input, *output| {
        output.* = .{
            .code = primitives.Id.parse(input.code) catch
                return error.InvalidRequest,
            .value = .{
                .value = primitives.Decimal.parse(input.value.amount) catch
                    return error.InvalidRequest,
                .unit = primitives.Unit.parse(input.value.unit) catch
                    return error.InvalidRequest,
            },
        };
    }
    return metrics;
}

fn translateState(
    allocator: std.mem.Allocator,
    source: ?canonical.MethodologyState,
    config: double_progression.Config,
) ExecuteError!?double_progression.State {
    const state = source orelse return null;
    if (state.schemaVersion != double_progression.state_schema_version) {
        return error.UnsupportedVersion;
    }
    const data = switch (state.data) {
        .object => |object| object,
        else => return error.InvalidRequest,
    };
    const exercise_value = data.get("exercises") orelse return error.InvalidRequest;
    if (exercise_value == .array) {
        const exercises = std.json.parseFromValueLeaky(
            []const double_progression.ExerciseState,
            allocator,
            exercise_value,
            .{},
        ) catch return error.InvalidRequest;
        return .{
            .schemaVersion = state.schemaVersion,
            .data = .{ .exercises = exercises },
        };
    }
    const keyed = switch (exercise_value) {
        .object => |object| object,
        else => return error.InvalidRequest,
    };
    const exercises = allocator.alloc(
        double_progression.ExerciseState,
        keyed.count(),
    ) catch return error.OutOfMemory;
    var iterator = keyed.iterator();
    var index: usize = 0;
    while (iterator.next()) |entry| : (index += 1) {
        const value = switch (entry.value_ptr.*) {
            .object => |object| object,
            else => return error.InvalidRequest,
        };
        const load_value = value.get("load") orelse return error.InvalidRequest;
        const load = std.json.parseFromValueLeaky(
            canonical.Measurement,
            allocator,
            load_value,
            .{},
        ) catch return error.InvalidRequest;
        exercises[index] = .{
            .exerciseId = entry.key_ptr.*,
            .load = load,
            .targetRepetitions = config.repRange.min,
        };
    }
    return .{
        .schemaVersion = state.schemaVersion,
        .data = .{ .exercises = exercises },
    };
}

test "C runtime reports required size and writes caller-owned output" {
    var runtime: ?*Runtime = null;
    try std.testing.expectEqual(Status.ok, caudex_runtime_create(&runtime));
    defer caudex_runtime_destroy(runtime);
    const input = @embedFile("../fixtures/operations/recommendation-v1.json");
    var required: usize = 0;
    try std.testing.expectEqual(
        Status.insufficient_output,
        caudex_runtime_execute(runtime, input.ptr, input.len, null, 0, &required),
    );
    try std.testing.expect(required != 0);
    const output = try std.testing.allocator.alloc(u8, required);
    defer std.testing.allocator.free(output);
    var exact_required: usize = 0;
    try std.testing.expectEqual(
        Status.ok,
        caudex_runtime_execute(runtime, input.ptr, input.len, output.ptr, output.len, &exact_required),
    );
    try std.testing.expectEqual(required, exact_required);
    const parsed = try canonical_json.decodeRecommendationResult(
        std.testing.allocator,
        output,
        .{},
    );
    defer parsed.deinit();
    try std.testing.expect(parsed.value.ok);
}

test "versioned dispatcher accepts recommendation envelope" {
    var runtime: Runtime = .{ .debug_allocator = .init };
    defer _ = runtime.debug_allocator.deinit();
    var output: OwnedBuffer = .{};
    defer if (output.data) |data| runtime.allocator().free(data[0..output.capacity]);
    try executeDispatch(
        &runtime,
        @embedFile("../fixtures/operations/recommendation-v1.json"),
        &output,
    );
    try std.testing.expect(output.len != 0);
}

test "C ABI rejects invalid arguments without exposing errors" {
    var required: usize = 99;
    try std.testing.expectEqual(
        Status.invalid_argument,
        caudex_runtime_execute(null, null, 0, null, 0, &required),
    );
    try std.testing.expectEqual(Status.invalid_argument, caudex_runtime_create(null));
    try std.testing.expectEqual(@as(u32, 2), caudex_abi_version());
}

test "C ABI leaves insufficient caller output untouched" {
    var runtime: ?*Runtime = null;
    try std.testing.expectEqual(Status.ok, caudex_runtime_create(&runtime));
    defer caudex_runtime_destroy(runtime);
    const input = @embedFile("../fixtures/operations/recommendation-v1.json");
    var required: usize = 0;
    try std.testing.expectEqual(Status.insufficient_output, caudex_runtime_execute(runtime, input.ptr, input.len, null, 0, &required));
    const short = try std.testing.allocator.alloc(u8, required - 1);
    defer std.testing.allocator.free(short);
    @memset(short, 0xaa);
    try std.testing.expectEqual(Status.insufficient_output, caudex_runtime_execute(runtime, input.ptr, input.len, short.ptr, short.len, &required));
    for (short) |byte| try std.testing.expectEqual(@as(u8, 0xaa), byte);
}

test "C ABI validates pointer length and UTF-8 combinations" {
    var runtime: ?*Runtime = null;
    try std.testing.expectEqual(Status.ok, caudex_runtime_create(&runtime));
    defer caudex_runtime_destroy(runtime);
    var required: usize = 0;
    try std.testing.expectEqual(Status.invalid_argument, caudex_runtime_execute(runtime, null, 1, null, 0, &required));
    try std.testing.expectEqual(Status.invalid_argument, caudex_runtime_execute(runtime, null, 0, null, 1, &required));
    try std.testing.expectEqual(Status.invalid_argument, caudex_runtime_execute(runtime, null, 0, null, 0, null));
    const invalid_utf8 = [_]u8{0xff};
    try std.testing.expectEqual(Status.invalid_request, caudex_runtime_execute(runtime, &invalid_utf8, invalid_utf8.len, null, 0, &required));
}

test "C ABI supports independent runtimes" {
    var first: ?*Runtime = null;
    var second: ?*Runtime = null;
    try std.testing.expectEqual(Status.ok, caudex_runtime_create(&first));
    defer caudex_runtime_destroy(first);
    try std.testing.expectEqual(Status.ok, caudex_runtime_create(&second));
    defer caudex_runtime_destroy(second);
    try std.testing.expect(first != second);
    const input = @embedFile("../fixtures/operations/recommendation-v1.json");
    var first_required: usize = 0;
    var second_required: usize = 0;
    try std.testing.expectEqual(Status.insufficient_output, caudex_runtime_execute(first, input.ptr, input.len, null, 0, &first_required));
    try std.testing.expectEqual(Status.insufficient_output, caudex_runtime_execute(second, input.ptr, input.len, null, 0, &second_required));
    try std.testing.expectEqual(first_required, second_required);
}
