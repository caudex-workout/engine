//! Database-independent capability contracts for optional Caudex persistence
//! adapters.
//!
//! Import this public package as `@import("caudex_persistence")`. The package
//! depends only on the public `caudex` package; it performs no I/O and provides
//! no database implementation.

const std = @import("std");
const caudex = @import("caudex");
pub const portable = @import("caudex_portable");

pub const canonical = caudex.canonical;
pub const contract_version: u32 = 5;

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

/// Identifies a host-owned persistent athlete profile without prescribing an
/// account, authentication, or tenancy model.
pub const AthleteProfileKey = struct {
    host_scope_key: []const u8,
    athlete_profile_id: []const u8,
};

/// A programming-relevant athlete-profile snapshot. The profile's numeric
/// revision is its optimistic-concurrency token; hosts may retain separate
/// presentation-only metadata without changing this record.
pub const AthleteProfileRecord = struct {
    key: AthleteProfileKey,
    profile: canonical.AthleteProfile,
};

/// Replaces a profile only when the stored programming revision matches.
/// `expected_revision = null` means create only if absent. The returned
/// profile is the accepted persisted snapshot, including its next revision.
pub const CompareAndSetAthleteProfile = struct {
    key: AthleteProfileKey,
    expected_revision: ?u64,
    next_profile: canonical.AthleteProfile,
};

/// Optional persistent-profile capability. It deliberately remains separate
/// from program and progression state: hosts may instead pass an explicit
/// profile snapshot directly to the deterministic engine.
pub const AthleteProfileStore = struct {
    context: *anyopaque,
    load_fn: *const fn (
        context: *anyopaque,
        allocator: std.mem.Allocator,
        key: AthleteProfileKey,
    ) CapabilityError!?AthleteProfileRecord,
    compare_and_set_fn: *const fn (
        context: *anyopaque,
        allocator: std.mem.Allocator,
        change: CompareAndSetAthleteProfile,
    ) StateStoreError!AthleteProfileRecord,

    pub fn load(
        self: AthleteProfileStore,
        allocator: std.mem.Allocator,
        key: AthleteProfileKey,
    ) CapabilityError!?AthleteProfileRecord {
        return self.load_fn(self.context, allocator, key);
    }

    pub fn compareAndSet(
        self: AthleteProfileStore,
        allocator: std.mem.Allocator,
        change: CompareAndSetAthleteProfile,
    ) StateStoreError!AthleteProfileRecord {
        return self.compare_and_set_fn(self.context, allocator, change);
    }
};

/// Immutable identity of one versioned, host-scoped program definition.
pub const ProgramDefinitionKey = struct {
    host_scope_key: []const u8,
    definition_id: []const u8,
    definition_version: []const u8,
};

pub const ProgramDefinitionRecord = struct {
    key: ProgramDefinitionKey,
    definition: canonical.ProgramDefinitionDocument,
};

pub const ProgramDefinitionStore = struct {
    context: *anyopaque,
    load_fn: *const fn (*anyopaque, std.mem.Allocator, ProgramDefinitionKey) CapabilityError!?ProgramDefinitionRecord,
    put_fn: *const fn (*anyopaque, std.mem.Allocator, ProgramDefinitionRecord) StateStoreError!ProgramDefinitionRecord,

    pub fn load(self: ProgramDefinitionStore, allocator: std.mem.Allocator, key: ProgramDefinitionKey) CapabilityError!?ProgramDefinitionRecord {
        return self.load_fn(self.context, allocator, key);
    }

    /// Creates one immutable definition version. Reusing its scoped key is a
    /// conflict even when the supplied payload is byte-identical.
    pub fn put(self: ProgramDefinitionStore, allocator: std.mem.Allocator, record: ProgramDefinitionRecord) StateStoreError!ProgramDefinitionRecord {
        return self.put_fn(self.context, allocator, record);
    }
};

pub const ProgramInstanceKey = struct {
    host_scope_key: []const u8,
    instance_id: []const u8,
};

/// The instance and accepted planning state are persisted together so an
/// active lifecycle cannot be observed with a torn or unrelated cursor.
pub const ProgramInstanceRecord = struct {
    key: ProgramInstanceKey,
    instance: canonical.ProgramInstanceDocument,
    planning_state: ?canonical.ProgramPlanningState = null,
};

pub const CompareAndSetProgramInstance = struct {
    record: ProgramInstanceRecord,
    /// Null creates only an absent instance. Otherwise this must equal the
    /// currently persisted planning-state revision.
    expected_revision: ?u64,
};

pub const ProgramInstanceStore = struct {
    context: *anyopaque,
    load_fn: *const fn (*anyopaque, std.mem.Allocator, ProgramInstanceKey) CapabilityError!?ProgramInstanceRecord,
    compare_and_set_fn: *const fn (*anyopaque, std.mem.Allocator, CompareAndSetProgramInstance) StateStoreError!ProgramInstanceRecord,

    pub fn load(self: ProgramInstanceStore, allocator: std.mem.Allocator, key: ProgramInstanceKey) CapabilityError!?ProgramInstanceRecord {
        return self.load_fn(self.context, allocator, key);
    }

    pub fn compareAndSet(self: ProgramInstanceStore, allocator: std.mem.Allocator, change: CompareAndSetProgramInstance) StateStoreError!ProgramInstanceRecord {
        return self.compare_and_set_fn(self.context, allocator, change);
    }
};

pub const ProgramOccurrenceKey = struct {
    host_scope_key: []const u8,
    instance_id: []const u8,
    occurrence_id: []const u8,
};

pub const ProgramOccurrenceRecord = struct {
    key: ProgramOccurrenceKey,
    occurrence: canonical.ProgramOccurrenceRecord,
};

pub const ProgramOccurrenceStore = struct {
    context: *anyopaque,
    load_fn: *const fn (*anyopaque, std.mem.Allocator, ProgramOccurrenceKey) CapabilityError!?ProgramOccurrenceRecord,
    append_fn: *const fn (*anyopaque, std.mem.Allocator, ProgramOccurrenceRecord) StateStoreError!ProgramOccurrenceRecord,

    pub fn load(self: ProgramOccurrenceStore, allocator: std.mem.Allocator, key: ProgramOccurrenceKey) CapabilityError!?ProgramOccurrenceRecord {
        return self.load_fn(self.context, allocator, key);
    }

    /// Appends an immutable occurrence ledger entry. A duplicate scoped key
    /// returns Conflict instead of replacing historical transition evidence.
    pub fn append(self: ProgramOccurrenceStore, allocator: std.mem.Allocator, record: ProgramOccurrenceRecord) StateStoreError!ProgramOccurrenceRecord {
        return self.append_fn(self.context, allocator, record);
    }
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

pub const PortableExportQuery = struct {
    host_scope_key: []const u8,
    exported_at: []const u8,
};

/// Adapter-independent import/export capability. Exported values and import
/// issues live in `allocator`; implementations must validate before mutation.
pub const PortableDataStore = struct {
    context: *anyopaque,
    export_fn: *const fn (*anyopaque, std.mem.Allocator, PortableExportQuery) CapabilityError!portable.Document,
    import_fn: *const fn (*anyopaque, std.mem.Allocator, portable.ImportRequest) CapabilityError!portable.ImportPlan,

    pub fn exportData(self: PortableDataStore, allocator: std.mem.Allocator, query: PortableExportQuery) CapabilityError!portable.Document {
        return self.export_fn(self.context, allocator, query);
    }

    pub fn importData(self: PortableDataStore, allocator: std.mem.Allocator, request: portable.ImportRequest) CapabilityError!portable.ImportPlan {
        return self.import_fn(self.context, allocator, request);
    }
};
