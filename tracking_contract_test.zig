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
