//! Public SQLite adapter for optional Caudex persistence capabilities.
//!
//! Import as `@import("caudex_sqlite")`. SQLite handles, SQL, migrations,
//! statements, and physical schema details are private implementation data.

const std = @import("std");
const builtin = @import("builtin");
const caudex = @import("caudex");
const persistence = @import("caudex_persistence");
const tracking = @import("caudex_tracking");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const adapter_version = "0.1.0";
pub const schema_version: u32 = 8;
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

pub const IntegrityStatus = enum {
    ok,
    corrupt,
};

pub const IntegrityReport = struct {
    status: IntegrityStatus,
};

pub const IntegrityError = error{
    Busy,
    Corrupt,
    OperationFailed,
};

pub const TransferError = error{ DestinationExists, Symlink, Busy, Corrupt, Incompatible, OperationFailed };

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

    /// Checks SQLite's own structural invariants without exposing raw SQLite
    /// diagnostics, which can contain host paths or internal implementation data.
    pub fn integrity(self: *Adapter) IntegrityError!IntegrityReport {
        var query = self.prepare("PRAGMA integrity_check") catch |err| return mapIntegrityError(err);
        defer query.finalize();
        var status: IntegrityStatus = .ok;
        while (query.row() catch |err| return mapIntegrityError(err)) {
            const value = column(query.raw, 0) orelse return error.Corrupt;
            if (!std.mem.eql(u8, value, "ok")) status = .corrupt;
        }
        return .{ .status = status };
    }

    /// Creates a consistent SQLite backup. The destination must be a new regular path.
    pub fn backup(self: *Adapter, io: std.Io, destination: [:0]const u8) TransferError!void {
        try requireNewRegularPath(io, destination);
        try copyToPath(self, io, destination);
    }

    /// Validates a source database before copying it into this open database.
    pub fn restore(self: *Adapter, io: std.Io, source_path: [:0]const u8) TransferError!void {
        try requireExistingRegularPath(io, source_path);
        const source = open(source_path, .{ .create_if_missing = false }) catch |err| return mapTransferOpenError(err);
        defer source.close();
        const report = source.integrity() catch |err| return mapTransferIntegrityError(err);
        if (report.status != .ok) return error.Corrupt;
        try copyDatabase(self, source);
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

    pub fn templateStore(self: *Adapter) persistence.WorkoutTemplateStore {
        return .{ .context = self, .load_fn = loadTemplateCallback, .put_fn = putTemplateCallback };
    }

    pub fn recoveryStore(self: *Adapter) persistence.WorkflowRecoveryStore {
        return .{ .context = self, .load_fn = loadRecoveryCallback, .put_fn = putRecoveryCallback };
    }

    /// Persists a pure workflow-instantiated workout and its immutable
    /// provenance/prescription as one SQLite transaction.
    pub fn saveInstantiatedWorkout(self: *Adapter, allocator: std.mem.Allocator, workout: tracking.Workout) TrackingError!void {
        try self.execute("BEGIN IMMEDIATE");
        errdefer self.execute("ROLLBACK") catch {};
        try insertTrackedWorkout(self, allocator, workout);
        try persistWorkoutState(self, allocator, workout);
        try self.execute("COMMIT");
    }

    pub fn startWorkout(
        self: *Adapter,
        allocator: std.mem.Allocator,
        command: tracking.StartWorkoutCommand,
    ) TrackingError!tracking.CommandResult {
        return startTrackedWorkout(self, allocator, command);
    }

    pub fn completeWorkout(self: *Adapter, allocator: std.mem.Allocator, command: tracking.CompleteWorkoutCommand) TrackingError!tracking.CommandResult {
        return endTrackedWorkout(self, allocator, .{ .complete = command });
    }

    pub fn cancelWorkout(self: *Adapter, allocator: std.mem.Allocator, command: tracking.CancelWorkoutCommand) TrackingError!tracking.CommandResult {
        return endTrackedWorkout(self, allocator, .{ .cancel = command });
    }

    pub fn readWorkout(
        self: *Adapter,
        allocator: std.mem.Allocator,
        query: tracking.ReadWorkoutQuery,
    ) TrackingError!tracking.ReadWorkoutResult {
        return readTrackedWorkout(self, allocator, query);
    }

    pub fn listActiveWorkouts(
        self: *Adapter,
        allocator: std.mem.Allocator,
        query: tracking.ListActiveWorkoutsQuery,
    ) TrackingError!tracking.ActiveWorkoutSelection {
        return listTrackedActiveWorkouts(self, allocator, query);
    }

    pub fn listHistory(self: *Adapter, allocator: std.mem.Allocator, query: tracking.HistoryQuery) TrackingError!tracking.HistoryPage {
        return listTrackedHistory(self, allocator, query);
    }

    pub fn lastPerformance(self: *Adapter, allocator: std.mem.Allocator, query: tracking.LastPerformanceQuery) TrackingError!tracking.LastPerformanceResult {
        return lastTrackedPerformance(self, allocator, query);
    }

    pub fn correctSet(self: *Adapter, allocator: std.mem.Allocator, command: tracking.CorrectSetCommand) TrackingError!tracking.CorrectionResult {
        return correctTrackedSet(self, allocator, command);
    }

    pub fn createExercise(self: *Adapter, allocator: std.mem.Allocator, command: tracking.CreateExerciseCommand) TrackingError!tracking.CatalogCommandResult {
        return changeManagedCatalog(self, allocator, .{ .create = command });
    }

    pub fn editExercise(self: *Adapter, allocator: std.mem.Allocator, command: tracking.EditExerciseCommand) TrackingError!tracking.CatalogCommandResult {
        return changeManagedCatalog(self, allocator, .{ .edit = command });
    }

    pub fn archiveExercise(self: *Adapter, allocator: std.mem.Allocator, command: tracking.ChangeExerciseAvailabilityCommand) TrackingError!tracking.CatalogCommandResult {
        return changeManagedCatalog(self, allocator, .{ .archive = command });
    }

    pub fn restoreExercise(self: *Adapter, allocator: std.mem.Allocator, command: tracking.ChangeExerciseAvailabilityCommand) TrackingError!tracking.CatalogCommandResult {
        return changeManagedCatalog(self, allocator, .{ .restore = command });
    }

    pub fn readManagedExercise(self: *Adapter, allocator: std.mem.Allocator, query: tracking.ReadExerciseQuery) TrackingError!tracking.ReadExerciseResult {
        return readManagedCatalogExercise(self, allocator, query);
    }

    pub fn searchExercises(self: *Adapter, allocator: std.mem.Allocator, query: tracking.SearchExercisesQuery) TrackingError!tracking.SearchExercisesResult {
        return searchManagedCatalog(self, allocator, query);
    }

    pub fn listExercises(self: *Adapter, allocator: std.mem.Allocator, query: tracking.ListExercisesQuery) TrackingError!tracking.ListExercisesResult {
        return listManagedCatalog(self, allocator, query);
    }

    pub fn addExercise(
        self: *Adapter,
        allocator: std.mem.Allocator,
        command: tracking.AddExerciseCommand,
    ) TrackingError!tracking.CommandResult {
        return changeTrackedExercises(self, allocator, .{ .add = command });
    }

    pub fn removeExercise(
        self: *Adapter,
        allocator: std.mem.Allocator,
        command: tracking.RemoveExerciseCommand,
    ) TrackingError!tracking.CommandResult {
        return changeTrackedExercises(self, allocator, .{ .remove = command });
    }

    pub fn reorderExercise(
        self: *Adapter,
        allocator: std.mem.Allocator,
        command: tracking.ReorderExerciseCommand,
    ) TrackingError!tracking.CommandResult {
        return changeTrackedExercises(self, allocator, .{ .reorder = command });
    }

    pub fn addSet(self: *Adapter, allocator: std.mem.Allocator, command: tracking.AddSetCommand) TrackingError!tracking.CommandResult {
        return changeTrackedSets(self, allocator, .{ .add = command });
    }
    pub fn completeSet(self: *Adapter, allocator: std.mem.Allocator, command: tracking.CompleteSetCommand) TrackingError!tracking.CommandResult {
        return changeTrackedSets(self, allocator, .{ .complete = command });
    }
    pub fn logSet(self: *Adapter, allocator: std.mem.Allocator, command: tracking.LogSetCommand) TrackingError!tracking.CommandResult {
        return self.completeSet(allocator, command);
    }
    pub fn skipSet(self: *Adapter, allocator: std.mem.Allocator, command: tracking.SkipSetCommand) TrackingError!tracking.CommandResult {
        return changeTrackedSets(self, allocator, .{ .skip = command });
    }
    pub fn reopenSet(self: *Adapter, allocator: std.mem.Allocator, command: tracking.ReopenSetCommand) TrackingError!tracking.CommandResult {
        return changeTrackedSets(self, allocator, .{ .reopen = command });
    }
    pub fn removeSet(self: *Adapter, allocator: std.mem.Allocator, command: tracking.RemoveSetCommand) TrackingError!tracking.CommandResult {
        return changeTrackedSets(self, allocator, .{ .remove = command });
    }
    pub fn reorderSet(self: *Adapter, allocator: std.mem.Allocator, command: tracking.ReorderSetCommand) TrackingError!tracking.CommandResult {
        return changeTrackedSets(self, allocator, .{ .reorder = command });
    }

    pub fn replaceCatalog(
        self: *Adapter,
        allocator: std.mem.Allocator,
        scope: persistence.CatalogScope,
        exercises: []const persistence.canonical.Exercise,
    ) persistence.CapabilityError!void {
        try self.execute("BEGIN IMMEDIATE");
        errdefer self.execute("ROLLBACK") catch {};

        var archive_statement = try self.prepare(
            "UPDATE catalog SET archived = 1, revision = revision + 1, updated_at = ?2 WHERE host_scope_key = ?1 AND archived = 0",
        );
        defer archive_statement.finalize();
        try archive_statement.bindText(1, scope.host_scope_key);
        try archive_statement.bindText(2, scope.as_of);
        try archive_statement.done();

        var insert_statement = try self.prepare(
            \\INSERT INTO catalog (host_scope_key, exercise_id, payload, archived, revision, updated_at)
            \\VALUES (?1, ?2, ?3, 0, 1, ?4)
            \\ON CONFLICT (host_scope_key, exercise_id) DO UPDATE SET
            \\  payload = excluded.payload,
            \\  archived = 0, revision = catalog.revision + 1,
            \\  updated_at = excluded.updated_at
        );
        defer insert_statement.finalize();
        for (exercises) |exercise| {
            const payload = try encodeAlloc(allocator, exercise);
            defer allocator.free(payload);
            try insert_statement.bindText(1, scope.host_scope_key);
            try insert_statement.bindText(2, exercise.id);
            try insert_statement.bindText(3, payload);
            try insert_statement.bindText(4, scope.as_of);
            try insert_statement.done();
            try insert_statement.reset();
            try self.replaceCatalogSearchTerms(scope.host_scope_key, exercise);
        }
        try self.execute("COMMIT");
    }

    fn changeManagedCatalog(self: *Adapter, allocator: std.mem.Allocator, command: tracking.CatalogCommand) TrackingError!tracking.CatalogCommandResult {
        const payload = try encodeAlloc(allocator, command);
        defer allocator.free(payload);
        const command_metadata, const scope, const exercise_id = switch (command) {
            .create => |value| .{ value.metadata, value.host_scope_key, value.exercise.id },
            .edit => |value| .{ value.metadata, value.host_scope_key, value.exercise.id },
            .archive, .restore => |value| .{ value.metadata, value.host_scope_key, value.exercise_id.bytes },
        };
        try self.execute("BEGIN IMMEDIATE");
        errdefer self.execute("ROLLBACK") catch {};
        if (try self.loadCatalogReceipt(allocator, scope, command_metadata.command_id)) |prior| {
            defer allocator.free(prior);
            if (!std.mem.eql(u8, prior, payload)) {
                const rejected = try ownCatalogRejected(allocator, command_metadata.command_id, .{ .code = tracking.issue_codes.command_payload_conflict, .category = .conflict, .severity = .@"error", .message = "The command ID was already used with another payload." });
                try self.execute("ROLLBACK");
                return rejected;
            }
            const current = (try self.loadManagedExercise(allocator, scope, exercise_id)) orelse return error.InvalidData;
            const accepted = tracking.AcceptedCatalogCommand{ .command_id = try ownId(allocator, command_metadata.command_id), .disposition = .replayed, .exercise = current };
            try self.execute("COMMIT");
            return .{ .accepted = accepted };
        }
        const current = try self.loadManagedExercise(allocator, scope, exercise_id);
        var issues: [1]tracking.Issue = undefined;
        const decided = tracking.applyCatalogCommand(.{ .exercises = if (current) |value| &.{value} else &.{} }, command, &issues) catch return error.InvalidData;
        const accepted = switch (decided) {
            .accepted => |value| value,
            .rejected => |rejected| {
                const owned = try ownCatalogRejected(allocator, rejected.command_id, rejected.issues[0]);
                try self.execute("ROLLBACK");
                return owned;
            },
        };
        try self.persistManagedExercise(allocator, accepted.exercise);
        try self.insertCatalogReceipt(scope, command_metadata.command_id, exercise_id, payload);
        try self.execute("COMMIT");
        return .{ .accepted = try ownAcceptedCatalog(allocator, accepted) };
    }

    fn loadManagedExercise(self: *Adapter, allocator: std.mem.Allocator, scope: tracking.Id, exercise_id: []const u8) TrackingError!?tracking.ManagedExercise {
        var statement = try self.prepare(
            \\SELECT payload, revision, archived, updated_at FROM catalog
            \\WHERE host_scope_key = ?1 AND exercise_id = ?2
        );
        defer statement.finalize();
        try statement.bindText(1, scope.bytes);
        try statement.bindText(2, exercise_id);
        if (!try statement.row()) return null;
        const revision = c.sqlite3_column_int64(statement.raw, 1);
        const archived = c.sqlite3_column_int(statement.raw, 2);
        if (revision <= 0 or (archived != 0 and archived != 1)) return error.InvalidData;
        return .{
            .host_scope_key = try ownId(allocator, scope),
            .exercise = try parseColumn(persistence.canonical.Exercise, allocator, statement.raw, 0),
            .revision = @intCast(revision),
            .availability = if (archived == 0) .active else .archived,
            .updated_at = .{ .bytes = try dupeColumn(allocator, statement.raw, 3) },
        };
    }

    fn persistManagedExercise(self: *Adapter, allocator: std.mem.Allocator, managed: tracking.ManagedExercise) TrackingError!void {
        const payload = try encodeAlloc(allocator, managed.exercise);
        defer allocator.free(payload);
        var statement = try self.prepare(
            \\INSERT INTO catalog (host_scope_key, exercise_id, payload, archived, revision, updated_at)
            \\VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            \\ON CONFLICT (host_scope_key, exercise_id) DO UPDATE SET
            \\ payload = excluded.payload, archived = excluded.archived,
            \\ revision = excluded.revision, updated_at = excluded.updated_at
        );
        defer statement.finalize();
        try statement.bindText(1, managed.host_scope_key.bytes);
        try statement.bindText(2, managed.exercise.id);
        try statement.bindText(3, payload);
        try statement.bindInt(4, @intFromBool(managed.availability == .archived));
        try statement.bindInt(5, managed.revision);
        try statement.bindText(6, managed.updated_at.bytes);
        try statement.done();
        try self.replaceCatalogSearchTerms(managed.host_scope_key.bytes, managed.exercise);
    }

    fn replaceCatalogSearchTerms(self: *Adapter, scope: []const u8, exercise: persistence.canonical.Exercise) TrackingError!void {
        var delete = try self.prepare("DELETE FROM catalog_search_terms WHERE host_scope_key = ?1 AND exercise_id = ?2");
        defer delete.finalize();
        try delete.bindText(1, scope);
        try delete.bindText(2, exercise.id);
        try delete.done();
        var insert = try self.prepare("INSERT OR IGNORE INTO catalog_search_terms (host_scope_key, exercise_id, term) VALUES (?1, ?2, lower(?3))");
        defer insert.finalize();
        try insertSearchTerm(insert, scope, exercise.id, exercise.id);
        if (exercise.name) |name| try insertSearchTerm(insert, scope, exercise.id, name);
        for (exercise.aliases) |alias| try insertSearchTerm(insert, scope, exercise.id, alias);
    }

    fn loadCatalogReceipt(self: *Adapter, allocator: std.mem.Allocator, scope: tracking.Id, command_id: tracking.Id) TrackingError!?[]const u8 {
        var statement = try self.prepare("SELECT payload_json FROM catalog_command_receipts WHERE host_scope_key = ?1 AND command_id = ?2");
        defer statement.finalize();
        try statement.bindText(1, scope.bytes);
        try statement.bindText(2, command_id.bytes);
        if (!try statement.row()) return null;
        return try dupeColumn(allocator, statement.raw, 0);
    }

    fn insertCatalogReceipt(self: *Adapter, scope: tracking.Id, command_id: tracking.Id, exercise_id: []const u8, payload: []const u8) TrackingError!void {
        var statement = try self.prepare("INSERT INTO catalog_command_receipts (host_scope_key, command_id, exercise_id, payload_json) VALUES (?1, ?2, ?3, ?4)");
        defer statement.finalize();
        try statement.bindText(1, scope.bytes);
        try statement.bindText(2, command_id.bytes);
        try statement.bindText(3, exercise_id);
        try statement.bindText(4, payload);
        try statement.done();
    }

    fn readManagedCatalogExercise(self: *Adapter, allocator: std.mem.Allocator, query: tracking.ReadExerciseQuery) TrackingError!tracking.ReadExerciseResult {
        if (try self.loadManagedExercise(allocator, query.host_scope_key, query.exercise_id.bytes)) |value| return .{ .found = value };
        return .{ .not_found = .{ .code = tracking.issue_codes.catalog_exercise_not_found, .category = .not_found, .severity = .@"error", .message = "The exercise does not exist in this scope." } };
    }

    fn searchManagedCatalog(self: *Adapter, allocator: std.mem.Allocator, query: tracking.SearchExercisesQuery) TrackingError!tracking.SearchExercisesResult {
        if (query.text.len == 0 or query.text.len > 200 or !std.unicode.utf8ValidateSlice(query.text) or query.max_results == 0 or query.max_results > 100)
            return .{ .rejected = .{ .code = tracking.issue_codes.catalog_invalid_query, .category = .validation, .severity = .@"error", .message = "Catalog search requires non-empty text and a limit from 1 to 100." } };
        var statement = try self.prepare(
            \\SELECT DISTINCT c.exercise_id FROM catalog_search_terms AS s
            \\JOIN catalog AS c ON c.host_scope_key = s.host_scope_key AND c.exercise_id = s.exercise_id
            \\WHERE s.host_scope_key = ?1 AND s.term >= lower(?2)
            \\ AND s.term < lower(?2) || X'f48fbfbf' AND (?3 = 1 OR c.archived = 0)
            \\ORDER BY c.exercise_id LIMIT ?4
        );
        defer statement.finalize();
        try statement.bindText(1, query.host_scope_key.bytes);
        try statement.bindText(2, query.text);
        try statement.bindInt(3, @intFromBool(query.include_archived));
        try statement.bindInt(4, query.max_results);
        var values: std.ArrayList(tracking.ManagedExercise) = .empty;
        errdefer values.deinit(allocator);
        while (try statement.row()) {
            const id = try dupeColumn(allocator, statement.raw, 0);
            defer allocator.free(id);
            try values.append(allocator, (try self.loadManagedExercise(allocator, query.host_scope_key, id)).?);
        }
        return .{ .found = try values.toOwnedSlice(allocator) };
    }

    fn listManagedCatalog(self: *Adapter, allocator: std.mem.Allocator, query: tracking.ListExercisesQuery) TrackingError!tracking.ListExercisesResult {
        if (query.max_results == 0 or query.max_results > 100)
            return .{ .rejected = .{ .code = tracking.issue_codes.catalog_invalid_query, .category = .validation, .severity = .@"error", .message = "Catalog listing requires a limit from 1 to 100." } };
        var statement = try self.prepare(
            \\SELECT exercise_id FROM catalog
            \\WHERE host_scope_key = ?1 AND (?2 = 1 OR archived = 0)
            \\ORDER BY exercise_id LIMIT ?3
        );
        defer statement.finalize();
        try statement.bindText(1, query.host_scope_key.bytes);
        try statement.bindInt(2, @intFromBool(query.include_archived));
        try statement.bindInt(3, query.max_results);
        var values: std.ArrayList(tracking.ManagedExercise) = .empty;
        errdefer values.deinit(allocator);
        while (try statement.row()) {
            const id = try dupeColumn(allocator, statement.raw, 0);
            defer allocator.free(id);
            try values.append(allocator, (try self.loadManagedExercise(allocator, query.host_scope_key, id)).?);
        }
        return .{ .found = try values.toOwnedSlice(allocator) };
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
        if (current < 3) try self.applyMigration(
            3,
            @embedFile("sqlite/migrations/003_tracking_exercises.sql"),
        );
        if (current < 4) try self.applyMigration(
            4,
            @embedFile("sqlite/migrations/004_tracking_sets.sql"),
        );
        if (current < 5) try self.applyMigration(
            5,
            @embedFile("sqlite/migrations/005_tracking_workout_end.sql"),
        );
        if (current < 6) try self.applyMigration(
            6,
            @embedFile("sqlite/migrations/006_catalog_management.sql"),
        );
        if (current < 7) try self.applyMigration(
            7,
            @embedFile("sqlite/migrations/007_history_queries.sql"),
        );
        if (current < 8) try self.applyMigration(
            8,
            @embedFile("sqlite/migrations/008_workflow_persistence.sql"),
        );
    }

    fn applyMigration(
        self: *Adapter,
        version: u32,
        script: []const u8,
    ) persistence.AdapterError!void {
        try self.execute("BEGIN IMMEDIATE");
        errdefer self.execute("ROLLBACK") catch {};
        const already_applied = blk: {
            var existing = try self.prepare(
                "SELECT 1 FROM schema_migrations WHERE version >= ?1 LIMIT 1",
            );
            defer existing.finalize();
            try existing.bindInt(1, version);
            break :blk try existing.row();
        };
        if (already_applied) {
            try self.execute("COMMIT");
            return;
        }
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

fn insertSearchTerm(statement: Statement, scope: []const u8, exercise_id: []const u8, term: []const u8) TrackingError!void {
    try statement.bindText(1, scope);
    try statement.bindText(2, exercise_id);
    try statement.bindText(3, term);
    try statement.done();
    try statement.reset();
}

fn ownAcceptedCatalog(allocator: std.mem.Allocator, accepted: tracking.AcceptedCatalogCommand) TrackingError!tracking.AcceptedCatalogCommand {
    const payload = try encodeAlloc(allocator, accepted.exercise.exercise);
    defer allocator.free(payload);
    const exercise = std.json.parseFromSliceLeaky(persistence.canonical.Exercise, allocator, payload, .{ .allocate = .alloc_always }) catch return error.InvalidData;
    return .{
        .command_id = try ownId(allocator, accepted.command_id),
        .disposition = accepted.disposition,
        .exercise = .{
            .host_scope_key = try ownId(allocator, accepted.exercise.host_scope_key),
            .exercise = exercise,
            .revision = accepted.exercise.revision,
            .availability = accepted.exercise.availability,
            .updated_at = .{ .bytes = try allocator.dupe(u8, accepted.exercise.updated_at.bytes) },
        },
    };
}

fn ownCatalogRejected(allocator: std.mem.Allocator, command_id: tracking.Id, issue: tracking.Issue) std.mem.Allocator.Error!tracking.CatalogCommandResult {
    const issues = try allocator.alloc(tracking.Issue, 1);
    issues[0] = issue;
    return .{ .rejected = .{ .command_id = try ownId(allocator, command_id), .issues = issues } };
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
    try insertTrackedWorkout(self, allocator, accepted.workout);
    try insertStartReceipt(self, command, accepted);
    try self.execute("COMMIT");
    return .{ .accepted = accepted };
}

fn endTrackedWorkout(
    self: *Adapter,
    allocator: std.mem.Allocator,
    command: tracking.EndWorkoutCommand,
) TrackingError!tracking.CommandResult {
    const payload = try encodeAlloc(allocator, command);
    defer allocator.free(payload);
    const scope, const workout_id, const command_id = switch (command) {
        inline else => |value| .{ value.scope, value.workout_id, value.metadata.command_id },
    };
    try self.execute("BEGIN IMMEDIATE");
    errdefer self.execute("ROLLBACK") catch {};
    if (try loadEndReceipt(self, allocator, scope, command_id)) |prior| {
        if (!std.mem.eql(u8, prior, payload)) {
            var issues = [1]tracking.Issue{.{
                .code = tracking.issue_codes.command_payload_conflict,
                .category = .conflict,
                .severity = .@"error",
                .message = "The command ID was already used with another payload.",
            }};
            const rejected = try ownRejected(allocator, .{ .command_id = command_id, .issues = &issues });
            try self.execute("ROLLBACK");
            return rejected;
        }
        const current = (try loadTrackedWorkout(self, allocator, scope, workout_id)) orelse return error.InvalidData;
        const accepted = try ownAccepted(allocator, .{ .command_id = command_id, .disposition = .replayed, .workout = current });
        try self.execute("COMMIT");
        return .{ .accepted = accepted };
    }
    const current = try loadTrackedWorkout(self, allocator, scope, workout_id);
    var issue_storage: [1]tracking.Issue = undefined;
    const decided = tracking.endWorkout(.{ .workouts = if (current) |value| &.{value} else &.{} }, command, &issue_storage) catch return error.InvalidData;
    const proposed = switch (decided) {
        .accepted => |accepted| accepted,
        .rejected => |rejected| {
            const owned = try ownRejected(allocator, rejected);
            try self.execute("ROLLBACK");
            return owned;
        },
    };
    const accepted = try ownAccepted(allocator, proposed);
    try persistWorkoutState(self, allocator, accepted.workout);
    try insertEndReceipt(self, scope, command_id, workout_id, payload);
    try self.execute("COMMIT");
    return .{ .accepted = accepted };
}

fn loadEndReceipt(self: *Adapter, allocator: std.mem.Allocator, scope: tracking.Scope, command_id: tracking.Id) TrackingError!?[]const u8 {
    var statement = try self.prepare(
        \\SELECT payload_json FROM tracking_workout_end_receipts
        \\WHERE host_scope_key = ?1 AND athlete_id = ?2 AND command_id = ?3
    );
    defer statement.finalize();
    try statement.bindText(1, scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(scope));
    try statement.bindText(3, command_id.bytes);
    if (!try statement.row()) return null;
    return try dupeColumn(allocator, statement.raw, 0);
}

fn insertEndReceipt(self: *Adapter, scope: tracking.Scope, command_id: tracking.Id, workout_id: tracking.Id, payload: []const u8) TrackingError!void {
    var statement = try self.prepare(
        \\INSERT INTO tracking_workout_end_receipts
        \\  (host_scope_key, athlete_id, command_id, workout_id, payload_json)
        \\VALUES (?1, ?2, ?3, ?4, ?5)
    );
    defer statement.finalize();
    try statement.bindText(1, scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(scope));
    try statement.bindText(3, command_id.bytes);
    try statement.bindText(4, workout_id.bytes);
    try statement.bindText(5, payload);
    try statement.done();
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

fn listTrackedActiveWorkouts(
    self: *Adapter,
    allocator: std.mem.Allocator,
    query: tracking.ListActiveWorkoutsQuery,
) TrackingError!tracking.ActiveWorkoutSelection {
    var statement = try self.prepare(
        \\SELECT workout_id FROM tracking_workouts
        \\WHERE host_scope_key = ?1 AND athlete_id = ?2 AND status = 'active'
        \\ORDER BY workout_id
    );
    defer statement.finalize();
    try statement.bindText(1, query.scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(query.scope));
    var matches: std.ArrayList(tracking.Workout) = .empty;
    errdefer matches.deinit(allocator);
    var total: usize = 0;
    var first: ?tracking.Workout = null;
    while (try statement.row()) {
        total += 1;
        const workout_id = tracking.Id{
            .bytes = try dupeColumn(allocator, statement.raw, 0),
        };
        const workout = (try loadTrackedWorkout(
            self,
            allocator,
            query.scope,
            workout_id,
        )) orelse return error.InvalidData;
        if (first == null) first = workout;
        if (matches.items.len < query.max_results)
            try matches.append(allocator, workout);
    }
    if (total == 0) {
        matches.deinit(allocator);
        return .none;
    }
    if (total == 1) {
        matches.deinit(allocator);
        return .{ .one = first.? };
    }
    return .{ .ambiguous = try matches.toOwnedSlice(allocator) };
}

fn listTrackedHistory(self: *Adapter, allocator: std.mem.Allocator, query: tracking.HistoryQuery) TrackingError!tracking.HistoryPage {
    if (query.max_results == 0 or query.max_results > 100) return error.InvalidData;
    if (query.from) |value| _ = tracking.Timestamp.parse(value.bytes) catch return error.InvalidData;
    if (query.through) |value| _ = tracking.Timestamp.parse(value.bytes) catch return error.InvalidData;
    var statement = try self.prepare(
        \\SELECT workout_id FROM tracking_workouts
        \\WHERE host_scope_key = ?1 AND athlete_id = ?2 AND status = 'completed'
        \\ AND (?3 IS NULL OR completed_at >= ?3) AND (?4 IS NULL OR completed_at <= ?4)
        \\ AND (?5 IS NULL OR EXISTS (SELECT 1 FROM tracking_workout_exercises e
        \\   WHERE e.host_scope_key = tracking_workouts.host_scope_key AND e.athlete_id = tracking_workouts.athlete_id
        \\     AND e.workout_id = tracking_workouts.workout_id AND e.exercise_id = ?5))
        \\ AND (?6 IS NULL OR completed_at > ?6 OR (completed_at = ?6 AND workout_id > ?7))
        \\ORDER BY completed_at, workout_id LIMIT ?8
    );
    defer statement.finalize();
    try statement.bindText(1, query.scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(query.scope));
    if (query.from) |value| try statement.bindText(3, value.bytes) else try statement.bindNull(3);
    if (query.through) |value| try statement.bindText(4, value.bytes) else try statement.bindNull(4);
    if (query.exercise_id) |value| try statement.bindText(5, value.bytes) else try statement.bindNull(5);
    if (query.after) |value| {
        try statement.bindText(6, value.completed_at.bytes);
        try statement.bindText(7, value.workout_id.bytes);
    } else {
        try statement.bindNull(6);
        try statement.bindNull(7);
    }
    try statement.bindInt(8, query.max_results);
    var values: std.ArrayList(tracking.Workout) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.row()) {
        const id = tracking.Id{ .bytes = try dupeColumn(allocator, statement.raw, 0) };
        try values.append(allocator, (try loadTrackedWorkout(self, allocator, query.scope, id)).?);
    }
    const workouts = try values.toOwnedSlice(allocator);
    const next: ?tracking.HistoryCursor = if (workouts.len == query.max_results) .{ .completed_at = workouts[workouts.len - 1].completed_at.?, .workout_id = workouts[workouts.len - 1].id } else null;
    return .{ .workouts = workouts, .next = next };
}

fn lastTrackedPerformance(self: *Adapter, allocator: std.mem.Allocator, query: tracking.LastPerformanceQuery) TrackingError!tracking.LastPerformanceResult {
    var statement = try self.prepare(
        \\SELECT w.workout_id FROM tracking_workouts w
        \\WHERE w.host_scope_key = ?1 AND w.athlete_id = ?2 AND w.status = 'completed'
        \\ AND EXISTS (SELECT 1 FROM tracking_workout_exercises e WHERE e.host_scope_key = w.host_scope_key
        \\   AND e.athlete_id = w.athlete_id AND e.workout_id = w.workout_id AND e.exercise_id = ?3)
        \\ORDER BY w.completed_at DESC, w.workout_id DESC LIMIT 1
    );
    defer statement.finalize();
    try statement.bindText(1, query.scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(query.scope));
    try statement.bindText(3, query.exercise_id.bytes);
    if (!try statement.row()) return .{ .not_found = .{ .code = tracking.issue_codes.workout_not_found, .category = .not_found, .severity = .@"error", .message = "No completed performance matched the exercise." } };
    const id = tracking.Id{ .bytes = try dupeColumn(allocator, statement.raw, 0) };
    return .{ .found = (try loadTrackedWorkout(self, allocator, query.scope, id)).? };
}

fn correctTrackedSet(self: *Adapter, allocator: std.mem.Allocator, command: tracking.CorrectSetCommand) TrackingError!tracking.CorrectionResult {
    const payload = try encodeAlloc(allocator, command);
    defer allocator.free(payload);
    try self.execute("BEGIN IMMEDIATE");
    errdefer self.execute("ROLLBACK") catch {};
    var receipt = try self.prepare("SELECT payload_json FROM tracking_correction_receipts WHERE host_scope_key = ?1 AND athlete_id = ?2 AND command_id = ?3");
    defer receipt.finalize();
    try receipt.bindText(1, command.scope.host_scope_key.bytes);
    try receipt.bindText(2, athleteKey(command.scope));
    try receipt.bindText(3, command.metadata.command_id.bytes);
    if (try receipt.row()) {
        const prior = try dupeColumn(allocator, receipt.raw, 0);
        defer allocator.free(prior);
        if (!std.mem.eql(u8, prior, payload)) {
            var issues = [1]tracking.Issue{.{ .code = tracking.issue_codes.command_payload_conflict, .category = .conflict, .severity = .@"error", .message = "The command ID was already used with another payload." }};
            const rejected = try ownRejected(allocator, .{ .command_id = command.metadata.command_id, .issues = &issues });
            try self.execute("ROLLBACK");
            return .{ .rejected = rejected.rejected };
        }
        const current = (try loadTrackedWorkout(self, allocator, command.scope, command.workout_id)) orelse return error.InvalidData;
        try self.execute("COMMIT");
        return .{ .accepted = .{ .command_id = try ownId(allocator, command.metadata.command_id), .disposition = .replayed, .workout = current } };
    }
    const current = (try loadTrackedWorkout(self, allocator, command.scope, command.workout_id)) orelse {
        var issues = [1]tracking.Issue{.{ .code = tracking.issue_codes.workout_not_found, .category = .not_found, .severity = .@"error", .message = "No workout matched the correction." }};
        const owned = try ownRejected(allocator, .{ .command_id = command.metadata.command_id, .issues = &issues });
        try self.execute("ROLLBACK");
        return .{ .rejected = owned.rejected };
    };
    var issues: [1]tracking.Issue = undefined;
    const decision = tracking.validateCorrection(current, command, &issues) catch return error.InvalidData;
    switch (decision) {
        .rejected => |rejected| {
            const owned = try ownRejected(allocator, rejected);
            try self.execute("ROLLBACK");
            return .{ .rejected = owned.rejected };
        },
        .accepted => {},
    }
    const actuals = try encodeAlloc(allocator, command.actual_metrics);
    defer allocator.free(actuals);
    var set_update = try self.prepare(
        \\UPDATE tracking_workout_sets SET actual_metrics_json = ?1, status = ?2, recorded_at = ?3
        \\WHERE host_scope_key = ?4 AND athlete_id = ?5 AND workout_id = ?6 AND membership_id = ?7 AND set_id = ?8
    );
    defer set_update.finalize();
    try set_update.bindText(1, actuals);
    try set_update.bindText(2, setStatusText(command.status));
    try set_update.bindText(3, command.completed_at.bytes);
    try set_update.bindText(4, command.scope.host_scope_key.bytes);
    try set_update.bindText(5, athleteKey(command.scope));
    try set_update.bindText(6, command.workout_id.bytes);
    try set_update.bindText(7, command.membership_id.bytes);
    try set_update.bindText(8, command.set_id.bytes);
    try set_update.done();
    var workout_update = try self.prepare("UPDATE tracking_workouts SET revision = revision + 1 WHERE host_scope_key = ?1 AND athlete_id = ?2 AND workout_id = ?3 AND revision = ?4");
    defer workout_update.finalize();
    try workout_update.bindText(1, command.scope.host_scope_key.bytes);
    try workout_update.bindText(2, athleteKey(command.scope));
    try workout_update.bindText(3, command.workout_id.bytes);
    try workout_update.bindInt(4, command.expected_revision);
    try workout_update.done();
    var insert = try self.prepare("INSERT INTO tracking_correction_receipts (host_scope_key, athlete_id, command_id, workout_id, payload_json) VALUES (?1, ?2, ?3, ?4, ?5)");
    defer insert.finalize();
    try insert.bindText(1, command.scope.host_scope_key.bytes);
    try insert.bindText(2, athleteKey(command.scope));
    try insert.bindText(3, command.metadata.command_id.bytes);
    try insert.bindText(4, command.workout_id.bytes);
    try insert.bindText(5, payload);
    try insert.done();
    const corrected = (try loadTrackedWorkout(self, allocator, command.scope, command.workout_id)) orelse return error.InvalidData;
    try self.execute("COMMIT");
    return .{ .accepted = .{ .command_id = try ownId(allocator, command.metadata.command_id), .disposition = .applied, .workout = corrected } };
}

const ExerciseChange = union(enum) {
    add: tracking.AddExerciseCommand,
    remove: tracking.RemoveExerciseCommand,
    reorder: tracking.ReorderExerciseCommand,

    fn scope(self: ExerciseChange) tracking.Scope {
        return switch (self) {
            inline else => |command| command.scope,
        };
    }

    fn workoutId(self: ExerciseChange) tracking.Id {
        return switch (self) {
            inline else => |command| command.workout_id,
        };
    }
};

fn setChangeScope(change: tracking.SetCommand) tracking.Scope {
    return switch (change) {
        inline else => |command| command.scope,
    };
}

fn setChangeWorkoutId(change: tracking.SetCommand) tracking.Id {
    return switch (change) {
        inline else => |command| command.workout_id,
    };
}

fn setChangeCommandId(change: tracking.SetCommand) tracking.Id {
    return switch (change) {
        inline else => |command| command.metadata.command_id,
    };
}

fn changeTrackedSets(
    self: *Adapter,
    allocator: std.mem.Allocator,
    change: tracking.SetCommand,
) TrackingError!tracking.CommandResult {
    const payload = try encodeAlloc(allocator, change);
    defer allocator.free(payload);
    try self.execute("BEGIN IMMEDIATE");
    errdefer self.execute("ROLLBACK") catch {};
    const scope = setChangeScope(change);
    const workout_id = setChangeWorkoutId(change);
    const command_id = setChangeCommandId(change);

    if (try loadSetReceipt(self, allocator, scope, command_id)) |prior_payload| {
        if (!std.mem.eql(u8, prior_payload, payload)) {
            var issue: [1]tracking.Issue = .{.{
                .code = tracking.issue_codes.command_payload_conflict,
                .category = .conflict,
                .severity = .@"error",
                .message = "The command ID was already used with another payload.",
            }};
            const owned = try ownRejected(allocator, .{
                .command_id = command_id,
                .issues = &issue,
            });
            try self.execute("ROLLBACK");
            return owned;
        }
        const current = (try loadTrackedWorkout(
            self,
            allocator,
            scope,
            workout_id,
        )) orelse return error.InvalidData;
        const accepted = try ownAccepted(allocator, .{
            .command_id = command_id,
            .disposition = .replayed,
            .workout = current,
        });
        try self.execute("COMMIT");
        return .{ .accepted = accepted };
    }

    const workout = try loadTrackedWorkout(self, allocator, scope, workout_id);
    const workouts = if (workout) |value| &.{value} else &.{};
    const exercise_count = if (workout) |value| value.exercises.len else 0;
    var set_count: usize = 0;
    if (workout) |value| {
        const membership_id = switch (change) {
            inline else => |command| command.membership_id,
        };
        if (findTrackedMembership(value.exercises, membership_id)) |index|
            set_count = value.exercises[index].sets.len;
    }
    const exercise_storage = try allocator.alloc(
        tracking.ExerciseMembership,
        exercise_count,
    );
    const set_storage = try allocator.alloc(
        tracking.TrackedSet,
        set_count + switch (change) {
            .add => @as(usize, 1),
            else => 0,
        },
    );
    var issues: [1]tracking.Issue = undefined;
    const decided = tracking.applySetCommand(
        .{ .workouts = workouts },
        change,
        exercise_storage,
        set_storage,
        &issues,
    ) catch |err| switch (err) {
        error.IssueBufferTooSmall,
        error.ExerciseBufferTooSmall,
        error.SetBufferTooSmall,
        error.RevisionOverflow,
        => return error.InvalidData,
    };
    const proposed = switch (decided) {
        .accepted => |accepted| accepted,
        .rejected => |rejected| {
            const owned = try ownRejected(allocator, rejected);
            try self.execute("ROLLBACK");
            return owned;
        },
    };
    const accepted = try ownAccepted(allocator, proposed);
    try persistWorkoutState(self, allocator, accepted.workout);
    try insertSetReceipt(self, scope, command_id, workout_id, payload);
    try self.execute("COMMIT");
    return .{ .accepted = accepted };
}

fn loadSetReceipt(
    self: *Adapter,
    allocator: std.mem.Allocator,
    scope: tracking.Scope,
    command_id: tracking.Id,
) TrackingError!?[]const u8 {
    var statement = try self.prepare(
        \\SELECT payload_json FROM tracking_set_command_receipts
        \\WHERE host_scope_key = ?1 AND athlete_id = ?2 AND command_id = ?3
    );
    defer statement.finalize();
    try statement.bindText(1, scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(scope));
    try statement.bindText(3, command_id.bytes);
    if (!try statement.row()) return null;
    return try dupeColumn(allocator, statement.raw, 0);
}

fn insertSetReceipt(
    self: *Adapter,
    scope: tracking.Scope,
    command_id: tracking.Id,
    workout_id: tracking.Id,
    payload: []const u8,
) persistence.AdapterError!void {
    var statement = try self.prepare(
        \\INSERT INTO tracking_set_command_receipts
        \\  (host_scope_key, athlete_id, command_id, payload_json, workout_id)
        \\VALUES (?1, ?2, ?3, ?4, ?5)
    );
    defer statement.finalize();
    try statement.bindText(1, scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(scope));
    try statement.bindText(3, command_id.bytes);
    try statement.bindText(4, payload);
    try statement.bindText(5, workout_id.bytes);
    try statement.done();
}

fn findTrackedMembership(
    exercises: []const tracking.ExerciseMembership,
    membership_id: tracking.Id,
) ?usize {
    for (exercises, 0..) |membership, index| {
        if (membership.id.eql(membership_id)) return index;
    }
    return null;
}

fn changeTrackedExercises(
    self: *Adapter,
    allocator: std.mem.Allocator,
    change: ExerciseChange,
) TrackingError!tracking.CommandResult {
    try self.execute("BEGIN IMMEDIATE");
    errdefer self.execute("ROLLBACK") catch {};

    const workout = try loadTrackedWorkout(
        self,
        allocator,
        change.scope(),
        change.workoutId(),
    );
    const workouts = if (workout) |value| &.{value} else &.{};
    var catalog_storage: [1]tracking.ExerciseCatalogEntry = undefined;
    const catalog = switch (change) {
        .add => |command| blk: {
            const entry = try loadExerciseCatalogEntry(
                self,
                allocator,
                command.scope.host_scope_key,
                command.exercise_id,
            );
            if (entry) |value| {
                catalog_storage[0] = value;
                break :blk catalog_storage[0..1];
            }
            break :blk catalog_storage[0..0];
        },
        else => catalog_storage[0..0],
    };
    const existing_len = if (workout) |value| value.exercises.len else 0;
    const capacity = existing_len + switch (change) {
        .add => @as(usize, 1),
        else => 0,
    };
    const exercise_storage = try allocator.alloc(
        tracking.ExerciseMembership,
        capacity,
    );
    var issue_storage: [1]tracking.Issue = undefined;
    const decided = switch (change) {
        .add => |command| tracking.addExercise(
            .{ .workouts = workouts, .exercise_catalog = catalog },
            command,
            exercise_storage,
            &issue_storage,
        ),
        .remove => |command| tracking.removeExercise(
            .{ .workouts = workouts },
            command,
            exercise_storage,
            &issue_storage,
        ),
        .reorder => |command| tracking.reorderExercise(
            .{ .workouts = workouts },
            command,
            exercise_storage,
            &issue_storage,
        ),
    } catch |err| switch (err) {
        error.IssueBufferTooSmall,
        error.ExerciseBufferTooSmall,
        error.SetBufferTooSmall,
        error.RevisionOverflow,
        => return error.InvalidData,
    };
    const proposed = switch (decided) {
        .accepted => |accepted| accepted,
        .rejected => |rejected| {
            const owned = try ownRejected(allocator, rejected);
            try self.execute("ROLLBACK");
            return owned;
        },
    };
    const accepted = try ownAccepted(allocator, proposed);
    try persistWorkoutState(self, allocator, accepted.workout);
    try self.execute("COMMIT");
    return .{ .accepted = accepted };
}

fn loadExerciseCatalogEntry(
    self: *Adapter,
    allocator: std.mem.Allocator,
    host_scope_key: tracking.Id,
    exercise_id: tracking.Id,
) TrackingError!?tracking.ExerciseCatalogEntry {
    var statement = try self.prepare(
        \\SELECT archived FROM catalog
        \\WHERE host_scope_key = ?1 AND exercise_id = ?2
    );
    defer statement.finalize();
    try statement.bindText(1, host_scope_key.bytes);
    try statement.bindText(2, exercise_id.bytes);
    if (!try statement.row()) return null;
    const archived = c.sqlite3_column_int(statement.raw, 0);
    if (archived != 0 and archived != 1) return error.InvalidData;
    return .{
        .exercise_id = try ownId(allocator, exercise_id),
        .availability = if (archived == 0) .active else .archived,
    };
}

fn persistWorkoutState(
    self: *Adapter,
    allocator: std.mem.Allocator,
    workout: tracking.Workout,
) persistence.CapabilityError!void {
    const provenance = if (workout.provenance) |value| try encodeAlloc(allocator, value) else null;
    defer if (provenance) |value| allocator.free(value);
    const prescription = try encodeAlloc(allocator, workout.prescription);
    defer allocator.free(prescription);
    var update = try self.prepare(
        \\UPDATE tracking_workouts SET revision = ?1, status = ?2, completed_at = ?3,
        \\ origin = ?7, provenance_json = ?8, prescription_json = ?9
        \\WHERE host_scope_key = ?4 AND athlete_id = ?5 AND workout_id = ?6
    );
    defer update.finalize();
    try update.bindInt(1, workout.revision);
    try update.bindText(2, workoutStatusText(workout.status));
    if (workout.completed_at) |ended| try update.bindText(3, ended.bytes) else try update.bindNull(3);
    try update.bindText(4, workout.scope.host_scope_key.bytes);
    try update.bindText(5, athleteKey(workout.scope));
    try update.bindText(6, workout.id.bytes);
    try update.bindText(7, workoutOriginText(workout.origin));
    if (provenance) |value| try update.bindText(8, value) else try update.bindNull(8);
    try update.bindText(9, prescription);
    try update.done();

    var delete_sets = try self.prepare(
        \\DELETE FROM tracking_workout_sets
        \\WHERE host_scope_key = ?1 AND athlete_id = ?2 AND workout_id = ?3
    );
    defer delete_sets.finalize();
    try delete_sets.bindText(1, workout.scope.host_scope_key.bytes);
    try delete_sets.bindText(2, athleteKey(workout.scope));
    try delete_sets.bindText(3, workout.id.bytes);
    try delete_sets.done();

    var delete = try self.prepare(
        \\DELETE FROM tracking_workout_exercises
        \\WHERE host_scope_key = ?1 AND athlete_id = ?2 AND workout_id = ?3
    );
    defer delete.finalize();
    try delete.bindText(1, workout.scope.host_scope_key.bytes);
    try delete.bindText(2, athleteKey(workout.scope));
    try delete.bindText(3, workout.id.bytes);
    try delete.done();

    var insert = try self.prepare(
        \\INSERT INTO tracking_workout_exercises
        \\  (host_scope_key, athlete_id, workout_id, membership_id,
        \\   exercise_id, ordinal)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6)
    );
    defer insert.finalize();
    for (workout.exercises, 0..) |membership, ordinal| {
        try insert.bindText(1, workout.scope.host_scope_key.bytes);
        try insert.bindText(2, athleteKey(workout.scope));
        try insert.bindText(3, workout.id.bytes);
        try insert.bindText(4, membership.id.bytes);
        try insert.bindText(5, membership.exercise_id.bytes);
        try insert.bindInt(6, ordinal);
        try insert.done();
        try insert.reset();
    }

    var insert_set = try self.prepare(
        \\INSERT INTO tracking_workout_sets
        \\  (host_scope_key, athlete_id, workout_id, membership_id, set_id,
        \\   kind, target_metrics_json, actual_metrics_json, status,
        \\   recorded_at, ordinal)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
    );
    defer insert_set.finalize();
    for (workout.exercises) |membership| {
        for (membership.sets, 0..) |set, ordinal| {
            const targets = try encodeAlloc(allocator, set.target_metrics);
            defer allocator.free(targets);
            const actuals = try encodeAlloc(allocator, set.actual_metrics);
            defer allocator.free(actuals);
            try insert_set.bindText(1, workout.scope.host_scope_key.bytes);
            try insert_set.bindText(2, athleteKey(workout.scope));
            try insert_set.bindText(3, workout.id.bytes);
            try insert_set.bindText(4, membership.id.bytes);
            try insert_set.bindText(5, set.id.bytes);
            try insert_set.bindText(6, set.kind.bytes);
            try insert_set.bindText(7, targets);
            try insert_set.bindText(8, actuals);
            try insert_set.bindText(9, setStatusText(set.status));
            if (set.recorded_at) |recorded|
                try insert_set.bindText(10, recorded.bytes)
            else
                try insert_set.bindNull(10);
            try insert_set.bindInt(11, ordinal);
            try insert_set.done();
            try insert_set.reset();
        }
    }
}

fn loadTrackedWorkout(
    self: *Adapter,
    allocator: std.mem.Allocator,
    scope: tracking.Scope,
    workout_id: tracking.Id,
) TrackingError!?tracking.Workout {
    var statement = try self.prepare(
        \\SELECT revision, status, started_at, completed_at, origin,
        \\ provenance_json, prescription_json
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
    const exercises = try loadTrackedExercises(self, allocator, scope, workout_id);
    const origin = try parseWorkoutOrigin(column(statement.raw, 4) orelse return error.InvalidData);
    const provenance: ?tracking.Provenance = if (column(statement.raw, 5) != null)
        try parseColumn(tracking.Provenance, allocator, statement.raw, 5)
    else
        null;
    const prescription = try parseColumn([]const tracking.PrescribedExercise, allocator, statement.raw, 6);
    return .{
        .id = try ownId(allocator, workout_id),
        .scope = try ownScope(allocator, scope),
        .revision = @intCast(revision),
        .status = status,
        .started_at = started_at,
        .completed_at = completed_at,
        .exercises = exercises,
        .origin = origin,
        .provenance = provenance,
        .prescription = prescription,
    };
}

fn loadTrackedExercises(
    self: *Adapter,
    allocator: std.mem.Allocator,
    scope: tracking.Scope,
    workout_id: tracking.Id,
) TrackingError![]const tracking.ExerciseMembership {
    var statement = try self.prepare(
        \\SELECT membership_id, exercise_id
        \\FROM tracking_workout_exercises
        \\WHERE host_scope_key = ?1 AND athlete_id = ?2 AND workout_id = ?3
        \\ORDER BY ordinal
    );
    defer statement.finalize();
    try statement.bindText(1, scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(scope));
    try statement.bindText(3, workout_id.bytes);
    var values: std.ArrayList(tracking.ExerciseMembership) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.row()) {
        const membership_id = tracking.Id{
            .bytes = try dupeColumn(allocator, statement.raw, 0),
        };
        const exercise_id = tracking.Id{
            .bytes = try dupeColumn(allocator, statement.raw, 1),
        };
        _ = tracking.Id.parse(membership_id.bytes) catch return error.InvalidData;
        _ = tracking.Id.parse(exercise_id.bytes) catch return error.InvalidData;
        try values.append(allocator, .{
            .id = membership_id,
            .exercise_id = exercise_id,
            .sets = try loadTrackedSets(
                self,
                allocator,
                scope,
                workout_id,
                membership_id,
            ),
        });
    }
    return values.toOwnedSlice(allocator);
}

fn loadTrackedSets(
    self: *Adapter,
    allocator: std.mem.Allocator,
    scope: tracking.Scope,
    workout_id: tracking.Id,
    membership_id: tracking.Id,
) TrackingError![]const tracking.TrackedSet {
    var statement = try self.prepare(
        \\SELECT set_id, kind, target_metrics_json, actual_metrics_json,
        \\       status, recorded_at
        \\FROM tracking_workout_sets
        \\WHERE host_scope_key = ?1 AND athlete_id = ?2 AND workout_id = ?3
        \\  AND membership_id = ?4
        \\ORDER BY ordinal
    );
    defer statement.finalize();
    try statement.bindText(1, scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(scope));
    try statement.bindText(3, workout_id.bytes);
    try statement.bindText(4, membership_id.bytes);
    var values: std.ArrayList(tracking.TrackedSet) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.row()) {
        const recorded = column(statement.raw, 5);
        try values.append(allocator, .{
            .id = .{ .bytes = try dupeColumn(allocator, statement.raw, 0) },
            .kind = .{ .bytes = try dupeColumn(allocator, statement.raw, 1) },
            .target_metrics = try parseColumn(
                []const tracking.Metric,
                allocator,
                statement.raw,
                2,
            ),
            .actual_metrics = try parseColumn(
                []const tracking.Metric,
                allocator,
                statement.raw,
                3,
            ),
            .status = try parseSetStatus(
                column(statement.raw, 4) orelse return error.InvalidData,
            ),
            .recorded_at = if (recorded) |value|
                .{ .bytes = try allocator.dupe(u8, value) }
            else
                null,
        });
    }
    return values.toOwnedSlice(allocator);
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
    allocator: std.mem.Allocator,
    workout: tracking.Workout,
) persistence.CapabilityError!void {
    const provenance = if (workout.provenance) |value| try encodeAlloc(allocator, value) else null;
    defer if (provenance) |value| allocator.free(value);
    const prescription = try encodeAlloc(allocator, workout.prescription);
    defer allocator.free(prescription);
    var statement = try self.prepare(
        \\INSERT INTO tracking_workouts
        \\  (host_scope_key, athlete_id, workout_id, revision, status,
        \\   started_at, completed_at, origin, provenance_json, prescription_json)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL, ?7, ?8, ?9)
    );
    defer statement.finalize();
    try statement.bindText(1, workout.scope.host_scope_key.bytes);
    try statement.bindText(2, athleteKey(workout.scope));
    try statement.bindText(3, workout.id.bytes);
    try statement.bindInt(4, workout.revision);
    try statement.bindText(5, workoutStatusText(workout.status));
    try statement.bindText(6, workout.started_at.bytes);
    try statement.bindText(7, workoutOriginText(workout.origin));
    if (provenance) |value| try statement.bindText(8, value) else try statement.bindNull(8);
    try statement.bindText(9, prescription);
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
            .exercises = try ownExerciseMemberships(
                allocator,
                accepted.workout.exercises,
            ),
        },
        .issues = try allocator.dupe(tracking.Issue, accepted.issues),
    };
}

fn ownExerciseMemberships(
    allocator: std.mem.Allocator,
    memberships: []const tracking.ExerciseMembership,
) std.mem.Allocator.Error![]const tracking.ExerciseMembership {
    const owned = try allocator.alloc(tracking.ExerciseMembership, memberships.len);
    for (memberships, 0..) |membership, index| {
        owned[index] = .{
            .id = try ownId(allocator, membership.id),
            .exercise_id = try ownId(allocator, membership.exercise_id),
            .sets = try ownTrackedSets(allocator, membership.sets),
        };
    }
    return owned;
}

fn ownTrackedSets(
    allocator: std.mem.Allocator,
    sets: []const tracking.TrackedSet,
) std.mem.Allocator.Error![]const tracking.TrackedSet {
    const owned = try allocator.alloc(tracking.TrackedSet, sets.len);
    for (sets, 0..) |set, index| {
        owned[index] = .{
            .id = try ownId(allocator, set.id),
            .kind = try ownId(allocator, set.kind),
            .target_metrics = try ownMetrics(allocator, set.target_metrics),
            .actual_metrics = try ownMetrics(allocator, set.actual_metrics),
            .status = set.status,
            .recorded_at = if (set.recorded_at) |timestamp|
                .{ .bytes = try allocator.dupe(u8, timestamp.bytes) }
            else
                null,
        };
    }
    return owned;
}

fn ownMetrics(
    allocator: std.mem.Allocator,
    metrics: []const tracking.Metric,
) std.mem.Allocator.Error![]const tracking.Metric {
    const owned = try allocator.alloc(tracking.Metric, metrics.len);
    for (metrics, 0..) |metric, index| {
        owned[index] = metric;
        owned[index].code = try ownId(allocator, metric.code);
    }
    return owned;
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
        .cancelled => "cancelled",
    };
}

fn workoutOriginText(origin: tracking.WorkoutOrigin) []const u8 {
    return switch (origin) {
        .manual => "manual",
        .template => "template",
        .recommendation => "recommendation",
    };
}

fn parseWorkoutOrigin(value: []const u8) persistence.AdapterError!tracking.WorkoutOrigin {
    if (std.mem.eql(u8, value, "manual")) return .manual;
    if (std.mem.eql(u8, value, "template")) return .template;
    if (std.mem.eql(u8, value, "recommendation")) return .recommendation;
    return error.InvalidData;
}

fn parseWorkoutStatus(value: []const u8) persistence.AdapterError!tracking.WorkoutStatus {
    if (std.mem.eql(u8, value, "active")) return .active;
    if (std.mem.eql(u8, value, "completed")) return .completed;
    if (std.mem.eql(u8, value, "cancelled")) return .cancelled;
    return error.InvalidData;
}

fn setStatusText(status: tracking.SetStatus) []const u8 {
    return @tagName(status);
}

fn parseSetStatus(value: []const u8) persistence.AdapterError!tracking.SetStatus {
    inline for (std.meta.fields(tracking.SetStatus)) |field| {
        if (std.mem.eql(u8, value, field.name))
            return @enumFromInt(field.value);
    }
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

    fn bindNull(self: Statement, index: c_int) persistence.AdapterError!void {
        const status = c.sqlite3_bind_null(self.raw, index);
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

fn loadTemplateCallback(context: *anyopaque, allocator: std.mem.Allocator, key: persistence.TemplateKey) persistence.CapabilityError!?persistence.TemplateRecord {
    const self: *Adapter = @ptrCast(@alignCast(context));
    var statement = try self.prepare("SELECT payload_json FROM workout_templates WHERE host_scope_key = ?1 AND template_id = ?2");
    defer statement.finalize();
    try statement.bindText(1, key.host_scope_key);
    try statement.bindText(2, key.template_id);
    if (!try statement.row()) return null;
    return .{
        .host_scope_key = try allocator.dupe(u8, key.host_scope_key),
        .template = try parseColumn(persistence.canonical.WorkoutTemplate, allocator, statement.raw, 0),
    };
}

fn putTemplateCallback(context: *anyopaque, allocator: std.mem.Allocator, change: persistence.PutTemplate) persistence.StateStoreError!persistence.TemplateRecord {
    const self: *Adapter = @ptrCast(@alignCast(context));
    try self.execute("BEGIN IMMEDIATE");
    errdefer self.execute("ROLLBACK") catch {};
    var query = try self.prepare("SELECT revision FROM workout_templates WHERE host_scope_key = ?1 AND template_id = ?2");
    defer query.finalize();
    try query.bindText(1, change.record.host_scope_key);
    try query.bindText(2, change.record.template.id);
    const exists = try query.row();
    const actual: ?u64 = if (exists) @intCast(c.sqlite3_column_int64(query.raw, 0)) else null;
    if (actual != change.expected_revision) {
        try self.execute("ROLLBACK");
        return error.Conflict;
    }
    const payload = try encodeAlloc(allocator, change.record.template);
    defer allocator.free(payload);
    var statement = try self.prepare(
        \\INSERT INTO workout_templates (host_scope_key, template_id, revision, payload_json)
        \\VALUES (?1, ?2, ?3, ?4)
        \\ON CONFLICT (host_scope_key, template_id) DO UPDATE SET
        \\ revision = excluded.revision, payload_json = excluded.payload_json
    );
    defer statement.finalize();
    try statement.bindText(1, change.record.host_scope_key);
    try statement.bindText(2, change.record.template.id);
    try statement.bindInt(3, change.record.template.revision);
    try statement.bindText(4, payload);
    try statement.done();
    try self.execute("COMMIT");
    return (try loadTemplateCallback(context, allocator, .{ .host_scope_key = change.record.host_scope_key, .template_id = change.record.template.id })).?;
}

fn loadRecoveryCallback(context: *anyopaque, allocator: std.mem.Allocator, key: persistence.WorkflowRecoveryKey) persistence.CapabilityError!?persistence.WorkflowRecoveryRecord {
    const self: *Adapter = @ptrCast(@alignCast(context));
    var statement = try self.prepare(
        \\SELECT kind, status, idempotency_key, payload_json, updated_at
        \\FROM workflow_recovery WHERE host_scope_key = ?1 AND workflow_id = ?2
    );
    defer statement.finalize();
    try statement.bindText(1, key.host_scope_key);
    try statement.bindText(2, key.workflow_id);
    if (!try statement.row()) return null;
    const status_value = column(statement.raw, 1) orelse return error.InvalidData;
    const status: persistence.WorkflowRecoveryStatus = if (std.mem.eql(u8, status_value, "pending")) .pending else if (std.mem.eql(u8, status_value, "completed")) .completed else return error.InvalidData;
    return .{
        .key = .{ .host_scope_key = try allocator.dupe(u8, key.host_scope_key), .workflow_id = try allocator.dupe(u8, key.workflow_id) },
        .kind = try dupeColumn(allocator, statement.raw, 0),
        .status = status,
        .idempotency_key = try dupeColumn(allocator, statement.raw, 2),
        .payload_json = try dupeColumn(allocator, statement.raw, 3),
        .updated_at = try dupeColumn(allocator, statement.raw, 4),
    };
}

fn putRecoveryCallback(context: *anyopaque, record: persistence.WorkflowRecoveryRecord) persistence.AdapterError!void {
    const self: *Adapter = @ptrCast(@alignCast(context));
    var statement = try self.prepare(
        \\INSERT INTO workflow_recovery
        \\ (host_scope_key, workflow_id, kind, status, idempotency_key, payload_json, updated_at)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
        \\ON CONFLICT (host_scope_key, workflow_id) DO UPDATE SET
        \\ kind = excluded.kind, status = excluded.status,
        \\ idempotency_key = excluded.idempotency_key,
        \\ payload_json = excluded.payload_json, updated_at = excluded.updated_at
    );
    defer statement.finalize();
    try statement.bindText(1, record.key.host_scope_key);
    try statement.bindText(2, record.key.workflow_id);
    try statement.bindText(3, record.kind);
    try statement.bindText(4, if (record.status == .pending) "pending" else "completed");
    try statement.bindText(5, record.idempotency_key);
    try statement.bindText(6, record.payload_json);
    try statement.bindText(7, record.updated_at);
    try statement.done();
}

fn loadCatalogCallback(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    scope: persistence.CatalogScope,
) persistence.CapabilityError![]const persistence.canonical.Exercise {
    const self: *Adapter = @ptrCast(@alignCast(context));
    var statement = try self.prepare(
        \\SELECT payload FROM catalog
        \\WHERE host_scope_key = ?1 AND archived = 0
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

fn mapIntegrityError(err: persistence.AdapterError) IntegrityError {
    return switch (err) {
        error.Unavailable => error.Busy,
        error.InvalidData => error.Corrupt,
        error.UnsupportedVersion, error.OperationFailed => error.OperationFailed,
    };
}

fn requireNewRegularPath(io: std.Io, path: []const u8) TransferError!void {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return error.OperationFailed,
    };
    if (stat.kind == .sym_link) return error.Symlink;
    return error.DestinationExists;
}

fn requireExistingRegularPath(io: std.Io, path: []const u8) TransferError!void {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch return error.OperationFailed;
    if (stat.kind == .sym_link) return error.Symlink;
    if (stat.kind != .file) return error.Incompatible;
}

fn copyToPath(source: *Adapter, io: std.Io, destination: [:0]const u8) TransferError!void {
    var target_raw: ?*c.sqlite3 = null;
    const status = c.sqlite3_open_v2(destination.ptr, &target_raw, c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX, null);
    if (status != c.SQLITE_OK or target_raw == null) return mapTransferStatus(status);
    defer _ = c.sqlite3_close(target_raw.?);
    if (builtin.os.tag != .windows) {
        std.Io.Dir.cwd().setFilePermissions(io, destination, std.Io.File.Permissions.fromMode(0o600), .{ .follow_symlinks = false }) catch return error.OperationFailed;
    }
    try copyRaw(target_raw.?, raw(source));
}

fn copyDatabase(destination: *Adapter, source: *Adapter) TransferError!void {
    try copyRaw(raw(destination), raw(source));
}

fn copyRaw(destination: *c.sqlite3, source: *c.sqlite3) TransferError!void {
    const backup = c.sqlite3_backup_init(destination, "main", source, "main") orelse return error.OperationFailed;
    defer _ = c.sqlite3_backup_finish(backup);
    const status = c.sqlite3_backup_step(backup, -1);
    if (status != c.SQLITE_DONE) return mapTransferStatus(status);
}

fn mapTransferStatus(status: c_int) TransferError {
    return switch (status) {
        c.SQLITE_BUSY, c.SQLITE_LOCKED => error.Busy,
        c.SQLITE_CORRUPT, c.SQLITE_NOTADB => error.Corrupt,
        else => error.OperationFailed,
    };
}

fn mapTransferOpenError(err: OpenError) TransferError {
    return switch (err) {
        error.Busy => error.Busy,
        error.Corrupt => error.Corrupt,
        error.UnsupportedSchema, error.MigrationFailed => error.Incompatible,
        error.OpenFailed => error.OperationFailed,
    };
}

fn mapTransferIntegrityError(err: IntegrityError) TransferError {
    return switch (err) {
        error.Busy => error.Busy,
        error.Corrupt => error.Corrupt,
        error.OperationFailed => error.OperationFailed,
    };
}
