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
