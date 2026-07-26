const std = @import("std");
const persistence = @import("caudex_persistence");
const sqlite = @import("caudex_sqlite");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const exercises = [_]persistence.canonical.Exercise{
    .{ .id = "squat" },
    .{ .id = "bench-press" },
};
const workouts = [_]persistence.canonical.CompletedWorkout{
    .{
        .id = "later",
        .startedAt = "2026-07-25T12:00:00Z",
        .completedAt = "2026-07-25T13:00:00Z",
        .exercises = &.{},
    },
    .{
        .id = "earlier",
        .startedAt = "2026-07-24T12:00:00Z",
        .completedAt = "2026-07-24T13:00:00Z",
        .exercises = &.{},
    },
};
const state: persistence.canonical.MethodologyState = .{
    .schemaVersion = 1,
    .data = .{ .object = .empty },
};
const key: persistence.MethodologyStateKey = .{
    .host_scope_key = "athlete-1",
    .methodology_id = "caudex.double-progression",
};

test "in-memory adapter loads canonical snapshots and compare-and-sets state" {
    const adapter = try sqlite.openInMemory(.{});
    defer adapter.close();
    const metadata = try adapter.metadata();
    try std.testing.expectEqual(sqlite.DatabaseKind.memory, metadata.database_kind);
    try std.testing.expectEqual(sqlite.Compatibility.current, metadata.compatibility);
    try std.testing.expectEqual(sqlite.schema_version, metadata.schema_version);
    try std.testing.expectEqualStrings(sqlite.adapter_version, metadata.adapter_version);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try adapter.replaceCatalog(allocator, .{
        .host_scope_key = "athlete-1",
        .as_of = "2026-07-26T12:00:00Z",
    }, &exercises);
    const catalog = try adapter.catalogSource().load(allocator, .{
        .host_scope_key = "athlete-1",
        .as_of = "2026-07-26T12:00:00Z",
    });
    try std.testing.expectEqualStrings("bench-press", catalog[0].id);
    try std.testing.expectEqualStrings("squat", catalog[1].id);

    try adapter.appendCompletedWorkout(allocator, "athlete-1", workouts[0]);
    try adapter.appendCompletedWorkout(allocator, "athlete-1", workouts[1]);
    const history = try adapter.historySource().load(allocator, .{
        .host_scope_key = "athlete-1",
        .through = "2026-07-26T12:00:00Z",
    });
    try std.testing.expectEqualStrings("earlier", history.workouts[0].id);
    try std.testing.expectEqualStrings("later", history.workouts[1].id);

    const first = try adapter.stateStore().compareAndSet(allocator, .{
        .key = key,
        .expected_revision = null,
        .methodology_version = "0.1.0",
        .next_state = state,
        .updated_at = "2026-07-26T12:00:00Z",
    });
    try std.testing.expectEqualStrings("1", first.revision);
    try std.testing.expectError(
        error.Conflict,
        adapter.stateStore().compareAndSet(allocator, .{
            .key = key,
            .expected_revision = null,
            .methodology_version = "0.1.0",
            .next_state = state,
            .updated_at = "2026-07-26T12:01:00Z",
        }),
    );
    const second = try adapter.stateStore().compareAndSet(allocator, .{
        .key = key,
        .expected_revision = first.revision,
        .methodology_version = "0.1.0",
        .next_state = state,
        .updated_at = "2026-07-26T12:02:00Z",
    });
    try std.testing.expectEqualStrings("2", second.revision);
}

test "file adapter persists state across connections" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/caudex.sqlite",
        .{temporary.sub_path},
        0,
    );
    defer std.testing.allocator.free(database_path);

    {
        const first = try sqlite.open(database_path, .{});
        defer first.close();
        const metadata = try first.metadata();
        try std.testing.expectEqual(sqlite.DatabaseKind.file, metadata.database_kind);
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        _ = try first.stateStore().compareAndSet(arena.allocator(), .{
            .key = key,
            .expected_revision = null,
            .methodology_version = "0.1.0",
            .next_state = state,
            .updated_at = "2026-07-26T12:00:00Z",
        });
    }
    {
        const second = try sqlite.open(database_path, .{});
        defer second.close();
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const loaded = (try second.stateStore().load(
            arena.allocator(),
            key,
        )).?;
        try std.testing.expectEqualStrings("1", loaded.revision);
    }
}

test "open without create rejects a missing file" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/missing.sqlite",
        .{temporary.sub_path},
        0,
    );
    defer std.testing.allocator.free(database_path);
    try std.testing.expectError(
        error.OpenFailed,
        sqlite.open(database_path, .{ .create_if_missing = false }),
    );
}

test "newer schema is rejected distinctly" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try databasePath(temporary, "newer.sqlite");
    defer std.testing.allocator.free(database_path);
    const database = try openRaw(database_path);
    defer _ = c.sqlite3_close(database);
    try execRaw(
        database,
        "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY)",
    );
    try execRaw(database, "INSERT INTO schema_migrations (version) VALUES (3)");

    try std.testing.expectError(
        error.UnsupportedSchema,
        sqlite.open(database_path, .{}),
    );
}

test "schema version one migrates forward to current metadata" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try databasePath(temporary, "version-one.sqlite");
    defer std.testing.allocator.free(database_path);
    {
        const database = try openRaw(database_path);
        defer _ = c.sqlite3_close(database);
        try execRaw(
            database,
            "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY)",
        );
        try execRaw(
            database,
            @embedFile("adapters/sqlite/migrations/001_initial.sql"),
        );
        try execRaw(
            database,
            "INSERT INTO schema_migrations (version) VALUES (1)",
        );
    }

    const migrated = try sqlite.open(database_path, .{});
    defer migrated.close();
    const metadata = try migrated.metadata();
    try std.testing.expectEqual(sqlite.schema_version, metadata.schema_version);
}

test "corrupt database is rejected distinctly" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try databasePath(temporary, "corrupt.sqlite");
    defer std.testing.allocator.free(database_path);
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "corrupt.sqlite",
        .data = "this is not a sqlite database",
    });

    try std.testing.expectError(error.Corrupt, sqlite.open(database_path, .{}));
}

test "migration failure is distinct from corruption" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try databasePath(temporary, "migration.sqlite");
    defer std.testing.allocator.free(database_path);
    const database = try openRaw(database_path);
    defer _ = c.sqlite3_close(database);
    try execRaw(database, "CREATE TABLE schema_migrations (wrong INTEGER)");

    try std.testing.expectError(
        error.MigrationFailed,
        sqlite.open(database_path, .{}),
    );
}

test "busy timeout maps lock contention to unavailable" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/busy.sqlite",
        .{temporary.sub_path},
        0,
    );
    defer std.testing.allocator.free(database_path);
    const adapter = try sqlite.open(database_path, .{
        .busy_timeout_ms = 1,
    });
    defer adapter.close();

    var locking_database: ?*c.sqlite3 = null;
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_open(database_path.ptr, &locking_database),
    );
    defer _ = c.sqlite3_close(locking_database);
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            locking_database,
            "BEGIN EXCLUSIVE",
            null,
            null,
            null,
        ),
    );
    defer _ = c.sqlite3_exec(
        locking_database,
        "ROLLBACK",
        null,
        null,
        null,
    );

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(
        error.Unavailable,
        adapter.stateStore().load(arena.allocator(), key),
    );
}

test "open-time lock contention is a distinct busy error" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const database_path = try databasePath(temporary, "open-busy.sqlite");
    defer std.testing.allocator.free(database_path);
    const initialized = try sqlite.open(database_path, .{});
    initialized.close();

    const locking_database = try openRaw(database_path);
    defer _ = c.sqlite3_close(locking_database);
    try execRaw(locking_database, "BEGIN EXCLUSIVE");
    defer execRaw(locking_database, "ROLLBACK") catch {};

    try std.testing.expectError(
        error.Busy,
        sqlite.open(database_path, .{ .busy_timeout_ms = 1 }),
    );
}

test "public adapter handle and declarations expose no SQLite internals" {
    try std.testing.expect(@typeInfo(sqlite.Adapter) == .@"opaque");
    inline for (.{
        "db",
        "raw",
        "prepare",
        "execute",
        "migrate",
        "schema_migrations",
        "CREATE TABLE",
    }) |name| {
        try std.testing.expect(!@hasDecl(sqlite, name));
        try std.testing.expect(!@hasDecl(sqlite.Adapter, name));
    }
}

fn databasePath(
    temporary: std.testing.TmpDir,
    name: []const u8,
) ![:0]u8 {
    return std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/{s}",
        .{ temporary.sub_path, name },
        0,
    );
}

fn openRaw(path: [:0]const u8) !*c.sqlite3 {
    var database: ?*c.sqlite3 = null;
    try std.testing.expectEqual(c.SQLITE_OK, c.sqlite3_open(path.ptr, &database));
    return database orelse error.RawDatabaseUnavailable;
}

fn execRaw(database: *c.sqlite3, sql: [*:0]const u8) !void {
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(database, sql, null, null, null),
    );
}
