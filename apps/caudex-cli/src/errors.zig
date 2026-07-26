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
};

pub fn fromError(err: anyerror) Failure {
    return switch (err) {
        error.InvalidArguments => .{
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
