//! Normalizes program-strategy intent and explicit session facts into the
//! immutable problem consumed by the planning solver.

const std = @import("std");
const primitives = @import("../primitives.zig");
const training = @import("../training.zig");
const program_intent = @import("../programs/intent.zig");
const hypertrophy = @import("../programs/hypertrophy.zig");
const model = @import("problem.zig");
const solver = @import("solver.zig");

pub const SessionContext = struct {
    /// The explicit instant at which the host is resolving this occurrence.
    as_of: primitives.Timestamp,
    catalog: training.ExerciseCatalog,
    /// Hard facts which are not strategy-specific. When a hypertrophy policy
    /// supplies equipment, it is the sole source of available equipment.
    constraints: model.SessionConstraints = .{},
    /// User preferences remain distinct from an adaptive slot's inline
    /// preferred set, which belongs to the program-correctness tier.
    exercise_preferences: []const ExercisePreference = &.{},
};

pub const ExercisePreference = struct {
    target: model.PreferenceTarget,
    direction: model.PreferenceDirection = .prefer,
    weight: u16,
};

pub const Storage = struct {
    objectives: []model.Objective,
    duration_estimates: []model.DurationEstimate,
};

pub const BuildError = error{
    EmptyIntent,
    TooManySlots,
    TooManyCatalogExercises,
    TooManyObjectives,
    TooManyDurationEstimates,
    TooManyAvailableEquipmentIds,
    TooManyMusclePriorities,
    ObjectiveStorageTooSmall,
    DurationStorageTooSmall,
    PolicyForNonAdaptiveIntent,
    AmbiguousAvailableEquipment,
    InvalidOrigin,
    InvalidConstraints,
    DuplicateSlotId,
    InvalidMusclePriorityWeight,
    DuplicateMusclePriority,
    InvalidExercisePreferenceWeight,
    DuplicateDurationEstimate,
    DurationEstimateForUnknownSlot,
};

/// Builds a planning problem without allocating. The returned problem borrows
/// the intent, context, policy, and populated prefixes of `storage`; all must
/// remain live through solving and use of the result.
pub fn build(
    intent: program_intent.PlannedSessionIntent,
    context: SessionContext,
    policy: ?hypertrophy.SessionPolicy,
    storage: Storage,
) BuildError!model.PlanningProblem {
    try validateIntent(intent);
    try validateContext(context);
    if (policy != null and intent.strategy != .adaptive_hypertrophy)
        return error.PolicyForNonAdaptiveIntent;

    const objective_count = try requiredObjectiveCount(context, policy);
    const duration_count = if (policy) |value| value.duration_estimates.len else 0;
    if (duration_count > solver.max_duration_estimates) return error.TooManyDurationEstimates;
    if (policy) |value| try validateDurationEstimates(intent.slots, value.duration_estimates);
    if (storage.objectives.len < objective_count) return error.ObjectiveStorageTooSmall;
    if (storage.duration_estimates.len < duration_count) return error.DurationStorageTooSmall;

    var constraints = context.constraints;
    if (policy) |value| {
        if (constraints.available_equipment_ids.len != 0 and
            value.available_equipment_ids.len != 0)
            return error.AmbiguousAvailableEquipment;
        if (value.available_equipment_ids.len != 0)
            constraints.available_equipment_ids = value.available_equipment_ids;
        if (value.hard_maximum_minutes) |maximum| {
            constraints.hard_maximum_minutes = if (constraints.hard_maximum_minutes) |existing|
                @min(existing, maximum)
            else
                maximum;
        }
    }

    var objective_count_written: usize = 0;
    for (context.exercise_preferences) |preference| {
        storage.objectives[objective_count_written] = .{ .exercise_preference = .{
            .target = preference.target,
            .direction = preference.direction,
            .weight = preference.weight,
        } };
        objective_count_written += 1;
    }
    if (policy) |value| {
        for (value.muscle_priorities) |priority| {
            storage.objectives[objective_count_written] = .{ .muscle_priority = .{
                .muscle_id = priority.muscle_id,
                .weight = priority.weight,
            } };
            objective_count_written += 1;
        }
        if (value.target_duration_minutes) |minutes| {
            storage.objectives[objective_count_written] = .{ .target_duration = .{
                .minutes = minutes,
                .weight = target_duration_weight,
            } };
            objective_count_written += 1;
        }
    }

    var duration_count_written: usize = 0;
    if (policy) |value| for (value.duration_estimates) |estimate| {
        storage.duration_estimates[duration_count_written] = .{
            .slot_id = estimate.slot_id,
            .exercise_id = estimate.exercise_id,
            .minutes = estimate.minutes,
        };
        duration_count_written += 1;
    };

    std.debug.assert(objective_count_written == objective_count);
    std.debug.assert(duration_count_written == duration_count);
    return .{
        .origin = .{
            .definition_id = intent.definition_id,
            .definition_version = intent.definition_version,
            .definition_fingerprint = intent.definition_fingerprint,
            .instance_id = intent.instance_id,
            .occurrence_id = intent.occurrence_id,
            .block_id = intent.block_id,
            .role_id = intent.role_id,
            .planning_state_revision = intent.planning_state_revision,
            .strategy = intent.strategy,
        },
        .as_of = context.as_of,
        .catalog = context.catalog,
        .slots = intent.slots,
        .constraints = constraints,
        .objectives = storage.objectives[0..objective_count_written],
        .duration_estimates = storage.duration_estimates[0..duration_count_written],
    };
}

/// This is deliberately a modest, fixed value: target duration is a
/// training-quality objective, never a feasibility rule or a caller-tunable
/// substitute for the hard duration cap.
pub const target_duration_weight: u16 = 1;

fn requiredObjectiveCount(context: SessionContext, policy: ?hypertrophy.SessionPolicy) BuildError!usize {
    var count = context.exercise_preferences.len;
    if (policy) |value| {
        try validatePolicy(value);
        count = std.math.add(usize, count, value.muscle_priorities.len) catch
            return error.TooManyObjectives;
        if (value.target_duration_minutes != null) {
            count = std.math.add(usize, count, 1) catch return error.TooManyObjectives;
        }
    }
    if (count > solver.max_objectives) return error.TooManyObjectives;
    return count;
}

fn validateIntent(intent: program_intent.PlannedSessionIntent) BuildError!void {
    if (intent.slots.len == 0) return error.EmptyIntent;
    if (intent.slots.len > solver.max_slots) return error.TooManySlots;
    if (intent.definition_version == 0 or intent.definition_fingerprint.len == 0)
        return error.InvalidOrigin;
    for (intent.slots, 0..) |slot, index| {
        for (intent.slots[0..index]) |prior| {
            if (slot.id.eql(prior.id)) return error.DuplicateSlotId;
        }
    }
}

fn validateContext(context: SessionContext) BuildError!void {
    if (context.catalog.exercises.len > solver.max_catalog_exercises)
        return error.TooManyCatalogExercises;
    try validateConstraints(context.constraints);
    for (context.exercise_preferences) |preference| {
        if (preference.weight == 0) return error.InvalidExercisePreferenceWeight;
    }
}

fn validatePolicy(policy: hypertrophy.SessionPolicy) BuildError!void {
    if (policy.available_equipment_ids.len > hypertrophy.max_available_equipment)
        return error.TooManyAvailableEquipmentIds;
    if (policy.muscle_priorities.len > hypertrophy.max_muscle_priorities)
        return error.TooManyMusclePriorities;
    if (policy.duration_estimates.len > hypertrophy.max_duration_estimates)
        return error.TooManyDurationEstimates;
    for (policy.muscle_priorities, 0..) |priority, index| {
        if (priority.weight == 0) return error.InvalidMusclePriorityWeight;
        for (policy.muscle_priorities[0..index]) |prior| {
            if (priority.muscle_id.eql(prior.muscle_id)) return error.DuplicateMusclePriority;
        }
    }
}

fn validateDurationEstimates(
    slots: []const program_intent.Slot,
    estimates: []const hypertrophy.CandidateDurationEstimate,
) BuildError!void {
    for (estimates, 0..) |estimate, index| {
        if (!containsSlot(slots, estimate.slot_id)) return error.DurationEstimateForUnknownSlot;
        for (estimates[0..index]) |prior| {
            if (estimate.slot_id.eql(prior.slot_id) and estimate.exercise_id.eql(prior.exercise_id))
                return error.DuplicateDurationEstimate;
        }
    }
}

fn validateConstraints(constraints: model.SessionConstraints) BuildError!void {
    if (constraints.minimum_exercises) |minimum| {
        if (constraints.maximum_exercises) |maximum| if (minimum > maximum)
            return error.InvalidConstraints;
    }
    try validateUniqueIds(constraints.available_equipment_ids);
    try validateUniqueIds(constraints.required_exercise_ids);
    try validateUniqueIds(constraints.excluded_exercise_ids);
    try validateUniqueIds(constraints.excluded_family_ids);
    try validateUniqueIds(constraints.excluded_movement_pattern_ids);
    try validateUniqueIds(constraints.excluded_restriction_tag_ids);
    try validateUniqueIds(constraints.excluded_equipment_ids);
}

fn validateUniqueIds(ids: []const primitives.Id) BuildError!void {
    for (ids, 0..) |id, index| {
        for (ids[0..index]) |prior| if (id.eql(prior)) return error.InvalidConstraints;
    }
}

fn containsSlot(slots: []const program_intent.Slot, id: primitives.Id) bool {
    for (slots) |slot| if (slot.id.eql(id)) return true;
    return false;
}

test "build normalizes hypertrophy policy into hard constraints and objectives" {
    const as_of = try primitives.Timestamp.parse("2026-08-17T12:00:00Z");
    const definition = try primitives.Id.parse("program:upper");
    const instance = try primitives.Id.parse("instance:1");
    const occurrence = try primitives.Id.parse("occurrence:1");
    const block = try primitives.Id.parse("block:1");
    const role = try primitives.Id.parse("role:upper");
    const slot_id = try primitives.Id.parse("slot:press");
    const exercise = try primitives.Id.parse("exercise:press");
    const family = try primitives.Id.parse("family:press");
    const chest = try primitives.Id.parse("muscle:chest");
    const bench = try primitives.Id.parse("equipment:bench");
    const lane = try primitives.Id.parse("lane:press");

    const slots = [_]program_intent.Slot{.{
        .id = slot_id,
        .selection = .{ .adaptive = .{ .preferred = .{ .exercise_ids = &.{exercise} } } },
        .progression = .{ .state_id = lane, .method = undefined },
    }};
    const catalog_exercises = [_]training.Exercise{.{ .id = exercise, .family_ids = &.{family} }};
    const equipment = [_]primitives.Id{bench};
    const priorities = [_]hypertrophy.MusclePriority{.{ .muscle_id = chest, .weight = 20 }};
    const durations = [_]hypertrophy.CandidateDurationEstimate{.{
        .slot_id = slot_id,
        .exercise_id = exercise,
        .minutes = 15,
    }};
    const preferences = [_]ExercisePreference{.{
        .target = .{ .family = family },
        .weight = 3,
    }};
    var objectives: [3]model.Objective = undefined;
    var duration_storage: [1]model.DurationEstimate = undefined;

    const result = try build(.{
        .definition_id = definition,
        .definition_version = 1,
        .definition_fingerprint = "definition-fingerprint",
        .instance_id = instance,
        .occurrence_id = occurrence,
        .block_id = block,
        .role_id = role,
        .planning_state_revision = 4,
        .strategy = .adaptive_hypertrophy,
        .slots = &slots,
    }, .{
        .as_of = as_of,
        .catalog = .{ .exercises = &catalog_exercises },
        .exercise_preferences = &preferences,
    }, .{
        .available_equipment_ids = &equipment,
        .hard_maximum_minutes = 40,
        .target_duration_minutes = 30,
        .muscle_priorities = &priorities,
        .duration_estimates = &durations,
    }, .{ .objectives = &objectives, .duration_estimates = &duration_storage });

    try std.testing.expectEqual(program_intent.Strategy.adaptive_hypertrophy, result.origin.strategy);
    try std.testing.expect(result.slots.ptr == slots[0..].ptr);
    try std.testing.expect(result.slots[0].progression.state_id.eql(lane));
    try std.testing.expectEqual(@as(usize, 1), result.constraints.available_equipment_ids.len);
    try std.testing.expect(result.constraints.available_equipment_ids[0].eql(bench));
    try std.testing.expectEqual(@as(?u16, 40), result.constraints.hard_maximum_minutes);
    try std.testing.expectEqual(@as(usize, 3), result.objectives.len);
    try std.testing.expect(result.objectives[0] == .exercise_preference);
    try std.testing.expect(result.objectives[1] == .muscle_priority);
    try std.testing.expect(result.objectives[2] == .target_duration);
    try std.testing.expectEqual(@as(usize, 1), result.duration_estimates.len);
    try std.testing.expect(result.duration_estimates[0].slot_id.eql(slot_id));
}

test "build rejects insufficient caller storage before writing" {
    const id = try primitives.Id.parse("id:one");
    const slots = [_]program_intent.Slot{.{
        .id = id,
        .selection = .{ .fixed = id },
        .progression = .{ .state_id = id, .method = undefined },
    }};
    var objectives: [0]model.Objective = .{};
    var durations: [0]model.DurationEstimate = .{};
    try std.testing.expectError(error.ObjectiveStorageTooSmall, build(.{
        .definition_id = id,
        .definition_version = 1,
        .definition_fingerprint = "fingerprint",
        .instance_id = id,
        .occurrence_id = id,
        .block_id = id,
        .role_id = id,
        .planning_state_revision = 0,
        .strategy = .fixed,
        .slots = &slots,
    }, .{
        .as_of = try primitives.Timestamp.parse("2026-08-17T12:00:00Z"),
        .catalog = .{ .exercises = &.{} },
        .exercise_preferences = &.{.{ .target = .{ .exercise = id }, .weight = 1 }},
    }, null, .{ .objectives = &objectives, .duration_estimates = &durations }));
}
