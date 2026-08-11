const std = @import("std");
const persistence = @import("caudex_persistence");

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

const FakeProfileStore = struct {
    record: ?persistence.AthleteProfileRecord = null,

    fn load(
        context: *anyopaque,
        _: std.mem.Allocator,
        key: persistence.AthleteProfileKey,
    ) persistence.CapabilityError!?persistence.AthleteProfileRecord {
        const self: *FakeProfileStore = @ptrCast(@alignCast(context));
        const record = self.record orelse return null;
        if (!std.mem.eql(u8, record.key.host_scope_key, key.host_scope_key) or
            !std.mem.eql(u8, record.key.athlete_profile_id, key.athlete_profile_id)) return null;
        return record;
    }

    fn compareAndSet(
        context: *anyopaque,
        _: std.mem.Allocator,
        change: persistence.CompareAndSetAthleteProfile,
    ) persistence.StateStoreError!persistence.AthleteProfileRecord {
        const self: *FakeProfileStore = @ptrCast(@alignCast(context));
        const current = if (self.record) |record|
            if (std.mem.eql(u8, record.key.host_scope_key, change.key.host_scope_key) and
                std.mem.eql(u8, record.key.athlete_profile_id, change.key.athlete_profile_id)) record else null
        else
            null;
        if ((if (current) |record| record.profile.revision else null) != change.expected_revision)
            return error.Conflict;
        if (!std.mem.eql(u8, change.key.athlete_profile_id, change.next_profile.id))
            return error.InvalidData;
        self.record = .{ .key = change.key, .profile = change.next_profile };
        return self.record.?;
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

test "athlete profiles use a separate scoped compare-and-set capability" {
    var fake: FakeProfileStore = .{};
    const store: persistence.AthleteProfileStore = .{
        .context = &fake,
        .load_fn = FakeProfileStore.load,
        .compare_and_set_fn = FakeProfileStore.compareAndSet,
    };
    const key: persistence.AthleteProfileKey = .{
        .host_scope_key = "scope-1",
        .athlete_profile_id = "athlete-1",
    };
    try std.testing.expect((try store.load(std.testing.allocator, key)) == null);
    const created = try store.compareAndSet(std.testing.allocator, .{
        .key = key,
        .expected_revision = null,
        .next_profile = .{ .id = "athlete-1", .revision = 1 },
    });
    try std.testing.expectEqual(@as(u64, 1), created.profile.revision);
    try std.testing.expectError(error.Conflict, store.compareAndSet(std.testing.allocator, .{
        .key = key,
        .expected_revision = null,
        .next_profile = .{ .id = "athlete-1", .revision = 2 },
    }));
}

fn conflict() persistence.StateStoreError!void {
    return error.Conflict;
}

fn unavailable() persistence.AdapterError!void {
    return error.Unavailable;
}

test "optional write capabilities remain separate declarations" {
    try std.testing.expect(@hasDecl(persistence, "AthleteProfileStore"));
    try std.testing.expect(@hasDecl(persistence, "RecommendationJournal"));
    try std.testing.expect(@hasDecl(persistence, "CompletedWorkoutSink"));
    try std.testing.expect(@hasDecl(persistence, "WorkoutTemplateStore"));
    try std.testing.expect(@hasDecl(persistence, "WorkflowRecoveryStore"));
    try std.testing.expect(@hasDecl(persistence, "PortableDataStore"));
    try std.testing.expect(@hasDecl(persistence, "ProgramDefinitionStore"));
    try std.testing.expect(@hasDecl(persistence, "ProgramInstanceStore"));
    try std.testing.expect(@hasDecl(persistence, "ProgramOccurrenceStore"));
    try std.testing.expectEqual(@as(u32, 5), persistence.contract_version);
}
