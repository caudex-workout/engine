//! Presentation-only program lifecycle screen.
//!
//! Actions cross the shared application boundary; schedule resolution and
//! advancement remain in the public program planner used by the line client.

const std = @import("std");
const actions = @import("actions.zig");

pub const State = struct {
    preset: []const u8,
    instance_id: []const u8,
    lifecycle: []const u8,
    revision: u64,
    block_name: []const u8,
    phase: []const u8,
    next_role: ?[]const u8,
    complete: bool,
    help_visible: bool = false,
};

pub const Key = enum { inspect, start, status, next, advance, pause, end, help };

pub fn actionFor(state: State, key: Key) ?actions.Action {
    return switch (key) {
        .inspect => .{ .program = .{ .inspect = state.preset } },
        .start => .{ .program = .{ .start = state.preset } },
        .status => .{ .program = .status },
        .next => if (state.complete) null else .{ .program = .next },
        .advance => if (state.complete or state.next_role == null) null else .{ .program = .advance },
        .pause => if (std.mem.eql(u8, state.lifecycle, "active")) .{ .program = .pause } else null,
        .end => if (std.mem.eql(u8, state.lifecycle, "ended")) null else .{ .program = .end },
        .help => .show_help,
    };
}

pub fn render(state: State, writer: *std.Io.Writer) !void {
    if (state.help_visible) return writer.writeAll("Program help\nn next  a accept advancement  p pause  e end  ? close help\n");
    try writer.print("Program: {s}\nInstance: {s}\nStatus: {s}  revision {d}\nBlock: {s} ({s})\n", .{ state.preset, state.instance_id, state.lifecycle, state.revision, state.block_name, state.phase });
    if (state.complete) return writer.writeAll("Next: program complete\n");
    try writer.print("Next: {s}\n", .{state.next_role orelse "not resolved"});
}

test "program screen exposes explicit lifecycle actions" {
    const state: State = .{ .preset = "rotation", .instance_id = "run-1", .lifecycle = "active", .revision = 2, .block_name = "Rotation", .phase = "base", .next_role = "lower", .complete = false };
    try std.testing.expect(actionFor(state, .advance).?.program == .advance);
    try std.testing.expect(actionFor(state, .pause).?.program == .pause);
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try render(state, &writer);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "Next: lower") != null);
    var completed = state;
    completed.complete = true;
    try std.testing.expect(actionFor(completed, .advance) == null);
}
