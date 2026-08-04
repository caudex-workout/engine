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

test "workflow-instantiated provenance and prescription survive reopen" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const path = try databasePath(temporary, "workflow.sqlite");
    defer std.testing.allocator.free(path);
    const target: tracking.Metric = .{
        .code = .{ .bytes = "load" },
        .value = .{ .value = .{ .mantissa = 18500, .scale = 2 }, .unit = .lb },
    };
    const prescribed_set: tracking.PrescribedSet = .{ .set_id = .{ .bytes = "set-1" }, .kind = .{ .bytes = "working" }, .target_metrics = &.{target} };
    const prescription: tracking.PrescribedExercise = .{ .membership_id = .{ .bytes = "membership-1" }, .exercise_id = .{ .bytes = "squat" }, .sets = &.{prescribed_set} };
    const workout: tracking.Workout = .{
        .id = .{ .bytes = "workflow-workout-1" },
        .scope = scope,
        .revision = 1,
        .status = .active,
        .started_at = .{ .bytes = "2026-07-26T12:00:00Z" },
        .exercises = &.{.{ .id = prescription.membership_id, .exercise_id = prescription.exercise_id, .sets = &.{.{ .id = prescribed_set.set_id, .kind = prescribed_set.kind, .target_metrics = prescribed_set.target_metrics }} }},
        .origin = .recommendation,
        .provenance = .{ .recommendation = .{
            .accepted_recommendation_id = .{ .bytes = "accepted-1" },
            .input_fingerprint = "input-fingerprint",
            .result_fingerprint = "result-fingerprint",
            .methodology_id = .{ .bytes = "caudex.double-progression" },
            .methodology_version = "1.0.0",
            .methodology_config_version = 1,
        } },
        .prescription = &.{prescription},
    };
    {
        const writer = try sqlite.open(path, .{});
        defer writer.close();
        try writer.saveInstantiatedWorkout(std.testing.allocator, workout);
    }
    const reader = try sqlite.open(path, .{});
    defer reader.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const loaded = (try reader.readWorkout(arena.allocator(), .{ .scope = scope, .workout_id = workout.id })).found;
    try std.testing.expectEqual(tracking.WorkoutOrigin.recommendation, loaded.origin);
    try std.testing.expectEqualStrings("result-fingerprint", loaded.provenance.?.recommendation.result_fingerprint);
    try std.testing.expectEqual(@as(i64, 18500), loaded.prescription[0].sets[0].target_metrics[0].value.value.mantissa);
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

test "portable active workout preserves exact targets scope and start replay" {
    const source = try sqlite.openInMemory(.{});
    defer source.close();
    const destination = try sqlite.openInMemory(.{});
    defer destination.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try source.replaceCatalog(allocator, .{ .host_scope_key = scope.host_scope_key.bytes, .as_of = start.started_at.bytes }, &.{.{ .id = "bench" }});
    _ = try source.startWorkout(allocator, start);
    _ = try source.addExercise(allocator, .{
        .metadata = metadata("portable-add-bench"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 1,
        .membership_id = .{ .bytes = "bench-membership" },
        .exercise_id = .{ .bytes = "bench" },
        .anchor = .end,
    });
    const target: tracking.Metric = .{ .code = .{ .bytes = "load" }, .value = .{ .value = .{ .mantissa = 18500, .scale = 2 }, .unit = .lb } };
    _ = try source.addSet(allocator, .{
        .metadata = metadata("portable-add-set"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 2,
        .membership_id = .{ .bytes = "bench-membership" },
        .set_id = .{ .bytes = "set-1" },
        .kind = .{ .bytes = "working" },
        .target_metrics = &.{target},
        .anchor = .end,
    });

    const document = try source.portableStore().exportData(allocator, .{ .host_scope_key = scope.host_scope_key.bytes, .exported_at = "2026-08-04T12:00:00Z" });
    try std.testing.expectEqualStrings("athlete-1", document.activeWorkouts[0].athleteId.?);
    try std.testing.expectEqualStrings("185.00", document.activeWorkouts[0].snapshot.workouts[0].exercises[0].sets[0].targetMetrics[0].value.amount);
    const imported = try destination.portableStore().importData(allocator, .{ .schemaVersion = 1, .mode = .replace, .conflictPolicy = .overwrite, .dryRun = false, .document = document });
    try std.testing.expect(imported.valid);
    const loaded = (try destination.readWorkout(allocator, .{ .scope = scope, .workout_id = start.workout_id })).found;
    try std.testing.expectEqual(@as(u64, 3), loaded.revision);
    try std.testing.expectEqual(@as(i64, 18500), loaded.exercises[0].sets[0].target_metrics[0].value.value.mantissa);
    const replay = try destination.startWorkout(allocator, start);
    try std.testing.expectEqual(tracking.CommandDisposition.replayed, replay.accepted.disposition);
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

test "set lifecycle is exact idempotent and transactional" {
    const database = try sqlite.openInMemory(.{});
    defer database.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try database.replaceCatalog(allocator, .{
        .host_scope_key = scope.host_scope_key.bytes,
        .as_of = start.started_at.bytes,
    }, &.{persistence.canonical.Exercise{ .id = "bench" }});
    _ = try database.startWorkout(allocator, start);
    _ = try database.addExercise(allocator, .{
        .metadata = metadata("add-bench"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 1,
        .membership_id = .{ .bytes = "bench-membership" },
        .exercise_id = .{ .bytes = "bench" },
        .anchor = .end,
    });
    const target: tracking.Metric = .{
        .code = .{ .bytes = "load" },
        .value = .{ .value = .{ .mantissa = 1025, .scale = 1 }, .unit = .kg },
    };
    const actual: tracking.Metric = .{
        .code = .{ .bytes = "rpe" },
        .value = .{ .value = .{ .mantissa = 85, .scale = 1 }, .unit = .rpe },
    };
    const add: tracking.AddSetCommand = .{
        .metadata = metadata("add-set-1"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 2,
        .membership_id = .{ .bytes = "bench-membership" },
        .set_id = .{ .bytes = "set-1" },
        .kind = .{ .bytes = "working" },
        .target_metrics = &.{target},
        .anchor = .end,
    };
    const applied = try database.addSet(allocator, add);
    try std.testing.expectEqual(tracking.CommandDisposition.applied, applied.accepted.disposition);
    const replayed = try database.addSet(allocator, add);
    try std.testing.expectEqual(tracking.CommandDisposition.replayed, replayed.accepted.disposition);
    try std.testing.expectEqual(@as(u64, 3), replayed.accepted.workout.revision);

    var conflicting = add;
    conflicting.kind = .{ .bytes = "warmup" };
    try expectRejected(
        try database.addSet(allocator, conflicting),
        tracking.issue_codes.command_payload_conflict,
    );
    var stale = add;
    stale.metadata = metadata("stale-add");
    stale.set_id = .{ .bytes = "set-stale" };
    stale.expected_revision = 2;
    try expectRejected(
        try database.addSet(allocator, stale),
        tracking.issue_codes.revision_conflict,
    );

    const completed = try database.completeSet(allocator, .{
        .metadata = metadata("complete-set-1"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 3,
        .membership_id = .{ .bytes = "bench-membership" },
        .set_id = .{ .bytes = "set-1" },
        .actual_metrics = &.{actual},
        .completed_at = .{ .bytes = "2026-07-26T12:02:00Z" },
    });
    const stored_set = completed.accepted.workout.exercises[0].sets[0];
    try std.testing.expectEqual(tracking.SetStatus.completed, stored_set.status);
    try std.testing.expectEqual(@as(i64, 1025), stored_set.target_metrics[0].value.value.mantissa);
    try std.testing.expectEqual(@as(i64, 85), stored_set.actual_metrics[0].value.value.mantissa);

    try expectRejected(try database.skipSet(allocator, .{
        .metadata = metadata("invalid-skip"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 4,
        .membership_id = .{ .bytes = "bench-membership" },
        .set_id = .{ .bytes = "set-1" },
        .skipped_at = .{ .bytes = "2026-07-26T12:03:00Z" },
    }), tracking.issue_codes.invalid_set_transition);
    const unchanged = try database.readWorkout(allocator, .{
        .scope = scope,
        .workout_id = start.workout_id,
    });
    try std.testing.expectEqual(@as(u64, 4), unchanged.found.revision);
    try std.testing.expectEqual(tracking.SetStatus.completed, unchanged.found.exercises[0].sets[0].status);
    try std.testing.expectEqual(@as(i64, 1025), unchanged.found.exercises[0].sets[0].target_metrics[0].value.value.mantissa);
    try std.testing.expectEqual(@as(i64, 85), unchanged.found.exercises[0].sets[0].actual_metrics[0].value.value.mantissa);

    const reopened = try database.reopenSet(allocator, .{
        .metadata = metadata("reopen-set-1"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 4,
        .membership_id = .{ .bytes = "bench-membership" },
        .set_id = .{ .bytes = "set-1" },
    });
    try std.testing.expectEqual(tracking.SetStatus.open, reopened.accepted.workout.exercises[0].sets[0].status);
    try std.testing.expectEqual(@as(usize, 0), reopened.accepted.workout.exercises[0].sets[0].actual_metrics.len);
}

test "workout finish and cancel persist atomically and replay idempotently" {
    const database = try sqlite.openInMemory(.{});
    defer database.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    _ = try database.startWorkout(allocator, start);
    const finish: tracking.CompleteWorkoutCommand = .{
        .metadata = metadata("finish-workout"),
        .scope = scope,
        .workout_id = start.workout_id,
        .expected_revision = 1,
        .completed_at = .{ .bytes = "2026-07-26T12:05:00Z" },
    };
    const applied = try database.completeWorkout(allocator, finish);
    try std.testing.expectEqual(tracking.WorkoutStatus.completed, applied.accepted.workout.status);
    try std.testing.expectEqual(@as(usize, 1), applied.accepted.issues.len);
    const replayed = try database.completeWorkout(allocator, finish);
    try std.testing.expectEqual(tracking.CommandDisposition.replayed, replayed.accepted.disposition);
    var second = start;
    second.metadata.command_id = .{ .bytes = "start-cancelled" };
    second.workout_id = .{ .bytes = "workout-cancelled" };
    _ = try database.startWorkout(allocator, second);
    const cancelled = try database.cancelWorkout(allocator, .{
        .metadata = metadata("cancel-workout"),
        .scope = scope,
        .workout_id = second.workout_id,
        .expected_revision = 1,
        .cancelled_at = .{ .bytes = "2026-07-26T12:06:00Z" },
    });
    try std.testing.expectEqual(tracking.WorkoutStatus.cancelled, cancelled.accepted.workout.status);
    const active = try database.listActiveWorkouts(allocator, .{ .scope = scope, .max_results = 10 });
    try std.testing.expect(active == .none);
}

test "completed history is bounded, indexed, and corrected with a receipt" {
    const database = try sqlite.openInMemory(.{});
    defer database.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try database.replaceCatalog(allocator, .{ .host_scope_key = scope.host_scope_key.bytes, .as_of = start.started_at.bytes }, &.{.{ .id = "bench" }});
    _ = try database.startWorkout(allocator, start);
    _ = try database.addExercise(allocator, .{ .metadata = metadata("history-add"), .scope = scope, .workout_id = start.workout_id, .expected_revision = 1, .membership_id = .{ .bytes = "history-membership" }, .exercise_id = .{ .bytes = "bench" }, .anchor = .end });
    _ = try database.addSet(allocator, .{ .metadata = metadata("history-set"), .scope = scope, .workout_id = start.workout_id, .expected_revision = 2, .membership_id = .{ .bytes = "history-membership" }, .set_id = .{ .bytes = "history-set" }, .kind = .{ .bytes = "working" }, .anchor = .end });
    const first_metric: tracking.Metric = .{ .code = .{ .bytes = "rpe" }, .value = .{ .value = .{ .mantissa = 8, .scale = 0 }, .unit = .rpe } };
    _ = try database.logSet(allocator, .{ .metadata = metadata("history-log"), .scope = scope, .workout_id = start.workout_id, .expected_revision = 3, .membership_id = .{ .bytes = "history-membership" }, .set_id = .{ .bytes = "history-set" }, .actual_metrics = &.{first_metric}, .completed_at = .{ .bytes = "2026-07-26T12:02:00Z" } });
    _ = try database.completeWorkout(allocator, .{ .metadata = metadata("history-finish"), .scope = scope, .workout_id = start.workout_id, .expected_revision = 4, .completed_at = .{ .bytes = "2026-07-26T12:03:00Z" } });
    const page = try database.listHistory(allocator, .{ .scope = scope, .from = .{ .bytes = "2026-07-26T12:00:00Z" }, .through = .{ .bytes = "2026-07-26T12:04:00Z" }, .exercise_id = .{ .bytes = "bench" }, .max_results = 1 });
    try std.testing.expectEqual(@as(usize, 1), page.workouts.len);
    const last = try database.lastPerformance(allocator, .{ .scope = scope, .exercise_id = .{ .bytes = "bench" } });
    try std.testing.expectEqualStrings("workout-1", last.found.id.bytes);
    const corrected_metric: tracking.Metric = .{ .code = .{ .bytes = "rpe" }, .value = .{ .value = .{ .mantissa = 9, .scale = 0 }, .unit = .rpe } };
    const correction: tracking.CorrectSetCommand = .{ .metadata = metadata("history-correct"), .scope = scope, .workout_id = start.workout_id, .expected_revision = 5, .membership_id = .{ .bytes = "history-membership" }, .set_id = .{ .bytes = "history-set" }, .actual_metrics = &.{corrected_metric}, .completed_at = .{ .bytes = "2026-07-26T12:04:00Z" } };
    const applied = try database.correctSet(allocator, correction);
    try std.testing.expectEqual(@as(u64, 6), applied.accepted.workout.revision);
    try std.testing.expectEqual(@as(i64, 9), applied.accepted.workout.exercises[0].sets[0].actual_metrics[0].value.value.mantissa);
    const replayed = try database.correctSet(allocator, correction);
    try std.testing.expectEqual(tracking.CommandDisposition.replayed, replayed.accepted.disposition);
}

test "managed catalog is revisioned searchable idempotent and snapshot compatible" {
    const database = try sqlite.openInMemory(.{});
    defer database.close();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const catalog_scope: tracking.Id = .{ .bytes = "managed-catalog" };
    const create: tracking.CreateExerciseCommand = .{
        .metadata = metadata("create-bench"),
        .host_scope_key = catalog_scope,
        .exercise = .{ .id = "bench", .name = "Bench Press", .aliases = &.{"press"}, .equipmentIds = &.{"barbell"} },
    };
    const created = try database.createExercise(allocator, create);
    try std.testing.expectEqual(@as(u64, 1), created.accepted.exercise.revision);
    const replayed = try database.createExercise(allocator, create);
    try std.testing.expectEqual(tracking.CommandDisposition.replayed, replayed.accepted.disposition);
    var conflict = create;
    conflict.exercise.name = "Changed";
    try expectCatalogRejected(try database.createExercise(allocator, conflict), tracking.issue_codes.command_payload_conflict);
    const search = try database.searchExercises(allocator, .{ .host_scope_key = catalog_scope, .text = "pre", .max_results = 10 });
    try std.testing.expectEqual(@as(usize, 1), search.found.len);
    const listed = try database.listExercises(allocator, .{ .host_scope_key = catalog_scope, .max_results = 10 });
    try std.testing.expectEqual(@as(usize, 1), listed.found.len);
    var edited_exercise = create.exercise;
    edited_exercise.name = "Competition Bench Press";
    try expectCatalogRejected(try database.editExercise(allocator, .{
        .metadata = metadata("stale-edit"),
        .host_scope_key = catalog_scope,
        .exercise = edited_exercise,
        .expected_revision = 0,
    }), tracking.issue_codes.catalog_revision_conflict);
    const edited = try database.editExercise(allocator, .{
        .metadata = metadata("edit-bench"),
        .host_scope_key = catalog_scope,
        .exercise = edited_exercise,
        .expected_revision = 1,
    });
    try std.testing.expectEqual(@as(u64, 2), edited.accepted.exercise.revision);
    const archived = try database.archiveExercise(allocator, .{
        .metadata = metadata("archive-bench"),
        .host_scope_key = catalog_scope,
        .exercise_id = .{ .bytes = "bench" },
        .expected_revision = 2,
    });
    try std.testing.expectEqual(tracking.ExerciseAvailability.archived, archived.accepted.exercise.availability);
    const active_snapshot = try database.catalogSource().load(allocator, .{ .host_scope_key = catalog_scope.bytes, .as_of = "2026-07-26T12:10:00Z" });
    try std.testing.expectEqual(@as(usize, 0), active_snapshot.len);
    const hidden = try database.searchExercises(allocator, .{ .host_scope_key = catalog_scope, .text = "bench", .max_results = 10 });
    try std.testing.expectEqual(@as(usize, 0), hidden.found.len);
    const archived_hidden = try database.listExercises(allocator, .{ .host_scope_key = catalog_scope, .max_results = 10 });
    try std.testing.expectEqual(@as(usize, 0), archived_hidden.found.len);
    const including_archived = try database.searchExercises(allocator, .{ .host_scope_key = catalog_scope, .text = "bench", .max_results = 10, .include_archived = true });
    try std.testing.expectEqual(@as(usize, 1), including_archived.found.len);
    const restored = try database.restoreExercise(allocator, .{
        .metadata = metadata("restore-bench"),
        .host_scope_key = catalog_scope,
        .exercise_id = .{ .bytes = "bench" },
        .expected_revision = 3,
    });
    try std.testing.expectEqual(tracking.ExerciseAvailability.active, restored.accepted.exercise.availability);
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

fn expectCatalogRejected(result: tracking.CatalogCommandResult, code: []const u8) !void {
    switch (result) {
        .accepted => return error.UnexpectedAcceptance,
        .rejected => |rejected| try std.testing.expectEqualStrings(code, rejected.issues[0].code),
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
