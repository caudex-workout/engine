//! Versioned, adapter-independent portable data protocol.

const std = @import("std");
const caudex = @import("caudex");
const tracking_protocol = @import("caudex_tracking_protocol");
const tracking = @import("caudex_tracking");

pub const schema_version: u32 = 1;
pub const max_input_bytes: usize = 4 * 1024 * 1024;
pub const max_records_per_kind: usize = 10_000;
pub const max_issues: usize = 256;

pub const CatalogReference = struct {
    hostScopeKey: []const u8,
    exerciseId: []const u8,
    catalogId: ?[]const u8 = null,
    catalogVersion: ?[]const u8 = null,
};

pub const CustomExerciseRecord = struct {
    hostScopeKey: []const u8,
    exercise: caudex.canonical.Exercise,
};

pub const TemplateRecord = struct {
    hostScopeKey: []const u8,
    template: caudex.canonical.WorkoutTemplate,
};

pub const ActiveWorkoutRecord = struct {
    hostScopeKey: []const u8,
    athleteId: ?[]const u8 = null,
    workoutId: []const u8,
    snapshot: tracking_protocol.TrackingSnapshot,
};

pub const CompletedWorkoutRecord = struct {
    hostScopeKey: []const u8,
    workout: caudex.canonical.CompletedWorkout,
};

pub const AcceptedRecommendationRecord = struct {
    id: []const u8,
    hostScopeKey: []const u8,
    acceptedAt: []const u8,
    result: caudex.canonical.RecommendationResult,
};

pub const AcceptedProgramRecommendationRecord = struct {
    id: []const u8,
    hostScopeKey: []const u8,
    acceptedAt: []const u8,
    result: caudex.canonical.ProgramRecommendationResult,
};

pub const ProgressionStateRecord = struct {
    hostScopeKey: []const u8,
    stateId: []const u8,
    progressionId: []const u8,
    progressionVersion: []const u8,
    state: caudex.canonical.MethodologyState,
    revision: []const u8,
    updatedAt: []const u8,
};

pub const ProgramStateRecord = struct {
    hostScopeKey: []const u8,
    programId: []const u8,
    strategyId: []const u8,
    strategyVersion: []const u8,
    state: caudex.canonical.ProgramState,
    revision: []const u8,
    updatedAt: []const u8,
};

pub const MethodologyStateRecord = struct {
    hostScopeKey: []const u8,
    methodologyId: []const u8,
    methodologyVersion: []const u8,
    state: caudex.canonical.MethodologyState,
    revision: []const u8,
    updatedAt: []const u8,
};

pub const WorkflowRecoveryRecord = struct {
    hostScopeKey: []const u8,
    workflowId: []const u8,
    kind: []const u8,
    status: enum { pending, completed },
    idempotencyKey: []const u8,
    payload: std.json.Value,
    updatedAt: []const u8,
};

pub const Document = struct {
    schemaVersion: u32,
    exportedAt: []const u8,
    catalogReferences: []const CatalogReference = &.{},
    customExercises: []const CustomExerciseRecord = &.{},
    templates: []const TemplateRecord = &.{},
    activeWorkouts: []const ActiveWorkoutRecord = &.{},
    completedWorkouts: []const CompletedWorkoutRecord = &.{},
    acceptedRecommendations: []const AcceptedRecommendationRecord = &.{},
    acceptedProgramRecommendations: []const AcceptedProgramRecommendationRecord = &.{},
    methodologyStates: []const MethodologyStateRecord = &.{},
    progressionStates: []const ProgressionStateRecord = &.{},
    programStates: []const ProgramStateRecord = &.{},
    workflowRecovery: []const WorkflowRecoveryRecord = &.{},
};

pub const ImportMode = enum { merge, replace };
pub const ConflictPolicy = enum { reject, keepExisting, overwrite };

pub const ImportRequest = struct {
    schemaVersion: u32,
    mode: ImportMode,
    conflictPolicy: ConflictPolicy,
    dryRun: bool = true,
    document: Document,
};

pub const Severity = enum { warning, @"error" };
pub const Issue = struct {
    code: []const u8,
    path: []const u8,
    message: []const u8,
    severity: Severity,
};

pub const Counts = struct {
    catalogReferences: usize,
    customExercises: usize,
    templates: usize,
    activeWorkouts: usize,
    completedWorkouts: usize,
    acceptedRecommendations: usize,
    acceptedProgramRecommendations: usize,
    methodologyStates: usize,
    progressionStates: usize,
    programStates: usize,
    workflowRecovery: usize,
};

pub const ImportPlan = struct {
    schemaVersion: u32 = schema_version,
    valid: bool,
    dryRun: bool,
    mode: ImportMode,
    conflictPolicy: ConflictPolicy,
    counts: Counts,
    issues: []const Issue,
};

pub const ExportOutcome = union(enum) {
    accepted: Document,
    rejected: []const Issue,
};

pub const ExportResult = struct {
    schemaVersion: u32 = schema_version,
    outcome: ExportOutcome,
};

pub const DecodeError = caudex.canonical_json.DecodeError || error{RecordLimitExceeded};

pub fn decodeDocument(allocator: std.mem.Allocator, input: []const u8) DecodeError!std.json.Parsed(Document) {
    const parsed = try caudex.canonical_json.decodeValue(Document, allocator, input, limits());
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != schema_version) return error.UnsupportedVersion;
    try validateDocumentBounds(parsed.value);
    return parsed;
}

pub fn decodeImportRequest(allocator: std.mem.Allocator, input: []const u8) DecodeError!std.json.Parsed(ImportRequest) {
    const parsed = try caudex.canonical_json.decodeValue(ImportRequest, allocator, input, limits());
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != schema_version or parsed.value.document.schemaVersion != schema_version) return error.UnsupportedVersion;
    try validateDocumentBounds(parsed.value.document);
    return parsed;
}

pub fn encode(value: anytype, output: []u8) caudex.canonical_json.EncodeError![]const u8 {
    return caudex.canonical_json.encode(value, output);
}

pub fn planImport(request: ImportRequest, issue_storage: []Issue) error{IssueBufferTooSmall}!ImportPlan {
    var issue_count: usize = 0;
    if (request.schemaVersion != schema_version) try appendIssue(issue_storage, &issue_count, "portable.unsupported_version", "/schemaVersion", "Only portable schema version 1 is supported.");
    validateDocument(request.document, issue_storage, &issue_count) catch return error.IssueBufferTooSmall;
    return .{
        .valid = issue_count == 0,
        .dryRun = request.dryRun,
        .mode = request.mode,
        .conflictPolicy = request.conflictPolicy,
        .counts = counts(request.document),
        .issues = issue_storage[0..issue_count],
    };
}

pub fn validateExport(document: Document, issue_storage: []Issue) error{IssueBufferTooSmall}!ExportResult {
    var issue_count: usize = 0;
    validateDocument(document, issue_storage, &issue_count) catch return error.IssueBufferTooSmall;
    return .{ .outcome = if (issue_count == 0)
        .{ .accepted = document }
    else
        .{ .rejected = issue_storage[0..issue_count] } };
}

pub fn validateDocumentBounds(document: Document) error{RecordLimitExceeded}!void {
    inline for (.{
        document.catalogReferences.len,
        document.customExercises.len,
        document.templates.len,
        document.activeWorkouts.len,
        document.completedWorkouts.len,
        document.acceptedRecommendations.len,
        document.acceptedProgramRecommendations.len,
        document.methodologyStates.len,
        document.progressionStates.len,
        document.programStates.len,
        document.workflowRecovery.len,
    }) |count| if (count > max_records_per_kind) return error.RecordLimitExceeded;
    for (document.activeWorkouts) |record| tracking_protocol.validateSnapshot(record.snapshot) catch return error.RecordLimitExceeded;
}

fn validateDocument(document: Document, storage: []Issue, count: *usize) error{IssueBufferTooSmall}!void {
    validateDocumentBounds(document) catch try appendIssue(storage, count, "portable.record_limit_exceeded", "/", "The portable document exceeds a record or nested tracking limit.");
    if (document.schemaVersion != schema_version) try appendIssue(storage, count, "portable.unsupported_version", "/schemaVersion", "Only portable schema version 1 is supported.");
    if (tracking.Timestamp.parse(document.exportedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/exportedAt", "The export timestamp is not valid RFC 3339.");
    try validateUniqueAndSorted(CatalogReference, document.catalogReferences, storage, count, "/catalogReferences", catalogOrder);
    try validateUniqueAndSorted(CustomExerciseRecord, document.customExercises, storage, count, "/customExercises", exerciseOrder);
    try validateUniqueAndSorted(TemplateRecord, document.templates, storage, count, "/templates", templateOrder);
    try validateUniqueAndSorted(ActiveWorkoutRecord, document.activeWorkouts, storage, count, "/activeWorkouts", activeOrder);
    try validateUniqueAndSorted(CompletedWorkoutRecord, document.completedWorkouts, storage, count, "/completedWorkouts", completedOrder);
    try validateUniqueAndSorted(AcceptedRecommendationRecord, document.acceptedRecommendations, storage, count, "/acceptedRecommendations", acceptedOrder);
    try validateUniqueAndSorted(AcceptedProgramRecommendationRecord, document.acceptedProgramRecommendations, storage, count, "/acceptedProgramRecommendations", acceptedProgramOrder);
    try validateUniqueAndSorted(MethodologyStateRecord, document.methodologyStates, storage, count, "/methodologyStates", stateOrder);
    try validateUniqueAndSorted(ProgressionStateRecord, document.progressionStates, storage, count, "/progressionStates", progressionStateOrder);
    try validateUniqueAndSorted(ProgramStateRecord, document.programStates, storage, count, "/programStates", programStateOrder);
    try validateUniqueAndSorted(WorkflowRecoveryRecord, document.workflowRecovery, storage, count, "/workflowRecovery", recoveryOrder);
    var reference_index: usize = 0;
    var custom_index: usize = 0;
    while (reference_index < document.catalogReferences.len and custom_index < document.customExercises.len) {
        const reference = document.catalogReferences[reference_index];
        const custom = document.customExercises[custom_index];
        const order = scopedOrder(reference.hostScopeKey, reference.exerciseId, custom.hostScopeKey, custom.exercise.id);
        switch (order) {
            .lt => reference_index += 1,
            .gt => custom_index += 1,
            .eq => {
                try appendIssue(storage, count, "portable.catalog_source_conflict", "/catalogReferences", "An exercise cannot be both an external catalog reference and an embedded custom exercise in one scope.");
                reference_index += 1;
                custom_index += 1;
            },
        }
    }
    for (document.activeWorkouts) |record| {
        if (record.snapshot.workouts.len != 1 or
            !std.mem.eql(u8, record.snapshot.workouts[0].id, record.workoutId) or
            !std.mem.eql(u8, record.snapshot.workouts[0].scope.hostScopeKey, record.hostScopeKey) or
            !optionalStringsEqual(record.snapshot.workouts[0].scope.athleteId, record.athleteId) or
            record.snapshot.workouts[0].status != .active)
            try appendIssue(storage, count, "portable.active_workout_inconsistent", "/activeWorkouts", "An active-workout record must contain exactly its matching active workout and scope.");
        for (record.snapshot.workouts) |workout| {
            for (workout.exercises) |exercise| {
                if (!hasExercise(document, record.hostScopeKey, exercise.exerciseId)) try appendIssue(storage, count, "portable.catalog_reference_missing", "/activeWorkouts", "An active workout exercise has no catalog reference or embedded custom exercise.");
                for (exercise.sets) |set| {
                    try validateMetrics(set.targetMetrics, storage, count, "/activeWorkouts");
                    try validateMetrics(set.actualMetrics, storage, count, "/activeWorkouts");
                }
            }
        }
    }
    for (document.completedWorkouts) |record| {
        if (tracking.Timestamp.parse(record.workout.startedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/completedWorkouts", "A completed workout start timestamp is invalid.");
        if (tracking.Timestamp.parse(record.workout.completedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/completedWorkouts", "A completed workout completion timestamp is invalid.");
        for (record.workout.exercises) |exercise| {
            if (!hasExercise(document, record.hostScopeKey, exercise.exerciseId)) try appendIssue(storage, count, "portable.catalog_reference_missing", "/completedWorkouts", "A completed workout exercise has no catalog reference or embedded custom exercise.");
            for (exercise.sets) |set| {
                try validateMetrics(set.targetMetrics, storage, count, "/completedWorkouts");
                try validateMetrics(set.actualMetrics, storage, count, "/completedWorkouts");
            }
        }
    }
    for (document.templates) |record| for (record.template.exercises) |exercise| for (exercise.sets) |set| try validateMetrics(set.targetMetrics, storage, count, "/templates");
    for (document.acceptedRecommendations) |record| {
        if (tracking.Timestamp.parse(record.acceptedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/acceptedRecommendations", "An accepted-recommendation timestamp is invalid.");
        if (record.result.recommendation) |recommendation| try validateSessionMetrics(recommendation, storage, count);
        for (record.result.alternatives) |alternative| try validateSessionMetrics(alternative, storage, count);
    }
    for (document.acceptedProgramRecommendations) |record| {
        if (tracking.Timestamp.parse(record.acceptedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/acceptedProgramRecommendations", "An accepted program recommendation timestamp is invalid.");
        if (record.result.recommendation) |recommendation| try validateSessionMetrics(recommendation, storage, count);
    }
    for (document.methodologyStates) |record| if (tracking.Timestamp.parse(record.updatedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/methodologyStates", "A methodology-state timestamp is invalid.");
    for (document.progressionStates) |record| if (tracking.Timestamp.parse(record.updatedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/progressionStates", "A progression-state timestamp is invalid.");
    for (document.programStates) |record| if (tracking.Timestamp.parse(record.updatedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/programStates", "A program-state timestamp is invalid.");
    for (document.workflowRecovery) |record| if (tracking.Timestamp.parse(record.updatedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/workflowRecovery", "A workflow-recovery timestamp is invalid.");
}

fn validateSessionMetrics(session: caudex.canonical.SessionRecommendation, storage: []Issue, count: *usize) error{IssueBufferTooSmall}!void {
    for (session.exercises) |exercise| for (exercise.sets) |set| try validateMetrics(set.targetMetrics, storage, count, "/acceptedRecommendations");
}

fn validateMetrics(metrics: []const caudex.canonical.Metric, storage: []Issue, count: *usize, path: []const u8) error{IssueBufferTooSmall}!void {
    for (metrics) |metric| {
        if (caudex.primitives.Decimal.parse(metric.value.amount)) |_| {} else |_| try appendIssue(storage, count, "portable.decimal_invalid", path, "A metric amount is not an exact canonical decimal.");
        _ = caudex.primitives.Unit.parse(metric.value.unit) catch try appendIssue(storage, count, "portable.unit_unknown", path, "A metric unit is not supported by this protocol version.");
    }
}

fn optionalStringsEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn validateUniqueAndSorted(comptime T: type, values: []const T, storage: []Issue, count: *usize, path: []const u8, orderFn: fn (T, T) std.math.Order) error{IssueBufferTooSmall}!void {
    if (values.len < 2) return;
    for (values[1..], values[0..if (values.len == 0) 0 else values.len - 1]) |current, previous| {
        const order = orderFn(previous, current);
        if (order == .eq) try appendIssue(storage, count, "portable.duplicate_id", path, "Portable record IDs must be unique within each record kind.");
        if (order == .gt) try appendIssue(storage, count, "portable.order_invalid", path, "Portable records must be sorted by their stable key.");
    }
}

fn catalogOrder(left: CatalogReference, right: CatalogReference) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.exerciseId, right.hostScopeKey, right.exerciseId);
}
fn exerciseOrder(left: CustomExerciseRecord, right: CustomExerciseRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.exercise.id, right.hostScopeKey, right.exercise.id);
}
fn templateOrder(left: TemplateRecord, right: TemplateRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.template.id, right.hostScopeKey, right.template.id);
}
fn activeOrder(left: ActiveWorkoutRecord, right: ActiveWorkoutRecord) std.math.Order {
    const scope_order = std.mem.order(u8, left.hostScopeKey, right.hostScopeKey);
    if (scope_order != .eq) return scope_order;
    const athlete_order = std.mem.order(u8, left.athleteId orelse "", right.athleteId orelse "");
    return if (athlete_order == .eq) std.mem.order(u8, left.workoutId, right.workoutId) else athlete_order;
}
fn completedOrder(left: CompletedWorkoutRecord, right: CompletedWorkoutRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.workout.id, right.hostScopeKey, right.workout.id);
}
fn acceptedOrder(left: AcceptedRecommendationRecord, right: AcceptedRecommendationRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.id, right.hostScopeKey, right.id);
}
fn acceptedProgramOrder(left: AcceptedProgramRecommendationRecord, right: AcceptedProgramRecommendationRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.id, right.hostScopeKey, right.id);
}
fn stateOrder(left: MethodologyStateRecord, right: MethodologyStateRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.methodologyId, right.hostScopeKey, right.methodologyId);
}
fn progressionStateOrder(left: ProgressionStateRecord, right: ProgressionStateRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.stateId, right.hostScopeKey, right.stateId);
}
fn programStateOrder(left: ProgramStateRecord, right: ProgramStateRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.programId, right.hostScopeKey, right.programId);
}
fn recoveryOrder(left: WorkflowRecoveryRecord, right: WorkflowRecoveryRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.workflowId, right.hostScopeKey, right.workflowId);
}

fn scopedOrder(left_scope: []const u8, left_id: []const u8, right_scope: []const u8, right_id: []const u8) std.math.Order {
    const scope_order = std.mem.order(u8, left_scope, right_scope);
    return if (scope_order == .eq) std.mem.order(u8, left_id, right_id) else scope_order;
}

fn hasExercise(document: Document, scope: []const u8, id: []const u8) bool {
    for (document.catalogReferences) |reference| if (std.mem.eql(u8, reference.hostScopeKey, scope) and std.mem.eql(u8, reference.exerciseId, id)) return true;
    for (document.customExercises) |record| if (std.mem.eql(u8, record.hostScopeKey, scope) and std.mem.eql(u8, record.exercise.id, id)) return true;
    return false;
}

fn appendIssue(storage: []Issue, count: *usize, code: []const u8, path: []const u8, message: []const u8) error{IssueBufferTooSmall}!void {
    if (count.* >= storage.len or count.* >= max_issues) return error.IssueBufferTooSmall;
    storage[count.*] = .{ .code = code, .path = path, .message = message, .severity = .@"error" };
    count.* += 1;
}

fn counts(document: Document) Counts {
    return .{
        .catalogReferences = document.catalogReferences.len,
        .customExercises = document.customExercises.len,
        .templates = document.templates.len,
        .activeWorkouts = document.activeWorkouts.len,
        .completedWorkouts = document.completedWorkouts.len,
        .acceptedRecommendations = document.acceptedRecommendations.len,
        .acceptedProgramRecommendations = document.acceptedProgramRecommendations.len,
        .methodologyStates = document.methodologyStates.len,
        .progressionStates = document.progressionStates.len,
        .programStates = document.programStates.len,
        .workflowRecovery = document.workflowRecovery.len,
    };
}

fn limits() caudex.canonical_json.Limits {
    return .{ .max_input_bytes = max_input_bytes, .max_nesting = 32, .max_collection_items = 100_000, .max_string_bytes = 64 * 1024 };
}
