const std = @import("std");
const caudex = @import("caudex");
const canonical = caudex.canonical;
const diagnostics = caudex.diagnostics;

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
