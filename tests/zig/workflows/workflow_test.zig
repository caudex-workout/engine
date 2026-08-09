const std = @import("std");
const caudex = @import("caudex");
const tracking = @import("caudex_tracking");
const workflows = @import("caudex_workflows");
const assets = @import("repository_test_assets");

const timestamp: tracking.Timestamp = .{ .bytes = "2026-08-04T12:00:00Z" };
const scope: tracking.Scope = .{ .host_scope_key = .{ .bytes = "scope-1" } };
const catalog = [_]caudex.canonical.Exercise{.{ .id = "squat" }};

fn storage(exercises: []tracking.ExerciseMembership, sets: []tracking.TrackedSet, prescribed_exercises: []tracking.PrescribedExercise, prescribed_sets: []tracking.PrescribedSet, metrics: []tracking.Metric) workflows.InstantiationStorage {
    return .{ .exercises = exercises, .sets = sets, .prescription_exercises = prescribed_exercises, .prescription_sets = prescribed_sets, .metrics = metrics };
}

test "recommendation instantiation preserves provenance and original prescription" {
    const result: caudex.canonical.RecommendationResult = .{
        .ok = true,
        .recommendation = .{ .exercises = &.{.{
            .exerciseId = "squat",
            .sets = &.{.{ .kind = "working", .targetMetrics = &.{.{ .code = "load", .value = .{ .amount = "185.00", .unit = "lb" } }} }},
        }} },
        .metadata = .{
            .engineVersion = "0.1.0",
            .schemaVersion = 1,
            .methodology = .{ .id = "caudex.double-progression", .version = "1.0.0", .configVersion = 1 },
            .inputFingerprint = "input-fingerprint",
            .resultFingerprint = "result-fingerprint",
        },
    };
    var exercises: [1]tracking.ExerciseMembership = undefined;
    var sets: [1]tracking.TrackedSet = undefined;
    var prescribed_exercises: [1]tracking.PrescribedExercise = undefined;
    var prescribed_sets: [1]tracking.PrescribedSet = undefined;
    var metrics: [1]tracking.Metric = undefined;
    var issues: [1]tracking.Issue = undefined;
    const instantiated = try workflows.instantiateRecommendation(result, &catalog, .{
        .scope = scope,
        .ids = .{ .workout_id = .{ .bytes = "workout-1" }, .membership_ids = &.{.{ .bytes = "membership-1" }}, .set_ids = &.{.{ .bytes = "set-1" }} },
        .created_at = timestamp,
        .accepted_recommendation_id = .{ .bytes = "accepted-1" },
        .methodology_state_revision = "state-revision-4",
    }, storage(&exercises, &sets, &prescribed_exercises, &prescribed_sets, &metrics), &issues);
    const workout = instantiated.accepted;
    try std.testing.expectEqual(tracking.WorkoutOrigin.recommendation, workout.origin);
    try std.testing.expectEqualStrings("result-fingerprint", workout.provenance.?.recommendation.result_fingerprint);
    try std.testing.expectEqual(@as(i64, 18500), workout.prescription[0].sets[0].target_metrics[0].value.value.mantissa);

    var next_exercises: [1]tracking.ExerciseMembership = undefined;
    var next_sets: [1]tracking.TrackedSet = undefined;
    const removed = try tracking.removeSet(.{ .workouts = &.{workout} }, .{
        .metadata = .{ .command_id = .{ .bytes = "remove-set-1" }, .occurred_at = timestamp },
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = workout.revision,
        .membership_id = workout.exercises[0].id,
        .set_id = workout.exercises[0].sets[0].id,
    }, &next_exercises, &next_sets, &issues);
    try std.testing.expectEqual(@as(usize, 0), removed.accepted.workout.exercises[0].sets.len);
    try std.testing.expectEqual(@as(usize, 1), removed.accepted.workout.prescription[0].sets.len);
    var modifications: [4]workflows.Modification = undefined;
    const changes = try workflows.collectModifications(removed.accepted.workout, &modifications);
    try std.testing.expectEqual(workflows.ModificationKind.set_removed, changes[0].kind);
}

test "evaluation state remains an explicit compare-and-set proposal" {
    const evaluation: caudex.canonical.EvaluationResult = .{
        .ok = true,
        .evaluation = .{ .outcome = "advanced", .exercises = &.{} },
        .nextMethodologyState = .{ .schemaVersion = 1, .data = .null },
        .metadata = .{
            .engineVersion = "0.1.0",
            .schemaVersion = 1,
            .methodology = .{ .id = "caudex.double-progression", .version = "1.0.0", .configVersion = 1 },
            .inputFingerprint = "evaluation-input",
            .resultFingerprint = "evaluation-result",
        },
    };
    var issues: [1]tracking.Issue = undefined;
    const proposal = try workflows.proposeStateAcceptance(evaluation, "state-revision-4", timestamp, &issues);
    try std.testing.expectEqualStrings("state-revision-4", proposal.accepted.expected_revision.?);
    try std.testing.expectEqualStrings("evaluation-result", proposal.accepted.evaluation_fingerprint);
    try std.testing.expectEqual(@as(u32, 1), proposal.accepted.next_state.schemaVersion);
}

test "template instantiation remains distinct from recommendation state" {
    const template: workflows.WorkoutTemplate = .{
        .id = .{ .bytes = "template-1" },
        .display_name = "Squat day",
        .exercises = &.{.{ .exercise_id = .{ .bytes = "squat" }, .sets = &.{.{}} }},
        .revision = 7,
    };
    var exercises: [1]tracking.ExerciseMembership = undefined;
    var sets: [1]tracking.TrackedSet = undefined;
    var prescribed_exercises: [1]tracking.PrescribedExercise = undefined;
    var prescribed_sets: [1]tracking.PrescribedSet = undefined;
    var metrics: [1]tracking.Metric = undefined;
    var issues: [1]tracking.Issue = undefined;
    const instantiated = try workflows.instantiateTemplate(template, &catalog, .{
        .scope = scope,
        .ids = .{ .workout_id = .{ .bytes = "workout-template-1" }, .membership_ids = &.{.{ .bytes = "membership-template-1" }}, .set_ids = &.{.{ .bytes = "set-template-1" }} },
        .created_at = timestamp,
    }, storage(&exercises, &sets, &prescribed_exercises, &prescribed_sets, &metrics), &issues);
    try std.testing.expectEqual(tracking.WorkoutOrigin.template, instantiated.accepted.origin);
    try std.testing.expectEqual(@as(u64, 7), instantiated.accepted.provenance.?.template.template_revision);
}

test "template canonical document round trips exact values" {
    const parsed = try workflows.decodeTemplateDocument(
        std.testing.allocator,
        assets.squat_day,
        .{},
    );
    defer parsed.deinit();
    var exercises: [1]workflows.TemplateExercise = undefined;
    var sets: [1]workflows.TemplateSet = undefined;
    var metrics: [1]tracking.Metric = undefined;
    var tags: [2]tracking.Id = undefined;
    const template = try workflows.templateToDomain(parsed.value, .{ .exercises = &exercises, .sets = &sets, .metrics = &metrics, .tags = &tags });
    try std.testing.expectEqual(@as(i64, 8), template.exercises[0].sets[0].target_metrics[0].value.value.mantissa);
    var wire_exercises: [1]workflows.TemplateExerciseDocument = undefined;
    var wire_sets: [1]workflows.TemplateSetDocument = undefined;
    var wire_metrics: [1]caudex.canonical.Metric = undefined;
    var amounts: [1][64]u8 = undefined;
    var wire_tags: [2][]const u8 = undefined;
    const document = try workflows.templateFromDomain(template, .{ .exercises = &wire_exercises, .sets = &wire_sets, .metrics = &wire_metrics, .amount_bytes = &amounts, .tags = &wire_tags });
    var encoded: [4096]u8 = undefined;
    try std.testing.expectEqualStrings(std.mem.trimEnd(u8, assets.squat_day, "\r\n"), try workflows.encodeTemplateDocument(document, &encoded));
}

test "completed tracked workout converts to canonical evaluation input without changing prescription" {
    const target: tracking.Metric = .{
        .code = .{ .bytes = "repetitions" },
        .value = .{ .value = .{ .mantissa = 8, .scale = 0 }, .unit = .count },
    };
    const actual: tracking.Metric = .{
        .code = .{ .bytes = "repetitions" },
        .value = .{ .value = .{ .mantissa = 7, .scale = 0 }, .unit = .count },
    };
    const prescribed_set: tracking.PrescribedSet = .{ .set_id = .{ .bytes = "set-1" }, .kind = .{ .bytes = "working" }, .target_metrics = &.{target} };
    const prescription: tracking.PrescribedExercise = .{ .membership_id = .{ .bytes = "membership-1" }, .exercise_id = .{ .bytes = "squat" }, .sets = &.{prescribed_set} };
    const executed_set: tracking.TrackedSet = .{
        .id = prescribed_set.set_id,
        .kind = prescribed_set.kind,
        .target_metrics = prescribed_set.target_metrics,
        .actual_metrics = &.{actual},
        .status = .completed,
        .recorded_at = .{ .bytes = "2026-08-04T12:10:00Z" },
    };
    const workout: tracking.Workout = .{
        .id = .{ .bytes = "workout-1" },
        .scope = scope,
        .revision = 2,
        .status = .completed,
        .started_at = timestamp,
        .completed_at = .{ .bytes = "2026-08-04T12:10:00Z" },
        .exercises = &.{.{ .id = prescription.membership_id, .exercise_id = prescription.exercise_id, .sets = &.{executed_set} }},
        .origin = .recommendation,
        .provenance = .{ .recommendation = .{
            .accepted_recommendation_id = .{ .bytes = "accepted-1" },
            .input_fingerprint = "input",
            .result_fingerprint = "result",
            .methodology_id = .{ .bytes = "caudex.double-progression" },
            .methodology_version = "1.0.0",
            .methodology_config_version = 1,
        } },
        .prescription = &.{prescription},
    };
    var exercises: [1]caudex.canonical.CompletedExercise = undefined;
    var sets: [1]caudex.canonical.CompletedSet = undefined;
    var metrics: [2]caudex.canonical.Metric = undefined;
    var amounts: [2][64]u8 = undefined;
    var tags: [1][]const u8 = undefined;
    var issues: [1]tracking.Issue = undefined;
    const converted = try workflows.completeForEvaluation(workout, &catalog, .{
        .exercises = &exercises,
        .sets = &sets,
        .metrics = &metrics,
        .amount_bytes = &amounts,
        .tags = &tags,
    }, &issues);
    try std.testing.expectEqualStrings("7", converted.accepted.exercises[0].sets[0].actualMetrics[0].value.amount);
    try std.testing.expectEqualStrings("8", converted.accepted.exercises[0].sets[0].targetMetrics[0].value.amount);
    try std.testing.expectEqual(@as(i64, 8), workout.prescription[0].sets[0].target_metrics[0].value.value.mantissa);
}

test "completion conversion rejects open sets with structured issue" {
    const workout: tracking.Workout = .{
        .id = .{ .bytes = "workout-1" },
        .scope = scope,
        .revision = 2,
        .status = .completed,
        .started_at = timestamp,
        .completed_at = .{ .bytes = "2026-08-04T12:10:00Z" },
        .exercises = &.{.{ .id = .{ .bytes = "membership-1" }, .exercise_id = .{ .bytes = "squat" }, .sets = &.{.{ .id = .{ .bytes = "set-1" }, .kind = .{ .bytes = "working" } }} }},
    };
    var exercises: [1]caudex.canonical.CompletedExercise = undefined;
    var sets: [1]caudex.canonical.CompletedSet = undefined;
    var metrics: [1]caudex.canonical.Metric = undefined;
    var amounts: [1][64]u8 = undefined;
    var tags: [1][]const u8 = undefined;
    var issues: [1]tracking.Issue = undefined;
    const converted = try workflows.completeForEvaluation(workout, &catalog, .{ .exercises = &exercises, .sets = &sets, .metrics = &metrics, .amount_bytes = &amounts, .tags = &tags }, &issues);
    try std.testing.expectEqualStrings(workflows.issue_codes.actual_value_required, converted.rejected[0].code);
}
