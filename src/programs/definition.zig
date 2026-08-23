//! Immutable program definitions and their structural validation.
//!
//! Definitions describe scheduling and session composition policy. Exercise
//! search is deliberately absent: fixed and adaptive selections are copied
//! into resolved session intent for the shared planner.

const std = @import("std");
const primitives = @import("../primitives.zig");
const progression = @import("../progression/root.zig");
const intent = @import("intent.zig");

pub const schema_version: u32 = 1;
pub const max_blocks: usize = 32;
pub const max_roles_per_block: usize = 64;
pub const max_items_per_role: usize = 16;
pub const max_schedule_entries: usize = 366;

pub const Phase = enum {
    base,
    accumulation,
    intensification,
    realization,
    deload,
    custom,
};

pub const Weekday = enum {
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,
    sunday,
};

pub const DefinitionRef = struct {
    id: primitives.Id,
    version: u32,
    fingerprint: []const u8,
};

/// A definition item may inherit its progression lane from its role or block.
/// Resolution removes this optionality before producing planner intent.
pub const Item = struct {
    id: primitives.Id,
    presence: intent.Presence = .required,
    selection: intent.Selection,
    progression: ?progression.Lane = null,
    ordering: intent.Ordering = .{},
};

pub const Role = struct {
    id: primitives.Id,
    name: []const u8,
    purpose: ?[]const u8 = null,
    items: []const Item,
    default_progression: ?progression.Lane = null,
    expected_duration_minutes: ?u16 = null,
};

pub const WeekdayEntry = struct {
    weekday: Weekday,
    role_id: primitives.Id,
};

pub const DatedEntry = struct {
    local_date: []const u8,
    role_id: primitives.Id,
};

pub const FrequencyTarget = struct {
    sessions: u8,
    days: u16,
};

pub const Schedule = union(enum) {
    rotation: struct {
        role_ids: []const primitives.Id,
        frequency: ?FrequencyTarget = null,
    },
    fixed_weekdays: struct { entries: []const WeekdayEntry },
    frequency_targeted: struct {
        role_ids: []const primitives.Id,
        target: FrequencyTarget,
    },
    explicit_dates: struct { entries: []const DatedEntry },
    hybrid: struct {
        role_ids: []const primitives.Id,
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
    id: primitives.Id,
    name: []const u8,
    phase: Phase = .base,
    phase_semantic: ?[]const u8 = null,
    length: Length,
    schedule: Schedule,
    roles: []const Role,
    default_progression: ?progression.Lane = null,
    next_block_id: ?primitives.Id = null,
};

pub const ProgramDefinition = struct {
    schema_version: u32 = schema_version,
    id: primitives.Id,
    version: u32,
    display_name: []const u8,
    description: ?[]const u8 = null,
    fingerprint: []const u8,
    source: ?[]const u8 = null,
    strategy: intent.Strategy = .fixed,
    blocks: []const Block,
};

pub const Issue = struct {
    code: []const u8,
    path: []const u8,
    message: []const u8,
};

pub fn reference(program: ProgramDefinition) DefinitionRef {
    return .{
        .id = program.id,
        .version = program.version,
        .fingerprint = program.fingerprint,
    };
}

pub fn referencesEqual(left: DefinitionRef, right: DefinitionRef) bool {
    return left.id.eql(right.id) and
        left.version == right.version and
        std.mem.eql(u8, left.fingerprint, right.fingerprint);
}

pub fn resolveProgression(block: Block, role: Role, item: Item) ?progression.Lane {
    return item.progression orelse role.default_progression orelse block.default_progression;
}

/// Validates bounded structure and references into caller-owned issue storage.
/// Every resolvable problem is reported until `storage` is exhausted.
pub fn validate(
    program: ProgramDefinition,
    storage: []Issue,
) error{OutputTooSmall}![]const Issue {
    var count: usize = 0;
    if (program.schema_version != schema_version or program.version == 0 or
        program.fingerprint.len == 0)
        try appendIssue(
            storage,
            &count,
            "program.definition.identity_invalid",
            "/definition",
            "Program identity, version, and fingerprint are required.",
        );
    if (program.blocks.len == 0 or program.blocks.len > max_blocks) {
        try appendIssue(
            storage,
            &count,
            "program.definition.blocks_invalid",
            "/definition/blocks",
            "A program requires a bounded non-empty block sequence.",
        );
        return storage[0..count];
    }

    for (program.blocks, 0..) |block, block_index| {
        if (block.roles.len == 0 or block.roles.len > max_roles_per_block) {
            try appendIssue(
                storage,
                &count,
                "program.block.roles_invalid",
                "/definition/blocks/roles",
                "Each block requires bounded session roles.",
            );
            continue;
        }
        for (program.blocks[0..block_index]) |prior| {
            if (block.id.eql(prior.id))
                try appendIssue(
                    storage,
                    &count,
                    "program.block.id_duplicate",
                    "/definition/blocks/id",
                    "Block IDs must be unique.",
                );
        }

        for (block.roles, 0..) |role, role_index| {
            if (role.items.len == 0 or role.items.len > max_items_per_role) {
                try appendIssue(
                    storage,
                    &count,
                    "program.role.items_exceeded",
                    "/definition/blocks/roles/items",
                    "A session role requires a bounded non-empty item list.",
                );
                continue;
            }
            for (block.roles[0..role_index]) |prior| {
                if (role.id.eql(prior.id))
                    try appendIssue(
                        storage,
                        &count,
                        "program.role.id_duplicate",
                        "/definition/blocks/roles/id",
                        "Session-role IDs must be unique within a block.",
                    );
            }

            for (role.items, 0..) |item, item_index| {
                for (role.items[0..item_index]) |prior| {
                    if (item.id.eql(prior.id))
                        try appendIssue(
                            storage,
                            &count,
                            "program.item.id_duplicate",
                            "/definition/blocks/roles/items/id",
                            "Session item IDs must be unique within a role.",
                        );
                }
                if (resolveProgression(block, role, item) == null)
                    try appendIssue(
                        storage,
                        &count,
                        "progression.assignment_missing",
                        "/definition/blocks/roles/items/progression",
                        "Every item needs one resolved progression lane.",
                    );
                try validateOrdering(role, item, storage, &count);
            }
        }

        try validateLaneMethods(block, storage, &count);
        try validateSchedule(block, storage, &count);
        if (block.next_block_id) |next| {
            if (findBlock(program, next) == null)
                try appendIssue(
                    storage,
                    &count,
                    "program.transition.target_unknown",
                    "/definition/blocks/nextBlockId",
                    "The next block reference is unknown.",
                );
        }
    }
    return storage[0..count];
}

fn validateLaneMethods(
    block: Block,
    storage: []Issue,
    count: *usize,
) error{OutputTooSmall}!void {
    for (block.roles, 0..) |role, role_index| {
        for (role.items, 0..) |item, item_index| {
            const lane = resolveProgression(block, role, item) orelse continue;
            for (block.roles[0..role_index]) |prior_role| {
                for (prior_role.items) |prior_item| {
                    const prior = resolveProgression(block, prior_role, prior_item) orelse continue;
                    if (lane.state_id.eql(prior.state_id))
                        try appendAmbiguousLane(storage, count);
                }
            }
            for (role.items[0..item_index]) |prior_item| {
                const prior = resolveProgression(block, role, prior_item) orelse continue;
                if (lane.state_id.eql(prior.state_id))
                    try appendAmbiguousLane(storage, count);
            }
        }
    }
}

fn appendAmbiguousLane(storage: []Issue, count: *usize) error{OutputTooSmall}!void {
    try appendIssue(
        storage,
        count,
        "progression.assignment_ambiguous",
        "/definition/blocks/roles/items/progression/stateId",
        "A progression state lane must be unique within a block.",
    );
}

fn validateSchedule(
    block: Block,
    storage: []Issue,
    count: *usize,
) error{OutputTooSmall}!void {
    const role_ids: []const primitives.Id = switch (block.schedule) {
        .rotation => |schedule| schedule.role_ids,
        .frequency_targeted => |schedule| schedule.role_ids,
        .hybrid => |schedule| schedule.role_ids,
        .fixed_weekdays, .explicit_dates => &.{},
    };
    if (role_ids.len == 0 and switch (block.schedule) {
        .rotation, .frequency_targeted, .hybrid => true,
        .fixed_weekdays, .explicit_dates => false,
    })
        try appendIssue(
            storage,
            count,
            "program.schedule.rotation_empty",
            "/definition/blocks/schedule",
            "Sequence schedules require a non-empty rotation.",
        );
    if (role_ids.len > max_schedule_entries) {
        try appendScheduleTooLong(storage, count);
        return;
    }
    for (role_ids) |role_id| {
        if (findRole(block, role_id) == null)
            try appendUnknownRole(storage, count);
    }

    switch (block.schedule) {
        .fixed_weekdays => |schedule| {
            if (schedule.entries.len == 0 or schedule.entries.len > max_schedule_entries) {
                try appendScheduleEntriesInvalid(storage, count);
                return;
            }
            for (schedule.entries, 0..) |entry, index| {
                if (findRole(block, entry.role_id) == null)
                    try appendUnknownRole(storage, count);
                for (schedule.entries[0..index]) |prior| {
                    if (entry.weekday == prior.weekday)
                        try appendIssue(
                            storage,
                            count,
                            "program.schedule.weekday_duplicate",
                            "/definition/blocks/schedule",
                            "Only one role per weekday is supported.",
                        );
                }
            }
        },
        .explicit_dates => |schedule| {
            if (schedule.entries.len == 0 or schedule.entries.len > max_schedule_entries) {
                try appendScheduleEntriesInvalid(storage, count);
                return;
            }
            for (schedule.entries, 0..) |entry, index| {
                if (findRole(block, entry.role_id) == null)
                    try appendUnknownRole(storage, count);
                for (schedule.entries[0..index]) |prior| {
                    if (std.mem.eql(u8, entry.local_date, prior.local_date))
                        try appendIssue(
                            storage,
                            count,
                            "program.schedule.date_duplicate",
                            "/definition/blocks/schedule",
                            "Only one role per date is supported.",
                        );
                }
            }
        },
        .frequency_targeted => |schedule| try validateFrequency(schedule.target, storage, count),
        .hybrid => |schedule| try validateFrequency(schedule.target, storage, count),
        .rotation => |schedule| if (schedule.frequency) |frequency| {
            try validateFrequency(frequency, storage, count);
        },
    }
}

fn validateFrequency(
    frequency: FrequencyTarget,
    storage: []Issue,
    count: *usize,
) error{OutputTooSmall}!void {
    if (frequency.sessions == 0 or frequency.days == 0)
        try appendIssue(
            storage,
            count,
            "program.frequency.invalid",
            "/definition/blocks/schedule/target",
            "Frequency target values must be positive.",
        );
}

fn validateOrdering(
    role: Role,
    item: Item,
    storage: []Issue,
    count: *usize,
) error{OutputTooSmall}!void {
    for (item.ordering.before_slot_ids) |target| {
        if (item.id.eql(target) or findItem(role, target) == null)
            try appendInvalidOrdering(storage, count);
        if (findItem(role, target)) |other| {
            if (containsId(other.ordering.before_slot_ids, item.id))
                try appendIssue(
                    storage,
                    count,
                    "program.ordering.cycle",
                    "/definition/blocks/roles/items/ordering",
                    "Direct cyclic ordering constraints are not allowed.",
                );
        }
    }
    for (item.ordering.after_slot_ids) |target| {
        if (item.id.eql(target) or findItem(role, target) == null)
            try appendInvalidOrdering(storage, count);
    }
}

fn appendInvalidOrdering(storage: []Issue, count: *usize) error{OutputTooSmall}!void {
    try appendIssue(
        storage,
        count,
        "program.ordering.reference_invalid",
        "/definition/blocks/roles/items/ordering",
        "Ordering references must identify a different item in the same role.",
    );
}

fn appendUnknownRole(storage: []Issue, count: *usize) error{OutputTooSmall}!void {
    try appendIssue(
        storage,
        count,
        "program.schedule.role_unknown",
        "/definition/blocks/schedule",
        "A schedule references an unknown role.",
    );
}

fn appendScheduleTooLong(storage: []Issue, count: *usize) error{OutputTooSmall}!void {
    try appendIssue(
        storage,
        count,
        "program.schedule.entries_exceeded",
        "/definition/blocks/schedule",
        "A schedule exceeds the entry limit.",
    );
}

fn appendScheduleEntriesInvalid(storage: []Issue, count: *usize) error{OutputTooSmall}!void {
    try appendIssue(
        storage,
        count,
        "program.schedule.entries_invalid",
        "/definition/blocks/schedule",
        "Dated and weekday schedules require a bounded non-empty entry list.",
    );
}

fn appendIssue(
    storage: []Issue,
    count: *usize,
    code: []const u8,
    path: []const u8,
    message: []const u8,
) error{OutputTooSmall}!void {
    if (count.* == storage.len) return error.OutputTooSmall;
    storage[count.*] = .{ .code = code, .path = path, .message = message };
    count.* += 1;
}

fn findItem(role: Role, id: primitives.Id) ?Item {
    for (role.items) |item| if (item.id.eql(id)) return item;
    return null;
}

pub fn findRole(block: Block, id: primitives.Id) ?Role {
    for (block.roles) |role| if (role.id.eql(id)) return role;
    return null;
}

pub fn findBlock(program: ProgramDefinition, id: primitives.Id) ?Block {
    for (program.blocks) |block| if (block.id.eql(id)) return block;
    return null;
}

pub fn findBlockIndex(program: ProgramDefinition, id: primitives.Id) ?usize {
    for (program.blocks, 0..) |block, index| {
        if (block.id.eql(id)) return index;
    }
    return null;
}

fn containsId(ids: []const primitives.Id, wanted: primitives.Id) bool {
    for (ids) |id| if (id.eql(wanted)) return true;
    return false;
}

test "definition validation requires resolved progression and valid ordering" {
    const slot_id = try primitives.Id.parse("slot:press");
    const missing_id = try primitives.Id.parse("slot:missing");
    const role_id = try primitives.Id.parse("role:upper");
    const block_id = try primitives.Id.parse("block:base");
    const exercise_id = try primitives.Id.parse("exercise:press");
    const role_ids = [_]primitives.Id{role_id};
    const before = [_]primitives.Id{missing_id};
    const items = [_]Item{.{
        .id = slot_id,
        .selection = .{ .fixed = exercise_id },
        .ordering = .{ .before_slot_ids = &before },
    }};
    const roles = [_]Role{.{ .id = role_id, .name = "Upper", .items = &items }};
    const blocks = [_]Block{.{
        .id = block_id,
        .name = "Base",
        .length = .manual,
        .schedule = .{ .rotation = .{ .role_ids = &role_ids } },
        .roles = &roles,
    }};
    const program: ProgramDefinition = .{
        .id = try primitives.Id.parse("program:upper"),
        .version = 1,
        .display_name = "Upper",
        .fingerprint = "definition-v1",
        .blocks = &blocks,
    };
    var issue_storage: [4]Issue = undefined;

    const issues = try validate(program, &issue_storage);

    try std.testing.expectEqual(@as(usize, 2), issues.len);
    try std.testing.expectEqualStrings("progression.assignment_missing", issues[0].code);
    try std.testing.expectEqualStrings("program.ordering.reference_invalid", issues[1].code);
}
