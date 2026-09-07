//! Deterministic, explainable estimates of training readiness.
//!
//! Readiness is a policy-relative estimate derived from completed training and
//! host observations. It is not a measurement of biological recovery. Volume
//! credit is consumed from `volume.State`; this module never recreates volume
//! accounting or treats prescribed work as completed work.

const std = @import("std");
const primitives = @import("primitives.zig");
const training = @import("training.zig");
const volume = @import("volume.zig");

pub const readiness_units: u32 = 1_000_000;
pub const max_observations: usize = 512;
pub const max_completed_sets: usize = volume.max_contributions;
pub const max_factors: usize = 2 * volume.max_contributions + max_observations + 3;

pub const Confidence = enum { low, moderate, high };
pub const Status = enum { unknown, highly_ready, sufficiently_ready, partially_recovered, substantially_fatigued };
pub const Direction = enum { increased_readiness, decreased_readiness, reduced_confidence, conflicting };
pub const Level = enum(u8) { very_low, low, moderate, high, very_high };

pub const Subject = union(enum) {
    muscle: primitives.Id,
    systemic,
};

pub const ObservationKind = enum {
    soreness,
    subjective_readiness,
    perceived_fatigue,
    sleep_quality,
    performance_relative_to_expected,
};

/// Temporary host evidence. `valid_for_seconds` is explicit so an observation
/// cannot silently become permanent. A later observation does not mutate an
/// earlier one; evaluation uses all non-expired evidence in the bounded window.
pub const Observation = struct {
    id: primitives.Id,
    subject: Subject,
    kind: ObservationKind,
    level: Level,
    observed_at: primitives.Timestamp,
    valid_for_seconds: u32,
};

pub const Policy = struct {
    id: primitives.Id,
    version: u32,
    evidence_window_seconds: u32 = 7 * 24 * 60 * 60,
    local_recovery_seconds: u32 = 72 * 60 * 60,
    systemic_recovery_seconds: u32 = 48 * 60 * 60,
    /// Readiness deficit caused by one stress-unit at age zero. These are
    /// transparent programming coefficients, not physiological constants.
    local_capacity_credit: u64 = 4 * volume.units_per_set,
    systemic_set_cost: u32 = readiness_units / 12,

    pub fn firstParty() Policy {
        return .{ .id = .{ .bytes = "caudex.baseline-recovery" }, .version = 1 };
    }
};

pub const FactorCode = enum {
    recent_completed_training,
    elapsed_recovery,
    soreness_observation,
    readiness_observation,
    fatigue_observation,
    sleep_observation,
    performance_observation,
    missing_effort,
    missing_exercise_demand,
    contradictory_observations,
    no_usable_evidence,
};

/// Structured provenance points back to real canonical source evidence.
pub const Factor = struct {
    code: FactorCode,
    direction: Direction,
    subject: Subject,
    observed_at: ?primitives.Timestamp = null,
    workout_id: ?primitives.Id = null,
    exercise_id: ?primitives.Id = null,
    set_id: ?primitives.Id = null,
    observation_id: ?primitives.Id = null,
    /// Policy-relative contribution in readiness millionths. This is an
    /// explanatory contribution, not a probability or biological percentage.
    magnitude: u32 = 0,
};

pub const LocalState = struct {
    muscle_id: primitives.Id,
    readiness: ?u32,
    fatigue: ?u32,
    status: Status,
    confidence: Confidence,
    last_meaningful_exposure: ?primitives.Timestamp,
    recent_training_stress: u64,
    factors: []const Factor,
};

pub const SystemicState = struct {
    readiness: ?u32,
    fatigue: ?u32,
    status: Status,
    confidence: Confidence,
    recent_training_stress: u64,
    factors: []const Factor,
};

pub const State = struct {
    policy_id: primitives.Id,
    policy_version: u32,
    as_of: primitives.Timestamp,
    source_volume_policy_id: primitives.Id,
    source_volume_policy_version: u32,
    muscles: []const LocalState,
    systemic: SystemicState,

    pub fn find(self: State, muscle_id: primitives.Id) ?*const LocalState {
        for (self.muscles) |*item| if (item.muscle_id.eql(muscle_id)) return item;
        return null;
    }
};

pub const OwnedState = struct {
    arena: std.heap.ArenaAllocator,
    state: State,

    pub fn deinit(self: *OwnedState) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const Inputs = struct {
    as_of: primitives.Timestamp,
    catalog: training.ExerciseCatalog,
    history: training.HistorySnapshot,
    volume_state: volume.State,
    observations: []const Observation = &.{},
    policy: Policy = Policy.firstParty(),
};

pub const EvaluateError = error{
    OutOfMemory,
    InvalidPolicy,
    TooManyObservations,
    MissingExercise,
    MissingCompletedContribution,
    FutureEvidence,
    InvalidObservation,
    DuplicateObservation,
    TooMuchHistory,
    TooManyFactors,
    Overflow,
};

pub fn evaluate(backing_allocator: std.mem.Allocator, inputs: Inputs) EvaluateError!OwnedState {
    try validate(inputs);
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();

    var local_states = std.ArrayList(LocalState).empty;
    for (inputs.volume_state.muscles) |muscle| {
        try local_states.append(allocator, try evaluateLocal(allocator, inputs, muscle.muscle_id));
    }
    for (inputs.observations) |observation| switch (observation.subject) {
        .muscle => |muscle_id| {
            for (local_states.items) |state| if (state.muscle_id.eql(muscle_id)) break else {} else try local_states.append(allocator, try evaluateLocal(allocator, inputs, muscle_id));
        },
        .systemic => {},
    };
    std.mem.sort(LocalState, local_states.items, {}, lessLocal);
    const systemic = try evaluateSystemic(allocator, inputs);
    return .{ .arena = arena, .state = .{
        .policy_id = inputs.policy.id,
        .policy_version = inputs.policy.version,
        .as_of = inputs.as_of,
        .source_volume_policy_id = inputs.volume_state.policy_id,
        .source_volume_policy_version = inputs.volume_state.policy_version,
        .muscles = try local_states.toOwnedSlice(allocator),
        .systemic = systemic,
    } };
}

fn evaluateLocal(allocator: std.mem.Allocator, inputs: Inputs, muscle_id: primitives.Id) EvaluateError!LocalState {
    var factors = std.ArrayList(Factor).empty;
    var deficit: u64 = 0;
    var stress: u64 = 0;
    var last_exposure: ?primitives.Timestamp = null;
    var completed_count: u32 = 0;
    var effort_count: u32 = 0;
    var demand_count: u32 = 0;

    for (inputs.volume_state.contributions) |contribution| {
        if (contribution.phase != .completed or !contribution.muscle_id.eql(muscle_id)) continue;
        const source = findContributionSource(inputs.history, contribution) orelse
            return error.MissingCompletedContribution;
        const age = try evidenceAge(inputs.as_of, source.at);
        if (age > inputs.policy.evidence_window_seconds) continue;
        const exercise = inputs.catalog.find(contribution.exercise_id) orelse return error.MissingExercise;
        const demand = localDemand(exercise.*);
        if (demand.known) demand_count += 1;
        const effort = effortMultiplier(source.set.*);
        if (effort.known) effort_count += 1;
        const transformed = try scaleCredit(contribution.credit, demand.multiplier, effort.multiplier);
        stress = std.math.add(u64, stress, transformed) catch return error.Overflow;
        const initial = @min(@as(u64, readiness_units), transformed * readiness_units / inputs.policy.local_capacity_credit);
        const remaining = linearRemaining(initial, age, inputs.policy.local_recovery_seconds);
        deficit = @min(@as(u64, readiness_units), deficit + remaining);
        completed_count += 1;
        if (last_exposure == null or source.at.unixSeconds() > last_exposure.?.unixSeconds())
            last_exposure = source.at;
        try appendFactor(&factors, allocator, .{
            .code = .recent_completed_training,
            .direction = .decreased_readiness,
            .subject = .{ .muscle = muscle_id },
            .observed_at = source.at,
            .workout_id = contribution.workout_id,
            .exercise_id = contribution.exercise_id,
            .set_id = contribution.set_id,
            .magnitude = @intCast(remaining),
        });
        if (age != 0 and initial > remaining) try appendFactor(&factors, allocator, .{
            .code = .elapsed_recovery,
            .direction = .increased_readiness,
            .subject = .{ .muscle = muscle_id },
            .observed_at = inputs.as_of,
            .magnitude = @intCast(initial - remaining),
        });
    }

    var observation_count: u32 = 0;
    var positive = false;
    var negative = false;
    for (inputs.observations) |observation| {
        const observed_muscle = switch (observation.subject) {
            .muscle => |id| id,
            .systemic => continue,
        };
        if (!observed_muscle.eql(muscle_id) or !try observationActive(inputs, observation)) continue;
        observation_count += 1;
        try applyObservation(&deficit, &factors, allocator, observation);
        const effect = observationEffect(observation);
        positive = positive or effect < 0;
        negative = negative or effect > 0;
    }
    if (positive and negative) try appendFactor(&factors, allocator, .{
        .code = .contradictory_observations,
        .direction = .conflicting,
        .subject = .{ .muscle = muscle_id },
    });
    const evidence_count = completed_count + observation_count;
    if (evidence_count == 0) try appendFactor(&factors, allocator, .{
        .code = .no_usable_evidence,
        .direction = .reduced_confidence,
        .subject = .{ .muscle = muscle_id },
    });
    if (completed_count != 0 and effort_count != completed_count) try appendFactor(&factors, allocator, .{
        .code = .missing_effort,
        .direction = .reduced_confidence,
        .subject = .{ .muscle = muscle_id },
    });
    if (completed_count != 0 and demand_count != completed_count) try appendFactor(&factors, allocator, .{
        .code = .missing_exercise_demand,
        .direction = .reduced_confidence,
        .subject = .{ .muscle = muscle_id },
    });
    const score: ?u32 = if (evidence_count == 0) null else @intCast(readiness_units - @min(deficit, readiness_units));
    return .{
        .muscle_id = muscle_id,
        .readiness = score,
        .fatigue = if (score) |value| readiness_units - value else null,
        .status = status(score),
        .confidence = confidence(completed_count, observation_count, effort_count, demand_count, positive and negative),
        .last_meaningful_exposure = last_exposure,
        .recent_training_stress = stress,
        .factors = try factors.toOwnedSlice(allocator),
    };
}

fn evaluateSystemic(allocator: std.mem.Allocator, inputs: Inputs) EvaluateError!SystemicState {
    var factors = std.ArrayList(Factor).empty;
    var deficit: u64 = 0;
    var stress: u64 = 0;
    var completed_count: u32 = 0;
    var effort_count: u32 = 0;
    var demand_count: u32 = 0;
    for (inputs.history.workouts) |workout| {
        for (workout.exercises) |completed_exercise| {
            const exercise = inputs.catalog.find(completed_exercise.exercise_id) orelse return error.MissingExercise;
            const demand = systemicDemand(exercise.*);
            for (completed_exercise.sets) |*set| {
                if (set.status == .skipped) continue;
                const at = set.completed_at orelse workout.completed_at;
                const age = try evidenceAge(inputs.as_of, at);
                if (age > inputs.policy.evidence_window_seconds) continue;
                const effort = effortMultiplier(set.*);
                if (effort.known) effort_count += 1;
                if (demand.known) demand_count += 1;
                const set_stress = @as(u64, inputs.policy.systemic_set_cost) * demand.multiplier * effort.multiplier / 1_000_000;
                stress = std.math.add(u64, stress, set_stress) catch return error.Overflow;
                const remaining = linearRemaining(set_stress, age, inputs.policy.systemic_recovery_seconds);
                deficit = @min(@as(u64, readiness_units), deficit + remaining);
                completed_count += 1;
                try appendFactor(&factors, allocator, .{
                    .code = .recent_completed_training,
                    .direction = .decreased_readiness,
                    .subject = .systemic,
                    .observed_at = at,
                    .workout_id = workout.id,
                    .exercise_id = completed_exercise.exercise_id,
                    .set_id = set.id,
                    .magnitude = @intCast(@min(remaining, readiness_units)),
                });
            }
        }
    }
    var observation_count: u32 = 0;
    var positive = false;
    var negative = false;
    for (inputs.observations) |observation| {
        switch (observation.subject) {
            .systemic => {},
            .muscle => continue,
        }
        if (!try observationActive(inputs, observation)) continue;
        observation_count += 1;
        try applyObservation(&deficit, &factors, allocator, observation);
        const effect = observationEffect(observation);
        positive = positive or effect < 0;
        negative = negative or effect > 0;
    }
    if (positive and negative) try appendFactor(&factors, allocator, .{
        .code = .contradictory_observations,
        .direction = .conflicting,
        .subject = .systemic,
    });
    const evidence_count = completed_count + observation_count;
    if (evidence_count == 0) try appendFactor(&factors, allocator, .{
        .code = .no_usable_evidence,
        .direction = .reduced_confidence,
        .subject = .systemic,
    });
    if (completed_count != 0 and effort_count != completed_count) try appendFactor(&factors, allocator, .{
        .code = .missing_effort,
        .direction = .reduced_confidence,
        .subject = .systemic,
    });
    if (completed_count != 0 and demand_count != completed_count) try appendFactor(&factors, allocator, .{
        .code = .missing_exercise_demand,
        .direction = .reduced_confidence,
        .subject = .systemic,
    });
    const score: ?u32 = if (evidence_count == 0) null else @intCast(readiness_units - @min(deficit, readiness_units));
    return .{
        .readiness = score,
        .fatigue = if (score) |value| readiness_units - value else null,
        .status = status(score),
        .confidence = confidence(completed_count, observation_count, effort_count, demand_count, positive and negative),
        .recent_training_stress = stress,
        .factors = try factors.toOwnedSlice(allocator),
    };
}

const Source = struct { at: primitives.Timestamp, set: *const training.CompletedSet };

fn findContributionSource(history: training.HistorySnapshot, contribution: volume.Contribution) ?Source {
    for (history.workouts) |workout| {
        if (!workout.id.eql(contribution.workout_id)) continue;
        for (workout.exercises) |exercise| {
            if (!exercise.exercise_id.eql(contribution.exercise_id)) continue;
            for (exercise.sets) |*set| {
                if (contribution.set_id) |id| {
                    if (set.id == null or !set.id.?.eql(id)) continue;
                } else if (set.id != null) continue;
                return .{ .at = set.completed_at orelse workout.completed_at, .set = set };
            }
        }
    }
    return null;
}

const Multiplier = struct { multiplier: u64, known: bool };

fn localDemand(exercise: training.Exercise) Multiplier {
    const fatigue = if (exercise.knowledge) |knowledge| knowledge.fatigue else null;
    const value = if (fatigue) |item| item.localMuscular else null;
    return if (value) |demand| demandMultiplier(demand) else .{ .multiplier = 1_000, .known = false };
}

fn systemicDemand(exercise: training.Exercise) Multiplier {
    const fatigue = if (exercise.knowledge) |knowledge| knowledge.fatigue else null;
    if (fatigue) |item| if (item.systemic) |value| return demandMultiplier(value);
    if (exercise.knowledge) |knowledge| if (knowledge.structuralType) |kind| return switch (kind) {
        .compound, .locomotor, .conditioning => .{ .multiplier = 1_150, .known = true },
        .isolation, .mobility => .{ .multiplier = 700, .known = true },
        else => .{ .multiplier = 1_000, .known = false },
    };
    return .{ .multiplier = 1_000, .known = false };
}

fn demandMultiplier(demand: anytype) Multiplier {
    return switch (demand) {
        .low => .{ .multiplier = 750, .known = true },
        .moderate => .{ .multiplier = 1_000, .known = true },
        .high => .{ .multiplier = 1_250, .known = true },
        .unknown => .{ .multiplier = 1_000, .known = false },
    };
}

fn effortMultiplier(set: training.CompletedSet) Multiplier {
    for (set.actual_metrics) |metric| {
        const value = metric.value.value;
        if (metric.value.unit == .rir) {
            const whole = @divTrunc(decimalTenths(value), 10);
            return .{ .multiplier = if (whole <= 0) 1_250 else if (whole <= 2) 1_125 else if (whole <= 4) 1_000 else 875, .known = true };
        }
        if (metric.value.unit == .rpe) {
            const tenths = decimalTenths(value);
            return .{ .multiplier = if (tenths >= 95) 1_250 else if (tenths >= 85) 1_125 else if (tenths >= 70) 1_000 else 875, .known = true };
        }
    }
    return .{ .multiplier = if (set.status == .failed) 1_250 else if (set.status == .partial) 1_100 else 1_000, .known = set.status != .completed };
}

fn decimalTenths(value: primitives.Decimal) i64 {
    if (value.scale == 0) return std.math.mul(i64, value.mantissa, 10) catch
        if (value.mantissa < 0) std.math.minInt(i64) else std.math.maxInt(i64);
    var divisor: i64 = 1;
    var remaining = value.scale - 1;
    while (remaining > 0) : (remaining -= 1) divisor = std.math.mul(i64, divisor, 10) catch
        return 0;
    return @divTrunc(value.mantissa, divisor);
}

fn scaleCredit(credit: u64, demand: u64, effort: u64) EvaluateError!u64 {
    const first = std.math.mul(u64, credit, demand) catch return error.Overflow;
    const second = std.math.mul(u64, first / 1_000, effort) catch return error.Overflow;
    return second / 1_000;
}

fn linearRemaining(initial: u64, age_seconds: u64, recovery_seconds: u32) u64 {
    if (age_seconds >= recovery_seconds) return 0;
    return initial * (recovery_seconds - age_seconds) / recovery_seconds;
}

fn observationActive(inputs: Inputs, observation: Observation) EvaluateError!bool {
    const age = try evidenceAge(inputs.as_of, observation.observed_at);
    return age <= observation.valid_for_seconds and age <= inputs.policy.evidence_window_seconds;
}

fn observationEffect(observation: Observation) i64 {
    const centered = @as(i64, @intFromEnum(observation.level)) - 2;
    return switch (observation.kind) {
        .soreness, .perceived_fatigue => centered * 100_000,
        .subjective_readiness, .sleep_quality, .performance_relative_to_expected => -centered * 100_000,
    };
}

fn applyObservation(
    deficit: *u64,
    factors: *std.ArrayList(Factor),
    allocator: std.mem.Allocator,
    observation: Observation,
) EvaluateError!void {
    const effect = observationEffect(observation);
    if (effect > 0) deficit.* = @min(@as(u64, readiness_units), deficit.* + @as(u64, @intCast(effect)));
    if (effect < 0) deficit.* -|= @as(u64, @intCast(-effect));
    try appendFactor(factors, allocator, .{
        .code = switch (observation.kind) {
            .soreness => .soreness_observation,
            .subjective_readiness => .readiness_observation,
            .perceived_fatigue => .fatigue_observation,
            .sleep_quality => .sleep_observation,
            .performance_relative_to_expected => .performance_observation,
        },
        .direction = if (effect > 0) .decreased_readiness else if (effect < 0) .increased_readiness else .conflicting,
        .subject = observation.subject,
        .observed_at = observation.observed_at,
        .observation_id = observation.id,
        .magnitude = @intCast(@abs(effect)),
    });
}

fn confidence(completed: u32, observations: u32, effort: u32, demand: u32, contradictory: bool) Confidence {
    if (contradictory) return .low;
    if (completed >= 4 and observations != 0 and effort * 2 >= completed and demand * 2 >= completed) return .high;
    if (completed != 0 or observations != 0) return .moderate;
    return .low;
}

fn status(score: ?u32) Status {
    const value = score orelse return .unknown;
    if (value >= 800_000) return .highly_ready;
    if (value >= 600_000) return .sufficiently_ready;
    if (value >= 300_000) return .partially_recovered;
    return .substantially_fatigued;
}

fn evidenceAge(as_of: primitives.Timestamp, at: primitives.Timestamp) EvaluateError!u64 {
    const difference = as_of.unixSeconds() - at.unixSeconds();
    if (difference < 0) return error.FutureEvidence;
    return @intCast(difference);
}

fn appendFactor(list: *std.ArrayList(Factor), allocator: std.mem.Allocator, factor: Factor) EvaluateError!void {
    if (list.items.len == max_factors) return error.TooManyFactors;
    list.append(allocator, factor) catch return error.OutOfMemory;
}

fn validate(inputs: Inputs) EvaluateError!void {
    _ = primitives.Id.parse(inputs.policy.id.bytes) catch return error.InvalidPolicy;
    if (inputs.policy.version == 0 or
        inputs.policy.evidence_window_seconds == 0 or inputs.policy.local_recovery_seconds == 0 or
        inputs.policy.systemic_recovery_seconds == 0 or inputs.policy.local_capacity_credit == 0 or
        inputs.policy.systemic_set_cost == 0 or inputs.policy.systemic_set_cost > readiness_units)
        return error.InvalidPolicy;
    if (inputs.observations.len > max_observations) return error.TooManyObservations;
    var completed_set_count: usize = 0;
    for (inputs.history.workouts) |workout| {
        _ = try evidenceAge(inputs.as_of, workout.completed_at);
        for (workout.exercises) |exercise| {
            for (exercise.sets) |set| {
                completed_set_count = std.math.add(usize, completed_set_count, 1) catch
                    return error.TooMuchHistory;
                if (completed_set_count > max_completed_sets) return error.TooMuchHistory;
                if (set.completed_at) |at| _ = try evidenceAge(inputs.as_of, at);
            }
        }
    }
    for (inputs.observations, 0..) |observation, index| {
        if (observation.valid_for_seconds == 0) return error.InvalidObservation;
        _ = try evidenceAge(inputs.as_of, observation.observed_at);
        for (inputs.observations[0..index]) |prior| {
            if (prior.id.eql(observation.id)) return error.DuplicateObservation;
        }
    }
}

fn lessLocal(_: void, left: LocalState, right: LocalState) bool {
    return std.mem.order(u8, left.muscle_id.bytes, right.muscle_id.bytes) == .lt;
}

test "fresh athlete is explicitly unknown rather than fully recovered" {
    const as_of = try primitives.Timestamp.parse("2026-08-23T12:00:00Z");
    const empty_volume = volume.State{
        .policy_id = volume.CreditPolicy.firstParty().id,
        .policy_version = 1,
        .scope = .all_history,
        .muscles = &.{},
        .contributions = &.{},
    };
    var result = try evaluate(std.testing.allocator, .{
        .as_of = as_of,
        .catalog = .{ .exercises = &.{} },
        .history = .{},
        .volume_state = empty_volume,
    });
    defer result.deinit();
    try std.testing.expectEqual(Status.unknown, result.state.systemic.status);
    try std.testing.expectEqual(Confidence.low, result.state.systemic.confidence);
    try std.testing.expectEqual(@as(?u32, null), result.state.systemic.readiness);
}

test "completed compound work lowers distinct local and systemic readiness then time recovers" {
    const quad = try primitives.Id.parse("quadriceps");
    const glute = try primitives.Id.parse("gluteus-maximus");
    const squat_id = try primitives.Id.parse("barbell-squat");
    const set_id = try primitives.Id.parse("set-1");
    const rpe = [_]training.Metric{.{ .code = try .parse("rpe"), .value = .{ .value = try .parse("9"), .unit = .rpe } }};
    const sets = [_]training.CompletedSet{.{ .id = set_id, .kind = try .parse("working"), .actual_metrics = &rpe, .status = .completed }};
    const completed_exercises = [_]training.CompletedExercise{.{ .exercise_id = squat_id, .sets = &sets }};
    const workouts = [_]training.CompletedWorkout{.{
        .id = try .parse("workout-1"),
        .started_at = try .parse("2026-08-22T11:30:00Z"),
        .completed_at = try .parse("2026-08-22T12:00:00Z"),
        .exercises = &completed_exercises,
    }};
    const contributions = [_]training.MuscleContribution{
        .{ .muscle_id = quad, .role = .primary }, .{ .muscle_id = glute, .role = .secondary },
    };
    const exercises = [_]training.Exercise{.{
        .id = squat_id,
        .muscle_contributions = &contributions,
        .knowledge = .{ .structuralType = .compound, .fatigue = .{ .localMuscular = .high, .systemic = .high } },
    }};
    var credited = try volume.calculate(std.testing.allocator, .{
        .catalog = .{ .exercises = &exercises },
        .history = .{ .workouts = &workouts },
    });
    defer credited.deinit();
    var recent = try evaluate(std.testing.allocator, .{
        .as_of = try .parse("2026-08-22T13:00:00Z"),
        .catalog = .{ .exercises = &exercises },
        .history = .{ .workouts = &workouts },
        .volume_state = credited.state,
    });
    defer recent.deinit();
    try std.testing.expect(recent.state.find(quad).?.readiness.? < recent.state.find(glute).?.readiness.?);
    try std.testing.expect(recent.state.systemic.readiness.? < readiness_units);
    var later = try evaluate(std.testing.allocator, .{
        .as_of = try .parse("2026-08-25T13:00:00Z"),
        .catalog = .{ .exercises = &exercises },
        .history = .{ .workouts = &workouts },
        .volume_state = credited.state,
    });
    defer later.deinit();
    try std.testing.expect(later.state.find(quad).?.readiness.? > recent.state.find(quad).?.readiness.?);
    try std.testing.expectEqual(readiness_units, later.state.systemic.readiness.?);
}

test "soreness expires and skipped work creates no systemic stress" {
    const quad = try primitives.Id.parse("quadriceps");
    const observation = Observation{
        .id = try .parse("obs-1"),
        .subject = .{ .muscle = quad },
        .kind = .soreness,
        .level = .high,
        .observed_at = try .parse("2026-08-20T12:00:00Z"),
        .valid_for_seconds = 24 * 60 * 60,
    };
    const empty_volume = volume.State{
        .policy_id = volume.CreditPolicy.firstParty().id,
        .policy_version = 1,
        .scope = .all_history,
        .muscles = &.{},
        .contributions = &.{},
    };
    var result = try evaluate(std.testing.allocator, .{
        .as_of = try .parse("2026-08-23T12:00:00Z"),
        .catalog = .{ .exercises = &.{} },
        .history = .{},
        .volume_state = empty_volume,
        .observations = &.{observation},
    });
    defer result.deinit();
    try std.testing.expectEqual(Status.unknown, result.state.find(quad).?.status);
}
