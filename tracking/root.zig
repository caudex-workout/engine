//! Public, database-independent contracts for host-owned workout tracking.
//!
//! This package defines borrowed command, query, state, and result values. It
//! performs no storage, I/O, allocation, clock reads, or command execution.

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
    pub const invalid_timestamp_order = "tracking.invalid_timestamp_order";
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
