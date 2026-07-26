const std = @import("std");
const tracking = @import("caudex_tracking");

const scope: tracking.Scope = .{
    .host_scope_key = .{ .bytes = "local-profile" },
    .athlete_id = .{ .bytes = "athlete-1" },
};
const command: tracking.StartWorkoutCommand = .{
    .metadata = .{
        .command_id = .{ .bytes = "command-start-1" },
        .occurred_at = .{ .bytes = "2026-07-26T12:00:00Z" },
    },
    .scope = scope,
    .workout_id = .{ .bytes = "workout-1" },
    .started_at = .{ .bytes = "2026-07-26T12:00:00Z" },
};

test "valid start is deterministic and proposes revision one" {
    var issues: [1]tracking.Issue = undefined;
    const first = try tracking.startWorkout(.{}, command, &issues);
    const second = try tracking.startWorkout(.{}, command, &issues);

    try expectAcceptedWorkout(first, "workout-1", .applied);
    try expectAcceptedWorkout(second, "workout-1", .applied);
    try std.testing.expectEqual(
        first.accepted.workout.revision,
        second.accepted.workout.revision,
    );
    try std.testing.expectEqual(tracking.WorkoutStatus.active, first.accepted.workout.status);
    try std.testing.expectEqual(@as(usize, 0), first.accepted.workout.exercises.len);
}

test "identical receipt replays original result and payload reuse conflicts" {
    var issues: [1]tracking.Issue = undefined;
    const applied = (try tracking.startWorkout(.{}, command, &issues)).accepted;
    const receipt = tracking.StartReceipt{
        .command = command,
        .accepted = applied,
    };
    const snapshot: tracking.LifecycleSnapshot = .{
        .workouts = &.{applied.workout},
        .start_receipts = &.{receipt},
    };

    const replay = try tracking.startWorkout(snapshot, command, &issues);
    try expectAcceptedWorkout(replay, "workout-1", .replayed);
    try std.testing.expectEqual(applied.workout.revision, replay.accepted.workout.revision);

    var changed = command;
    changed.workout_id = .{ .bytes = "workout-2" };
    const conflict = try tracking.startWorkout(snapshot, changed, &issues);
    try expectRejectedCode(conflict, tracking.issue_codes.command_payload_conflict);
}

test "duplicate workout ID rejects without blocking another active ID" {
    var issues: [1]tracking.Issue = undefined;
    const existing = (try tracking.startWorkout(.{}, command, &issues)).accepted.workout;
    const snapshot: tracking.LifecycleSnapshot = .{ .workouts = &.{existing} };

    var duplicate = command;
    duplicate.metadata.command_id = .{ .bytes = "command-start-2" };
    const rejected = try tracking.startWorkout(snapshot, duplicate, &issues);
    try expectRejectedCode(rejected, tracking.issue_codes.workout_id_conflict);

    var second = duplicate;
    second.workout_id = .{ .bytes = "workout-2" };
    const accepted = try tracking.startWorkout(snapshot, second, &issues);
    try expectAcceptedWorkout(accepted, "workout-2", .applied);
}

test "invalid identifiers and timestamps are structured rejections" {
    var issues: [1]tracking.Issue = undefined;
    var invalid_id = command;
    invalid_id.workout_id = .{ .bytes = "" };
    try expectRejectedCode(
        try tracking.startWorkout(.{}, invalid_id, &issues),
        tracking.issue_codes.invalid_identifier,
    );

    var invalid_time = command;
    invalid_time.started_at = .{ .bytes = "not-a-time" };
    try expectRejectedCode(
        try tracking.startWorkout(.{}, invalid_time, &issues),
        tracking.issue_codes.invalid_timestamp,
    );
    try std.testing.expectError(
        error.IssueBufferTooSmall,
        tracking.startWorkout(.{}, invalid_time, &.{}),
    );
}

test "read finds exact scope and reports structured not found" {
    var issues: [1]tracking.Issue = undefined;
    const workout = (try tracking.startWorkout(.{}, command, &issues)).accepted.workout;
    const snapshot: tracking.LifecycleSnapshot = .{ .workouts = &.{workout} };
    const found = tracking.readWorkout(snapshot, .{
        .scope = scope,
        .workout_id = workout.id,
    });
    try std.testing.expect(found.found.id.eql(workout.id));

    const missing = tracking.readWorkout(snapshot, .{
        .scope = scope,
        .workout_id = .{ .bytes = "missing" },
    });
    try std.testing.expectEqualStrings(
        tracking.issue_codes.workout_not_found,
        missing.not_found.code,
    );
}

test "two active workouts are allowed and produce ambiguity" {
    var issues: [1]tracking.Issue = undefined;
    const first = (try tracking.startWorkout(.{}, command, &issues)).accepted.workout;
    var second_command = command;
    second_command.metadata.command_id = .{ .bytes = "command-start-2" };
    second_command.workout_id = .{ .bytes = "workout-2" };
    const second = (try tracking.startWorkout(
        .{ .workouts = &.{first} },
        second_command,
        &issues,
    )).accepted.workout;

    var output: [2]tracking.Workout = undefined;
    const selected = try tracking.selectActiveWorkouts(
        .{ .workouts = &.{ first, second } },
        .{ .scope = scope, .max_results = 2 },
        &output,
    );
    try std.testing.expectEqual(@as(usize, 2), selected.ambiguous.len);
    try std.testing.expect(selected.ambiguous[0].id.eql(first.id));
    try std.testing.expect(selected.ambiguous[1].id.eql(second.id));
}

fn expectAcceptedWorkout(
    result: tracking.CommandResult,
    id: []const u8,
    disposition: tracking.CommandDisposition,
) !void {
    switch (result) {
        .accepted => |accepted| {
            try std.testing.expectEqual(disposition, accepted.disposition);
            try std.testing.expectEqualStrings(id, accepted.workout.id.bytes);
        },
        .rejected => return error.UnexpectedRejection,
    }
}

fn expectRejectedCode(result: tracking.CommandResult, code: []const u8) !void {
    switch (result) {
        .accepted => return error.UnexpectedAcceptance,
        .rejected => |rejected| {
            try std.testing.expectEqual(@as(usize, 1), rejected.issues.len);
            try std.testing.expectEqualStrings(code, rejected.issues[0].code);
        },
    }
}
