const std = @import("std");
const canonical = @import("canonical.zig");
const diagnostics = @import("diagnostics.zig");
const double_progression_contract = @import("double_progression.zig");
const methodology = @import("methodology.zig");
const primitives = @import("primitives.zig");
const training = @import("training.zig");

pub const engine_version = "0.1.0";
pub const schema_version: u32 = 1;
pub const max_recommended_exercises: usize = 16;

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
    max_working_sets: ?u16 = null,
};

pub const EvaluationRequest = struct {
    as_of: primitives.Timestamp,
    methodology_id: primitives.Id,
    methodology_version: methodology.Version,
    config: DoubleProgressionConfig,
    methodology_state: ?double_progression_contract.State = null,
    catalog: training.ExerciseCatalog,
    completed_workout: *const training.CompletedWorkout,
};

pub const EvaluationOutput = struct {
    state_exercises: [64]double_progression_contract.ExerciseState = undefined,
    exercise_evaluations: [64]double_progression_contract.ExerciseEvaluation = undefined,
    load_amounts: [2048]u8 = undefined,
    result: ?double_progression_contract.Evaluation = null,

    fn buffers(self: *EvaluationOutput) double_progression_contract.EvaluationBuffers {
        return .{
            .state_exercises = &self.state_exercises,
            .exercise_evaluations = &self.exercise_evaluations,
            .load_amounts = &self.load_amounts,
        };
    }
};

pub const RecommendError = error{
    UnsupportedMethodology,
    CatalogLimitReached,
    InvalidRequest,
    OutputLimitReached,
};

/// Caller-owned storage for the bounded CWE-015 recommendation result.
pub const Output = struct {
    metrics: [max_recommended_exercises * 64 * 2]canonical.Metric = undefined,
    sets: [max_recommended_exercises * 64]canonical.SetRecommendation = undefined,
    exercises: [max_recommended_exercises]canonical.ExerciseRecommendation = undefined,
    explanations: [max_recommended_exercises * 3]canonical.Explanation = undefined,
    warnings: [max_recommended_exercises]canonical.ValidationIssue = undefined,
    explanation_ids: [max_recommended_exercises][3][32]u8 = undefined,
    explanation_id_lens: [max_recommended_exercises][3]usize = @splat(@splat(0)),
    explanation_refs: [max_recommended_exercises][3][]const u8 = undefined,
    input_fingerprint: [64]u8 = undefined,
    result_fingerprint: [64]u8 = undefined,
    rep_amounts: [max_recommended_exercises][20]u8 = undefined,
    rep_amount_lens: [max_recommended_exercises]usize = @splat(0),
    load_amounts: [max_recommended_exercises][32]u8 = undefined,
    load_amount_lens: [max_recommended_exercises]usize = @splat(0),
    set_lens: [max_recommended_exercises]usize = @splat(0),
    exercise_len: usize = 0,
    explanation_len: usize = 0,
    warning_len: usize = 0,

    fn result(self: *Output, request: RecommendationRequest) canonical.RecommendationResult {
        return .{
            .ok = true,
            .recommendation = .{ .exercises = self.exercises[0..self.exercise_len] },
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
    exercise_index: usize,
};

const MethodologyEvaluationOutput = struct {
    request: *const EvaluationRequest,
    output: *EvaluationOutput,
};

const available_equipment_evidence = [_]canonical.EvidenceRef{
    .{ .path = "/session/availableEquipmentIds" },
};

fn validateDoubleProgressionConfig(
    view: methodology.ConfigView,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    const config: *const DoubleProgressionConfig = @ptrCast(@alignCast(view.context));
    try double_progression_contract.validateConfig(config.*, issues);
}

fn validateDoubleProgressionState(
    config_view: methodology.ConfigView,
    state_view: methodology.StateView,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    const config: *const DoubleProgressionConfig =
        @ptrCast(@alignCast(config_view.context));
    const state: *const double_progression_contract.State =
        @ptrCast(@alignCast(state_view.context));
    try double_progression_contract.validateState(config.*, state.*, issues);
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
    const exercise_index = destination.exercise_index;
    const exercise = &request.catalog.exercises[exercise_index];
    const prescription = double_progression_contract.recommendExerciseWithConstraints(
        request.config,
        request.methodology_state,
        request.history,
        exercise.id,
        .{ .max_working_sets = request.max_working_sets },
    ) catch return error.InvalidInput;
    const explanation_offset = destination.output.explanation_len;
    const explanation_count: usize = if (prescription.session_explanation != null) 3 else 2;
    for (0..explanation_count) |local_index| {
        const id = std.fmt.bufPrint(
            &destination.output.explanation_ids[exercise_index][local_index],
            "explanation-{d}",
            .{explanation_offset + local_index + 1},
        ) catch return error.OutputLimitReached;
        destination.output.explanation_id_lens[exercise_index][local_index] = id.len;
        destination.output.explanation_refs[exercise_index][local_index] = id;
    }
    const explanation_refs = destination.output.explanation_refs[exercise_index][0..explanation_count];

    destination.output.rep_amount_lens[exercise_index] = (std.fmt.bufPrint(
        &destination.output.rep_amounts[exercise_index],
        "{d}",
        .{prescription.repetitions},
    ) catch return error.OutputLimitReached).len;
    destination.output.load_amount_lens[exercise_index] = (prescription.load.value.format(
        &destination.output.load_amounts[exercise_index],
    ) catch return error.OutputLimitReached).len;
    destination.output.set_lens[exercise_index] = prescription.working_sets;
    const set_offset = exercise_index * 64;
    const metric_offset = exercise_index * 64 * 2;
    for (0..destination.output.set_lens[exercise_index]) |set_index| {
        const metric_index = metric_offset + set_index * 2;
        destination.output.metrics[metric_index] = .{
            .code = "load",
            .value = .{
                .amount = destination.output.load_amounts[exercise_index][0..destination.output.load_amount_lens[exercise_index]],
                .unit = prescription.load.unit.code(),
            },
        };
        destination.output.metrics[metric_index + 1] = .{
            .code = "repetitions",
            .value = .{
                .amount = destination.output.rep_amounts[exercise_index][0..destination.output.rep_amount_lens[exercise_index]],
                .unit = "count",
            },
        };
        destination.output.sets[set_offset + set_index] = .{
            .kind = "working",
            .targetMetrics = destination.output.metrics[metric_index .. metric_index + 2],
            .explanationRefs = explanation_refs,
        };
    }
    destination.output.exercises[exercise_index] = .{
        .exerciseId = exercise.id.bytes,
        .sets = destination.output.sets[set_offset .. set_offset + destination.output.set_lens[exercise_index]],
        .explanationRefs = explanation_refs,
    };
    destination.output.explanations[explanation_offset] = .{
        .id = explanation_refs[0],
        .code = "exercise.selected.available_equipment",
        .category = "selection",
        .summary = "Available equipment supported the exercise selection.",
        .subject = .{ .exerciseId = exercise.id.bytes },
        .evidence = &available_equipment_evidence,
        .ruleId = "double-progression.initial-working-set",
        .severity = .info,
    };
    destination.output.explanations[explanation_offset + 1] = .{
        .id = explanation_refs[1],
        .code = prescription.explanation.code,
        .category = "progression",
        .summary = prescription.explanation.summary,
        .subject = .{ .exerciseId = exercise.id.bytes },
        .evidence = &.{.{ .path = "/@derived/history/lastCompletedExercise" }},
        .ruleId = prescription.explanation.rule_id,
        .severity = .info,
    };
    destination.output.explanation_len = explanation_offset + 2;
    if (prescription.session_explanation) |session_explanation| {
        destination.output.explanations[explanation_offset + 2] = .{
            .id = explanation_refs[2],
            .code = session_explanation.code,
            .category = "session",
            .summary = session_explanation.summary,
            .subject = .{ .exerciseId = exercise.id.bytes },
            .evidence = &.{.{ .path = "/session/maxSets" }},
            .ruleId = session_explanation.rule_id,
            .severity = .warning,
        };
        destination.output.explanation_len = explanation_offset + 3;
    }
    if (prescription.warning) |warning| {
        destination.output.warnings[destination.output.warning_len] = warning;
        destination.output.warning_len += 1;
    }
}

fn evaluateDoubleProgression(
    view: methodology.EvaluationView,
    scratch: *methodology.Scratch,
    writer: *methodology.EvaluationWriter,
) methodology.MethodologyError!void {
    _ = scratch;
    const request: *const EvaluationRequest = @ptrCast(@alignCast(view.context));
    const destination: *MethodologyEvaluationOutput =
        @ptrCast(@alignCast(writer.context));
    destination.output.result = double_progression_contract.evaluatePerformance(
        request.config,
        request.methodology_state,
        request.completed_workout,
        destination.output.buffers(),
    ) catch |err| return switch (err) {
        error.OutputLimitReached => error.OutputLimitReached,
        else => error.InvalidInput,
    };
}

const double_progression = methodology.Methodology{
    .metadata = .{
        .id = .{ .bytes = "caudex.double-progression" },
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
        .config_version = 1,
        .state_schema_version = 1,
    },
    .validate_config = validateDoubleProgressionConfig,
    .validate_state = validateDoubleProgressionState,
    .recommend_session = recommendDoubleProgression,
    .evaluate_performance = evaluateDoubleProgression,
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
    if (request.catalog.exercises.len == 0 or
        request.catalog.exercises.len > max_recommended_exercises)
    {
        return error.CatalogLimitReached;
    }
    var issue_storage: [16]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&issue_storage);
    var training_issue_storage: [64]training.ValidationIssue = undefined;
    const training_issues = training.validate(
        request.catalog,
        request.history,
        &training_issue_storage,
    ) catch return error.OutputLimitReached;
    if (training_issues.len != 0) return error.InvalidRequest;
    for (request.history.workouts) |workout| {
        if (workout.completed_at.unixSeconds() > request.as_of.unixSeconds()) {
            return error.InvalidRequest;
        }
    }
    implementation.validate_config(
        .{ .context = &request.config },
        &issues,
    ) catch return error.OutputLimitReached;
    if (request.methodology_state) |state| {
        implementation.validate_state(
            .{ .context = &request.config },
            .{ .context = &state },
            &issues,
        ) catch return error.OutputLimitReached;
    }
    if (issues.items().len != 0) return error.InvalidRequest;
    for (request.catalog.exercises) |exercise| {
        if (!equipmentAvailable(
            exercise.equipment_ids,
            request.available_equipment_ids,
        )) return error.InvalidRequest;
    }

    output.explanation_len = 0;
    output.warning_len = 0;
    var scratch = methodology.Scratch{ .bytes = &.{} };
    output.exercise_len = request.catalog.exercises.len;
    for (0..output.exercise_len) |exercise_index| {
        var methodology_output = MethodologyOutput{
            .request = &request,
            .output = output,
            .exercise_index = exercise_index,
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
    }

    fingerprintRequest(request, &output.input_fingerprint);
    fingerprintResult(request, output, &output.result_fingerprint);
    return output.result(request);
}

/// Evaluates completed performance and returns a discardable state proposal.
pub fn evaluatePerformance(
    request: EvaluationRequest,
    output: *EvaluationOutput,
) RecommendError!double_progression_contract.Evaluation {
    const implementation = registry.find(
        request.methodology_id,
        request.methodology_version,
    ) orelse return error.UnsupportedMethodology;
    var training_issue_storage: [64]training.ValidationIssue = undefined;
    const workout_snapshot = [_]training.CompletedWorkout{request.completed_workout.*};
    const training_issues = training.validate(
        request.catalog,
        .{ .workouts = &workout_snapshot },
        &training_issue_storage,
    ) catch return error.OutputLimitReached;
    if (training_issues.len != 0) return error.InvalidRequest;
    if (request.completed_workout.completed_at.unixSeconds() > request.as_of.unixSeconds()) {
        return error.InvalidRequest;
    }
    var destination = MethodologyEvaluationOutput{
        .request = &request,
        .output = output,
    };
    var scratch = methodology.Scratch{ .bytes = &.{} };
    var writer = methodology.EvaluationWriter{ .context = &destination };
    implementation.evaluate_performance(
        .{ .context = &request },
        &scratch,
        &writer,
    ) catch |err| return switch (err) {
        error.InvalidInput => error.InvalidRequest,
        error.OutputLimitReached => error.OutputLimitReached,
    };
    return output.result orelse error.InvalidRequest;
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
    updatePresence(&hash, request.max_working_sets != null);
    if (request.max_working_sets) |limit| updateU64(&hash, limit);
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
    for (0..output.exercise_len) |exercise_index| {
        const metric_offset = exercise_index * 64 * 2;
        hash.update(output.exercises[exercise_index].exerciseId);
        hash.update("\x00working\x00load\x00");
        hash.update(output.load_amounts[exercise_index][0..output.load_amount_lens[exercise_index]]);
        hash.update("\x00");
        hash.update(output.metrics[metric_offset].value.unit);
        hash.update("\x00repetitions\x00");
        hash.update(output.rep_amounts[exercise_index][0..output.rep_amount_lens[exercise_index]]);
        updateU64(&hash, output.set_lens[exercise_index]);
        hash.update("\x00count\x00");
    }
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

test "recommendation rejects history references outside the supplied catalog" {
    const catalog = [_]training.Exercise{.{ .id = try .parse("squat") }};
    const history_exercise = [_]training.CompletedExercise{.{
        .exercise_id = try .parse("bench-press"),
        .sets = &.{},
    }};
    const history_workouts = [_]training.CompletedWorkout{.{
        .id = try .parse("workout-1"),
        .started_at = try .parse("2026-07-25T14:00:00Z"),
        .completed_at = try .parse("2026-07-25T14:30:00Z"),
        .exercises = &history_exercise,
    }};
    var output: Output = .{};
    try std.testing.expectError(
        error.InvalidRequest,
        recommendSession(
            .{
                .as_of = try .parse("2026-07-25T15:00:00Z"),
                .methodology_id = try .parse("caudex.double-progression"),
                .methodology_version = .{ .major = 0, .minor = 1, .patch = 0 },
                .config = testConfig(),
                .catalog = .{ .exercises = &catalog },
                .history = .{ .workouts = &history_workouts },
                .available_equipment_ids = &.{},
            },
            &output,
        ),
    );
}

test "recommendation supports a multi-exercise catalog" {
    const catalog = [_]training.Exercise{
        .{ .id = try .parse("squat") },
        .{ .id = try .parse("bench-press") },
    };
    var output: Output = .{};
    const result = try recommendSession(
        .{
            .as_of = try .parse("2026-07-25T15:00:00Z"),
            .methodology_id = try .parse("caudex.double-progression"),
            .methodology_version = .{ .major = 0, .minor = 1, .patch = 0 },
            .config = testConfig(),
            .catalog = .{ .exercises = &catalog },
            .history = .{},
            .available_equipment_ids = &.{},
        },
        &output,
    );
    try std.testing.expectEqual(@as(usize, 2), result.recommendation.?.exercises.len);
    try std.testing.expectEqualStrings("squat", result.recommendation.?.exercises[0].exerciseId);
    try std.testing.expectEqualStrings("bench-press", result.recommendation.?.exercises[1].exerciseId);
    try std.testing.expectEqual(@as(usize, 2), result.recommendation.?.exercises[1].explanationRefs.len);
    try std.testing.expectEqualStrings(
        "explanation-3",
        result.recommendation.?.exercises[1].explanationRefs[0],
    );
    try std.testing.expectEqual(@as(usize, 4), result.explanations.len);
    try std.testing.expectEqualStrings("bench-press", result.explanations[2].subject.?.exerciseId.?);
}

test "evaluation rejects duplicate catalog identifiers" {
    const duplicate_catalog = [_]training.Exercise{
        .{ .id = try .parse("squat") },
        .{ .id = try .parse("squat") },
    };
    const workout = training.CompletedWorkout{
        .id = try .parse("workout-1"),
        .started_at = try .parse("2026-07-25T14:00:00Z"),
        .completed_at = try .parse("2026-07-25T14:30:00Z"),
        .exercises = &.{},
    };
    var output: EvaluationOutput = .{};
    try std.testing.expectError(
        error.InvalidRequest,
        evaluatePerformance(
            .{
                .as_of = try .parse("2026-07-25T15:00:00Z"),
                .methodology_id = try .parse("caudex.double-progression"),
                .methodology_version = .{ .major = 0, .minor = 1, .patch = 0 },
                .config = testConfig(),
                .catalog = .{ .exercises = &duplicate_catalog },
                .completed_workout = &workout,
            },
            &output,
        ),
    );
}

test "recommendation rejects history completed after as-of" {
    const catalog = [_]training.Exercise{.{ .id = try .parse("squat") }};
    const future_workouts = [_]training.CompletedWorkout{.{
        .id = try .parse("future-workout"),
        .started_at = try .parse("2026-07-25T15:00:00Z"),
        .completed_at = try .parse("2026-07-25T16:00:00Z"),
        .exercises = &.{},
    }};
    var output: Output = .{};
    try std.testing.expectError(
        error.InvalidRequest,
        recommendSession(
            .{
                .as_of = try .parse("2026-07-25T15:00:00Z"),
                .methodology_id = try .parse("caudex.double-progression"),
                .methodology_version = .{ .major = 0, .minor = 1, .patch = 0 },
                .config = testConfig(),
                .catalog = .{ .exercises = &catalog },
                .history = .{ .workouts = &future_workouts },
                .available_equipment_ids = &.{},
            },
            &output,
        ),
    );
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

test "typed evaluation routes through registry and proposes state" {
    const load_id = try primitives.Id.parse("load");
    const repetitions_id = try primitives.Id.parse("repetitions");
    const working_id = try primitives.Id.parse("working");
    const actual_metrics = [_]training.Metric{
        .{
            .code = load_id,
            .value = .{ .value = try .parse("45"), .unit = .lb },
        },
        .{
            .code = repetitions_id,
            .value = .{ .value = try .parse("12"), .unit = .count },
        },
    };
    const target_metrics = [_]training.Metric{.{
        .code = repetitions_id,
        .value = .{ .value = try .parse("12"), .unit = .count },
    }};
    const sets = [_]training.CompletedSet{.{
        .kind = working_id,
        .actual_metrics = &actual_metrics,
        .target_metrics = &target_metrics,
        .status = .completed,
    }};
    const completed_exercises = [_]training.CompletedExercise{.{
        .exercise_id = try .parse("squat"),
        .sets = &sets,
    }};
    const workout = training.CompletedWorkout{
        .id = try .parse("workout-1"),
        .started_at = try .parse("2026-07-25T14:00:00Z"),
        .completed_at = try .parse("2026-07-25T14:30:00Z"),
        .exercises = &completed_exercises,
    };
    const catalog_exercises = [_]training.Exercise{.{
        .id = try .parse("squat"),
    }};
    const states = [_]double_progression_contract.ExerciseState{.{
        .exerciseId = "squat",
        .load = .{ .amount = "45", .unit = "lb" },
        .targetRepetitions = 12,
    }};
    var output: EvaluationOutput = .{};
    const evaluation = try evaluatePerformance(
        .{
            .as_of = try .parse("2026-07-25T15:00:00Z"),
            .methodology_id = try .parse("caudex.double-progression"),
            .methodology_version = .{ .major = 0, .minor = 1, .patch = 0 },
            .config = testConfig(),
            .methodology_state = .{
                .schemaVersion = 1,
                .data = .{ .exercises = &states },
            },
            .catalog = .{ .exercises = &catalog_exercises },
            .completed_workout = &workout,
        },
        &output,
    );

    try std.testing.expectEqualStrings("advanced", evaluation.outcome);
    try std.testing.expectEqualStrings(
        "50.0",
        evaluation.next_state.data.exercises[0].load.amount,
    );
    try std.testing.expectEqualStrings("45", states[0].load.amount);
}
