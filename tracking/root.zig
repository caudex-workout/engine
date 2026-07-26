//! Public, database-independent contracts for host-owned workout tracking.
//!
//! This package defines borrowed command, query, state, and result values plus
//! deterministic lifecycle calculations over explicit snapshots. It performs
//! no storage, I/O, allocation, clock reads, or hidden mutation.

const std = @import("std");
const caudex = @import("caudex");

pub const contract_version: u32 = 3;

pub const Id = caudex.primitives.Id;
pub const Timestamp = caudex.primitives.Timestamp;
pub const Metric = caudex.training.Metric;
pub const Measurement = caudex.primitives.Measurement;
pub const Decimal = caudex.primitives.Decimal;

pub const metric_codes = struct {
    pub const repetitions = "repetitions";
    pub const load = "load";
    pub const rir = "rir";
    pub const rpe = "rpe";
    pub const duration = "duration";
};

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

pub const SetStatus = enum {
    open,
    completed,
    partial,
    failed,
    skipped,
};

pub const TrackedSet = struct {
    id: Id,
    kind: Id,
    target_metrics: []const Metric = &.{},
    actual_metrics: []const Metric = &.{},
    status: SetStatus = .open,
    recorded_at: ?Timestamp = null,
};

pub const LoggedSet = TrackedSet;

pub const ExerciseMembership = struct {
    id: Id,
    exercise_id: Id,
    sets: []const LoggedSet = &.{},
};

/// A semantic insertion point. Numeric persistence positions are private.
pub const ExerciseAnchor = union(enum) {
    beginning,
    end,
    before: Id,
    after: Id,
};

pub const SetAnchor = union(enum) {
    beginning,
    end,
    before: Id,
    after: Id,
};

pub const ExerciseAvailability = enum {
    active,
    archived,
};

/// Explicit catalog state supplied to deterministic exercise decisions.
pub const ExerciseCatalogEntry = struct {
    exercise_id: Id,
    availability: ExerciseAvailability,
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
    anchor: ExerciseAnchor,
};

pub const RemoveExerciseCommand = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    membership_id: Id,
};

pub const ReorderExerciseCommand = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    membership_id: Id,
    anchor: ExerciseAnchor,
};

pub const AddSetCommand = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    membership_id: Id,
    set_id: Id,
    kind: Id,
    target_metrics: []const Metric = &.{},
    anchor: SetAnchor,
};

pub const CompleteSetCommand = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    membership_id: Id,
    set_id: Id,
    actual_metrics: []const Metric,
    status: SetStatus = .completed,
    completed_at: Timestamp,
};

pub const SkipSetCommand = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    membership_id: Id,
    set_id: Id,
    skipped_at: Timestamp,
};

pub const ReopenSetCommand = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    membership_id: Id,
    set_id: Id,
};

pub const RemoveSetCommand = ReopenSetCommand;

pub const ReorderSetCommand = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    membership_id: Id,
    set_id: Id,
    anchor: SetAnchor,
};

pub const LogSetCommand = CompleteSetCommand;

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
    remove_exercise: RemoveExerciseCommand,
    reorder_exercise: ReorderExerciseCommand,
    add_set: AddSetCommand,
    log_set: LogSetCommand,
    complete_set: CompleteSetCommand,
    skip_set: SkipSetCommand,
    reopen_set: ReopenSetCommand,
    remove_set: RemoveSetCommand,
    reorder_set: ReorderSetCommand,
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
    pub const workout_not_active = "tracking.workout_not_active";
    pub const exercise_not_found = "tracking.exercise_not_found";
    pub const exercise_archived = "tracking.exercise_archived";
    pub const membership_id_conflict = "tracking.membership_id_conflict";
    pub const membership_not_found = "tracking.membership_not_found";
    pub const invalid_exercise_anchor = "tracking.invalid_exercise_anchor";
    pub const set_id_conflict = "tracking.set_id_conflict";
    pub const set_not_found = "tracking.set_not_found";
    pub const invalid_set_anchor = "tracking.invalid_set_anchor";
    pub const invalid_set_transition = "tracking.invalid_set_transition";
    pub const invalid_metric = "tracking.invalid_metric";
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
    exercise_catalog: []const ExerciseCatalogEntry = &.{},
};

pub const DecisionError = error{
    IssueBufferTooSmall,
    ExerciseBufferTooSmall,
    SetBufferTooSmall,
    RevisionOverflow,
};
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

/// Proposes adding one catalog exercise at a semantic anchor.
pub fn addExercise(
    snapshot: LifecycleSnapshot,
    command: AddExerciseCommand,
    exercise_storage: []ExerciseMembership,
    issue_storage: []Issue,
) DecisionError!CommandResult {
    if (try validateExerciseCommand(
        snapshot,
        command.metadata,
        command.scope,
        command.workout_id,
        command.expected_revision,
        issue_storage,
    )) |rejected| return rejected;
    if (!validId(command.membership_id) or !validId(command.exercise_id) or
        !validAnchor(command.anchor))
    {
        return reject(command.metadata.command_id, issue_storage, .{
            .code = issue_codes.invalid_identifier,
            .category = .validation,
            .severity = .@"error",
            .message = "A tracking identifier is invalid.",
        });
    }
    const workout = findWorkout(snapshot, command.scope, command.workout_id).?;
    for (workout.exercises) |membership| {
        if (membership.id.eql(command.membership_id)) {
            return reject(command.metadata.command_id, issue_storage, .{
                .code = issue_codes.membership_id_conflict,
                .category = .conflict,
                .severity = .@"error",
                .message = "The exercise membership ID already exists.",
            });
        }
    }
    const catalog_entry = findCatalogEntry(snapshot, command.exercise_id) orelse
        return reject(command.metadata.command_id, issue_storage, .{
            .code = issue_codes.exercise_not_found,
            .category = .not_found,
            .severity = .@"error",
            .message = "The exercise does not exist in the supplied catalog.",
        });
    if (catalog_entry.availability == .archived) {
        return reject(command.metadata.command_id, issue_storage, .{
            .code = issue_codes.exercise_archived,
            .category = .conflict,
            .severity = .@"error",
            .message = "The exercise is archived and cannot be added.",
        });
    }
    const insertion = resolveAnchor(workout.exercises, command.anchor, null);
    if (insertion == null) {
        return reject(command.metadata.command_id, issue_storage, .{
            .code = issue_codes.invalid_exercise_anchor,
            .category = .not_found,
            .severity = .@"error",
            .message = "The exercise anchor does not match a membership.",
        });
    }
    if (exercise_storage.len < workout.exercises.len + 1)
        return error.ExerciseBufferTooSmall;
    @memcpy(exercise_storage[0..insertion.?], workout.exercises[0..insertion.?]);
    exercise_storage[insertion.?] = .{
        .id = command.membership_id,
        .exercise_id = command.exercise_id,
    };
    @memcpy(
        exercise_storage[insertion.? + 1 .. workout.exercises.len + 1],
        workout.exercises[insertion.?..],
    );
    return acceptExerciseChange(
        command.metadata.command_id,
        workout,
        exercise_storage[0 .. workout.exercises.len + 1],
    );
}

/// Proposes removing one exercise membership while preserving relative order.
pub fn removeExercise(
    snapshot: LifecycleSnapshot,
    command: RemoveExerciseCommand,
    exercise_storage: []ExerciseMembership,
    issue_storage: []Issue,
) DecisionError!CommandResult {
    if (try validateExerciseCommand(
        snapshot,
        command.metadata,
        command.scope,
        command.workout_id,
        command.expected_revision,
        issue_storage,
    )) |rejected| return rejected;
    if (!validId(command.membership_id)) {
        return reject(command.metadata.command_id, issue_storage, .{
            .code = issue_codes.invalid_identifier,
            .category = .validation,
            .severity = .@"error",
            .message = "A tracking identifier is invalid.",
        });
    }
    const workout = findWorkout(snapshot, command.scope, command.workout_id).?;
    const removed = findMembership(workout.exercises, command.membership_id) orelse
        return reject(command.metadata.command_id, issue_storage, .{
            .code = issue_codes.membership_not_found,
            .category = .not_found,
            .severity = .@"error",
            .message = "The exercise membership does not exist.",
        });
    if (exercise_storage.len < workout.exercises.len - 1)
        return error.ExerciseBufferTooSmall;
    @memcpy(exercise_storage[0..removed], workout.exercises[0..removed]);
    @memcpy(
        exercise_storage[removed .. workout.exercises.len - 1],
        workout.exercises[removed + 1 ..],
    );
    return acceptExerciseChange(
        command.metadata.command_id,
        workout,
        exercise_storage[0 .. workout.exercises.len - 1],
    );
}

/// Proposes moving one membership to a semantic anchor.
pub fn reorderExercise(
    snapshot: LifecycleSnapshot,
    command: ReorderExerciseCommand,
    exercise_storage: []ExerciseMembership,
    issue_storage: []Issue,
) DecisionError!CommandResult {
    if (try validateExerciseCommand(
        snapshot,
        command.metadata,
        command.scope,
        command.workout_id,
        command.expected_revision,
        issue_storage,
    )) |rejected| return rejected;
    if (!validId(command.membership_id) or !validAnchor(command.anchor)) {
        return reject(command.metadata.command_id, issue_storage, .{
            .code = issue_codes.invalid_identifier,
            .category = .validation,
            .severity = .@"error",
            .message = "A tracking identifier is invalid.",
        });
    }
    const workout = findWorkout(snapshot, command.scope, command.workout_id).?;
    const moved = findMembership(workout.exercises, command.membership_id) orelse
        return reject(command.metadata.command_id, issue_storage, .{
            .code = issue_codes.membership_not_found,
            .category = .not_found,
            .severity = .@"error",
            .message = "The exercise membership does not exist.",
        });
    const insertion = resolveAnchor(
        workout.exercises,
        command.anchor,
        command.membership_id,
    );
    if (insertion == null) {
        return reject(command.metadata.command_id, issue_storage, .{
            .code = issue_codes.invalid_exercise_anchor,
            .category = .not_found,
            .severity = .@"error",
            .message = "The exercise anchor does not match another membership.",
        });
    }
    if (exercise_storage.len < workout.exercises.len)
        return error.ExerciseBufferTooSmall;
    var written: usize = 0;
    for (workout.exercises, 0..) |membership, index| {
        if (index == moved) continue;
        exercise_storage[written] = membership;
        written += 1;
    }
    const destination = insertion.?;
    std.mem.copyBackwards(
        ExerciseMembership,
        exercise_storage[destination + 1 .. workout.exercises.len],
        exercise_storage[destination .. workout.exercises.len - 1],
    );
    exercise_storage[destination] = workout.exercises[moved];
    return acceptExerciseChange(
        command.metadata.command_id,
        workout,
        exercise_storage[0..workout.exercises.len],
    );
}

pub const SetCommand = union(enum) {
    add: AddSetCommand,
    complete: CompleteSetCommand,
    skip: SkipSetCommand,
    reopen: ReopenSetCommand,
    remove: RemoveSetCommand,
    reorder: ReorderSetCommand,
};

/// Applies one explicit set lifecycle transition without allocation or mutation.
pub fn applySetCommand(
    snapshot: LifecycleSnapshot,
    command: SetCommand,
    exercise_storage: []ExerciseMembership,
    set_storage: []TrackedSet,
    issue_storage: []Issue,
) DecisionError!CommandResult {
    const common = setCommandCommon(command);
    if (try validateExerciseCommand(
        snapshot,
        common.metadata,
        common.scope,
        common.workout_id,
        common.expected_revision,
        issue_storage,
    )) |rejected| return rejected;
    if (!validId(common.membership_id) or !validId(common.set_id)) {
        return reject(common.metadata.command_id, issue_storage, invalidIdIssue());
    }
    const workout = findWorkout(snapshot, common.scope, common.workout_id).?;
    const membership_index =
        findMembership(workout.exercises, common.membership_id) orelse
        return reject(common.metadata.command_id, issue_storage, .{
            .code = issue_codes.membership_not_found,
            .category = .not_found,
            .severity = .@"error",
            .message = "The exercise membership does not exist.",
        });
    const membership = workout.exercises[membership_index];
    const existing_index = findSet(membership.sets, common.set_id);
    const next_len = switch (command) {
        .add => membership.sets.len + 1,
        .remove => if (existing_index == null)
            membership.sets.len
        else
            membership.sets.len - 1,
        else => membership.sets.len,
    };
    if (exercise_storage.len < workout.exercises.len)
        return error.ExerciseBufferTooSmall;
    if (set_storage.len < next_len) return error.SetBufferTooSmall;

    switch (command) {
        .add => |add| {
            if (!validId(add.kind) or !validMetrics(add.target_metrics))
                return reject(common.metadata.command_id, issue_storage, .{
                    .code = issue_codes.invalid_metric,
                    .category = .validation,
                    .severity = .@"error",
                    .message = "A set kind or target metric is invalid.",
                });
            if (existing_index != null)
                return reject(common.metadata.command_id, issue_storage, .{
                    .code = issue_codes.set_id_conflict,
                    .category = .conflict,
                    .severity = .@"error",
                    .message = "The set ID already exists in this exercise.",
                });
            const insertion = resolveSetAnchor(membership.sets, add.anchor, null) orelse
                return reject(common.metadata.command_id, issue_storage, .{
                    .code = issue_codes.invalid_set_anchor,
                    .category = .not_found,
                    .severity = .@"error",
                    .message = "The set anchor does not match a set.",
                });
            @memcpy(set_storage[0..insertion], membership.sets[0..insertion]);
            set_storage[insertion] = .{
                .id = add.set_id,
                .kind = add.kind,
                .target_metrics = add.target_metrics,
            };
            @memcpy(
                set_storage[insertion + 1 .. next_len],
                membership.sets[insertion..],
            );
        },
        .complete => |complete| {
            const index = existing_index orelse
                return reject(common.metadata.command_id, issue_storage, setNotFoundIssue());
            if (membership.sets[index].status != .open or
                (complete.status != .completed and complete.status != .partial and
                    complete.status != .failed))
            {
                return reject(common.metadata.command_id, issue_storage, transitionIssue());
            }
            if (!validTimestamp(complete.completed_at) or
                !validMetrics(complete.actual_metrics))
                return reject(common.metadata.command_id, issue_storage, .{
                    .code = issue_codes.invalid_metric,
                    .category = .validation,
                    .severity = .@"error",
                    .message = "A completion timestamp or actual metric is invalid.",
                });
            @memcpy(set_storage[0..membership.sets.len], membership.sets);
            set_storage[index].actual_metrics = complete.actual_metrics;
            set_storage[index].status = complete.status;
            set_storage[index].recorded_at = complete.completed_at;
        },
        .skip => |skip| {
            const index = existing_index orelse
                return reject(common.metadata.command_id, issue_storage, setNotFoundIssue());
            if (membership.sets[index].status != .open)
                return reject(common.metadata.command_id, issue_storage, transitionIssue());
            if (!validTimestamp(skip.skipped_at))
                return reject(common.metadata.command_id, issue_storage, .{
                    .code = issue_codes.invalid_timestamp,
                    .category = .validation,
                    .severity = .@"error",
                    .message = "The skipped-at timestamp is invalid.",
                });
            @memcpy(set_storage[0..membership.sets.len], membership.sets);
            set_storage[index].status = .skipped;
            set_storage[index].recorded_at = skip.skipped_at;
        },
        .reopen => {
            const index = existing_index orelse
                return reject(common.metadata.command_id, issue_storage, setNotFoundIssue());
            if (membership.sets[index].status == .open)
                return reject(common.metadata.command_id, issue_storage, transitionIssue());
            @memcpy(set_storage[0..membership.sets.len], membership.sets);
            set_storage[index].status = .open;
            set_storage[index].recorded_at = null;
            set_storage[index].actual_metrics = &.{};
        },
        .remove => {
            const index = existing_index orelse
                return reject(common.metadata.command_id, issue_storage, setNotFoundIssue());
            @memcpy(set_storage[0..index], membership.sets[0..index]);
            @memcpy(set_storage[index .. membership.sets.len - 1], membership.sets[index + 1 ..]);
        },
        .reorder => |reorder| {
            const index = existing_index orelse
                return reject(common.metadata.command_id, issue_storage, setNotFoundIssue());
            const destination = resolveSetAnchor(
                membership.sets,
                reorder.anchor,
                reorder.set_id,
            ) orelse return reject(
                common.metadata.command_id,
                issue_storage,
                .{
                    .code = issue_codes.invalid_set_anchor,
                    .category = .not_found,
                    .severity = .@"error",
                    .message = "The set anchor does not match another set.",
                },
            );
            var written: usize = 0;
            for (membership.sets, 0..) |set, set_index| {
                if (set_index == index) continue;
                set_storage[written] = set;
                written += 1;
            }
            std.mem.copyBackwards(
                TrackedSet,
                set_storage[destination + 1 .. membership.sets.len],
                set_storage[destination .. membership.sets.len - 1],
            );
            set_storage[destination] = membership.sets[index];
        },
    }
    @memcpy(exercise_storage[0..workout.exercises.len], workout.exercises);
    exercise_storage[membership_index].sets = set_storage[0..next_len];
    return acceptExerciseChange(
        common.metadata.command_id,
        workout,
        exercise_storage[0..workout.exercises.len],
    );
}

pub fn addSet(snapshot: LifecycleSnapshot, command: AddSetCommand, exercises: []ExerciseMembership, sets: []TrackedSet, issues: []Issue) DecisionError!CommandResult {
    return applySetCommand(snapshot, .{ .add = command }, exercises, sets, issues);
}
pub fn completeSet(snapshot: LifecycleSnapshot, command: CompleteSetCommand, exercises: []ExerciseMembership, sets: []TrackedSet, issues: []Issue) DecisionError!CommandResult {
    return applySetCommand(snapshot, .{ .complete = command }, exercises, sets, issues);
}
pub fn logSet(snapshot: LifecycleSnapshot, command: LogSetCommand, exercises: []ExerciseMembership, sets: []TrackedSet, issues: []Issue) DecisionError!CommandResult {
    return completeSet(snapshot, command, exercises, sets, issues);
}
pub fn skipSet(snapshot: LifecycleSnapshot, command: SkipSetCommand, exercises: []ExerciseMembership, sets: []TrackedSet, issues: []Issue) DecisionError!CommandResult {
    return applySetCommand(snapshot, .{ .skip = command }, exercises, sets, issues);
}
pub fn reopenSet(snapshot: LifecycleSnapshot, command: ReopenSetCommand, exercises: []ExerciseMembership, sets: []TrackedSet, issues: []Issue) DecisionError!CommandResult {
    return applySetCommand(snapshot, .{ .reopen = command }, exercises, sets, issues);
}
pub fn removeSet(snapshot: LifecycleSnapshot, command: RemoveSetCommand, exercises: []ExerciseMembership, sets: []TrackedSet, issues: []Issue) DecisionError!CommandResult {
    return applySetCommand(snapshot, .{ .remove = command }, exercises, sets, issues);
}
pub fn reorderSet(snapshot: LifecycleSnapshot, command: ReorderSetCommand, exercises: []ExerciseMembership, sets: []TrackedSet, issues: []Issue) DecisionError!CommandResult {
    return applySetCommand(snapshot, .{ .reorder = command }, exercises, sets, issues);
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

fn validateExerciseCommand(
    snapshot: LifecycleSnapshot,
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    issue_storage: []Issue,
) DecisionError!?CommandResult {
    if (!validId(metadata.command_id) or !validId(scope.host_scope_key) or
        (scope.athlete_id != null and !validId(scope.athlete_id.?)) or
        !validId(workout_id))
    {
        return try reject(metadata.command_id, issue_storage, .{
            .code = issue_codes.invalid_identifier,
            .category = .validation,
            .severity = .@"error",
            .message = "A tracking identifier is invalid.",
        });
    }
    if (!validTimestamp(metadata.occurred_at)) {
        return try reject(metadata.command_id, issue_storage, .{
            .code = issue_codes.invalid_timestamp,
            .category = .validation,
            .severity = .@"error",
            .message = "A command timestamp is not valid RFC 3339.",
        });
    }
    const workout = findWorkout(snapshot, scope, workout_id) orelse
        return try reject(metadata.command_id, issue_storage, .{
            .code = issue_codes.workout_not_found,
            .category = .not_found,
            .severity = .@"error",
            .message = "No workout matched the requested scope and ID.",
        });
    if (workout.status != .active) {
        return try reject(metadata.command_id, issue_storage, .{
            .code = issue_codes.workout_not_active,
            .category = .conflict,
            .severity = .@"error",
            .message = "Exercise ordering requires an active workout.",
        });
    }
    if (workout.revision != expected_revision) {
        return try reject(metadata.command_id, issue_storage, .{
            .code = issue_codes.revision_conflict,
            .category = .conflict,
            .severity = .@"error",
            .message = "The expected workout revision does not match.",
        });
    }
    return null;
}

fn acceptExerciseChange(
    command_id: Id,
    workout: Workout,
    exercises: []const ExerciseMembership,
) DecisionError!CommandResult {
    return .{ .accepted = .{
        .command_id = command_id,
        .disposition = .applied,
        .workout = .{
            .id = workout.id,
            .scope = workout.scope,
            .revision = std.math.add(u64, workout.revision, 1) catch
                return error.RevisionOverflow,
            .status = workout.status,
            .started_at = workout.started_at,
            .completed_at = workout.completed_at,
            .exercises = exercises,
        },
    } };
}

fn findWorkout(
    snapshot: LifecycleSnapshot,
    scope: Scope,
    workout_id: Id,
) ?Workout {
    for (snapshot.workouts) |workout| {
        if (workout.id.eql(workout_id) and scopesEqual(workout.scope, scope))
            return workout;
    }
    return null;
}

fn findCatalogEntry(
    snapshot: LifecycleSnapshot,
    exercise_id: Id,
) ?ExerciseCatalogEntry {
    for (snapshot.exercise_catalog) |entry| {
        if (entry.exercise_id.eql(exercise_id)) return entry;
    }
    return null;
}

fn findMembership(exercises: []const ExerciseMembership, id: Id) ?usize {
    for (exercises, 0..) |membership, index| {
        if (membership.id.eql(id)) return index;
    }
    return null;
}

const SetCommandCommon = struct {
    metadata: CommandMetadata,
    scope: Scope,
    workout_id: Id,
    expected_revision: u64,
    membership_id: Id,
    set_id: Id,
};

fn setCommandCommon(command: SetCommand) SetCommandCommon {
    return switch (command) {
        inline else => |value| .{
            .metadata = value.metadata,
            .scope = value.scope,
            .workout_id = value.workout_id,
            .expected_revision = value.expected_revision,
            .membership_id = value.membership_id,
            .set_id = value.set_id,
        },
    };
}

fn findSet(sets: []const TrackedSet, id: Id) ?usize {
    for (sets, 0..) |set, index| {
        if (set.id.eql(id)) return index;
    }
    return null;
}

fn resolveSetAnchor(
    sets: []const TrackedSet,
    anchor: SetAnchor,
    excluded: ?Id,
) ?usize {
    const remaining = sets.len - @intFromBool(excluded != null);
    return switch (anchor) {
        .beginning => 0,
        .end => remaining,
        .before => |id| resolveSetRelative(sets, id, excluded, 0),
        .after => |id| resolveSetRelative(sets, id, excluded, 1),
    };
}

fn resolveSetRelative(
    sets: []const TrackedSet,
    anchor_id: Id,
    excluded: ?Id,
    offset: usize,
) ?usize {
    if (excluded != null and anchor_id.eql(excluded.?)) return null;
    var position: usize = 0;
    for (sets) |set| {
        if (excluded != null and set.id.eql(excluded.?)) continue;
        if (set.id.eql(anchor_id)) return position + offset;
        position += 1;
    }
    return null;
}

fn validMetrics(metrics: []const Metric) bool {
    for (metrics) |metric| {
        if (!validId(metric.code) or metric.value.value.scale > Decimal.max_scale)
            return false;
        const dimension = metric.value.unit.dimension();
        if (std.mem.eql(u8, metric.code.bytes, metric_codes.repetitions) and
            dimension != .count) return false;
        if (std.mem.eql(u8, metric.code.bytes, metric_codes.load) and
            dimension != .mass) return false;
        if (std.mem.eql(u8, metric.code.bytes, metric_codes.rir) and
            dimension != .rir) return false;
        if (std.mem.eql(u8, metric.code.bytes, metric_codes.rpe) and
            dimension != .rpe) return false;
        if (std.mem.eql(u8, metric.code.bytes, metric_codes.duration) and
            dimension != .duration) return false;
    }
    return true;
}

fn invalidIdIssue() Issue {
    return .{
        .code = issue_codes.invalid_identifier,
        .category = .validation,
        .severity = .@"error",
        .message = "A tracking identifier is invalid.",
    };
}

fn setNotFoundIssue() Issue {
    return .{
        .code = issue_codes.set_not_found,
        .category = .not_found,
        .severity = .@"error",
        .message = "The set does not exist in this exercise.",
    };
}

fn transitionIssue() Issue {
    return .{
        .code = issue_codes.invalid_set_transition,
        .category = .conflict,
        .severity = .@"error",
        .message = "The set cannot make the requested lifecycle transition.",
    };
}

fn resolveAnchor(
    exercises: []const ExerciseMembership,
    anchor: ExerciseAnchor,
    excluded: ?Id,
) ?usize {
    const remaining = exercises.len - @intFromBool(excluded != null);
    return switch (anchor) {
        .beginning => 0,
        .end => remaining,
        .before => |anchor_id| blk: {
            if (excluded != null and anchor_id.eql(excluded.?)) break :blk null;
            var position: usize = 0;
            for (exercises) |membership| {
                if (excluded != null and membership.id.eql(excluded.?)) continue;
                if (membership.id.eql(anchor_id)) break :blk position;
                position += 1;
            }
            break :blk null;
        },
        .after => |anchor_id| blk: {
            if (excluded != null and anchor_id.eql(excluded.?)) break :blk null;
            var position: usize = 0;
            for (exercises) |membership| {
                if (excluded != null and membership.id.eql(excluded.?)) continue;
                if (membership.id.eql(anchor_id)) break :blk position + 1;
                position += 1;
            }
            break :blk null;
        },
    };
}

fn validId(id: Id) bool {
    _ = Id.parse(id.bytes) catch return false;
    return true;
}

fn validTimestamp(timestamp: Timestamp) bool {
    _ = Timestamp.parse(timestamp.bytes) catch return false;
    return true;
}

fn validAnchor(anchor: ExerciseAnchor) bool {
    return switch (anchor) {
        .beginning, .end => true,
        .before, .after => |id| validId(id),
    };
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
