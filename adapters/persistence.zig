//! Database-independent capability contracts for optional Caudex persistence
//! adapters.
//!
//! Import this public package as `@import("caudex_persistence")`. The package
//! depends only on the public `caudex` package; it performs no I/O and provides
//! no database implementation.

const std = @import("std");
const caudex = @import("caudex");

pub const canonical = caudex.canonical;
pub const contract_version: u32 = 2;

pub const AdapterError = error{
    Unavailable,
    InvalidData,
    UnsupportedVersion,
    OperationFailed,
};

pub const CapabilityError = AdapterError || std.mem.Allocator.Error;
pub const StateStoreError = CapabilityError || error{Conflict};

pub const CatalogScope = struct {
    host_scope_key: []const u8,
    as_of: []const u8,
};

pub const HistoryQuery = struct {
    host_scope_key: []const u8,
    through: []const u8,
    exercise_ids: []const []const u8 = &.{},
};

pub const MethodologyStateKey = struct {
    host_scope_key: []const u8,
    methodology_id: []const u8,
};

pub const MethodologyStateRecord = struct {
    key: MethodologyStateKey,
    methodology_version: []const u8,
    state: canonical.MethodologyState,
    revision: []const u8,
    updated_at: []const u8,
};

pub const CompareAndSetMethodologyState = struct {
    key: MethodologyStateKey,
    expected_revision: ?[]const u8,
    methodology_version: []const u8,
    next_state: canonical.MethodologyState,
    updated_at: []const u8,
};

/// Loaded values and their nested slices live in `allocator`.
pub const CatalogSource = struct {
    context: *anyopaque,
    load_fn: *const fn (
        context: *anyopaque,
        allocator: std.mem.Allocator,
        scope: CatalogScope,
    ) CapabilityError![]const canonical.Exercise,

    pub fn load(
        self: CatalogSource,
        allocator: std.mem.Allocator,
        scope: CatalogScope,
    ) CapabilityError![]const canonical.Exercise {
        return self.load_fn(self.context, allocator, scope);
    }
};

/// Loaded values and their nested slices live in `allocator`.
pub const HistorySource = struct {
    context: *anyopaque,
    load_fn: *const fn (
        context: *anyopaque,
        allocator: std.mem.Allocator,
        query: HistoryQuery,
    ) CapabilityError!canonical.HistorySnapshot,

    pub fn load(
        self: HistorySource,
        allocator: std.mem.Allocator,
        query: HistoryQuery,
    ) CapabilityError!canonical.HistorySnapshot {
        return self.load_fn(self.context, allocator, query);
    }
};

/// Loaded records and their nested values live in `allocator`.
pub const MethodologyStateStore = struct {
    context: *anyopaque,
    load_fn: *const fn (
        context: *anyopaque,
        allocator: std.mem.Allocator,
        key: MethodologyStateKey,
    ) CapabilityError!?MethodologyStateRecord,
    compare_and_set_fn: *const fn (
        context: *anyopaque,
        allocator: std.mem.Allocator,
        change: CompareAndSetMethodologyState,
    ) StateStoreError!MethodologyStateRecord,

    pub fn load(
        self: MethodologyStateStore,
        allocator: std.mem.Allocator,
        key: MethodologyStateKey,
    ) CapabilityError!?MethodologyStateRecord {
        return self.load_fn(self.context, allocator, key);
    }

    pub fn compareAndSet(
        self: MethodologyStateStore,
        allocator: std.mem.Allocator,
        change: CompareAndSetMethodologyState,
    ) StateStoreError!MethodologyStateRecord {
        return self.compare_and_set_fn(self.context, allocator, change);
    }
};

pub const AcceptedRecommendationRecord = struct {
    id: []const u8,
    host_scope_key: []const u8,
    accepted_at: []const u8,
    result: canonical.RecommendationResult,
};

pub const RecommendationJournal = struct {
    context: *anyopaque,
    append_fn: *const fn (
        context: *anyopaque,
        record: AcceptedRecommendationRecord,
    ) AdapterError!void,

    pub fn append(
        self: RecommendationJournal,
        record: AcceptedRecommendationRecord,
    ) AdapterError!void {
        return self.append_fn(self.context, record);
    }
};

pub const CompletedWorkoutSink = struct {
    context: *anyopaque,
    append_fn: *const fn (
        context: *anyopaque,
        host_scope_key: []const u8,
        workout: canonical.CompletedWorkout,
    ) AdapterError!void,

    pub fn append(
        self: CompletedWorkoutSink,
        host_scope_key: []const u8,
        workout: canonical.CompletedWorkout,
    ) AdapterError!void {
        return self.append_fn(self.context, host_scope_key, workout);
    }
};

pub const TemplateKey = struct {
    host_scope_key: []const u8,
    template_id: []const u8,
};

pub const TemplateRecord = struct {
    host_scope_key: []const u8,
    template: canonical.WorkoutTemplate,
};

pub const PutTemplate = struct {
    record: TemplateRecord,
    expected_revision: ?u64,
};

pub const WorkoutTemplateStore = struct {
    context: *anyopaque,
    load_fn: *const fn (*anyopaque, std.mem.Allocator, TemplateKey) CapabilityError!?TemplateRecord,
    put_fn: *const fn (*anyopaque, std.mem.Allocator, PutTemplate) StateStoreError!TemplateRecord,

    pub fn load(self: WorkoutTemplateStore, allocator: std.mem.Allocator, key: TemplateKey) CapabilityError!?TemplateRecord {
        return self.load_fn(self.context, allocator, key);
    }

    pub fn put(self: WorkoutTemplateStore, allocator: std.mem.Allocator, change: PutTemplate) StateStoreError!TemplateRecord {
        return self.put_fn(self.context, allocator, change);
    }
};

pub const WorkflowRecoveryStatus = enum { pending, completed };

pub const WorkflowRecoveryKey = struct {
    host_scope_key: []const u8,
    workflow_id: []const u8,
};

pub const WorkflowRecoveryRecord = struct {
    key: WorkflowRecoveryKey,
    kind: []const u8,
    status: WorkflowRecoveryStatus,
    idempotency_key: []const u8,
    payload_json: []const u8,
    updated_at: []const u8,
};

pub const WorkflowRecoveryStore = struct {
    context: *anyopaque,
    load_fn: *const fn (*anyopaque, std.mem.Allocator, WorkflowRecoveryKey) CapabilityError!?WorkflowRecoveryRecord,
    put_fn: *const fn (*anyopaque, WorkflowRecoveryRecord) AdapterError!void,

    pub fn load(self: WorkflowRecoveryStore, allocator: std.mem.Allocator, key: WorkflowRecoveryKey) CapabilityError!?WorkflowRecoveryRecord {
        return self.load_fn(self.context, allocator, key);
    }

    pub fn put(self: WorkflowRecoveryStore, record: WorkflowRecoveryRecord) AdapterError!void {
        return self.put_fn(self.context, record);
    }
};
