const std = @import("std");
const protocol = @import("caudex_tracking_protocol");
const tracking = @import("caudex_tracking");

test "tracking fixture decodes and re-encodes deterministically" {
    const fixture = @embedFile("fixtures/tracking/start-workout-v1.json");
    const parsed = try protocol.decodeCommandRequest(std.testing.allocator, fixture, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.schemaVersion);
    try std.testing.expectEqualStrings("workout-1", parsed.value.command.startWorkout.workoutId);
    var first_storage: [4096]u8 = undefined;
    var second_storage: [4096]u8 = undefined;
    const first = try protocol.encode(parsed.value, &first_storage);
    const second = try protocol.encode(parsed.value, &second_storage);
    try std.testing.expectEqualStrings(first, second);
}

test "versions batches and transport failures are distinct" {
    const unsupported =
        \\{"schemaVersion":2,"snapshot":{"workouts":[]},"command":{"startWorkout":{"metadata":{"commandId":"c","occurredAt":"2026-08-04T12:00:00Z"},"scope":{"hostScopeKey":"s"},"workoutId":"w","startedAt":"2026-08-04T12:00:00Z"}}}
    ;
    try std.testing.expectError(error.UnsupportedVersion, protocol.decodeCommandRequest(std.testing.allocator, unsupported, .{}));
    try std.testing.expectError(error.MalformedJson, protocol.decodeCommandRequest(std.testing.allocator, "{", .{}));
    const empty_batch =
        \\{"schemaVersion":1,"snapshot":{"workouts":[]},"commands":[]}
    ;
    try std.testing.expectError(error.EmptyBatch, protocol.decodeAtomicBatchRequest(std.testing.allocator, empty_batch, .{}));
}

test "start command conversion validates and preserves typed values" {
    const parsed = try protocol.decodeCommandRequest(
        std.testing.allocator,
        @embedFile("fixtures/tracking/start-workout-v1.json"),
        .{},
    );
    defer parsed.deinit();
    const typed = try protocol.startWorkoutToDomain(parsed.value.command.startWorkout);
    try std.testing.expectEqualStrings("command-start-1", typed.metadata.command_id.bytes);
    try std.testing.expectEqualStrings("local-profile", typed.scope.host_scope_key.bytes);
    const wire = protocol.startWorkoutFromDomain(typed);
    try std.testing.expectEqualStrings("workout-1", wire.workoutId);

    var invalid = wire;
    invalid.workoutId = "";
    try std.testing.expectError(tracking.Id.ParseError.Empty, protocol.startWorkoutToDomain(invalid));
}

test "batch and snapshot limits fail before domain execution" {
    const batch =
        \\{"schemaVersion":1,"snapshot":{"workouts":[]},"commands":[{"startWorkout":{"metadata":{"commandId":"c","occurredAt":"2026-08-04T12:00:00Z"},"scope":{"hostScopeKey":"s"},"workoutId":"w","startedAt":"2026-08-04T12:00:00Z"}}]}
    ;
    try std.testing.expectError(
        error.BatchLimitExceeded,
        protocol.decodeAtomicBatchRequest(std.testing.allocator, batch, .{ .max_commands = 0 }),
    );
}

test "command conversion preserves exact target metrics and explicit anchors" {
    const command: protocol.Command = .{ .addSet = .{
        .metadata = .{ .commandId = "add-set-1", .occurredAt = "2026-08-04T12:01:00Z" },
        .scope = .{ .hostScopeKey = "scope-1" },
        .workoutId = "workout-1",
        .expectedRevision = 2,
        .membershipId = "membership-1",
        .setId = "set-1",
        .kind = "working",
        .targetMetrics = &.{.{
            .code = "load",
            .value = .{ .amount = "185.00", .unit = "lb" },
        }},
        .anchor = .end,
    } };
    var metrics: [protocol.max_metrics_per_set]tracking.Metric = undefined;
    const typed = try protocol.commandToDomain(command, &metrics);
    try std.testing.expectEqual(@as(u64, 2), typed.add_set.expected_revision);
    try std.testing.expectEqual(@as(i64, 18500), typed.add_set.target_metrics[0].value.value.mantissa);
    try std.testing.expectEqual(@as(u8, 2), typed.add_set.target_metrics[0].value.value.scale);
    try std.testing.expectEqual(tracking.SetAnchor.end, typed.add_set.anchor);
}

test "canonical snapshots preserve exact metrics and replay receipts" {
    const workout: protocol.TrackedWorkout = .{
        .id = "workout-1",
        .scope = .{ .hostScopeKey = "scope-1" },
        .revision = 3,
        .status = .active,
        .startedAt = "2026-08-04T12:00:00Z",
        .exercises = &.{.{
            .id = "membership-1",
            .exerciseId = "squat",
            .sets = &.{.{
                .id = "set-1",
                .kind = "working",
                .targetMetrics = &.{.{ .code = "load", .value = .{ .amount = "185.00", .unit = "lb" } }},
            }},
        }},
    };
    const start: protocol.StartWorkout = .{
        .metadata = .{ .commandId = "start-1", .occurredAt = "2026-08-04T12:00:00Z" },
        .scope = workout.scope,
        .workoutId = workout.id,
        .startedAt = workout.startedAt,
    };
    const snapshot: protocol.TrackingSnapshot = .{
        .workouts = &.{workout},
        .startReceipts = &.{.{ .command = start, .disposition = .applied, .workout = workout }},
    };
    var workouts: [1]tracking.Workout = undefined;
    var receipts: [1]tracking.StartReceipt = undefined;
    var exercises: [1]tracking.ExerciseMembership = undefined;
    var sets: [1]tracking.TrackedSet = undefined;
    var metrics: [1]tracking.Metric = undefined;
    const typed = try protocol.snapshotToDomain(snapshot, .{
        .workouts = &workouts,
        .receipts = &receipts,
        .exercises = &exercises,
        .sets = &sets,
        .metrics = &metrics,
    });
    try std.testing.expectEqual(@as(i64, 18500), typed.workouts[0].exercises[0].sets[0].target_metrics[0].value.value.mantissa);
    try std.testing.expectEqual(tracking.CommandDisposition.applied, typed.start_receipts[0].accepted.disposition);

    var wire_workouts: [1]protocol.TrackedWorkout = undefined;
    var wire_receipts: [1]protocol.StartReceipt = undefined;
    var wire_exercises: [1]protocol.ExerciseMembership = undefined;
    var wire_sets: [1]protocol.TrackedSet = undefined;
    var wire_metrics: [1]@import("caudex").canonical.Metric = undefined;
    var amounts: [1][64]u8 = undefined;
    const round_trip = try protocol.snapshotFromDomain(typed, .{
        .workouts = &wire_workouts,
        .receipts = &wire_receipts,
        .exercises = &wire_exercises,
        .sets = &wire_sets,
        .metrics = &wire_metrics,
        .amountBytes = &amounts,
    });
    try std.testing.expectEqualStrings("185.00", round_trip.workouts[0].exercises[0].sets[0].targetMetrics[0].value.amount);
    try std.testing.expectEqualStrings("start-1", round_trip.startReceipts[0].command.metadata.commandId);
}

test "canonical atomic batch executes through the typed reducer" {
    const commands = [_]protocol.Command{
        .{ .startWorkout = .{
            .metadata = .{ .commandId = "start-1", .occurredAt = "2026-08-04T12:00:00Z" },
            .scope = .{ .hostScopeKey = "scope-1" },
            .workoutId = "workout-1",
            .startedAt = "2026-08-04T12:00:00Z",
        } },
        .{ .addExercise = .{
            .metadata = .{ .commandId = "add-exercise-1", .occurredAt = "2026-08-04T12:01:00Z" },
            .scope = .{ .hostScopeKey = "scope-1" },
            .workoutId = "workout-1",
            .expectedRevision = 1,
            .membershipId = "membership-1",
            .exerciseId = "squat",
            .anchor = .end,
        } },
    };
    var typed_commands: [commands.len]tracking.Command = undefined;
    var command_metrics: [1]tracking.Metric = undefined;
    const converted = try protocol.batchCommandsToDomain(&commands, &typed_commands, &command_metrics);
    var workouts: [2]tracking.Workout = undefined;
    var receipts: [2]tracking.StartReceipt = undefined;
    var exercises: [2]tracking.ExerciseMembership = undefined;
    var sets: [2]tracking.TrackedSet = undefined;
    var issues: [commands.len]tracking.Issue = undefined;
    var outcomes: [commands.len]tracking.AcceptedCommand = undefined;
    const result = try tracking.applyAtomicBatch(
        .{ .exercise_catalog = &.{.{ .exercise_id = .{ .bytes = "squat" }, .availability = .active }} },
        converted,
        .{ .workouts = &workouts, .start_receipts = &receipts, .exercises = &exercises, .sets = &sets, .issues = &issues, .outcomes = &outcomes },
    );
    try std.testing.expectEqual(@as(u64, 2), result.accepted.snapshot.workouts[0].revision);
}
