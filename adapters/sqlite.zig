//! Public SQLite adapter for optional Caudex persistence capabilities.
//!
//! Import as `@import("caudex_sqlite")`. SQLite handles, SQL, migrations,
//! statements, and physical schema details are private implementation data.

const std = @import("std");
const caudex = @import("caudex");
const persistence = @import("caudex_persistence");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const adapter_version = "0.1.0";
pub const schema_version: u32 = 1;
pub const minimum_schema_version: u32 = 1;

pub const Options = struct {
    busy_timeout_ms: u32 = 250,
    create_if_missing: bool = true,
};

pub const DatabaseKind = enum {
    memory,
    file,
};

pub const Compatibility = enum {
    current,
};

pub const Metadata = struct {
    adapter_version: []const u8,
    schema_version: u32,
    minimum_schema_version: u32,
    latest_schema_version: u32,
    compatibility: Compatibility,
    database_kind: DatabaseKind,
};

pub const OpenError = error{
    Busy,
    Corrupt,
    MigrationFailed,
    UnsupportedSchema,
    OpenFailed,
};

pub const MetadataError = error{
    Busy,
    Corrupt,
    OperationFailed,
};

/// Opaque connection handle. Its representation is not public API.
pub const Adapter = opaque {
    pub fn close(self: *Adapter) void {
        _ = c.sqlite3_close(raw(self));
    }

    pub fn metadata(self: *Adapter) MetadataError!Metadata {
        var query = self.prepare(
            "SELECT COALESCE(MAX(version), 0) FROM schema_migrations",
        ) catch |err| return mapMetadataError(err);
        defer query.finalize();
        if (!(query.row() catch |err| return mapMetadataError(err)))
            return error.Corrupt;
        const current = c.sqlite3_column_int64(query.raw, 0);
        if (current < 0 or current > std.math.maxInt(u32))
            return error.Corrupt;
        const filename = c.sqlite3_db_filename(raw(self), "main");
        const kind: DatabaseKind = if (filename == null or filename[0] == 0)
            .memory
        else
            .file;
        return .{
            .adapter_version = adapter_version,
            .schema_version = @intCast(current),
            .minimum_schema_version = minimum_schema_version,
            .latest_schema_version = schema_version,
            .compatibility = .current,
            .database_kind = kind,
        };
    }

    pub fn catalogSource(self: *Adapter) persistence.CatalogSource {
        return .{ .context = self, .load_fn = loadCatalogCallback };
    }

    pub fn historySource(self: *Adapter) persistence.HistorySource {
        return .{ .context = self, .load_fn = loadHistoryCallback };
    }

    pub fn stateStore(self: *Adapter) persistence.MethodologyStateStore {
        return .{
            .context = self,
            .load_fn = loadStateCallback,
            .compare_and_set_fn = compareAndSetStateCallback,
        };
    }

    pub fn replaceCatalog(
        self: *Adapter,
        allocator: std.mem.Allocator,
        scope: persistence.CatalogScope,
        exercises: []const persistence.canonical.Exercise,
    ) persistence.CapabilityError!void {
        try self.execute("BEGIN IMMEDIATE");
        errdefer self.execute("ROLLBACK") catch {};

        var delete_statement = try self.prepare(
            "DELETE FROM catalog WHERE host_scope_key = ?1",
        );
        defer delete_statement.finalize();
        try delete_statement.bindText(1, scope.host_scope_key);
        try delete_statement.done();

        var insert_statement = try self.prepare(
            \\INSERT INTO catalog (host_scope_key, exercise_id, payload)
            \\VALUES (?1, ?2, ?3)
        );
        defer insert_statement.finalize();
        for (exercises) |exercise| {
            const payload = try encodeAlloc(allocator, exercise);
            defer allocator.free(payload);
            try insert_statement.bindText(1, scope.host_scope_key);
            try insert_statement.bindText(2, exercise.id);
            try insert_statement.bindText(3, payload);
            try insert_statement.done();
            try insert_statement.reset();
        }
        try self.execute("COMMIT");
    }

    pub fn appendCompletedWorkout(
        self: *Adapter,
        allocator: std.mem.Allocator,
        host_scope_key: []const u8,
        workout: persistence.canonical.CompletedWorkout,
    ) persistence.CapabilityError!void {
        const payload = try encodeAlloc(allocator, workout);
        defer allocator.free(payload);
        var statement = try self.prepare(
            \\INSERT INTO history
            \\  (host_scope_key, completed_at, workout_id, payload)
            \\VALUES (?1, ?2, ?3, ?4)
            \\ON CONFLICT (host_scope_key, completed_at, workout_id)
            \\DO UPDATE SET payload = excluded.payload
        );
        defer statement.finalize();
        try statement.bindText(1, host_scope_key);
        try statement.bindText(2, workout.completedAt);
        try statement.bindText(3, workout.id);
        try statement.bindText(4, payload);
        try statement.done();
    }

    fn migrate(self: *Adapter) persistence.AdapterError!void {
        try self.execute(
            \\CREATE TABLE IF NOT EXISTS schema_migrations (
            \\  version INTEGER PRIMARY KEY
            \\)
        );
        var query = try self.prepare(
            "SELECT COALESCE(MAX(version), 0) FROM schema_migrations",
        );
        defer query.finalize();
        if (!try query.row()) return error.InvalidData;
        const current: u32 = @intCast(c.sqlite3_column_int(query.raw, 0));
        if (current > schema_version) return error.UnsupportedVersion;
        if (current == schema_version) return;

        try self.execute("BEGIN IMMEDIATE");
        errdefer self.execute("ROLLBACK") catch {};
        try self.executeScript(
            @embedFile("sqlite/migrations/001_initial.sql"),
        );
        var record = try self.prepare(
            "INSERT INTO schema_migrations (version) VALUES (?1)",
        );
        defer record.finalize();
        try record.bindInt(1, schema_version);
        try record.done();
        try self.execute("COMMIT");
    }

    fn execute(self: *Adapter, sql: []const u8) persistence.AdapterError!void {
        var statement = try self.prepare(sql);
        defer statement.finalize();
        try statement.done();
    }

    fn executeScript(
        self: *Adapter,
        script: []const u8,
    ) persistence.AdapterError!void {
        var statements = std.mem.splitScalar(u8, script, ';');
        while (statements.next()) |part| {
            const sql = std.mem.trim(u8, part, " \n\r\t");
            if (sql.len == 0) continue;
            try self.execute(sql);
        }
    }

    fn prepare(self: *Adapter, sql: []const u8) persistence.AdapterError!Statement {
        var statement: ?*c.sqlite3_stmt = null;
        const status = c.sqlite3_prepare_v2(
            raw(self),
            sql.ptr,
            @intCast(sql.len),
            &statement,
            null,
        );
        if (status != c.SQLITE_OK or statement == null) return mapStatus(status);
        return .{ .raw = statement.? };
    }
};

pub fn open(path: [:0]const u8, options: Options) OpenError!*Adapter {
    var database: ?*c.sqlite3 = null;
    var flags = c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_FULLMUTEX;
    if (options.create_if_missing) flags |= c.SQLITE_OPEN_CREATE;
    const status = c.sqlite3_open_v2(path.ptr, &database, flags, null);
    if (status != c.SQLITE_OK or database == null) {
        if (database) |db| _ = c.sqlite3_close(db);
        return mapOpenStatus(status);
    }
    const adapter: *Adapter = @ptrCast(database.?);
    errdefer adapter.close();
    if (c.sqlite3_busy_timeout(raw(adapter), @intCast(options.busy_timeout_ms)) !=
        c.SQLITE_OK) return error.OpenFailed;
    adapter.migrate() catch |err| return mapMigrationError(err);
    return adapter;
}

pub fn openInMemory(options: Options) OpenError!*Adapter {
    return open(":memory:", options);
}

fn raw(self: *Adapter) *c.sqlite3 {
    return @ptrCast(@alignCast(self));
}

const Statement = struct {
    raw: *c.sqlite3_stmt,

    fn finalize(self: Statement) void {
        _ = c.sqlite3_finalize(self.raw);
    }

    fn reset(self: Statement) persistence.AdapterError!void {
        if (c.sqlite3_reset(self.raw) != c.SQLITE_OK) return error.OperationFailed;
        if (c.sqlite3_clear_bindings(self.raw) != c.SQLITE_OK)
            return error.OperationFailed;
    }

    fn bindText(
        self: Statement,
        index: c_int,
        value: []const u8,
    ) persistence.AdapterError!void {
        const status = c.sqlite3_bind_text64(
            self.raw,
            index,
            value.ptr,
            value.len,
            null,
            c.SQLITE_UTF8,
        );
        if (status != c.SQLITE_OK) return mapStatus(status);
    }

    fn bindInt(
        self: Statement,
        index: c_int,
        value: anytype,
    ) persistence.AdapterError!void {
        const status = c.sqlite3_bind_int64(self.raw, index, @intCast(value));
        if (status != c.SQLITE_OK) return mapStatus(status);
    }

    fn row(self: Statement) persistence.AdapterError!bool {
        return switch (c.sqlite3_step(self.raw)) {
            c.SQLITE_ROW => true,
            c.SQLITE_DONE => false,
            else => |status| mapStatus(status),
        };
    }

    fn done(self: Statement) persistence.AdapterError!void {
        const status = c.sqlite3_step(self.raw);
        if (status != c.SQLITE_DONE) return mapStatus(status);
    }
};

fn loadCatalogCallback(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    scope: persistence.CatalogScope,
) persistence.CapabilityError![]const persistence.canonical.Exercise {
    const self: *Adapter = @ptrCast(@alignCast(context));
    var statement = try self.prepare(
        \\SELECT payload FROM catalog
        \\WHERE host_scope_key = ?1
        \\ORDER BY exercise_id
    );
    defer statement.finalize();
    try statement.bindText(1, scope.host_scope_key);
    var values: std.ArrayList(persistence.canonical.Exercise) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.row()) {
        try values.append(
            allocator,
            try parseColumn(
                persistence.canonical.Exercise,
                allocator,
                statement.raw,
                0,
            ),
        );
    }
    return values.toOwnedSlice(allocator);
}

fn loadHistoryCallback(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    query: persistence.HistoryQuery,
) persistence.CapabilityError!persistence.canonical.HistorySnapshot {
    const self: *Adapter = @ptrCast(@alignCast(context));
    var statement = try self.prepare(
        \\SELECT payload FROM history
        \\WHERE host_scope_key = ?1 AND completed_at <= ?2
        \\ORDER BY completed_at, workout_id
    );
    defer statement.finalize();
    try statement.bindText(1, query.host_scope_key);
    try statement.bindText(2, query.through);
    var values: std.ArrayList(persistence.canonical.CompletedWorkout) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.row()) {
        const workout = try parseColumn(
            persistence.canonical.CompletedWorkout,
            allocator,
            statement.raw,
            0,
        );
        if (query.exercise_ids.len == 0 or
            workoutContainsAny(workout, query.exercise_ids))
        {
            try values.append(allocator, workout);
        }
    }
    return .{ .workouts = try values.toOwnedSlice(allocator) };
}

fn loadStateCallback(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    key: persistence.MethodologyStateKey,
) persistence.CapabilityError!?persistence.MethodologyStateRecord {
    const self: *Adapter = @ptrCast(@alignCast(context));
    var statement = try self.prepare(
        \\SELECT methodology_version, state_schema_version, state_json,
        \\       revision, updated_at
        \\FROM methodology_state
        \\WHERE host_scope_key = ?1 AND methodology_id = ?2
    );
    defer statement.finalize();
    try statement.bindText(1, key.host_scope_key);
    try statement.bindText(2, key.methodology_id);
    if (!try statement.row()) return null;
    return try readStateRecord(allocator, statement.raw, key);
}

fn compareAndSetStateCallback(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    change: persistence.CompareAndSetMethodologyState,
) persistence.StateStoreError!persistence.MethodologyStateRecord {
    const self: *Adapter = @ptrCast(@alignCast(context));
    try self.execute("BEGIN IMMEDIATE");
    errdefer self.execute("ROLLBACK") catch {};

    const current = try loadStateCallback(context, allocator, change.key);
    const actual_revision = if (current) |record| record.revision else null;
    if (!optionalStringsEqual(actual_revision, change.expected_revision)) {
        self.execute("ROLLBACK") catch {};
        return error.Conflict;
    }
    const next_revision: u64 = if (actual_revision) |revision|
        (std.fmt.parseInt(u64, revision, 10) catch return error.InvalidData) + 1
    else
        1;
    const state_json = try encodeAlloc(allocator, change.next_state);
    defer allocator.free(state_json);
    var statement = try self.prepare(
        \\INSERT INTO methodology_state
        \\  (host_scope_key, methodology_id, methodology_version,
        \\   state_schema_version, state_json, revision, updated_at)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
        \\ON CONFLICT (host_scope_key, methodology_id) DO UPDATE SET
        \\  methodology_version = excluded.methodology_version,
        \\  state_schema_version = excluded.state_schema_version,
        \\  state_json = excluded.state_json,
        \\  revision = excluded.revision,
        \\  updated_at = excluded.updated_at
    );
    defer statement.finalize();
    try statement.bindText(1, change.key.host_scope_key);
    try statement.bindText(2, change.key.methodology_id);
    try statement.bindText(3, change.methodology_version);
    try statement.bindInt(4, change.next_state.schemaVersion);
    try statement.bindText(5, state_json);
    try statement.bindInt(6, next_revision);
    try statement.bindText(7, change.updated_at);
    try statement.done();
    try self.execute("COMMIT");

    const revision = try std.fmt.allocPrint(allocator, "{d}", .{next_revision});
    return .{
        .key = .{
            .host_scope_key = try allocator.dupe(u8, change.key.host_scope_key),
            .methodology_id = try allocator.dupe(u8, change.key.methodology_id),
        },
        .methodology_version = try allocator.dupe(u8, change.methodology_version),
        .state = change.next_state,
        .revision = revision,
        .updated_at = try allocator.dupe(u8, change.updated_at),
    };
}

fn readStateRecord(
    allocator: std.mem.Allocator,
    statement: *c.sqlite3_stmt,
    key: persistence.MethodologyStateKey,
) persistence.CapabilityError!persistence.MethodologyStateRecord {
    const methodology_version = try dupeColumn(allocator, statement, 0);
    const schema: u32 = @intCast(c.sqlite3_column_int(statement, 1));
    const json = column(statement, 2) orelse return error.InvalidData;
    const state = std.json.parseFromSliceLeaky(
        persistence.canonical.MethodologyState,
        allocator,
        json,
        .{ .allocate = .alloc_always },
    ) catch return error.InvalidData;
    if (state.schemaVersion != schema) return error.InvalidData;
    const revision = try std.fmt.allocPrint(
        allocator,
        "{d}",
        .{c.sqlite3_column_int64(statement, 3)},
    );
    return .{
        .key = .{
            .host_scope_key = try allocator.dupe(u8, key.host_scope_key),
            .methodology_id = try allocator.dupe(u8, key.methodology_id),
        },
        .methodology_version = methodology_version,
        .state = state,
        .revision = revision,
        .updated_at = try dupeColumn(allocator, statement, 4),
    };
}

fn parseColumn(
    comptime T: type,
    allocator: std.mem.Allocator,
    statement: *c.sqlite3_stmt,
    index: c_int,
) persistence.CapabilityError!T {
    const json = column(statement, index) orelse return error.InvalidData;
    return std.json.parseFromSliceLeaky(
        T,
        allocator,
        json,
        .{ .allocate = .alloc_always },
    ) catch return error.InvalidData;
}

fn encodeAlloc(
    allocator: std.mem.Allocator,
    value: anytype,
) persistence.CapabilityError![]u8 {
    const buffer = try allocator.alloc(u8, 1024 * 1024);
    errdefer allocator.free(buffer);
    const encoded = caudex.canonical_json.encode(value, buffer) catch
        return error.InvalidData;
    return allocator.realloc(buffer, encoded.len);
}

fn column(statement: *c.sqlite3_stmt, index: c_int) ?[]const u8 {
    const bytes = c.sqlite3_column_text(statement, index) orelse return null;
    const length: usize = @intCast(c.sqlite3_column_bytes(statement, index));
    return bytes[0..length];
}

fn dupeColumn(
    allocator: std.mem.Allocator,
    statement: *c.sqlite3_stmt,
    index: c_int,
) persistence.CapabilityError![]const u8 {
    return allocator.dupe(u8, column(statement, index) orelse
        return error.InvalidData);
}

fn workoutContainsAny(
    workout: persistence.canonical.CompletedWorkout,
    exercise_ids: []const []const u8,
) bool {
    for (workout.exercises) |exercise| {
        for (exercise_ids) |id| {
            if (std.mem.eql(u8, exercise.exerciseId, id)) return true;
        }
    }
    return false;
}

fn optionalStringsEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn mapStatus(status: c_int) persistence.AdapterError {
    return switch (status) {
        c.SQLITE_BUSY, c.SQLITE_LOCKED => error.Unavailable,
        c.SQLITE_NOMEM => error.OperationFailed,
        c.SQLITE_SCHEMA => error.UnsupportedVersion,
        c.SQLITE_CORRUPT, c.SQLITE_NOTADB => error.InvalidData,
        else => error.OperationFailed,
    };
}

fn mapOpenStatus(status: c_int) OpenError {
    return switch (status) {
        c.SQLITE_BUSY, c.SQLITE_LOCKED => error.Busy,
        c.SQLITE_CORRUPT, c.SQLITE_NOTADB => error.Corrupt,
        else => error.OpenFailed,
    };
}

fn mapMigrationError(err: persistence.AdapterError) OpenError {
    return switch (err) {
        error.Unavailable => error.Busy,
        error.InvalidData => error.Corrupt,
        error.UnsupportedVersion => error.UnsupportedSchema,
        error.OperationFailed => error.MigrationFailed,
    };
}

fn mapMetadataError(err: persistence.AdapterError) MetadataError {
    return switch (err) {
        error.Unavailable => error.Busy,
        error.InvalidData, error.UnsupportedVersion => error.Corrupt,
        error.OperationFailed => error.OperationFailed,
    };
}
