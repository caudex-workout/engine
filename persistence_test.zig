const std = @import("std");
const persistence = @import("persistence");

const FakeSources = struct {
    catalog_loads: usize = 0,
    history_loads: usize = 0,

    fn loadCatalog(
        context: *anyopaque,
        allocator: std.mem.Allocator,
        scope: persistence.CatalogScope,
    ) persistence.CapabilityError![]const persistence.canonical.Exercise {
        const self: *FakeSources = @ptrCast(@alignCast(context));
        self.catalog_loads += 1;
        if (!std.mem.eql(u8, scope.host_scope_key, "athlete-1"))
            return error.InvalidData;
        return allocator.dupe(persistence.canonical.Exercise, &.{});
    }

    fn loadHistory(
        context: *anyopaque,
        _: std.mem.Allocator,
        query: persistence.HistoryQuery,
    ) persistence.CapabilityError!persistence.canonical.HistorySnapshot {
        const self: *FakeSources = @ptrCast(@alignCast(context));
        self.history_loads += 1;
        if (!std.mem.eql(u8, query.host_scope_key, "athlete-1"))
            return error.InvalidData;
        return .{};
    }
};

test "catalog and history capabilities are independently callable" {
    var fake: FakeSources = .{};
    const catalog: persistence.CatalogSource = .{
        .context = &fake,
        .load_fn = FakeSources.loadCatalog,
    };
    const history: persistence.HistorySource = .{
        .context = &fake,
        .load_fn = FakeSources.loadHistory,
    };
    const loaded_catalog = try catalog.load(std.testing.allocator, .{
        .host_scope_key = "athlete-1",
        .as_of = "2026-07-26T12:00:00Z",
    });
    defer std.testing.allocator.free(loaded_catalog);
    const loaded_history = try history.load(std.testing.allocator, .{
        .host_scope_key = "athlete-1",
        .through = "2026-07-26T12:00:00Z",
    });

    try std.testing.expectEqual(@as(usize, 0), loaded_catalog.len);
    try std.testing.expectEqual(@as(usize, 0), loaded_history.workouts.len);
    try std.testing.expectEqual(@as(usize, 1), fake.catalog_loads);
    try std.testing.expectEqual(@as(usize, 1), fake.history_loads);
}

test "adapter failures and optimistic conflicts are distinct" {
    try std.testing.expect(
        persistence.AdapterError != persistence.StateStoreError,
    );
    try std.testing.expectError(error.Conflict, conflict());
    try std.testing.expectError(error.Unavailable, unavailable());
}

fn conflict() persistence.StateStoreError!void {
    return error.Conflict;
}

fn unavailable() persistence.AdapterError!void {
    return error.Unavailable;
}

test "optional write capabilities remain separate declarations" {
    try std.testing.expect(@hasDecl(persistence, "RecommendationJournal"));
    try std.testing.expect(@hasDecl(persistence, "CompletedWorkoutSink"));
    try std.testing.expectEqual(@as(u32, 1), persistence.contract_version);
}
