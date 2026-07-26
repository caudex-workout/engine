const std = @import("std");
const canonical = @import("canonical.zig");
const canonical_json = @import("canonical_json.zig");
const double_progression = @import("double_progression.zig");
const engine = @import("engine.zig");
const methodology = @import("methodology.zig");
const primitives = @import("primitives.zig");
const training = @import("training.zig");

pub const abi_version: u32 = 1;
const max_result_bytes: usize = 1024 * 1024;

pub const Status = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    out_of_memory = 2,
    invalid_request = 3,
    unsupported_version = 4,
    unsupported_methodology = 5,
    output_limit_reached = 6,
    internal_error = 255,
};

pub const Buffer = extern struct {
    data: ?[*]u8 = null,
    len: usize = 0,
    capacity: usize = 0,
};

pub const Runtime = struct {
    allocator: std.mem.Allocator,
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
    runtime.* = .{ .allocator = std.heap.page_allocator };
    destination.* = runtime;
    return .ok;
}

pub export fn caudex_runtime_destroy(runtime: ?*Runtime) callconv(.c) void {
    if (runtime) |value| value.allocator.destroy(value);
}

pub export fn caudex_runtime_execute(
    runtime: ?*Runtime,
    request_data: ?[*]const u8,
    request_len: usize,
    out_result: ?*Buffer,
) callconv(.c) Status {
    const active = runtime orelse return .invalid_argument;
    const result = out_result orelse return .invalid_argument;
    if (result.data != null or result.len != 0 or result.capacity != 0) {
        return .invalid_argument;
    }
    if (request_data == null and request_len != 0) return .invalid_argument;
    const input = if (request_len == 0)
        @as([]const u8, &.{})
    else
        request_data.?[0..request_len];

    execute(active, input, result) catch |err| return switch (err) {
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
    return .ok;
}

pub export fn caudex_buffer_free(
    runtime: ?*Runtime,
    buffer: ?*Buffer,
) callconv(.c) void {
    const active = runtime orelse return;
    const value = buffer orelse return;
    if (value.data) |data| {
        if (value.capacity != 0) {
            active.allocator.free(data[0..value.capacity]);
        }
    }
    value.* = .{};
}

const ExecuteError = canonical_json.DecodeError || engine.RecommendError ||
    error{InvalidRequest};

fn execute(
    runtime: *Runtime,
    input: []const u8,
    out: *Buffer,
) ExecuteError!void {
    const document = try canonical_json.decodeRecommendationRequest(
        runtime.allocator,
        input,
        .{},
    );
    defer document.deinit();

    var arena = std.heap.ArenaAllocator.init(runtime.allocator);
    defer arena.deinit();
    const request = try translateRequest(arena.allocator(), document.value);
    var engine_output: engine.Output = .{};
    const result = try engine.recommendSession(request, &engine_output);

    const bytes = runtime.allocator.alloc(u8, max_result_bytes) catch
        return error.OutOfMemory;
    errdefer runtime.allocator.free(bytes);
    const encoded = canonical_json.encode(result, bytes) catch
        return error.OutputLimitReached;
    out.* = .{
        .data = bytes.ptr,
        .len = encoded.len,
        .capacity = bytes.len,
    };
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

test "C runtime executes a canonical request and frees its result" {
    var runtime: ?*Runtime = null;
    try std.testing.expectEqual(Status.ok, caudex_runtime_create(&runtime));
    defer caudex_runtime_destroy(runtime);
    var result: Buffer = .{};
    const input = @embedFile("../fixtures/requests/recommendation.json");
    try std.testing.expectEqual(
        Status.ok,
        caudex_runtime_execute(runtime, input.ptr, input.len, &result),
    );
    try std.testing.expect(result.data != null);
    try std.testing.expect(result.len != 0);
    const parsed = try canonical_json.decodeRecommendationResult(
        std.testing.allocator,
        result.data.?[0..result.len],
        .{},
    );
    defer parsed.deinit();
    try std.testing.expect(parsed.value.ok);
    caudex_buffer_free(runtime, &result);
    try std.testing.expect(result.data == null);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "C ABI rejects invalid arguments without exposing errors" {
    var result: Buffer = .{};
    try std.testing.expectEqual(
        Status.invalid_argument,
        caudex_runtime_execute(null, null, 0, &result),
    );
    try std.testing.expectEqual(Status.invalid_argument, caudex_runtime_create(null));
    try std.testing.expectEqual(@as(u32, 1), caudex_abi_version());
}
