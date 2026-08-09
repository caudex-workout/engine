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

test "short completion and cancellation are distinct terminal states" {
    var issues: [1]tracking.Issue = undefined;
    const workout = (try tracking.startWorkout(.{}, command, &issues)).accepted.workout;
    const completed = try tracking.endWorkout(.{ .workouts = &.{workout} }, .{ .complete = .{
        .metadata = .{ .command_id = .{ .bytes = "finish" }, .occurred_at = .{ .bytes = "2026-07-26T12:05:00Z" } },
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = 1,
        .completed_at = .{ .bytes = "2026-07-26T12:05:00Z" },
    } }, &issues);
    try std.testing.expectEqual(tracking.WorkoutStatus.completed, completed.accepted.workout.status);
    try std.testing.expectEqualStrings(tracking.issue_codes.short_workout_completed, completed.accepted.issues[0].code);
    const cancelled = try tracking.endWorkout(.{ .workouts = &.{workout} }, .{ .cancel = .{
        .metadata = .{ .command_id = .{ .bytes = "cancel" }, .occurred_at = .{ .bytes = "2026-07-26T12:06:00Z" } },
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = 1,
        .cancelled_at = .{ .bytes = "2026-07-26T12:06:00Z" },
    } }, &issues);
    try std.testing.expectEqual(tracking.WorkoutStatus.cancelled, cancelled.accepted.workout.status);
    try std.testing.expectEqual(@as(usize, 0), cancelled.accepted.issues.len);
    const rejected = try tracking.endWorkout(.{ .workouts = &.{completed.accepted.workout} }, .{ .cancel = .{
        .metadata = .{ .command_id = .{ .bytes = "late-cancel" }, .occurred_at = .{ .bytes = "2026-07-26T12:07:00Z" } },
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = 2,
        .cancelled_at = .{ .bytes = "2026-07-26T12:07:00Z" },
    } }, &issues);
    try expectRejectedCode(rejected, tracking.issue_codes.workout_not_active);
}

test "catalog management validates revisions and reversible availability" {
    const catalog_scope: tracking.Id = .{ .bytes = "catalog-scope" };
    const exercise = tracking.canonical.Exercise{ .id = "bench", .name = "Bench Press", .aliases = &.{"press"} };
    var issues: [1]tracking.Issue = undefined;
    const created = try tracking.applyCatalogCommand(.{}, .{ .create = .{
        .metadata = .{ .command_id = .{ .bytes = "create-bench" }, .occurred_at = command.started_at },
        .host_scope_key = catalog_scope,
        .exercise = exercise,
    } }, &issues);
    try std.testing.expectEqual(@as(u64, 1), created.accepted.exercise.revision);
    var duplicate = exercise;
    duplicate.aliases = &.{ "press", "press" };
    try expectCatalogRejected(try tracking.applyCatalogCommand(.{}, .{ .create = .{
        .metadata = .{ .command_id = .{ .bytes = "invalid" }, .occurred_at = command.started_at },
        .host_scope_key = catalog_scope,
        .exercise = duplicate,
    } }, &issues), tracking.issue_codes.catalog_invalid_exercise);
    const archived = try tracking.applyCatalogCommand(.{ .exercises = &.{created.accepted.exercise} }, .{ .archive = .{
        .metadata = .{ .command_id = .{ .bytes = "archive" }, .occurred_at = command.started_at },
        .host_scope_key = catalog_scope,
        .exercise_id = .{ .bytes = "bench" },
        .expected_revision = 1,
    } }, &issues);
    try std.testing.expectEqual(tracking.ExerciseAvailability.archived, archived.accepted.exercise.availability);
    try expectCatalogRejected(try tracking.applyCatalogCommand(.{ .exercises = &.{archived.accepted.exercise} }, .{ .restore = .{
        .metadata = .{ .command_id = .{ .bytes = "stale" }, .occurred_at = command.started_at },
        .host_scope_key = catalog_scope,
        .exercise_id = .{ .bytes = "bench" },
        .expected_revision = 1,
    } }, &issues), tracking.issue_codes.catalog_revision_conflict);
    const restored = try tracking.applyCatalogCommand(.{ .exercises = &.{archived.accepted.exercise} }, .{ .restore = .{
        .metadata = .{ .command_id = .{ .bytes = "restore" }, .occurred_at = command.started_at },
        .host_scope_key = catalog_scope,
        .exercise_id = .{ .bytes = "bench" },
        .expected_revision = 2,
    } }, &issues);
    try std.testing.expectEqual(tracking.ExerciseAvailability.active, restored.accepted.exercise.availability);
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

test "exercise ordering uses semantic anchors deterministically" {
    const bench: tracking.ExerciseCatalogEntry = .{
        .exercise_id = .{ .bytes = "bench" },
        .availability = .active,
    };
    const row: tracking.ExerciseCatalogEntry = .{
        .exercise_id = .{ .bytes = "row" },
        .availability = .active,
    };
    const curl: tracking.ExerciseCatalogEntry = .{
        .exercise_id = .{ .bytes = "curl" },
        .availability = .active,
    };
    var issues: [1]tracking.Issue = undefined;
    var storage_a: [3]tracking.ExerciseMembership = undefined;
    var storage_b: [3]tracking.ExerciseMembership = undefined;
    const workout = (try tracking.startWorkout(.{}, command, &issues)).accepted.workout;

    const first = (try tracking.addExercise(.{
        .workouts = &.{workout},
        .exercise_catalog = &.{ bench, row, curl },
    }, addCommand("add-bench", 1, "bench-membership", "bench", .end), &storage_a, &issues)).accepted.workout;
    try expectOrder(first, &.{"bench-membership"});

    const second = (try tracking.addExercise(.{
        .workouts = &.{first},
        .exercise_catalog = &.{ bench, row, curl },
    }, addCommand("add-row", 2, "row-membership", "row", .beginning), &storage_b, &issues)).accepted.workout;
    try expectOrder(second, &.{ "row-membership", "bench-membership" });

    const third = (try tracking.addExercise(.{
        .workouts = &.{second},
        .exercise_catalog = &.{ bench, row, curl },
    }, addCommand(
        "add-curl",
        3,
        "curl-membership",
        "curl",
        .{ .after = .{ .bytes = "row-membership" } },
    ), &storage_a, &issues)).accepted.workout;
    try expectOrder(third, &.{
        "row-membership",
        "curl-membership",
        "bench-membership",
    });

    const reordered = (try tracking.reorderExercise(
        .{ .workouts = &.{third} },
        .{
            .metadata = metadata("reorder-bench"),
            .scope = scope,
            .workout_id = command.workout_id,
            .expected_revision = 4,
            .membership_id = .{ .bytes = "bench-membership" },
            .anchor = .beginning,
        },
        &storage_b,
        &issues,
    )).accepted.workout;
    try expectOrder(reordered, &.{
        "bench-membership",
        "row-membership",
        "curl-membership",
    });

    const removed = (try tracking.removeExercise(
        .{ .workouts = &.{reordered} },
        .{
            .metadata = metadata("remove-row"),
            .scope = scope,
            .workout_id = command.workout_id,
            .expected_revision = 5,
            .membership_id = .{ .bytes = "row-membership" },
        },
        &storage_a,
        &issues,
    )).accepted.workout;
    try expectOrder(removed, &.{ "bench-membership", "curl-membership" });
    try std.testing.expectEqual(@as(u64, 6), removed.revision);
}

test "missing archived and invalid anchor exercises are structured issues" {
    const archived: tracking.ExerciseCatalogEntry = .{
        .exercise_id = .{ .bytes = "archived-exercise" },
        .availability = .archived,
    };
    var issues: [1]tracking.Issue = undefined;
    var storage: [2]tracking.ExerciseMembership = undefined;
    const workout = (try tracking.startWorkout(.{}, command, &issues)).accepted.workout;

    try expectRejectedCode(try tracking.addExercise(
        .{ .workouts = &.{workout} },
        addCommand("missing", 1, "membership-1", "missing", .end),
        &storage,
        &issues,
    ), tracking.issue_codes.exercise_not_found);
    try expectRejectedCode(try tracking.addExercise(
        .{
            .workouts = &.{workout},
            .exercise_catalog = &.{archived},
        },
        addCommand(
            "archived",
            1,
            "membership-1",
            "archived-exercise",
            .end,
        ),
        &storage,
        &issues,
    ), tracking.issue_codes.exercise_archived);

    const active = tracking.ExerciseCatalogEntry{
        .exercise_id = .{ .bytes = "active-exercise" },
        .availability = .active,
    };
    try expectRejectedCode(try tracking.addExercise(
        .{
            .workouts = &.{workout},
            .exercise_catalog = &.{active},
        },
        addCommand(
            "bad-anchor",
            1,
            "membership-1",
            "active-exercise",
            .{ .before = .{ .bytes = "missing-membership" } },
        ),
        &storage,
        &issues,
    ), tracking.issue_codes.invalid_exercise_anchor);
}

test "set lifecycle preserves exact targets and actuals" {
    const repetitions: tracking.Metric = .{
        .code = .{ .bytes = "repetitions" },
        .value = .{ .value = .{ .mantissa = 8, .scale = 0 }, .unit = .count },
    };
    const load: tracking.Metric = .{
        .code = .{ .bytes = "load" },
        .value = .{ .value = .{ .mantissa = 1025, .scale = 1 }, .unit = .kg },
    };
    const rir: tracking.Metric = .{
        .code = .{ .bytes = "rir" },
        .value = .{ .value = .{ .mantissa = 25, .scale = 1 }, .unit = .rir },
    };
    const rpe: tracking.Metric = .{
        .code = .{ .bytes = "rpe" },
        .value = .{ .value = .{ .mantissa = 85, .scale = 1 }, .unit = .rpe },
    };
    const duration: tracking.Metric = .{
        .code = .{ .bytes = "duration" },
        .value = .{ .value = .{ .mantissa = 455, .scale = 1 }, .unit = .s },
    };
    const membership: tracking.ExerciseMembership = .{
        .id = .{ .bytes = "bench-membership" },
        .exercise_id = .{ .bytes = "bench" },
    };
    const workout: tracking.Workout = .{
        .id = command.workout_id,
        .scope = scope,
        .revision = 1,
        .status = .active,
        .started_at = command.started_at,
        .exercises = &.{membership},
    };
    var issues: [1]tracking.Issue = undefined;
    var exercise_a: [1]tracking.ExerciseMembership = undefined;
    var exercise_b: [1]tracking.ExerciseMembership = undefined;
    var sets_a: [2]tracking.TrackedSet = undefined;
    var sets_b: [2]tracking.TrackedSet = undefined;

    const added = (try tracking.addSet(.{ .workouts = &.{workout} }, .{
        .metadata = metadata("add-set"),
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = 1,
        .membership_id = membership.id,
        .set_id = .{ .bytes = "set-1" },
        .kind = .{ .bytes = "working" },
        .target_metrics = &.{ repetitions, load, rir, duration },
        .anchor = .end,
    }, &exercise_a, &sets_a, &issues)).accepted.workout;
    try std.testing.expectEqual(tracking.SetStatus.open, added.exercises[0].sets[0].status);
    try std.testing.expectEqual(@as(i64, 1025), added.exercises[0].sets[0].target_metrics[1].value.value.mantissa);

    const completed = (try tracking.completeSet(.{ .workouts = &.{added} }, .{
        .metadata = metadata("complete-set"),
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = 2,
        .membership_id = membership.id,
        .set_id = .{ .bytes = "set-1" },
        .actual_metrics = &.{ repetitions, load, rpe, duration },
        .status = .completed,
        .completed_at = .{ .bytes = "2026-07-26T12:02:00Z" },
    }, &exercise_b, &sets_b, &issues)).accepted.workout;
    try std.testing.expectEqual(tracking.SetStatus.completed, completed.exercises[0].sets[0].status);
    try std.testing.expectEqual(@as(u8, 1), completed.exercises[0].sets[0].actual_metrics[1].value.value.scale);

    const reopened = (try tracking.reopenSet(.{ .workouts = &.{completed} }, .{
        .metadata = metadata("reopen-set"),
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = 3,
        .membership_id = membership.id,
        .set_id = .{ .bytes = "set-1" },
    }, &exercise_a, &sets_a, &issues)).accepted.workout;
    try std.testing.expectEqual(tracking.SetStatus.open, reopened.exercises[0].sets[0].status);
    try std.testing.expectEqual(@as(usize, 0), reopened.exercises[0].sets[0].actual_metrics.len);

    const skipped = (try tracking.skipSet(.{ .workouts = &.{reopened} }, .{
        .metadata = metadata("skip-set"),
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = 4,
        .membership_id = membership.id,
        .set_id = .{ .bytes = "set-1" },
        .skipped_at = .{ .bytes = "2026-07-26T12:03:00Z" },
    }, &exercise_b, &sets_b, &issues)).accepted.workout;
    try std.testing.expectEqual(tracking.SetStatus.skipped, skipped.exercises[0].sets[0].status);

    try expectRejectedCode(try tracking.completeSet(.{ .workouts = &.{skipped} }, .{
        .metadata = metadata("invalid-complete"),
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = 5,
        .membership_id = membership.id,
        .set_id = .{ .bytes = "set-1" },
        .actual_metrics = &.{repetitions},
        .completed_at = .{ .bytes = "2026-07-26T12:04:00Z" },
    }, &exercise_a, &sets_a, &issues), tracking.issue_codes.invalid_set_transition);
    try std.testing.expectEqual(tracking.SetStatus.skipped, skipped.exercises[0].sets[0].status);
}

test "sets reorder and remove only by semantic identity" {
    const sets = [_]tracking.TrackedSet{
        .{ .id = .{ .bytes = "set-1" }, .kind = .{ .bytes = "working" } },
        .{ .id = .{ .bytes = "set-2" }, .kind = .{ .bytes = "working" } },
    };
    const membership: tracking.ExerciseMembership = .{
        .id = .{ .bytes = "membership-1" },
        .exercise_id = .{ .bytes = "bench" },
        .sets = &sets,
    };
    const workout: tracking.Workout = .{
        .id = command.workout_id,
        .scope = scope,
        .revision = 1,
        .status = .active,
        .started_at = command.started_at,
        .exercises = &.{membership},
    };
    var issues: [1]tracking.Issue = undefined;
    var exercises_a: [1]tracking.ExerciseMembership = undefined;
    var exercises_b: [1]tracking.ExerciseMembership = undefined;
    var sets_a: [2]tracking.TrackedSet = undefined;
    var sets_b: [2]tracking.TrackedSet = undefined;
    const reordered = (try tracking.reorderSet(.{ .workouts = &.{workout} }, .{
        .metadata = metadata("reorder-set"),
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = 1,
        .membership_id = membership.id,
        .set_id = .{ .bytes = "set-2" },
        .anchor = .beginning,
    }, &exercises_a, &sets_a, &issues)).accepted.workout;
    try std.testing.expectEqualStrings("set-2", reordered.exercises[0].sets[0].id.bytes);
    const removed = (try tracking.removeSet(.{ .workouts = &.{reordered} }, .{
        .metadata = metadata("remove-set"),
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = 2,
        .membership_id = membership.id,
        .set_id = .{ .bytes = "set-1" },
    }, &exercises_b, &sets_b, &issues)).accepted.workout;
    try std.testing.expectEqual(@as(usize, 1), removed.exercises[0].sets.len);
    try std.testing.expectEqualStrings("set-2", removed.exercises[0].sets[0].id.bytes);
}

fn metadata(command_id: []const u8) tracking.CommandMetadata {
    return .{
        .command_id = .{ .bytes = command_id },
        .occurred_at = .{ .bytes = "2026-07-26T12:01:00Z" },
    };
}

fn addCommand(
    command_id: []const u8,
    revision: u64,
    membership_id: []const u8,
    exercise_id: []const u8,
    anchor: tracking.ExerciseAnchor,
) tracking.AddExerciseCommand {
    return .{
        .metadata = metadata(command_id),
        .scope = scope,
        .workout_id = command.workout_id,
        .expected_revision = revision,
        .membership_id = .{ .bytes = membership_id },
        .exercise_id = .{ .bytes = exercise_id },
        .anchor = anchor,
    };
}

fn expectOrder(workout: tracking.Workout, expected: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, workout.exercises.len);
    for (expected, workout.exercises) |id, membership| {
        try std.testing.expectEqualStrings(id, membership.id.bytes);
    }
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

fn expectCatalogRejected(result: tracking.CatalogCommandResult, code: []const u8) !void {
    switch (result) {
        .accepted => return error.UnexpectedAcceptance,
        .rejected => |rejected| try std.testing.expectEqualStrings(code, rejected.issues[0].code),
    }
}
