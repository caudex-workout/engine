const std = @import("std");
const tracking = @import("caudex_tracking");

const scope: tracking.Scope = .{ .host_scope_key = .{ .bytes = "model-scope" } };

const Reference = struct {
    applied_workouts: usize = 0,
    replayed_commands: usize = 0,

    fn apply(self: *Reference, replay: bool) void {
        if (replay) self.replayed_commands += 1 else self.applied_workouts += 1;
    }
};

fn startCommand(index: u8) tracking.StartWorkoutCommand {
    return .{
        .metadata = .{
            .command_id = .{ .bytes = if (index == 0) "model-start-0" else "model-start-1" },
            .occurred_at = .{ .bytes = "2026-08-08T12:00:00Z" },
        },
        .scope = scope,
        .workout_id = .{ .bytes = if (index == 0) "model-workout-0" else "model-workout-1" },
        .started_at = .{ .bytes = "2026-08-08T12:00:00Z" },
    };
}

test "bounded reference model agrees with reducer for replay and revisions" {
    var reference = Reference{};
    var workouts: [2]tracking.Workout = undefined;
    var receipts: [2]tracking.StartReceipt = undefined;
    var count: usize = 0;
    var issues: [2]tracking.Issue = undefined;

    const first = startCommand(0);
    const applied = try tracking.startWorkout(.{}, first, &issues);
    try std.testing.expectEqual(tracking.CommandDisposition.applied, applied.accepted.disposition);
    reference.apply(false);
    workouts[count] = applied.accepted.workout;
    receipts[count] = .{ .command = first, .accepted = applied.accepted };
    count += 1;
    try std.testing.expectEqual(reference.applied_workouts, count);
    try std.testing.expectEqual(@as(u64, 1), workouts[0].revision);

    const replayed = try tracking.startWorkout(.{ .workouts = workouts[0..count], .start_receipts = receipts[0..count] }, first, &issues);
    try std.testing.expectEqual(tracking.CommandDisposition.replayed, replayed.accepted.disposition);
    reference.apply(true);
    try std.testing.expectEqual(@as(usize, 1), reference.applied_workouts);
    try std.testing.expectEqual(@as(usize, 1), reference.replayed_commands);
    try std.testing.expectEqual(@as(u64, 1), replayed.accepted.workout.revision);

    const second = startCommand(1);
    const secondResult = try tracking.startWorkout(.{ .workouts = workouts[0..count] }, second, &issues);
    try std.testing.expectEqual(tracking.CommandDisposition.applied, secondResult.accepted.disposition);
    reference.apply(false);
    try std.testing.expectEqual(@as(usize, 2), reference.applied_workouts);
    try std.testing.expectEqual(@as(u64, 1), secondResult.accepted.workout.revision);
}
