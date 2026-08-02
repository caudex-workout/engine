const std = @import("std");
const persistence = @import("caudex_persistence");
const sqlite = @import("caudex_sqlite");
const tracking = @import("caudex_tracking");
const tui = @import("caudex_tui");
const terminal = tui.terminal;
const dashboard = tui.dashboard;
const workout_screen = tui.workout;
const session = tui.session;

const scope: tracking.Scope = .{ .host_scope_key = .{ .bytes = "tui-e2e" } };
const Fake = struct { calls: usize = 0 };
fn fakeStep(context: *anyopaque) !void {
    const value: *Fake = @ptrCast(@alignCast(context));
    value.calls += 1;
}
fn fakeLeave(context: *anyopaque) !void {
    const value: *Fake = @ptrCast(@alignCast(context));
    value.calls += 1;
}
fn fakeDriver(value: *Fake) terminal.Driver {
    return .{ .context = value, .enter_raw = fakeStep, .leave_raw = fakeLeave, .enter_screen = fakeStep, .leave_screen = fakeLeave, .register_resize = fakeStep, .unregister_resize = fakeLeave };
}
fn metadata(id: []const u8, at: []const u8) tracking.CommandMetadata {
    return .{ .command_id = .{ .bytes = id }, .occurred_at = .{ .bytes = at } };
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.InvalidArguments;
    const path = try init.arena.allocator().dupeZ(u8, args[1]);
    var fake_value = Fake{};
    var terminal_value = terminal.Terminal{ .driver = fakeDriver(&fake_value) };
    try terminal_value.init();
    defer terminal_value.restore();

    const database = try sqlite.open(path, .{});
    defer database.close();
    const allocator = init.arena.allocator();
    try database.replaceCatalog(allocator, .{ .host_scope_key = "tui-e2e", .as_of = "2026-07-28T09:00:00Z" }, &.{persistence.canonical.Exercise{ .id = "bench", .name = "Bench Press" }});
    const started = (try database.startWorkout(allocator, .{ .metadata = metadata("tui-start", "2026-07-28T09:00:00Z"), .scope = scope, .workout_id = .{ .bytes = "tui-workout" }, .started_at = .{ .bytes = "2026-07-28T09:00:00Z" } })).accepted.workout;
    _ = dashboard.choose(&.{.{ .id = started.id.bytes, .started_at = started.started_at.bytes }});
    const added = (try database.addExercise(allocator, .{ .metadata = metadata("tui-add", "2026-07-28T09:01:00Z"), .scope = scope, .workout_id = started.id, .expected_revision = started.revision, .membership_id = .{ .bytes = "tui-membership" }, .exercise_id = .{ .bytes = "bench" }, .anchor = .end })).accepted.workout;
    const set_added = (try database.addSet(allocator, .{ .metadata = metadata("tui-add-set", "2026-07-28T09:02:00Z"), .scope = scope, .workout_id = added.id, .expected_revision = added.revision, .membership_id = .{ .bytes = "tui-membership" }, .set_id = .{ .bytes = "tui-set" }, .kind = .{ .bytes = "working" }, .anchor = .end })).accepted.workout;
    _ = workout_screen.actionFor(.{ .exercises = &.{.{ .membership_id = "tui-membership", .exercise_id = "bench", .sets = &.{.{ .id = "tui-set", .status = "open" }} }} }, .log);
    const logged = (try database.completeSet(allocator, .{ .metadata = metadata("tui-log", "2026-07-28T09:03:00Z"), .scope = scope, .workout_id = set_added.id, .expected_revision = set_added.revision, .membership_id = .{ .bytes = "tui-membership" }, .set_id = .{ .bytes = "tui-set" }, .actual_metrics = &.{}, .completed_at = .{ .bytes = "2026-07-28T09:03:00Z" } })).accepted.workout;
    try std.testing.expect(session.update(.{ .short_workout = true }, .finish).action.? == .finish_workout);
    _ = try database.completeWorkout(allocator, .{ .metadata = metadata("tui-finish", "2026-07-28T09:04:00Z"), .scope = scope, .workout_id = logged.id, .expected_revision = logged.revision, .completed_at = .{ .bytes = "2026-07-28T09:04:00Z" } });
}
