const std = @import("std");
const persistence = @import("caudex_persistence");

pub const canonical = persistence.canonical;

pub const ContractError = persistence.StateStoreError || error{
    CatalogMismatch,
    HistoryMismatch,
    HistoryOutOfOrder,
    MissingScopeReturnedData,
    StateMismatch,
    ConflictNotReported,
    CanonicalMismatch,
    RollbackMismatch,
    TemplateMismatch,
    RecoveryMismatch,
    SerializationFailed,
};

pub const Fixture = struct {
    host_scope_key: []const u8,
    catalog: []const canonical.Exercise,
    history: canonical.HistorySnapshot,
};

/// A database-independent test double. Fixture values must outlive the double.
/// Returned top-level slices are copied into the caller's allocator.
pub const InMemoryAdapter = struct {
    fixture: Fixture,
    state: ?persistence.MethodologyStateRecord = null,
    revision_number: u64 = 0,
    revision_buffer: [20]u8 = undefined,
    transaction_snapshot: ?persistence.MethodologyStateRecord = null,
    transaction_active: bool = false,
    template: ?persistence.TemplateRecord = null,
    recovery: ?persistence.WorkflowRecoveryRecord = null,

    pub fn catalogSource(self: *InMemoryAdapter) persistence.CatalogSource {
        return .{ .context = self, .load_fn = loadCatalog };
    }

    pub fn historySource(self: *InMemoryAdapter) persistence.HistorySource {
        return .{ .context = self, .load_fn = loadHistory };
    }

    pub fn stateStore(self: *InMemoryAdapter) persistence.MethodologyStateStore {
        return .{
            .context = self,
            .load_fn = loadState,
            .compare_and_set_fn = compareAndSetState,
        };
    }

    pub fn templateStore(self: *InMemoryAdapter) persistence.WorkoutTemplateStore {
        return .{ .context = self, .load_fn = loadTemplate, .put_fn = putTemplate };
    }

    pub fn recoveryStore(self: *InMemoryAdapter) persistence.WorkflowRecoveryStore {
        return .{ .context = self, .load_fn = loadRecovery, .put_fn = putRecovery };
    }

    pub fn beginTransaction(self: *InMemoryAdapter) void {
        std.debug.assert(!self.transaction_active);
        self.transaction_snapshot = self.state;
        self.transaction_active = true;
    }

    pub fn rollback(self: *InMemoryAdapter) void {
        std.debug.assert(self.transaction_active);
        self.state = self.transaction_snapshot;
        self.transaction_snapshot = null;
        self.transaction_active = false;
    }

    fn loadCatalog(
        context: *anyopaque,
        allocator: std.mem.Allocator,
        scope: persistence.CatalogScope,
    ) persistence.CapabilityError![]const canonical.Exercise {
        const self: *InMemoryAdapter = @ptrCast(@alignCast(context));
        if (!std.mem.eql(u8, scope.host_scope_key, self.fixture.host_scope_key))
            return allocator.alloc(canonical.Exercise, 0);
        return allocator.dupe(canonical.Exercise, self.fixture.catalog);
    }

    fn loadHistory(
        context: *anyopaque,
        allocator: std.mem.Allocator,
        query: persistence.HistoryQuery,
    ) persistence.CapabilityError!canonical.HistorySnapshot {
        const self: *InMemoryAdapter = @ptrCast(@alignCast(context));
        if (!std.mem.eql(u8, query.host_scope_key, self.fixture.host_scope_key))
            return .{};
        const workouts = try allocator.dupe(
            canonical.CompletedWorkout,
            self.fixture.history.workouts,
        );
        std.mem.sort(
            canonical.CompletedWorkout,
            workouts,
            {},
            struct {
                fn lessThan(
                    _: void,
                    left: canonical.CompletedWorkout,
                    right: canonical.CompletedWorkout,
                ) bool {
                    return std.mem.order(
                        u8,
                        left.completedAt,
                        right.completedAt,
                    ) == .lt;
                }
            }.lessThan,
        );
        return .{
            .workouts = workouts,
            .summaries = self.fixture.history.summaries,
        };
    }

    fn loadState(
        context: *anyopaque,
        _: std.mem.Allocator,
        key: persistence.MethodologyStateKey,
    ) persistence.CapabilityError!?persistence.MethodologyStateRecord {
        const self: *InMemoryAdapter = @ptrCast(@alignCast(context));
        const record = self.state orelse return null;
        if (!keysEqual(record.key, key)) return null;
        return record;
    }

    fn compareAndSetState(
        context: *anyopaque,
        _: std.mem.Allocator,
        change: persistence.CompareAndSetMethodologyState,
    ) persistence.StateStoreError!persistence.MethodologyStateRecord {
        const self: *InMemoryAdapter = @ptrCast(@alignCast(context));
        const current = if (self.state) |record|
            if (keysEqual(record.key, change.key)) record else null
        else
            null;
        const current_revision = if (current) |record| record.revision else null;
        if (!optionalStringsEqual(current_revision, change.expected_revision))
            return error.Conflict;

        self.revision_number += 1;
        const revision = std.fmt.bufPrint(
            &self.revision_buffer,
            "{d}",
            .{self.revision_number},
        ) catch unreachable;
        self.state = .{
            .key = change.key,
            .methodology_version = change.methodology_version,
            .state = change.next_state,
            .revision = revision,
            .updated_at = change.updated_at,
        };
        return self.state.?;
    }

    fn loadTemplate(
        context: *anyopaque,
        _: std.mem.Allocator,
        key: persistence.TemplateKey,
    ) persistence.CapabilityError!?persistence.TemplateRecord {
        const self: *InMemoryAdapter = @ptrCast(@alignCast(context));
        const record = self.template orelse return null;
        if (!std.mem.eql(u8, record.host_scope_key, key.host_scope_key) or
            !std.mem.eql(u8, record.template.id, key.template_id)) return null;
        return record;
    }

    fn putTemplate(
        context: *anyopaque,
        _: std.mem.Allocator,
        change: persistence.PutTemplate,
    ) persistence.StateStoreError!persistence.TemplateRecord {
        const self: *InMemoryAdapter = @ptrCast(@alignCast(context));
        const actual_revision: ?u64 = if (self.template) |record| record.template.revision else null;
        if (actual_revision != change.expected_revision) return error.Conflict;
        self.template = change.record;
        return change.record;
    }

    fn loadRecovery(
        context: *anyopaque,
        _: std.mem.Allocator,
        key: persistence.WorkflowRecoveryKey,
    ) persistence.CapabilityError!?persistence.WorkflowRecoveryRecord {
        const self: *InMemoryAdapter = @ptrCast(@alignCast(context));
        const record = self.recovery orelse return null;
        if (!std.mem.eql(u8, record.key.host_scope_key, key.host_scope_key) or
            !std.mem.eql(u8, record.key.workflow_id, key.workflow_id)) return null;
        return record;
    }

    fn putRecovery(
        context: *anyopaque,
        record: persistence.WorkflowRecoveryRecord,
    ) persistence.AdapterError!void {
        const self: *InMemoryAdapter = @ptrCast(@alignCast(context));
        if (self.recovery) |existing| {
            if (std.mem.eql(u8, existing.key.host_scope_key, record.key.host_scope_key) and
                std.mem.eql(u8, existing.idempotency_key, record.idempotency_key) and
                !std.mem.eql(u8, existing.key.workflow_id, record.key.workflow_id))
                return error.InvalidData;
        }
        self.recovery = record;
    }
};

pub const TransactionProbe = struct {
    context: *anyopaque,
    begin_fn: *const fn (*anyopaque) void,
    rollback_fn: *const fn (*anyopaque) void,
};

pub fn verifySources(
    allocator: std.mem.Allocator,
    catalog_source: persistence.CatalogSource,
    history_source: persistence.HistorySource,
    fixture: Fixture,
) ContractError!void {
    const catalog = try catalog_source.load(allocator, .{
        .host_scope_key = fixture.host_scope_key,
        .as_of = "9999-12-31T23:59:59Z",
    });
    if (catalog.len != fixture.catalog.len) return error.CatalogMismatch;

    const history = try history_source.load(allocator, .{
        .host_scope_key = fixture.host_scope_key,
        .through = "9999-12-31T23:59:59Z",
    });
    if (history.workouts.len != fixture.history.workouts.len)
        return error.HistoryMismatch;
    for (history.workouts[1..], history.workouts[0 .. history.workouts.len - 1]) |
        current,
        previous,
    | {
        if (std.mem.order(u8, previous.completedAt, current.completedAt) == .gt)
            return error.HistoryOutOfOrder;
    }

    const missing_catalog = try catalog_source.load(allocator, .{
        .host_scope_key = "__caudex_missing_scope__",
        .as_of = "9999-12-31T23:59:59Z",
    });
    const missing_history = try history_source.load(allocator, .{
        .host_scope_key = "__caudex_missing_scope__",
        .through = "9999-12-31T23:59:59Z",
    });
    if (missing_catalog.len != 0 or missing_history.workouts.len != 0)
        return error.MissingScopeReturnedData;
}

pub fn verifyStateStore(
    allocator: std.mem.Allocator,
    store: persistence.MethodologyStateStore,
    key: persistence.MethodologyStateKey,
    state: canonical.MethodologyState,
) ContractError!void {
    if (try store.load(allocator, key) != null) return error.StateMismatch;
    const created = try store.compareAndSet(allocator, .{
        .key = key,
        .expected_revision = null,
        .methodology_version = "0.1.0",
        .next_state = state,
        .updated_at = "2026-07-26T12:00:00Z",
    });
    const loaded = (try store.load(allocator, key)) orelse
        return error.StateMismatch;
    if (!std.mem.eql(u8, created.revision, loaded.revision) or
        loaded.state.schemaVersion != state.schemaVersion or
        !std.mem.eql(u8, loaded.methodology_version, "0.1.0"))
        return error.StateMismatch;

    if (store.compareAndSet(allocator, .{
        .key = key,
        .expected_revision = null,
        .methodology_version = "0.1.0",
        .next_state = state,
        .updated_at = "2026-07-26T12:01:00Z",
    })) |_| {
        return error.ConflictNotReported;
    } else |err| switch (err) {
        error.Conflict => {},
        else => return err,
    }
    if ((try store.load(allocator, key)).?.revision.len == 0)
        return error.StateMismatch;
}

pub fn verifyTemplateStore(
    allocator: std.mem.Allocator,
    store: persistence.WorkoutTemplateStore,
    record: persistence.TemplateRecord,
) ContractError!void {
    const key: persistence.TemplateKey = .{
        .host_scope_key = record.host_scope_key,
        .template_id = record.template.id,
    };
    if (try store.load(allocator, key) != null) return error.TemplateMismatch;
    _ = try store.put(allocator, .{ .record = record, .expected_revision = null });
    const loaded = (try store.load(allocator, key)) orelse return error.TemplateMismatch;
    if (!std.mem.eql(u8, loaded.template.id, record.template.id) or
        loaded.template.revision != record.template.revision)
        return error.TemplateMismatch;
    if (store.put(allocator, .{ .record = record, .expected_revision = null })) |_| {
        return error.ConflictNotReported;
    } else |err| switch (err) {
        error.Conflict => {},
        else => return err,
    }
}

pub fn verifyRecoveryStore(
    allocator: std.mem.Allocator,
    store: persistence.WorkflowRecoveryStore,
    pending: persistence.WorkflowRecoveryRecord,
) ContractError!void {
    if (try store.load(allocator, pending.key) != null) return error.RecoveryMismatch;
    try store.put(pending);
    const loaded = (try store.load(allocator, pending.key)) orelse return error.RecoveryMismatch;
    if (loaded.status != .pending or
        !std.mem.eql(u8, loaded.idempotency_key, pending.idempotency_key) or
        !std.mem.eql(u8, loaded.payload_json, pending.payload_json))
        return error.RecoveryMismatch;
    var completed = pending;
    completed.status = .completed;
    try store.put(completed);
    const final = (try store.load(allocator, pending.key)) orelse return error.RecoveryMismatch;
    if (final.status != .completed) return error.RecoveryMismatch;
}

pub fn verifyCanonicalEquivalence(
    allocator: std.mem.Allocator,
    host_scope_key: []const u8,
    direct: canonical.RecommendationRequest,
    catalog_source: persistence.CatalogSource,
    history_source: persistence.HistorySource,
) ContractError!void {
    const loaded_catalog = try catalog_source.load(allocator, .{
        .host_scope_key = host_scope_key,
        .as_of = direct.asOf,
    });
    const loaded_history = try history_source.load(allocator, .{
        .host_scope_key = host_scope_key,
        .through = direct.asOf,
    });
    var adapter_request = direct;
    adapter_request.catalog = loaded_catalog;
    adapter_request.history = loaded_history;

    var direct_buffer: [8192]u8 = undefined;
    var adapter_buffer: [8192]u8 = undefined;
    const direct_json = stringify(direct, &direct_buffer) catch
        return error.SerializationFailed;
    const adapter_json = stringify(adapter_request, &adapter_buffer) catch
        return error.SerializationFailed;
    if (!std.mem.eql(u8, direct_json, adapter_json))
        return error.CanonicalMismatch;
}

pub fn verifyRollbackWhenAdvertised(
    allocator: std.mem.Allocator,
    store: persistence.MethodologyStateStore,
    probe: ?TransactionProbe,
    key: persistence.MethodologyStateKey,
    state: canonical.MethodologyState,
) ContractError!void {
    const transaction = probe orelse return;
    transaction.begin_fn(transaction.context);
    _ = try store.compareAndSet(allocator, .{
        .key = key,
        .expected_revision = null,
        .methodology_version = "0.1.0",
        .next_state = state,
        .updated_at = "2026-07-26T12:00:00Z",
    });
    transaction.rollback_fn(transaction.context);
    if (try store.load(allocator, key) != null) return error.RollbackMismatch;
}

fn stringify(value: anytype, buffer: []u8) ![]const u8 {
    var writer: std.Io.Writer = .fixed(buffer);
    try std.json.Stringify.value(
        value,
        .{ .emit_null_optional_fields = false },
        &writer,
    );
    return writer.buffered();
}

fn keysEqual(
    left: persistence.MethodologyStateKey,
    right: persistence.MethodologyStateKey,
) bool {
    return std.mem.eql(u8, left.host_scope_key, right.host_scope_key) and
        std.mem.eql(u8, left.methodology_id, right.methodology_id);
}

fn optionalStringsEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}
