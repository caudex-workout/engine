const std = @import("std");
const primitives = @import("primitives.zig");
const training = @import("training.zig");

pub const SummaryError = error{
    OutputLimitReached,
    IncompatibleUnit,
    InvalidMetric,
    FuturePerformance,
    Overflow,
};

/// A borrowed location in the host-supplied history snapshot.
pub const ExercisePerformance = struct {
    workout_index: usize,
    exercise_index: usize,
    workout: *const training.CompletedWorkout,
    exercise: *const training.CompletedExercise,
};

pub const Recency = struct {
    elapsed_seconds: u64,
};

pub const OneRepMaxFormula = enum {
    epley,

    pub fn id(self: OneRepMaxFormula) []const u8 {
        return switch (self) {
            .epley => "epley",
        };
    }
};

pub const OneRepMaxEstimate = struct {
    value: primitives.Measurement,
    formula: OneRepMaxFormula,
};

/// Finds the most recently completed occurrence, independent of input order.
pub fn lastCompletedExercise(
    snapshot: training.HistorySnapshot,
    exercise_id: primitives.Id,
) ?ExercisePerformance {
    var latest: ?ExercisePerformance = null;
    for (snapshot.workouts, 0..) |*workout, workout_index| {
        for (workout.exercises, 0..) |*exercise, exercise_index| {
            if (!exercise.exercise_id.eql(exercise_id)) continue;
            const candidate = ExercisePerformance{
                .workout_index = workout_index,
                .exercise_index = exercise_index,
                .workout = workout,
                .exercise = exercise,
            };
            if (latest == null or performanceComesBefore(
                candidate,
                latest.?,
            )) {
                latest = candidate;
            }
        }
    }
    return latest;
}

/// Writes newest-first exercise occurrences into caller-owned storage.
pub fn recentPerformances(
    snapshot: training.HistorySnapshot,
    exercise_id: primitives.Id,
    out: []ExercisePerformance,
) SummaryError![]const ExercisePerformance {
    var len: usize = 0;
    for (snapshot.workouts, 0..) |*workout, workout_index| {
        for (workout.exercises, 0..) |*exercise, exercise_index| {
            if (!exercise.exercise_id.eql(exercise_id)) continue;
            if (len == out.len) return error.OutputLimitReached;
            const candidate = ExercisePerformance{
                .workout_index = workout_index,
                .exercise_index = exercise_index,
                .workout = workout,
                .exercise = exercise,
            };
            var insertion = len;
            while (insertion > 0 and performanceComesBefore(
                candidate,
                out[insertion - 1],
            )) {
                out[insertion] = out[insertion - 1];
                insertion -= 1;
            }
            out[insertion] = candidate;
            len += 1;
        }
    }
    return out[0..len];
}

/// Orders performances newest-first with an explicit ID tie-break. Host
/// snapshots are not required to arrive in chronological order, and equal
/// timestamps are common when a host only records second precision.
fn performanceComesBefore(
    left: ExercisePerformance,
    right: ExercisePerformance,
) bool {
    const left_seconds = left.workout.completed_at.unixSeconds();
    const right_seconds = right.workout.completed_at.unixSeconds();
    if (left_seconds != right_seconds) return left_seconds > right_seconds;
    return std.mem.order(u8, left.workout.id.bytes, right.workout.id.bytes) == .lt;
}

/// Returns elapsed whole seconds from a completed workout to explicit `as_of`.
pub fn recency(
    completed_at: primitives.Timestamp,
    as_of: primitives.Timestamp,
) SummaryError!Recency {
    const completed_seconds = completed_at.unixSeconds();
    const as_of_seconds = as_of.unixSeconds();
    if (completed_seconds > as_of_seconds) return error.FuturePerformance;
    return .{ .elapsed_seconds = @intCast(as_of_seconds - completed_seconds) };
}

/// Sums completed load × repetitions using one exact caller-selected load unit.
pub fn compatibleUnitVolume(
    performance: ExercisePerformance,
    load_unit: primitives.Unit,
) SummaryError!primitives.Measurement {
    if (load_unit.dimension() != .mass) return error.IncompatibleUnit;
    var total = primitives.Decimal{ .mantissa = 0, .scale = 0 };
    for (performance.exercise.sets) |set| {
        if (set.status != .completed) continue;
        const load = try requiredMetric(set, "load");
        const repetitions = try requiredMetric(set, "repetitions");
        if (load.unit != load_unit or repetitions.unit != .count) {
            return error.IncompatibleUnit;
        }
        if (load.value.mantissa < 0) return error.InvalidMetric;
        try requireNonNegativeInteger(repetitions.value);
        const set_volume = primitives.Decimal.multiply(
            load.value,
            repetitions.value,
        ) catch return error.Overflow;
        total = primitives.Decimal.add(total, set_volume) catch return error.Overflow;
    }
    return .{ .value = total, .unit = load_unit };
}

/// Finds the greatest completed load whose repetitions fall in an inclusive range.
pub fn bestCompletedLoad(
    snapshot: training.HistorySnapshot,
    exercise_id: primitives.Id,
    rep_min: u16,
    rep_max: u16,
    load_unit: primitives.Unit,
) SummaryError!?primitives.Measurement {
    if (rep_min == 0 or rep_min > rep_max) return error.InvalidMetric;
    if (load_unit.dimension() != .mass) return error.IncompatibleUnit;
    var best: ?primitives.Decimal = null;
    for (snapshot.workouts) |workout| {
        for (workout.exercises) |exercise| {
            if (!exercise.exercise_id.eql(exercise_id)) continue;
            for (exercise.sets) |set| {
                if (set.status != .completed) continue;
                const load = try requiredMetric(set, "load");
                const repetitions = try requiredMetric(set, "repetitions");
                if (load.unit != load_unit or repetitions.unit != .count) {
                    return error.IncompatibleUnit;
                }
                if (load.value.mantissa < 0) return error.InvalidMetric;
                const reps = try nonNegativeInteger(repetitions.value);
                if (reps < rep_min or reps > rep_max) continue;
                if (best == null or try decimalGreaterThan(load.value, best.?)) {
                    best = load.value;
                }
            }
        }
    }
    return if (best) |value| .{ .value = value, .unit = load_unit } else null;
}

/// Estimates 1RM using Epley: load × (1 + repetitions / 30).
///
/// The result uses three decimal places and rounds half away from zero.
pub fn estimateOneRepMaxEpley(
    load: primitives.Measurement,
    repetitions: u16,
) SummaryError!OneRepMaxEstimate {
    if (load.unit.dimension() != .mass or
        load.value.mantissa < 0 or
        repetitions == 0)
    {
        return error.InvalidMetric;
    }
    const scale_multiplier: i128 = 1_000;
    const numerator, const numerator_overflow = @mulWithOverflow(
        @as(i128, load.value.mantissa),
        @as(i128, 30 + @as(u32, repetitions)),
    );
    if (numerator_overflow != 0) return error.Overflow;
    const scaled, const scaled_overflow = @mulWithOverflow(numerator, scale_multiplier);
    if (scaled_overflow != 0) return error.Overflow;
    const denominator = try powerOfTen(load.value.scale) * 30;
    const rounded = try divideRoundHalfAwayFromZero(scaled, denominator);
    if (rounded < std.math.minInt(i64) or rounded > std.math.maxInt(i64)) {
        return error.Overflow;
    }
    return .{
        .value = .{
            .value = .{ .mantissa = @intCast(rounded), .scale = 3 },
            .unit = load.unit,
        },
        .formula = .epley,
    };
}

fn requiredMetric(
    set: training.CompletedSet,
    code: []const u8,
) SummaryError!primitives.Measurement {
    for (set.actual_metrics) |metric| {
        if (std.mem.eql(u8, metric.code.bytes, code)) return metric.value;
    }
    return error.InvalidMetric;
}

fn requireNonNegativeInteger(value: primitives.Decimal) SummaryError!void {
    _ = try nonNegativeInteger(value);
}

fn nonNegativeInteger(value: primitives.Decimal) SummaryError!u64 {
    if (value.scale != 0 or value.mantissa < 0) return error.InvalidMetric;
    return @intCast(value.mantissa);
}

fn decimalGreaterThan(
    left: primitives.Decimal,
    right: primitives.Decimal,
) SummaryError!bool {
    const scale = @max(left.scale, right.scale);
    const left_scaled = try scaleMantissa(left, scale);
    const right_scaled = try scaleMantissa(right, scale);
    return left_scaled > right_scaled;
}

fn scaleMantissa(value: primitives.Decimal, scale: u8) SummaryError!i128 {
    var result: i128 = value.mantissa;
    var remaining = scale - value.scale;
    while (remaining > 0) : (remaining -= 1) {
        const next, const overflow = @mulWithOverflow(result, 10);
        if (overflow != 0) return error.Overflow;
        result = next;
    }
    return result;
}

fn powerOfTen(scale: u8) SummaryError!i128 {
    var result: i128 = 1;
    for (0..scale) |_| {
        const next, const overflow = @mulWithOverflow(result, 10);
        if (overflow != 0) return error.Overflow;
        result = next;
    }
    return result;
}

fn divideRoundHalfAwayFromZero(
    numerator: i128,
    denominator: i128,
) SummaryError!i128 {
    if (denominator <= 0) return error.InvalidMetric;
    const quotient = @divTrunc(numerator, denominator);
    const remainder = @rem(numerator, denominator);
    const magnitude = if (remainder < 0) -remainder else remainder;
    if (magnitude * 2 < denominator) return quotient;
    return quotient + (if (numerator < 0) @as(i128, -1) else 1);
}

const TestHistory = struct {
    exercise_id: primitives.Id,
    load_id: primitives.Id,
    repetitions_id: primitives.Id,
    working_id: primitives.Id,
    metrics: [6]training.Metric,
    sets: [3]training.CompletedSet,
    exercises: [2]training.CompletedExercise,
    workouts: [2]training.CompletedWorkout,

    fn init(self: *TestHistory) !void {
        const exercise_id = try primitives.Id.parse("squat");
        const load_id = try primitives.Id.parse("load");
        const repetitions_id = try primitives.Id.parse("repetitions");
        const working_id = try primitives.Id.parse("working");
        self.* = .{
            .exercise_id = exercise_id,
            .load_id = load_id,
            .repetitions_id = repetitions_id,
            .working_id = working_id,
            .metrics = undefined,
            .sets = undefined,
            .exercises = undefined,
            .workouts = undefined,
        };
        self.metrics = .{
            testMetric(load_id, 100, .kg),
            testMetric(repetitions_id, 5, .count),
            testMetric(load_id, 90, .kg),
            testMetric(repetitions_id, 8, .count),
            testMetric(load_id, 95, .kg),
            testMetric(repetitions_id, 6, .count),
        };
        self.sets = .{
            .{ .kind = working_id, .actual_metrics = self.metrics[0..2], .status = .completed },
            .{ .kind = working_id, .actual_metrics = self.metrics[2..4], .status = .completed },
            .{ .kind = working_id, .actual_metrics = self.metrics[4..6], .status = .completed },
        };
        self.exercises = .{
            .{ .exercise_id = exercise_id, .sets = self.sets[0..2] },
            .{ .exercise_id = exercise_id, .sets = self.sets[2..3] },
        };
        self.workouts = .{
            .{
                .id = try primitives.Id.parse("newer"),
                .started_at = try primitives.Timestamp.parse("2026-07-24T10:00:00Z"),
                .completed_at = try primitives.Timestamp.parse("2026-07-24T11:00:00Z"),
                .exercises = self.exercises[0..1],
            },
            .{
                .id = try primitives.Id.parse("older"),
                .started_at = try primitives.Timestamp.parse("2026-07-20T10:00:00Z"),
                .completed_at = try primitives.Timestamp.parse("2026-07-20T11:00:00Z"),
                .exercises = self.exercises[1..2],
            },
        };
    }

    fn snapshot(self: *const TestHistory) training.HistorySnapshot {
        return .{ .workouts = &self.workouts };
    }
};

fn testMetric(code: primitives.Id, mantissa: i64, unit: primitives.Unit) training.Metric {
    return .{
        .code = code,
        .value = .{ .value = .{ .mantissa = mantissa, .scale = 0 }, .unit = unit },
    };
}

test "last and recent exercise performances use completion time" {
    var history: TestHistory = undefined;
    try history.init();
    const last = lastCompletedExercise(history.snapshot(), history.exercise_id).?;
    try std.testing.expectEqualStrings("newer", last.workout.id.bytes);

    var storage: [2]ExercisePerformance = undefined;
    const recent = try recentPerformances(history.snapshot(), history.exercise_id, &storage);
    try std.testing.expectEqualStrings("newer", recent[0].workout.id.bytes);
    try std.testing.expectEqualStrings("older", recent[1].workout.id.bytes);

    var insufficient_storage: [1]ExercisePerformance = undefined;
    try std.testing.expectError(
        error.OutputLimitReached,
        recentPerformances(
            history.snapshot(),
            history.exercise_id,
            &insufficient_storage,
        ),
    );
}

test "equal completion timestamps use stable workout ID ordering" {
    var history: TestHistory = undefined;
    try history.init();
    history.workouts[0].completed_at = try .parse("2026-07-24T11:00:00Z");
    history.workouts[1].completed_at = history.workouts[0].completed_at;
    history.workouts[0].id = try .parse("z-workout");
    history.workouts[1].id = try .parse("a-workout");

    const last = lastCompletedExercise(history.snapshot(), history.exercise_id).?;
    try std.testing.expectEqualStrings("a-workout", last.workout.id.bytes);

    var storage: [2]ExercisePerformance = undefined;
    const recent = try recentPerformances(history.snapshot(), history.exercise_id, &storage);
    try std.testing.expectEqualStrings("a-workout", recent[0].workout.id.bytes);
    try std.testing.expectEqualStrings("z-workout", recent[1].workout.id.bytes);
}

test "recency is relative to explicit as-of instant" {
    const result = try recency(
        try .parse("2026-07-24T11:00:00Z"),
        try .parse("2026-07-25T11:00:00Z"),
    );
    try std.testing.expectEqual(@as(u64, 86_400), result.elapsed_seconds);
    try std.testing.expectError(
        error.FuturePerformance,
        recency(
            try .parse("2026-07-26T11:00:00Z"),
            try .parse("2026-07-25T11:00:00Z"),
        ),
    );
}

test "compatible-unit volume is exact and rejects mixed units" {
    var history: TestHistory = undefined;
    try history.init();
    const performance = lastCompletedExercise(history.snapshot(), history.exercise_id).?;
    const volume = try compatibleUnitVolume(performance, .kg);
    try std.testing.expectEqual(primitives.Decimal{ .mantissa = 1220, .scale = 0 }, volume.value);

    history.metrics[0].value.unit = .lb;
    try std.testing.expectError(
        error.IncompatibleUnit,
        compatibleUnitVolume(performance, .kg),
    );

    history.metrics[0].value = .{
        .value = .{ .mantissa = std.math.maxInt(i64), .scale = 0 },
        .unit = .kg,
    };
    history.metrics[1].value.value = .{ .mantissa = 2, .scale = 0 };
    try std.testing.expectError(
        error.Overflow,
        compatibleUnitVolume(performance, .kg),
    );
}

test "best completed load respects inclusive rep range" {
    var history: TestHistory = undefined;
    try history.init();
    const best = (try bestCompletedLoad(
        history.snapshot(),
        history.exercise_id,
        5,
        8,
        .kg,
    )).?;
    try std.testing.expectEqual(primitives.Decimal{ .mantissa = 100, .scale = 0 }, best.value);
}

test "Epley estimate identifies formula and rounds deterministically" {
    const estimate = try estimateOneRepMaxEpley(
        .{ .value = try .parse("100"), .unit = .kg },
        5,
    );
    try std.testing.expectEqualStrings("epley", estimate.formula.id());
    try std.testing.expectEqual(
        primitives.Decimal{ .mantissa = 116_667, .scale = 3 },
        estimate.value.value,
    );
    try std.testing.expectError(
        error.InvalidMetric,
        estimateOneRepMaxEpley(
            .{ .value = try .parse("100"), .unit = .s },
            5,
        ),
    );
}
