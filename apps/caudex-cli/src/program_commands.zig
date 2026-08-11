//! Stateless reference-client flows for the public deterministic program planner.

const std = @import("std");
const caudex = @import("caudex");
const output = @import("output.zig");

const planning = caudex.program_planning;

const Preset = struct { name: []const u8, summary: []const u8 };
const presets = [_]Preset{
    .{ .name = "rotation", .summary = "Asynchronous upper/lower rotation" },
    .{ .name = "weekdays", .summary = "Fixed-weekday upper/lower" },
    .{ .name = "ppl", .summary = "Push/pull/legs rotation" },
    .{ .name = "block", .summary = "Structured hypertrophy and deload block" },
};

const Options = struct {
    preset: []const u8,
    instance_id: []const u8 = "program-instance",
    revision: u64 = 0,
    block_index: u16 = 0,
    microcycle_index: u32 = 0,
    session_cursor: u16 = 0,
    completed_occurrences: u64 = 0,
    block_completed_occurrences: u32 = 0,
    complete: bool = false,
    local_date: ?[]const u8 = null,
    weekday: ?planning.Weekday = null,
    completion: planning.Completion = .completed,
};

pub fn run(
    allocator: std.mem.Allocator,
    verb: []const u8,
    args: []const []const u8,
    athlete_id: []const u8,
    settings: output.Settings,
    writer: *std.Io.Writer,
) !void {
    if (std.mem.eql(u8, verb, "list")) {
        if (args.len != 0) return error.InvalidArguments;
        return writeList(settings, writer);
    }
    const options = try parseOptions(args);
    const definition = presetByName(options.preset) orelse return error.InvalidArguments;
    if (std.mem.eql(u8, verb, "inspect")) return writeDefinition(allocator, settings, writer, definition);

    const reference = planning.definitionRef(definition);
    var instance: planning.ProgramInstance = .{
        .id = options.instance_id,
        .athlete_id = athlete_id,
        .definition = reference,
        .lifecycle = if (std.mem.eql(u8, verb, "start")) .created else .active,
    };
    const state: planning.ProgramState = .{
        .instance_id = instance.id,
        .definition = reference,
        .revision = options.revision,
        .block_index = options.block_index,
        .microcycle_index = options.microcycle_index,
        .session_cursor = options.session_cursor,
        .completed_occurrences = options.completed_occurrences,
        .block_completed_occurrences = options.block_completed_occurrences,
        .complete = options.complete,
    };
    if (std.mem.eql(u8, verb, "start") or std.mem.eql(u8, verb, "pause") or std.mem.eql(u8, verb, "end")) {
        const requested: planning.Lifecycle = if (std.mem.eql(u8, verb, "pause")) .paused else if (std.mem.eql(u8, verb, "end")) .ended else .active;
        const lifecycle_proposal = planning.proposeLifecycle(instance, requested) orelse return error.InvalidArguments;
        instance = planning.acceptLifecycle(instance, lifecycle_proposal) orelse return error.InvalidArguments;
    }
    if (std.mem.eql(u8, verb, "start") or std.mem.eql(u8, verb, "status") or
        std.mem.eql(u8, verb, "pause") or std.mem.eql(u8, verb, "end"))
    {
        return writeState(settings, writer, verb, definition, instance, if (std.mem.eql(u8, verb, "start")) planning.initialState(instance) else state);
    }
    if (!std.mem.eql(u8, verb, "next") and !std.mem.eql(u8, verb, "advance")) return error.InvalidArguments;
    if (state.block_index >= definition.blocks.len) return error.InvalidArguments;
    switch (definition.blocks[state.block_index].schedule) {
        .fixed_weekdays, .explicit_dates => if (options.local_date == null) return error.InvalidArguments,
        else => {},
    }

    var occurrence_storage: [256]u8 = undefined;
    const date: ?planning.LocalDate = if (options.local_date) |iso_date| .{
        .iso_date = iso_date,
        .weekday = options.weekday orelse return error.InvalidArguments,
    } else null;
    const planned = try planning.resolvePlannedSession(&occurrence_storage, definition, instance, state, date);
    if (std.mem.eql(u8, verb, "next")) return writeIntent(settings, writer, planned, state.revision);
    const proposal = try planning.proposeAdvancement(definition, state, planned, options.completion);
    return writeProposal(settings, writer, instance, proposal);
}

fn parseOptions(args: []const []const u8) !Options {
    if (args.len == 0 or std.mem.startsWith(u8, args[0], "--")) return error.InvalidArguments;
    var result = Options{ .preset = args[0] };
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const name = args[index];
        index += 1;
        if (index >= args.len or args[index].len == 0) return error.InvalidArguments;
        const value = args[index];
        if (std.mem.eql(u8, name, "--instance")) result.instance_id = value else if (std.mem.eql(u8, name, "--revision")) result.revision = std.fmt.parseInt(u64, value, 10) catch return error.InvalidArguments else if (std.mem.eql(u8, name, "--block")) result.block_index = std.fmt.parseInt(u16, value, 10) catch return error.InvalidArguments else if (std.mem.eql(u8, name, "--microcycle")) result.microcycle_index = std.fmt.parseInt(u32, value, 10) catch return error.InvalidArguments else if (std.mem.eql(u8, name, "--cursor")) result.session_cursor = std.fmt.parseInt(u16, value, 10) catch return error.InvalidArguments else if (std.mem.eql(u8, name, "--completed")) result.completed_occurrences = std.fmt.parseInt(u64, value, 10) catch return error.InvalidArguments else if (std.mem.eql(u8, name, "--block-completed")) result.block_completed_occurrences = std.fmt.parseInt(u32, value, 10) catch return error.InvalidArguments else if (std.mem.eql(u8, name, "--complete")) result.complete = if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else return error.InvalidArguments else if (std.mem.eql(u8, name, "--date")) result.local_date = value else if (std.mem.eql(u8, name, "--weekday")) result.weekday = parseWeekday(value) orelse return error.InvalidArguments else if (std.mem.eql(u8, name, "--completion")) result.completion = parseCompletion(value) orelse return error.InvalidArguments else return error.InvalidArguments;
    }
    if ((result.local_date == null) != (result.weekday == null)) return error.InvalidArguments;
    return result;
}

fn presetByName(name: []const u8) ?planning.ProgramDefinition {
    if (std.mem.eql(u8, name, "rotation")) return planning.presets.asynchronousUpperLower("cli:rotation:v1");
    if (std.mem.eql(u8, name, "weekdays")) return planning.presets.fixedWeekdayUpperLower("cli:weekdays:v1");
    if (std.mem.eql(u8, name, "ppl")) return planning.presets.pplRotation("cli:ppl:v1");
    if (std.mem.eql(u8, name, "block")) return planning.presets.structuredHypertrophyBlock("cli:block:v1");
    return null;
}

fn parseWeekday(value: []const u8) ?planning.Weekday {
    inline for (std.meta.fields(planning.Weekday)) |field| if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    return null;
}

fn parseCompletion(value: []const u8) ?planning.Completion {
    inline for (std.meta.fields(planning.Completion)) |field| if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    return null;
}

fn writeList(settings: output.Settings, writer: *std.Io.Writer) !void {
    if (settings.quiet) return;
    if (settings.format == .json) {
        try std.json.Stringify.value(.{ .schemaVersion = 1, .kind = "caudex.program.list", .data = .{ .presets = presets } }, .{}, writer);
        return writer.writeByte('\n');
    }
    try writer.writeAll("PRESET  DESCRIPTION\n");
    for (presets) |item| try writer.print("{s}  {s}\n", .{ item.name, item.summary });
}

const BlockInfo = struct { id: []const u8, name: []const u8, phase: []const u8, roleCount: usize };
fn writeDefinition(allocator: std.mem.Allocator, settings: output.Settings, writer: *std.Io.Writer, definition: planning.ProgramDefinition) !void {
    if (settings.quiet) return;
    const blocks = try allocator.alloc(BlockInfo, definition.blocks.len);
    for (definition.blocks, 0..) |block, index| blocks[index] = .{ .id = block.id, .name = block.name, .phase = @tagName(block.phase), .roleCount = block.roles.len };
    if (settings.format == .json) {
        try std.json.Stringify.value(.{ .schemaVersion = 1, .kind = "caudex.program.inspect", .data = .{ .id = definition.id, .version = definition.version, .displayName = definition.display_name, .fingerprint = definition.configuration_fingerprint, .blocks = blocks } }, .{}, writer);
        return writer.writeByte('\n');
    }
    try writer.print("Program: {s}\nID: {s}\nVersion: {d}\n", .{ definition.display_name, definition.id, definition.version });
    for (blocks) |block| try writer.print("  {s}  phase={s}  roles={d}\n", .{ block.id, block.phase, block.roleCount });
}

fn writeState(settings: output.Settings, writer: *std.Io.Writer, verb: []const u8, definition: planning.ProgramDefinition, instance: planning.ProgramInstance, state: planning.ProgramState) !void {
    if (settings.quiet) return;
    if (settings.format == .json) {
        try std.json.Stringify.value(.{ .schemaVersion = 1, .kind = if (std.mem.eql(u8, verb, "start")) "caudex.program.started" else if (std.mem.eql(u8, verb, "pause")) "caudex.program.paused" else if (std.mem.eql(u8, verb, "end")) "caudex.program.ended" else "caudex.program.status", .data = .{ .programId = definition.id, .instanceId = instance.id, .athleteId = instance.athlete_id, .lifecycle = @tagName(instance.lifecycle), .revision = state.revision, .blockIndex = state.block_index, .microcycleIndex = state.microcycle_index, .sessionCursor = state.session_cursor, .completedOccurrences = state.completed_occurrences, .blockCompletedOccurrences = state.block_completed_occurrences, .complete = state.complete } }, .{}, writer);
        return writer.writeByte('\n');
    }
    try writer.print("Program: {s}\nInstance: {s}\nLifecycle: {s}\nRevision: {d}\nPosition: block {d}, microcycle {d}, session {d}\nCompleted occurrences: {d} total, {d} in block\nComplete: {s}\n", .{ definition.display_name, instance.id, @tagName(instance.lifecycle), state.revision, state.block_index, state.microcycle_index, state.session_cursor, state.completed_occurrences, state.block_completed_occurrences, if (state.complete) "yes" else "no" });
}

fn writeIntent(settings: output.Settings, writer: *std.Io.Writer, planned: planning.PlannedSessionIntent, revision: u64) !void {
    if (settings.quiet) return;
    if (settings.format == .json) {
        try std.json.Stringify.value(.{ .schemaVersion = 1, .kind = "caudex.program.next", .data = .{ .instanceId = planned.instance_id, .revision = revision, .blockId = planned.block_id, .phase = @tagName(planned.block_phase), .roleId = planned.role.id, .roleName = planned.role.name, .occurrenceId = planned.occurrence.id, .scheduledDate = planned.occurrence.scheduled_date, .status = @tagName(planned.occurrence.status), .schedulingProvenance = @tagName(planned.scheduling_provenance) } }, .{ .emit_null_optional_fields = false }, writer);
        return writer.writeByte('\n');
    }
    try writer.print("Next session: {s}\nRole: {s}\nBlock: {s} ({s})\nOccurrence: {s}\nState revision: {d}\n", .{ planned.role.name, planned.role.id, planned.block_id, @tagName(planned.block_phase), planned.occurrence.id, revision });
}

fn writeProposal(settings: output.Settings, writer: *std.Io.Writer, instance: planning.ProgramInstance, proposal: planning.ProgramStateProposal) !void {
    if (settings.quiet) return;
    switch (proposal.outcome) {
        .advance => |next| {
            if (settings.format == .json) {
                try std.json.Stringify.value(.{ .schemaVersion = 1, .kind = "caudex.program.advancement_proposed", .data = .{ .instanceId = instance.id, .expectedRevision = proposal.expected_revision, .occurrenceId = proposal.occurrence_id, .explanationCode = proposal.explanation_code, .nextState = .{ .revision = next.revision, .blockIndex = next.block_index, .microcycleIndex = next.microcycle_index, .sessionCursor = next.session_cursor, .completedOccurrences = next.completed_occurrences, .blockCompletedOccurrences = next.block_completed_occurrences, .complete = next.complete } } }, .{}, writer);
                return writer.writeByte('\n');
            }
            try writer.print("Advancement proposed (not persisted)\nOccurrence: {s}\nExpected revision: {d}\nNext revision: {d}\nNext position: block {d}, microcycle {d}, session {d}\nReason: {s}\n", .{ proposal.occurrence_id, proposal.expected_revision, next.revision, next.block_index, next.microcycle_index, next.session_cursor, proposal.explanation_code });
        },
        .require_host_policy => try writer.print("No automatic advancement: host policy required ({s}).\n", .{proposal.explanation_code}),
        .no_change => try writer.print("No advancement proposed ({s}).\n", .{proposal.explanation_code}),
    }
}

test "program command options keep schedule facts explicit" {
    const parsed = try parseOptions(&.{ "weekdays", "--instance", "run-1", "--date", "2026-08-10", "--weekday", "monday", "--revision", "2" });
    try std.testing.expectEqualStrings("run-1", parsed.instance_id);
    try std.testing.expectEqual(@as(u64, 2), parsed.revision);
    try std.testing.expectEqual(planning.Weekday.monday, parsed.weekday.?);
    try std.testing.expectError(error.InvalidArguments, parseOptions(&.{ "weekdays", "--date", "2026-08-10" }));
}

test "program commands resolve and propose through public planner" {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try run(std.testing.allocator, "next", &.{ "rotation", "--instance", "run-1" }, "athlete-1", .{ .format = .json }, &writer);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "\"roleId\":\"upper-a\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "\"rotation_next\"") != null);

    writer = std.Io.Writer.fixed(&buffer);
    try run(std.testing.allocator, "advance", &.{ "rotation", "--instance", "run-1" }, "athlete-1", .{ .format = .json }, &writer);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "\"revision\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "\"sessionCursor\":1") != null);

    writer = std.Io.Writer.fixed(&buffer);
    try run(std.testing.allocator, "next", &.{ "weekdays", "--date", "2026-08-10", "--weekday", "monday" }, "athlete-1", .{ .format = .json }, &writer);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "\"weekday_match\"") != null);
}
