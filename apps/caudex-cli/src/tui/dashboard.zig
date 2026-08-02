const std = @import("std");

pub const Workout = struct { id: []const u8, started_at: []const u8 };
pub const State = union(enum) { empty, selected: Workout, ambiguous: []const Workout };
pub const Performance = struct { workout_id: []const u8, completed_at: []const u8 };
pub const Exercise = struct { id: []const u8, name: []const u8, last: ?Performance = null };
pub const Picker = union(enum) { empty, selected: Exercise, ambiguous: []const Exercise };
pub const Dashboard = struct { workouts: State, picker: Picker = .empty, selected: usize = 0, help_visible: bool = false };
pub const Key = enum { up, down, help };

pub fn choose(workouts: []const Workout) State {
    return switch (workouts.len) {
        0 => .empty,
        1 => .{ .selected = workouts[0] },
        else => .{ .ambiguous = workouts },
    };
}

pub fn chooseExercise(exercises: []const Exercise) Picker {
    return switch (exercises.len) {
        0 => .empty,
        1 => .{ .selected = exercises[0] },
        else => .{ .ambiguous = exercises },
    };
}

pub fn update(dashboard: Dashboard, key: Key) Dashboard {
    var next = dashboard;
    const count = switch (next.picker) {
        .ambiguous => |values| values.len,
        .selected => 1,
        .empty => 0,
    };
    switch (key) {
        .up => if (next.selected > 0) {
            next.selected -= 1;
        },
        .down => if (next.selected + 1 < count) {
            next.selected += 1;
        },
        .help => next.help_visible = !next.help_visible,
    }
    return next;
}

pub fn render(state: State, writer: *std.Io.Writer) !void {
    switch (state) {
        .empty => try writer.writeAll("No active workout. Press s to start one.\n"),
        .selected => |workout| try writer.print("Active workout: {s}\nStarted: {s}\n", .{ workout.id, workout.started_at }),
        .ambiguous => |workouts| {
            try writer.writeAll("Choose an active workout:\n");
            for (workouts) |workout| try writer.print("  {s}\n", .{workout.id});
        },
    }
}

pub fn renderPicker(dashboard: Dashboard, writer: *std.Io.Writer) !void {
    if (dashboard.help_visible) return writer.writeAll("Exercise picker help\n↑/↓ select  enter choose  ? close help\n");
    switch (dashboard.picker) {
        .empty => try writer.writeAll("No exercises matched.\n"),
        .selected => |exercise| try renderExercise(exercise, true, writer),
        .ambiguous => |exercises| for (exercises, 0..) |exercise, index| try renderExercise(exercise, index == dashboard.selected, writer),
    }
}

fn renderExercise(exercise: Exercise, selected: bool, writer: *std.Io.Writer) !void {
    try writer.print("{s} {s} ({s})\n", .{ if (selected) ">" else " ", exercise.name, exercise.id });
    if (selected) if (exercise.last) |last| try writer.print("  Last: {s} at {s}\n", .{ last.workout_id, last.completed_at });
}

test "dashboard never guesses among active workouts" {
    const values = [_]Workout{ .{ .id = "a", .started_at = "one" }, .{ .id = "b", .started_at = "two" } };
    try std.testing.expect(choose(&.{}) == .empty);
    try std.testing.expectEqualStrings("a", choose(values[0..1]).selected.id);
    try std.testing.expectEqual(@as(usize, 2), choose(&values).ambiguous.len);
}

test "exercise picker shows last performance and keyboard help" {
    const exercises = [_]Exercise{
        .{ .id = "bench", .name = "Bench Press", .last = .{ .workout_id = "w1", .completed_at = "2026-07-27T09:03:00Z" } },
        .{ .id = "bench-db", .name = "Dumbbell Bench" },
    };
    var dashboard = Dashboard{ .workouts = .empty, .picker = chooseExercise(&exercises) };
    dashboard = update(dashboard, .down);
    try std.testing.expectEqual(@as(usize, 1), dashboard.selected);
    dashboard = update(dashboard, .up);
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try renderPicker(dashboard, &writer);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "Last: w1 at 2026-07-27T09:03:00Z") != null);
    dashboard = update(dashboard, .help);
    writer = std.Io.Writer.fixed(&buffer);
    try renderPicker(dashboard, &writer);
    try std.testing.expectEqualStrings("Exercise picker help\n↑/↓ select  enter choose  ? close help\n", writer.buffered());
}
