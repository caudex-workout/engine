//! Versioned, bounded cross-language tracking protocol.
//!
//! These wire values are independent of the typed tracking domain. Conversion
//! is explicit; JSON is never used inside lifecycle decisions.

const std = @import("std");
const caudex = @import("caudex");
const tracking = @import("caudex_tracking");

pub const schema_version: u32 = 1;
pub const max_commands_per_batch: usize = 128;
pub const max_workouts: usize = 256;
pub const max_catalog_entries: usize = 4096;
pub const max_exercises_per_workout: usize = 128;
pub const max_sets_per_exercise: usize = 256;
pub const max_metrics_per_set: usize = 32;
pub const max_tags_per_exercise: usize = 32;
pub const max_issues_per_result: usize = 128;
pub const max_related_ids_per_issue: usize = 32;

pub const Limits = struct {
    json: caudex.canonical_json.Limits = .{},
    max_commands: usize = max_commands_per_batch,
};

pub const WorkoutStatus = enum { active, completed, cancelled };
pub const SetStatus = enum { open, completed, partial, failed, skipped };
pub const IssueCategory = enum { validation, not_found, conflict };
pub const IssueSeverity = enum { warning, @"error" };
pub const CommandDisposition = enum { applied, replayed };

pub const Scope = struct {
    hostScopeKey: []const u8,
    athleteId: ?[]const u8 = null,
};

pub const CommandMetadata = struct {
    commandId: []const u8,
    occurredAt: []const u8,
};

pub const TrackedSet = struct {
    id: []const u8,
    kind: []const u8,
    targetMetrics: []const caudex.canonical.Metric = &.{},
    actualMetrics: []const caudex.canonical.Metric = &.{},
    status: SetStatus = .open,
    recordedAt: ?[]const u8 = null,
};

pub const ExerciseMembership = struct {
    id: []const u8,
    exerciseId: []const u8,
    sets: []const TrackedSet = &.{},
};

pub const ExerciseAvailability = enum { active, archived };

pub const ExerciseCatalogEntry = struct {
    exerciseId: []const u8,
    availability: ExerciseAvailability,
};

pub const WorkoutOrigin = enum { manual, template, recommendation };

pub const PrescribedSet = struct {
    setId: []const u8,
    kind: []const u8,
    targetMetrics: []const caudex.canonical.Metric = &.{},
};

pub const PrescribedExercise = struct {
    membershipId: []const u8,
    exerciseId: []const u8,
    sets: []const PrescribedSet = &.{},
    notes: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
};

pub const RecommendationProvenance = struct {
    acceptedRecommendationId: []const u8,
    inputFingerprint: []const u8,
    resultFingerprint: []const u8,
    methodologyId: []const u8,
    methodologyVersion: []const u8,
    methodologyConfigVersion: u32,
    methodologyStateRevision: ?[]const u8 = null,
    methodologyStateFingerprint: ?[]const u8 = null,
};

pub const TemplateProvenance = struct {
    templateId: []const u8,
    templateRevision: u64,
};

pub const Provenance = union(enum) {
    recommendation: RecommendationProvenance,
    template: TemplateProvenance,
};

pub const TrackedWorkout = struct {
    id: []const u8,
    scope: Scope,
    revision: u64,
    status: WorkoutStatus,
    startedAt: []const u8,
    completedAt: ?[]const u8 = null,
    exercises: []const ExerciseMembership = &.{},
    origin: WorkoutOrigin = .manual,
    provenance: ?Provenance = null,
    prescription: []const PrescribedExercise = &.{},
};

pub const TrackingSnapshot = struct {
    workouts: []const TrackedWorkout = &.{},
    startReceipts: []const StartReceipt = &.{},
    exerciseCatalog: []const ExerciseCatalogEntry = &.{},
};

/// Standalone, versioned snapshot document for canonical interchange.
pub const SnapshotDocument = struct {
    schemaVersion: u32,
    snapshot: TrackingSnapshot,
};

pub const Anchor = union(enum) {
    beginning,
    end,
    before: []const u8,
    after: []const u8,
};

pub const StartWorkout = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workoutId: []const u8,
    startedAt: []const u8,
};

pub const StartReceipt = struct {
    command: StartWorkout,
    disposition: CommandDisposition,
    workout: TrackedWorkout,
};

pub const WorkoutRevision = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workoutId: []const u8,
    expectedRevision: u64,
};

pub const AddExercise = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workoutId: []const u8,
    expectedRevision: u64,
    membershipId: []const u8,
    exerciseId: []const u8,
    anchor: Anchor,
};

pub const MembershipRevision = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workoutId: []const u8,
    expectedRevision: u64,
    membershipId: []const u8,
};

pub const ReorderExercise = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workoutId: []const u8,
    expectedRevision: u64,
    membershipId: []const u8,
    anchor: Anchor,
};

pub const AddSet = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workoutId: []const u8,
    expectedRevision: u64,
    membershipId: []const u8,
    setId: []const u8,
    kind: []const u8,
    targetMetrics: []const caudex.canonical.Metric = &.{},
    anchor: Anchor,
};

pub const SetRevision = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workoutId: []const u8,
    expectedRevision: u64,
    membershipId: []const u8,
    setId: []const u8,
};

pub const CompleteSet = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workoutId: []const u8,
    expectedRevision: u64,
    membershipId: []const u8,
    setId: []const u8,
    actualMetrics: []const caudex.canonical.Metric,
    status: SetStatus = .completed,
    completedAt: []const u8,
};

pub const TimedSet = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workoutId: []const u8,
    expectedRevision: u64,
    membershipId: []const u8,
    setId: []const u8,
    at: []const u8,
};

pub const ReorderSet = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workoutId: []const u8,
    expectedRevision: u64,
    membershipId: []const u8,
    setId: []const u8,
    anchor: Anchor,
};

pub const CompleteWorkout = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workoutId: []const u8,
    expectedRevision: u64,
    completedAt: []const u8,
};

/// The union tag is the stable explicit operation discriminator.
pub const Command = union(enum) {
    startWorkout: StartWorkout,
    addExercise: AddExercise,
    removeExercise: MembershipRevision,
    reorderExercise: ReorderExercise,
    addSet: AddSet,
    completeSet: CompleteSet,
    skipSet: TimedSet,
    reopenSet: SetRevision,
    removeSet: SetRevision,
    reorderSet: ReorderSet,
    completeWorkout: CompleteWorkout,
};

pub const CommandRequest = struct {
    schemaVersion: u32,
    snapshot: TrackingSnapshot,
    command: Command,
};

pub const AtomicBatchRequest = struct {
    schemaVersion: u32,
    snapshot: TrackingSnapshot,
    commands: []const Command,
};

pub const Issue = struct {
    code: []const u8,
    category: IssueCategory,
    severity: IssueSeverity,
    path: ?[]const u8 = null,
    message: []const u8,
    relatedIds: []const []const u8 = &.{},
};

pub const AcceptedCommand = struct {
    commandId: []const u8,
    disposition: CommandDisposition,
    workout: TrackedWorkout,
    warnings: []const Issue = &.{},
};

pub const RejectedCommand = struct {
    commandId: []const u8,
    issues: []const Issue,
};

pub const CommandOutcome = union(enum) {
    accepted: AcceptedCommand,
    rejected: RejectedCommand,
};

pub const CommandResult = struct {
    schemaVersion: u32,
    outcome: CommandOutcome,
    snapshot: TrackingSnapshot,
};

pub const AtomicBatchResult = struct {
    schemaVersion: u32,
    applied: bool,
    outcomes: []const CommandOutcome,
    snapshot: TrackingSnapshot,
    issues: []const Issue = &.{},
};

pub const DecodeError = caudex.canonical_json.DecodeError || error{
    EmptyBatch,
    BatchLimitExceeded,
    SnapshotLimitExceeded,
};

pub fn decodeCommandRequest(allocator: std.mem.Allocator, input: []const u8, limits: Limits) DecodeError!std.json.Parsed(CommandRequest) {
    const parsed = try caudex.canonical_json.decodeValue(CommandRequest, allocator, input, limits.json);
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != schema_version) return error.UnsupportedVersion;
    try validateSnapshot(parsed.value.snapshot);
    try validateCommand(parsed.value.command);
    return parsed;
}

pub fn decodeSnapshotDocument(allocator: std.mem.Allocator, input: []const u8, limits: Limits) DecodeError!std.json.Parsed(SnapshotDocument) {
    const parsed = try caudex.canonical_json.decodeValue(SnapshotDocument, allocator, input, limits.json);
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != schema_version) return error.UnsupportedVersion;
    try validateSnapshot(parsed.value.snapshot);
    return parsed;
}

pub fn decodeAtomicBatchRequest(allocator: std.mem.Allocator, input: []const u8, limits: Limits) DecodeError!std.json.Parsed(AtomicBatchRequest) {
    const parsed = try caudex.canonical_json.decodeValue(AtomicBatchRequest, allocator, input, limits.json);
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != schema_version) return error.UnsupportedVersion;
    if (parsed.value.commands.len == 0) return error.EmptyBatch;
    if (parsed.value.commands.len > limits.max_commands) return error.BatchLimitExceeded;
    try validateSnapshot(parsed.value.snapshot);
    for (parsed.value.commands) |command| try validateCommand(command);
    return parsed;
}

pub fn decodeCommandResult(allocator: std.mem.Allocator, input: []const u8, limits: Limits) DecodeError!std.json.Parsed(CommandResult) {
    const parsed = try caudex.canonical_json.decodeValue(CommandResult, allocator, input, limits.json);
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != schema_version) return error.UnsupportedVersion;
    try validateSnapshot(parsed.value.snapshot);
    try validateOutcomeBounds(parsed.value.outcome);
    return parsed;
}

pub fn decodeAtomicBatchResult(allocator: std.mem.Allocator, input: []const u8, limits: Limits) DecodeError!std.json.Parsed(AtomicBatchResult) {
    const parsed = try caudex.canonical_json.decodeValue(AtomicBatchResult, allocator, input, limits.json);
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != schema_version) return error.UnsupportedVersion;
    if (parsed.value.outcomes.len > limits.max_commands) return error.BatchLimitExceeded;
    try validateSnapshot(parsed.value.snapshot);
    for (parsed.value.outcomes) |outcome| try validateOutcomeBounds(outcome);
    try validateIssuesBounds(parsed.value.issues);
    return parsed;
}

fn validateOutcomeBounds(outcome: CommandOutcome) error{SnapshotLimitExceeded}!void {
    switch (outcome) {
        .accepted => |accepted| {
            try validateSnapshot(.{ .workouts = &.{accepted.workout} });
            try validateIssuesBounds(accepted.warnings);
        },
        .rejected => |rejected| try validateIssuesBounds(rejected.issues),
    }
}

fn validateIssuesBounds(issues: []const Issue) error{SnapshotLimitExceeded}!void {
    if (issues.len > max_issues_per_result) return error.SnapshotLimitExceeded;
    for (issues) |issue| if (issue.relatedIds.len > max_related_ids_per_issue)
        return error.SnapshotLimitExceeded;
}

pub fn encode(value: anytype, output: []u8) caudex.canonical_json.EncodeError![]const u8 {
    return caudex.canonical_json.encode(value, output);
}

pub fn validateSnapshot(snapshot: TrackingSnapshot) error{SnapshotLimitExceeded}!void {
    if (snapshot.workouts.len > max_workouts) return error.SnapshotLimitExceeded;
    if (snapshot.startReceipts.len > max_workouts) return error.SnapshotLimitExceeded;
    if (snapshot.exerciseCatalog.len > max_catalog_entries) return error.SnapshotLimitExceeded;
    for (snapshot.workouts) |workout| try validateWorkoutBounds(workout);
    for (snapshot.startReceipts) |receipt| try validateWorkoutBounds(receipt.workout);
}

/// Validate command-owned collections before allocating typed-domain storage.
/// Snapshot and command collection violations intentionally share one bounded
/// protocol error so every valid JSON document is rejected at the boundary.
pub fn validateCommand(command: Command) error{SnapshotLimitExceeded}!void {
    const metric_count = switch (command) {
        .addSet => |value| value.targetMetrics.len,
        .completeSet => |value| value.actualMetrics.len,
        .startWorkout,
        .addExercise,
        .removeExercise,
        .reorderExercise,
        .skipSet,
        .reopenSet,
        .removeSet,
        .reorderSet,
        .completeWorkout,
        => 0,
    };
    if (metric_count > max_metrics_per_set) return error.SnapshotLimitExceeded;
}

fn validateWorkoutBounds(workout: TrackedWorkout) error{SnapshotLimitExceeded}!void {
    if (workout.exercises.len > max_exercises_per_workout) return error.SnapshotLimitExceeded;
    if (workout.prescription.len > max_exercises_per_workout) return error.SnapshotLimitExceeded;
    for (workout.exercises) |exercise| {
        if (exercise.sets.len > max_sets_per_exercise) return error.SnapshotLimitExceeded;
        for (exercise.sets) |set| {
            if (set.targetMetrics.len > max_metrics_per_set or set.actualMetrics.len > max_metrics_per_set)
                return error.SnapshotLimitExceeded;
        }
    }
    for (workout.prescription) |exercise| {
        if (exercise.sets.len > max_sets_per_exercise or exercise.tags.len > max_tags_per_exercise)
            return error.SnapshotLimitExceeded;
        for (exercise.sets) |set| if (set.targetMetrics.len > max_metrics_per_set)
            return error.SnapshotLimitExceeded;
    }
}

pub const ConversionError = tracking.Id.ParseError || error{InvalidTimestamp};

pub const CommandConversionError = ConversionError || caudex.primitives.Decimal.ParseError || error{
    UnknownUnit,
    CommandBufferTooSmall,
    MetricBufferTooSmall,
    UnsupportedSetStatus,
};

pub const SnapshotConversionError = CommandConversionError || error{
    WorkoutBufferTooSmall,
    ReceiptBufferTooSmall,
    ExerciseBufferTooSmall,
    SetBufferTooSmall,
    MetricBufferTooSmall,
    SnapshotLimitExceeded,
};

pub const SnapshotConversionStorage = struct {
    workouts: []tracking.Workout,
    receipts: []tracking.StartReceipt,
    exercises: []tracking.ExerciseMembership,
    sets: []tracking.TrackedSet,
    metrics: []tracking.Metric,
    prescription_exercises: []tracking.PrescribedExercise,
    prescription_sets: []tracking.PrescribedSet,
    tags: []tracking.Id,
    catalog: []tracking.ExerciseCatalogEntry = &.{},
};

pub const WireSnapshotStorage = struct {
    workouts: []TrackedWorkout,
    receipts: []StartReceipt,
    exercises: []ExerciseMembership,
    sets: []TrackedSet,
    metrics: []caudex.canonical.Metric,
    amountBytes: [][64]u8,
    prescription_exercises: []PrescribedExercise,
    prescription_sets: []PrescribedSet,
    tags: [][]const u8,
    catalog: []ExerciseCatalogEntry = &.{},
};

const WireOffsets = struct {
    exercise: usize = 0,
    set: usize = 0,
    metric: usize = 0,
    prescription_exercise: usize = 0,
    prescription_set: usize = 0,
    tag: usize = 0,
};

pub fn snapshotFromDomain(value: tracking.LifecycleSnapshot, storage: WireSnapshotStorage) SnapshotConversionError!TrackingSnapshot {
    var offsets: WireOffsets = .{};
    return snapshotFromDomainAt(value, storage, &offsets);
}

fn snapshotFromDomainAt(value: tracking.LifecycleSnapshot, storage: WireSnapshotStorage, offsets: *WireOffsets) SnapshotConversionError!TrackingSnapshot {
    if (value.workouts.len > max_workouts) return error.SnapshotLimitExceeded;
    if (storage.workouts.len < value.workouts.len) return error.WorkoutBufferTooSmall;
    if (storage.receipts.len < value.start_receipts.len) return error.ReceiptBufferTooSmall;
    if (storage.catalog.len < value.exercise_catalog.len) return error.ExerciseBufferTooSmall;
    for (value.workouts, 0..) |workout, index| {
        storage.workouts[index] = try workoutFromDomain(
            workout,
            storage,
            &offsets.exercise,
            &offsets.set,
            &offsets.metric,
            &offsets.prescription_exercise,
            &offsets.prescription_set,
            &offsets.tag,
        );
    }
    for (value.start_receipts, 0..) |receipt, index| {
        const workout_index = findDomainWorkout(value.workouts, receipt.accepted.workout.id, receipt.accepted.workout.scope) orelse
            return error.SnapshotLimitExceeded;
        storage.receipts[index] = .{
            .command = startWorkoutFromDomain(receipt.command),
            .disposition = dispositionFromDomain(receipt.accepted.disposition),
            .workout = storage.workouts[workout_index],
        };
    }
    for (value.exercise_catalog, 0..) |entry, index| {
        storage.catalog[index] = .{
            .exerciseId = entry.exercise_id.bytes,
            .availability = availabilityFromDomain(entry.availability),
        };
    }
    return .{
        .workouts = storage.workouts[0..value.workouts.len],
        .startReceipts = storage.receipts[0..value.start_receipts.len],
        .exerciseCatalog = storage.catalog[0..value.exercise_catalog.len],
    };
}

pub const BatchResultStorage = struct {
    snapshot: WireSnapshotStorage,
    outcomes: []CommandOutcome,
    accepted: []AcceptedCommand,
    rejected: []RejectedCommand,
    issues: []Issue,
    relatedIds: [][]const u8,
};

pub const ResultConversionError = SnapshotConversionError || error{
    OutcomeBufferTooSmall,
    IssueBufferTooSmall,
    RelatedIdBufferTooSmall,
};

pub fn batchResultFromDomain(result: tracking.BatchResult, original: tracking.LifecycleSnapshot, storage: BatchResultStorage) ResultConversionError!AtomicBatchResult {
    var offsets: WireOffsets = .{};
    var issue_offset: usize = 0;
    var related_offset: usize = 0;
    return switch (result) {
        .accepted => |accepted_batch| blk: {
            if (storage.outcomes.len < accepted_batch.outcomes.len or storage.accepted.len < accepted_batch.outcomes.len)
                return error.OutcomeBufferTooSmall;
            const snapshot = try snapshotFromDomainAt(accepted_batch.snapshot, storage.snapshot, &offsets);
            for (accepted_batch.outcomes, 0..) |accepted, index| {
                const workout = try workoutFromDomain(
                    accepted.workout,
                    storage.snapshot,
                    &offsets.exercise,
                    &offsets.set,
                    &offsets.metric,
                    &offsets.prescription_exercise,
                    &offsets.prescription_set,
                    &offsets.tag,
                );
                const warnings = try issuesFromDomain(
                    accepted.issues,
                    storage,
                    &issue_offset,
                    &related_offset,
                );
                storage.accepted[index] = .{
                    .commandId = accepted.command_id.bytes,
                    .disposition = dispositionFromDomain(accepted.disposition),
                    .workout = workout,
                    .warnings = warnings,
                };
                storage.outcomes[index] = .{ .accepted = storage.accepted[index] };
            }
            break :blk .{
                .schemaVersion = schema_version,
                .applied = true,
                .outcomes = storage.outcomes[0..accepted_batch.outcomes.len],
                .snapshot = snapshot,
            };
        },
        .rejected => |rejected| blk: {
            if (storage.outcomes.len == 0 or storage.rejected.len == 0)
                return error.OutcomeBufferTooSmall;
            const snapshot = try snapshotFromDomainAt(original, storage.snapshot, &offsets);
            const issues = try issuesFromDomain(
                rejected.issues,
                storage,
                &issue_offset,
                &related_offset,
            );
            storage.rejected[0] = .{
                .commandId = rejected.command_id.bytes,
                .issues = issues,
            };
            storage.outcomes[0] = .{ .rejected = storage.rejected[0] };
            break :blk .{
                .schemaVersion = schema_version,
                .applied = false,
                .outcomes = storage.outcomes[0..1],
                .snapshot = snapshot,
                .issues = issues,
            };
        },
    };
}

pub fn commandResultFromDomain(result: tracking.CommandResult, snapshot: tracking.LifecycleSnapshot, storage: BatchResultStorage) ResultConversionError!CommandResult {
    var offsets: WireOffsets = .{};
    var issue_offset: usize = 0;
    var related_offset: usize = 0;
    if (storage.outcomes.len == 0) return error.OutcomeBufferTooSmall;
    switch (result) {
        .accepted => |accepted| {
            if (storage.accepted.len == 0) return error.OutcomeBufferTooSmall;
            const workout = try workoutFromDomain(
                accepted.workout,
                storage.snapshot,
                &offsets.exercise,
                &offsets.set,
                &offsets.metric,
                &offsets.prescription_exercise,
                &offsets.prescription_set,
                &offsets.tag,
            );
            storage.accepted[0] = .{
                .commandId = accepted.command_id.bytes,
                .disposition = dispositionFromDomain(accepted.disposition),
                .workout = workout,
                .warnings = try issuesFromDomain(accepted.issues, storage, &issue_offset, &related_offset),
            };
            storage.outcomes[0] = .{ .accepted = storage.accepted[0] };
        },
        .rejected => |rejected| {
            if (storage.rejected.len == 0) return error.OutcomeBufferTooSmall;
            storage.rejected[0] = .{
                .commandId = rejected.command_id.bytes,
                .issues = try issuesFromDomain(rejected.issues, storage, &issue_offset, &related_offset),
            };
            storage.outcomes[0] = .{ .rejected = storage.rejected[0] };
        },
    }
    return .{
        .schemaVersion = schema_version,
        .outcome = storage.outcomes[0],
        .snapshot = try snapshotFromDomainAt(snapshot, storage.snapshot, &offsets),
    };
}

fn issuesFromDomain(values: []const tracking.Issue, storage: BatchResultStorage, issue_offset: *usize, related_offset: *usize) ResultConversionError![]const Issue {
    const issue_end = std.math.add(usize, issue_offset.*, values.len) catch return error.IssueBufferTooSmall;
    if (issue_end > storage.issues.len) return error.IssueBufferTooSmall;
    const issue_start = issue_offset.*;
    for (values, issue_start..) |value, index| {
        const related_end = std.math.add(usize, related_offset.*, value.related_ids.len) catch return error.RelatedIdBufferTooSmall;
        if (related_end > storage.relatedIds.len) return error.RelatedIdBufferTooSmall;
        const related_start = related_offset.*;
        for (value.related_ids, related_start..) |id, related_index| {
            storage.relatedIds[related_index] = id.bytes;
        }
        storage.issues[index] = .{
            .code = value.code,
            .category = issueCategoryFromDomain(value.category),
            .severity = issueSeverityFromDomain(value.severity),
            .path = value.path,
            .message = value.message,
            .relatedIds = storage.relatedIds[related_start..related_end],
        };
        related_offset.* = related_end;
    }
    issue_offset.* = issue_end;
    return storage.issues[issue_start..issue_end];
}

fn workoutFromDomain(value: tracking.Workout, storage: WireSnapshotStorage, exercise_offset: *usize, set_offset: *usize, metric_offset: *usize, prescribed_exercise_offset: *usize, prescribed_set_offset: *usize, tag_offset: *usize) SnapshotConversionError!TrackedWorkout {
    const exercise_end = std.math.add(usize, exercise_offset.*, value.exercises.len) catch return error.SnapshotLimitExceeded;
    if (exercise_end > storage.exercises.len) return error.ExerciseBufferTooSmall;
    const exercise_start = exercise_offset.*;
    for (value.exercises, exercise_start..) |exercise, exercise_index| {
        const set_end = std.math.add(usize, set_offset.*, exercise.sets.len) catch return error.SnapshotLimitExceeded;
        if (set_end > storage.sets.len) return error.SetBufferTooSmall;
        const set_start = set_offset.*;
        for (exercise.sets, set_start..) |set, set_index| {
            const targets = try metricsFromDomain(set.target_metrics, storage, metric_offset);
            const actuals = try metricsFromDomain(set.actual_metrics, storage, metric_offset);
            storage.sets[set_index] = .{
                .id = set.id.bytes,
                .kind = set.kind.bytes,
                .targetMetrics = targets,
                .actualMetrics = actuals,
                .status = setStatusFromDomain(set.status),
                .recordedAt = if (set.recorded_at) |at| at.bytes else null,
            };
        }
        storage.exercises[exercise_index] = .{
            .id = exercise.id.bytes,
            .exerciseId = exercise.exercise_id.bytes,
            .sets = storage.sets[set_start..set_end],
        };
        set_offset.* = set_end;
    }
    exercise_offset.* = exercise_end;
    const prescribed_exercise_end = std.math.add(usize, prescribed_exercise_offset.*, value.prescription.len) catch return error.SnapshotLimitExceeded;
    if (prescribed_exercise_end > storage.prescription_exercises.len) return error.ExerciseBufferTooSmall;
    const prescribed_exercise_start = prescribed_exercise_offset.*;
    for (value.prescription, prescribed_exercise_start..) |exercise, output_index| {
        const prescribed_set_end = std.math.add(usize, prescribed_set_offset.*, exercise.sets.len) catch return error.SnapshotLimitExceeded;
        if (prescribed_set_end > storage.prescription_sets.len) return error.SetBufferTooSmall;
        const prescribed_set_start = prescribed_set_offset.*;
        for (exercise.sets, prescribed_set_start..) |set, set_index| {
            storage.prescription_sets[set_index] = .{
                .setId = set.set_id.bytes,
                .kind = set.kind.bytes,
                .targetMetrics = try metricsFromDomain(set.target_metrics, storage, metric_offset),
            };
        }
        const tag_end = std.math.add(usize, tag_offset.*, exercise.tags.len) catch return error.SnapshotLimitExceeded;
        if (tag_end > storage.tags.len) return error.ExerciseBufferTooSmall;
        const tag_start = tag_offset.*;
        for (exercise.tags, tag_start..) |tag, tag_index| storage.tags[tag_index] = tag.bytes;
        storage.prescription_exercises[output_index] = .{
            .membershipId = exercise.membership_id.bytes,
            .exerciseId = exercise.exercise_id.bytes,
            .sets = storage.prescription_sets[prescribed_set_start..prescribed_set_end],
            .notes = exercise.notes,
            .tags = storage.tags[tag_start..tag_end],
        };
        prescribed_set_offset.* = prescribed_set_end;
        tag_offset.* = tag_end;
    }
    prescribed_exercise_offset.* = prescribed_exercise_end;
    return .{
        .id = value.id.bytes,
        .scope = scopeFromDomain(value.scope),
        .revision = value.revision,
        .status = workoutStatusFromDomain(value.status),
        .startedAt = value.started_at.bytes,
        .completedAt = if (value.completed_at) |at| at.bytes else null,
        .exercises = storage.exercises[exercise_start..exercise_end],
        .origin = originFromDomain(value.origin),
        .provenance = provenanceFromDomain(value.provenance),
        .prescription = storage.prescription_exercises[prescribed_exercise_start..prescribed_exercise_end],
    };
}

fn metricsFromDomain(values: []const tracking.Metric, storage: WireSnapshotStorage, offset: *usize) SnapshotConversionError![]const caudex.canonical.Metric {
    const end = std.math.add(usize, offset.*, values.len) catch return error.SnapshotLimitExceeded;
    if (end > storage.metrics.len or end > storage.amountBytes.len) return error.MetricBufferTooSmall;
    const start = offset.*;
    for (values, start..) |metric, index| {
        const amount = metric.value.value.format(&storage.amountBytes[index]) catch return error.MetricBufferTooSmall;
        storage.metrics[index] = .{
            .code = metric.code.bytes,
            .value = .{ .amount = amount, .unit = metric.value.unit.code() },
        };
    }
    offset.* = end;
    return storage.metrics[start..end];
}

fn findDomainWorkout(workouts: []const tracking.Workout, id: tracking.Id, scope: tracking.Scope) ?usize {
    for (workouts, 0..) |workout, index| {
        if (workout.id.eql(id) and workout.scope.host_scope_key.eql(scope.host_scope_key) and
            ((workout.scope.athlete_id == null and scope.athlete_id == null) or
                (workout.scope.athlete_id != null and scope.athlete_id != null and workout.scope.athlete_id.?.eql(scope.athlete_id.?))))
            return index;
    }
    return null;
}

pub fn snapshotToDomain(value: TrackingSnapshot, storage: SnapshotConversionStorage) SnapshotConversionError!tracking.LifecycleSnapshot {
    try validateSnapshot(value);
    if (storage.workouts.len < value.workouts.len) return error.WorkoutBufferTooSmall;
    if (storage.receipts.len < value.startReceipts.len) return error.ReceiptBufferTooSmall;
    if (storage.catalog.len < value.exerciseCatalog.len) return error.ExerciseBufferTooSmall;
    var exercise_offset: usize = 0;
    var set_offset: usize = 0;
    var metric_offset: usize = 0;
    var prescription_exercise_offset: usize = 0;
    var prescription_set_offset: usize = 0;
    var tag_offset: usize = 0;
    for (value.workouts, 0..) |workout, workout_index| {
        storage.workouts[workout_index] = try workoutToDomain(
            workout,
            storage,
            &exercise_offset,
            &set_offset,
            &metric_offset,
            &prescription_exercise_offset,
            &prescription_set_offset,
            &tag_offset,
        );
    }
    for (value.startReceipts, 0..) |receipt, receipt_index| {
        const command = try startWorkoutToDomain(receipt.command);
        const workout_index = findWireWorkout(value.workouts, receipt.workout.id, receipt.workout.scope) orelse
            return error.SnapshotLimitExceeded;
        storage.receipts[receipt_index] = .{
            .command = command,
            .accepted = .{
                .command_id = command.metadata.command_id,
                .disposition = dispositionToDomain(receipt.disposition),
                .workout = storage.workouts[workout_index],
            },
        };
    }
    for (value.exerciseCatalog, 0..) |entry, index| {
        storage.catalog[index] = .{
            .exercise_id = try tracking.Id.parse(entry.exerciseId),
            .availability = availabilityToDomain(entry.availability),
        };
    }
    return .{
        .workouts = storage.workouts[0..value.workouts.len],
        .start_receipts = storage.receipts[0..value.startReceipts.len],
        .exercise_catalog = storage.catalog[0..value.exerciseCatalog.len],
    };
}

fn workoutToDomain(value: TrackedWorkout, storage: SnapshotConversionStorage, exercise_offset: *usize, set_offset: *usize, metric_offset: *usize, prescribed_exercise_offset: *usize, prescribed_set_offset: *usize, tag_offset: *usize) SnapshotConversionError!tracking.Workout {
    const exercise_end = std.math.add(usize, exercise_offset.*, value.exercises.len) catch return error.SnapshotLimitExceeded;
    if (exercise_end > storage.exercises.len) return error.ExerciseBufferTooSmall;
    const exercise_start = exercise_offset.*;
    for (value.exercises, exercise_start..) |exercise, exercise_index| {
        const set_end = std.math.add(usize, set_offset.*, exercise.sets.len) catch return error.SnapshotLimitExceeded;
        if (set_end > storage.sets.len) return error.SetBufferTooSmall;
        const set_start = set_offset.*;
        for (exercise.sets, set_start..) |set, set_index| {
            const target_end = std.math.add(usize, metric_offset.*, set.targetMetrics.len) catch return error.SnapshotLimitExceeded;
            if (target_end > storage.metrics.len) return error.MetricBufferTooSmall;
            const targets = try metricsToDomain(set.targetMetrics, storage.metrics[metric_offset.*..target_end]);
            metric_offset.* = target_end;
            const actual_end = std.math.add(usize, metric_offset.*, set.actualMetrics.len) catch return error.SnapshotLimitExceeded;
            if (actual_end > storage.metrics.len) return error.MetricBufferTooSmall;
            const actuals = try metricsToDomain(set.actualMetrics, storage.metrics[metric_offset.*..actual_end]);
            metric_offset.* = actual_end;
            storage.sets[set_index] = .{
                .id = try tracking.Id.parse(set.id),
                .kind = try tracking.Id.parse(set.kind),
                .target_metrics = targets,
                .actual_metrics = actuals,
                .status = setStatusToDomain(set.status),
                .recorded_at = if (set.recordedAt) |at| try tracking.Timestamp.parse(at) else null,
            };
        }
        storage.exercises[exercise_index] = .{
            .id = try tracking.Id.parse(exercise.id),
            .exercise_id = try tracking.Id.parse(exercise.exerciseId),
            .sets = storage.sets[set_start..set_end],
        };
        set_offset.* = set_end;
    }
    exercise_offset.* = exercise_end;
    const prescribed_exercise_end = std.math.add(usize, prescribed_exercise_offset.*, value.prescription.len) catch return error.SnapshotLimitExceeded;
    if (prescribed_exercise_end > storage.prescription_exercises.len) return error.ExerciseBufferTooSmall;
    const prescribed_exercise_start = prescribed_exercise_offset.*;
    for (value.prescription, prescribed_exercise_start..) |exercise, output_index| {
        const prescribed_set_end = std.math.add(usize, prescribed_set_offset.*, exercise.sets.len) catch return error.SnapshotLimitExceeded;
        if (prescribed_set_end > storage.prescription_sets.len) return error.SetBufferTooSmall;
        const prescribed_set_start = prescribed_set_offset.*;
        for (exercise.sets, prescribed_set_start..) |set, set_index| {
            const metric_end = std.math.add(usize, metric_offset.*, set.targetMetrics.len) catch return error.SnapshotLimitExceeded;
            if (metric_end > storage.metrics.len) return error.MetricBufferTooSmall;
            storage.prescription_sets[set_index] = .{
                .set_id = try tracking.Id.parse(set.setId),
                .kind = try tracking.Id.parse(set.kind),
                .target_metrics = try metricsToDomain(set.targetMetrics, storage.metrics[metric_offset.*..metric_end]),
            };
            metric_offset.* = metric_end;
        }
        const tag_end = std.math.add(usize, tag_offset.*, exercise.tags.len) catch return error.SnapshotLimitExceeded;
        if (tag_end > storage.tags.len) return error.ExerciseBufferTooSmall;
        const tag_start = tag_offset.*;
        for (exercise.tags, tag_start..) |tag, tag_index| storage.tags[tag_index] = try tracking.Id.parse(tag);
        storage.prescription_exercises[output_index] = .{
            .membership_id = try tracking.Id.parse(exercise.membershipId),
            .exercise_id = try tracking.Id.parse(exercise.exerciseId),
            .sets = storage.prescription_sets[prescribed_set_start..prescribed_set_end],
            .notes = exercise.notes,
            .tags = storage.tags[tag_start..tag_end],
        };
        prescribed_set_offset.* = prescribed_set_end;
        tag_offset.* = tag_end;
    }
    prescribed_exercise_offset.* = prescribed_exercise_end;
    return .{
        .id = try tracking.Id.parse(value.id),
        .scope = try scopeToDomain(value.scope),
        .revision = value.revision,
        .status = workoutStatusToDomain(value.status),
        .started_at = try tracking.Timestamp.parse(value.startedAt),
        .completed_at = if (value.completedAt) |at| try tracking.Timestamp.parse(at) else null,
        .exercises = storage.exercises[exercise_start..exercise_end],
        .origin = originToDomain(value.origin),
        .provenance = try provenanceToDomain(value.provenance),
        .prescription = storage.prescription_exercises[prescribed_exercise_start..prescribed_exercise_end],
    };
}

fn findWireWorkout(workouts: []const TrackedWorkout, id: []const u8, scope: Scope) ?usize {
    for (workouts, 0..) |workout, index| {
        if (std.mem.eql(u8, workout.id, id) and std.mem.eql(u8, workout.scope.hostScopeKey, scope.hostScopeKey) and
            ((workout.scope.athleteId == null and scope.athleteId == null) or
                (workout.scope.athleteId != null and scope.athleteId != null and std.mem.eql(u8, workout.scope.athleteId.?, scope.athleteId.?))))
            return index;
    }
    return null;
}

pub fn commandToDomain(value: Command, metric_storage: []tracking.Metric) CommandConversionError!tracking.Command {
    return switch (value) {
        .startWorkout => |command| .{ .start_workout = try startWorkoutToDomain(command) },
        .addExercise => |command| .{ .add_exercise = .{
            .metadata = try metadataToDomain(command.metadata),
            .scope = try scopeToDomain(command.scope),
            .workout_id = try tracking.Id.parse(command.workoutId),
            .expected_revision = command.expectedRevision,
            .membership_id = try tracking.Id.parse(command.membershipId),
            .exercise_id = try tracking.Id.parse(command.exerciseId),
            .anchor = try exerciseAnchorToDomain(command.anchor),
        } },
        .removeExercise => |command| .{ .remove_exercise = try membershipRevisionToDomain(command) },
        .reorderExercise => |command| .{ .reorder_exercise = .{
            .metadata = try metadataToDomain(command.metadata),
            .scope = try scopeToDomain(command.scope),
            .workout_id = try tracking.Id.parse(command.workoutId),
            .expected_revision = command.expectedRevision,
            .membership_id = try tracking.Id.parse(command.membershipId),
            .anchor = try exerciseAnchorToDomain(command.anchor),
        } },
        .addSet => |command| .{ .add_set = .{
            .metadata = try metadataToDomain(command.metadata),
            .scope = try scopeToDomain(command.scope),
            .workout_id = try tracking.Id.parse(command.workoutId),
            .expected_revision = command.expectedRevision,
            .membership_id = try tracking.Id.parse(command.membershipId),
            .set_id = try tracking.Id.parse(command.setId),
            .kind = try tracking.Id.parse(command.kind),
            .target_metrics = try metricsToDomain(command.targetMetrics, metric_storage),
            .anchor = try setAnchorToDomain(command.anchor),
        } },
        .completeSet => |command| .{ .complete_set = .{
            .metadata = try metadataToDomain(command.metadata),
            .scope = try scopeToDomain(command.scope),
            .workout_id = try tracking.Id.parse(command.workoutId),
            .expected_revision = command.expectedRevision,
            .membership_id = try tracking.Id.parse(command.membershipId),
            .set_id = try tracking.Id.parse(command.setId),
            .actual_metrics = try metricsToDomain(command.actualMetrics, metric_storage),
            .status = try completedSetStatusToDomain(command.status),
            .completed_at = try tracking.Timestamp.parse(command.completedAt),
        } },
        .skipSet => |command| .{ .skip_set = .{
            .metadata = try metadataToDomain(command.metadata),
            .scope = try scopeToDomain(command.scope),
            .workout_id = try tracking.Id.parse(command.workoutId),
            .expected_revision = command.expectedRevision,
            .membership_id = try tracking.Id.parse(command.membershipId),
            .set_id = try tracking.Id.parse(command.setId),
            .skipped_at = try tracking.Timestamp.parse(command.at),
        } },
        .reopenSet => |command| .{ .reopen_set = try setRevisionToDomain(command) },
        .removeSet => |command| .{ .remove_set = try setRevisionToDomain(command) },
        .reorderSet => |command| .{ .reorder_set = .{
            .metadata = try metadataToDomain(command.metadata),
            .scope = try scopeToDomain(command.scope),
            .workout_id = try tracking.Id.parse(command.workoutId),
            .expected_revision = command.expectedRevision,
            .membership_id = try tracking.Id.parse(command.membershipId),
            .set_id = try tracking.Id.parse(command.setId),
            .anchor = try setAnchorToDomain(command.anchor),
        } },
        .completeWorkout => |command| .{ .complete_workout = .{
            .metadata = try metadataToDomain(command.metadata),
            .scope = try scopeToDomain(command.scope),
            .workout_id = try tracking.Id.parse(command.workoutId),
            .expected_revision = command.expectedRevision,
            .completed_at = try tracking.Timestamp.parse(command.completedAt),
        } },
    };
}

pub fn batchCommandsToDomain(values: []const Command, command_storage: []tracking.Command, metric_storage: []tracking.Metric) CommandConversionError![]const tracking.Command {
    if (values.len == 0) return command_storage[0..0];
    if (values.len > max_commands_per_batch or command_storage.len < values.len)
        return error.CommandBufferTooSmall;
    var metric_offset: usize = 0;
    for (values, 0..) |command, index| {
        const metric_count = commandMetricCount(command);
        const metric_end = std.math.add(usize, metric_offset, metric_count) catch return error.MetricBufferTooSmall;
        if (metric_end > metric_storage.len) return error.MetricBufferTooSmall;
        command_storage[index] = try commandToDomain(command, metric_storage[metric_offset..metric_end]);
        metric_offset = metric_end;
    }
    return command_storage[0..values.len];
}

pub const CommandFormatStorage = struct {
    metrics: []caudex.canonical.Metric,
    amountBytes: [][64]u8,
};

pub const CommandFormatError = error{ UnsupportedCommand, MetricBufferTooSmall, SnapshotLimitExceeded };

pub fn commandFromDomain(value: tracking.Command, storage: CommandFormatStorage) CommandFormatError!Command {
    return switch (value) {
        .start_workout => |command| .{ .startWorkout = startWorkoutFromDomain(command) },
        .add_exercise => |command| .{ .addExercise = .{
            .metadata = metadataFromDomain(command.metadata),
            .scope = scopeFromDomain(command.scope),
            .workoutId = command.workout_id.bytes,
            .expectedRevision = command.expected_revision,
            .membershipId = command.membership_id.bytes,
            .exerciseId = command.exercise_id.bytes,
            .anchor = anchorFromExerciseDomain(command.anchor),
        } },
        .remove_exercise => |command| .{ .removeExercise = membershipRevisionFromDomain(command) },
        .reorder_exercise => |command| .{ .reorderExercise = .{
            .metadata = metadataFromDomain(command.metadata),
            .scope = scopeFromDomain(command.scope),
            .workoutId = command.workout_id.bytes,
            .expectedRevision = command.expected_revision,
            .membershipId = command.membership_id.bytes,
            .anchor = anchorFromExerciseDomain(command.anchor),
        } },
        .add_set => |command| .{ .addSet = .{
            .metadata = metadataFromDomain(command.metadata),
            .scope = scopeFromDomain(command.scope),
            .workoutId = command.workout_id.bytes,
            .expectedRevision = command.expected_revision,
            .membershipId = command.membership_id.bytes,
            .setId = command.set_id.bytes,
            .kind = command.kind.bytes,
            .targetMetrics = try commandMetricsFromDomain(command.target_metrics, storage),
            .anchor = anchorFromSetDomain(command.anchor),
        } },
        .complete_set => |command| .{ .completeSet = .{
            .metadata = metadataFromDomain(command.metadata),
            .scope = scopeFromDomain(command.scope),
            .workoutId = command.workout_id.bytes,
            .expectedRevision = command.expected_revision,
            .membershipId = command.membership_id.bytes,
            .setId = command.set_id.bytes,
            .actualMetrics = try commandMetricsFromDomain(command.actual_metrics, storage),
            .status = setStatusFromDomain(command.status),
            .completedAt = command.completed_at.bytes,
        } },
        .skip_set => |command| .{ .skipSet = .{
            .metadata = metadataFromDomain(command.metadata),
            .scope = scopeFromDomain(command.scope),
            .workoutId = command.workout_id.bytes,
            .expectedRevision = command.expected_revision,
            .membershipId = command.membership_id.bytes,
            .setId = command.set_id.bytes,
            .at = command.skipped_at.bytes,
        } },
        .reopen_set => |command| .{ .reopenSet = setRevisionFromDomain(command) },
        .remove_set => |command| .{ .removeSet = setRevisionFromDomain(command) },
        .reorder_set => |command| .{ .reorderSet = .{
            .metadata = metadataFromDomain(command.metadata),
            .scope = scopeFromDomain(command.scope),
            .workoutId = command.workout_id.bytes,
            .expectedRevision = command.expected_revision,
            .membershipId = command.membership_id.bytes,
            .setId = command.set_id.bytes,
            .anchor = anchorFromSetDomain(command.anchor),
        } },
        .complete_workout => |command| .{ .completeWorkout = .{
            .metadata = metadataFromDomain(command.metadata),
            .scope = scopeFromDomain(command.scope),
            .workoutId = command.workout_id.bytes,
            .expectedRevision = command.expected_revision,
            .completedAt = command.completed_at.bytes,
        } },
        .log_set, .cancel_workout => error.UnsupportedCommand,
    };
}

fn commandMetricsFromDomain(values: []const tracking.Metric, storage: CommandFormatStorage) CommandFormatError![]const caudex.canonical.Metric {
    var offset: usize = 0;
    var empty_workouts: [0]TrackedWorkout = .{};
    var empty_receipts: [0]StartReceipt = .{};
    var empty_exercises: [0]ExerciseMembership = .{};
    var empty_sets: [0]TrackedSet = .{};
    var empty_prescribed_exercises: [0]PrescribedExercise = .{};
    var empty_prescribed_sets: [0]PrescribedSet = .{};
    var empty_tags: [0][]const u8 = .{};
    const wire_storage: WireSnapshotStorage = .{
        .workouts = &empty_workouts,
        .receipts = &empty_receipts,
        .exercises = &empty_exercises,
        .sets = &empty_sets,
        .metrics = storage.metrics,
        .amountBytes = storage.amountBytes,
        .prescription_exercises = &empty_prescribed_exercises,
        .prescription_sets = &empty_prescribed_sets,
        .tags = &empty_tags,
    };
    return metricsFromDomain(values, wire_storage, &offset) catch |err| switch (err) {
        error.MetricBufferTooSmall => error.MetricBufferTooSmall,
        else => error.SnapshotLimitExceeded,
    };
}

fn metadataFromDomain(value: tracking.CommandMetadata) CommandMetadata {
    return .{ .commandId = value.command_id.bytes, .occurredAt = value.occurred_at.bytes };
}

fn membershipRevisionFromDomain(value: tracking.RemoveExerciseCommand) MembershipRevision {
    return .{ .metadata = metadataFromDomain(value.metadata), .scope = scopeFromDomain(value.scope), .workoutId = value.workout_id.bytes, .expectedRevision = value.expected_revision, .membershipId = value.membership_id.bytes };
}

fn setRevisionFromDomain(value: tracking.ReopenSetCommand) SetRevision {
    return .{ .metadata = metadataFromDomain(value.metadata), .scope = scopeFromDomain(value.scope), .workoutId = value.workout_id.bytes, .expectedRevision = value.expected_revision, .membershipId = value.membership_id.bytes, .setId = value.set_id.bytes };
}

fn anchorFromExerciseDomain(value: tracking.ExerciseAnchor) Anchor {
    return switch (value) {
        .beginning => .beginning,
        .end => .end,
        .before => |id| .{ .before = id.bytes },
        .after => |id| .{ .after = id.bytes },
    };
}

fn anchorFromSetDomain(value: tracking.SetAnchor) Anchor {
    return switch (value) {
        .beginning => .beginning,
        .end => .end,
        .before => |id| .{ .before = id.bytes },
        .after => |id| .{ .after = id.bytes },
    };
}

fn commandMetricCount(command: Command) usize {
    return switch (command) {
        .addSet => |value| value.targetMetrics.len,
        .completeSet => |value| value.actualMetrics.len,
        else => 0,
    };
}

pub fn startWorkoutToDomain(value: StartWorkout) ConversionError!tracking.StartWorkoutCommand {
    return .{
        .metadata = .{
            .command_id = try tracking.Id.parse(value.metadata.commandId),
            .occurred_at = try tracking.Timestamp.parse(value.metadata.occurredAt),
        },
        .scope = .{
            .host_scope_key = try tracking.Id.parse(value.scope.hostScopeKey),
            .athlete_id = if (value.scope.athleteId) |id| try tracking.Id.parse(id) else null,
        },
        .workout_id = try tracking.Id.parse(value.workoutId),
        .started_at = try tracking.Timestamp.parse(value.startedAt),
    };
}

fn metadataToDomain(value: CommandMetadata) ConversionError!tracking.CommandMetadata {
    return .{
        .command_id = try tracking.Id.parse(value.commandId),
        .occurred_at = try tracking.Timestamp.parse(value.occurredAt),
    };
}

fn scopeToDomain(value: Scope) tracking.Id.ParseError!tracking.Scope {
    return .{
        .host_scope_key = try tracking.Id.parse(value.hostScopeKey),
        .athlete_id = if (value.athleteId) |id| try tracking.Id.parse(id) else null,
    };
}

fn membershipRevisionToDomain(value: MembershipRevision) ConversionError!tracking.RemoveExerciseCommand {
    return .{
        .metadata = try metadataToDomain(value.metadata),
        .scope = try scopeToDomain(value.scope),
        .workout_id = try tracking.Id.parse(value.workoutId),
        .expected_revision = value.expectedRevision,
        .membership_id = try tracking.Id.parse(value.membershipId),
    };
}

fn setRevisionToDomain(value: SetRevision) ConversionError!tracking.ReopenSetCommand {
    return .{
        .metadata = try metadataToDomain(value.metadata),
        .scope = try scopeToDomain(value.scope),
        .workout_id = try tracking.Id.parse(value.workoutId),
        .expected_revision = value.expectedRevision,
        .membership_id = try tracking.Id.parse(value.membershipId),
        .set_id = try tracking.Id.parse(value.setId),
    };
}

fn exerciseAnchorToDomain(value: Anchor) tracking.Id.ParseError!tracking.ExerciseAnchor {
    return switch (value) {
        .beginning => .beginning,
        .end => .end,
        .before => |id| .{ .before = try tracking.Id.parse(id) },
        .after => |id| .{ .after = try tracking.Id.parse(id) },
    };
}

fn setAnchorToDomain(value: Anchor) tracking.Id.ParseError!tracking.SetAnchor {
    return switch (value) {
        .beginning => .beginning,
        .end => .end,
        .before => |id| .{ .before = try tracking.Id.parse(id) },
        .after => |id| .{ .after = try tracking.Id.parse(id) },
    };
}

fn completedSetStatusToDomain(value: SetStatus) error{UnsupportedSetStatus}!tracking.SetStatus {
    return switch (value) {
        .completed => .completed,
        .partial => .partial,
        .failed => .failed,
        .open, .skipped => error.UnsupportedSetStatus,
    };
}

fn metricsToDomain(values: []const caudex.canonical.Metric, storage: []tracking.Metric) CommandConversionError![]const tracking.Metric {
    if (values.len > max_metrics_per_set) return error.MetricBufferTooSmall;
    if (storage.len < values.len) return error.MetricBufferTooSmall;
    for (values, 0..) |metric, index| {
        storage[index] = .{
            .code = try tracking.Id.parse(metric.code),
            .value = .{
                .value = try tracking.Decimal.parse(metric.value.amount),
                .unit = caudex.primitives.Unit.parse(metric.value.unit) catch return error.UnknownUnit,
            },
        };
    }
    return storage[0..values.len];
}

pub fn startWorkoutFromDomain(value: tracking.StartWorkoutCommand) StartWorkout {
    return .{
        .metadata = .{ .commandId = value.metadata.command_id.bytes, .occurredAt = value.metadata.occurred_at.bytes },
        .scope = scopeFromDomain(value.scope),
        .workoutId = value.workout_id.bytes,
        .startedAt = value.started_at.bytes,
    };
}

pub fn workoutStatusFromDomain(value: tracking.WorkoutStatus) WorkoutStatus {
    return switch (value) {
        .active => .active,
        .completed => .completed,
        .cancelled => .cancelled,
    };
}

pub fn workoutStatusToDomain(value: WorkoutStatus) tracking.WorkoutStatus {
    return switch (value) {
        .active => .active,
        .completed => .completed,
        .cancelled => .cancelled,
    };
}

pub fn setStatusFromDomain(value: tracking.SetStatus) SetStatus {
    return switch (value) {
        .open => .open,
        .completed => .completed,
        .partial => .partial,
        .failed => .failed,
        .skipped => .skipped,
    };
}

pub fn setStatusToDomain(value: SetStatus) tracking.SetStatus {
    return switch (value) {
        .open => .open,
        .completed => .completed,
        .partial => .partial,
        .failed => .failed,
        .skipped => .skipped,
    };
}

pub fn issueCategoryFromDomain(value: tracking.IssueCategory) IssueCategory {
    return switch (value) {
        .validation => .validation,
        .not_found => .not_found,
        .conflict => .conflict,
    };
}

pub fn issueSeverityFromDomain(value: tracking.IssueSeverity) IssueSeverity {
    return switch (value) {
        .warning => .warning,
        .@"error" => .@"error",
    };
}

pub fn dispositionFromDomain(value: tracking.CommandDisposition) CommandDisposition {
    return switch (value) {
        .applied => .applied,
        .replayed => .replayed,
    };
}

pub fn dispositionToDomain(value: CommandDisposition) tracking.CommandDisposition {
    return switch (value) {
        .applied => .applied,
        .replayed => .replayed,
    };
}

pub fn availabilityFromDomain(value: tracking.ExerciseAvailability) ExerciseAvailability {
    return switch (value) {
        .active => .active,
        .archived => .archived,
    };
}

pub fn availabilityToDomain(value: ExerciseAvailability) tracking.ExerciseAvailability {
    return switch (value) {
        .active => .active,
        .archived => .archived,
    };
}

fn originFromDomain(value: tracking.WorkoutOrigin) WorkoutOrigin {
    return switch (value) {
        .manual => .manual,
        .template => .template,
        .recommendation => .recommendation,
    };
}

fn originToDomain(value: WorkoutOrigin) tracking.WorkoutOrigin {
    return switch (value) {
        .manual => .manual,
        .template => .template,
        .recommendation => .recommendation,
    };
}

fn provenanceFromDomain(value: ?tracking.Provenance) ?Provenance {
    const provenance = value orelse return null;
    return switch (provenance) {
        .recommendation => |item| .{ .recommendation = .{
            .acceptedRecommendationId = item.accepted_recommendation_id.bytes,
            .inputFingerprint = item.input_fingerprint,
            .resultFingerprint = item.result_fingerprint,
            .methodologyId = item.methodology_id.bytes,
            .methodologyVersion = item.methodology_version,
            .methodologyConfigVersion = item.methodology_config_version,
            .methodologyStateRevision = item.methodology_state_revision,
            .methodologyStateFingerprint = item.methodology_state_fingerprint,
        } },
        .template => |item| .{ .template = .{ .templateId = item.template_id.bytes, .templateRevision = item.template_revision } },
    };
}

fn provenanceToDomain(value: ?Provenance) tracking.Id.ParseError!?tracking.Provenance {
    const provenance = value orelse return null;
    return switch (provenance) {
        .recommendation => |item| .{ .recommendation = .{
            .accepted_recommendation_id = try tracking.Id.parse(item.acceptedRecommendationId),
            .input_fingerprint = item.inputFingerprint,
            .result_fingerprint = item.resultFingerprint,
            .methodology_id = try tracking.Id.parse(item.methodologyId),
            .methodology_version = item.methodologyVersion,
            .methodology_config_version = item.methodologyConfigVersion,
            .methodology_state_revision = item.methodologyStateRevision,
            .methodology_state_fingerprint = item.methodologyStateFingerprint,
        } },
        .template => |item| .{ .template = .{ .template_id = try tracking.Id.parse(item.templateId), .template_revision = item.templateRevision } },
    };
}

fn scopeFromDomain(value: tracking.Scope) Scope {
    return .{ .hostScopeKey = value.host_scope_key.bytes, .athleteId = if (value.athlete_id) |id| id.bytes else null };
}

test "independent enums map explicitly in both directions" {
    inline for (std.meta.tags(WorkoutStatus)) |status| {
        try std.testing.expectEqual(status, workoutStatusFromDomain(workoutStatusToDomain(status)));
    }
    inline for (std.meta.tags(SetStatus)) |status| {
        try std.testing.expectEqual(status, setStatusFromDomain(setStatusToDomain(status)));
    }
    inline for (std.meta.tags(ExerciseAvailability)) |availability| {
        try std.testing.expectEqual(availability, availabilityFromDomain(availabilityToDomain(availability)));
    }
}
