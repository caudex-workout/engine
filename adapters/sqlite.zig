//! Public SQLite adapter for optional Caudex persistence capabilities.
//!
//! Import as `@import("caudex_sqlite")`. SQLite handles, SQL, migrations,
//! statements, and physical schema details are private implementation data.

const std = @import("std");
const caudex = @import("caudex");
const persistence = @import("caudex_persistence");
const tracking = @import("caudex_tracking");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const adapter_version = "0.1.0";
pub const schema_version: u32 = 2;
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

pub const TrackingError = persistence.CapabilityError;

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

    pub fn startWorkout(
        self: *Adapter,
        allocator: std.mem.Allocator,
        command: tracking.StartWorkoutCommand,
    ) TrackingError!tracking.CommandResult {
        return startTrackedWorkout(self, allocator, command);
    }

    pub fn readWorkout(
        self: *Adapter,
        allocator: std.mem.Allocator,
        query: tracking.ReadWorkoutQuery,
    ) TrackingError!tracking.ReadWorkoutResult {
        return readTrackedWorkout(self, allocator, query);
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

        if (current < 1) try self.applyMigration(
            1,
            @embedFile("sqlite/migrations/001_initial.sql"),
        );
        if (current < 2) try self.applyMigration(
            2,
            @embedFile("sqlite/migrations/002_tracking_start.sql"),
        );
    }

    fn applyMigration(
        self: *Adapter,
        version: u32,
        script: []const u8,
    ) persistence.AdapterError!void {
        try self.execute("BEGIN IMMEDIATE");
        errdefer self.execute("ROLLBACK") catch {};
        try self.executeScript(script);
        var record = try self.prepare(
            "INSERT INTO schema_migrations (version) VALUES (?1)",
        );
        defer record.finalize();
        try record.bindInt(1, version);
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

fn startTrackedWorkout(
    self: *Adapter,
    allocator: std.mem.Allocator,
    command: tracking.StartWorkoutCommand,
) TrackingError!tracking.CommandResult {
    var issue_storage: [1]tracking.Issue = undefined;
    const validated = tracking.startWorkout(.{}, command, &issue_storage) catch
        unreachable;
    switch (validated) {
        .accepted => {},
        .rejected => |rejected| return ownRejected(allocator, rejected),
    }

    try self.execute("BEGIN IMMEDIATE");
    errdefer self.execute("ROLLBACK") catch {};

    const prior_receipt = try loadStartReceipt(
        self,
        allocator,
        command.scope,
        command.metadata.command_id,
    );
    if (prior_receipt) |receipt| {
        const replay = tracking.startWorkout(
            .{ .start_receipts = &.{receipt} },
            command,
            &issue_storage,
        ) catch unreachable;
        const owned = switch (replay) {
            .accepted => replay,
            .rejected => |rejected| try ownRejected(allocator, rejected),
        };
        try self.execute("COMMIT");
        return owned;
    }

    const existing = try loadTrackedWorkout(
        self,
        allocator,
        command.scope,
        command.workout_id,
    );
    const decided = tracking.startWorkout(
        .{ .workouts = if (existing) |workout| &.{workout} else &.{} },
        command,
        &issue_storage,
    ) catch unreachable;
    const proposed = switch (decided) {
        .accepted => |accepted| accepted,
        .rejected => |rejected| {
            const owned = try ownRejected(allocator, rejected);
            try self.execute("ROLLBACK");
            return owned;
        },
    };

    const accepted = try ownAccepted(allocator, proposed);
    try insertTrackedWorkout(self, accepted.workout);
    try insertStartReceipt(self, command, accepted);
    try self.execute("COMMIT");
    return .{ .accepted = accepted };
}

fn readTrackedWorkout(
    self: *Adapter,
    allocator: std.mem.Allocator,
    query: tracking.ReadWorkoutQuery,
) TrackingError!tracking.ReadWorkoutResult {
    const workout = try loadTrackedWorkout(
        self,
        allocator,
        query.scope,
        query.workout_id,
    );
    if (workout) |found| return .{ .found = found };
    return .{ .not_found = .{
        .code = tracking.issue_codes.workout_not_found,
        .category = .not_found,
        .severity = .@"error",
        .message = "No workout matched the requested scope and ID.",
    } };
}

fn loadTrackedWorkout(
    self: *Adapter,
    allocator: std.mem.Allocator,
    scope: tracking.Scope,
    workout_id: tracking.Id,
) TrackingError!?tracking.Workout {
    var statement = try self.prepare(
        \\SELECT revision, status, started_at, completed_at
        \\FROM tracking_workouts
        \\WHERE host_scope_key = ?1 AND athlete_id = ?2 AND workout_id = ?3
    );
    defer statement.finalize();
    try statement.bindText(1, scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(scope));
    try statement.bindText(3, workout_id.bytes);
    if (!try statement.row()) return null;
    const revision = c.sqlite3_column_int64(statement.raw, 0);
    if (revision < 1) return error.InvalidData;
    const status = try parseWorkoutStatus(
        column(statement.raw, 1) orelse return error.InvalidData,
    );
    const started_at = tracking.Timestamp{
        .bytes = try dupeColumn(allocator, statement.raw, 2),
    };
    _ = tracking.Timestamp.parse(started_at.bytes) catch return error.InvalidData;
    const completed_bytes = column(statement.raw, 3);
    const completed_at: ?tracking.Timestamp = if (completed_bytes) |value|
        .{ .bytes = try allocator.dupe(u8, value) }
    else
        null;
    return .{
        .id = try ownId(allocator, workout_id),
        .scope = try ownScope(allocator, scope),
        .revision = @intCast(revision),
        .status = status,
        .started_at = started_at,
        .completed_at = completed_at,
    };
}

fn loadStartReceipt(
    self: *Adapter,
    allocator: std.mem.Allocator,
    scope: tracking.Scope,
    command_id: tracking.Id,
) TrackingError!?tracking.StartReceipt {
    var statement = try self.prepare(
        \\SELECT command_kind, occurred_at, workout_id, started_at,
        \\       result_revision, result_status
        \\FROM tracking_command_receipts
        \\WHERE host_scope_key = ?1 AND athlete_id = ?2 AND command_id = ?3
    );
    defer statement.finalize();
    try statement.bindText(1, scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(scope));
    try statement.bindText(3, command_id.bytes);
    if (!try statement.row()) return null;
    const kind = column(statement.raw, 0) orelse return error.InvalidData;
    if (!std.mem.eql(u8, kind, "start_workout")) return error.InvalidData;
    const occurred_at = tracking.Timestamp{
        .bytes = try dupeColumn(allocator, statement.raw, 1),
    };
    const workout_id = tracking.Id{
        .bytes = try dupeColumn(allocator, statement.raw, 2),
    };
    const started_at = tracking.Timestamp{
        .bytes = try dupeColumn(allocator, statement.raw, 3),
    };
    const revision = c.sqlite3_column_int64(statement.raw, 4);
    if (revision < 1) return error.InvalidData;
    const status = try parseWorkoutStatus(
        column(statement.raw, 5) orelse return error.InvalidData,
    );
    const owned_scope = try ownScope(allocator, scope);
    const owned_command_id = try ownId(allocator, command_id);
    const command: tracking.StartWorkoutCommand = .{
        .metadata = .{
            .command_id = owned_command_id,
            .occurred_at = occurred_at,
        },
        .scope = owned_scope,
        .workout_id = workout_id,
        .started_at = started_at,
    };
    return .{
        .command = command,
        .accepted = .{
            .command_id = owned_command_id,
            .disposition = .applied,
            .workout = .{
                .id = workout_id,
                .scope = owned_scope,
                .revision = @intCast(revision),
                .status = status,
                .started_at = started_at,
            },
        },
    };
}

fn insertTrackedWorkout(
    self: *Adapter,
    workout: tracking.Workout,
) persistence.AdapterError!void {
    var statement = try self.prepare(
        \\INSERT INTO tracking_workouts
        \\  (host_scope_key, athlete_id, workout_id, revision, status,
        \\   started_at, completed_at)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL)
    );
    defer statement.finalize();
    try statement.bindText(1, workout.scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(workout.scope));
    try statement.bindText(3, workout.id.bytes);
    try statement.bindInt(4, workout.revision);
    try statement.bindText(5, workoutStatusText(workout.status));
    try statement.bindText(6, workout.started_at.bytes);
    try statement.done();
}

fn insertStartReceipt(
    self: *Adapter,
    command: tracking.StartWorkoutCommand,
    accepted: tracking.AcceptedCommand,
) persistence.AdapterError!void {
    var statement = try self.prepare(
        \\INSERT INTO tracking_command_receipts
        \\  (host_scope_key, athlete_id, command_id, command_kind, occurred_at,
        \\   workout_id, started_at, result_revision, result_status)
        \\VALUES (?1, ?2, ?3, 'start_workout', ?4, ?5, ?6, ?7, ?8)
    );
    defer statement.finalize();
    try statement.bindText(1, command.scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(command.scope));
    try statement.bindText(3, command.metadata.command_id.bytes);
    try statement.bindText(4, command.metadata.occurred_at.bytes);
    try statement.bindText(5, command.workout_id.bytes);
    try statement.bindText(6, command.started_at.bytes);
    try statement.bindInt(7, accepted.workout.revision);
    try statement.bindText(8, workoutStatusText(accepted.workout.status));
    try statement.done();
}

fn ownRejected(
    allocator: std.mem.Allocator,
    rejected: tracking.RejectedCommand,
) std.mem.Allocator.Error!tracking.CommandResult {
    return .{ .rejected = .{
        .command_id = try ownId(allocator, rejected.command_id),
        .issues = try allocator.dupe(tracking.Issue, rejected.issues),
    } };
}

fn ownAccepted(
    allocator: std.mem.Allocator,
    accepted: tracking.AcceptedCommand,
) std.mem.Allocator.Error!tracking.AcceptedCommand {
    return .{
        .command_id = try ownId(allocator, accepted.command_id),
        .disposition = accepted.disposition,
        .workout = .{
            .id = try ownId(allocator, accepted.workout.id),
            .scope = try ownScope(allocator, accepted.workout.scope),
            .revision = accepted.workout.revision,
            .status = accepted.workout.status,
            .started_at = .{
                .bytes = try allocator.dupe(
                    u8,
                    accepted.workout.started_at.bytes,
                ),
            },
            .completed_at = if (accepted.workout.completed_at) |timestamp|
                .{ .bytes = try allocator.dupe(u8, timestamp.bytes) }
            else
                null,
        },
        .issues = try allocator.dupe(tracking.Issue, accepted.issues),
    };
}

fn ownId(
    allocator: std.mem.Allocator,
    id: tracking.Id,
) std.mem.Allocator.Error!tracking.Id {
    return .{ .bytes = try allocator.dupe(u8, id.bytes) };
}

fn ownScope(
    allocator: std.mem.Allocator,
    scope: tracking.Scope,
) std.mem.Allocator.Error!tracking.Scope {
    return .{
        .host_scope_key = try ownId(allocator, scope.host_scope_key),
        .athlete_id = if (scope.athlete_id) |athlete|
            try ownId(allocator, athlete)
        else
            null,
    };
}

fn athleteKey(scope: tracking.Scope) []const u8 {
    return if (scope.athlete_id) |athlete| athlete.bytes else "";
}

fn workoutStatusText(status: tracking.WorkoutStatus) []const u8 {
    return switch (status) {
        .active => "active",
        .completed => "completed",
    };
}

fn parseWorkoutStatus(value: []const u8) persistence.AdapterError!tracking.WorkoutStatus {
    if (std.mem.eql(u8, value, "active")) return .active;
    if (std.mem.eql(u8, value, "completed")) return .completed;
    return error.InvalidData;
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
