const std = @import("std");
const primitives = @import("primitives.zig");

pub const Id = primitives.Id;
pub const Decimal = primitives.Decimal;
pub const Measurement = primitives.Measurement;
pub const Timestamp = primitives.Timestamp;

pub const MuscleRole = enum {
    primary,
    secondary,
    stabilizer,
    custom,
};

pub const MuscleContribution = struct {
    muscle_id: Id,
    role: MuscleRole,
    weight: ?Decimal = null,
};

/// A methodology-neutral exercise whose taxonomy values are supplied by the host.
pub const Exercise = struct {
    id: Id,
    name: ?[]const u8 = null,
    equipment_ids: []const Id = &.{},
    movement_tags: []const Id = &.{},
    muscle_contributions: []const MuscleContribution = &.{},
    unilateral: ?bool = null,
    aliases: []const []const u8 = &.{},
};

/// A borrowed view of the host-supplied exercise catalog.
pub const ExerciseCatalog = struct {
    exercises: []const Exercise,

    pub fn find(self: ExerciseCatalog, id: Id) ?*const Exercise {
        for (self.exercises) |*exercise| {
            if (exercise.id.eql(id)) return exercise;
        }
        return null;
    }
};

pub const Metric = struct {
    code: Id,
    value: Measurement,
};

pub const SetStatus = enum {
    completed,
    partial,
    skipped,
    failed,
};

/// A completed set preserves both observed metrics and optional prescribed targets.
pub const CompletedSet = struct {
    id: ?Id = null,
    kind: Id,
    actual_metrics: []const Metric,
    target_metrics: []const Metric = &.{},
    completed_at: ?Timestamp = null,
    status: SetStatus,
};

pub const CompletedExercise = struct {
    exercise_id: Id,
    sets: []const CompletedSet,
    tags: []const Id = &.{},
    notes: ?[]const u8 = null,
};

pub const CompletedWorkout = struct {
    id: Id,
    started_at: Timestamp,
    completed_at: Timestamp,
    exercises: []const CompletedExercise,
};

/// A borrowed history snapshot supplied explicitly by the host.
pub const HistorySnapshot = struct {
    workouts: []const CompletedWorkout = &.{},
};

pub const DuplicateExerciseId = struct {
    first_index: usize,
    duplicate_index: usize,
};

pub const MissingExerciseReference = struct {
    workout_index: usize,
    exercise_index: usize,
};

/// Structured expected outcomes from catalog/history validation.
pub const ValidationIssue = union(enum) {
    duplicate_exercise_id: DuplicateExerciseId,
    missing_exercise_reference: MissingExerciseReference,

    pub fn code(self: ValidationIssue) []const u8 {
        return switch (self) {
            .duplicate_exercise_id => "catalog.duplicate_exercise_id",
            .missing_exercise_reference => "history.exercise_reference_missing",
        };
    }
};

pub const ValidateError = error{IssueBufferFull};

/// Validates catalog identity and history-to-catalog references.
///
/// Every discovered issue is written to caller-owned storage. Validation order
/// is deterministic: catalog duplicates first, followed by history order.
pub fn validate(
    catalog: ExerciseCatalog,
    history: HistorySnapshot,
    issue_storage: []ValidationIssue,
) ValidateError![]const ValidationIssue {
    var issue_count: usize = 0;

    for (catalog.exercises, 0..) |exercise, duplicate_index| {
        for (catalog.exercises[0..duplicate_index], 0..) |prior, first_index| {
            if (prior.id.eql(exercise.id)) {
                try appendIssue(
                    issue_storage,
                    &issue_count,
                    .{ .duplicate_exercise_id = .{
                        .first_index = first_index,
                        .duplicate_index = duplicate_index,
                    } },
                );
                break;
            }
        }
    }

    for (history.workouts, 0..) |workout, workout_index| {
        for (workout.exercises, 0..) |exercise, exercise_index| {
            if (catalog.find(exercise.exercise_id) == null) {
                try appendIssue(
                    issue_storage,
                    &issue_count,
                    .{ .missing_exercise_reference = .{
                        .workout_index = workout_index,
                        .exercise_index = exercise_index,
                    } },
                );
            }
        }
    }

    return issue_storage[0..issue_count];
}

fn appendIssue(
    storage: []ValidationIssue,
    len: *usize,
    issue: ValidationIssue,
) ValidateError!void {
    if (len.* >= storage.len) return error.IssueBufferFull;
    storage[len.*] = issue;
    len.* += 1;
}

test "catalog supports optional names and host taxonomies" {
    const equipment = [_]Id{
        try Id.parse("dumbbell"),
        try Id.parse("adjustable-bench"),
    };
    const movement_tags = [_]Id{try Id.parse("horizontal-push")};
    const exercises = [_]Exercise{.{
        .id = try Id.parse("incline-dumbbell-press"),
        .name = null,
        .equipment_ids = &equipment,
        .movement_tags = &movement_tags,
    }};
    const catalog = ExerciseCatalog{ .exercises = &exercises };

    const found = catalog.find(try Id.parse("incline-dumbbell-press")).?;
    try std.testing.expect(found.name == null);
    try std.testing.expectEqualStrings("dumbbell", found.equipment_ids[0].bytes);
    try std.testing.expectEqualStrings("horizontal-push", found.movement_tags[0].bytes);
}

test "validation collects duplicate and missing cross references" {
    const exercises = [_]Exercise{
        .{ .id = try Id.parse("squat") },
        .{ .id = try Id.parse("squat") },
    };
    const completed_exercises = [_]CompletedExercise{.{
        .exercise_id = try Id.parse("bench-press"),
        .sets = &.{},
    }};
    const workouts = [_]CompletedWorkout{.{
        .id = try Id.parse("workout-1"),
        .started_at = try Timestamp.parse("2026-07-25T14:00:00Z"),
        .completed_at = try Timestamp.parse("2026-07-25T14:30:00Z"),
        .exercises = &completed_exercises,
    }};
    var issue_storage: [2]ValidationIssue = undefined;

    const issues = try validate(
        .{ .exercises = &exercises },
        .{ .workouts = &workouts },
        &issue_storage,
    );
    try std.testing.expectEqual(@as(usize, 2), issues.len);
    try std.testing.expectEqualStrings(
        "catalog.duplicate_exercise_id",
        issues[0].code(),
    );
    try std.testing.expectEqualStrings(
        "history.exercise_reference_missing",
        issues[1].code(),
    );
}

test "completed sets preserve target and actual metrics" {
    const target_metrics = [_]Metric{
        .{
            .code = try Id.parse("load"),
            .value = .{
                .value = try Decimal.parse("70"),
                .unit = .kg,
            },
        },
        .{
            .code = try Id.parse("repetitions"),
            .value = .{
                .value = try Decimal.parse("8"),
                .unit = .count,
            },
        },
    };
    const actual_metrics = [_]Metric{
        .{
            .code = try Id.parse("load"),
            .value = .{
                .value = try Decimal.parse("70"),
                .unit = .kg,
            },
        },
        .{
            .code = try Id.parse("repetitions"),
            .value = .{
                .value = try Decimal.parse("9"),
                .unit = .count,
            },
        },
    };
    const set = CompletedSet{
        .kind = try Id.parse("working"),
        .actual_metrics = &actual_metrics,
        .target_metrics = &target_metrics,
        .status = .completed,
    };

    try std.testing.expectEqual(
        Decimal{ .mantissa = 8, .scale = 0 },
        set.target_metrics[1].value.value,
    );
    try std.testing.expectEqual(
        Decimal{ .mantissa = 9, .scale = 0 },
        set.actual_metrics[1].value.value,
    );
}
