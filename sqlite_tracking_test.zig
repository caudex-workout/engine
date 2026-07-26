const std = @import("std");
const persistence = @import("caudex_persistence");
const sqlite = @import("caudex_sqlite");
const tracking = @import("caudex_tracking");

const scope: tracking.Scope = .{
    .host_scope_key = .{ .bytes = "local-profile" },
    .athlete_id = .{ .bytes = "athlete-1" },
};
const start: tracking.StartWorkoutCommand = .{
    .metadata = .{
        .command_id = .{ .bytes = "command-start-1" },
        .occurred_at = .{ .bytes = "2026-07-26T12:00:00Z" },
    },
    .scope = scope,
    .workout_id = .{ .bytes = "workout-1" },
    .started_at = .{ .bytes = "2026-07-26T12:00:00Z" },
};

test "workout started through one instance is read through another" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const path = try databasePath(temporary, "tracking.sqlite");
    defer std.testing.allocator.free(path);

    {
        const writer = try sqlite.open(path, .{});
        defer writer.close();
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const result = try writer.startWorkout(arena.allocator(), start);
        try expectAccepted(result, .applied, "workout-1");
    }
    {
        const reader = try sqlite.open(path, .{});
        defer reader.close();
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const result = try reader.readWorkout(arena.allocator(), .{
            .scope = scope,
            .workout_id = start.workout_id,
        });
        try std.testing.expectEqualStrings("workout-1", result.found.id.bytes);
        try std.testing.expectEqual(@as(u64, 1), result.found.revision);
        try std.testing.expectEqual(tracking.WorkoutStatus.active, result.found.status);
    }
}

test "retry returns replay without duplicating or replacing the workout" {
    const database = try sqlite.openInMemory(.{});
    defer database.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try expectAccepted(
        try database.startWorkout(arena.allocator(), start),
        .applied,
        "workout-1",
    );
    try expectAccepted(
        try database.startWorkout(arena.allocator(), start),
        .replayed,
        "workout-1",
    );

    var changed = start;
    changed.workout_id = .{ .bytes = "workout-2" };
    const conflict = try database.startWorkout(arena.allocator(), changed);
    try expectRejected(
        conflict,
        tracking.issue_codes.command_payload_conflict,
    );
    try expectNotFound(try database.readWorkout(arena.allocator(), .{
        .scope = scope,
        .workout_id = changed.workout_id,
    }));
    const original = try database.readWorkout(arena.allocator(), .{
        .scope = scope,
        .workout_id = start.workout_id,
    });
    try std.testing.expectEqualStrings("workout-1", original.found.id.bytes);
}

test "rejected duplicate rolls back without recording its command receipt" {
    const database = try sqlite.openInMemory(.{});
    defer database.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try database.startWorkout(arena.allocator(), start);
    var duplicate = start;
    duplicate.metadata.command_id = .{ .bytes = "command-start-2" };
    const rejected = try database.startWorkout(arena.allocator(), duplicate);
    try expectRejected(rejected, tracking.issue_codes.workout_id_conflict);

    duplicate.workout_id = .{ .bytes = "workout-2" };
    try expectAccepted(
        try database.startWorkout(arena.allocator(), duplicate),
        .applied,
        "workout-2",
    );
    const stored = try database.readWorkout(arena.allocator(), .{
        .scope = scope,
        .workout_id = duplicate.workout_id,
    });
    try std.testing.expectEqualStrings("workout-2", stored.found.id.bytes);
}

test "invalid start is rejected and leaves no workout or receipt" {
    const database = try sqlite.openInMemory(.{});
    defer database.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var invalid = start;
    invalid.started_at = .{ .bytes = "invalid" };
    try expectRejected(
        try database.startWorkout(arena.allocator(), invalid),
        tracking.issue_codes.invalid_timestamp,
    );

    invalid.started_at = start.started_at;
    try expectAccepted(
        try database.startWorkout(arena.allocator(), invalid),
        .applied,
        "workout-1",
    );
}

test "execution failure rolls back before workout and receipt become visible" {
    const database = try sqlite.openInMemory(.{});
    defer database.close();
    var no_memory: [0]u8 = .{};
    var failing = std.heap.FixedBufferAllocator.init(&no_memory);
    try std.testing.expectError(
        error.OutOfMemory,
        database.startWorkout(failing.allocator(), start),
    );

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectNotFound(try database.readWorkout(arena.allocator(), .{
        .scope = scope,
        .workout_id = start.workout_id,
    }));
    try expectAccepted(
        try database.startWorkout(arena.allocator(), start),
        .applied,
        "workout-1",
    );
}

test "exercise add remove and reorder persist atomically" {
    const database = try sqlite.openInMemory(.{});
    defer database.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try database.replaceCatalog(allocator, .{
        .host_scope_key = scope.host_scope_key.bytes,
        .as_of = start.started_at.bytes,
    }, &.{
        persistence.canonical.Exercise{ .id = "bench" },
        persistence.canonical.Exercise{ .id = "row" },
    });
    _ = try database.startWorkout(allocator, start);

    const bench = try database.addExercise(allocator, .{
        .metadata = metadata("add-bench"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 1,
        .membership_id = .{ .bytes = "bench-membership" },
        .exercise_id = .{ .bytes = "bench" },
        .anchor = .end,
    });
    try expectOrder(bench.accepted.workout, &.{"bench-membership"});
    const row = try database.addExercise(allocator, .{
        .metadata = metadata("add-row"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 2,
        .membership_id = .{ .bytes = "row-membership" },
        .exercise_id = .{ .bytes = "row" },
        .anchor = .beginning,
    });
    try expectOrder(row.accepted.workout, &.{
        "row-membership",
        "bench-membership",
    });
    const reordered = try database.reorderExercise(allocator, .{
        .metadata = metadata("reorder-bench"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 3,
        .membership_id = .{ .bytes = "bench-membership" },
        .anchor = .beginning,
    });
    try expectOrder(reordered.accepted.workout, &.{
        "bench-membership",
        "row-membership",
    });
    const removed = try database.removeExercise(allocator, .{
        .metadata = metadata("remove-row"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 4,
        .membership_id = .{ .bytes = "row-membership" },
    });
    try expectOrder(removed.accepted.workout, &.{"bench-membership"});

    const persisted = try database.readWorkout(allocator, .{
        .scope = scope,
        .workout_id = start.workout_id,
    });
    try std.testing.expectEqual(@as(u64, 5), persisted.found.revision);
    try expectOrder(persisted.found, &.{"bench-membership"});

    const rejected = try database.reorderExercise(allocator, .{
        .metadata = metadata("bad-reorder"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 5,
        .membership_id = .{ .bytes = "bench-membership" },
        .anchor = .{ .after = .{ .bytes = "missing-membership" } },
    });
    try expectRejected(rejected, tracking.issue_codes.invalid_exercise_anchor);
    const unchanged = try database.readWorkout(allocator, .{
        .scope = scope,
        .workout_id = start.workout_id,
    });
    try std.testing.expectEqual(@as(u64, 5), unchanged.found.revision);
    try expectOrder(unchanged.found, &.{"bench-membership"});
}

test "adapter distinguishes archived and missing catalog exercises" {
    const database = try sqlite.openInMemory(.{});
    defer database.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const catalog_scope: persistence.CatalogScope = .{
        .host_scope_key = scope.host_scope_key.bytes,
        .as_of = start.started_at.bytes,
    };
    try database.replaceCatalog(allocator, catalog_scope, &.{
        persistence.canonical.Exercise{ .id = "archived" },
    });
    try database.replaceCatalog(allocator, catalog_scope, &.{});
    _ = try database.startWorkout(allocator, start);

    const archived = try database.addExercise(allocator, .{
        .metadata = metadata("add-archived"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 1,
        .membership_id = .{ .bytes = "membership-1" },
        .exercise_id = .{ .bytes = "archived" },
        .anchor = .end,
    });
    try expectRejected(archived, tracking.issue_codes.exercise_archived);
    const missing = try database.addExercise(allocator, .{
        .metadata = metadata("add-missing"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 1,
        .membership_id = .{ .bytes = "membership-1" },
        .exercise_id = .{ .bytes = "never-existed" },
        .anchor = .end,
    });
    try expectRejected(missing, tracking.issue_codes.exercise_not_found);
}

fn metadata(command_id: []const u8) tracking.CommandMetadata {
    return .{
        .command_id = .{ .bytes = command_id },
        .occurred_at = .{ .bytes = "2026-07-26T12:01:00Z" },
    };
}

fn expectOrder(workout: tracking.Workout, expected: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, workout.exercises.len);
    for (expected, workout.exercises) |id, membership| {
        try std.testing.expectEqualStrings(id, membership.id.bytes);
    }
}

fn expectAccepted(
    result: tracking.CommandResult,
    disposition: tracking.CommandDisposition,
    workout_id: []const u8,
) !void {
    switch (result) {
        .accepted => |accepted| {
            try std.testing.expectEqual(disposition, accepted.disposition);
            try std.testing.expectEqualStrings(workout_id, accepted.workout.id.bytes);
        },
        .rejected => return error.UnexpectedRejection,
    }
}

fn expectRejected(result: tracking.CommandResult, code: []const u8) !void {
    switch (result) {
        .accepted => return error.UnexpectedAcceptance,
        .rejected => |rejected| {
            try std.testing.expectEqual(@as(usize, 1), rejected.issues.len);
            try std.testing.expectEqualStrings(code, rejected.issues[0].code);
        },
    }
}

fn expectNotFound(result: tracking.ReadWorkoutResult) !void {
    switch (result) {
        .found => return error.UnexpectedWorkout,
        .not_found => |issue| try std.testing.expectEqualStrings(
            tracking.issue_codes.workout_not_found,
            issue.code,
        ),
    }
}

fn databasePath(
    temporary: std.testing.TmpDir,
    name: []const u8,
) ![:0]u8 {
    return std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/{s}",
        .{ temporary.sub_path, name },
        0,
    );
}
