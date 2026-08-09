const std = @import("std");
const protocol = @import("caudex_tracking_protocol");
const tracking = @import("caudex_tracking");
const assets = @import("repository_test_assets");

test "tracking fixture decodes and re-encodes deterministically" {
    const fixture = assets.tracking_start;
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

test "standalone tracking snapshot is versioned bounded and deterministic" {
    const fixture = assets.tracking_snapshot;
    const parsed = try protocol.decodeSnapshotDocument(std.testing.allocator, fixture, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, protocol.schema_version), parsed.value.schemaVersion);
    try std.testing.expectEqual(@as(usize, 0), parsed.value.snapshot.workouts.len);

    var output: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        std.mem.trimEnd(u8, fixture, "\r\n"),
        try protocol.encode(parsed.value, &output),
    );

    const unsupported =
        \\{"schemaVersion":2,"snapshot":{"workouts":[],"startReceipts":[]}}
    ;
    try std.testing.expectError(
        error.UnsupportedVersion,
        protocol.decodeSnapshotDocument(std.testing.allocator, unsupported, .{}),
    );
    try std.testing.expectError(
        error.InputTooLarge,
        protocol.decodeSnapshotDocument(std.testing.allocator, fixture, .{ .json = .{ .max_input_bytes = 1 } }),
    );
}

test "versions batches and transport failures are distinct" {
    const unsupported =
        \\{"schemaVersion":2,"snapshot":{"workouts":[]},"command":{"startWorkout":{"metadata":{"commandId":"c","occurredAt":"2026-08-04T12:00:00Z"},"scope":{"hostScopeKey":"s"},"workoutId":"w","startedAt":"2026-08-04T12:00:00Z"}}}
    ;
    try std.testing.expectError(error.UnsupportedVersion, protocol.decodeCommandRequest(std.testing.allocator, unsupported, .{}));
    try std.testing.expectError(error.MalformedJson, protocol.decodeCommandRequest(std.testing.allocator, "{", .{}));
    const unknown_operation =
        \\{"schemaVersion":1,"snapshot":{"workouts":[]},"command":{"teleportWorkout":{}}}
    ;
    try std.testing.expectError(
        error.MalformedJson,
        protocol.decodeCommandRequest(std.testing.allocator, unknown_operation, .{}),
    );
    const empty_batch =
        \\{"schemaVersion":1,"snapshot":{"workouts":[]},"commands":[]}
    ;
    try std.testing.expectError(error.EmptyBatch, protocol.decodeAtomicBatchRequest(std.testing.allocator, empty_batch, .{}));
}

test "canonical rejected result fixture has stable bytes" {
    const fixture = assets.tracking_rejected_batch;
    const parsed = try protocol.decodeAtomicBatchResult(std.testing.allocator, fixture, .{});
    defer parsed.deinit();
    var storage: [4096]u8 = undefined;
    try std.testing.expectEqualStrings(
        std.mem.trimEnd(u8, fixture, "\r\n"),
        try protocol.encode(parsed.value, &storage),
    );
}

test "start command conversion validates and preserves typed values" {
    const parsed = try protocol.decodeCommandRequest(
        std.testing.allocator,
        assets.tracking_start,
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

test "command metric collections are bounded during canonical decoding" {
    var metrics: [protocol.max_metrics_per_set + 1]@import("caudex").canonical.Metric = undefined;
    for (&metrics) |*metric| metric.* = .{
        .code = "repetitions",
        .value = .{ .amount = "8", .unit = "count" },
    };
    const request: protocol.CommandRequest = .{
        .schemaVersion = protocol.schema_version,
        .snapshot = .{},
        .command = .{ .completeSet = .{
            .metadata = .{ .commandId = "complete-set-1", .occurredAt = "2026-08-04T12:01:00Z" },
            .scope = .{ .hostScopeKey = "scope-1" },
            .workoutId = "workout-1",
            .expectedRevision = 1,
            .membershipId = "membership-1",
            .setId = "set-1",
            .actualMetrics = &metrics,
            .completedAt = "2026-08-04T12:01:00Z",
        } },
    };
    var json: [16 * 1024]u8 = undefined;
    const encoded = try protocol.encode(request, &json);
    try std.testing.expectError(
        error.SnapshotLimitExceeded,
        protocol.decodeCommandRequest(std.testing.allocator, encoded, .{}),
    );

    const batch: protocol.AtomicBatchRequest = .{
        .schemaVersion = protocol.schema_version,
        .snapshot = .{},
        .commands = &.{request.command},
    };
    const encoded_batch = try protocol.encode(batch, &json);
    try std.testing.expectError(
        error.SnapshotLimitExceeded,
        protocol.decodeAtomicBatchRequest(std.testing.allocator, encoded_batch, .{}),
    );
}

test "snapshot bounds include replay workouts and prescription tags" {
    var too_many_sets: [protocol.max_sets_per_exercise + 1]protocol.TrackedSet = undefined;
    for (&too_many_sets, 0..) |*set, index| {
        set.* = .{
            .id = if (index == 0) "set-1" else "set-n",
            .kind = "working",
        };
    }
    const receipt_workout: protocol.TrackedWorkout = .{
        .id = "workout-1",
        .scope = .{ .hostScopeKey = "scope-1" },
        .revision = 1,
        .status = .active,
        .startedAt = "2026-08-04T12:00:00Z",
        .exercises = &.{.{
            .id = "membership-1",
            .exerciseId = "squat",
            .sets = &too_many_sets,
        }},
    };
    const start: protocol.StartWorkout = .{
        .metadata = .{ .commandId = "start-1", .occurredAt = "2026-08-04T12:00:00Z" },
        .scope = receipt_workout.scope,
        .workoutId = receipt_workout.id,
        .startedAt = receipt_workout.startedAt,
    };
    var receipt_json: [256 * 1024]u8 = undefined;
    const receipt_document: protocol.SnapshotDocument = .{
        .schemaVersion = protocol.schema_version,
        .snapshot = .{ .startReceipts = &.{.{
            .command = start,
            .disposition = .applied,
            .workout = receipt_workout,
        }} },
    };
    const encoded_receipt = try protocol.encode(receipt_document, &receipt_json);
    try std.testing.expectError(
        error.SnapshotLimitExceeded,
        protocol.decodeSnapshotDocument(std.testing.allocator, encoded_receipt, .{}),
    );

    var too_many_tags: [protocol.max_tags_per_exercise + 1][]const u8 = undefined;
    @memset(&too_many_tags, "tag");
    const tagged_workout: protocol.TrackedWorkout = .{
        .id = "workout-2",
        .scope = .{ .hostScopeKey = "scope-1" },
        .revision = 1,
        .status = .active,
        .startedAt = "2026-08-04T12:00:00Z",
        .prescription = &.{.{
            .membershipId = "membership-1",
            .exerciseId = "squat",
            .tags = &too_many_tags,
        }},
    };
    var tag_json: [16 * 1024]u8 = undefined;
    const tag_document: protocol.SnapshotDocument = .{
        .schemaVersion = protocol.schema_version,
        .snapshot = .{ .workouts = &.{tagged_workout} },
    };
    const encoded_tags = try protocol.encode(tag_document, &tag_json);
    try std.testing.expectError(
        error.SnapshotLimitExceeded,
        protocol.decodeSnapshotDocument(std.testing.allocator, encoded_tags, .{}),
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
    var wire_metrics: [1]@import("caudex").canonical.Metric = undefined;
    var amounts: [1][64]u8 = undefined;
    const round_trip = try protocol.commandFromDomain(typed, .{ .metrics = &wire_metrics, .amountBytes = &amounts });
    try std.testing.expectEqualStrings("185.00", round_trip.addSet.targetMetrics[0].value.amount);
    try std.testing.expectEqual(protocol.Anchor.end, round_trip.addSet.anchor);
    var encoded_storage: [1024]u8 = undefined;
    const encoded = try protocol.encode(round_trip, &encoded_storage);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\"anchor\":{\"end\":{}}") != null);
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
        .origin = .recommendation,
        .provenance = .{ .recommendation = .{
            .acceptedRecommendationId = "accepted-1",
            .inputFingerprint = "input-fingerprint",
            .resultFingerprint = "result-fingerprint",
            .methodologyId = "caudex.double-progression",
            .methodologyVersion = "1.0.0",
            .methodologyConfigVersion = 1,
            .methodologyStateRevision = "state-4",
        } },
        .prescription = &.{.{
            .membershipId = "membership-1",
            .exerciseId = "squat",
            .sets = &.{.{ .setId = "set-1", .kind = "working", .targetMetrics = &.{.{ .code = "load", .value = .{ .amount = "185.00", .unit = "lb" } }} }},
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
        .exerciseCatalog = &.{.{ .exerciseId = "squat", .availability = .active }},
    };
    var workouts: [1]tracking.Workout = undefined;
    var receipts: [1]tracking.StartReceipt = undefined;
    var exercises: [1]tracking.ExerciseMembership = undefined;
    var sets: [1]tracking.TrackedSet = undefined;
    var metrics: [2]tracking.Metric = undefined;
    var typed_prescribed_exercises: [1]tracking.PrescribedExercise = undefined;
    var typed_prescribed_sets: [1]tracking.PrescribedSet = undefined;
    var typed_tags: [1]tracking.Id = undefined;
    var typed_catalog: [1]tracking.ExerciseCatalogEntry = undefined;
    const typed = try protocol.snapshotToDomain(snapshot, .{
        .workouts = &workouts,
        .receipts = &receipts,
        .exercises = &exercises,
        .sets = &sets,
        .metrics = &metrics,
        .prescription_exercises = &typed_prescribed_exercises,
        .prescription_sets = &typed_prescribed_sets,
        .tags = &typed_tags,
        .catalog = &typed_catalog,
    });
    try std.testing.expectEqual(@as(i64, 18500), typed.workouts[0].exercises[0].sets[0].target_metrics[0].value.value.mantissa);
    try std.testing.expectEqual(tracking.CommandDisposition.applied, typed.start_receipts[0].accepted.disposition);
    try std.testing.expectEqual(tracking.WorkoutOrigin.recommendation, typed.workouts[0].origin);
    try std.testing.expectEqualStrings("result-fingerprint", typed.workouts[0].provenance.?.recommendation.result_fingerprint);
    try std.testing.expectEqual(tracking.ExerciseAvailability.active, typed.exercise_catalog[0].availability);

    var wire_workouts: [1]protocol.TrackedWorkout = undefined;
    var wire_receipts: [1]protocol.StartReceipt = undefined;
    var wire_exercises: [1]protocol.ExerciseMembership = undefined;
    var wire_sets: [1]protocol.TrackedSet = undefined;
    var wire_metrics: [2]@import("caudex").canonical.Metric = undefined;
    var amounts: [2][64]u8 = undefined;
    var wire_prescribed_exercises: [1]protocol.PrescribedExercise = undefined;
    var wire_prescribed_sets: [1]protocol.PrescribedSet = undefined;
    var wire_tags: [1][]const u8 = undefined;
    var wire_catalog: [1]protocol.ExerciseCatalogEntry = undefined;
    const round_trip = try protocol.snapshotFromDomain(typed, .{
        .workouts = &wire_workouts,
        .receipts = &wire_receipts,
        .exercises = &wire_exercises,
        .sets = &wire_sets,
        .metrics = &wire_metrics,
        .amountBytes = &amounts,
        .prescription_exercises = &wire_prescribed_exercises,
        .prescription_sets = &wire_prescribed_sets,
        .tags = &wire_tags,
        .catalog = &wire_catalog,
    });
    try std.testing.expectEqualStrings("185.00", round_trip.workouts[0].exercises[0].sets[0].targetMetrics[0].value.amount);
    try std.testing.expectEqualStrings("start-1", round_trip.startReceipts[0].command.metadata.commandId);
    try std.testing.expectEqualStrings("accepted-1", round_trip.workouts[0].provenance.?.recommendation.acceptedRecommendationId);
    try std.testing.expectEqualStrings("185.00", round_trip.workouts[0].prescription[0].sets[0].targetMetrics[0].value.amount);
    try std.testing.expectEqualStrings("squat", round_trip.exerciseCatalog[0].exerciseId);
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

    var wire_workouts: [2]protocol.TrackedWorkout = undefined;
    var wire_receipts: [2]protocol.StartReceipt = undefined;
    var wire_exercises: [8]protocol.ExerciseMembership = undefined;
    var wire_sets: [8]protocol.TrackedSet = undefined;
    var wire_metrics: [8]@import("caudex").canonical.Metric = undefined;
    var amounts: [8][64]u8 = undefined;
    var wire_prescribed_exercises: [8]protocol.PrescribedExercise = undefined;
    var wire_prescribed_sets: [8]protocol.PrescribedSet = undefined;
    var wire_tags: [8][]const u8 = undefined;
    var wire_catalog: [1]protocol.ExerciseCatalogEntry = undefined;
    var wire_outcomes: [commands.len]protocol.CommandOutcome = undefined;
    var wire_accepted: [commands.len]protocol.AcceptedCommand = undefined;
    var wire_rejected: [1]protocol.RejectedCommand = undefined;
    var wire_issues: [commands.len]protocol.Issue = undefined;
    var related_ids: [commands.len][]const u8 = undefined;
    const wire_result = try protocol.batchResultFromDomain(result, .{}, .{
        .snapshot = .{
            .workouts = &wire_workouts,
            .receipts = &wire_receipts,
            .exercises = &wire_exercises,
            .sets = &wire_sets,
            .metrics = &wire_metrics,
            .amountBytes = &amounts,
            .prescription_exercises = &wire_prescribed_exercises,
            .prescription_sets = &wire_prescribed_sets,
            .tags = &wire_tags,
            .catalog = &wire_catalog,
        },
        .outcomes = &wire_outcomes,
        .accepted = &wire_accepted,
        .rejected = &wire_rejected,
        .issues = &wire_issues,
        .relatedIds = &related_ids,
    });
    try std.testing.expect(wire_result.applied);
    try std.testing.expectEqual(@as(usize, 2), wire_result.outcomes.len);
    try std.testing.expectEqualStrings("add-exercise-1", wire_result.outcomes[1].accepted.commandId);
    try std.testing.expectEqual(@as(u64, 2), wire_result.snapshot.workouts[0].revision);
    try std.testing.expectEqualStrings("squat", wire_result.snapshot.exerciseCatalog[0].exerciseId);
    var encoded_a: [8192]u8 = undefined;
    var encoded_b: [8192]u8 = undefined;
    const encoded = try protocol.encode(wire_result, &encoded_a);
    try std.testing.expectEqualStrings(encoded, try protocol.encode(wire_result, &encoded_b));
    const decoded = try protocol.decodeAtomicBatchResult(std.testing.allocator, encoded, .{});
    defer decoded.deinit();
    try std.testing.expect(decoded.value.applied);
    try std.testing.expectEqualStrings("add-exercise-1", decoded.value.outcomes[1].accepted.commandId);
}

test "canonical rejected batch returns original snapshot and structured issue" {
    const active: tracking.Workout = .{
        .id = .{ .bytes = "workout-1" },
        .scope = .{ .host_scope_key = .{ .bytes = "scope-1" } },
        .revision = 1,
        .status = .active,
        .started_at = .{ .bytes = "2026-08-04T12:00:00Z" },
    };
    const original: tracking.LifecycleSnapshot = .{ .workouts = &.{active} };
    const commands = [_]tracking.Command{.{ .complete_workout = .{
        .metadata = .{ .command_id = .{ .bytes = "complete-1" }, .occurred_at = .{ .bytes = "2026-08-04T12:01:00Z" } },
        .scope = active.scope,
        .workout_id = active.id,
        .expected_revision = 99,
        .completed_at = .{ .bytes = "2026-08-04T12:01:00Z" },
    } }};
    var workouts: [1]tracking.Workout = undefined;
    var receipts: [1]tracking.StartReceipt = undefined;
    var exercises: [1]tracking.ExerciseMembership = undefined;
    var sets: [1]tracking.TrackedSet = undefined;
    var issues: [1]tracking.Issue = undefined;
    var outcomes: [1]tracking.AcceptedCommand = undefined;
    const result = try tracking.applyAtomicBatch(original, &commands, .{
        .workouts = &workouts,
        .start_receipts = &receipts,
        .exercises = &exercises,
        .sets = &sets,
        .issues = &issues,
        .outcomes = &outcomes,
    });
    var wire_workouts: [1]protocol.TrackedWorkout = undefined;
    var wire_receipts: [1]protocol.StartReceipt = undefined;
    var wire_exercises: [1]protocol.ExerciseMembership = undefined;
    var wire_sets: [1]protocol.TrackedSet = undefined;
    var wire_metrics: [1]@import("caudex").canonical.Metric = undefined;
    var amounts: [1][64]u8 = undefined;
    var wire_prescribed_exercises: [1]protocol.PrescribedExercise = undefined;
    var wire_prescribed_sets: [1]protocol.PrescribedSet = undefined;
    var wire_tags: [1][]const u8 = undefined;
    var wire_outcomes: [1]protocol.CommandOutcome = undefined;
    var wire_accepted: [1]protocol.AcceptedCommand = undefined;
    var wire_rejected: [1]protocol.RejectedCommand = undefined;
    var wire_issues: [1]protocol.Issue = undefined;
    var related_ids: [1][]const u8 = undefined;
    const wire_result = try protocol.batchResultFromDomain(result, original, .{
        .snapshot = .{ .workouts = &wire_workouts, .receipts = &wire_receipts, .exercises = &wire_exercises, .sets = &wire_sets, .metrics = &wire_metrics, .amountBytes = &amounts, .prescription_exercises = &wire_prescribed_exercises, .prescription_sets = &wire_prescribed_sets, .tags = &wire_tags },
        .outcomes = &wire_outcomes,
        .accepted = &wire_accepted,
        .rejected = &wire_rejected,
        .issues = &wire_issues,
        .relatedIds = &related_ids,
    });
    try std.testing.expect(!wire_result.applied);
    try std.testing.expectEqual(@as(u64, 1), wire_result.snapshot.workouts[0].revision);
    try std.testing.expectEqualStrings(tracking.issue_codes.revision_conflict, wire_result.issues[0].code);
    var encoded: [4096]u8 = undefined;
    const decoded = try protocol.decodeAtomicBatchResult(
        std.testing.allocator,
        try protocol.encode(wire_result, &encoded),
        .{},
    );
    defer decoded.deinit();
    try std.testing.expectEqualStrings(tracking.issue_codes.revision_conflict, decoded.value.outcomes[0].rejected.issues[0].code);
}
