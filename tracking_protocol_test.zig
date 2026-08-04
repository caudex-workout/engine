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
