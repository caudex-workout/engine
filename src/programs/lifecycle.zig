//! Deterministic occurrence resolution and explicit program-state proposals.
//!
//! Lifecycle selects a due definition role and resolves progression
//! inheritance. It does not inspect a catalog, choose an exercise, prescribe
//! training, or accept any proposal on the host's behalf.

const std = @import("std");
const primitives = @import("../primitives.zig");
const definition = @import("definition.zig");
const intent = @import("intent.zig");

pub const schema_version: u32 = 1;
pub const max_occurrence_id_bytes: usize = 200;

pub const Lifecycle = enum {
    created,
    active,
    paused,
    completed,
    ended,
};

pub const OccurrenceStatus = enum {
    upcoming,
    due,
    overdue,
    completed,
    skipped,
    partial,
    abandoned,
};

pub const ProgramInstance = struct {
    schema_version: u32 = schema_version,
    id: primitives.Id,
    athlete_id: primitives.Id,
    definition: definition.DefinitionRef,
    lifecycle: Lifecycle = .created,
    started_on: ?[]const u8 = null,
};

pub const ProgramState = struct {
    schema_version: u32 = schema_version,
    instance_id: primitives.Id,
    definition: definition.DefinitionRef,
    revision: u64,
    block_index: u16 = 0,
    microcycle_index: u32 = 0,
    session_cursor: u16 = 0,
    completed_occurrences: u64 = 0,
    block_completed_occurrences: u32 = 0,
    complete: bool = false,
};

pub const LocalDate = struct {
    iso_date: []const u8,
    weekday: definition.Weekday,
};

pub const SchedulingProvenance = enum {
    rotation_next,
    weekday_match,
    frequency_sequence,
    explicit_date,
    hybrid_sequence,
};

pub const Occurrence = struct {
    id: primitives.Id,
    instance_id: primitives.Id,
    block_id: primitives.Id,
    microcycle_index: u32,
    role_id: primitives.Id,
    sequence_index: u16,
    scheduled_date: ?[]const u8,
    status: OccurrenceStatus,
    scheduling_provenance: SchedulingProvenance,
};

/// Lifecycle metadata accompanies the authoritative planner-facing intent.
pub const ResolvedSession = struct {
    intent: intent.PlannedSessionIntent,
    occurrence: Occurrence,
    block_phase: definition.Phase,
};

pub const ResolveError = error{
    InvalidDefinition,
    StateMismatch,
    InvalidCursor,
    NoScheduledSession,
    OutputTooSmall,
};

pub fn initialState(instance: ProgramInstance) ProgramState {
    return .{
        .instance_id = instance.id,
        .definition = instance.definition,
        .revision = 0,
    };
}

/// Resolves the next occurrence into fully planner-ready intent.
///
/// The result borrows definition/instance/state inputs plus the populated
/// prefixes of both storage slices. The host must retain those values through
/// planning.
pub fn resolvePlannedSession(
    occurrence_storage: []u8,
    slot_storage: []intent.Slot,
    program: definition.ProgramDefinition,
    instance: ProgramInstance,
    state: ProgramState,
    local_date: ?LocalDate,
) ResolveError!ResolvedSession {
    var validation_storage: [64]definition.Issue = undefined;
    const issues = definition.validate(program, &validation_storage) catch
        return error.OutputTooSmall;
    if (issues.len != 0) return error.InvalidDefinition;
    if (instance.schema_version != schema_version or state.schema_version != schema_version)
        return error.StateMismatch;
    if (!definition.referencesEqual(instance.definition, definition.reference(program)) or
        !definition.referencesEqual(state.definition, instance.definition) or
        !state.instance_id.eql(instance.id))
        return error.StateMismatch;
    if (instance.lifecycle != .active or state.complete) return error.InvalidCursor;
    if (state.block_index >= program.blocks.len) return error.InvalidCursor;

    const block = program.blocks[state.block_index];
    const choice = try chooseRole(block, state, local_date);
    const role = definition.findRole(block, choice.role_id) orelse
        return error.InvalidDefinition;
    if (slot_storage.len < role.items.len) return error.OutputTooSmall;

    for (role.items, 0..) |item, index| {
        slot_storage[index] = .{
            .id = item.id,
            .presence = item.presence,
            .selection = item.selection,
            .progression = definition.resolveProgression(block, role, item) orelse
                return error.InvalidDefinition,
            .ordering = item.ordering,
        };
    }

    if (choice.scheduled_date) |date| if (date.len > 32) return error.InvalidDefinition;
    const occurrence_bytes = try occurrenceId(
        occurrence_storage,
        instance.id,
        block.id,
        state.microcycle_index,
        state.session_cursor,
        role.id,
        choice.scheduled_date,
    );
    const occurrence_id = primitives.Id.parse(occurrence_bytes) catch
        return error.InvalidDefinition;
    const occurrence: Occurrence = .{
        .id = occurrence_id,
        .instance_id = instance.id,
        .block_id = block.id,
        .microcycle_index = state.microcycle_index,
        .role_id = role.id,
        .sequence_index = state.session_cursor,
        .scheduled_date = choice.scheduled_date,
        .status = choice.status,
        .scheduling_provenance = choice.provenance,
    };
    return .{
        .intent = .{
            .definition_id = program.id,
            .definition_version = program.version,
            .definition_fingerprint = program.fingerprint,
            .instance_id = instance.id,
            .occurrence_id = occurrence_id,
            .block_id = block.id,
            .role_id = role.id,
            .planning_state_revision = state.revision,
            .strategy = program.strategy,
            .slots = slot_storage[0..role.items.len],
        },
        .occurrence = occurrence,
        .block_phase = block.phase,
    };
}

fn occurrenceId(
    storage: []u8,
    instance_id: primitives.Id,
    block_id: primitives.Id,
    microcycle_index: u32,
    session_cursor: u16,
    role_id: primitives.Id,
    scheduled_date: ?[]const u8,
) error{OutputTooSmall}![]const u8 {
    if (storage.len < 64) return error.OutputTooSmall;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("caudex:program-occurrence:v1\x00");
    const parts = [_][]const u8{
        instance_id.bytes,
        block_id.bytes,
        role_id.bytes,
        scheduled_date orelse "",
    };
    for (parts) |part| {
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, part.len, .big);
        hash.update(&length);
        hash.update(part);
    }
    var number: [4]u8 = undefined;
    std.mem.writeInt(u32, &number, microcycle_index, .big);
    hash.update(&number);
    var cursor: [2]u8 = undefined;
    std.mem.writeInt(u16, &cursor, session_cursor, .big);
    hash.update(&cursor);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const alphabet = "0123456789abcdef";
    for (digest, 0..) |byte, index| {
        storage[index * 2] = alphabet[byte >> 4];
        storage[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return storage[0..64];
}

pub const Completion = enum {
    completed,
    substituted_completed,
    partial,
    abandoned,
    unrelated,
    skipped,
};

pub const ProposalOutcome = union(enum) {
    advance: ProgramState,
    require_host_policy,
    no_change,
};

pub const ProgramStateProposal = struct {
    expected_revision: u64,
    occurrence_id: primitives.Id,
    outcome: ProposalOutcome,
    explanation_code: []const u8,
};

pub fn proposeAdvancement(
    program: definition.ProgramDefinition,
    state: ProgramState,
    planned: ResolvedSession,
    completion: Completion,
) ResolveError!ProgramStateProposal {
    if (!definition.referencesEqual(state.definition, definition.reference(program)) or
        !definition.referencesEqual(state.definition, .{
            .id = planned.intent.definition_id,
            .version = planned.intent.definition_version,
            .fingerprint = planned.intent.definition_fingerprint,
        }) or !state.instance_id.eql(planned.intent.instance_id) or
        planned.intent.planning_state_revision != state.revision)
        return error.StateMismatch;
    if (state.block_index >= program.blocks.len) return error.InvalidCursor;

    const block = program.blocks[state.block_index];
    const expected_role_id = roleAtCursor(block.schedule, state.session_cursor) orelse
        return error.InvalidCursor;
    if (!planned.intent.block_id.eql(block.id) or
        !planned.intent.role_id.eql(expected_role_id) or
        !planned.occurrence.block_id.eql(block.id) or
        !planned.occurrence.role_id.eql(expected_role_id) or
        planned.occurrence.microcycle_index != state.microcycle_index or
        planned.occurrence.sequence_index != state.session_cursor or
        !planned.occurrence.id.eql(planned.intent.occurrence_id))
        return error.StateMismatch;

    var occurrence_storage: [max_occurrence_id_bytes]u8 = undefined;
    const expected_occurrence_bytes = occurrenceId(
        &occurrence_storage,
        state.instance_id,
        block.id,
        state.microcycle_index,
        state.session_cursor,
        expected_role_id,
        planned.occurrence.scheduled_date,
    ) catch return error.InvalidCursor;
    if (!std.mem.eql(u8, planned.occurrence.id.bytes, expected_occurrence_bytes))
        return error.StateMismatch;

    if (completion == .partial or completion == .abandoned)
        return .{
            .expected_revision = state.revision,
            .occurrence_id = planned.occurrence.id,
            .outcome = .require_host_policy,
            .explanation_code = "program.transition.ambiguous_completion",
        };
    if (completion == .unrelated)
        return .{
            .expected_revision = state.revision,
            .occurrence_id = planned.occurrence.id,
            .outcome = .no_change,
            .explanation_code = "program.transition.unrelated_workout",
        };

    var next = state;
    next.revision = std.math.add(u64, next.revision, 1) catch
        return error.InvalidCursor;
    next.completed_occurrences = std.math.add(u64, next.completed_occurrences, 1) catch
        return error.InvalidCursor;
    next.block_completed_occurrences = std.math.add(
        u32,
        next.block_completed_occurrences,
        1,
    ) catch return error.InvalidCursor;

    const sequence_len = scheduleLength(block.schedule);
    if (sequence_len == 0) return error.InvalidDefinition;
    next.session_cursor = std.math.add(u16, next.session_cursor, 1) catch
        return error.InvalidCursor;
    if (next.session_cursor >= sequence_len) {
        next.session_cursor = 0;
        next.microcycle_index = std.math.add(u32, next.microcycle_index, 1) catch
            return error.InvalidCursor;
    }
    if (blockComplete(block, next)) {
        if (block.next_block_id) |next_id| {
            next.block_index = @intCast(definition.findBlockIndex(program, next_id) orelse
                return error.InvalidDefinition);
            resetBlockCursor(&next);
        } else if (@as(usize, state.block_index) + 1 < program.blocks.len) {
            next.block_index = std.math.add(u16, next.block_index, 1) catch
                return error.InvalidCursor;
            resetBlockCursor(&next);
        } else {
            next.complete = true;
        }
    }
    return .{
        .expected_revision = state.revision,
        .occurrence_id = planned.occurrence.id,
        .outcome = .{ .advance = next },
        .explanation_code = if (completion == .skipped)
            "program.transition.explicit_skip"
        else
            "program.transition.session_completed",
    };
}

/// Accepts only the exact advancement proposed for the current revision.
/// Hosts remain responsible for persisting the returned snapshot.
pub fn acceptAdvancement(
    current: ProgramState,
    proposal: ProgramStateProposal,
) ?ProgramState {
    if (current.revision != proposal.expected_revision) return null;
    const expected_next_revision = std.math.add(u64, current.revision, 1) catch
        return null;
    return switch (proposal.outcome) {
        .advance => |next| if (next.revision == expected_next_revision and
            next.instance_id.eql(current.instance_id) and
            definition.referencesEqual(next.definition, current.definition))
            next
        else
            null,
        .require_host_policy, .no_change => null,
    };
}

pub const LifecycleProposal = struct {
    expected_lifecycle: Lifecycle,
    proposed_lifecycle: Lifecycle,
    explanation_code: []const u8,
};

pub fn proposeLifecycle(
    instance: ProgramInstance,
    requested: Lifecycle,
) ?LifecycleProposal {
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

/// Accepts a lifecycle proposal only against its expected snapshot.
pub fn acceptLifecycle(
    instance: ProgramInstance,
    proposal: LifecycleProposal,
) ?ProgramInstance {
    if (instance.lifecycle != proposal.expected_lifecycle) return null;
    var accepted = instance;
    accepted.lifecycle = proposal.proposed_lifecycle;
    return accepted;
}

const Choice = struct {
    role_id: primitives.Id,
    scheduled_date: ?[]const u8,
    status: OccurrenceStatus,
    provenance: SchedulingProvenance,
};

fn chooseRole(
    block: definition.Block,
    state: ProgramState,
    local_date: ?LocalDate,
) ResolveError!Choice {
    return switch (block.schedule) {
        .rotation => |schedule| sequenceChoice(
            schedule.role_ids,
            state,
            null,
            .rotation_next,
        ),
        .frequency_targeted => |schedule| sequenceChoice(
            schedule.role_ids,
            state,
            null,
            .frequency_sequence,
        ),
        .hybrid => |schedule| sequenceChoice(
            schedule.role_ids,
            state,
            if (local_date) |date| date.iso_date else null,
            .hybrid_sequence,
        ),
        .fixed_weekdays => |schedule| blk: {
            const date = local_date orelse return error.NoScheduledSession;
            if (state.session_cursor >= schedule.entries.len)
                return error.InvalidCursor;
            const entry = schedule.entries[state.session_cursor];
            if (entry.weekday != date.weekday) return error.NoScheduledSession;
            break :blk .{
                .role_id = entry.role_id,
                .scheduled_date = date.iso_date,
                .status = .due,
                .provenance = .weekday_match,
            };
        },
        .explicit_dates => |schedule| blk: {
            const date = local_date orelse return error.NoScheduledSession;
            if (state.session_cursor >= schedule.entries.len)
                return error.InvalidCursor;
            const entry = schedule.entries[state.session_cursor];
            break :blk .{
                .role_id = entry.role_id,
                .scheduled_date = entry.local_date,
                .status = switch (std.mem.order(u8, entry.local_date, date.iso_date)) {
                    .lt => .overdue,
                    .eq => .due,
                    .gt => .upcoming,
                },
                .provenance = .explicit_date,
            };
        },
    };
}

fn sequenceChoice(
    role_ids: []const primitives.Id,
    state: ProgramState,
    scheduled_date: ?[]const u8,
    provenance: SchedulingProvenance,
) ResolveError!Choice {
    if (role_ids.len == 0 or state.session_cursor >= role_ids.len)
        return error.InvalidCursor;
    return .{
        .role_id = role_ids[state.session_cursor],
        .scheduled_date = scheduled_date,
        .status = .upcoming,
        .provenance = provenance,
    };
}

fn scheduleLength(schedule: definition.Schedule) u16 {
    const length = switch (schedule) {
        .rotation => |value| value.role_ids.len,
        .frequency_targeted => |value| value.role_ids.len,
        .hybrid => |value| value.role_ids.len,
        .fixed_weekdays => |value| value.entries.len,
        .explicit_dates => |value| value.entries.len,
    };
    return @intCast(length);
}

fn roleAtCursor(
    schedule: definition.Schedule,
    cursor: u16,
) ?primitives.Id {
    const index: usize = cursor;
    return switch (schedule) {
        .rotation => |value| if (index < value.role_ids.len) value.role_ids[index] else null,
        .frequency_targeted => |value| if (index < value.role_ids.len) value.role_ids[index] else null,
        .hybrid => |value| if (index < value.role_ids.len) value.role_ids[index] else null,
        .fixed_weekdays => |value| if (index < value.entries.len) value.entries[index].role_id else null,
        .explicit_dates => |value| if (index < value.entries.len) value.entries[index].role_id else null,
    };
}

fn blockComplete(block: definition.Block, next: ProgramState) bool {
    return switch (block.length) {
        .completed_occurrences => |count| next.block_completed_occurrences >= count,
        .completed_microcycles => |count| next.microcycle_index >= count,
        .calendar_weeks, .explicit_end_date, .manual => false,
    };
}

fn resetBlockCursor(state: *ProgramState) void {
    state.microcycle_index = 0;
    state.session_cursor = 0;
    state.block_completed_occurrences = 0;
}

test "resolution preserves selection policy and resolves progression lanes" {
    const program_id = try primitives.Id.parse("program:upper-lower");
    const instance_id = try primitives.Id.parse("instance:one");
    const athlete_id = try primitives.Id.parse("athlete:one");
    const block_id = try primitives.Id.parse("block:base");
    const role_id = try primitives.Id.parse("role:upper");
    const fixed_slot_id = try primitives.Id.parse("slot:press");
    const adaptive_slot_id = try primitives.Id.parse("slot:row");
    const exercise_id = try primitives.Id.parse("exercise:press");
    const lane_id = try primitives.Id.parse("lane:upper");
    const accessory_lane_id = try primitives.Id.parse("lane:upper-accessory");
    const role_ids = [_]primitives.Id{role_id};
    const lane = @import("../progression/root.zig").Lane{
        .state_id = lane_id,
        .method = .{ .double_progression = .{ .config = undefined } },
    };
    const items = [_]definition.Item{
        .{ .id = fixed_slot_id, .selection = .{ .fixed = exercise_id } },
        .{
            .id = adaptive_slot_id,
            .presence = .optional,
            .selection = .{ .adaptive = .{} },
            .progression = .{
                .state_id = accessory_lane_id,
                .method = .{ .double_progression = .{ .config = undefined } },
            },
        },
    };
    const roles = [_]definition.Role{.{
        .id = role_id,
        .name = "Upper",
        .items = &items,
        .default_progression = lane,
    }};
    const blocks = [_]definition.Block{.{
        .id = block_id,
        .name = "Base",
        .length = .{ .completed_occurrences = 1 },
        .schedule = .{ .rotation = .{ .role_ids = &role_ids } },
        .roles = &roles,
    }};
    const program: definition.ProgramDefinition = .{
        .id = program_id,
        .version = 1,
        .display_name = "Upper/lower",
        .fingerprint = "definition-v1",
        .blocks = &blocks,
    };
    const instance: ProgramInstance = .{
        .id = instance_id,
        .athlete_id = athlete_id,
        .definition = definition.reference(program),
        .lifecycle = .active,
    };
    var occurrence_storage: [max_occurrence_id_bytes]u8 = undefined;
    var slots: [2]intent.Slot = undefined;

    const resolved = try resolvePlannedSession(
        &occurrence_storage,
        &slots,
        program,
        instance,
        initialState(instance),
        null,
    );

    try std.testing.expectEqual(@as(usize, 2), resolved.intent.slots.len);
    try std.testing.expect(resolved.intent.slots[0].selection == .fixed);
    try std.testing.expect(resolved.intent.slots[1].selection == .adaptive);
    try std.testing.expectEqual(intent.Presence.optional, resolved.intent.slots[1].presence);
    try std.testing.expect(resolved.intent.slots[0].progression.state_id.eql(lane_id));
    try std.testing.expect(resolved.intent.slots[1].progression.state_id.eql(accessory_lane_id));
}

test "advancement and lifecycle changes remain explicit proposals" {
    const program_id = try primitives.Id.parse("program:rotation");
    const instance_id = try primitives.Id.parse("instance:rotation");
    const athlete_id = try primitives.Id.parse("athlete:rotation");
    const block_id = try primitives.Id.parse("block:rotation");
    const role_id = try primitives.Id.parse("role:session");
    const slot_id = try primitives.Id.parse("slot:work");
    const exercise_id = try primitives.Id.parse("exercise:work");
    const lane_id = try primitives.Id.parse("lane:work");
    const role_ids = [_]primitives.Id{role_id};
    const items = [_]definition.Item{.{
        .id = slot_id,
        .selection = .{ .fixed = exercise_id },
        .progression = .{
            .state_id = lane_id,
            .method = .{ .double_progression = .{ .config = undefined } },
        },
    }};
    const roles = [_]definition.Role{.{ .id = role_id, .name = "Session", .items = &items }};
    const blocks = [_]definition.Block{.{
        .id = block_id,
        .name = "Rotation",
        .length = .{ .completed_occurrences = 1 },
        .schedule = .{ .rotation = .{ .role_ids = &role_ids } },
        .roles = &roles,
    }};
    const program: definition.ProgramDefinition = .{
        .id = program_id,
        .version = 1,
        .display_name = "Rotation",
        .fingerprint = "definition-v1",
        .blocks = &blocks,
    };
    const created: ProgramInstance = .{
        .id = instance_id,
        .athlete_id = athlete_id,
        .definition = definition.reference(program),
    };
    const start = proposeLifecycle(created, .active).?;
    const active = acceptLifecycle(created, start).?;
    try std.testing.expectEqual(Lifecycle.active, active.lifecycle);
    try std.testing.expect(proposeLifecycle(active, .created) == null);

    const state = initialState(active);
    var occurrence_storage: [max_occurrence_id_bytes]u8 = undefined;
    var slots: [1]intent.Slot = undefined;
    const resolved = try resolvePlannedSession(
        &occurrence_storage,
        &slots,
        program,
        active,
        state,
        null,
    );
    const proposal = try proposeAdvancement(program, state, resolved, .completed);
    const accepted = acceptAdvancement(state, proposal).?;

    try std.testing.expectEqual(@as(u64, 1), accepted.revision);
    try std.testing.expect(accepted.complete);
    try std.testing.expect(acceptAdvancement(accepted, proposal) == null);
}
