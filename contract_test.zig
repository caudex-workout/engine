const std = @import("std");
const caudex = @import("caudex");
const canonical = caudex.canonical;
const diagnostics = caudex.diagnostics;
const engine = caudex.engine;

const ConformanceSet = struct {
    status: caudex.training.SetStatus,
    load: canonical.Measurement,
    repetitions: u16,
    targetRepetitions: u16,
};

const ConformanceError = enum {
    incompatible_unit,
};

const ConformanceExpected = struct {
    decision: ?caudex.double_progression.RecommendationDecision = null,
    load: ?[]const u8 = null,
    repetitions: ?u16 = null,
    workingSets: ?u16 = null,
    explanationCode: ?[]const u8 = null,
    sessionExplanationCode: ?[]const u8 = null,
    warningCode: ?[]const u8 = null,
    @"error": ?ConformanceError = null,
};

const ConformanceCase = struct {
    name: []const u8,
    exerciseId: []const u8,
    state: ?caudex.double_progression.ExerciseState = null,
    sets: []const ConformanceSet,
    maxWorkingSets: ?u16 = null,
    expected: ConformanceExpected,
};

const ConformanceSuite = struct {
    config: caudex.double_progression.Config,
    cases: []const ConformanceCase,
};

test "canonical request fixtures decode" {
    inline for (.{
        .{ canonical.RecommendationRequest, @embedFile("fixtures/requests/recommendation.json") },
        .{ canonical.EvaluationRequest, @embedFile("fixtures/requests/evaluation.json") },
    }) |fixture| {
        const parsed = try std.json.parseFromSlice(
            fixture[0],
            std.testing.allocator,
            fixture[1],
            .{},
        );
        defer parsed.deinit();

        try std.testing.expectEqual(@as(u32, 1), parsed.value.schemaVersion);
    }
}

test "canonical schemas are valid JSON documents" {
    inline for (.{
        @embedFile("schemas/v0/canonical.schema.json"),
        @embedFile("schemas/v0/recommendation-request.schema.json"),
        @embedFile("schemas/v0/evaluation-request.schema.json"),
        @embedFile("schemas/v0/recommendation-result.schema.json"),
        @embedFile("schemas/v0/evaluation-result.schema.json"),
    }) |schema| {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            std.testing.allocator,
            schema,
            .{},
        );
        defer parsed.deinit();

        try std.testing.expect(parsed.value == .object);
    }
}

test "double-progression config and state fixtures decode" {
    inline for (.{
        .{
            caudex.double_progression.Config,
            @embedFile("fixtures/methodologies/double-progression-config-v1.json"),
        },
        .{
            caudex.double_progression.State,
            @embedFile("fixtures/methodologies/double-progression-state-v1.json"),
        },
    }) |fixture| {
        const parsed = try std.json.parseFromSlice(
            fixture[0],
            std.testing.allocator,
            fixture[1],
            .{},
        );
        defer parsed.deinit();
    }
}

test "double-progression schemas are valid JSON documents" {
    inline for (.{
        @embedFile("schemas/methodologies/double-progression-config-v1.schema.json"),
        @embedFile("schemas/methodologies/double-progression-state-v1.schema.json"),
    }) |schema| {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            std.testing.allocator,
            schema,
            .{},
        );
        defer parsed.deinit();
        try std.testing.expect(parsed.value == .object);
    }
}

test "double-progression state fixture round-trips" {
    const parsed = try std.json.parseFromSlice(
        caudex.double_progression.State,
        std.testing.allocator,
        @embedFile("fixtures/methodologies/double-progression-state-v1.json"),
        .{},
    );
    defer parsed.deinit();
    var encoded_buffer: [1024]u8 = undefined;
    const encoded = try caudex.double_progression.writeStateJson(
        parsed.value,
        &encoded_buffer,
    );
    const reparsed = try std.json.parseFromSlice(
        caudex.double_progression.State,
        std.testing.allocator,
        encoded,
        .{},
    );
    defer reparsed.deinit();

    try std.testing.expectEqual(
        parsed.value.schemaVersion,
        reparsed.value.schemaVersion,
    );
    try std.testing.expectEqualStrings(
        parsed.value.data.exercises[0].load.amount,
        reparsed.value.data.exercises[0].load.amount,
    );
    try std.testing.expectEqual(
        parsed.value.data.exercises[0].targetRepetitions,
        reparsed.value.data.exercises[0].targetRepetitions,
    );
}

test "double-progression conformance fixtures" {
    const parsed = try std.json.parseFromSlice(
        ConformanceSuite,
        std.testing.allocator,
        @embedFile("fixtures/methodologies/double-progression-conformance-v1.json"),
        .{},
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 10), parsed.value.cases.len);

    for (parsed.value.cases) |case| {
        const exercise_id = try caudex.primitives.Id.parse(case.exerciseId);
        const load_id = try caudex.primitives.Id.parse("load");
        const repetitions_id = try caudex.primitives.Id.parse("repetitions");
        const working_id = try caudex.primitives.Id.parse("working");
        var actual_metrics: [128]caudex.training.Metric = undefined;
        var target_metrics: [64]caudex.training.Metric = undefined;
        var sets: [64]caudex.training.CompletedSet = undefined;
        try std.testing.expect(case.sets.len <= sets.len);

        for (case.sets, 0..) |fixture_set, set_index| {
            actual_metrics[set_index * 2] = .{
                .code = load_id,
                .value = .{
                    .value = try caudex.primitives.Decimal.parse(fixture_set.load.amount),
                    .unit = try caudex.primitives.Unit.parse(fixture_set.load.unit),
                },
            };
            actual_metrics[set_index * 2 + 1] = .{
                .code = repetitions_id,
                .value = .{
                    .value = .{ .mantissa = fixture_set.repetitions, .scale = 0 },
                    .unit = .count,
                },
            };
            target_metrics[set_index] = .{
                .code = repetitions_id,
                .value = .{
                    .value = .{ .mantissa = fixture_set.targetRepetitions, .scale = 0 },
                    .unit = .count,
                },
            };
            sets[set_index] = .{
                .kind = working_id,
                .actual_metrics = actual_metrics[set_index * 2 .. set_index * 2 + 2],
                .target_metrics = target_metrics[set_index .. set_index + 1],
                .status = fixture_set.status,
            };
        }
        const completed_exercises = [_]caudex.training.CompletedExercise{.{
            .exercise_id = exercise_id,
            .sets = sets[0..case.sets.len],
        }};
        const workouts = [_]caudex.training.CompletedWorkout{.{
            .id = try .parse("fixture-workout"),
            .started_at = try .parse("2026-07-25T14:00:00Z"),
            .completed_at = try .parse("2026-07-25T15:00:00Z"),
            .exercises = &completed_exercises,
        }};
        const history: caudex.training.HistorySnapshot = if (case.sets.len == 0)
            .{}
        else
            .{ .workouts = &workouts };
        var state_storage: [1]caudex.double_progression.ExerciseState = undefined;
        const state: ?caudex.double_progression.State = if (case.state) |state_entry| blk: {
            state_storage[0] = state_entry;
            break :blk .{
                .schemaVersion = 1,
                .data = .{ .exercises = &state_storage },
            };
        } else null;

        const actual = caudex.double_progression.recommendExerciseWithConstraints(
            parsed.value.config,
            state,
            history,
            exercise_id,
            .{ .max_working_sets = case.maxWorkingSets },
        );
        if (case.expected.@"error") |expected_error| {
            if (actual) |_| {
                return error.ExpectedConformanceError;
            } else |actual_error| {
                switch (expected_error) {
                    .incompatible_unit => try std.testing.expectEqual(
                        error.IncompatibleUnit,
                        actual_error,
                    ),
                }
            }
            continue;
        }

        const recommendation = try actual;
        try std.testing.expectEqual(case.expected.decision.?, recommendation.decision);
        var load_buffer: [32]u8 = undefined;
        try std.testing.expectEqualStrings(
            case.expected.load.?,
            try recommendation.load.value.format(&load_buffer),
        );
        try std.testing.expectEqual(case.expected.repetitions.?, recommendation.repetitions);
        try std.testing.expectEqual(case.expected.workingSets.?, recommendation.working_sets);
        try std.testing.expectEqualStrings(
            case.expected.explanationCode.?,
            recommendation.explanation.code,
        );
        if (case.expected.sessionExplanationCode) |expected_code| {
            try std.testing.expectEqualStrings(
                expected_code,
                recommendation.session_explanation.?.code,
            );
        } else {
            try std.testing.expect(recommendation.session_explanation == null);
        }
        if (case.expected.warningCode) |expected_code| {
            try std.testing.expectEqualStrings(expected_code, recommendation.warning.?.code);
        } else {
            try std.testing.expect(recommendation.warning == null);
        }
    }
}

test "measurement rejects a JSON number at the decimal boundary" {
    const invalid = "{\"amount\":72.5,\"unit\":\"lb\"}";
    try std.testing.expectError(
        error.UnexpectedToken,
        std.json.parseFromSlice(
            canonical.Measurement,
            std.testing.allocator,
            invalid,
            .{},
        ),
    );
}

test "issue convention fields decode" {
    const json =
        \\{
        \\  "code": "history.exercise_reference_missing",
        \\  "path": "/history/workouts/2/exercises/0/exerciseId",
        \\  "message": "The completed exercise is absent from the catalog.",
        \\  "severity": "error",
        \\  "parameters": { "exerciseId": "incline-dumbbell-press" },
        \\  "suggestion": "Include the referenced exercise in the catalog."
        \\}
    ;
    const parsed = try std.json.parseFromSlice(
        canonical.ValidationIssue,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    try std.testing.expectEqual(canonical.Severity.@"error", parsed.value.severity);
    try std.testing.expectEqualStrings(
        "/history/workouts/2/exercises/0/exerciseId",
        parsed.value.path,
    );
}

test "explanation supports deterministic derived evidence" {
    const json =
        \\{
        \\  "id": "explanation-1",
        \\  "code": "progression.held.insufficient_evidence",
        \\  "category": "progression",
        \\  "summary": "Progression was held because evidence was insufficient.",
        \\  "evidence": [
        \\    { "path": "/@derived/history/lastCompletedExercise" }
        \\  ],
        \\  "severity": "warning"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(
        canonical.Explanation,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.value.evidence.len);
    try std.testing.expectEqualStrings(
        "/@derived/history/lastCompletedExercise",
        parsed.value.evidence[0].path,
    );
}

test "diagnostic bundle matches the stable canonical fixture" {
    var issue_storage: [1]canonical.ValidationIssue = undefined;
    var issue_writer: diagnostics.IssueWriter = .init(&issue_storage);
    try issue_writer.append(.{
        .code = "history.exercise_reference_missing",
        .path = "/history/workouts/0/exercises/0/exerciseId",
        .message = "The completed exercise is absent from the catalog.",
        .severity = .@"error",
    });

    const evidence = [_]canonical.EvidenceRef{
        .{ .path = "/session/availableEquipmentIds" },
    };
    var explanation_storage: [1]canonical.Explanation = undefined;
    var explanation_writer: diagnostics.ExplanationWriter = .init(&explanation_storage);
    try explanation_writer.append(.{
        .id = "explanation-1",
        .code = "exercise.selected.available_equipment",
        .category = "selection",
        .summary = "Available equipment supported the exercise selection.",
        .evidence = &evidence,
        .severity = .info,
    });

    const bundle = diagnostics.DiagnosticBundle{
        .issues = issue_writer.items(),
        .explanations = explanation_writer.items(),
    };
    var json_buffer: [1024]u8 = undefined;
    const actual = try bundle.writeJson(&json_buffer);
    const expected = std.mem.trimEnd(
        u8,
        @embedFile("fixtures/results/diagnostics.json"),
        "\n",
    );
    try std.testing.expectEqualStrings(expected, actual);
}

test "deterministic recommendation matches the golden canonical fixture" {
    const equipment = [_]caudex.primitives.Id{
        try .parse("dumbbell"),
        try .parse("adjustable-bench"),
    };
    const exercises = [_]caudex.training.Exercise{.{
        .id = try .parse("incline-dumbbell-press"),
        .equipment_ids = &equipment,
    }};
    const request = engine.RecommendationRequest{
        .as_of = try .parse("2026-07-25T14:00:00Z"),
        .methodology_id = try .parse("caudex.double-progression"),
        .methodology_version = .{ .major = 0, .minor = 1, .patch = 0 },
        .config = .{
            .repRange = .{ .min = 8, .max = 12 },
            .workingSets = 1,
            .advancementCriteria = .{
                .minimumSuccessfulSets = 1,
                .minimumRepetitions = 12,
            },
            .initialLoad = .{ .amount = "45", .unit = "lb" },
            .loadIncrement = .{ .amount = "5", .unit = "lb" },
            .failurePolicy = .{
                .onPartial = .hold,
                .onFailure = .regress,
                .regressionAmount = .{ .amount = "5", .unit = "lb" },
            },
            .rounding = .{
                .mode = .nearest,
                .quantum = .{ .amount = "2.5", .unit = "lb" },
            },
        },
        .catalog = .{ .exercises = &exercises },
        .available_equipment_ids = &equipment,
    };
    var output: engine.Output = .{};
    const result = try engine.recommendSession(request, &output);
    var json_buffer: [2048]u8 = undefined;
    const actual = try engine.writeResultJson(result, &json_buffer);
    const expected = std.mem.trimEnd(
        u8,
        @embedFile("fixtures/results/recommendation-no-history.json"),
        "\n",
    );

    try std.testing.expectEqualStrings(expected, actual);
}
