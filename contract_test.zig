const std = @import("std");
const canonical = @import("caudex").canonical;

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
