const std = @import("std");
const actions = @import("actions.zig");

pub const Metric = struct { code: []const u8, decimal: []const u8, unit: []const u8 };
pub const Set = struct { id: []const u8, status: []const u8, targets: []const Metric = &.{}, actuals: []const Metric = &.{} };
pub const Exercise = struct { membership_id: []const u8, exercise_id: []const u8, sets: []const Set = &.{} };
pub const Conflict = union(enum) { none, refresh_required, explanation: []const u8 };
pub const Screen = struct { exercises: []const Exercise, selected_exercise: usize = 0, selected_set: usize = 0, conflict: Conflict = .none };

pub fn actionFor(screen: Screen, operation: actions.SetAction) ?actions.Action {
    if (screen.selected_exercise >= screen.exercises.len) return null;
    const exercise = screen.exercises[screen.selected_exercise];
    if (screen.selected_set >= exercise.sets.len) return null;
    return .{ .change_set = .{ .set_id = exercise.sets[screen.selected_set].id, .action = operation } };
}

pub fn reorderAction(screen: Screen, direction: actions.Direction) ?actions.Action {
    if (screen.selected_exercise >= screen.exercises.len) return null;
    return .{ .reorder_exercise = .{ .membership_id = screen.exercises[screen.selected_exercise].membership_id, .direction = direction } };
}

pub fn render(screen: Screen, writer: *std.Io.Writer) !void {
    switch (screen.conflict) {
        .refresh_required => return writer.writeAll("Workout changed. Press r to refresh; no change was overwritten.\n"),
        .explanation => |message| return writer.print("Conflict: {s}\n", .{message}),
        .none => {},
    }
    for (screen.exercises, 0..) |exercise, exercise_index| {
        try writer.print("{s} {s}\n", .{ if (exercise_index == screen.selected_exercise) ">" else " ", exercise.exercise_id });
        for (exercise.sets) |set| {
            try writer.print("  Set {s} [{s}]\n    target: ", .{ set.id, set.status });
            try renderMetrics(set.targets, writer);
            try writer.writeAll("\n    actual: ");
            try renderMetrics(set.actuals, writer);
            try writer.writeByte('\n');
        }
    }
}

fn renderMetrics(metrics: []const Metric, writer: *std.Io.Writer) !void {
    if (metrics.len == 0) return writer.writeAll("-");
    for (metrics, 0..) |metric, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s}={s}{s}", .{ metric.code, metric.decimal, metric.unit });
    }
}

test "exact target and actual metrics render without floating point" {
    const targets = [_]Metric{.{ .code = "load", .decimal = "102.50", .unit = "kg" }};
    const actuals = [_]Metric{ .{ .code = "load", .decimal = "102.50", .unit = "kg" }, .{ .code = "repetitions", .decimal = "8", .unit = "count" } };
    const sets = [_]Set{.{ .id = "set-1", .status = "completed", .targets = &targets, .actuals = &actuals }};
    const exercises = [_]Exercise{.{ .membership_id = "member-1", .exercise_id = "bench", .sets = &sets }};
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try render(.{ .exercises = &exercises }, &writer);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "target: load=102.50kg") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "actual: load=102.50kg, repetitions=8count") != null);
    try std.testing.expect(actionFor(.{ .exercises = &exercises }, .reopen).? == .change_set);
}

test "conflict never renders an overwritten value" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try render(.{ .exercises = &.{}, .conflict = .refresh_required }, &writer);
    try std.testing.expectEqualStrings("Workout changed. Press r to refresh; no change was overwritten.\n", writer.buffered());
}
