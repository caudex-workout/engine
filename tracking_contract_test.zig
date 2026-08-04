const std = @import("std");
const tracking = @import("caudex_tracking");

const scope: tracking.Scope = .{
    .host_scope_key = .{ .bytes = "local-profile" },
    .athlete_id = .{ .bytes = "athlete-1" },
};
const started_at: tracking.Timestamp = .{ .bytes = "2026-07-26T12:00:00Z" };
const start_command: tracking.StartWorkoutCommand = .{
    .metadata = .{
        .command_id = .{ .bytes = "command-start-1" },
        .occurred_at = started_at,
    },
    .scope = scope,
    .workout_id = .{ .bytes = "workout-1" },
    .started_at = started_at,
};
const started_workout: tracking.Workout = .{
    .id = start_command.workout_id,
    .scope = start_command.scope,
    .revision = 1,
    .status = .active,
    .started_at = start_command.started_at,
};
const start_result: tracking.CommandResult = .{ .accepted = .{
    .command_id = start_command.metadata.command_id,
    .disposition = .applied,
    .workout = started_workout,
} };
const next_host_read: tracking.ReadWorkoutQuery = .{
    .scope = scope,
    .workout_id = started_workout.id,
};
const read_result: tracking.ReadWorkoutResult = .{
    .found = started_workout,
};

test "typed fixtures express start and read across host calls" {
    try std.testing.expectEqual(
        tracking.CommandDisposition.applied,
        start_result.accepted.disposition,
    );
    try std.testing.expect(next_host_read.workout_id.eql(read_result.found.id));
    try std.testing.expect(
        next_host_read.scope.host_scope_key.eql(
            read_result.found.scope.host_scope_key,
        ),
    );
    try std.testing.expectEqual(@as(u64, 1), read_result.found.revision);
}

test "contract represents retries short completion and ambiguity" {
    var replayed = start_result.accepted;
    replayed.disposition = .replayed;
    try std.testing.expect(replayed.command_id.eql(start_command.metadata.command_id));

    const complete = tracking.CompleteWorkoutCommand{
        .metadata = .{
            .command_id = .{ .bytes = "command-complete-1" },
            .occurred_at = started_at,
        },
        .scope = scope,
        .workout_id = started_workout.id,
        .expected_revision = started_workout.revision,
        .completed_at = started_at,
    };
    try std.testing.expect(complete.workout_id.eql(started_workout.id));
    try std.testing.expectEqual(@as(usize, 0), started_workout.exercises.len);

    const ambiguous: tracking.ActiveWorkoutSelection = .{
        .ambiguous = &.{ started_workout, started_workout },
    };
    try std.testing.expectEqual(@as(usize, 2), ambiguous.ambiguous.len);
}

test "tracking contract exposes no execution or persistence API" {
    inline for (.{
        "open",
        "save",
        "execute",
        "database",
        "allocator",
        "clock",
    }) |name| {
        try std.testing.expect(!@hasDecl(tracking, name));
    }
    try std.testing.expectEqual(@as(u32, 6), tracking.contract_version);
}

test "atomic batch publishes only the final sequential snapshot" {
    const commands = [_]tracking.Command{
        .{ .start_workout = start_command },
        .{ .add_exercise = .{
            .metadata = .{ .command_id = .{ .bytes = "command-add-exercise" }, .occurred_at = started_at },
            .scope = scope,
            .workout_id = start_command.workout_id,
            .expected_revision = 1,
            .membership_id = .{ .bytes = "membership-1" },
            .exercise_id = .{ .bytes = "squat" },
            .anchor = .end,
        } },
        .{ .add_set = .{
            .metadata = .{ .command_id = .{ .bytes = "command-add-set" }, .occurred_at = started_at },
            .scope = scope,
            .workout_id = start_command.workout_id,
            .expected_revision = 2,
            .membership_id = .{ .bytes = "membership-1" },
            .set_id = .{ .bytes = "set-1" },
            .kind = .{ .bytes = "working" },
            .anchor = .end,
        } },
    };
    var workouts: [3]tracking.Workout = undefined;
    var receipts: [3]tracking.StartReceipt = undefined;
    var exercises: [8]tracking.ExerciseMembership = undefined;
    var sets: [8]tracking.TrackedSet = undefined;
    var issues: [commands.len]tracking.Issue = undefined;
    const result = try tracking.applyAtomicBatch(
        .{ .exercise_catalog = &.{.{ .exercise_id = .{ .bytes = "squat" }, .availability = .active }} },
        &commands,
        .{ .workouts = &workouts, .start_receipts = &receipts, .exercises = &exercises, .sets = &sets, .issues = &issues },
    );
    try std.testing.expectEqual(@as(u16, 3), result.accepted.applied_commands);
    try std.testing.expectEqual(@as(u64, 3), result.accepted.snapshot.workouts[0].revision);
    try std.testing.expectEqualStrings("set-1", result.accepted.snapshot.workouts[0].exercises[0].sets[0].id.bytes);
}

test "atomic batch rejection does not expose partial workspace state" {
    const commands = [_]tracking.Command{
        .{ .start_workout = start_command },
        .{ .add_exercise = .{
            .metadata = .{ .command_id = .{ .bytes = "command-invalid-revision" }, .occurred_at = started_at },
            .scope = scope,
            .workout_id = start_command.workout_id,
            .expected_revision = 99,
            .membership_id = .{ .bytes = "membership-1" },
            .exercise_id = .{ .bytes = "squat" },
            .anchor = .end,
        } },
    };
    var workouts: [2]tracking.Workout = undefined;
    var receipts: [2]tracking.StartReceipt = undefined;
    var exercises: [2]tracking.ExerciseMembership = undefined;
    var sets: [2]tracking.TrackedSet = undefined;
    var issues: [commands.len]tracking.Issue = undefined;
    const original: tracking.LifecycleSnapshot = .{
        .exercise_catalog = &.{.{ .exercise_id = .{ .bytes = "squat" }, .availability = .active }},
    };
    const result = try tracking.applyAtomicBatch(original, &commands, .{
        .workouts = &workouts,
        .start_receipts = &receipts,
        .exercises = &exercises,
        .sets = &sets,
        .issues = &issues,
    });
    try std.testing.expectEqualStrings(tracking.issue_codes.revision_conflict, result.rejected.issues[0].code);
    try std.testing.expectEqual(@as(usize, 0), original.workouts.len);
}
