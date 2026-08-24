//! Adaptive hypertrophy session intent.
//!
//! This strategy declares work and planning policy only.  It deliberately
//! neither reads nor searches a catalog; the shared planning kernel turns this
//! result into a bounded planning problem and resolves exercises later.

const primitives = @import("../primitives.zig");
const progression = @import("../progression/root.zig");
const intent = @import("intent.zig");
const volume = @import("../volume.zig");

pub const strategy_id = "caudex.adaptive-hypertrophy";
pub const strategy_version: u32 = 1;

/// These limits bound the strategy boundary before a caller builds a planning
/// problem.  The planner may impose stricter limits for a particular solve.
pub const max_primary_slots: usize = 8;
pub const max_accessory_slots: usize = 8;
pub const max_slots: usize = max_primary_slots + max_accessory_slots;
pub const max_muscle_priorities: usize = 16;
pub const max_available_equipment: usize = 32;
pub const max_duration_estimates: usize = 64;
pub const max_volume_targets: usize = volume.max_muscles;
pub const max_ids_per_set: usize = 32;

pub const MusclePriority = struct {
    muscle_id: primitives.Id,
    /// A positive relative priority.  The planning builder retains this value
    /// as a typed objective weight; it does not use it to alter eligibility.
    weight: u16,
};

/// Per-exercise data for the planner's time constraints.  A duration remains
/// associated with a candidate exercise rather than an adaptive slot because
/// different substitutions can take different amounts of time.
pub const CandidateDurationEstimate = struct {
    slot_id: primitives.Id,
    exercise_id: primitives.Id,
    minutes: u16,
};

/// Explicit facts the host knows at planning time.  `available_equipment_ids`
/// and `hard_maximum_minutes` are hard planning inputs; target duration and
/// muscle priorities become soft, typed planning objectives.
pub const SessionPolicy = struct {
    available_equipment_ids: []const primitives.Id = &.{},
    hard_maximum_minutes: ?u16 = null,
    target_duration_minutes: ?u16 = null,
    muscle_priorities: []const MusclePriority = &.{},
    duration_estimates: []const CandidateDurationEstimate = &.{},
    /// Program-owned muscle-volume intent. Accounting remains in `volume`;
    /// this strategy only selects the policy and resolved targets.
    volume_policy: volume.CreditPolicy = volume.CreditPolicy.firstParty(),
    volume_targets: []const volume.Target = &.{},
};

/// A host-authored adaptive slot.  The caller owns all IDs and progression
/// lane state; this strategy only borrows and preserves them.
pub const Work = struct {
    slot_id: primitives.Id,
    selection: intent.AdaptiveSelection,
    progression: progression.Lane,
    ordering: intent.Ordering = .{},
};

/// Identity/provenance for the occurrence this strategy is resolving.
pub const Origin = struct {
    definition_id: primitives.Id,
    definition_version: u32,
    definition_fingerprint: []const u8,
    instance_id: primitives.Id,
    occurrence_id: primitives.Id,
    block_id: primitives.Id,
    role_id: primitives.Id,
    planning_state_revision: u64,
};

/// All variable composition comes from the caller.  Primary work is required;
/// accessory work is optional and may be omitted by the planner only after
/// required work has been considered.
pub const Request = struct {
    origin: Origin,
    primary_work: []const Work,
    optional_accessories: []const Work = &.{},
    policy: SessionPolicy = .{},
};

pub const Result = struct {
    intent: intent.PlannedSessionIntent,
    policy: SessionPolicy,
};

pub const BuildError = error{
    OutputTooSmall,
    PrimaryWorkRequired,
    TooManyPrimarySlots,
    TooManyAccessorySlots,
    TooManyMusclePriorities,
    TooManyAvailableEquipmentIds,
    TooManyDurationEstimates,
    TooManyVolumeTargets,
    InvalidVolumePolicy,
    InvalidVolumeTarget,
    DuplicateVolumeTarget,
    TooManyIdsInSet,
    InvalidMusclePriorityWeight,
    DuplicateMusclePriority,
    DuplicateSlotId,
    DuplicateProgressionLane,
    DurationEstimateForUnknownSlot,
    DuplicateDurationEstimate,
};

/// Builds adaptive hypertrophy intent in caller-owned `slot_storage`.
///
/// The result borrows every input slice and the populated prefix of
/// `slot_storage`; callers must retain them through planning and persistence
/// of the resulting snapshot.
pub fn build(request: Request, slot_storage: []intent.Slot) BuildError!Result {
    try validate(request);

    const slot_count = request.primary_work.len + request.optional_accessories.len;
    if (slot_storage.len < slot_count) return error.OutputTooSmall;

    var count: usize = 0;
    for (request.primary_work) |work| {
        slot_storage[count] = slotFor(work, .required);
        count += 1;
    }
    for (request.optional_accessories) |work| {
        slot_storage[count] = slotFor(work, .optional);
        count += 1;
    }

    return .{
        .intent = .{
            .definition_id = request.origin.definition_id,
            .definition_version = request.origin.definition_version,
            .definition_fingerprint = request.origin.definition_fingerprint,
            .instance_id = request.origin.instance_id,
            .occurrence_id = request.origin.occurrence_id,
            .block_id = request.origin.block_id,
            .role_id = request.origin.role_id,
            .planning_state_revision = request.origin.planning_state_revision,
            .strategy = .adaptive_hypertrophy,
            .slots = slot_storage[0..count],
        },
        .policy = request.policy,
    };
}

fn slotFor(work: Work, presence: intent.Presence) intent.Slot {
    return .{
        .id = work.slot_id,
        .presence = presence,
        .selection = .{ .adaptive = work.selection },
        .progression = work.progression,
        .ordering = work.ordering,
    };
}

fn validate(request: Request) BuildError!void {
    if (request.primary_work.len == 0) return error.PrimaryWorkRequired;
    if (request.primary_work.len > max_primary_slots) return error.TooManyPrimarySlots;
    if (request.optional_accessories.len > max_accessory_slots) return error.TooManyAccessorySlots;
    if (request.policy.muscle_priorities.len > max_muscle_priorities) return error.TooManyMusclePriorities;
    if (request.policy.available_equipment_ids.len > max_available_equipment)
        return error.TooManyAvailableEquipmentIds;
    if (request.policy.duration_estimates.len > max_duration_estimates)
        return error.TooManyDurationEstimates;
    if (request.policy.volume_targets.len > max_volume_targets)
        return error.TooManyVolumeTargets;
    volume.validatePolicy(request.policy.volume_policy) catch return error.InvalidVolumePolicy;
    for (request.policy.volume_targets, 0..) |target, index| {
        if (!volume.validTarget(target)) return error.InvalidVolumeTarget;
        for (request.policy.volume_targets[0..index]) |prior| {
            if (prior.muscle_id.eql(target.muscle_id)) return error.DuplicateVolumeTarget;
        }
    }

    for (request.policy.muscle_priorities, 0..) |priority, index| {
        if (priority.weight == 0) return error.InvalidMusclePriorityWeight;
        for (request.policy.muscle_priorities[0..index]) |prior| {
            if (priority.muscle_id.eql(prior.muscle_id)) return error.DuplicateMusclePriority;
        }
    }

    for (request.primary_work, 0..) |work, index| {
        try validateWork(work);
        try validateUniqueWork(request.primary_work, request.optional_accessories, work, index, true);
    }
    for (request.optional_accessories, 0..) |work, index| {
        try validateWork(work);
        try validateUniqueWork(request.primary_work, request.optional_accessories, work, index, false);
    }
    for (request.policy.duration_estimates, 0..) |estimate, index| {
        if (!containsSlot(request.primary_work, request.optional_accessories, estimate.slot_id))
            return error.DurationEstimateForUnknownSlot;
        for (request.policy.duration_estimates[0..index]) |prior| {
            if (estimate.slot_id.eql(prior.slot_id) and estimate.exercise_id.eql(prior.exercise_id))
                return error.DuplicateDurationEstimate;
        }
    }
}

fn validateWork(work: Work) BuildError!void {
    try validateSelection(work.selection);
    if (work.ordering.before_slot_ids.len > max_ids_per_set or work.ordering.after_slot_ids.len > max_ids_per_set)
        return error.TooManyIdsInSet;
}

fn validateSelection(selection: intent.AdaptiveSelection) BuildError!void {
    switch (selection.universe) {
        .catalog => {},
        .allowlist => |set| try validateSet(set),
    }
    try validateSet(selection.preferred);
    try validateRequirement(selection.requirements.muscles);
    try validateRequirement(selection.requirements.movement_patterns);
    try validateRequirement(selection.requirements.exercise_families);
    try validateRequirement(selection.requirements.equipment);
    if (selection.requirements.excluded_exercise_ids.len > max_ids_per_set)
        return error.TooManyIdsInSet;
}

fn validateSet(set: intent.ExerciseSet) BuildError!void {
    if (set.exercise_ids.len > max_ids_per_set or set.family_ids.len > max_ids_per_set)
        return error.TooManyIdsInSet;
}

fn validateRequirement(requirement: intent.IdRequirement) BuildError!void {
    if (requirement.ids.len > max_ids_per_set) return error.TooManyIdsInSet;
}

fn validateUniqueWork(
    primary_work: []const Work,
    optional_accessories: []const Work,
    work: Work,
    index: usize,
    is_primary: bool,
) BuildError!void {
    const prior = if (is_primary) primary_work[0..index] else optional_accessories[0..index];
    for (prior) |other| try validateDistinct(work, other);
    if (!is_primary) for (primary_work) |other| try validateDistinct(work, other);
}

fn validateDistinct(left: Work, right: Work) BuildError!void {
    if (left.slot_id.eql(right.slot_id)) return error.DuplicateSlotId;
    if (left.progression.state_id.eql(right.progression.state_id)) return error.DuplicateProgressionLane;
}

fn containsSlot(primary_work: []const Work, optional_accessories: []const Work, slot_id: primitives.Id) bool {
    for (primary_work) |work| if (work.slot_id.eql(slot_id)) return true;
    for (optional_accessories) |work| if (work.slot_id.eql(slot_id)) return true;
    return false;
}

test "adaptive hypertrophy preserves required work, optional accessories, and planning policy" {
    const chest = try primitives.Id.parse("muscle:chest");
    const triceps = try primitives.Id.parse("muscle:triceps");
    const horizontal_push = try primitives.Id.parse("pattern:horizontal-push");
    const press_family = try primitives.Id.parse("family:press");
    const bench = try primitives.Id.parse("equipment:bench");
    const barbell = try primitives.Id.parse("equipment:barbell");
    const incline_press = try primitives.Id.parse("exercise:incline-press");
    const dumbbell_press = try primitives.Id.parse("exercise:dumbbell-press");
    const fly = try primitives.Id.parse("exercise:cable-fly");

    const primary_muscles = [_]primitives.Id{chest};
    const primary_patterns = [_]primitives.Id{horizontal_push};
    const primary_families = [_]primitives.Id{press_family};
    const preferred_primary = [_]primitives.Id{incline_press};
    const primary_equipment = [_]primitives.Id{ bench, barbell };
    const accessory_muscles = [_]primitives.Id{triceps};
    const accessory_allowlist = [_]primitives.Id{fly};
    const priorities = [_]MusclePriority{
        .{ .muscle_id = chest, .weight = 100 },
        .{ .muscle_id = triceps, .weight = 40 },
    };
    const durations = [_]CandidateDurationEstimate{
        .{ .slot_id = try primitives.Id.parse("slot:primary-press"), .exercise_id = incline_press, .minutes = 18 },
        .{ .slot_id = try primitives.Id.parse("slot:primary-press"), .exercise_id = dumbbell_press, .minutes = 16 },
        .{ .slot_id = try primitives.Id.parse("slot:accessory-fly"), .exercise_id = fly, .minutes = 10 },
    };
    const available_equipment = [_]primitives.Id{ bench, barbell };

    const primary = [_]Work{.{
        .slot_id = try primitives.Id.parse("slot:primary-press"),
        .selection = .{
            .universe = .catalog,
            .preferred = .{ .exercise_ids = &preferred_primary },
            .requirements = .{
                .muscles = .{ .ids = &primary_muscles, .mode = .all },
                .movement_patterns = .{ .ids = &primary_patterns },
                .exercise_families = .{ .ids = &primary_families },
                .equipment = .{ .ids = &primary_equipment, .mode = .any },
            },
        },
        .progression = .{
            .state_id = try primitives.Id.parse("lane:primary-press"),
            .method = .{ .double_progression = .{ .config = undefined } },
        },
    }};
    const accessories = [_]Work{.{
        .slot_id = try primitives.Id.parse("slot:accessory-fly"),
        .selection = .{
            .universe = .{ .allowlist = .{ .exercise_ids = &accessory_allowlist } },
            .requirements = .{ .muscles = .{ .ids = &accessory_muscles } },
        },
        .progression = .{
            .state_id = try primitives.Id.parse("lane:accessory-fly"),
            .method = .{ .rpe_top_set_backoff = .{ .config = undefined } },
        },
    }};
    var slots: [max_slots]intent.Slot = undefined;

    const result = try build(.{
        .origin = .{
            .definition_id = try primitives.Id.parse("program:hypertrophy"),
            .definition_version = 3,
            .definition_fingerprint = "sha256:definition",
            .instance_id = try primitives.Id.parse("instance:42"),
            .occurrence_id = try primitives.Id.parse("occurrence:9"),
            .block_id = try primitives.Id.parse("block:accumulation"),
            .role_id = try primitives.Id.parse("role:upper-a"),
            .planning_state_revision = 7,
        },
        .primary_work = &primary,
        .optional_accessories = &accessories,
        .policy = .{
            .available_equipment_ids = &available_equipment,
            .hard_maximum_minutes = 45,
            .target_duration_minutes = 40,
            .muscle_priorities = &priorities,
            .duration_estimates = &durations,
        },
    }, &slots);

    try @import("std").testing.expectEqual(intent.Strategy.adaptive_hypertrophy, result.intent.strategy);
    try @import("std").testing.expectEqual(@as(usize, 2), result.intent.slots.len);
    try @import("std").testing.expectEqual(intent.Presence.required, result.intent.slots[0].presence);
    try @import("std").testing.expectEqual(intent.Presence.optional, result.intent.slots[1].presence);
    try @import("std").testing.expectEqual(@as(usize, 2), result.policy.muscle_priorities.len);
    try @import("std").testing.expectEqual(@as(?u16, 45), result.policy.hard_maximum_minutes);
    try @import("std").testing.expect(result.intent.slots[0].selection == .adaptive);
    try @import("std").testing.expect(result.intent.slots[1].selection.adaptive.universe == .allowlist);
    try @import("std").testing.expect(result.intent.slots[0].progression.method == .double_progression);
    try @import("std").testing.expect(result.intent.slots[1].progression.method == .rpe_top_set_backoff);
}

test "adaptive hypertrophy rejects ambiguous lane routing" {
    const slot_a = try primitives.Id.parse("slot:a");
    const slot_b = try primitives.Id.parse("slot:b");
    const lane = try primitives.Id.parse("lane:shared");
    const work = [_]Work{
        .{ .slot_id = slot_a, .selection = .{}, .progression = .{ .state_id = lane, .method = undefined } },
        .{ .slot_id = slot_b, .selection = .{}, .progression = .{ .state_id = lane, .method = undefined } },
    };
    var slots: [2]intent.Slot = undefined;

    try @import("std").testing.expectError(error.DuplicateProgressionLane, build(.{
        .origin = undefined,
        .primary_work = &work,
    }, &slots));
}
