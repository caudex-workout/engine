//! Public, database-independent contracts for host-owned workout tracking.
//!
//! This package defines borrowed command, query, state, and result values plus
//! deterministic lifecycle calculations over explicit snapshots. It performs
//! no storage, I/O, allocation, clock reads, or hidden mutation.

const std = @import("std");
const caudex = @import("caudex");

pub const contract_version: u32 = 1;

pub const Id = caudex.primitives.Id;
pub const Timestamp = caudex.primitives.Timestamp;
pub const Metric = caudex.training.Metric;
pub const SetStatus = caudex.training.SetStatus;

/// Identifies host-owned workout data without defining an athlete repository.
pub const Scope = struct {
    host_scope_key: Id,
    athlete_id: ?Id = null,
};

/// A caller-supplied idempotency key and explicit time for one command.
pub const CommandMetadata = struct {
    command_id: Id,
    occurred_at: Timestamp,
};

pub const WorkoutStatus = enum {
    active,
    completed,
};

pub const LoggedSet = struct {
    id: Id,
    recorded_at: Timestamp,
    kind: Id,
    actual_metrics: []const Metric,
    target_metrics: []const Metric = &.{},
    status: SetStatus,
};

pub const ExerciseMembership = struct {
    id: Id,
    exercise_id: Id,
    /// Host-supplied stable ordering key; it is not a public numeric position.
    order_key: []const u8,
    sets: []const LoggedSet = &.{},
};

/// Borrowed workout state returned by commands and queries.
pub const Workout = struct {
    id: Id,
    scope: Scope,
    revision: u64,
    status: WorkoutStatus,
    started_at: Timestamp,
    completed_at: ?Timestamp = null,
    exercises: []const ExerciseMembership = &.{},
};

pub const StartWorkoutCommand = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    started_at: Timestamp,
};

pub const AddExerciseCommand = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    membership_id: Id,
    exercise_id: Id,
    order_key: []const u8,
};

pub const LogSetCommand = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    membership_id: Id,
    set: LoggedSet,
};

/// Completes an active workout even when it has no exercises or completed sets.
pub const CompleteWorkoutCommand = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    completed_at: Timestamp,
};

pub const Command = union(enum) {
    start_workout: StartWorkoutCommand,
    add_exercise: AddExerciseCommand,
    log_set: LogSetCommand,
    complete_workout: CompleteWorkoutCommand,
};

pub const IssueCategory = enum {
    validation,
    not_found,
    conflict,
};

pub const IssueSeverity = enum {
    warning,
    @"error",
};

/// A stable machine-readable expected outcome. Runtime and adapter failures are
/// returned separately by the implementation executing the contract.
pub const Issue = struct {
    code: []const u8,
    category: IssueCategory,
    severity: IssueSeverity,
    path: ?[]const u8 = null,
    message: []const u8,
    related_ids: []const Id = &.{},
};

pub const issue_codes = struct {
    pub const invalid_identifier = "tracking.invalid_identifier";
    pub const invalid_timestamp = "tracking.invalid_timestamp";
    pub const invalid_timestamp_order = "tracking.invalid_timestamp_order";
    pub const workout_id_conflict = "tracking.workout_id_conflict";
    pub const workout_not_found = "tracking.workout_not_found";
    pub const revision_conflict = "tracking.revision_conflict";
    pub const command_payload_conflict = "tracking.command_payload_conflict";
    pub const short_workout_completed = "tracking.short_workout_completed";
};

pub const CommandDisposition = enum {
    /// The command produced a new accepted state transition.
    applied,
    /// The command ID and payload matched a previously accepted command.
    replayed,
};

pub const AcceptedCommand = struct {
    command_id: Id,
    disposition: CommandDisposition,
    workout: Workout,
    issues: []const Issue = &.{},
};

pub const RejectedCommand = struct {
    command_id: Id,
    issues: []const Issue,
};

pub const CommandResult = union(enum) {
    accepted: AcceptedCommand,
    rejected: RejectedCommand,
};

pub const ReadWorkoutQuery = struct {
    scope: Scope,
    workout_id: Id,
};

pub const ReadWorkoutResult = union(enum) {
    found: Workout,
    not_found: Issue,
};

pub const ListActiveWorkoutsQuery = struct {
    scope: Scope,
    max_results: u16,
};

/// Makes zero, one, or multiple active workouts explicit so hosts never guess.
pub const ActiveWorkoutSelection = union(enum) {
    none,
    one: Workout,
    ambiguous: []const Workout,
};

pub const Query = union(enum) {
    read_workout: ReadWorkoutQuery,
    list_active_workouts: ListActiveWorkoutsQuery,
};

/// A host-persisted receipt supplied explicitly for deterministic retry checks.
pub const StartReceipt = struct {
    command: StartWorkoutCommand,
    accepted: AcceptedCommand,
};

/// Complete borrowed state visible to the minimal lifecycle calculations.
pub const LifecycleSnapshot = struct {
    workouts: []const Workout = &.{},
    start_receipts: []const StartReceipt = &.{},
};

pub const DecisionError = error{IssueBufferTooSmall};
pub const QueryError = error{OutputBufferTooSmall};

/// Proposes a new active workout or returns a structured rejection.
///
/// The function does not allocate, mutate the snapshot, persist a receipt, or
/// obtain IDs or timestamps. The host decides whether to accept and store the
/// returned value and receipt.
pub fn startWorkout(
    snapshot: LifecycleSnapshot,
    command: StartWorkoutCommand,
    issue_storage: []Issue,
) DecisionError!CommandResult {
    if (!validId(command.metadata.command_id) or
        !validId(command.scope.host_scope_key) or
        (command.scope.athlete_id != null and
            !validId(command.scope.athlete_id.?)) or
        !validId(command.workout_id))
    {
        return reject(
            command.metadata.command_id,
            issue_storage,
            .{
                .code = issue_codes.invalid_identifier,
                .category = .validation,
                .severity = .@"error",
                .message = "A tracking identifier is invalid.",
            },
        );
    }
    if (!validTimestamp(command.metadata.occurred_at) or
        !validTimestamp(command.started_at))
    {
        return reject(
            command.metadata.command_id,
            issue_storage,
            .{
                .code = issue_codes.invalid_timestamp,
                .category = .validation,
                .severity = .@"error",
                .message = "A command timestamp is not valid RFC 3339.",
            },
        );
    }

    for (snapshot.start_receipts) |receipt| {
        if (!receipt.command.metadata.command_id.eql(command.metadata.command_id))
            continue;
        if (!startCommandsEqual(receipt.command, command)) {
            return reject(
                command.metadata.command_id,
                issue_storage,
                .{
                    .code = issue_codes.command_payload_conflict,
                    .category = .conflict,
                    .severity = .@"error",
                    .message = "The command ID was already used with another payload.",
                },
            );
        }
        var replayed = receipt.accepted;
        replayed.disposition = .replayed;
        return .{ .accepted = replayed };
    }

    for (snapshot.workouts) |workout| {
        if (workout.id.eql(command.workout_id)) {
            return reject(
                command.metadata.command_id,
                issue_storage,
                .{
                    .code = issue_codes.workout_id_conflict,
                    .category = .conflict,
                    .severity = .@"error",
                    .message = "The workout ID already exists.",
                },
            );
        }
    }

    return .{ .accepted = .{
        .command_id = command.metadata.command_id,
        .disposition = .applied,
        .workout = .{
            .id = command.workout_id,
            .scope = command.scope,
            .revision = 1,
            .status = .active,
            .started_at = command.started_at,
        },
    } };
}

/// Reads one workout from an explicit host snapshot.
pub fn readWorkout(
    snapshot: LifecycleSnapshot,
    query: ReadWorkoutQuery,
) ReadWorkoutResult {
    for (snapshot.workouts) |workout| {
        if (workout.id.eql(query.workout_id) and
            scopesEqual(workout.scope, query.scope))
        {
            return .{ .found = workout };
        }
    }
    return .{ .not_found = .{
        .code = issue_codes.workout_not_found,
        .category = .not_found,
        .severity = .@"error",
        .message = "No workout matched the requested scope and ID.",
    } };
}

/// Selects active workouts without guessing when multiple matches exist.
///
/// Up to `query.max_results` ambiguous values are written to `output`. The
/// function still detects ambiguity when the configured result bound is zero.
pub fn selectActiveWorkouts(
    snapshot: LifecycleSnapshot,
    query: ListActiveWorkoutsQuery,
    output: []Workout,
) QueryError!ActiveWorkoutSelection {
    var matching: usize = 0;
    var first: ?Workout = null;
    var written: usize = 0;
    for (snapshot.workouts) |workout| {
        if (workout.status != .active or !scopesEqual(workout.scope, query.scope))
            continue;
        matching += 1;
        if (first == null) first = workout;
        if (written < query.max_results) {
            if (written >= output.len) return error.OutputBufferTooSmall;
            output[written] = workout;
            written += 1;
        }
    }
    if (matching == 0) return .none;
    if (matching == 1) return .{ .one = first.? };
    return .{ .ambiguous = output[0..written] };
}

fn reject(
    command_id: Id,
    storage: []Issue,
    issue: Issue,
) DecisionError!CommandResult {
    if (storage.len == 0) return error.IssueBufferTooSmall;
    storage[0] = issue;
    return .{ .rejected = .{
        .command_id = command_id,
        .issues = storage[0..1],
    } };
}

fn validId(id: Id) bool {
    _ = Id.parse(id.bytes) catch return false;
    return true;
}

fn validTimestamp(timestamp: Timestamp) bool {
    _ = Timestamp.parse(timestamp.bytes) catch return false;
    return true;
}

fn startCommandsEqual(
    left: StartWorkoutCommand,
    right: StartWorkoutCommand,
) bool {
    return left.metadata.command_id.eql(right.metadata.command_id) and
        timestampsEqual(left.metadata.occurred_at, right.metadata.occurred_at) and
        scopesEqual(left.scope, right.scope) and
        left.workout_id.eql(right.workout_id) and
        timestampsEqual(left.started_at, right.started_at);
}

fn scopesEqual(left: Scope, right: Scope) bool {
    if (!left.host_scope_key.eql(right.host_scope_key))
        return false;
    if (left.athlete_id == null or right.athlete_id == null)
        return left.athlete_id == null and right.athlete_id == null;
    return left.athlete_id.?.eql(right.athlete_id.?);
}

fn timestampsEqual(left: Timestamp, right: Timestamp) bool {
    return std.mem.eql(u8, left.bytes, right.bytes);
}
