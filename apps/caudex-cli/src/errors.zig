pub const ExitClass = enum(u8) {
    success = 0,
    syntax = 2,
    validation = 3,
    not_found = 4,
    ambiguity = 5,
    conflict = 6,
    busy = 7,
    database = 8,
    runtime = 70,
    interrupted = 130,
};

pub const Failure = struct {
    exit_class: ExitClass,
    code: []const u8,
    category: []const u8,
    message: []const u8,
    candidate_ids: []const []const u8 = &.{},
};

pub fn workoutNotFound() Failure {
    return .{
        .exit_class = .not_found,
        .code = "tracking.workout_not_found",
        .category = "not_found",
        .message = "No active workout matched; pass --workout with a stable ID.",
    };
}

pub fn ambiguousWorkout(candidate_ids: []const []const u8) Failure {
    return .{
        .exit_class = .ambiguity,
        .code = "client.active_workout_ambiguous",
        .category = "ambiguity",
        .message = "Multiple active workouts matched; pass --workout with one candidate ID.",
        .candidate_ids = candidate_ids,
    };
}

pub fn exerciseNotFound() Failure {
    return .{
        .exit_class = .not_found,
        .code = "client.exercise_not_found",
        .category = "not_found",
        .message = "No exercise matched the reference.",
    };
}

pub fn managedExerciseNotFound() Failure {
    return .{ .exit_class = .not_found, .code = "catalog.exercise_not_found", .category = "not_found", .message = "No managed exercise matched the reference." };
}

pub fn membershipNotFound() Failure {
    return .{ .exit_class = .not_found, .code = "tracking.membership_not_found", .category = "not_found", .message = "No unique workout exercise matched; pass --exercise with a membership or exercise ID." };
}

pub fn setNotFound() Failure {
    return .{ .exit_class = .not_found, .code = "tracking.set_not_found", .category = "not_found", .message = "No unique eligible set matched; pass --set with a stable ID." };
}

pub fn confirmationRequired() Failure {
    return .{ .exit_class = .syntax, .code = "client.confirmation_required", .category = "syntax", .message = "Cancellation requires --yes when input is not a TTY." };
}

pub fn cancelledByUser() Failure {
    return .{ .exit_class = .interrupted, .code = "client.cancelled", .category = "interrupted", .message = "Cancellation was not confirmed." };
}

pub fn ambiguousExercise(candidate_ids: []const []const u8) Failure {
    return .{
        .exit_class = .ambiguity,
        .code = "client.exercise_ambiguous",
        .category = "ambiguity",
        .message = "Multiple exercises matched; pass an exact exercise ID.",
        .candidate_ids = candidate_ids,
    };
}

pub fn fromTrackingIssue(issue: anytype) Failure {
    return .{
        .exit_class = switch (issue.category) {
            .validation => .validation,
            .not_found => .not_found,
            .conflict => .conflict,
        },
        .code = issue.code,
        .category = @tagName(issue.category),
        .message = issue.message,
    };
}

pub fn fromError(err: anyerror) Failure {
    return switch (err) {
        error.InvalidArguments,
        error.Empty,
        error.TooLong,
        error.InvalidUtf8,
        error.InvalidTimestamp,
        => .{
            .exit_class = .syntax,
            .code = "client.invalid_arguments",
            .category = "syntax",
            .message = "Invalid arguments; run 'caudex --help'.",
        },
        error.Busy => .{
            .exit_class = .busy,
            .code = "database.busy",
            .category = "database",
            .message = "The database is busy.",
        },
        error.Corrupt => .{
            .exit_class = .database,
            .code = "database.corrupt",
            .category = "database",
            .message = "The database is corrupt.",
        },
        error.MigrationFailed => .{
            .exit_class = .database,
            .code = "database.migration_failed",
            .category = "database",
            .message = "The database migration failed.",
        },
        error.UnsupportedSchema => .{
            .exit_class = .database,
            .code = "database.unsupported_schema",
            .category = "database",
            .message = "The database schema is not supported.",
        },
        error.DataDirectoryUnavailable => .{
            .exit_class = .runtime,
            .code = "client.data_directory_unavailable",
            .category = "runtime",
            .message = "The platform data directory is unavailable.",
        },
        else => .{
            .exit_class = .runtime,
            .code = "client.database_operation_failed",
            .category = "runtime",
            .message = "The database operation failed.",
        },
    };
}

test "stable exit classes retain documented values" {
    const testing = @import("std").testing;
    try testing.expectEqual(@as(u8, 0), @intFromEnum(ExitClass.success));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(ExitClass.syntax));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(ExitClass.validation));
    try testing.expectEqual(@as(u8, 4), @intFromEnum(ExitClass.not_found));
    try testing.expectEqual(@as(u8, 5), @intFromEnum(ExitClass.ambiguity));
    try testing.expectEqual(@as(u8, 6), @intFromEnum(ExitClass.conflict));
    try testing.expectEqual(@as(u8, 7), @intFromEnum(ExitClass.busy));
    try testing.expectEqual(@as(u8, 8), @intFromEnum(ExitClass.database));
    try testing.expectEqual(@as(u8, 70), @intFromEnum(ExitClass.runtime));
    try testing.expectEqual(@as(u8, 130), @intFromEnum(ExitClass.interrupted));
}
