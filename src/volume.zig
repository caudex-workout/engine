//! Deterministic muscle-volume accounting.
//!
//! Raw set events remain canonical history. This module derives policy-specific
//! muscle credit without rewriting that history. A tracked set is one raw work
//! event even for unilateral exercises; side-specific repetitions do not create
//! extra sets unless the host recorded separate set events.

const std = @import("std");
const primitives = @import("primitives.zig");
const training = @import("training.zig");

pub const units_per_set: u64 = 1_000_000;
pub const max_muscles: usize = 128;
pub const max_contributions: usize = 32_768;
pub const max_credit_per_muscle_per_set: u64 = 100 * units_per_set;
pub const max_state_credit: u64 = max_contributions * max_credit_per_muscle_per_set;

pub const PolicyMode = enum { role_credit, catalog_weight, direct_only };

/// Credits are millionths of a set-equivalent. They are programming heuristics,
/// not physiological percentages or claims about "effective sets".
pub const CreditPolicy = struct {
    id: primitives.Id,
    version: u32,
    mode: PolicyMode = .role_credit,
    primary_credit: u64 = units_per_set,
    secondary_credit: u64 = units_per_set / 2,
    stabilizer_credit: u64 = 0,
    custom_credit: u64 = 0,
    count_partial: bool = false,
    count_failed: bool = false,
    qualifying_set_kinds: []const primitives.Id = &.{
        .{ .bytes = "working" },
        .{ .bytes = "top" },
        .{ .bytes = "backoff" },
    },
    maximum_credit_per_muscle_per_set: u64 = units_per_set,

    pub fn firstParty() CreditPolicy {
        return .{ .id = .{ .bytes = "caudex.contribution-sets" }, .version = 1 };
    }
};

pub const Scope = union(enum) {
    all_history,
    interval: struct { from: primitives.Timestamp, through: primitives.Timestamp },
    /// The supplied snapshots are already bounded to this asynchronous program
    /// window. Identity is retained so consumers never infer a calendar week.
    program_window: struct {
        instance_id: primitives.Id,
        block_id: primitives.Id,
        microcycle_index: u32,
    },
};

pub const TargetSource = struct {
    kind: enum { program_template, program_strategy, block, athlete_override, temporary_adjustment },
    id: primitives.Id,
    version: ?u32 = null,
};

pub const Target = struct {
    muscle_id: primitives.Id,
    minimum: ?u64 = null,
    preferred_minimum: ?u64 = null,
    preferred_maximum: ?u64 = null,
    hard_cap: ?u64 = null,
    desired_exposures: ?u16 = null,
    priority_weight: ?u16 = null,
    source: TargetSource,
};

pub const Status = enum {
    no_target,
    below_minimum,
    below_preferred,
    within_preferred,
    above_preferred,
    within_limits,
    at_hard_cap,
    above_hard_cap,
};

pub const Remaining = struct {
    required: ?u64,
    preferred: ?u64,
    maximum_additional: ?u64,
};

pub const Observation = struct {
    muscle_id: primitives.Id,
    prescribed_raw_sets: u32 = 0,
    completed_raw_sets: u32 = 0,
    direct_raw_sets: u32 = 0,
    indirect_raw_sets: u32 = 0,
    prescribed_credit: u64 = 0,
    completed_credit: u64 = 0,
    prescribed_exposure_count: u16 = 0,
    exposure_count: u16 = 0,
    remaining_exposures: ?u16 = null,
    last_exposure: ?primitives.Timestamp = null,
    target: ?Target = null,
    remaining: Remaining = .{ .required = null, .preferred = null, .maximum_additional = null },
    excess_above_preferred: u64 = 0,
    status: Status = .no_target,
};

pub const ContributionPhase = enum { prescribed, completed };

pub const Contribution = struct {
    phase: ContributionPhase,
    muscle_id: primitives.Id,
    workout_id: primitives.Id,
    exercise_id: primitives.Id,
    set_id: ?primitives.Id,
    role: training.MuscleRole,
    credit: u64,
};

/// Explicit prescribed source. This is intentionally separate from completed
/// history so added work and skipped prescription cannot be confused.
pub const PrescribedSet = struct { id: ?primitives.Id = null, kind: primitives.Id };
pub const PrescribedExercise = struct { exercise_id: primitives.Id, sets: []const PrescribedSet };
pub const PrescribedWorkout = struct {
    id: primitives.Id,
    scheduled_at: primitives.Timestamp,
    exercises: []const PrescribedExercise,
};

pub const Inputs = struct {
    catalog: training.ExerciseCatalog,
    history: training.HistorySnapshot = .{},
    prescribed_workouts: []const PrescribedWorkout = &.{},
    targets: []const Target = &.{},
    policy: CreditPolicy = CreditPolicy.firstParty(),
    scope: Scope = .all_history,
};

pub const State = struct {
    policy_id: primitives.Id,
    policy_version: u32,
    scope: Scope,
    muscles: []const Observation,
    contributions: []const Contribution,

    pub fn find(self: State, muscle_id: primitives.Id) ?*const Observation {
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

pub const CalculateError = error{
    OutOfMemory,
    InvalidPolicy,
    InvalidScope,
    InvalidTarget,
    DuplicateTarget,
    MissingExercise,
    InvalidContribution,
    TooManyMuscles,
    TooManyContributions,
    Overflow,
};

pub fn calculate(backing_allocator: std.mem.Allocator, inputs: Inputs) CalculateError!OwnedState {
    try validateInputs(inputs);
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();
    var muscles = std.ArrayList(Observation).empty;
    var contributions = std.ArrayList(Contribution).empty;

    for (inputs.targets) |target| {
        try muscles.append(allocator, .{ .muscle_id = target.muscle_id, .target = target });
    }
    for (inputs.prescribed_workouts) |workout| {
        if (!includes(inputs.scope, workout.scheduled_at)) continue;
        for (workout.exercises) |exercise_work| {
            const exercise = inputs.catalog.find(exercise_work.exercise_id) orelse
                return error.MissingExercise;
            for (exercise_work.sets) |set| {
                if (!qualifiesKind(inputs.policy, set.kind)) continue;
                try creditSet(allocator, &muscles, &contributions, inputs.policy, exercise.*, .{
                    .phase = .prescribed,
                    .workout_id = workout.id,
                    .set_id = set.id,
                    .at = workout.scheduled_at,
                });
            }
        }
    }
    for (inputs.history.workouts) |workout| {
        if (!includes(inputs.scope, workout.completed_at)) continue;
        for (workout.exercises) |exercise_work| {
            const exercise = inputs.catalog.find(exercise_work.exercise_id) orelse
                return error.MissingExercise;
            for (exercise_work.sets) |set| {
                if (!qualifiesCompleted(inputs.policy, set)) continue;
                try creditSet(allocator, &muscles, &contributions, inputs.policy, exercise.*, .{
                    .phase = .completed,
                    .workout_id = workout.id,
                    .set_id = set.id,
                    .at = set.completed_at orelse workout.completed_at,
                });
            }
        }
    }
    for (muscles.items) |*observation| resolveTarget(observation);
    std.mem.sort(Observation, muscles.items, {}, lessObservation);
    std.mem.sort(Contribution, contributions.items, {}, lessContribution);
    if (muscles.items.len > max_muscles) return error.TooManyMuscles;
    if (contributions.items.len > max_contributions) return error.TooManyContributions;
    return .{ .arena = arena, .state = .{
        .policy_id = inputs.policy.id,
        .policy_version = inputs.policy.version,
        .scope = inputs.scope,
        .muscles = try muscles.toOwnedSlice(allocator),
        .contributions = try contributions.toOwnedSlice(allocator),
    } };
}

/// A proposal describes raw set events. `kind` is evaluated by the same policy
/// as retrospective work; non-qualifying proposals contribute no impact.
pub const ProposedWork = struct {
    exercise_id: primitives.Id,
    set_count: u16,
    kind: primitives.Id = .{ .bytes = "working" },
};
pub const Impact = struct { muscle_id: primitives.Id, raw_sets: u32, credit: u64 };
pub const OwnedImpact = struct {
    arena: std.heap.ArenaAllocator,
    muscles: []const Impact,
    pub fn deinit(self: *OwnedImpact) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn estimate(
    backing_allocator: std.mem.Allocator,
    catalog: training.ExerciseCatalog,
    work: []const ProposedWork,
    policy: CreditPolicy,
) CalculateError!OwnedImpact {
    try validatePolicy(policy);
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();
    var impacts = std.ArrayList(Impact).empty;
    var contribution_count: usize = 0;
    for (work) |item| {
        if (!qualifiesKind(policy, item.kind)) continue;
        const exercise = catalog.find(item.exercise_id) orelse return error.MissingExercise;
        for (exercise.muscle_contributions) |muscle| {
            contribution_count = std.math.add(usize, contribution_count, item.set_count) catch
                return error.TooManyContributions;
            if (contribution_count > max_contributions) return error.TooManyContributions;
            const credit = try contributionCredit(policy, muscle);
            const impact = try findOrAppendImpact(allocator, &impacts, muscle.muscle_id);
            impact.raw_sets = std.math.add(u32, impact.raw_sets, item.set_count) catch return error.Overflow;
            const added = std.math.mul(u64, credit, item.set_count) catch return error.Overflow;
            impact.credit = std.math.add(u64, impact.credit, added) catch return error.Overflow;
            if (impact.credit > max_state_credit) return error.Overflow;
        }
    }
    std.mem.sort(Impact, impacts.items, {}, lessImpact);
    return .{ .arena = arena, .muscles = try impacts.toOwnedSlice(allocator) };
}

pub const CapConflict = struct { muscle_id: primitives.Id, current: u64, proposed: u64, hard_cap: u64 };

pub fn firstCapConflict(state: State, impact: []const Impact) ?CapConflict {
    for (impact) |candidate| {
        const current = state.find(candidate.muscle_id) orelse continue;
        const cap = if (current.target) |target| target.hard_cap orelse continue else continue;
        const total = std.math.add(u64, current.completed_credit, candidate.credit) catch
            return .{ .muscle_id = candidate.muscle_id, .current = current.completed_credit, .proposed = candidate.credit, .hard_cap = cap };
        if (total > cap) return .{ .muscle_id = candidate.muscle_id, .current = current.completed_credit, .proposed = candidate.credit, .hard_cap = cap };
    }
    return null;
}

/// Non-allocating planner seam for candidate eligibility. Overflow is treated
/// conservatively as a conflict rather than permitting an unbounded proposal.
pub fn capConflictForExercise(
    state: State,
    exercise: training.Exercise,
    set_count: u16,
    policy: CreditPolicy,
) CalculateError!?CapConflict {
    try validatePolicy(policy);
    for (exercise.muscle_contributions) |contribution| {
        const observation = state.find(contribution.muscle_id) orelse continue;
        const cap = if (observation.target) |target| target.hard_cap orelse continue else continue;
        const per_set = try contributionCredit(policy, contribution);
        const proposed = std.math.mul(u64, per_set, set_count) catch return .{
            .muscle_id = contribution.muscle_id,
            .current = observation.completed_credit,
            .proposed = std.math.maxInt(u64),
            .hard_cap = cap,
        };
        const total = std.math.add(u64, observation.completed_credit, proposed) catch return .{
            .muscle_id = contribution.muscle_id,
            .current = observation.completed_credit,
            .proposed = proposed,
            .hard_cap = cap,
        };
        if (total > cap) return .{
            .muscle_id = contribution.muscle_id,
            .current = observation.completed_credit,
            .proposed = proposed,
            .hard_cap = cap,
        };
    }
    return null;
}

const SetContext = struct {
    phase: ContributionPhase,
    workout_id: primitives.Id,
    set_id: ?primitives.Id,
    at: primitives.Timestamp,
};

fn creditSet(
    allocator: std.mem.Allocator,
    muscles: *std.ArrayList(Observation),
    contributions: *std.ArrayList(Contribution),
    policy: CreditPolicy,
    exercise: training.Exercise,
    context: SetContext,
) CalculateError!void {
    for (exercise.muscle_contributions) |muscle| {
        const credit = try contributionCredit(policy, muscle);
        var prior_same_workout = false;
        for (contributions.items) |prior| {
            if (prior.phase == context.phase and prior.workout_id.eql(context.workout_id) and
                prior.muscle_id.eql(muscle.muscle_id))
            {
                prior_same_workout = true;
                break;
            }
        }
        const observation = try findOrAppendObservation(allocator, muscles, muscle.muscle_id);
        switch (context.phase) {
            .prescribed => {
                observation.prescribed_raw_sets = std.math.add(u32, observation.prescribed_raw_sets, 1) catch return error.Overflow;
                observation.prescribed_credit = std.math.add(u64, observation.prescribed_credit, credit) catch return error.Overflow;
                if (!prior_same_workout) observation.prescribed_exposure_count = std.math.add(u16, observation.prescribed_exposure_count, 1) catch return error.Overflow;
            },
            .completed => {
                observation.completed_raw_sets = std.math.add(u32, observation.completed_raw_sets, 1) catch return error.Overflow;
                if (muscle.role == .primary) observation.direct_raw_sets = std.math.add(u32, observation.direct_raw_sets, 1) catch return error.Overflow else observation.indirect_raw_sets = std.math.add(u32, observation.indirect_raw_sets, 1) catch return error.Overflow;
                observation.completed_credit = std.math.add(u64, observation.completed_credit, credit) catch return error.Overflow;
                if (observation.last_exposure == null or timestampLess(observation.last_exposure.?, context.at))
                    observation.last_exposure = context.at;
                if (!prior_same_workout) observation.exposure_count = std.math.add(u16, observation.exposure_count, 1) catch return error.Overflow;
            },
        }
        if (contributions.items.len == max_contributions) return error.TooManyContributions;
        try contributions.append(allocator, .{
            .phase = context.phase,
            .muscle_id = muscle.muscle_id,
            .workout_id = context.workout_id,
            .exercise_id = exercise.id,
            .set_id = context.set_id,
            .role = muscle.role,
            .credit = credit,
        });
    }
}

fn contributionCredit(policy: CreditPolicy, contribution: training.MuscleContribution) CalculateError!u64 {
    const credit = switch (policy.mode) {
        .direct_only => if (contribution.role == .primary) policy.primary_credit else 0,
        .role_credit => roleCredit(policy, contribution.role),
        .catalog_weight => if (contribution.weight) |weight|
            try decimalToUnits(weight)
        else
            roleCredit(policy, contribution.role),
    };
    if (credit > policy.maximum_credit_per_muscle_per_set) return error.InvalidContribution;
    return credit;
}

fn decimalToUnits(value: primitives.Decimal) CalculateError!u64 {
    if (value.mantissa < 0) return error.InvalidContribution;
    var numerator: u128 = @intCast(value.mantissa);
    numerator = std.math.mul(u128, numerator, units_per_set) catch return error.Overflow;
    var denominator: u128 = 1;
    var scale = value.scale;
    while (scale > 0) : (scale -= 1) denominator = std.math.mul(u128, denominator, 10) catch return error.Overflow;
    const rounded = std.math.add(u128, numerator, denominator / 2) catch return error.Overflow;
    const result = rounded / denominator;
    if (result > std.math.maxInt(u64)) return error.Overflow;
    return @intCast(result);
}

fn roleCredit(policy: CreditPolicy, role: training.MuscleRole) u64 {
    return switch (role) {
        .primary => policy.primary_credit,
        .secondary => policy.secondary_credit,
        .stabilizer => policy.stabilizer_credit,
        .custom => policy.custom_credit,
    };
}

fn validateInputs(inputs: Inputs) CalculateError!void {
    try validatePolicy(inputs.policy);
    switch (inputs.scope) {
        .interval => |interval| if (timestampLess(interval.through, interval.from))
            return error.InvalidScope,
        .all_history, .program_window => {},
    }
    for (inputs.catalog.exercises) |exercise| {
        for (exercise.muscle_contributions, 0..) |contribution, index| {
            _ = try contributionCredit(inputs.policy, contribution);
            for (exercise.muscle_contributions[0..index]) |prior| {
                if (prior.muscle_id.eql(contribution.muscle_id))
                    return error.InvalidContribution;
            }
        }
    }
    for (inputs.targets, 0..) |target, index| {
        if (!validTarget(target)) return error.InvalidTarget;
        for (inputs.targets[0..index]) |prior| if (prior.muscle_id.eql(target.muscle_id)) return error.DuplicateTarget;
    }
}

pub fn validatePolicy(policy: CreditPolicy) CalculateError!void {
    if (policy.version == 0 or policy.qualifying_set_kinds.len == 0 or
        policy.maximum_credit_per_muscle_per_set > max_credit_per_muscle_per_set or
        policy.primary_credit > policy.maximum_credit_per_muscle_per_set or
        policy.secondary_credit > policy.maximum_credit_per_muscle_per_set or
        policy.stabilizer_credit > policy.maximum_credit_per_muscle_per_set or
        policy.custom_credit > policy.maximum_credit_per_muscle_per_set) return error.InvalidPolicy;
}

pub fn validTarget(target: Target) bool {
    const minimum = target.minimum orelse 0;
    const preferred_minimum = target.preferred_minimum orelse minimum;
    const preferred_maximum = target.preferred_maximum orelse preferred_minimum;
    const cap = target.hard_cap orelse std.math.maxInt(u64);
    return minimum <= preferred_minimum and preferred_minimum <= preferred_maximum and preferred_maximum <= cap and
        minimum <= max_state_credit and preferred_minimum <= max_state_credit and
        preferred_maximum <= max_state_credit and (target.hard_cap orelse 0) <= max_state_credit and
        (target.priority_weight orelse 1) > 0;
}

fn resolveTarget(observation: *Observation) void {
    const target = observation.target orelse return;
    const current = observation.completed_credit;
    observation.remaining.required = remainingTo(current, target.minimum);
    observation.remaining.preferred = remainingTo(current, target.preferred_minimum orelse target.preferred_maximum);
    observation.remaining.maximum_additional = remainingTo(current, target.hard_cap);
    if (target.desired_exposures) |desired|
        observation.remaining_exposures = desired -| observation.exposure_count;
    if (target.preferred_maximum) |maximum| observation.excess_above_preferred = current -| maximum;
    observation.status = if (target.hard_cap) |cap| if (current > cap) .above_hard_cap else if (current == cap) .at_hard_cap else statusBelowCap(current, target) else statusBelowCap(current, target);
}

fn statusBelowCap(current: u64, target: Target) Status {
    if (target.minimum) |minimum| if (current < minimum) return .below_minimum;
    if (target.preferred_minimum) |minimum| if (current < minimum) return .below_preferred;
    if (target.preferred_maximum) |maximum| return if (current <= maximum) .within_preferred else .above_preferred;
    if (target.minimum != null or target.preferred_minimum != null) return .within_preferred;
    return .within_limits;
}

fn remainingTo(current: u64, target: ?u64) ?u64 {
    return if (target) |value| value -| current else null;
}
fn qualifiesKind(policy: CreditPolicy, kind: primitives.Id) bool {
    for (policy.qualifying_set_kinds) |candidate| if (candidate.eql(kind)) return true;
    return false;
}
fn qualifiesCompleted(policy: CreditPolicy, set: training.CompletedSet) bool {
    if (!qualifiesKind(policy, set.kind)) return false;
    return switch (set.status) {
        .completed => true,
        .partial => policy.count_partial,
        .failed => policy.count_failed,
        .skipped => false,
    };
}
fn includes(scope: Scope, at: primitives.Timestamp) bool {
    return switch (scope) {
        .all_history => true,
        .interval => |value| !timestampLess(at, value.from) and !timestampLess(value.through, at),
        .program_window => true,
    };
}
fn timestampLess(left: primitives.Timestamp, right: primitives.Timestamp) bool {
    return std.mem.lessThan(u8, left.bytes, right.bytes);
}

fn findObservation(items: []Observation, id: primitives.Id) ?*Observation {
    for (items) |*item| if (item.muscle_id.eql(id)) return item;
    return null;
}
fn findOrAppendObservation(allocator: std.mem.Allocator, items: *std.ArrayList(Observation), id: primitives.Id) CalculateError!*Observation {
    if (findObservation(items.items, id)) |item| return item;
    if (items.items.len == max_muscles) return error.TooManyMuscles;
    try items.append(allocator, .{ .muscle_id = id });
    return &items.items[items.items.len - 1];
}
fn findOrAppendImpact(allocator: std.mem.Allocator, items: *std.ArrayList(Impact), id: primitives.Id) CalculateError!*Impact {
    for (items.items) |*item| if (item.muscle_id.eql(id)) return item;
    if (items.items.len == max_muscles) return error.TooManyMuscles;
    try items.append(allocator, .{ .muscle_id = id, .raw_sets = 0, .credit = 0 });
    return &items.items[items.items.len - 1];
}
fn lessObservation(_: void, left: Observation, right: Observation) bool {
    return std.mem.lessThan(u8, left.muscle_id.bytes, right.muscle_id.bytes);
}
fn lessImpact(_: void, left: Impact, right: Impact) bool {
    return std.mem.lessThan(u8, left.muscle_id.bytes, right.muscle_id.bytes);
}
fn lessContribution(_: void, left: Contribution, right: Contribution) bool {
    if (left.phase != right.phase) return @intFromEnum(left.phase) < @intFromEnum(right.phase);
    if (!left.workout_id.eql(right.workout_id))
        return std.mem.lessThan(u8, left.workout_id.bytes, right.workout_id.bytes);
    if (!left.exercise_id.eql(right.exercise_id))
        return std.mem.lessThan(u8, left.exercise_id.bytes, right.exercise_id.bytes);
    const left_set = if (left.set_id) |id| id.bytes else "";
    const right_set = if (right.set_id) |id| id.bytes else "";
    if (!std.mem.eql(u8, left_set, right_set)) return std.mem.lessThan(u8, left_set, right_set);
    return std.mem.lessThan(u8, left.muscle_id.bytes, right.muscle_id.bytes);
}

test "first-party policy separates prescribed completed direct and indirect volume" {
    const chest = try primitives.Id.parse("chest");
    const triceps = try primitives.Id.parse("triceps");
    const exercise = training.Exercise{ .id = try .parse("bench"), .muscle_contributions = &.{
        .{ .muscle_id = chest, .role = .primary }, .{ .muscle_id = triceps, .role = .secondary },
    } };
    const sets = [_]training.CompletedSet{
        .{ .id = try .parse("s1"), .kind = try .parse("working"), .actual_metrics = &.{}, .status = .completed },
        .{ .id = try .parse("s2"), .kind = try .parse("working"), .actual_metrics = &.{}, .status = .skipped },
        .{ .id = try .parse("s3"), .kind = try .parse("warmup"), .actual_metrics = &.{}, .status = .completed },
    };
    const completed_exercises = [_]training.CompletedExercise{.{ .exercise_id = exercise.id, .sets = &sets }};
    const workouts = [_]training.CompletedWorkout{.{ .id = try .parse("w1"), .started_at = try .parse("2026-08-01T10:00:00Z"), .completed_at = try .parse("2026-08-01T11:00:00Z"), .exercises = &completed_exercises }};
    const prescribed_sets = [_]PrescribedSet{ .{ .id = try .parse("s1"), .kind = try .parse("working") }, .{ .id = try .parse("s2"), .kind = try .parse("working") } };
    const prescribed_exercises = [_]PrescribedExercise{.{ .exercise_id = exercise.id, .sets = &prescribed_sets }};
    const prescribed = [_]PrescribedWorkout{.{ .id = try .parse("w1"), .scheduled_at = try .parse("2026-08-01T10:00:00Z"), .exercises = &prescribed_exercises }};
    var owned = try calculate(std.testing.allocator, .{ .catalog = .{ .exercises = &.{exercise} }, .history = .{ .workouts = &workouts }, .prescribed_workouts = &prescribed });
    defer owned.deinit();
    const chest_volume = owned.state.find(chest).?;
    try std.testing.expectEqual(@as(u32, 2), chest_volume.prescribed_raw_sets);
    try std.testing.expectEqual(@as(u32, 1), chest_volume.completed_raw_sets);
    try std.testing.expectEqual(units_per_set, chest_volume.completed_credit);
    try std.testing.expectEqual(units_per_set / 2, owned.state.find(triceps).?.completed_credit);
    try std.testing.expectEqual(@as(u16, 1), chest_volume.exposure_count);
}

test "targets derive remaining status and prospective compound cap conflict" {
    const chest = try primitives.Id.parse("chest");
    const triceps = try primitives.Id.parse("triceps");
    const bench = training.Exercise{ .id = try .parse("bench"), .muscle_contributions = &.{
        .{ .muscle_id = chest, .role = .primary }, .{ .muscle_id = triceps, .role = .secondary },
    } };
    const targets = [_]Target{ .{ .muscle_id = chest, .minimum = 2 * units_per_set, .preferred_minimum = 3 * units_per_set, .preferred_maximum = 4 * units_per_set, .hard_cap = 5 * units_per_set, .source = .{ .kind = .program_strategy, .id = try .parse("strategy") } }, .{ .muscle_id = triceps, .hard_cap = units_per_set, .source = .{ .kind = .program_strategy, .id = try .parse("strategy") } } };
    var state = try calculate(std.testing.allocator, .{ .catalog = .{ .exercises = &.{bench} }, .targets = &targets });
    defer state.deinit();
    try std.testing.expectEqual(@as(?u64, 2 * units_per_set), state.state.find(chest).?.remaining.required);
    var impact = try estimate(std.testing.allocator, .{ .exercises = &.{bench} }, &.{.{ .exercise_id = bench.id, .set_count = 3 }}, .firstParty());
    defer impact.deinit();
    const conflict = firstCapConflict(state.state, impact.muscles).?;
    try std.testing.expect(conflict.muscle_id.eql(triceps));
}

test "catalog-weight policy is replayable without changing history" {
    const chest = try primitives.Id.parse("chest");
    const exercise = training.Exercise{ .id = try .parse("fly"), .muscle_contributions = &.{.{ .muscle_id = chest, .role = .primary, .weight = try .parse("0.75") }} };
    var role = try estimate(std.testing.allocator, .{ .exercises = &.{exercise} }, &.{.{ .exercise_id = exercise.id, .set_count = 2 }}, .firstParty());
    defer role.deinit();
    var weighted_policy = CreditPolicy.firstParty();
    weighted_policy.mode = .catalog_weight;
    var weighted = try estimate(std.testing.allocator, .{ .exercises = &.{exercise} }, &.{.{ .exercise_id = exercise.id, .set_count = 2 }}, weighted_policy);
    defer weighted.deinit();
    try std.testing.expectEqual(2 * units_per_set, role.muscles[0].credit);
    try std.testing.expectEqual(1_500_000, weighted.muscles[0].credit);
}

test "actual substitutions and added sets do not rewrite prescription" {
    const chest = try primitives.Id.parse("chest");
    const triceps = try primitives.Id.parse("triceps");
    const bench = training.Exercise{ .id = try .parse("bench"), .muscle_contributions = &.{
        .{ .muscle_id = chest, .role = .primary },
        .{ .muscle_id = triceps, .role = .secondary },
    } };
    const fly = training.Exercise{ .id = try .parse("fly"), .muscle_contributions = &.{
        .{ .muscle_id = chest, .role = .primary },
    } };
    const actual_sets = [_]training.CompletedSet{
        .{ .id = try .parse("replacement-1"), .kind = try .parse("working"), .actual_metrics = &.{}, .status = .completed },
        .{ .id = try .parse("athlete-added"), .kind = try .parse("working"), .actual_metrics = &.{}, .status = .completed },
    };
    const actual_exercises = [_]training.CompletedExercise{.{ .exercise_id = fly.id, .sets = &actual_sets }};
    const workouts = [_]training.CompletedWorkout{.{ .id = try .parse("workout"), .started_at = try .parse("2026-08-02T10:00:00Z"), .completed_at = try .parse("2026-08-02T11:00:00Z"), .exercises = &actual_exercises }};
    const original_sets = [_]PrescribedSet{
        .{ .id = try .parse("original-1"), .kind = try .parse("working") },
        .{ .id = try .parse("original-2"), .kind = try .parse("working") },
        .{ .id = try .parse("original-3"), .kind = try .parse("working") },
    };
    const original_exercises = [_]PrescribedExercise{.{ .exercise_id = bench.id, .sets = &original_sets }};
    const prescribed = [_]PrescribedWorkout{.{ .id = try .parse("workout"), .scheduled_at = try .parse("2026-08-02T10:00:00Z"), .exercises = &original_exercises }};
    var owned = try calculate(std.testing.allocator, .{
        .catalog = .{ .exercises = &.{ bench, fly } },
        .history = .{ .workouts = &workouts },
        .prescribed_workouts = &prescribed,
    });
    defer owned.deinit();
    try std.testing.expectEqual(3 * units_per_set, owned.state.find(chest).?.prescribed_credit);
    try std.testing.expectEqual(2 * units_per_set, owned.state.find(chest).?.completed_credit);
    try std.testing.expectEqual(3 * units_per_set / 2, owned.state.find(triceps).?.prescribed_credit);
    try std.testing.expectEqual(@as(u64, 0), owned.state.find(triceps).?.completed_credit);
}

test "explicit interval accumulates exposures without weekday assumptions" {
    const back = try primitives.Id.parse("back");
    const row = training.Exercise{ .id = try .parse("row"), .muscle_contributions = &.{.{ .muscle_id = back, .role = .primary }} };
    const set = [_]training.CompletedSet{.{ .kind = try .parse("working"), .actual_metrics = &.{}, .status = .completed }};
    const exercise = [_]training.CompletedExercise{.{ .exercise_id = row.id, .sets = &set }};
    const workouts = [_]training.CompletedWorkout{
        .{ .id = try .parse("before"), .started_at = try .parse("2026-07-29T10:00:00Z"), .completed_at = try .parse("2026-07-29T11:00:00Z"), .exercises = &exercise },
        .{ .id = try .parse("saturday"), .started_at = try .parse("2026-08-01T10:00:00Z"), .completed_at = try .parse("2026-08-01T11:00:00Z"), .exercises = &exercise },
        .{ .id = try .parse("tuesday"), .started_at = try .parse("2026-08-04T10:00:00Z"), .completed_at = try .parse("2026-08-04T11:00:00Z"), .exercises = &exercise },
    };
    var owned = try calculate(std.testing.allocator, .{
        .catalog = .{ .exercises = &.{row} },
        .history = .{ .workouts = &workouts },
        .scope = .{ .interval = .{
            .from = try .parse("2026-08-01T00:00:00Z"),
            .through = try .parse("2026-08-06T00:00:00Z"),
        } },
    });
    defer owned.deinit();
    try std.testing.expectEqual(2 * units_per_set, owned.state.find(back).?.completed_credit);
    try std.testing.expectEqual(@as(u16, 2), owned.state.find(back).?.exposure_count);
}
