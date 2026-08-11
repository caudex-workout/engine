//! Deterministic training-program planning above session composition.
//!
//! Definitions are immutable borrowed snapshots. Instances identify one
//! athlete's run; accepted state identifies its sequence position. Resolution
//! and evaluation never persist or accept state on a host's behalf.

const std = @import("std");
const athlete_profile = @import("athlete_profile.zig");
const exercise_knowledge = @import("exercise_knowledge.zig");
const primitives = @import("primitives.zig");
const programming = @import("programming.zig");
const training = @import("training.zig");

pub const schema_version: u32 = 1;
pub const max_blocks: usize = 32;
pub const max_roles: usize = 64;
pub const max_items_per_role: usize = programming.max_exercises;
pub const max_schedule_entries: usize = 366;

pub const Weekday = athlete_profile.Weekday;
pub const Phase = enum { base, accumulation, intensification, realization, deload, custom };
pub const Lifecycle = enum { created, active, paused, completed, ended };
pub const OccurrenceStatus = enum { upcoming, due, overdue, completed, skipped, partial, abandoned };
pub const MusclePriority = athlete_profile.MusclePriority;

pub const DefinitionRef = struct {
    id: []const u8,
    version: u32,
    configuration_fingerprint: []const u8,
};

pub const ProgressionAssignment = struct {
    state_id: []const u8,
    method: programming.Method,
};

pub const SlotRequirements = struct {
    target_muscle_ids: []const []const u8 = &.{},
    movement_pattern_ids: []const []const u8 = &.{},
    exercise_family_ids: []const []const u8 = &.{},
    required_exercise_ids: []const []const u8 = &.{},
    excluded_exercise_ids: []const []const u8 = &.{},
    required_equipment_ids: []const []const u8 = &.{},
    progression_requirement: ?exercise_knowledge.ProgressionRequirement = null,
};

pub const ExercisePool = struct {
    exercise_ids: []const []const u8 = &.{},
    exercise_family_ids: []const []const u8 = &.{},
};

pub const Ordering = struct {
    priority_tier: u8 = 0,
    before_item_ids: []const []const u8 = &.{},
    after_item_ids: []const []const u8 = &.{},
};

pub const SessionItem = union(enum) {
    fixed: struct {
        id: []const u8,
        exercise_id: []const u8,
        anchor: enum { none, preferred, required, block } = .none,
        progression: ?ProgressionAssignment = null,
        ordering: Ordering = .{},
    },
    slot: struct {
        id: []const u8,
        requirements: SlotRequirements = .{},
        pool: ExercisePool = .{},
        progression: ?ProgressionAssignment = null,
        ordering: Ordering = .{},
    },

    pub fn id(self: SessionItem) []const u8 {
        return switch (self) {
            inline else => |item| item.id,
        };
    }
};

pub const SessionRole = struct {
    id: []const u8,
    name: []const u8,
    purpose: ?[]const u8 = null,
    muscle_priorities: []const MusclePriority = &.{},
    items: []const SessionItem,
    default_progression: ?ProgressionAssignment = null,
    expected_duration_minutes: ?u16 = null,
};

pub const WeekdayEntry = struct { weekday: Weekday, role_id: []const u8 };
pub const DatedEntry = struct { local_date: []const u8, role_id: []const u8 };
pub const FrequencyTarget = struct { sessions: u8, days: u16 };

pub const Schedule = union(enum) {
    rotation: struct { role_ids: []const []const u8, frequency: ?FrequencyTarget = null },
    fixed_weekdays: struct { entries: []const WeekdayEntry },
    frequency_targeted: struct { role_ids: []const []const u8, target: FrequencyTarget },
    explicit_dates: struct { entries: []const DatedEntry },
    hybrid: struct {
        role_ids: []const []const u8,
        target: FrequencyTarget,
        preferred_weekdays: []const Weekday = &.{},
    },
};

pub const Length = union(enum) {
    completed_occurrences: u32,
    completed_microcycles: u32,
    calendar_weeks: u16,
    explicit_end_date: []const u8,
    manual,
};

pub const Block = struct {
    id: []const u8,
    name: []const u8,
    phase: Phase = .base,
    phase_semantic: ?[]const u8 = null,
    length: Length,
    schedule: Schedule,
    roles: []const SessionRole,
    muscle_priorities: []const MusclePriority = &.{},
    default_progression: ?ProgressionAssignment = null,
    next_block_id: ?[]const u8 = null,
};

pub const Compatibility = struct {
    minimum_sessions_per_week: ?u8 = null,
    maximum_sessions_per_week: ?u8 = null,
    required_equipment_ids: []const []const u8 = &.{},
    suitable_experience: []const athlete_profile.ExperienceCategory = &.{},
};

pub const ProgramDefinition = struct {
    schema_version: u32 = schema_version,
    id: []const u8,
    version: u32,
    display_name: []const u8,
    description: ?[]const u8 = null,
    strategy_id: []const u8 = "caudex.sequenced-program",
    strategy_version: u32 = 1,
    configuration_fingerprint: []const u8,
    source: ?[]const u8 = null,
    blocks: []const Block,
    compatibility: Compatibility = .{},
};

pub const ProgramInstance = struct {
    schema_version: u32 = schema_version,
    id: []const u8,
    athlete_id: []const u8,
    definition: DefinitionRef,
    lifecycle: Lifecycle = .created,
    started_on: ?[]const u8 = null,
};

pub const ProgramState = struct {
    schema_version: u32 = schema_version,
    instance_id: []const u8,
    definition: DefinitionRef,
    revision: u64,
    block_index: u16 = 0,
    microcycle_index: u32 = 0,
    session_cursor: u16 = 0,
    completed_occurrences: u64 = 0,
    block_completed_occurrences: u32 = 0,
    complete: bool = false,
};

pub const LocalDate = struct { iso_date: []const u8, weekday: Weekday };

pub const Occurrence = struct {
    id: []const u8,
    instance_id: []const u8,
    block_id: []const u8,
    microcycle_index: u32,
    role_id: []const u8,
    sequence_index: u16,
    scheduled_date: ?[]const u8,
    status: OccurrenceStatus,
};

pub const SchedulingProvenance = enum { rotation_next, weekday_match, frequency_sequence, explicit_date, hybrid_sequence };
pub const PlannedSessionIntent = struct {
    definition: DefinitionRef,
    instance_id: []const u8,
    block_id: []const u8,
    block_phase: Phase,
    occurrence: Occurrence,
    role: SessionRole,
    block_default_progression: ?ProgressionAssignment,
    program_muscle_priorities: []const MusclePriority,
    scheduling_provenance: SchedulingProvenance,
};

pub const Issue = struct { code: []const u8, path: []const u8, message: []const u8 };
pub const ValidationError = error{ OutputTooSmall, InvalidDefinition };
pub const ResolveError = error{ InvalidDefinition, StateMismatch, InvalidCursor, NoScheduledSession, OutputTooSmall };

pub fn definitionRef(definition: ProgramDefinition) DefinitionRef {
    return .{ .id = definition.id, .version = definition.version, .configuration_fingerprint = definition.configuration_fingerprint };
}

pub fn initialState(instance: ProgramInstance) ProgramState {
    return .{ .instance_id = instance.id, .definition = instance.definition, .revision = 0 };
}

pub fn validateDefinition(definition: ProgramDefinition, storage: []Issue) error{OutputTooSmall}![]const Issue {
    var count: usize = 0;
    if (definition.schema_version != schema_version or definition.id.len == 0 or definition.version == 0 or
        definition.configuration_fingerprint.len == 0)
        try issue(storage, &count, "program.definition.identity_invalid", "/definition", "Program identity, version, and fingerprint are required.");
    if (definition.blocks.len == 0 or definition.blocks.len > max_blocks)
        try issue(storage, &count, "program.definition.blocks_invalid", "/definition/blocks", "A program requires a bounded non-empty block sequence.");
    for (definition.blocks, 0..) |block, block_index| {
        if (block.roles.len == 0 or block.roles.len > max_roles)
            try issue(storage, &count, "program.block.roles_invalid", "/definition/blocks/roles", "Each block requires bounded session roles.");
        for (definition.blocks[0..block_index]) |prior| if (std.mem.eql(u8, prior.id, block.id))
            try issue(storage, &count, "program.block.id_duplicate", "/definition/blocks/id", "Block IDs must be unique.");
        for (block.roles, 0..) |role, role_index| {
            if (role.items.len > max_items_per_role)
                try issue(storage, &count, "program.role.items_exceeded", "/definition/blocks/roles/items", "A session role exceeds the item limit.");
            for (block.roles[0..role_index]) |prior| if (std.mem.eql(u8, prior.id, role.id))
                try issue(storage, &count, "program.role.id_duplicate", "/definition/blocks/roles/id", "Session-role IDs must be unique within a block.");
            for (role.items, 0..) |item, item_index| {
                for (role.items[0..item_index]) |prior| if (std.mem.eql(u8, prior.id(), item.id()))
                    try issue(storage, &count, "program.item.id_duplicate", "/definition/blocks/roles/items/id", "Session item IDs must be unique.");
                const assignment = switch (item) {
                    inline else => |value| value.progression orelse role.default_progression orelse block.default_progression,
                };
                if (assignment == null)
                    try issue(storage, &count, "progression.assignment_missing", "/definition/blocks/roles/items/progression", "Every item needs one resolved progression assignment.");
                if (item == .slot) try validateSlot(item.slot, storage, &count);
                try validateOrdering(role, item, storage, &count);
                if (assignment) |current| for (block.roles[0..role_index]) |prior_role| {
                    for (prior_role.items) |prior_item| if (resolveItemProgression(block, prior_role, prior_item)) |prior| {
                        if (std.mem.eql(u8, current.state_id, prior.state_id) and
                            !std.mem.eql(u8, current.method.id(), prior.method.id()))
                            try issue(storage, &count, "progression.assignment_ambiguous", "/definition/blocks/roles/items/progression/stateId", "A progression state lane cannot be assigned to different methods.");
                    };
                };
            }
        }
        try validateSchedule(block, storage, &count);
        if (block.next_block_id) |next| if (findBlock(definition, next) == null)
            try issue(storage, &count, "program.transition.target_unknown", "/definition/blocks/nextBlockId", "The next block reference is unknown.");
    }
    return storage[0..count];
}

pub fn resolvePlannedSession(
    occurrence_storage: []u8,
    definition: ProgramDefinition,
    instance: ProgramInstance,
    state: ProgramState,
    local_date: ?LocalDate,
) ResolveError!PlannedSessionIntent {
    var validation: [64]Issue = undefined;
    const issues = validateDefinition(definition, &validation) catch return error.OutputTooSmall;
    if (issues.len != 0) return error.InvalidDefinition;
    if (!referenceEqual(instance.definition, definitionRef(definition)) or
        !referenceEqual(state.definition, instance.definition) or
        !std.mem.eql(u8, state.instance_id, instance.id)) return error.StateMismatch;
    if (instance.lifecycle != .active) return error.InvalidCursor;
    if (state.complete) return error.InvalidCursor;
    if (state.block_index >= definition.blocks.len) return error.InvalidCursor;
    const block = definition.blocks[state.block_index];
    const choice = try chooseRole(block, state, local_date);
    const role = findRole(block, choice.role_id) orelse return error.InvalidDefinition;
    const occurrence_id = std.fmt.bufPrint(occurrence_storage, "{s}:{s}:{d}:{d}:{s}:{s}", .{
        instance.id,
        block.id,
        state.microcycle_index,
        state.session_cursor,
        role.id,
        choice.scheduled_date orelse "unscheduled",
    }) catch return error.OutputTooSmall;
    return .{
        .definition = instance.definition,
        .instance_id = instance.id,
        .block_id = block.id,
        .block_phase = block.phase,
        .occurrence = .{
            .id = occurrence_id,
            .instance_id = instance.id,
            .block_id = block.id,
            .microcycle_index = state.microcycle_index,
            .role_id = role.id,
            .sequence_index = state.session_cursor,
            .scheduled_date = choice.scheduled_date,
            .status = choice.status,
        },
        .role = role,
        .block_default_progression = block.default_progression,
        .program_muscle_priorities = block.muscle_priorities,
        .scheduling_provenance = choice.provenance,
    };
}

pub const Completion = enum { completed, substituted_completed, partial, abandoned, unrelated, skipped };
pub const ProposalOutcome = union(enum) { advance: ProgramState, require_host_policy, no_change };
pub const ProgramStateProposal = struct {
    expected_revision: u64,
    occurrence_id: []const u8,
    outcome: ProposalOutcome,
    explanation_code: []const u8,
};

pub fn proposeAdvancement(
    definition: ProgramDefinition,
    state: ProgramState,
    planned: PlannedSessionIntent,
    completion: Completion,
) ResolveError!ProgramStateProposal {
    if (!referenceEqual(state.definition, planned.definition) or !std.mem.eql(u8, state.instance_id, planned.instance_id))
        return error.StateMismatch;
    if (state.block_index >= definition.blocks.len) return error.InvalidCursor;
    const active_block = definition.blocks[state.block_index];
    const expected_role_id = roleAtCursor(active_block.schedule, state.session_cursor) orelse
        return error.InvalidCursor;
    if (!std.mem.eql(u8, planned.block_id, active_block.id) or
        !std.mem.eql(u8, planned.role.id, expected_role_id) or
        !std.mem.eql(u8, planned.occurrence.block_id, active_block.id) or
        !std.mem.eql(u8, planned.occurrence.role_id, expected_role_id) or
        planned.occurrence.microcycle_index != state.microcycle_index or
        planned.occurrence.sequence_index != state.session_cursor) return error.StateMismatch;
    var expected_occurrence_storage: [1024]u8 = undefined;
    const expected_occurrence_id = std.fmt.bufPrint(&expected_occurrence_storage, "{s}:{s}:{d}:{d}:{s}:{s}", .{
        state.instance_id,
        active_block.id,
        state.microcycle_index,
        state.session_cursor,
        expected_role_id,
        planned.occurrence.scheduled_date orelse "unscheduled",
    }) catch return error.InvalidCursor;
    if (!std.mem.eql(u8, planned.occurrence.id, expected_occurrence_id)) return error.StateMismatch;
    if (completion == .partial or completion == .abandoned)
        return .{ .expected_revision = state.revision, .occurrence_id = planned.occurrence.id, .outcome = .require_host_policy, .explanation_code = "program.transition.ambiguous_completion" };
    if (completion == .unrelated)
        return .{ .expected_revision = state.revision, .occurrence_id = planned.occurrence.id, .outcome = .no_change, .explanation_code = "program.transition.unrelated_workout" };
    var next = state;
    next.revision = std.math.add(u64, next.revision, 1) catch return error.InvalidCursor;
    next.completed_occurrences = std.math.add(u64, next.completed_occurrences, 1) catch return error.InvalidCursor;
    next.block_completed_occurrences = std.math.add(u32, next.block_completed_occurrences, 1) catch return error.InvalidCursor;
    const block = active_block;
    const sequence_len = scheduleLength(block.schedule);
    if (sequence_len == 0) return error.InvalidDefinition;
    next.session_cursor += 1;
    if (next.session_cursor >= sequence_len) {
        next.session_cursor = 0;
        next.microcycle_index = std.math.add(u32, next.microcycle_index, 1) catch return error.InvalidCursor;
    }
    if (blockComplete(block, next, state)) {
        if (block.next_block_id) |next_id| {
            next.block_index = @intCast(findBlockIndex(definition, next_id) orelse return error.InvalidDefinition);
            next.microcycle_index = 0;
            next.session_cursor = 0;
            next.block_completed_occurrences = 0;
        } else if (@as(usize, state.block_index) + 1 < definition.blocks.len) {
            next.block_index += 1;
            next.microcycle_index = 0;
            next.session_cursor = 0;
            next.block_completed_occurrences = 0;
        } else {
            next.complete = true;
        }
    }
    return .{ .expected_revision = state.revision, .occurrence_id = planned.occurrence.id, .outcome = .{ .advance = next }, .explanation_code = if (completion == .skipped) "program.transition.explicit_skip" else "program.transition.session_completed" };
}

pub fn resolveItemProgression(block: Block, role: SessionRole, item: SessionItem) ?ProgressionAssignment {
    return switch (item) {
        inline else => |value| value.progression orelse role.default_progression orelse block.default_progression,
    };
}

pub fn resolveSlotBasic(slot: SessionItem, catalog: training.ExerciseCatalog) ?[]const u8 {
    if (slot != .slot) return null;
    const value = slot.slot;
    for (value.pool.exercise_ids) |allowed| for (catalog.exercises) |exercise| {
        if (std.mem.eql(u8, allowed, exercise.id.bytes) and matchesRequirements(exercise, value.requirements)) return exercise.id.bytes;
    };
    for (catalog.exercises) |exercise| if (matchesRequirements(exercise, value.requirements)) return exercise.id.bytes;
    return null;
}

/// Materializes the deterministic roadmap-#4 baseline composition consumed by
/// `programming.recommendFixedSession`. Dynamic selection is deliberately the
/// first matching curated/catalog candidate; roadmap #5 may replace ranking,
/// but not the planned intent or progression ownership represented here.
pub fn materializeBasicSlots(
    intent: PlannedSessionIntent,
    catalog: training.ExerciseCatalog,
    storage: []programming.ExerciseSlot,
) error{ InvalidDefinition, ExerciseNotFound, OutputTooSmall }![]const programming.ExerciseSlot {
    if (storage.len < intent.role.items.len) return error.OutputTooSmall;
    for (intent.role.items, 0..) |item, index| {
        const assignment = switch (item) {
            inline else => |value| value.progression orelse intent.role.default_progression orelse intent.block_default_progression,
        } orelse return error.InvalidDefinition;
        const exercise_id = switch (item) {
            .fixed => |fixed| fixed.exercise_id,
            .slot => resolveSlotBasic(item, catalog) orelse return error.ExerciseNotFound,
        };
        storage[index] = .{
            .slot_id = primitives.Id.parse(item.id()) catch return error.InvalidDefinition,
            .exercise_id = primitives.Id.parse(exercise_id) catch return error.InvalidDefinition,
            .state_id = primitives.Id.parse(assignment.state_id) catch return error.InvalidDefinition,
            .progression = assignment.method,
        };
    }
    return storage[0..intent.role.items.len];
}

fn matchesRequirements(exercise: training.Exercise, requirements: SlotRequirements) bool {
    for (requirements.excluded_exercise_ids) |id| if (std.mem.eql(u8, id, exercise.id.bytes)) return false;
    if (requirements.required_exercise_ids.len != 0) {
        for (requirements.required_exercise_ids) |id| if (std.mem.eql(u8, id, exercise.id.bytes)) break else {} else return false;
    }
    var mismatch: [8]exercise_knowledge.Mismatch = undefined;
    const query: exercise_knowledge.Query = .{
        .muscle_id = if (requirements.target_muscle_ids.len != 0) primitives.Id.parse(requirements.target_muscle_ids[0]) catch return false else null,
        .movement_pattern_id = if (requirements.movement_pattern_ids.len != 0) primitives.Id.parse(requirements.movement_pattern_ids[0]) catch return false else null,
        .progression_requirement = requirements.progression_requirement,
    };
    return (exercise_knowledge.match(exercise, query, &mismatch) catch return false).matches;
}

const Choice = struct { role_id: []const u8, scheduled_date: ?[]const u8, status: OccurrenceStatus, provenance: SchedulingProvenance };
fn chooseRole(block: Block, state: ProgramState, local_date: ?LocalDate) ResolveError!Choice {
    return switch (block.schedule) {
        .rotation => |value| sequenceChoice(value.role_ids, state, null, .rotation_next),
        .frequency_targeted => |value| sequenceChoice(value.role_ids, state, null, .frequency_sequence),
        .hybrid => |value| sequenceChoice(value.role_ids, state, if (local_date) |date| date.iso_date else null, .hybrid_sequence),
        .fixed_weekdays => |value| blk: {
            const date = local_date orelse return error.NoScheduledSession;
            if (state.session_cursor >= value.entries.len) return error.InvalidCursor;
            const entry = value.entries[state.session_cursor];
            if (entry.weekday != date.weekday) return error.NoScheduledSession;
            break :blk .{ .role_id = entry.role_id, .scheduled_date = date.iso_date, .status = .due, .provenance = .weekday_match };
        },
        .explicit_dates => |value| blk: {
            const date = local_date orelse return error.NoScheduledSession;
            if (state.session_cursor >= value.entries.len) return error.InvalidCursor;
            const entry = value.entries[state.session_cursor];
            const order = std.mem.order(u8, entry.local_date, date.iso_date);
            break :blk .{
                .role_id = entry.role_id,
                .scheduled_date = entry.local_date,
                .status = switch (order) {
                    .lt => .overdue,
                    .eq => .due,
                    .gt => .upcoming,
                },
                .provenance = .explicit_date,
            };
        },
    };
}

fn sequenceChoice(ids: []const []const u8, state: ProgramState, date: ?[]const u8, provenance: SchedulingProvenance) ResolveError!Choice {
    if (ids.len == 0 or state.session_cursor >= ids.len) return error.InvalidCursor;
    return .{ .role_id = ids[state.session_cursor], .scheduled_date = date, .status = .upcoming, .provenance = provenance };
}

fn validateSchedule(block: Block, storage: []Issue, count: *usize) error{OutputTooSmall}!void {
    const refs: []const []const u8 = switch (block.schedule) {
        .rotation => |v| v.role_ids,
        .frequency_targeted => |v| v.role_ids,
        .hybrid => |v| v.role_ids,
        .fixed_weekdays, .explicit_dates => &.{},
    };
    if (refs.len == 0 and (block.schedule == .rotation or block.schedule == .frequency_targeted or block.schedule == .hybrid))
        try issue(storage, count, "program.schedule.rotation_empty", "/definition/blocks/schedule", "Sequence schedules require a non-empty rotation.");
    for (refs) |role_id| if (findRole(block, role_id) == null)
        try issue(storage, count, "program.schedule.role_unknown", "/definition/blocks/schedule", "A schedule references an unknown role.");
    switch (block.schedule) {
        .fixed_weekdays => |v| for (v.entries, 0..) |entry, index| {
            if (findRole(block, entry.role_id) == null) try issue(storage, count, "program.schedule.role_unknown", "/definition/blocks/schedule", "A weekday references an unknown role.");
            for (v.entries[0..index]) |prior| if (prior.weekday == entry.weekday) try issue(storage, count, "program.schedule.weekday_duplicate", "/definition/blocks/schedule", "Only one role per weekday is supported.");
        },
        .explicit_dates => |v| for (v.entries, 0..) |entry, index| {
            if (findRole(block, entry.role_id) == null) try issue(storage, count, "program.schedule.role_unknown", "/definition/blocks/schedule", "A date references an unknown role.");
            for (v.entries[0..index]) |prior| if (std.mem.eql(u8, prior.local_date, entry.local_date)) try issue(storage, count, "program.schedule.date_duplicate", "/definition/blocks/schedule", "Only one role per date is supported.");
        },
        .frequency_targeted => |v| if (v.target.sessions == 0 or v.target.days == 0) try issue(storage, count, "program.frequency.invalid", "/definition/blocks/schedule/target", "Frequency target values must be positive."),
        .hybrid => |v| if (v.target.sessions == 0 or v.target.days == 0) try issue(storage, count, "program.frequency.invalid", "/definition/blocks/schedule/target", "Frequency target values must be positive."),
        .rotation => {},
    }
}

fn validateSlot(slot: anytype, storage: []Issue, count: *usize) error{OutputTooSmall}!void {
    for (slot.requirements.required_exercise_ids) |required| for (slot.requirements.excluded_exercise_ids) |excluded| if (std.mem.eql(u8, required, excluded))
        try issue(storage, count, "program.slot.constraints_contradictory", "/definition/blocks/roles/items/requirements", "An exercise cannot be both required and excluded.");
}

fn validateOrdering(role: SessionRole, item: SessionItem, storage: []Issue, count: *usize) error{OutputTooSmall}!void {
    const ordering = switch (item) {
        inline else => |value| value.ordering,
    };
    for (ordering.before_item_ids) |target| {
        if (std.mem.eql(u8, target, item.id()) or findItem(role, target) == null)
            try issue(storage, count, "program.ordering.reference_invalid", "/definition/blocks/roles/items/ordering/before", "Ordering references must identify a different item in the same role.");
        if (findItem(role, target)) |other| if (containsId(switch (other) {
            inline else => |value| value.ordering.before_item_ids,
        }, item.id()))
            try issue(storage, count, "program.ordering.cycle", "/definition/blocks/roles/items/ordering", "Direct cyclic ordering constraints are not allowed.");
    }
    for (ordering.after_item_ids) |target| if (std.mem.eql(u8, target, item.id()) or findItem(role, target) == null)
        try issue(storage, count, "program.ordering.reference_invalid", "/definition/blocks/roles/items/ordering/after", "Ordering references must identify a different item in the same role.");
}

fn scheduleLength(schedule: Schedule) u16 {
    const len = switch (schedule) {
        .rotation => |v| v.role_ids.len,
        .frequency_targeted => |v| v.role_ids.len,
        .hybrid => |v| v.role_ids.len,
        .fixed_weekdays => |v| v.entries.len,
        .explicit_dates => |v| v.entries.len,
    };
    return @intCast(len);
}
fn roleAtCursor(schedule: Schedule, cursor: u16) ?[]const u8 {
    const index: usize = cursor;
    return switch (schedule) {
        .rotation => |value| if (index < value.role_ids.len) value.role_ids[index] else null,
        .frequency_targeted => |value| if (index < value.role_ids.len) value.role_ids[index] else null,
        .hybrid => |value| if (index < value.role_ids.len) value.role_ids[index] else null,
        .fixed_weekdays => |value| if (index < value.entries.len) value.entries[index].role_id else null,
        .explicit_dates => |value| if (index < value.entries.len) value.entries[index].role_id else null,
    };
}
fn blockComplete(block: Block, next: ProgramState, prior: ProgramState) bool {
    _ = prior;
    return switch (block.length) {
        .completed_occurrences => |count| next.block_completed_occurrences >= count,
        .completed_microcycles => |count| next.microcycle_index >= count,
        .calendar_weeks, .explicit_end_date, .manual => false,
    };
}
fn findItem(role: SessionRole, id: []const u8) ?SessionItem {
    for (role.items) |item| if (std.mem.eql(u8, item.id(), id)) return item;
    return null;
}
fn containsId(ids: []const []const u8, wanted: []const u8) bool {
    for (ids) |id| if (std.mem.eql(u8, id, wanted)) return true;
    return false;
}
fn findRole(block: Block, id: []const u8) ?SessionRole {
    for (block.roles) |role| if (std.mem.eql(u8, role.id, id)) return role;
    return null;
}
fn findBlock(definition: ProgramDefinition, id: []const u8) ?Block {
    for (definition.blocks) |block| if (std.mem.eql(u8, block.id, id)) return block;
    return null;
}
fn findBlockIndex(definition: ProgramDefinition, id: []const u8) ?usize {
    for (definition.blocks, 0..) |block, index| if (std.mem.eql(u8, block.id, id)) return index;
    return null;
}
fn referenceEqual(left: DefinitionRef, right: DefinitionRef) bool {
    return left.version == right.version and std.mem.eql(u8, left.id, right.id) and std.mem.eql(u8, left.configuration_fingerprint, right.configuration_fingerprint);
}
fn issue(storage: []Issue, count: *usize, code: []const u8, path: []const u8, message: []const u8) error{OutputTooSmall}!void {
    if (count.* == storage.len) return error.OutputTooSmall;
    storage[count.*] = .{ .code = code, .path = path, .message = message };
    count.* += 1;
}

pub const LifecycleProposal = struct {
    expected_lifecycle: Lifecycle,
    proposed_lifecycle: Lifecycle,
    explanation_code: []const u8,
};

pub fn proposeLifecycle(instance: ProgramInstance, requested: Lifecycle) ?LifecycleProposal {
    const allowed = switch (instance.lifecycle) {
        .created => requested == .active or requested == .ended,
        .active => requested == .paused or requested == .completed or requested == .ended,
        .paused => requested == .active or requested == .ended,
        .completed, .ended => false,
    };
    if (!allowed) return null;
    return .{
        .expected_lifecycle = instance.lifecycle,
        .proposed_lifecycle = requested,
        .explanation_code = switch (requested) {
            .active => "program.lifecycle.started_or_resumed",
            .paused => "program.lifecycle.paused",
            .completed => "program.lifecycle.completed",
            .ended => "program.lifecycle.ended",
            .created => unreachable,
        },
    };
}

pub fn acceptLifecycle(instance: ProgramInstance, proposal: LifecycleProposal) ?ProgramInstance {
    if (instance.lifecycle != proposal.expected_lifecycle) return null;
    var accepted = instance;
    accepted.lifecycle = proposal.proposed_lifecycle;
    return accepted;
}

/// Reports hard incompatibilities without rewriting either the profile or the
/// immutable program definition. Soft preferences remain host-presentable.
pub fn validateCompatibility(
    definition: ProgramDefinition,
    profile: athlete_profile.AthleteProfile,
    storage: []Issue,
) error{OutputTooSmall}![]const Issue {
    var count: usize = 0;
    if (definition.compatibility.minimum_sessions_per_week) |minimum| {
        if (profile.schedule.maximum_sessions_per_week) |maximum| if (minimum > maximum)
            try issue(storage, &count, "program.compatibility.frequency_exceeded", "/profile/schedule/maximumSessionsPerWeek", "The program minimum frequency exceeds the athlete's hard maximum.");
    }
    if (definition.compatibility.maximum_sessions_per_week) |maximum| {
        if (profile.schedule.minimum_sessions_per_week) |minimum| if (maximum < minimum)
            try issue(storage, &count, "program.compatibility.frequency_below_minimum", "/profile/schedule/minimumSessionsPerWeek", "The program maximum frequency is below the athlete's minimum.");
    }
    for (definition.compatibility.required_equipment_ids) |required| {
        var available = false;
        for (profile.locations) |location| for (location.equipment) |equipment| {
            if (std.mem.eql(u8, equipment.equipment_id, required)) available = true;
        };
        if (!available) try issue(storage, &count, "program.compatibility.equipment_unavailable", "/profile/locations", "No athlete location provides required program equipment.");
    }
    if (definition.compatibility.suitable_experience.len != 0) if (profile.experience.resistance_training) |actual| {
        for (definition.compatibility.suitable_experience) |supported| if (supported == actual) break else {} else try issue(storage, &count, "program.compatibility.experience_unsupported", "/profile/experience/resistanceTraining", "The athlete's experience category is outside the program's declared suitability.");
    };
    return storage[0..count];
}

/// Structural first-party presets. They intentionally contain no exercise
/// prescriptions; hosts may use them as scheduling blueprints or add slots
/// with explicit progression ownership.
pub const presets = struct {
    const upper_lower_roles = [_]SessionRole{
        .{ .id = "upper-a", .name = "Upper A", .items = &.{} },
        .{ .id = "lower-a", .name = "Lower A", .items = &.{} },
        .{ .id = "upper-b", .name = "Upper B", .items = &.{} },
        .{ .id = "lower-b", .name = "Lower B", .items = &.{} },
    };
    const upper_lower_ids = [_][]const u8{ "upper-a", "lower-a", "upper-b", "lower-b" };
    const ppl_roles = [_]SessionRole{
        .{ .id = "push", .name = "Push", .items = &.{} },
        .{ .id = "pull", .name = "Pull", .items = &.{} },
        .{ .id = "legs", .name = "Legs", .items = &.{} },
    };
    const ppl_ids = [_][]const u8{ "push", "pull", "legs" };
    const weekdays = [_]WeekdayEntry{
        .{ .weekday = .monday, .role_id = "upper-a" },
        .{ .weekday = .tuesday, .role_id = "lower-a" },
        .{ .weekday = .thursday, .role_id = "upper-b" },
        .{ .weekday = .saturday, .role_id = "lower-b" },
    };
    const chest_priority = [_]MusclePriority{.{ .muscle_id = "chest", .priority = .emphasize }};
    const accumulation = [_]Block{.{
        .id = "accumulation",
        .name = "Accumulation",
        .phase = .accumulation,
        .length = .{ .completed_microcycles = 5 },
        .schedule = .{ .rotation = .{ .role_ids = &upper_lower_ids, .frequency = .{ .sessions = 4, .days = 7 } } },
        .roles = &upper_lower_roles,
        .muscle_priorities = &chest_priority,
        .next_block_id = "deload",
    }};
    const deload = [_]Block{.{
        .id = "deload",
        .name = "Planned deload",
        .phase = .deload,
        .length = .{ .completed_microcycles = 1 },
        .schedule = .{ .rotation = .{ .role_ids = &upper_lower_ids, .frequency = .{ .sessions = 4, .days = 7 } } },
        .roles = &upper_lower_roles,
        .muscle_priorities = &chest_priority,
    }};

    pub fn asynchronousUpperLower(fingerprint: []const u8) ProgramDefinition {
        const blocks = struct {
            const value = [_]Block{.{ .id = "rotation", .name = "Upper/lower rotation", .length = .manual, .schedule = .{ .rotation = .{ .role_ids = &upper_lower_ids, .frequency = .{ .sessions = 4, .days = 7 } } }, .roles = &upper_lower_roles }};
        }.value;
        return .{ .id = "caudex.asynchronous-upper-lower", .version = 1, .display_name = "Asynchronous upper/lower", .configuration_fingerprint = fingerprint, .source = "caudex", .blocks = &blocks };
    }

    pub fn fixedWeekdayUpperLower(fingerprint: []const u8) ProgramDefinition {
        const blocks = struct {
            const value = [_]Block{.{ .id = "weekly", .name = "Weekday upper/lower", .length = .manual, .schedule = .{ .fixed_weekdays = .{ .entries = &weekdays } }, .roles = &upper_lower_roles }};
        }.value;
        return .{ .id = "caudex.fixed-weekday-upper-lower", .version = 1, .display_name = "Fixed weekday upper/lower", .configuration_fingerprint = fingerprint, .source = "caudex", .blocks = &blocks };
    }

    pub fn pplRotation(fingerprint: []const u8) ProgramDefinition {
        const blocks = struct {
            const value = [_]Block{.{ .id = "rotation", .name = "PPL rotation", .length = .manual, .schedule = .{ .rotation = .{ .role_ids = &ppl_ids } }, .roles = &ppl_roles }};
        }.value;
        return .{ .id = "caudex.ppl-rotation", .version = 1, .display_name = "Push/pull/legs rotation", .configuration_fingerprint = fingerprint, .source = "caudex", .blocks = &blocks };
    }

    pub fn structuredHypertrophyBlock(fingerprint: []const u8) ProgramDefinition {
        const blocks = struct {
            const value = accumulation ++ deload;
        }.value;
        return .{ .id = "caudex.structured-hypertrophy-block", .version = 1, .display_name = "Structured hypertrophy block", .configuration_fingerprint = fingerprint, .source = "caudex", .blocks = &blocks };
    }
};

test "asynchronous sequence advances only after explicit completion" {
    const method: programming.Method = .{ .double_progression = .{ .config = undefined } };
    const roles = [_]SessionRole{
        .{ .id = "upper-a", .name = "Upper A", .items = &.{.{ .fixed = .{ .id = "bench", .exercise_id = "bench", .progression = .{ .state_id = "bench", .method = method } } }} },
        .{ .id = "lower-a", .name = "Lower A", .items = &.{.{ .fixed = .{ .id = "squat", .exercise_id = "squat", .progression = .{ .state_id = "squat", .method = method } } }} },
    };
    const ids = [_][]const u8{ "upper-a", "lower-a" };
    const blocks = [_]Block{.{ .id = "block", .name = "Block", .length = .{ .completed_microcycles = 2 }, .schedule = .{ .rotation = .{ .role_ids = &ids } }, .roles = &roles }};
    const definition: ProgramDefinition = .{ .id = "ul", .version = 1, .display_name = "UL", .configuration_fingerprint = "v1", .blocks = &blocks };
    const instance: ProgramInstance = .{ .id = "run", .athlete_id = "athlete", .definition = definitionRef(definition), .lifecycle = .active };
    var occurrence: [256]u8 = undefined;
    const planned = try resolvePlannedSession(&occurrence, definition, instance, initialState(instance), .{ .iso_date = "2026-08-10", .weekday = .monday });
    try std.testing.expectEqualStrings("upper-a", planned.role.id);
    const proposal = try proposeAdvancement(definition, initialState(instance), planned, .completed);
    try std.testing.expectEqualStrings("lower-a", (try resolvePlannedSession(&occurrence, definition, instance, proposal.outcome.advance, .{ .iso_date = "2026-09-01", .weekday = .tuesday })).role.id);
}

test "fixed weekday resolution uses explicit calendar input" {
    const definition = presets.fixedWeekdayUpperLower("fixture-v1");
    const instance: ProgramInstance = .{
        .id = "weekday-run",
        .athlete_id = "athlete",
        .definition = definitionRef(definition),
        .lifecycle = .active,
    };
    var occurrence: [256]u8 = undefined;
    const planned = try resolvePlannedSession(
        &occurrence,
        definition,
        instance,
        initialState(instance),
        .{ .iso_date = "2026-08-10", .weekday = .monday },
    );
    try std.testing.expectEqualStrings("upper-a", planned.role.id);
    try std.testing.expectEqual(OccurrenceStatus.due, planned.occurrence.status);
    try std.testing.expectError(
        error.NoScheduledSession,
        resolvePlannedSession(
            &occurrence,
            definition,
            instance,
            initialState(instance),
            .{ .iso_date = "2026-08-12", .weekday = .wednesday },
        ),
    );
}

test "lifecycle and compatibility changes are explicit proposals" {
    const base = presets.asynchronousUpperLower("fixture-v1");
    var definition = base;
    definition.compatibility = .{
        .minimum_sessions_per_week = 4,
        .required_equipment_ids = &.{"barbell"},
        .suitable_experience = &.{.intermediate},
    };
    const instance: ProgramInstance = .{
        .id = "run",
        .athlete_id = "athlete",
        .definition = definitionRef(definition),
    };
    const start = proposeLifecycle(instance, .active).?;
    const active = acceptLifecycle(instance, start).?;
    try std.testing.expectEqual(Lifecycle.active, active.lifecycle);
    try std.testing.expect(proposeLifecycle(active, .created) == null);

    const profile: athlete_profile.AthleteProfile = .{
        .id = "athlete",
        .experience = .{ .resistance_training = .novice },
        .schedule = .{ .maximum_sessions_per_week = 3 },
    };
    var issue_storage: [8]Issue = undefined;
    const issues = try validateCompatibility(definition, profile, &issue_storage);
    try std.testing.expectEqual(@as(usize, 3), issues.len);
    try std.testing.expectEqualStrings("program.compatibility.frequency_exceeded", issues[0].code);
}

test "planned intent materializes mixed fixed and dynamic slots upstream of composition" {
    const method: programming.Method = .{ .double_progression = .{ .config = undefined } };
    const items = [_]SessionItem{
        .{ .fixed = .{ .id = "press", .exercise_id = "bench-press", .progression = .{ .state_id = "press-lane", .method = method } } },
        .{ .slot = .{ .id = "pull", .pool = .{ .exercise_ids = &.{ "cable-row", "barbell-row" } }, .progression = .{ .state_id = "pull-lane", .method = method } } },
    };
    const roles = [_]SessionRole{.{ .id = "upper", .name = "Upper", .items = &items }};
    const role_ids = [_][]const u8{"upper"};
    const blocks = [_]Block{.{ .id = "block", .name = "Block", .length = .manual, .schedule = .{ .rotation = .{ .role_ids = &role_ids } }, .roles = &roles }};
    const definition: ProgramDefinition = .{ .id = "mixed", .version = 1, .display_name = "Mixed", .configuration_fingerprint = "mixed-v1", .blocks = &blocks };
    const instance: ProgramInstance = .{ .id = "run", .athlete_id = "athlete", .definition = definitionRef(definition), .lifecycle = .active };
    const exercises = [_]training.Exercise{
        .{ .id = try .parse("bench-press") },
        .{ .id = try .parse("barbell-row") },
        .{ .id = try .parse("cable-row") },
    };
    var occurrence: [256]u8 = undefined;
    const intent = try resolvePlannedSession(&occurrence, definition, instance, initialState(instance), null);
    var slot_storage: [2]programming.ExerciseSlot = undefined;
    const slots = try materializeBasicSlots(intent, .{ .exercises = &exercises }, &slot_storage);
    try std.testing.expectEqualStrings("bench-press", slots[0].exercise_id.bytes);
    try std.testing.expectEqualStrings("cable-row", slots[1].exercise_id.bytes);
    try std.testing.expectEqualStrings("pull-lane", slots[1].state_id.bytes);
}
