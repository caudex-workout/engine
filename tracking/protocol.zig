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
pub const max_exercises_per_workout: usize = 128;
pub const max_sets_per_exercise: usize = 256;
pub const max_metrics_per_set: usize = 32;

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

pub const TrackedWorkout = struct {
    id: []const u8,
    scope: Scope,
    revision: u64,
    status: WorkoutStatus,
    startedAt: []const u8,
    completedAt: ?[]const u8 = null,
    exercises: []const ExerciseMembership = &.{},
};

pub const TrackingSnapshot = struct {
    workouts: []const TrackedWorkout = &.{},
    startReceipts: []const StartReceipt = &.{},
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
    try validateSnapshotBounds(parsed.value.snapshot);
    return parsed;
}

pub fn decodeAtomicBatchRequest(allocator: std.mem.Allocator, input: []const u8, limits: Limits) DecodeError!std.json.Parsed(AtomicBatchRequest) {
    const parsed = try caudex.canonical_json.decodeValue(AtomicBatchRequest, allocator, input, limits.json);
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != schema_version) return error.UnsupportedVersion;
    if (parsed.value.commands.len == 0) return error.EmptyBatch;
    if (parsed.value.commands.len > limits.max_commands) return error.BatchLimitExceeded;
    try validateSnapshotBounds(parsed.value.snapshot);
    return parsed;
}

pub fn encode(value: anytype, output: []u8) caudex.canonical_json.EncodeError![]const u8 {
    return caudex.canonical_json.encode(value, output);
}

fn validateSnapshotBounds(snapshot: TrackingSnapshot) error{SnapshotLimitExceeded}!void {
    if (snapshot.workouts.len > max_workouts) return error.SnapshotLimitExceeded;
    if (snapshot.startReceipts.len > max_workouts) return error.SnapshotLimitExceeded;
    for (snapshot.workouts) |workout| {
        if (workout.exercises.len > max_exercises_per_workout) return error.SnapshotLimitExceeded;
        for (workout.exercises) |exercise| {
            if (exercise.sets.len > max_sets_per_exercise) return error.SnapshotLimitExceeded;
            for (exercise.sets) |set| {
                if (set.targetMetrics.len > max_metrics_per_set or set.actualMetrics.len > max_metrics_per_set)
                    return error.SnapshotLimitExceeded;
            }
        }
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
};

pub const WireSnapshotStorage = struct {
    workouts: []TrackedWorkout,
    receipts: []StartReceipt,
    exercises: []ExerciseMembership,
    sets: []TrackedSet,
    metrics: []caudex.canonical.Metric,
    amountBytes: [][64]u8,
};

pub fn snapshotFromDomain(value: tracking.LifecycleSnapshot, storage: WireSnapshotStorage) SnapshotConversionError!TrackingSnapshot {
    if (value.workouts.len > max_workouts) return error.SnapshotLimitExceeded;
    if (storage.workouts.len < value.workouts.len) return error.WorkoutBufferTooSmall;
    if (storage.receipts.len < value.start_receipts.len) return error.ReceiptBufferTooSmall;
    var exercise_offset: usize = 0;
    var set_offset: usize = 0;
    var metric_offset: usize = 0;
    for (value.workouts, 0..) |workout, index| {
        storage.workouts[index] = try workoutFromDomain(
            workout,
            storage,
            &exercise_offset,
            &set_offset,
            &metric_offset,
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
    return .{
        .workouts = storage.workouts[0..value.workouts.len],
        .startReceipts = storage.receipts[0..value.start_receipts.len],
    };
}

fn workoutFromDomain(value: tracking.Workout, storage: WireSnapshotStorage, exercise_offset: *usize, set_offset: *usize, metric_offset: *usize) SnapshotConversionError!TrackedWorkout {
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
    return .{
        .id = value.id.bytes,
        .scope = scopeFromDomain(value.scope),
        .revision = value.revision,
        .status = workoutStatusFromDomain(value.status),
        .startedAt = value.started_at.bytes,
        .completedAt = if (value.completed_at) |at| at.bytes else null,
        .exercises = storage.exercises[exercise_start..exercise_end],
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
    try validateSnapshotBounds(value);
    if (storage.workouts.len < value.workouts.len) return error.WorkoutBufferTooSmall;
    if (storage.receipts.len < value.startReceipts.len) return error.ReceiptBufferTooSmall;
    var exercise_offset: usize = 0;
    var set_offset: usize = 0;
    var metric_offset: usize = 0;
    for (value.workouts, 0..) |workout, workout_index| {
        storage.workouts[workout_index] = try workoutToDomain(
            workout,
            storage,
            &exercise_offset,
            &set_offset,
            &metric_offset,
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
    return .{
        .workouts = storage.workouts[0..value.workouts.len],
        .start_receipts = storage.receipts[0..value.startReceipts.len],
    };
}

fn workoutToDomain(value: TrackedWorkout, storage: SnapshotConversionStorage, exercise_offset: *usize, set_offset: *usize, metric_offset: *usize) SnapshotConversionError!tracking.Workout {
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
    return .{
        .id = try tracking.Id.parse(value.id),
        .scope = try scopeToDomain(value.scope),
        .revision = value.revision,
        .status = workoutStatusToDomain(value.status),
        .started_at = try tracking.Timestamp.parse(value.startedAt),
        .completed_at = if (value.completedAt) |at| try tracking.Timestamp.parse(at) else null,
        .exercises = storage.exercises[exercise_start..exercise_end],
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
}
