const std = @import("std");
const catalog = @import("caudex_exercise_catalog");

test "embedded catalog loads, searches, and projects deterministically" {
    const parsed = try catalog.load(std.testing.allocator);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 873), parsed.value.records.len);
    try std.testing.expect(!parsed.value.mediaIncluded);
    try std.testing.expectEqualStrings("1489c44273ece313784ef6322a9953bc695d368ef0415743ab988396cb195c8c", parsed.value.fingerprint);
    var results: [10]*const catalog.Record = undefined;
    const found = try catalog.search(parsed.value.records, .{ .text = "incline dumbbell curl", .max_results = results.len }, &results);
    try std.testing.expect(found.len != 0);
    var equipment: [1][]const u8 = undefined;
    var muscles: [16]@import("caudex").canonical.MuscleContribution = undefined;
    const projected = try catalog.project(found[0].*, .{ .equipment_ids = &equipment, .muscle_contributions = &muscles });
    try std.testing.expectEqualStrings(found[0].id, projected.id);
    try std.testing.expect(projected.muscleContributions.len != 0);
    const knowledge = catalog.projectKnowledge(found[0].*);
    try std.testing.expect(knowledge == null or knowledge.?.evidence.len != 0);
    var enriched_results: [10]*const catalog.Record = undefined;
    const enriched = try catalog.search(parsed.value.records, .{ .family_id = "horizontal-press", .tracking_metric = "load", .max_results = enriched_results.len }, &enriched_results);
    try std.testing.expect(enriched.len != 0);
}

test "host overrides replace by stable ID and reject duplicates" {
    const source: catalog.SourceProvenance = .{ .dataset = "host", .upstreamRepository = "host", .upstreamCommit = "1", .upstreamId = "custom", .license = "host" };
    const base = [_]catalog.Record{.{ .id = "a", .upstreamId = "a", .name = "A", .source = source }};
    const overrides = [_]catalog.Record{.{ .id = "a", .upstreamId = "custom", .name = "Replacement", .source = source }};
    var output: [2]catalog.Record = undefined;
    const merged = try catalog.merge(&base, &overrides, &output);
    try std.testing.expectEqual(@as(usize, 1), merged.len);
    try std.testing.expectEqualStrings("Replacement", merged[0].name);
    try std.testing.expectError(error.DuplicateOverrideId, catalog.merge(&base, &.{ overrides[0], overrides[0] }, &output));
}
