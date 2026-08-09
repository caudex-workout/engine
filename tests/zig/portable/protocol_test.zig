const std = @import("std");
const portable = @import("caudex_portable");
const assets = @import("repository_test_assets");

test "portable fixture preserves exact decimals and deterministic bytes" {
    const fixture = assets.portable_export;
    const parsed = try portable.decodeDocument(std.testing.allocator, fixture);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("185.00", parsed.value.completedWorkouts[0].workout.exercises[0].sets[0].actualMetrics[0].value.amount);
    var output: [8192]u8 = undefined;
    try std.testing.expectEqualStrings(std.mem.trimEnd(u8, fixture, "\r\n"), try portable.encode(parsed.value, &output));
    var issues: [portable.max_issues]portable.Issue = undefined;
    const plan = try portable.planImport(.{
        .schemaVersion = 1,
        .mode = .merge,
        .conflictPolicy = .reject,
        .dryRun = true,
        .document = parsed.value,
    }, &issues);
    try std.testing.expect(plan.valid);
    try std.testing.expect(plan.dryRun);
    try std.testing.expectEqual(@as(usize, 1), plan.counts.completedWorkouts);
}

test "portable validation returns structured duplicate and reference issues" {
    const references = [_]portable.CatalogReference{
        .{ .hostScopeKey = "scope-1", .exerciseId = "z" },
        .{ .hostScopeKey = "scope-1", .exerciseId = "z" },
    };
    const active = [_]portable.ActiveWorkoutRecord{.{
        .hostScopeKey = "scope-1",
        .workoutId = "workout-1",
        .snapshot = .{ .workouts = &.{.{
            .id = "workout-1",
            .scope = .{ .hostScopeKey = "scope-1" },
            .revision = 1,
            .status = .active,
            .startedAt = "2026-08-04T12:00:00Z",
            .exercises = &.{.{ .id = "membership-1", .exerciseId = "missing" }},
        }} },
    }};
    var issues: [8]portable.Issue = undefined;
    const plan = try portable.planImport(.{
        .schemaVersion = 1,
        .mode = .replace,
        .conflictPolicy = .overwrite,
        .document = .{
            .schemaVersion = 1,
            .exportedAt = "2026-08-04T12:00:00Z",
            .catalogReferences = &references,
            .activeWorkouts = &active,
        },
    }, &issues);
    try std.testing.expect(!plan.valid);
    try std.testing.expectEqualStrings("portable.duplicate_id", plan.issues[0].code);
    try std.testing.expectEqualStrings("portable.catalog_reference_missing", plan.issues[1].code);
}

test "portable protocol rejects unsupported versions and byte limits" {
    const fixture = assets.portable_export;
    var unsupported = try std.testing.allocator.dupe(u8, fixture);
    defer std.testing.allocator.free(unsupported);
    unsupported[17] = '2';
    try std.testing.expectError(error.UnsupportedVersion, portable.decodeDocument(std.testing.allocator, unsupported));
    const oversized = try std.testing.allocator.alloc(u8, portable.max_input_bytes + 1);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, ' ');
    try std.testing.expectError(error.InputTooLarge, portable.decodeDocument(std.testing.allocator, oversized));
}

test "portable semantic validation returns stable timestamp decimal and unit issues" {
    const document: portable.Document = .{
        .schemaVersion = 1,
        .exportedAt = "not-a-time",
        .catalogReferences = &.{.{ .hostScopeKey = "scope-1", .exerciseId = "squat" }},
        .completedWorkouts = &.{.{
            .hostScopeKey = "scope-1",
            .workout = .{
                .id = "workout-1",
                .startedAt = "invalid",
                .completedAt = "also-invalid",
                .exercises = &.{.{ .exerciseId = "squat", .sets = &.{.{
                    .kind = "working",
                    .actualMetrics = &.{.{ .code = "load", .value = .{ .amount = "01.0", .unit = "stone" } }},
                    .status = .completed,
                }} }},
            },
        }},
    };
    var issues: [16]portable.Issue = undefined;
    const plan = try portable.planImport(.{ .schemaVersion = 1, .mode = .merge, .conflictPolicy = .reject, .document = document }, &issues);
    try std.testing.expect(!plan.valid);
    try std.testing.expect(hasIssue(plan.issues, "portable.timestamp_invalid"));
    try std.testing.expect(hasIssue(plan.issues, "portable.decimal_invalid"));
    try std.testing.expect(hasIssue(plan.issues, "portable.unit_unknown"));
}

fn hasIssue(issues: []const portable.Issue, code: []const u8) bool {
    for (issues) |issue| if (std.mem.eql(u8, issue.code, code)) return true;
    return false;
}
