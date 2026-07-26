const std = @import("std");
const canonical = @import("canonical.zig");
const diagnostics = @import("diagnostics.zig");
const history_helpers = @import("history.zig");
const load_math = @import("load_math.zig");
const primitives = @import("primitives.zig");
const training = @import("training.zig");

pub const methodology_id = "caudex.double-progression";
pub const config_version: u32 = 1;
pub const state_schema_version: u32 = 1;

pub const RepRange = struct {
    min: u16,
    max: u16,
};

pub const AdvancementCriteria = struct {
    minimumSuccessfulSets: u16,
    minimumRepetitions: u16,
};

pub const FailureAction = enum {
    hold,
    regress,
};

pub const FailurePolicy = struct {
    onPartial: FailureAction,
    onFailure: FailureAction,
    regressionAmount: canonical.Measurement,
};

pub const RoundingMode = load_math.RoundingMode;
pub const Rounding = load_math.Rounding;

pub const ExerciseOverride = struct {
    exerciseId: []const u8,
    repRange: ?RepRange = null,
    workingSets: ?u16 = null,
    advancementCriteria: ?AdvancementCriteria = null,
    initialLoad: ?canonical.Measurement = null,
    loadIncrement: ?canonical.Measurement = null,
    failurePolicy: ?FailurePolicy = null,
    rounding: ?Rounding = null,
};

/// Version 1 JSON-boundary configuration for double progression.
pub const Config = struct {
    repRange: RepRange,
    workingSets: u16,
    advancementCriteria: AdvancementCriteria,
    initialLoad: canonical.Measurement,
    loadIncrement: canonical.Measurement,
    failurePolicy: FailurePolicy,
    rounding: Rounding,
    exerciseOverrides: []const ExerciseOverride = &.{},
};

pub const ExerciseState = struct {
    exerciseId: []const u8,
    load: canonical.Measurement,
    targetRepetitions: u16,
};

pub const StateData = struct {
    exercises: []const ExerciseState = &.{},
};

/// Versioned methodology state envelope returned as a proposal to the host.
pub const State = struct {
    schemaVersion: u32,
    data: StateData,
};

/// Collects every independently detectable configuration issue.
pub fn validateConfig(
    config: Config,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    try validateResolvedConfig(
        config.repRange,
        config.workingSets,
        config.advancementCriteria,
        config.initialLoad,
        config.loadIncrement,
        config.failurePolicy,
        config.rounding,
        "/methodology/config",
        issues,
    );

    for (config.exerciseOverrides, 0..) |override, override_index| {
        if (override.exerciseId.len == 0 or
            override.exerciseId.len > 200 or
            !std.unicode.utf8ValidateSlice(override.exerciseId))
        {
            try appendInvalid(
                issues,
                "/methodology/config/exerciseOverrides",
                "An exercise override has an invalid exercise ID.",
            );
        }
        for (config.exerciseOverrides[0..override_index]) |prior| {
            if (std.mem.eql(u8, prior.exerciseId, override.exerciseId)) {
                try appendInvalid(
                    issues,
                    "/methodology/config/exerciseOverrides",
                    "Exercise override IDs must be unique.",
                );
                break;
            }
        }

        try validateResolvedConfig(
            override.repRange orelse config.repRange,
            override.workingSets orelse config.workingSets,
            override.advancementCriteria orelse config.advancementCriteria,
            override.initialLoad orelse config.initialLoad,
            override.loadIncrement orelse config.loadIncrement,
            override.failurePolicy orelse config.failurePolicy,
            override.rounding orelse config.rounding,
            "/methodology/config/exerciseOverrides",
            issues,
        );
    }
}

/// Validates a decoded state against its schema version and resolved config.
pub fn validateState(
    config: Config,
    state: State,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    if (state.schemaVersion != state_schema_version) {
        try issues.append(.{
            .code = "methodology.state_unsupported_version",
            .path = "/methodologyState/schemaVersion",
            .message = "The double-progression state schema version is unsupported.",
            .severity = .@"error",
            .suggestion = "Provide double-progression state schema version 1.",
        });
    }
    for (state.data.exercises, 0..) |exercise, exercise_index| {
        for (state.data.exercises[0..exercise_index]) |prior| {
            if (std.mem.eql(u8, prior.exerciseId, exercise.exerciseId)) {
                try appendStateInvalid(
                    issues,
                    "Double-progression state exercise IDs must be unique.",
                );
                break;
            }
        }
        const resolved = resolvedForExercise(config, exercise.exerciseId);
        if (exercise.targetRepetitions < resolved.repRange.min or
            exercise.targetRepetitions > resolved.repRange.max)
        {
            try appendStateInvalid(
                issues,
                "A state target repetition value is outside its resolved rep range.",
            );
        }
        const load_value = primitives.Decimal.parse(exercise.load.amount) catch {
            try appendStateInvalid(
                issues,
                "A state load must be a non-negative mass measurement.",
            );
            continue;
        };
        const load_unit = primitives.Unit.parse(exercise.load.unit) catch {
            try appendStateInvalid(
                issues,
                "A state load must be a non-negative mass measurement.",
            );
            continue;
        };
        if (load_value.mantissa < 0 or load_unit.dimension() != .mass) {
            try appendStateInvalid(
                issues,
                "A state load must be a non-negative mass measurement.",
            );
        }
    }
}

pub const ResolvedConfig = struct {
    repRange: RepRange,
    workingSets: u16,
    advancementCriteria: AdvancementCriteria,
    initialLoad: canonical.Measurement,
    loadIncrement: canonical.Measurement,
    failurePolicy: FailurePolicy,
    rounding: Rounding,
};

pub fn resolvedForExercise(config: Config, exercise_id: []const u8) ResolvedConfig {
    for (config.exerciseOverrides) |override| {
        if (!std.mem.eql(u8, override.exerciseId, exercise_id)) continue;
        return .{
            .repRange = override.repRange orelse config.repRange,
            .workingSets = override.workingSets orelse config.workingSets,
            .advancementCriteria = override.advancementCriteria orelse
                config.advancementCriteria,
            .initialLoad = override.initialLoad orelse config.initialLoad,
            .loadIncrement = override.loadIncrement orelse config.loadIncrement,
            .failurePolicy = override.failurePolicy orelse config.failurePolicy,
            .rounding = override.rounding orelse config.rounding,
        };
    }
    return .{
        .repRange = config.repRange,
        .workingSets = config.workingSets,
        .advancementCriteria = config.advancementCriteria,
        .initialLoad = config.initialLoad,
        .loadIncrement = config.loadIncrement,
        .failurePolicy = config.failurePolicy,
        .rounding = config.rounding,
    };
}

pub const RecommendationDecision = enum {
    initial,
    state_without_history,
    repetitions_advanced,
    load_advanced,
    partial_held,
    partial_regressed,
    failure_held,
    failure_regressed,
    insufficient_sets_held,
};

pub const DecisionExplanation = struct {
    code: []const u8,
    summary: []const u8,
    rule_id: []const u8,
};

pub const Recommendation = struct {
    load: primitives.Measurement,
    repetitions: u16,
    working_sets: u16,
    decision: RecommendationDecision,
    explanation: DecisionExplanation,
    session_explanation: ?DecisionExplanation = null,
    warning: ?canonical.ValidationIssue = null,
};

pub const RecommendationError = error{
    InvalidConfig,
    InvalidHistory,
    IncompatibleUnit,
    Overflow,
};

pub const RecommendationConstraints = struct {
    max_working_sets: ?u16 = null,
};

pub const ExerciseEvaluation = struct {
    exercise_id: []const u8,
    outcome: []const u8,
    explanation: DecisionExplanation,
    warning: ?canonical.ValidationIssue = null,
};

pub const EvaluationBuffers = struct {
    state_exercises: []ExerciseState,
    exercise_evaluations: []ExerciseEvaluation,
    load_amounts: []u8,
};

pub const Evaluation = struct {
    outcome: []const u8,
    exercises: []const ExerciseEvaluation,
    next_state: State,
};

pub const EvaluationError = RecommendationError || error{
    DuplicateExercise,
    OutputLimitReached,
};

/// Evaluates a completed workout and returns a versioned proposed next state.
///
/// The supplied state and completed workout are borrowed and never mutated.
/// The host may discard the returned proposal without any side effects.
pub fn evaluatePerformance(
    config: Config,
    current_state: ?State,
    completed_workout: *const training.CompletedWorkout,
    buffers: EvaluationBuffers,
) EvaluationError!Evaluation {
    var validation_storage: [64]canonical.ValidationIssue = undefined;
    var validation_issues: diagnostics.IssueWriter = .init(&validation_storage);
    validateConfig(config, &validation_issues) catch return error.InvalidConfig;
    if (current_state) |state| {
        validateState(config, state, &validation_issues) catch
            return error.InvalidConfig;
    }
    if (validation_issues.items().len != 0) return error.InvalidConfig;

    if (current_state) |state| {
        if (state.data.exercises.len > buffers.state_exercises.len) {
            return error.OutputLimitReached;
        }
        @memcpy(
            buffers.state_exercises[0..state.data.exercises.len],
            state.data.exercises,
        );
    }
    var state_len: usize = if (current_state) |state|
        state.data.exercises.len
    else
        0;
    var evaluation_len: usize = 0;
    var load_amount_len: usize = 0;
    var any_advanced = false;
    var any_regressed = false;
    var any_held = false;

    const workout_snapshot = [_]training.CompletedWorkout{completed_workout.*};
    const history = training.HistorySnapshot{ .workouts = &workout_snapshot };
    for (completed_workout.exercises, 0..) |*completed_exercise, exercise_index| {
        for (completed_workout.exercises[0..exercise_index]) |prior| {
            if (prior.exercise_id.eql(completed_exercise.exercise_id)) {
                return error.DuplicateExercise;
            }
        }
        if (evaluation_len == buffers.exercise_evaluations.len) {
            return error.OutputLimitReached;
        }
        const recommendation = try recommendExercise(
            config,
            current_state,
            history,
            completed_exercise.exercise_id,
        );
        const outcome = outcomeFor(recommendation.decision);
        buffers.exercise_evaluations[evaluation_len] = .{
            .exercise_id = completed_exercise.exercise_id.bytes,
            .outcome = outcome,
            .explanation = recommendation.explanation,
            .warning = recommendation.warning,
        };
        evaluation_len += 1;
        if (std.mem.eql(u8, outcome, "advanced")) {
            any_advanced = true;
        } else if (std.mem.eql(u8, outcome, "regressed")) {
            any_regressed = true;
        } else {
            any_held = true;
        }

        const amount = recommendation.load.value.format(
            buffers.load_amounts[load_amount_len..],
        ) catch return error.OutputLimitReached;
        load_amount_len += amount.len;
        const proposed = ExerciseState{
            .exerciseId = completed_exercise.exercise_id.bytes,
            .load = .{
                .amount = amount,
                .unit = recommendation.load.unit.code(),
            },
            .targetRepetitions = recommendation.repetitions,
        };
        if (findStateIndex(buffers.state_exercises[0..state_len], completed_exercise.exercise_id)) |index| {
            buffers.state_exercises[index] = proposed;
        } else {
            if (state_len == buffers.state_exercises.len) {
                return error.OutputLimitReached;
            }
            buffers.state_exercises[state_len] = proposed;
            state_len += 1;
        }
    }

    return .{
        .outcome = if (any_regressed)
            "regressed"
        else if (any_held)
            "held"
        else if (any_advanced)
            "advanced"
        else
            "no_completed_exercises",
        .exercises = buffers.exercise_evaluations[0..evaluation_len],
        .next_state = .{
            .schemaVersion = state_schema_version,
            .data = .{ .exercises = buffers.state_exercises[0..state_len] },
        },
    };
}

fn outcomeFor(decision: RecommendationDecision) []const u8 {
    return switch (decision) {
        .repetitions_advanced, .load_advanced => "advanced",
        .partial_regressed, .failure_regressed => "regressed",
        .initial, .state_without_history => "insufficient_evidence",
        .partial_held,
        .failure_held,
        .insufficient_sets_held,
        => "held",
    };
}

fn findStateIndex(states: []const ExerciseState, exercise_id: primitives.Id) ?usize {
    for (states, 0..) |state, index| {
        if (std.mem.eql(u8, state.exerciseId, exercise_id.bytes)) return index;
    }
    return null;
}

/// Recommends one exercise from explicit config, state, and history snapshots.
///
/// This function proposes no next state and performs no evaluation-side
/// persistence; those concerns remain in CWE-032.
pub fn recommendExercise(
    config: Config,
    state: ?State,
    history: training.HistorySnapshot,
    exercise_id: primitives.Id,
) RecommendationError!Recommendation {
    return recommendExerciseWithConstraints(
        config,
        state,
        history,
        exercise_id,
        .{},
    );
}

pub fn recommendExerciseWithConstraints(
    config: Config,
    state: ?State,
    history: training.HistorySnapshot,
    exercise_id: primitives.Id,
    constraints: RecommendationConstraints,
) RecommendationError!Recommendation {
    var recommendation = try recommendExerciseUnconstrained(
        config,
        state,
        history,
        exercise_id,
    );
    if (constraints.max_working_sets) |limit| {
        if (limit == 0) return error.InvalidConfig;
        if (limit < recommendation.working_sets) {
            recommendation.working_sets = limit;
            recommendation.session_explanation = .{
                .code = "sets.reduced.available_time",
                .summary = "The explicit session limit reduced prescribed working sets.",
                .rule_id = "double-progression.short-session-set-cap",
            };
        }
    }
    return recommendation;
}

fn recommendExerciseUnconstrained(
    config: Config,
    state: ?State,
    history: training.HistorySnapshot,
    exercise_id: primitives.Id,
) RecommendationError!Recommendation {
    var validation_storage: [64]canonical.ValidationIssue = undefined;
    var validation_issues: diagnostics.IssueWriter = .init(&validation_storage);
    validateConfig(config, &validation_issues) catch return error.InvalidConfig;
    if (state) |value| {
        validateState(config, value, &validation_issues) catch
            return error.InvalidConfig;
    }
    if (validation_issues.items().len != 0) return error.InvalidConfig;

    const resolved = resolvedForExercise(config, exercise_id.bytes);
    const initial_load = parseBoundaryMeasurement(resolved.initialLoad) catch
        return error.InvalidConfig;
    const state_entry = if (state) |value|
        findState(value, exercise_id)
    else
        null;
    const state_load: ?primitives.Measurement = if (state_entry) |entry|
        parseBoundaryMeasurement(entry.load) catch return error.InvalidConfig
    else
        null;
    const performance = history_helpers.lastCompletedExercise(history, exercise_id);
    const prior = if (performance) |value|
        try analyzePerformance(value.exercise, state_entry, state_load, resolved)
    else
        null;

    if (prior == null) {
        const load = try roundLoad(
            state_load orelse initial_load,
            resolved.rounding,
        );
        return .{
            .load = load,
            .repetitions = if (state_entry) |entry|
                entry.targetRepetitions
            else
                resolved.repRange.min,
            .working_sets = resolved.workingSets,
            .decision = if (state_entry == null) .initial else .state_without_history,
            .explanation = if (state_entry == null)
                explanationFor(.initial)
            else
                explanationFor(.state_without_history),
            .warning = insufficientHistoryWarning(),
        };
    }

    const evidence = prior.?;
    if (evidence.successful_sets >= resolved.advancementCriteria.minimumSuccessfulSets) {
        if (evidence.target_repetitions >=
            resolved.advancementCriteria.minimumRepetitions)
        {
            const increment = parseBoundaryMeasurement(resolved.loadIncrement) catch
                return error.InvalidConfig;
            if (increment.unit != evidence.load.unit) return error.IncompatibleUnit;
            const advanced = primitives.Decimal.add(
                evidence.load.value,
                increment.value,
            ) catch return error.Overflow;
            return recommendationWith(
                try roundLoad(
                    .{ .value = advanced, .unit = evidence.load.unit },
                    resolved.rounding,
                ),
                resolved.repRange.min,
                resolved.workingSets,
                .load_advanced,
            );
        }
        return recommendationWith(
            evidence.load,
            @min(
                evidence.target_repetitions + 1,
                resolved.advancementCriteria.minimumRepetitions,
            ),
            resolved.workingSets,
            .repetitions_advanced,
        );
    }

    if (evidence.had_partial) {
        return applyFailureAction(
            evidence.load,
            evidence.target_repetitions,
            resolved,
            resolved.failurePolicy.onPartial,
            .partial_held,
            .partial_regressed,
        );
    }
    if (evidence.had_failure) {
        return applyFailureAction(
            evidence.load,
            evidence.target_repetitions,
            resolved,
            resolved.failurePolicy.onFailure,
            .failure_held,
            .failure_regressed,
        );
    }
    return recommendationWith(
        evidence.load,
        evidence.target_repetitions,
        resolved.workingSets,
        .insufficient_sets_held,
    );
}

const PriorPerformance = struct {
    load: primitives.Measurement,
    target_repetitions: u16,
    successful_sets: u16,
    had_partial: bool,
    had_failure: bool,
};

fn analyzePerformance(
    completed_exercise: *const training.CompletedExercise,
    state_entry: ?*const ExerciseState,
    state_load: ?primitives.Measurement,
    resolved: ResolvedConfig,
) RecommendationError!?PriorPerformance {
    var load = state_load;
    var inferred_target: ?u16 = if (state_entry) |entry|
        entry.targetRepetitions
    else
        null;
    var max_actual_repetitions: u16 = 0;
    var successful_sets: u16 = 0;
    var had_partial = false;
    var had_failure = false;
    var working_set_count: usize = 0;

    for (completed_exercise.sets) |set| {
        if (!std.mem.eql(u8, set.kind.bytes, "working")) continue;
        working_set_count += 1;
        switch (set.status) {
            .partial => {
                had_partial = true;
                continue;
            },
            .failed, .skipped => {
                had_failure = true;
                continue;
            },
            .completed => {},
        }
        const set_load = try metricMeasurement(set.actual_metrics, "load");
        const set_repetitions = try metricRepetitions(set.actual_metrics);
        if (load) |known| {
            if (known.unit != set_load.unit) return error.IncompatibleUnit;
        } else {
            load = set_load;
        }
        if (set_load.unit != load.?.unit or
            !decimalEqual(set_load.value, load.?.value))
        {
            return error.InvalidHistory;
        }
        max_actual_repetitions = @max(max_actual_repetitions, set_repetitions);
        if (inferred_target == null) {
            inferred_target = targetRepetitions(set.target_metrics);
        }
    }
    if (working_set_count == 0 or load == null) return null;
    const target = inferred_target orelse std.math.clamp(
        max_actual_repetitions,
        resolved.repRange.min,
        resolved.advancementCriteria.minimumRepetitions,
    );

    for (completed_exercise.sets) |set| {
        if (!std.mem.eql(u8, set.kind.bytes, "working") or
            set.status != .completed)
        {
            continue;
        }
        const repetitions = try metricRepetitions(set.actual_metrics);
        if (repetitions >= target) {
            successful_sets = std.math.add(
                u16,
                successful_sets,
                1,
            ) catch return error.Overflow;
        } else {
            had_failure = true;
        }
    }
    return .{
        .load = load.?,
        .target_repetitions = target,
        .successful_sets = successful_sets,
        .had_partial = had_partial,
        .had_failure = had_failure,
    };
}

fn applyFailureAction(
    load: primitives.Measurement,
    repetitions: u16,
    resolved: ResolvedConfig,
    action: FailureAction,
    hold_decision: RecommendationDecision,
    regress_decision: RecommendationDecision,
) RecommendationError!Recommendation {
    if (action == .hold) {
        return recommendationWith(
            load,
            repetitions,
            resolved.workingSets,
            hold_decision,
        );
    }
    const regression = parseBoundaryMeasurement(
        resolved.failurePolicy.regressionAmount,
    ) catch return error.InvalidConfig;
    if (regression.unit != load.unit) return error.IncompatibleUnit;
    const regressed = if (decimalGreaterThan(regression.value, load.value))
        primitives.Decimal{ .mantissa = 0, .scale = 0 }
    else
        primitives.Decimal.subtract(load.value, regression.value) catch
            return error.Overflow;
    return recommendationWith(
        try roundLoad(.{ .value = regressed, .unit = load.unit }, resolved.rounding),
        resolved.repRange.min,
        resolved.workingSets,
        regress_decision,
    );
}

fn recommendationWith(
    load: primitives.Measurement,
    repetitions: u16,
    working_sets: u16,
    decision: RecommendationDecision,
) Recommendation {
    return .{
        .load = load,
        .repetitions = repetitions,
        .working_sets = working_sets,
        .decision = decision,
        .explanation = explanationFor(decision),
    };
}

fn explanationFor(decision: RecommendationDecision) DecisionExplanation {
    return switch (decision) {
        .initial => .{
            .code = "double_progression.prescribed.initial",
            .summary = "The configured initial load and bottom of the rep range were prescribed.",
            .rule_id = "double-progression.initial-prescription",
        },
        .state_without_history => .{
            .code = "double_progression.prescribed.state_without_history",
            .summary = "Methodology state was prescribed without completed-history evidence.",
            .rule_id = "double-progression.state-prescription",
        },
        .repetitions_advanced => .{
            .code = "repetitions.increased.completed_target",
            .summary = "Completed target sets advanced the repetition prescription.",
            .rule_id = "double-progression.advance-repetitions",
        },
        .load_advanced => .{
            .code = "load.increased.rep_range_completed",
            .summary = "Completed advancement criteria increased load and reset repetitions.",
            .rule_id = "double-progression.advance-load",
        },
        .partial_held => .{
            .code = "load.held.partial_completion",
            .summary = "Partial completion held load and repetitions.",
            .rule_id = "double-progression.partial-hold",
        },
        .partial_regressed => .{
            .code = "load.regressed.partial_completion",
            .summary = "Partial completion applied the configured regression.",
            .rule_id = "double-progression.partial-regress",
        },
        .failure_held => .{
            .code = "load.held.failed_completion",
            .summary = "Failed completion held load and repetitions.",
            .rule_id = "double-progression.failure-hold",
        },
        .failure_regressed => .{
            .code = "load.regressed.failed_completion",
            .summary = "Failed completion applied the configured regression.",
            .rule_id = "double-progression.failure-regress",
        },
        .insufficient_sets_held => .{
            .code = "load.held.insufficient_successful_sets",
            .summary = "Too few successful sets were supplied to advance.",
            .rule_id = "double-progression.insufficient-sets-hold",
        },
    };
}

fn insufficientHistoryWarning() canonical.ValidationIssue {
    return .{
        .code = "history.insufficient_evidence",
        .path = "/history",
        .message = "No completed performance was available for this exercise.",
        .severity = .warning,
        .suggestion = "Treat the prescription as an initial or state-based assumption.",
    };
}

fn findState(state: State, exercise_id: primitives.Id) ?*const ExerciseState {
    for (state.data.exercises) |*exercise| {
        if (std.mem.eql(u8, exercise.exerciseId, exercise_id.bytes)) return exercise;
    }
    return null;
}

fn metricMeasurement(
    metrics: []const training.Metric,
    code: []const u8,
) RecommendationError!primitives.Measurement {
    for (metrics) |metric| {
        if (std.mem.eql(u8, metric.code.bytes, code)) return metric.value;
    }
    return error.InvalidHistory;
}

fn metricRepetitions(metrics: []const training.Metric) RecommendationError!u16 {
    const measurement = try metricMeasurement(metrics, "repetitions");
    if (measurement.unit != .count or
        measurement.value.scale != 0 or
        measurement.value.mantissa < 0 or
        measurement.value.mantissa > std.math.maxInt(u16))
    {
        return error.InvalidHistory;
    }
    return @intCast(measurement.value.mantissa);
}

fn targetRepetitions(metrics: []const training.Metric) ?u16 {
    return metricRepetitions(metrics) catch null;
}

fn parseBoundaryMeasurement(
    measurement: canonical.Measurement,
) !primitives.Measurement {
    return load_math.parseMeasurement(measurement);
}

fn roundLoad(
    load: primitives.Measurement,
    rounding: Rounding,
) RecommendationError!primitives.Measurement {
    return load_math.roundLoad(load, rounding);
}

fn scaledMantissa(value: primitives.Decimal, scale: u8) RecommendationError!i128 {
    var result: i128 = value.mantissa;
    var remaining = scale - value.scale;
    while (remaining > 0) : (remaining -= 1) {
        const next, const overflow = @mulWithOverflow(result, 10);
        if (overflow != 0) return error.Overflow;
        result = next;
    }
    return result;
}

fn decimalEqual(left: primitives.Decimal, right: primitives.Decimal) bool {
    const scale = @max(left.scale, right.scale);
    const left_value = scaledMantissa(left, scale) catch return false;
    const right_value = scaledMantissa(right, scale) catch return false;
    return left_value == right_value;
}

fn decimalGreaterThan(left: primitives.Decimal, right: primitives.Decimal) bool {
    const scale = @max(left.scale, right.scale);
    const left_value = scaledMantissa(left, scale) catch return false;
    const right_value = scaledMantissa(right, scale) catch return false;
    return left_value > right_value;
}

pub fn writeStateJson(
    state: State,
    out: []u8,
) std.Io.Writer.Error![]const u8 {
    var writer: std.Io.Writer = .fixed(out);
    try std.json.Stringify.value(
        state,
        .{ .emit_null_optional_fields = false },
        &writer,
    );
    return writer.buffered();
}

fn validateResolvedConfig(
    rep_range: RepRange,
    working_sets: u16,
    advancement: AdvancementCriteria,
    initial_load: canonical.Measurement,
    load_increment: canonical.Measurement,
    failure_policy: FailurePolicy,
    rounding: Rounding,
    path: []const u8,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    if (rep_range.min == 0 or rep_range.min > rep_range.max) {
        try appendInvalid(issues, path, "The repetition range must be positive and ordered.");
    }
    if (working_sets == 0 or working_sets > 64) {
        try appendInvalid(issues, path, "Working sets must be between 1 and 64.");
    }
    if (advancement.minimumSuccessfulSets == 0 or
        advancement.minimumSuccessfulSets > working_sets or
        advancement.minimumRepetitions < rep_range.min or
        advancement.minimumRepetitions > rep_range.max)
    {
        try appendInvalid(
            issues,
            path,
            "Advancement criteria must fit the configured sets and repetition range.",
        );
    }

    const initial = parseNonNegativeMeasurement(initial_load) catch {
        try appendInvalid(issues, path, "Initial load must be a non-negative mass measurement.");
        return;
    };
    const increment = parsePositiveMeasurement(load_increment) catch {
        try appendInvalid(issues, path, "Load increment must be a positive mass measurement.");
        return;
    };
    const regression = parsePositiveMeasurement(failure_policy.regressionAmount) catch {
        try appendInvalid(issues, path, "Regression amount must be a positive mass measurement.");
        return;
    };
    const quantum = parsePositiveMeasurement(rounding.quantum) catch {
        try appendInvalid(issues, path, "Rounding quantum must be a positive mass measurement.");
        return;
    };
    if (initial.unit.dimension() != .mass or
        increment.unit.dimension() != .mass or
        regression.unit.dimension() != .mass or
        quantum.unit.dimension() != .mass)
    {
        try appendInvalid(issues, path, "Load values must use mass units.");
    }
    if (initial.unit != increment.unit or
        increment.unit != regression.unit or
        increment.unit != quantum.unit)
    {
        try appendInvalid(
            issues,
            path,
            "Load increment, regression amount, and rounding quantum must use one unit.",
        );
    }
}

fn parsePositiveMeasurement(
    measurement: canonical.Measurement,
) !primitives.Measurement {
    const value = try primitives.Decimal.parse(measurement.amount);
    if (value.mantissa <= 0) return error.NonPositive;
    return .{
        .value = value,
        .unit = try primitives.Unit.parse(measurement.unit),
    };
}

fn parseNonNegativeMeasurement(
    measurement: canonical.Measurement,
) !primitives.Measurement {
    const value = try primitives.Decimal.parse(measurement.amount);
    if (value.mantissa < 0) return error.Negative;
    return .{
        .value = value,
        .unit = try primitives.Unit.parse(measurement.unit),
    };
}

fn appendInvalid(
    issues: *diagnostics.IssueWriter,
    path: []const u8,
    message: []const u8,
) diagnostics.IssueWriter.AppendError!void {
    try issues.append(.{
        .code = "methodology.config_invalid",
        .path = path,
        .message = message,
        .severity = .@"error",
        .suggestion = "Correct the double-progression configuration.",
    });
}

fn appendStateInvalid(
    issues: *diagnostics.IssueWriter,
    message: []const u8,
) diagnostics.IssueWriter.AppendError!void {
    try issues.append(.{
        .code = "methodology.state_invalid",
        .path = "/methodologyState/data/exercises",
        .message = message,
        .severity = .@"error",
        .suggestion = "Rebuild the state from valid accepted methodology output.",
    });
}

fn validConfig(overrides: []const ExerciseOverride) Config {
    return .{
        .repRange = .{ .min = 8, .max = 12 },
        .workingSets = 3,
        .advancementCriteria = .{
            .minimumSuccessfulSets = 3,
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
        .exerciseOverrides = overrides,
    };
}

test "valid config and state collect no issues" {
    const overrides = [_]ExerciseOverride{.{
        .exerciseId = "squat",
        .workingSets = 4,
        .advancementCriteria = .{
            .minimumSuccessfulSets = 4,
            .minimumRepetitions = 12,
        },
    }};
    const config = validConfig(&overrides);
    var issue_storage: [8]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&issue_storage);
    try validateConfig(config, &issues);
    try std.testing.expectEqual(@as(usize, 0), issues.items().len);

    const states = [_]ExerciseState{.{
        .exerciseId = "squat",
        .load = .{ .amount = "225", .unit = "lb" },
        .targetRepetitions = 10,
    }};
    try validateState(
        config,
        .{ .schemaVersion = 1, .data = .{ .exercises = &states } },
        &issues,
    );
    try std.testing.expectEqual(@as(usize, 0), issues.items().len);
}

test "config validation collects independent failures" {
    var config = validConfig(&.{});
    config.repRange = .{ .min = 12, .max = 8 };
    config.workingSets = 0;
    config.loadIncrement = .{ .amount = "0", .unit = "lb" };
    var issue_storage: [8]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&issue_storage);
    try validateConfig(config, &issues);
    try std.testing.expect(issues.items().len >= 3);
    for (issues.items()) |issue| {
        try std.testing.expectEqualStrings("methodology.config_invalid", issue.code);
    }
}

test "exercise overrides resolve deterministically and reject duplicates" {
    const overrides = [_]ExerciseOverride{
        .{ .exerciseId = "squat", .repRange = .{ .min = 5, .max = 8 } },
        .{ .exerciseId = "squat" },
    };
    const config = validConfig(&overrides);
    const resolved = resolvedForExercise(config, "squat");
    try std.testing.expectEqual(@as(u16, 5), resolved.repRange.min);

    var issue_storage: [8]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&issue_storage);
    try validateConfig(config, &issues);
    try std.testing.expect(issues.items().len > 0);
}

const TestPerformance = struct {
    metrics: [6]training.Metric,
    target_metric: [1]training.Metric,
    sets: [3]training.CompletedSet,
    exercise: [1]training.CompletedExercise,
    workout: [1]training.CompletedWorkout,

    fn init(
        self: *TestPerformance,
        status: training.SetStatus,
        load: i64,
        repetitions: u16,
        target_repetitions: u16,
        load_unit: primitives.Unit,
    ) !void {
        const load_id = try primitives.Id.parse("load");
        const repetitions_id = try primitives.Id.parse("repetitions");
        const working_id = try primitives.Id.parse("working");
        self.metrics = undefined;
        for (0..3) |index| {
            self.metrics[index * 2] = testTrainingMetric(load_id, load, load_unit);
            self.metrics[index * 2 + 1] = testTrainingMetric(
                repetitions_id,
                target_repetitions,
                .count,
            );
            self.metrics[index * 2 + 1].value.value.mantissa = repetitions;
        }
        self.target_metric = .{
            testTrainingMetric(repetitions_id, target_repetitions, .count),
        };
        self.sets = .{
            .{
                .kind = working_id,
                .actual_metrics = self.metrics[0..2],
                .target_metrics = &self.target_metric,
                .status = status,
            },
            .{
                .kind = working_id,
                .actual_metrics = self.metrics[2..4],
                .target_metrics = &self.target_metric,
                .status = status,
            },
            .{
                .kind = working_id,
                .actual_metrics = self.metrics[4..6],
                .target_metrics = &self.target_metric,
                .status = status,
            },
        };
        self.exercise = .{.{
            .exercise_id = try primitives.Id.parse("squat"),
            .sets = &self.sets,
        }};
        self.workout = .{.{
            .id = try primitives.Id.parse("workout-1"),
            .started_at = try primitives.Timestamp.parse("2026-07-24T10:00:00Z"),
            .completed_at = try primitives.Timestamp.parse("2026-07-24T11:00:00Z"),
            .exercises = &self.exercise,
        }};
    }

    fn history(self: *const TestPerformance) training.HistorySnapshot {
        return .{ .workouts = &self.workout };
    }
};

fn testTrainingMetric(
    code: primitives.Id,
    value: i64,
    unit: primitives.Unit,
) training.Metric {
    return .{
        .code = code,
        .value = .{
            .value = .{ .mantissa = value, .scale = 0 },
            .unit = unit,
        },
    };
}

test "initial prescription is explicit and warns about missing history" {
    const recommendation = try recommendExercise(
        validConfig(&.{}),
        null,
        .{},
        try .parse("squat"),
    );
    try std.testing.expectEqual(.initial, recommendation.decision);
    try std.testing.expectEqual(
        primitives.Decimal{ .mantissa = 450, .scale = 1 },
        recommendation.load.value,
    );
    try std.testing.expectEqual(@as(u16, 8), recommendation.repetitions);
    try std.testing.expectEqualStrings(
        "double_progression.prescribed.initial",
        recommendation.explanation.code,
    );
    try std.testing.expectEqualStrings(
        "history.insufficient_evidence",
        recommendation.warning.?.code,
    );
}

test "successful sets advance repetitions then load" {
    var performance: TestPerformance = undefined;
    try performance.init(.completed, 45, 10, 10, .lb);
    const states = [_]ExerciseState{.{
        .exerciseId = "squat",
        .load = .{ .amount = "45", .unit = "lb" },
        .targetRepetitions = 10,
    }};
    const state = State{ .schemaVersion = 1, .data = .{ .exercises = &states } };
    const repetitions = try recommendExercise(
        validConfig(&.{}),
        state,
        performance.history(),
        try .parse("squat"),
    );
    try std.testing.expectEqual(.repetitions_advanced, repetitions.decision);
    try std.testing.expectEqual(@as(u16, 11), repetitions.repetitions);
    try std.testing.expectEqualStrings(
        "repetitions.increased.completed_target",
        repetitions.explanation.code,
    );

    try performance.init(.completed, 45, 12, 12, .lb);
    const top_states = [_]ExerciseState{.{
        .exerciseId = "squat",
        .load = .{ .amount = "45", .unit = "lb" },
        .targetRepetitions = 12,
    }};
    const advanced = try recommendExercise(
        validConfig(&.{}),
        .{ .schemaVersion = 1, .data = .{ .exercises = &top_states } },
        performance.history(),
        try .parse("squat"),
    );
    try std.testing.expectEqual(.load_advanced, advanced.decision);
    try std.testing.expectEqual(
        primitives.Decimal{ .mantissa = 500, .scale = 1 },
        advanced.load.value,
    );
    try std.testing.expectEqual(@as(u16, 8), advanced.repetitions);
}

test "partial performance follows hold or regress policy" {
    var performance: TestPerformance = undefined;
    try performance.init(.partial, 47, 9, 9, .lb);
    const states = [_]ExerciseState{.{
        .exerciseId = "squat",
        .load = .{ .amount = "47", .unit = "lb" },
        .targetRepetitions = 9,
    }};
    const state = State{ .schemaVersion = 1, .data = .{ .exercises = &states } };
    const held = try recommendExercise(
        validConfig(&.{}),
        state,
        performance.history(),
        try .parse("squat"),
    );
    try std.testing.expectEqual(.partial_held, held.decision);
    try std.testing.expectEqual(
        primitives.Decimal{ .mantissa = 47, .scale = 0 },
        held.load.value,
    );

    var regress_config = validConfig(&.{});
    regress_config.failurePolicy.onPartial = .regress;
    const regressed = try recommendExercise(
        regress_config,
        state,
        performance.history(),
        try .parse("squat"),
    );
    try std.testing.expectEqual(.partial_regressed, regressed.decision);
    try std.testing.expectEqual(
        primitives.Decimal{ .mantissa = 425, .scale = 1 },
        regressed.load.value,
    );
    try std.testing.expectEqual(@as(u16, 8), regressed.repetitions);
}

test "rounding modes are exact and incompatible units fail" {
    const load = primitives.Measurement{
        .value = try .parse("52"),
        .unit = .lb,
    };
    try std.testing.expectEqual(
        primitives.Decimal{ .mantissa = 50, .scale = 0 },
        (try roundLoad(
            load,
            .{ .mode = .nearest, .quantum = .{ .amount = "5", .unit = "lb" } },
        )).value,
    );
    try std.testing.expectEqual(
        primitives.Decimal{ .mantissa = 55, .scale = 0 },
        (try roundLoad(
            load,
            .{ .mode = .up, .quantum = .{ .amount = "5", .unit = "lb" } },
        )).value,
    );
    try std.testing.expectError(
        error.IncompatibleUnit,
        roundLoad(
            load,
            .{ .mode = .down, .quantum = .{ .amount = "2.5", .unit = "kg" } },
        ),
    );
}

test "evaluation proposes versioned state without mutating supplied state" {
    var performance: TestPerformance = undefined;
    try performance.init(.completed, 45, 12, 12, .lb);
    const existing_states = [_]ExerciseState{
        .{
            .exerciseId = "squat",
            .load = .{ .amount = "45", .unit = "lb" },
            .targetRepetitions = 12,
        },
        .{
            .exerciseId = "row",
            .load = .{ .amount = "60", .unit = "lb" },
            .targetRepetitions = 10,
        },
    };
    const original_state = State{
        .schemaVersion = 1,
        .data = .{ .exercises = &existing_states },
    };
    var proposed_states: [2]ExerciseState = undefined;
    var evaluations: [1]ExerciseEvaluation = undefined;
    var load_amounts: [32]u8 = undefined;
    const evaluation = try evaluatePerformance(
        validConfig(&.{}),
        original_state,
        &performance.workout[0],
        .{
            .state_exercises = &proposed_states,
            .exercise_evaluations = &evaluations,
            .load_amounts = &load_amounts,
        },
    );

    try std.testing.expectEqualStrings("advanced", evaluation.outcome);
    try std.testing.expectEqual(@as(u32, 1), evaluation.next_state.schemaVersion);
    try std.testing.expectEqualStrings(
        "50.0",
        evaluation.next_state.data.exercises[0].load.amount,
    );
    try std.testing.expectEqual(
        @as(u16, 8),
        evaluation.next_state.data.exercises[0].targetRepetitions,
    );
    try std.testing.expectEqualStrings(
        "60",
        evaluation.next_state.data.exercises[1].load.amount,
    );
    try std.testing.expectEqualStrings("45", original_state.data.exercises[0].load.amount);
    try std.testing.expectEqual(
        @as(u16, 12),
        original_state.data.exercises[0].targetRepetitions,
    );
}

test "re-evaluation is deterministic and proposed state round-trips" {
    var performance: TestPerformance = undefined;
    try performance.init(.partial, 45, 9, 9, .lb);
    const existing_states = [_]ExerciseState{.{
        .exerciseId = "squat",
        .load = .{ .amount = "45", .unit = "lb" },
        .targetRepetitions = 9,
    }};
    const state = State{ .schemaVersion = 1, .data = .{ .exercises = &existing_states } };

    var first_states: [1]ExerciseState = undefined;
    var first_evaluations: [1]ExerciseEvaluation = undefined;
    var first_amounts: [32]u8 = undefined;
    const first = try evaluatePerformance(
        validConfig(&.{}),
        state,
        &performance.workout[0],
        .{
            .state_exercises = &first_states,
            .exercise_evaluations = &first_evaluations,
            .load_amounts = &first_amounts,
        },
    );
    var second_states: [1]ExerciseState = undefined;
    var second_evaluations: [1]ExerciseEvaluation = undefined;
    var second_amounts: [32]u8 = undefined;
    const second = try evaluatePerformance(
        validConfig(&.{}),
        state,
        &performance.workout[0],
        .{
            .state_exercises = &second_states,
            .exercise_evaluations = &second_evaluations,
            .load_amounts = &second_amounts,
        },
    );
    var first_json: [512]u8 = undefined;
    var second_json: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        try writeStateJson(first.next_state, &first_json),
        try writeStateJson(second.next_state, &second_json),
    );

    const encoded = try writeStateJson(first.next_state, &first_json);
    const reparsed = try std.json.parseFromSlice(
        State,
        std.testing.allocator,
        encoded,
        .{},
    );
    defer reparsed.deinit();
    try std.testing.expectEqualStrings(
        first.next_state.data.exercises[0].load.amount,
        reparsed.value.data.exercises[0].load.amount,
    );
}
