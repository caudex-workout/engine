const std = @import("std");
const canonical = @import("canonical.zig");
const diagnostics = @import("diagnostics.zig");
const history_helpers = @import("history.zig");
const load_math = @import("load_math.zig");
const primitives = @import("primitives.zig");
const training = @import("training.zig");

pub const methodology_id = "caudex.rpe-top-set-backoff";
pub const config_version: u32 = 1;
pub const state_schema_version: u32 = 1;

pub const EstimationFormula = enum {
    epley,
};

pub const BackoffCalculation = enum {
    percentage_of_top_set,
    percentage_of_estimated_one_rep_max,
};

pub const Backoff = struct {
    calculation: BackoffCalculation,
    percentage: []const u8,
    repetitions: u16,
    setCount: u16,
};

pub const RoundingMode = load_math.RoundingMode;
pub const Rounding = load_math.Rounding;

pub const OvershootAction = enum {
    hold,
    decrease_estimate,
};

pub const UndershootAction = enum {
    hold,
    increase_estimate,
};

pub const ExertionPolicy = struct {
    tolerance: []const u8,
    onOvershoot: OvershootAction,
    onUndershoot: UndershootAction,
    estimateAdjustmentPercentage: []const u8,
};

/// Version 1 JSON-boundary configuration for RPE top-set/backoff.
pub const Config = struct {
    initialEstimatedOneRepMax: canonical.Measurement,
    topSetRepetitions: u16,
    targetRpe: []const u8,
    backoff: Backoff,
    rounding: Rounding,
    exertionPolicy: ExertionPolicy,
    estimationFormula: EstimationFormula,
};

pub const ExerciseState = struct {
    exerciseId: []const u8,
    estimatedOneRepMax: canonical.Measurement,
};

pub const StateData = struct {
    exercises: []const ExerciseState = &.{},
};

pub const State = struct {
    schemaVersion: u32,
    data: StateData,
};

pub const EstimateSource = enum {
    history,
    state,
    initial_config,
};

pub const RecommendationExplanation = struct {
    code: []const u8,
    summary: []const u8,
    rule_id: []const u8,
};

pub const TopSetRecommendation = struct {
    load: primitives.Measurement,
    repetitions: u16,
    target_rpe: primitives.Decimal,
    estimated_one_rep_max: primitives.Measurement,
    estimate_source: EstimateSource,
    formula: EstimationFormula,
    explanation: RecommendationExplanation,
    warning: ?canonical.ValidationIssue = null,
};

pub const BackoffPrescription = struct {
    load: primitives.Measurement,
    repetitions: u16,
    set_count: u16,
    calculation: BackoffCalculation,
    explanation: RecommendationExplanation,
};

pub const AdjustmentOutcome = enum {
    held,
    increased,
    decreased,
};

pub const ExerciseEvaluation = struct {
    exercise_id: []const u8,
    observed_estimated_one_rep_max: primitives.Measurement,
    proposed_estimated_one_rep_max: primitives.Measurement,
    outcome: AdjustmentOutcome,
    estimation_explanation: RecommendationExplanation,
    policy_explanation: RecommendationExplanation,
};

pub const EvaluationBuffers = struct {
    state_exercises: []ExerciseState,
    exercise_evaluations: []ExerciseEvaluation,
    estimate_amounts: []u8,
};

pub const Evaluation = struct {
    outcome: []const u8,
    exercises: []const ExerciseEvaluation,
    next_state: State,
};

pub const RecommendationError = error{
    InvalidConfig,
    InvalidHistory,
    IncompatibleUnit,
    Overflow,
};

pub const EvaluationError = RecommendationError || error{
    DuplicateExercise,
    OutputLimitReached,
};

/// Recommends a top set from completed exertion evidence, state, or config.
pub fn recommendTopSet(
    config: Config,
    state: ?State,
    history: training.HistorySnapshot,
    exercise_id: primitives.Id,
) RecommendationError!TopSetRecommendation {
    var validation_storage: [64]canonical.ValidationIssue = undefined;
    var validation_issues: diagnostics.IssueWriter = .init(&validation_storage);
    validateConfig(config, &validation_issues) catch return error.InvalidConfig;
    if (state) |value| {
        validateState(config, value, &validation_issues) catch
            return error.InvalidConfig;
    }
    if (validation_issues.items().len != 0) return error.InvalidConfig;

    const configured_initial = parseBoundaryMeasurement(
        config.initialEstimatedOneRepMax,
    ) catch return error.InvalidConfig;
    const history_estimate = try estimateFromLatestTopSet(
        history,
        exercise_id,
        configured_initial.unit,
    );
    const state_estimate: ?primitives.Measurement = if (state) |value|
        if (findState(value, exercise_id)) |entry|
            parseBoundaryMeasurement(entry.estimatedOneRepMax) catch
                return error.InvalidConfig
        else
            null
    else
        null;
    const source: EstimateSource = if (history_estimate != null)
        .history
    else if (state_estimate != null)
        .state
    else
        .initial_config;
    const estimate = history_estimate orelse state_estimate orelse configured_initial;
    const target_rpe = primitives.Decimal.parse(config.targetRpe) catch
        return error.InvalidConfig;
    const unrounded_load = try loadFromEstimate(
        estimate,
        config.topSetRepetitions,
        target_rpe,
    );
    const load = try roundLoad(unrounded_load, config.rounding);

    return .{
        .load = load,
        .repetitions = config.topSetRepetitions,
        .target_rpe = target_rpe,
        .estimated_one_rep_max = estimate,
        .estimate_source = source,
        .formula = config.estimationFormula,
        .explanation = explanationFor(source),
        .warning = if (source == .history) null else insufficientHistoryWarning(),
    };
}

/// Derives all backoff sets from the explicitly configured calculation base.
pub fn recommendBackoffs(
    config: Config,
    top_set: TopSetRecommendation,
) RecommendationError!BackoffPrescription {
    var validation_storage: [64]canonical.ValidationIssue = undefined;
    var validation_issues: diagnostics.IssueWriter = .init(&validation_storage);
    validateConfig(config, &validation_issues) catch return error.InvalidConfig;
    if (validation_issues.items().len != 0) return error.InvalidConfig;

    const base = switch (config.backoff.calculation) {
        .percentage_of_top_set => top_set.load,
        .percentage_of_estimated_one_rep_max => top_set.estimated_one_rep_max,
    };
    const percentage = primitives.Decimal.parse(config.backoff.percentage) catch
        return error.InvalidConfig;
    const unrounded = try percentageOf(base, percentage);
    return .{
        .load = try roundLoad(unrounded, config.rounding),
        .repetitions = config.backoff.repetitions,
        .set_count = config.backoff.setCount,
        .calculation = config.backoff.calculation,
        .explanation = switch (config.backoff.calculation) {
            .percentage_of_top_set => .{
                .code = "backoff.selected.percentage_of_top_set",
                .summary = "The configured percentage of the top-set load determined the backoff load.",
                .rule_id = "rpe-top-set.backoff-from-top-set",
            },
            .percentage_of_estimated_one_rep_max => .{
                .code = "backoff.selected.percentage_of_estimated_one_rep_max",
                .summary = "The configured percentage of estimated 1RM determined the backoff load.",
                .rule_id = "rpe-top-set.backoff-from-estimated-one-rep-max",
            },
        },
    };
}

/// Evaluates completed top sets and returns a caller-owned proposed next state.
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

    const existing_len = if (current_state) |state| state.data.exercises.len else 0;
    if (existing_len > buffers.state_exercises.len) return error.OutputLimitReached;
    if (current_state) |state| {
        @memcpy(buffers.state_exercises[0..existing_len], state.data.exercises);
    }
    var state_len = existing_len;
    var evaluation_len: usize = 0;
    var amount_len: usize = 0;
    var any_increased = false;
    var any_decreased = false;

    const configured_unit = (parseBoundaryMeasurement(
        config.initialEstimatedOneRepMax,
    ) catch return error.InvalidConfig).unit;
    for (completed_workout.exercises, 0..) |*exercise, exercise_index| {
        for (completed_workout.exercises[0..exercise_index]) |prior| {
            if (prior.exercise_id.eql(exercise.exercise_id)) {
                return error.DuplicateExercise;
            }
        }
        const evidence = try analyzeCompletedTopSet(exercise, configured_unit) orelse
            continue;
        if (evaluation_len == buffers.exercise_evaluations.len) {
            return error.OutputLimitReached;
        }
        const adjustment = try applyExertionPolicy(
            evidence.estimate,
            evidence.rpe,
            config,
        );
        const formatted = adjustment.estimate.value.format(
            buffers.estimate_amounts[amount_len..],
        ) catch return error.OutputLimitReached;
        amount_len += formatted.len;
        const proposed = ExerciseState{
            .exerciseId = exercise.exercise_id.bytes,
            .estimatedOneRepMax = .{
                .amount = formatted,
                .unit = adjustment.estimate.unit.code(),
            },
        };
        if (findStateIndex(
            buffers.state_exercises[0..state_len],
            exercise.exercise_id,
        )) |index| {
            buffers.state_exercises[index] = proposed;
        } else {
            if (state_len == buffers.state_exercises.len) {
                return error.OutputLimitReached;
            }
            buffers.state_exercises[state_len] = proposed;
            state_len += 1;
        }
        buffers.exercise_evaluations[evaluation_len] = .{
            .exercise_id = exercise.exercise_id.bytes,
            .observed_estimated_one_rep_max = evidence.estimate,
            .proposed_estimated_one_rep_max = adjustment.estimate,
            .outcome = adjustment.outcome,
            .estimation_explanation = .{
                .code = "estimate.observed.completed_top_set",
                .summary = "Completed top-set load, repetitions, and exertion produced the observed estimate.",
                .rule_id = "rpe-top-set.completed-epley-estimate",
            },
            .policy_explanation = adjustment.explanation,
        };
        evaluation_len += 1;
        any_increased = any_increased or adjustment.outcome == .increased;
        any_decreased = any_decreased or adjustment.outcome == .decreased;
    }

    return .{
        .outcome = if (any_decreased)
            "decreased"
        else if (any_increased)
            "increased"
        else if (evaluation_len != 0)
            "held"
        else
            "no_completed_top_sets",
        .exercises = buffers.exercise_evaluations[0..evaluation_len],
        .next_state = .{
            .schemaVersion = state_schema_version,
            .data = .{ .exercises = buffers.state_exercises[0..state_len] },
        },
    };
}

const TopSetEvidence = struct {
    estimate: primitives.Measurement,
    rpe: primitives.Decimal,
};

fn analyzeCompletedTopSet(
    exercise: *const training.CompletedExercise,
    expected_unit: primitives.Unit,
) RecommendationError!?TopSetEvidence {
    for (exercise.sets) |set| {
        if (!std.mem.eql(u8, set.kind.bytes, "top") or set.status != .completed) {
            continue;
        }
        const rpe_metric = optionalMetric(set.actual_metrics, "rpe");
        const rir_metric = optionalMetric(set.actual_metrics, "rir");
        if (rpe_metric != null and rir_metric != null) return error.InvalidHistory;
        if (rpe_metric == null and rir_metric == null) return null;
        const load = try requiredMetric(set.actual_metrics, "load");
        if (load.unit != expected_unit) return error.IncompatibleUnit;
        const repetitions = try integerRepetitions(set.actual_metrics);
        const rpe = if (rpe_metric) |measurement|
            try validatedRpe(measurement)
        else
            try rpeFromRir(rir_metric.?);
        const effective_repetitions = try effectiveRepetitionsFromRpe(
            repetitions,
            .{ .value = rpe, .unit = .rpe },
        );
        return .{
            .estimate = try estimateOneRepMax(load, effective_repetitions),
            .rpe = rpe,
        };
    }
    return null;
}

const PolicyAdjustment = struct {
    estimate: primitives.Measurement,
    outcome: AdjustmentOutcome,
    explanation: RecommendationExplanation,
};

fn applyExertionPolicy(
    observed_estimate: primitives.Measurement,
    actual_rpe: primitives.Decimal,
    config: Config,
) RecommendationError!PolicyAdjustment {
    const target = primitives.Decimal.parse(config.targetRpe) catch
        return error.InvalidConfig;
    const tolerance = primitives.Decimal.parse(config.exertionPolicy.tolerance) catch
        return error.InvalidConfig;
    const upper = try decimalAdd(target, tolerance);
    const lower = try decimalSubtract(target, tolerance);
    const adjustment = primitives.Decimal.parse(
        config.exertionPolicy.estimateAdjustmentPercentage,
    ) catch return error.InvalidConfig;

    if (compareDecimal(actual_rpe, upper) == .gt) {
        return switch (config.exertionPolicy.onOvershoot) {
            .hold => heldAdjustment(observed_estimate, "overshoot"),
            .decrease_estimate => .{
                .estimate = try adjustPercentage(observed_estimate, adjustment, false),
                .outcome = .decreased,
                .explanation = .{
                    .code = "estimate.decreased.rpe_overshoot",
                    .summary = "RPE exceeded the tolerance band, so policy decreased the observed estimate.",
                    .rule_id = "rpe-top-set.overshoot-decrease",
                },
            },
        };
    }
    if (compareDecimal(actual_rpe, lower) == .lt) {
        return switch (config.exertionPolicy.onUndershoot) {
            .hold => heldAdjustment(observed_estimate, "undershoot"),
            .increase_estimate => .{
                .estimate = try adjustPercentage(observed_estimate, adjustment, true),
                .outcome = .increased,
                .explanation = .{
                    .code = "estimate.increased.rpe_undershoot",
                    .summary = "RPE fell below the tolerance band, so policy increased the observed estimate.",
                    .rule_id = "rpe-top-set.undershoot-increase",
                },
            },
        };
    }
    return heldAdjustment(observed_estimate, "tolerance");
}

fn heldAdjustment(
    estimate: primitives.Measurement,
    reason: []const u8,
) PolicyAdjustment {
    if (std.mem.eql(u8, reason, "overshoot")) return .{
        .estimate = estimate,
        .outcome = .held,
        .explanation = .{
            .code = "estimate.held.rpe_overshoot",
            .summary = "RPE exceeded the tolerance band, but policy held the observed estimate.",
            .rule_id = "rpe-top-set.overshoot-hold",
        },
    };
    if (std.mem.eql(u8, reason, "undershoot")) return .{
        .estimate = estimate,
        .outcome = .held,
        .explanation = .{
            .code = "estimate.held.rpe_undershoot",
            .summary = "RPE fell below the tolerance band, but policy held the observed estimate.",
            .rule_id = "rpe-top-set.undershoot-hold",
        },
    };
    return .{
        .estimate = estimate,
        .outcome = .held,
        .explanation = .{
            .code = "estimate.held.rpe_within_tolerance",
            .summary = "RPE remained within the inclusive tolerance band.",
            .rule_id = "rpe-top-set.tolerance-hold",
        },
    };
}

fn estimateFromLatestTopSet(
    history: training.HistorySnapshot,
    exercise_id: primitives.Id,
    expected_unit: primitives.Unit,
) RecommendationError!?primitives.Measurement {
    const performance = history_helpers.lastCompletedExercise(
        history,
        exercise_id,
    ) orelse return null;
    for (performance.exercise.sets) |set| {
        if (!std.mem.eql(u8, set.kind.bytes, "top") or
            set.status != .completed)
        {
            continue;
        }
        const rpe = optionalMetric(set.actual_metrics, "rpe");
        const rir = optionalMetric(set.actual_metrics, "rir");
        if (rpe != null and rir != null) return error.InvalidHistory;
        if (rpe == null and rir == null) return null;
        const load = try requiredMetric(set.actual_metrics, "load");
        if (load.unit != expected_unit) return error.IncompatibleUnit;
        const repetitions = try integerRepetitions(set.actual_metrics);
        const effective_repetitions = if (rpe) |measurement|
            try effectiveRepetitionsFromRpe(repetitions, measurement)
        else
            try effectiveRepetitionsFromRir(repetitions, rir.?);
        return try estimateOneRepMax(load, effective_repetitions);
    }
    return null;
}

fn effectiveRepetitionsFromRpe(
    repetitions: u16,
    measurement: primitives.Measurement,
) RecommendationError!primitives.Decimal {
    if (measurement.unit != .rpe or
        !decimalBetween(measurement.value, 1, 10))
    {
        return error.InvalidHistory;
    }
    const scale_factor = powerOfTen(measurement.value.scale);
    const value = (@as(i128, repetitions) + 10) * scale_factor -
        measurement.value.mantissa;
    if (value < 0 or value > std.math.maxInt(i64)) return error.InvalidHistory;
    return .{ .mantissa = @intCast(value), .scale = measurement.value.scale };
}

fn validatedRpe(
    measurement: primitives.Measurement,
) RecommendationError!primitives.Decimal {
    if (measurement.unit != .rpe or
        !decimalBetween(measurement.value, 1, 10))
    {
        return error.InvalidHistory;
    }
    return measurement.value;
}

fn rpeFromRir(
    measurement: primitives.Measurement,
) RecommendationError!primitives.Decimal {
    if (measurement.unit != .rir or
        !decimalBetween(measurement.value, 0, 9))
    {
        return error.InvalidHistory;
    }
    const factor = powerOfTen(measurement.value.scale);
    const result = 10 * factor - measurement.value.mantissa;
    if (result < 0 or result > std.math.maxInt(i64)) return error.InvalidHistory;
    return .{ .mantissa = @intCast(result), .scale = measurement.value.scale };
}

fn effectiveRepetitionsFromRir(
    repetitions: u16,
    measurement: primitives.Measurement,
) RecommendationError!primitives.Decimal {
    if (measurement.unit != .rir or
        !decimalBetween(measurement.value, 0, 9))
    {
        return error.InvalidHistory;
    }
    const scale_factor = powerOfTen(measurement.value.scale);
    const value = @as(i128, repetitions) * scale_factor +
        measurement.value.mantissa;
    if (value < 0 or value > std.math.maxInt(i64)) return error.InvalidHistory;
    return .{ .mantissa = @intCast(value), .scale = measurement.value.scale };
}

fn estimateOneRepMax(
    load: primitives.Measurement,
    effective_repetitions: primitives.Decimal,
) RecommendationError!primitives.Measurement {
    const load_scaled = try rescaleToThree(load.value);
    const scale_factor = powerOfTen(effective_repetitions.scale);
    const factor = 30 * scale_factor + effective_repetitions.mantissa;
    const numerator, const overflow = @mulWithOverflow(load_scaled, factor);
    if (overflow != 0) return error.Overflow;
    const estimate = try divideRoundHalfAwayFromZero(
        numerator,
        30 * scale_factor,
    );
    if (estimate < 0 or estimate > std.math.maxInt(i64)) return error.Overflow;
    return .{
        .value = .{ .mantissa = @intCast(estimate), .scale = 3 },
        .unit = load.unit,
    };
}

fn loadFromEstimate(
    estimate: primitives.Measurement,
    repetitions: u16,
    target_rpe: primitives.Decimal,
) RecommendationError!primitives.Measurement {
    const estimate_scaled = try rescaleToThree(estimate.value);
    const scale_factor = powerOfTen(target_rpe.scale);
    const denominator = (@as(i128, repetitions) + 40) * scale_factor -
        target_rpe.mantissa;
    if (denominator <= 0) return error.InvalidConfig;
    const numerator, const first_overflow = @mulWithOverflow(
        estimate_scaled,
        30,
    );
    if (first_overflow != 0) return error.Overflow;
    const scaled_numerator, const second_overflow = @mulWithOverflow(
        numerator,
        scale_factor,
    );
    if (second_overflow != 0) return error.Overflow;
    const load = try divideRoundHalfAwayFromZero(scaled_numerator, denominator);
    if (load < 0 or load > std.math.maxInt(i64)) return error.Overflow;
    return .{
        .value = .{ .mantissa = @intCast(load), .scale = 3 },
        .unit = estimate.unit,
    };
}

fn roundLoad(
    load: primitives.Measurement,
    rounding: Rounding,
) RecommendationError!primitives.Measurement {
    return load_math.roundLoad(load, rounding);
}

fn percentageOf(
    measurement: primitives.Measurement,
    percentage: primitives.Decimal,
) RecommendationError!primitives.Measurement {
    const measurement_scaled = try rescaleToThree(measurement.value);
    const denominator = 100 * powerOfTen(percentage.scale);
    const numerator, const overflow = @mulWithOverflow(
        measurement_scaled,
        @as(i128, percentage.mantissa),
    );
    if (overflow != 0) return error.Overflow;
    const result = try divideRoundHalfAwayFromZero(numerator, denominator);
    if (result < 0 or result > std.math.maxInt(i64)) return error.Overflow;
    return .{
        .value = .{ .mantissa = @intCast(result), .scale = 3 },
        .unit = measurement.unit,
    };
}

fn adjustPercentage(
    measurement: primitives.Measurement,
    percentage: primitives.Decimal,
    increase: bool,
) RecommendationError!primitives.Measurement {
    const scale_factor = powerOfTen(percentage.scale);
    const factor = if (increase)
        100 * scale_factor + percentage.mantissa
    else
        100 * scale_factor - percentage.mantissa;
    if (factor < 0) return error.InvalidConfig;
    const measurement_scaled = try rescaleToThree(measurement.value);
    const numerator, const overflow = @mulWithOverflow(measurement_scaled, factor);
    if (overflow != 0) return error.Overflow;
    const result = try divideRoundHalfAwayFromZero(
        numerator,
        100 * scale_factor,
    );
    if (result < 0 or result > std.math.maxInt(i64)) return error.Overflow;
    return .{
        .value = .{ .mantissa = @intCast(result), .scale = 3 },
        .unit = measurement.unit,
    };
}

fn explanationFor(source: EstimateSource) RecommendationExplanation {
    return switch (source) {
        .history => .{
            .code = "load.selected.history_estimated_one_rep_max",
            .summary = "Compatible completed top-set evidence determined the load.",
            .rule_id = "rpe-top-set.history-epley-load",
        },
        .state => .{
            .code = "load.selected.state_estimated_one_rep_max",
            .summary = "Stored estimated 1RM state determined the load.",
            .rule_id = "rpe-top-set.state-epley-load",
        },
        .initial_config => .{
            .code = "load.selected.initial_estimated_one_rep_max",
            .summary = "The configured initial estimated 1RM determined the load.",
            .rule_id = "rpe-top-set.initial-epley-load",
        },
    };
}

fn insufficientHistoryWarning() canonical.ValidationIssue {
    return .{
        .code = "history.insufficient_evidence",
        .path = "/history",
        .message = "No compatible completed top-set exertion evidence was available.",
        .severity = .warning,
        .suggestion = "Treat the state- or config-based estimated 1RM as an assumption.",
    };
}

fn findState(state: State, exercise_id: primitives.Id) ?*const ExerciseState {
    for (state.data.exercises) |*exercise| {
        if (std.mem.eql(u8, exercise.exerciseId, exercise_id.bytes)) return exercise;
    }
    return null;
}

fn findStateIndex(
    states: []const ExerciseState,
    exercise_id: primitives.Id,
) ?usize {
    for (states, 0..) |state, index| {
        if (std.mem.eql(u8, state.exerciseId, exercise_id.bytes)) return index;
    }
    return null;
}

fn requiredMetric(
    metrics: []const training.Metric,
    code: []const u8,
) RecommendationError!primitives.Measurement {
    return optionalMetric(metrics, code) orelse error.InvalidHistory;
}

fn optionalMetric(
    metrics: []const training.Metric,
    code: []const u8,
) ?primitives.Measurement {
    for (metrics) |metric| {
        if (std.mem.eql(u8, metric.code.bytes, code)) return metric.value;
    }
    return null;
}

fn integerRepetitions(metrics: []const training.Metric) RecommendationError!u16 {
    const repetitions = try requiredMetric(metrics, "repetitions");
    if (repetitions.unit != .count or
        repetitions.value.scale != 0 or
        repetitions.value.mantissa <= 0 or
        repetitions.value.mantissa > std.math.maxInt(u16))
    {
        return error.InvalidHistory;
    }
    return @intCast(repetitions.value.mantissa);
}

fn parseBoundaryMeasurement(measurement: canonical.Measurement) !primitives.Measurement {
    return load_math.parseMeasurement(measurement);
}

fn decimalBetween(value: primitives.Decimal, min: i64, max: i64) bool {
    const factor = powerOfTen(value.scale);
    return value.mantissa >= @as(i128, min) * factor and
        value.mantissa <= @as(i128, max) * factor;
}

fn decimalAdd(
    left: primitives.Decimal,
    right: primitives.Decimal,
) RecommendationError!primitives.Decimal {
    const scale = @max(left.scale, right.scale);
    const left_value = try checkedScaledMantissa(left, scale);
    const right_value = try checkedScaledMantissa(right, scale);
    const result, const overflow = @addWithOverflow(left_value, right_value);
    if (overflow != 0 or
        result < std.math.minInt(i64) or result > std.math.maxInt(i64))
    {
        return error.Overflow;
    }
    return .{ .mantissa = @intCast(result), .scale = scale };
}

fn decimalSubtract(
    left: primitives.Decimal,
    right: primitives.Decimal,
) RecommendationError!primitives.Decimal {
    const scale = @max(left.scale, right.scale);
    const left_value = try checkedScaledMantissa(left, scale);
    const right_value = try checkedScaledMantissa(right, scale);
    const result, const overflow = @subWithOverflow(left_value, right_value);
    if (overflow != 0 or
        result < std.math.minInt(i64) or result > std.math.maxInt(i64))
    {
        return error.Overflow;
    }
    return .{ .mantissa = @intCast(result), .scale = scale };
}

fn rescaleToThree(value: primitives.Decimal) RecommendationError!i128 {
    if (value.scale == 3) return value.mantissa;
    if (value.scale < 3) return try checkedScaledMantissa(value, 3);
    const divisor = powerOfTen(value.scale - 3);
    return divideRoundHalfAwayFromZero(value.mantissa, divisor);
}

fn checkedScaledMantissa(
    value: primitives.Decimal,
    scale: u8,
) RecommendationError!i128 {
    var result: i128 = value.mantissa;
    var remaining = scale - value.scale;
    while (remaining > 0) : (remaining -= 1) {
        const next, const overflow = @mulWithOverflow(result, 10);
        if (overflow != 0) return error.Overflow;
        result = next;
    }
    return result;
}

fn powerOfTen(scale: u8) i128 {
    var result: i128 = 1;
    for (0..scale) |_| result *= 10;
    return result;
}

fn divideRoundHalfAwayFromZero(
    numerator: i128,
    denominator: i128,
) RecommendationError!i128 {
    if (denominator <= 0) return error.InvalidConfig;
    const quotient = @divTrunc(numerator, denominator);
    const remainder = @rem(numerator, denominator);
    const magnitude = if (remainder < 0) -remainder else remainder;
    if (magnitude * 2 < denominator) return quotient;
    return quotient + (if (numerator < 0) @as(i128, -1) else 1);
}

pub fn validateConfig(
    config: Config,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    const initial = parseNonNegativeMeasurement(config.initialEstimatedOneRepMax) catch {
        try appendConfigInvalid(
            issues,
            "Initial estimated 1RM must be a non-negative mass measurement.",
        );
        return;
    };
    if (initial.unit.dimension() != .mass) {
        try appendConfigInvalid(issues, "Initial estimated 1RM must use a mass unit.");
    }
    if (config.topSetRepetitions == 0) {
        try appendConfigInvalid(issues, "Top-set repetitions must be greater than zero.");
    }
    if (!decimalInRange(config.targetRpe, "1", "10")) {
        try appendConfigInvalid(issues, "Target RPE must be an exact decimal from 1 through 10.");
    }
    if (!decimalPositiveAtMost(config.backoff.percentage, "100")) {
        try appendConfigInvalid(
            issues,
            "Backoff percentage must be greater than zero and at most 100.",
        );
    }
    if (config.backoff.repetitions == 0 or
        config.backoff.setCount == 0 or
        config.backoff.setCount > 64)
    {
        try appendConfigInvalid(
            issues,
            "Backoff repetitions must be positive and set count must be between 1 and 64.",
        );
    }
    const quantum = parsePositiveMeasurement(config.rounding.quantum) catch {
        try appendConfigInvalid(issues, "Rounding quantum must be a positive mass measurement.");
        return;
    };
    if (quantum.unit.dimension() != .mass or quantum.unit != initial.unit) {
        try appendConfigInvalid(
            issues,
            "Initial estimate and rounding quantum must use one mass unit.",
        );
    }
    if (!decimalInRange(config.exertionPolicy.tolerance, "0", "9")) {
        try appendConfigInvalid(
            issues,
            "RPE tolerance must be a non-negative exact decimal below 10.",
        );
    }
    if (!decimalPositiveAtMost(
        config.exertionPolicy.estimateAdjustmentPercentage,
        "100",
    )) {
        try appendConfigInvalid(
            issues,
            "Estimate adjustment percentage must be greater than zero and at most 100.",
        );
    }
}

pub fn validateState(
    config: Config,
    state: State,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    if (state.schemaVersion != state_schema_version) {
        try issues.append(.{
            .code = "methodology.state_unsupported_version",
            .path = "/methodologyState/schemaVersion",
            .message = "The RPE top-set/backoff state schema version is unsupported.",
            .severity = .@"error",
            .suggestion = "Provide RPE top-set/backoff state schema version 1.",
        });
    }
    const configured_unit = (parseNonNegativeMeasurement(
        config.initialEstimatedOneRepMax,
    ) catch return).unit;
    for (state.data.exercises, 0..) |exercise, exercise_index| {
        if (exercise.exerciseId.len == 0 or
            exercise.exerciseId.len > 200 or
            !std.unicode.utf8ValidateSlice(exercise.exerciseId))
        {
            try appendStateInvalid(issues, "A state exercise ID is invalid.");
        }
        for (state.data.exercises[0..exercise_index]) |prior| {
            if (std.mem.eql(u8, prior.exerciseId, exercise.exerciseId)) {
                try appendStateInvalid(issues, "State exercise IDs must be unique.");
                break;
            }
        }
        const estimate = parseNonNegativeMeasurement(exercise.estimatedOneRepMax) catch {
            try appendStateInvalid(
                issues,
                "Estimated 1RM state must be a non-negative mass measurement.",
            );
            continue;
        };
        if (estimate.unit.dimension() != .mass or estimate.unit != configured_unit) {
            try appendStateInvalid(
                issues,
                "Estimated 1RM state must use the configured mass unit.",
            );
        }
    }
}

fn parsePositiveMeasurement(measurement: canonical.Measurement) !primitives.Measurement {
    const parsed = try parseNonNegativeMeasurement(measurement);
    if (parsed.value.mantissa <= 0) return error.NonPositive;
    return parsed;
}

fn parseNonNegativeMeasurement(measurement: canonical.Measurement) !primitives.Measurement {
    const value = try primitives.Decimal.parse(measurement.amount);
    if (value.mantissa < 0) return error.Negative;
    return .{
        .value = value,
        .unit = try primitives.Unit.parse(measurement.unit),
    };
}

fn decimalInRange(text: []const u8, minimum: []const u8, maximum: []const u8) bool {
    const value = primitives.Decimal.parse(text) catch return false;
    const min = primitives.Decimal.parse(minimum) catch unreachable;
    const max = primitives.Decimal.parse(maximum) catch unreachable;
    return compareDecimal(value, min) != .lt and compareDecimal(value, max) != .gt;
}

fn decimalPositiveAtMost(text: []const u8, maximum: []const u8) bool {
    const value = primitives.Decimal.parse(text) catch return false;
    const zero = primitives.Decimal{ .mantissa = 0, .scale = 0 };
    const max = primitives.Decimal.parse(maximum) catch unreachable;
    return compareDecimal(value, zero) == .gt and compareDecimal(value, max) != .gt;
}

fn compareDecimal(left: primitives.Decimal, right: primitives.Decimal) std.math.Order {
    const scale = @max(left.scale, right.scale);
    const left_value = scaledMantissa(left, scale);
    const right_value = scaledMantissa(right, scale);
    return std.math.order(left_value, right_value);
}

fn scaledMantissa(value: primitives.Decimal, scale: u8) i128 {
    var result: i128 = value.mantissa;
    var remaining = scale - value.scale;
    while (remaining > 0) : (remaining -= 1) result *= 10;
    return result;
}

fn appendConfigInvalid(
    issues: *diagnostics.IssueWriter,
    message: []const u8,
) diagnostics.IssueWriter.AppendError!void {
    try issues.append(.{
        .code = "methodology.config_invalid",
        .path = "/methodology/config",
        .message = message,
        .severity = .@"error",
        .suggestion = "Correct the RPE top-set/backoff configuration.",
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
        .suggestion = "Rebuild state from valid accepted methodology output.",
    });
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

fn validConfig() Config {
    return .{
        .initialEstimatedOneRepMax = .{ .amount = "225", .unit = "lb" },
        .topSetRepetitions = 5,
        .targetRpe = "8.0",
        .backoff = .{
            .calculation = .percentage_of_top_set,
            .percentage = "90",
            .repetitions = 8,
            .setCount = 3,
        },
        .rounding = .{
            .mode = .nearest,
            .quantum = .{ .amount = "2.5", .unit = "lb" },
        },
        .exertionPolicy = .{
            .tolerance = "0.5",
            .onOvershoot = .decrease_estimate,
            .onUndershoot = .increase_estimate,
            .estimateAdjustmentPercentage = "2.5",
        },
        .estimationFormula = .epley,
    };
}

test "valid RPE config and state collect no issues" {
    const config = validConfig();
    const states = [_]ExerciseState{.{
        .exerciseId = "barbell-bench-press",
        .estimatedOneRepMax = .{ .amount = "225", .unit = "lb" },
    }};
    var storage: [8]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&storage);
    try validateConfig(config, &issues);
    try validateState(
        config,
        .{ .schemaVersion = 1, .data = .{ .exercises = &states } },
        &issues,
    );
    try std.testing.expectEqual(@as(usize, 0), issues.items().len);
}

test "RPE config validation collects range and unit failures" {
    var config = validConfig();
    config.targetRpe = "10.5";
    config.backoff.percentage = "0";
    config.backoff.setCount = 0;
    config.rounding.quantum = .{ .amount = "2.5", .unit = "kg" };
    var storage: [8]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&storage);
    try validateConfig(config, &issues);
    try std.testing.expect(issues.items().len >= 4);
    for (issues.items()) |issue| {
        try std.testing.expectEqualStrings("methodology.config_invalid", issue.code);
    }
}

const TestTopSetHistory = struct {
    metrics: [4]training.Metric,
    set: [1]training.CompletedSet,
    exercise: [1]training.CompletedExercise,
    workout: [1]training.CompletedWorkout,

    fn init(
        exertion_code: []const u8,
        exertion: primitives.Decimal,
        load_unit: primitives.Unit,
        include_second_exertion: bool,
    ) !TestTopSetHistory {
        var result: TestTopSetHistory = undefined;
        result.metrics = .{
            testMetric("load", .{ .mantissa = 185, .scale = 0 }, load_unit),
            testMetric("repetitions", .{ .mantissa = 5, .scale = 0 }, .count),
            testMetric(exertion_code, exertion, if (std.mem.eql(u8, exertion_code, "rpe")) .rpe else .rir),
            testMetric("rir", .{ .mantissa = 1, .scale = 0 }, .rir),
        };
        result.set = .{.{
            .kind = try .parse("top"),
            .actual_metrics = result.metrics[0..if (include_second_exertion) 4 else 3],
            .status = .completed,
        }};
        result.exercise = .{.{
            .exercise_id = try .parse("barbell-bench-press"),
            .sets = &result.set,
        }};
        result.workout = .{.{
            .id = try .parse("workout-1"),
            .started_at = try .parse("2026-07-25T14:00:00Z"),
            .completed_at = try .parse("2026-07-25T15:00:00Z"),
            .exercises = &result.exercise,
        }};
        return result;
    }

    fn history(self: *const TestTopSetHistory) training.HistorySnapshot {
        return .{ .workouts = &self.workout };
    }
};

fn testMetric(
    code: []const u8,
    value: primitives.Decimal,
    unit: primitives.Unit,
) training.Metric {
    return .{
        .code = primitives.Id.parse(code) catch unreachable,
        .value = .{ .value = value, .unit = unit },
    };
}

test "top-set recommendation prefers compatible history evidence" {
    var history = try TestTopSetHistory.init(
        "rpe",
        .{ .mantissa = 85, .scale = 1 },
        .lb,
        false,
    );
    const result = try recommendTopSet(
        validConfig(),
        null,
        history.history(),
        try .parse("barbell-bench-press"),
    );

    try std.testing.expectEqual(EstimateSource.history, result.estimate_source);
    try std.testing.expectEqualStrings(
        "225.083",
        result.estimated_one_rep_max.value.format().slice(),
    );
    try std.testing.expectEqualStrings("182.500", result.load.value.format().slice());
    try std.testing.expectEqualStrings(
        "load.selected.history_estimated_one_rep_max",
        result.explanation.code,
    );
    try std.testing.expect(result.warning == null);
}

test "RIR evidence is equivalent to its RPE conversion" {
    var rpe_history = try TestTopSetHistory.init(
        "rpe",
        .{ .mantissa = 85, .scale = 1 },
        .lb,
        false,
    );
    var rir_history = try TestTopSetHistory.init(
        "rir",
        .{ .mantissa = 15, .scale = 1 },
        .lb,
        false,
    );
    const config = validConfig();
    const exercise_id = try primitives.Id.parse("barbell-bench-press");
    const from_rpe = try recommendTopSet(config, null, rpe_history.history(), exercise_id);
    const from_rir = try recommendTopSet(config, null, rir_history.history(), exercise_id);

    try std.testing.expectEqual(
        from_rpe.estimated_one_rep_max.value,
        from_rir.estimated_one_rep_max.value,
    );
    try std.testing.expectEqual(from_rpe.load.value, from_rir.load.value);
}

test "top-set recommendation falls back to state then initial config" {
    const exercise_id = try primitives.Id.parse("barbell-bench-press");
    const states = [_]ExerciseState{.{
        .exerciseId = "barbell-bench-press",
        .estimatedOneRepMax = .{ .amount = "240", .unit = "lb" },
    }};
    const state: State = .{
        .schemaVersion = 1,
        .data = .{ .exercises = &states },
    };
    const from_state = try recommendTopSet(validConfig(), state, .{}, exercise_id);
    const from_initial = try recommendTopSet(validConfig(), null, .{}, exercise_id);

    try std.testing.expectEqual(EstimateSource.state, from_state.estimate_source);
    try std.testing.expectEqualStrings("195.000", from_state.load.value.format().slice());
    try std.testing.expect(from_state.warning != null);
    try std.testing.expectEqual(
        EstimateSource.initial_config,
        from_initial.estimate_source,
    );
    try std.testing.expectEqualStrings("182.500", from_initial.load.value.format().slice());
    try std.testing.expectEqualStrings(
        "history.insufficient_evidence",
        from_initial.warning.?.code,
    );
}

test "top-set recommendation rejects conflicting exertion and units" {
    var conflicting = try TestTopSetHistory.init(
        "rpe",
        .{ .mantissa = 8, .scale = 0 },
        .lb,
        true,
    );
    var kilograms = try TestTopSetHistory.init(
        "rpe",
        .{ .mantissa = 8, .scale = 0 },
        .kg,
        false,
    );
    const exercise_id = try primitives.Id.parse("barbell-bench-press");

    try std.testing.expectError(
        error.InvalidHistory,
        recommendTopSet(validConfig(), null, conflicting.history(), exercise_id),
    );
    try std.testing.expectError(
        error.IncompatibleUnit,
        recommendTopSet(validConfig(), null, kilograms.history(), exercise_id),
    );
}

test "top-set load rounding obeys every configured mode" {
    const load: primitives.Measurement = .{
        .value = .{ .mantissa = 182432, .scale = 3 },
        .unit = .lb,
    };
    const quantum: canonical.Measurement = .{ .amount = "5", .unit = "lb" };
    const down = try roundLoad(load, .{ .mode = .down, .quantum = quantum });
    const nearest = try roundLoad(load, .{ .mode = .nearest, .quantum = quantum });
    const up = try roundLoad(load, .{ .mode = .up, .quantum = quantum });

    try std.testing.expectEqualStrings("180.000", down.value.format().slice());
    try std.testing.expectEqualStrings("180.000", nearest.value.format().slice());
    try std.testing.expectEqualStrings("185.000", up.value.format().slice());
}

test "backoffs derive from the configured top-set or estimate base" {
    var history = try TestTopSetHistory.init(
        "rpe",
        .{ .mantissa = 85, .scale = 1 },
        .lb,
        false,
    );
    var config = validConfig();
    const top_set = try recommendTopSet(
        config,
        null,
        history.history(),
        try .parse("barbell-bench-press"),
    );
    const from_top_set = try recommendBackoffs(config, top_set);
    config.backoff.calculation = .percentage_of_estimated_one_rep_max;
    const from_estimate = try recommendBackoffs(config, top_set);

    try std.testing.expectEqualStrings(
        "165.000",
        from_top_set.load.value.format().slice(),
    );
    try std.testing.expectEqual(@as(u16, 8), from_top_set.repetitions);
    try std.testing.expectEqual(@as(u16, 3), from_top_set.set_count);
    try std.testing.expectEqualStrings(
        "backoff.selected.percentage_of_top_set",
        from_top_set.explanation.code,
    );
    try std.testing.expectEqualStrings(
        "202.500",
        from_estimate.load.value.format().slice(),
    );
    try std.testing.expectEqualStrings(
        "backoff.selected.percentage_of_estimated_one_rep_max",
        from_estimate.explanation.code,
    );
}

test "evaluation separates observed estimate from overshoot policy" {
    var history = try TestTopSetHistory.init(
        "rpe",
        .{ .mantissa = 9, .scale = 0 },
        .lb,
        false,
    );
    var state_storage: [1]ExerciseState = undefined;
    var evaluation_storage: [1]ExerciseEvaluation = undefined;
    var amount_storage: [32]u8 = undefined;
    const evaluation = try evaluatePerformance(
        validConfig(),
        null,
        &history.workout[0],
        .{
            .state_exercises = &state_storage,
            .exercise_evaluations = &evaluation_storage,
            .estimate_amounts = &amount_storage,
        },
    );

    try std.testing.expectEqualStrings("decreased", evaluation.outcome);
    try std.testing.expectEqual(@as(usize, 1), evaluation.exercises.len);
    try std.testing.expectEqual(
        AdjustmentOutcome.decreased,
        evaluation.exercises[0].outcome,
    );
    try std.testing.expectEqualStrings(
        "222.000",
        evaluation.exercises[0].observed_estimated_one_rep_max.value.format().slice(),
    );
    try std.testing.expectEqualStrings(
        "216.450",
        evaluation.exercises[0].proposed_estimated_one_rep_max.value.format().slice(),
    );
    try std.testing.expectEqualStrings(
        "estimate.observed.completed_top_set",
        evaluation.exercises[0].estimation_explanation.code,
    );
    try std.testing.expectEqualStrings(
        "estimate.decreased.rpe_overshoot",
        evaluation.exercises[0].policy_explanation.code,
    );
    try std.testing.expectEqualStrings(
        "216.450",
        evaluation.next_state.data.exercises[0].estimatedOneRepMax.amount,
    );
}

test "evaluation increases on undershoot and holds inside inclusive tolerance" {
    var undershoot = try TestTopSetHistory.init(
        "rir",
        .{ .mantissa = 3, .scale = 0 },
        .lb,
        false,
    );
    var within_tolerance = try TestTopSetHistory.init(
        "rpe",
        .{ .mantissa = 85, .scale = 1 },
        .lb,
        false,
    );
    var state_storage: [1]ExerciseState = undefined;
    var evaluation_storage: [1]ExerciseEvaluation = undefined;
    var amount_storage: [32]u8 = undefined;
    const increased = try evaluatePerformance(
        validConfig(),
        null,
        &undershoot.workout[0],
        .{
            .state_exercises = &state_storage,
            .exercise_evaluations = &evaluation_storage,
            .estimate_amounts = &amount_storage,
        },
    );
    try std.testing.expectEqualStrings("increased", increased.outcome);
    try std.testing.expectEqualStrings(
        "estimate.increased.rpe_undershoot",
        increased.exercises[0].policy_explanation.code,
    );

    const held = try evaluatePerformance(
        validConfig(),
        null,
        &within_tolerance.workout[0],
        .{
            .state_exercises = &state_storage,
            .exercise_evaluations = &evaluation_storage,
            .estimate_amounts = &amount_storage,
        },
    );
    try std.testing.expectEqualStrings("held", held.outcome);
    try std.testing.expectEqual(
        held.exercises[0].observed_estimated_one_rep_max.value,
        held.exercises[0].proposed_estimated_one_rep_max.value,
    );
    try std.testing.expectEqualStrings(
        "estimate.held.rpe_within_tolerance",
        held.exercises[0].policy_explanation.code,
    );
}

test "evaluation preserves unrelated state and is deterministic" {
    var history = try TestTopSetHistory.init(
        "rpe",
        .{ .mantissa = 9, .scale = 0 },
        .lb,
        false,
    );
    const existing = [_]ExerciseState{.{
        .exerciseId = "squat",
        .estimatedOneRepMax = .{ .amount = "315", .unit = "lb" },
    }};
    const state: State = .{
        .schemaVersion = 1,
        .data = .{ .exercises = &existing },
    };
    var first_states: [2]ExerciseState = undefined;
    var first_evaluations: [1]ExerciseEvaluation = undefined;
    var first_amounts: [32]u8 = undefined;
    const first = try evaluatePerformance(
        validConfig(),
        state,
        &history.workout[0],
        .{
            .state_exercises = &first_states,
            .exercise_evaluations = &first_evaluations,
            .estimate_amounts = &first_amounts,
        },
    );
    var second_states: [2]ExerciseState = undefined;
    var second_evaluations: [1]ExerciseEvaluation = undefined;
    var second_amounts: [32]u8 = undefined;
    const second = try evaluatePerformance(
        validConfig(),
        state,
        &history.workout[0],
        .{
            .state_exercises = &second_states,
            .exercise_evaluations = &second_evaluations,
            .estimate_amounts = &second_amounts,
        },
    );

    try std.testing.expectEqual(@as(usize, 2), first.next_state.data.exercises.len);
    try std.testing.expectEqualStrings(
        "315",
        first.next_state.data.exercises[0].estimatedOneRepMax.amount,
    );
    try std.testing.expectEqualStrings(
        first.next_state.data.exercises[1].estimatedOneRepMax.amount,
        second.next_state.data.exercises[1].estimatedOneRepMax.amount,
    );
    try std.testing.expectEqualStrings(
        "315",
        state.data.exercises[0].estimatedOneRepMax.amount,
    );
}
