const std = @import("std");
const canonical = @import("canonical.zig");
const diagnostics = @import("diagnostics.zig");
const double_progression_contract = @import("double_progression.zig");
const methodology = @import("methodology.zig");
const primitives = @import("primitives.zig");
const training = @import("training.zig");

pub const engine_version = "0.1.0-dev";
pub const schema_version: u32 = 1;

pub const DoubleProgressionConfig = double_progression_contract.Config;

/// The typed, borrowed Zig request supported by the first vertical slice.
///
/// The host owns every referenced value. Recommendation calculation performs no
/// allocation, I/O, persistence, clock reads, or mutation outside `Output`.
pub const RecommendationRequest = struct {
    as_of: primitives.Timestamp,
    methodology_id: primitives.Id,
    methodology_version: methodology.Version,
    config: DoubleProgressionConfig,
    methodology_state: ?double_progression_contract.State = null,
    catalog: training.ExerciseCatalog,
    history: training.HistorySnapshot = .{},
    available_equipment_ids: []const primitives.Id,
};

pub const RecommendError = error{
    UnsupportedMethodology,
    InvalidRequest,
    OutputLimitReached,
};

/// Caller-owned storage for the bounded CWE-015 recommendation result.
pub const Output = struct {
    metrics: [128]canonical.Metric = undefined,
    sets: [64]canonical.SetRecommendation = undefined,
    exercises: [1]canonical.ExerciseRecommendation = undefined,
    explanations: [2]canonical.Explanation = undefined,
    warnings: [1]canonical.ValidationIssue = undefined,
    input_fingerprint: [64]u8 = undefined,
    result_fingerprint: [64]u8 = undefined,
    rep_amount: [20]u8 = undefined,
    rep_amount_len: usize = 0,
    load_amount: [32]u8 = undefined,
    load_amount_len: usize = 0,
    set_len: usize = 0,
    explanation_len: usize = 0,
    warning_len: usize = 0,

    fn result(self: *Output, request: RecommendationRequest) canonical.RecommendationResult {
        return .{
            .ok = true,
            .recommendation = .{ .exercises = self.exercises[0..1] },
            .explanations = self.explanations[0..self.explanation_len],
            .warnings = self.warnings[0..self.warning_len],
            .metadata = .{
                .engineVersion = engine_version,
                .schemaVersion = schema_version,
                .methodology = .{
                    .id = request.methodology_id.bytes,
                    .version = "0.1.0",
                    .configVersion = 1,
                },
                .inputFingerprint = &self.input_fingerprint,
                .resultFingerprint = &self.result_fingerprint,
            },
        };
    }
};

const MethodologyOutput = struct {
    request: *const RecommendationRequest,
    output: *Output,
};

const available_equipment_evidence = [_]canonical.EvidenceRef{
    .{ .path = "/session/availableEquipmentIds" },
};
const set_explanation_refs = [_][]const u8{ "explanation-1", "explanation-2" };

fn validateDoubleProgressionConfig(
    view: methodology.ConfigView,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    const config: *const DoubleProgressionConfig = @ptrCast(@alignCast(view.context));
    try double_progression_contract.validateConfig(config.*, issues);
}

fn recommendDoubleProgression(
    view: methodology.RecommendationView,
    scratch: *methodology.Scratch,
    writer: *methodology.RecommendationWriter,
) methodology.MethodologyError!void {
    _ = scratch;
    const request: *const RecommendationRequest =
        @ptrCast(@alignCast(view.context));
    const destination: *MethodologyOutput =
        @ptrCast(@alignCast(writer.context));
    const exercise = &request.catalog.exercises[0];
    const prescription = double_progression_contract.recommendExercise(
        request.config,
        request.methodology_state,
        request.history,
        exercise.id,
    ) catch return error.InvalidInput;

    destination.output.rep_amount_len = (std.fmt.bufPrint(
        &destination.output.rep_amount,
        "{d}",
        .{prescription.repetitions},
    ) catch return error.OutputLimitReached).len;
    destination.output.load_amount_len = (prescription.load.value.format(
        &destination.output.load_amount,
    ) catch return error.OutputLimitReached).len;
    destination.output.set_len = prescription.working_sets;
    for (0..destination.output.set_len) |set_index| {
        const metric_index = set_index * 2;
        destination.output.metrics[metric_index] = .{
            .code = "load",
            .value = .{
                .amount = destination.output.load_amount[0..destination.output.load_amount_len],
                .unit = prescription.load.unit.code(),
            },
        };
        destination.output.metrics[metric_index + 1] = .{
            .code = "repetitions",
            .value = .{
                .amount = destination.output.rep_amount[0..destination.output.rep_amount_len],
                .unit = "count",
            },
        };
        destination.output.sets[set_index] = .{
            .kind = "working",
            .targetMetrics = destination.output.metrics[metric_index .. metric_index + 2],
            .explanationRefs = &set_explanation_refs,
        };
    }
    destination.output.exercises[0] = .{
        .exerciseId = exercise.id.bytes,
        .sets = destination.output.sets[0..destination.output.set_len],
        .explanationRefs = &set_explanation_refs,
    };
    destination.output.explanations[0] = .{
        .id = "explanation-1",
        .code = "exercise.selected.available_equipment",
        .category = "selection",
        .summary = "Available equipment supported the exercise selection.",
        .subject = .{ .exerciseId = exercise.id.bytes },
        .evidence = &available_equipment_evidence,
        .ruleId = "double-progression.initial-working-set",
        .severity = .info,
    };
    destination.output.explanations[1] = .{
        .id = "explanation-2",
        .code = prescription.explanation.code,
        .category = "progression",
        .summary = prescription.explanation.summary,
        .subject = .{ .exerciseId = exercise.id.bytes },
        .evidence = &.{.{ .path = "/@derived/history/lastCompletedExercise" }},
        .ruleId = prescription.explanation.rule_id,
        .severity = .info,
    };
    destination.output.explanation_len = 2;
    if (prescription.warning) |warning| {
        destination.output.warnings[0] = warning;
        destination.output.warning_len = 1;
    } else {
        destination.output.warning_len = 0;
    }
}

fn evaluateUnsupported(
    view: methodology.EvaluationView,
    scratch: *methodology.Scratch,
    writer: *methodology.EvaluationWriter,
) methodology.MethodologyError!void {
    _ = view;
    _ = scratch;
    _ = writer;
    return error.InvalidInput;
}

const double_progression = methodology.Methodology{
    .metadata = .{
        .id = .{ .bytes = "caudex.double-progression" },
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
        .config_version = 1,
    },
    .validate_config = validateDoubleProgressionConfig,
    .recommend_session = recommendDoubleProgression,
    .evaluate_performance = evaluateUnsupported,
};

const registry = methodology.Registry.initComptime(&.{double_progression});

/// Produces the first deterministic end-to-end recommendation.
pub fn recommendSession(
    request: RecommendationRequest,
    output: *Output,
) RecommendError!canonical.RecommendationResult {
    const implementation = registry.find(
        request.methodology_id,
        request.methodology_version,
    ) orelse return error.UnsupportedMethodology;
    if (request.catalog.exercises.len != 1) {
        return error.InvalidRequest;
    }
    var issue_storage: [16]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&issue_storage);
    implementation.validate_config(
        .{ .context = &request.config },
        &issues,
    ) catch return error.OutputLimitReached;
    if (request.methodology_state) |state| {
        double_progression_contract.validateState(
            request.config,
            state,
            &issues,
        ) catch return error.OutputLimitReached;
    }
    if (issues.items().len != 0) return error.InvalidRequest;
    if (!equipmentAvailable(
        request.catalog.exercises[0].equipment_ids,
        request.available_equipment_ids,
    )) return error.InvalidRequest;

    var scratch = methodology.Scratch{ .bytes = &.{} };
    var methodology_output = MethodologyOutput{
        .request = &request,
        .output = output,
    };
    var writer = methodology.RecommendationWriter{
        .context = &methodology_output,
    };
    implementation.recommend_session(
        .{ .context = &request },
        &scratch,
        &writer,
    ) catch |err| return switch (err) {
        error.InvalidInput => error.InvalidRequest,
        error.OutputLimitReached => error.OutputLimitReached,
    };

    fingerprintRequest(request, &output.input_fingerprint);
    fingerprintResult(request, output, &output.result_fingerprint);
    return output.result(request);
}

fn equipmentAvailable(required: []const primitives.Id, available: []const primitives.Id) bool {
    for (required) |required_id| {
        for (available) |available_id| {
            if (required_id.eql(available_id)) break;
        } else return false;
    }
    return true;
}

fn fingerprintRequest(request: RecommendationRequest, out: *[64]u8) void {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("caudex:recommendation-request:v1\x00");
    hash.update(request.as_of.bytes);
    hash.update("\x00");
    hash.update(request.methodology_id.bytes);
    hash.update("\x00");
    updateU64(&hash, request.methodology_version.major);
    updateU64(&hash, request.methodology_version.minor);
    updateU64(&hash, request.methodology_version.patch);
    fingerprintConfig(&hash, request.config);
    updatePresence(&hash, request.methodology_state != null);
    if (request.methodology_state) |state| {
        updateU64(&hash, state.schemaVersion);
        for (state.data.exercises) |exercise| {
            hash.update(exercise.exerciseId);
            hash.update("\x00");
            updateMeasurement(&hash, exercise.load);
            updateU64(&hash, exercise.targetRepetitions);
        }
    }
    fingerprintHistory(&hash, request.history);
    for (request.catalog.exercises) |exercise| {
        hash.update(exercise.id.bytes);
        hash.update("\x00");
        updatePresence(&hash, exercise.name != null);
        if (exercise.name) |name| {
            hash.update(name);
            hash.update("\x00");
        }
        for (exercise.equipment_ids) |equipment| {
            hash.update(equipment.bytes);
            hash.update("\x00");
        }
        for (exercise.movement_tags) |tag| {
            hash.update(tag.bytes);
            hash.update("\x00");
        }
        for (exercise.muscle_contributions) |contribution| {
            hash.update(contribution.muscle_id.bytes);
            hash.update("\x00");
            hash.update(@tagName(contribution.role));
            hash.update("\x00");
            updatePresence(&hash, contribution.weight != null);
            if (contribution.weight) |weight| updateDecimal(&hash, weight);
        }
        updatePresence(&hash, exercise.unilateral != null);
        if (exercise.unilateral) |unilateral| {
            hash.update(if (unilateral) "\x01" else "\x00");
        }
        for (exercise.aliases) |alias| {
            hash.update(alias);
            hash.update("\x00");
        }
    }
    for (request.available_equipment_ids) |equipment| {
        hash.update(equipment.bytes);
        hash.update("\x00");
    }
    finishHex(&hash, out);
}

fn fingerprintHistory(
    hash: *std.crypto.hash.sha2.Sha256,
    history: training.HistorySnapshot,
) void {
    updateU64(hash, history.workouts.len);
    for (history.workouts) |workout| {
        hash.update(workout.id.bytes);
        hash.update("\x00");
        hash.update(workout.started_at.bytes);
        hash.update("\x00");
        hash.update(workout.completed_at.bytes);
        hash.update("\x00");
        updateU64(hash, workout.exercises.len);
        for (workout.exercises) |exercise| {
            hash.update(exercise.exercise_id.bytes);
            hash.update("\x00");
            updateU64(hash, exercise.sets.len);
            for (exercise.sets) |set| {
                updatePresence(hash, set.id != null);
                if (set.id) |id| {
                    hash.update(id.bytes);
                    hash.update("\x00");
                }
                hash.update(set.kind.bytes);
                hash.update("\x00");
                hash.update(@tagName(set.status));
                hash.update("\x00");
                updatePresence(hash, set.completed_at != null);
                if (set.completed_at) |completed_at| {
                    hash.update(completed_at.bytes);
                    hash.update("\x00");
                }
                updateU64(hash, set.actual_metrics.len);
                for (set.actual_metrics) |metric| {
                    hash.update(metric.code.bytes);
                    hash.update("\x00");
                    updateTrainingMeasurement(hash, metric.value);
                }
                updateU64(hash, set.target_metrics.len);
                for (set.target_metrics) |metric| {
                    hash.update(metric.code.bytes);
                    hash.update("\x00");
                    updateTrainingMeasurement(hash, metric.value);
                }
            }
            for (exercise.tags) |tag| {
                hash.update(tag.bytes);
                hash.update("\x00");
            }
            updatePresence(hash, exercise.notes != null);
            if (exercise.notes) |notes| {
                hash.update(notes);
                hash.update("\x00");
            }
        }
    }
}

fn updateTrainingMeasurement(
    hash: *std.crypto.hash.sha2.Sha256,
    measurement: primitives.Measurement,
) void {
    updateDecimal(hash, measurement.value);
    hash.update(measurement.unit.code());
    hash.update("\x00");
}

fn updateDecimal(
    hash: *std.crypto.hash.sha2.Sha256,
    decimal: primitives.Decimal,
) void {
    updateU64(hash, @as(u64, @bitCast(decimal.mantissa)));
    updateU64(hash, decimal.scale);
}

fn fingerprintResult(
    request: RecommendationRequest,
    output: *const Output,
    out: *[64]u8,
) void {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("caudex:recommendation-result:v1\x00");
    hash.update(request.methodology_id.bytes);
    hash.update("\x00");
    hash.update(output.exercises[0].exerciseId);
    hash.update("\x00working\x00load\x00");
    hash.update(output.load_amount[0..output.load_amount_len]);
    hash.update("\x00");
    hash.update(output.metrics[0].value.unit);
    hash.update("\x00repetitions\x00");
    hash.update(output.rep_amount[0..output.rep_amount_len]);
    updateU64(&hash, output.set_len);
    hash.update("\x00count\x00");
    for (output.explanations[0..output.explanation_len]) |explanation| {
        hash.update(explanation.code);
        hash.update("\x00");
        hash.update(explanation.ruleId orelse "");
        hash.update("\x00");
    }
    for (output.warnings[0..output.warning_len]) |warning| {
        hash.update(warning.code);
        hash.update("\x00");
    }
    finishHex(&hash, out);
}

fn updateU64(hash: *std.crypto.hash.sha2.Sha256, value: anytype) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, @intCast(value), .big);
    hash.update(&bytes);
}

fn fingerprintConfig(
    hash: *std.crypto.hash.sha2.Sha256,
    config: DoubleProgressionConfig,
) void {
    updateU64(hash, config.repRange.min);
    updateU64(hash, config.repRange.max);
    updateU64(hash, config.workingSets);
    updateU64(hash, config.advancementCriteria.minimumSuccessfulSets);
    updateU64(hash, config.advancementCriteria.minimumRepetitions);
    updateMeasurement(hash, config.initialLoad);
    updateMeasurement(hash, config.loadIncrement);
    hash.update(@tagName(config.failurePolicy.onPartial));
    hash.update("\x00");
    hash.update(@tagName(config.failurePolicy.onFailure));
    hash.update("\x00");
    updateMeasurement(hash, config.failurePolicy.regressionAmount);
    hash.update(@tagName(config.rounding.mode));
    hash.update("\x00");
    updateMeasurement(hash, config.rounding.quantum);
    for (config.exerciseOverrides) |override| {
        hash.update(override.exerciseId);
        hash.update("\x00");
        updatePresence(hash, override.repRange != null);
        if (override.repRange) |rep_range| {
            updateU64(hash, rep_range.min);
            updateU64(hash, rep_range.max);
        }
        updatePresence(hash, override.workingSets != null);
        if (override.workingSets) |working_sets| updateU64(hash, working_sets);
        updatePresence(hash, override.advancementCriteria != null);
        if (override.advancementCriteria) |advancement| {
            updateU64(hash, advancement.minimumSuccessfulSets);
            updateU64(hash, advancement.minimumRepetitions);
        }
        updatePresence(hash, override.initialLoad != null);
        if (override.initialLoad) |measurement| updateMeasurement(hash, measurement);
        updatePresence(hash, override.loadIncrement != null);
        if (override.loadIncrement) |measurement| updateMeasurement(hash, measurement);
        updatePresence(hash, override.failurePolicy != null);
        if (override.failurePolicy) |failure_policy| {
            hash.update(@tagName(failure_policy.onPartial));
            hash.update("\x00");
            hash.update(@tagName(failure_policy.onFailure));
            hash.update("\x00");
            updateMeasurement(hash, failure_policy.regressionAmount);
        }
        updatePresence(hash, override.rounding != null);
        if (override.rounding) |rounding| {
            hash.update(@tagName(rounding.mode));
            hash.update("\x00");
            updateMeasurement(hash, rounding.quantum);
        }
        hash.update("\xff");
    }
}

fn updatePresence(hash: *std.crypto.hash.sha2.Sha256, present: bool) void {
    hash.update(if (present) "\x01" else "\x00");
}

fn updateMeasurement(
    hash: *std.crypto.hash.sha2.Sha256,
    measurement: canonical.Measurement,
) void {
    hash.update(measurement.amount);
    hash.update("\x00");
    hash.update(measurement.unit);
    hash.update("\x00");
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

pub fn writeResultJson(
    result: canonical.RecommendationResult,
    out: []u8,
) std.Io.Writer.Error![]const u8 {
    var writer: std.Io.Writer = .fixed(out);
    try std.json.Stringify.value(
        result,
        .{ .emit_null_optional_fields = false },
        &writer,
    );
    return writer.buffered();
}

test "one exercise recommendation repeats identically" {
    const equipment = [_]primitives.Id{
        try .parse("dumbbell"),
        try .parse("adjustable-bench"),
    };
    const exercises = [_]training.Exercise{.{
        .id = try .parse("incline-dumbbell-press"),
        .equipment_ids = &equipment,
    }};
    const request = RecommendationRequest{
        .as_of = try .parse("2026-07-25T14:00:00Z"),
        .methodology_id = try .parse("caudex.double-progression"),
        .methodology_version = .{ .major = 0, .minor = 1, .patch = 0 },
        .config = testConfig(),
        .catalog = .{ .exercises = &exercises },
        .available_equipment_ids = &equipment,
    };
    var first_output: Output = .{};
    const first = try recommendSession(request, &first_output);
    var second_output: Output = .{};
    const second = try recommendSession(request, &second_output);

    var first_json: [2048]u8 = undefined;
    var second_json: [2048]u8 = undefined;
    try std.testing.expectEqualStrings(
        try writeResultJson(first, &first_json),
        try writeResultJson(second, &second_json),
    );
    try std.testing.expectEqual(@as(usize, 64), first.metadata.inputFingerprint.len);
    try std.testing.expectEqual(@as(usize, 64), first.metadata.resultFingerprint.len);
}

fn testConfig() DoubleProgressionConfig {
    return .{
        .repRange = .{ .min = 8, .max = 12 },
        .workingSets = 1,
        .advancementCriteria = .{
            .minimumSuccessfulSets = 1,
            .minimumRepetitions = 12,
        },
        .initialLoad = .{ .amount = "45", .unit = "lb" },
        .loadIncrement = .{ .amount = "5", .unit = "lb" },
        .failurePolicy = .{
            .onPartial = .hold,
            .onFailure = .regress,
            .regressionAmount = .{ .amount = "5", .unit = "lb" },
        },
        .rounding = .{
            .mode = .nearest,
            .quantum = .{ .amount = "2.5", .unit = "lb" },
        },
    };
}
