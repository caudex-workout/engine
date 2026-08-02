const std = @import("std");
const errors = @import("errors.zig");
const security = @import("security.zig");

pub const Format = enum { human, json };
pub const Color = enum { auto, always, never };

pub const Settings = struct {
    format: Format = .human,
    color: Color = .auto,
    is_terminal: bool = false,
    no_color: bool = false,
    quiet: bool = false,

    pub fn useColor(self: Settings) bool {
        if (self.format == .json or self.no_color) return false;
        return switch (self.color) {
            .auto => self.is_terminal,
            .always => true,
            .never => false,
        };
    }
};

pub const DatabaseInfo = struct {
    path: []const u8,
    database_kind: []const u8,
    adapter_version: []const u8,
    database_schema_version: u32,
    minimum_schema_version: u32,
    latest_schema_version: u32,
    compatibility: []const u8,
};

pub const DatabaseCheck = struct {
    path: []const u8,
    status: []const u8,
};

pub const WorkoutInfo = struct {
    document_kind: []const u8,
    command_id: ?[]const u8 = null,
    disposition: ?[]const u8 = null,
    workout_id: []const u8,
    host_scope_key: []const u8,
    athlete_id: ?[]const u8,
    revision: u64,
    status: []const u8,
    started_at: []const u8,
    completed_at: ?[]const u8,
    exercises: ?[]const WorkoutExerciseInfo = null,
};

pub const WorkoutExerciseInfo = struct {
    membershipId: []const u8,
    exerciseId: []const u8,
    setCount: usize,
};

pub const ExerciseInfo = struct {
    id: []const u8,
    name: ?[]const u8,
    aliases: []const []const u8,
    equipmentIds: []const []const u8,
    movementTags: []const []const u8,
    unilateral: ?bool,
    revision: u64,
    availability: []const u8,
    updatedAt: []const u8,
};

pub const HistoryInfo = struct {
    workoutId: []const u8,
    revision: u64,
    completedAt: []const u8,
    exerciseCount: usize,
};

pub fn writeHistory(writer: *std.Io.Writer, settings: Settings, kind: []const u8, workouts: []const HistoryInfo) !void {
    if (settings.quiet) return;
    switch (settings.format) {
        .human => {
            if (workouts.len == 0) return writer.writeAll("No completed workouts.\n");
            try writer.writeAll("WORKOUT  COMPLETED  EXERCISES  REVISION\n");
            for (workouts) |workout| {
                try security.writeEscaped(writer, workout.workoutId);
                try writer.writeAll("  ");
                try security.writeEscaped(writer, workout.completedAt);
                try writer.print("  {d}  {d}\n", .{ workout.exerciseCount, workout.revision });
            }
        },
        .json => {
            try std.json.Stringify.value(.{ .schemaVersion = 1, .kind = kind, .data = .{ .workouts = workouts } }, .{}, writer);
            try writer.writeByte('\n');
        },
    }
}

pub fn writeExercises(writer: *std.Io.Writer, settings: Settings, kind: []const u8, command_id: ?[]const u8, disposition: ?[]const u8, exercises: []const ExerciseInfo) !void {
    if (settings.quiet) return;
    switch (settings.format) {
        .human => {
            if (exercises.len == 0) return writer.writeAll("No exercises.\n");
            try writer.writeAll("ID  NAME  STATUS  REVISION\n");
            for (exercises) |exercise| {
                try security.writeEscaped(writer, exercise.id);
                try writer.writeAll("  ");
                try writeTerminalText(writer, exercise.name orelse "-");
                try writer.writeAll("  ");
                try security.writeEscaped(writer, exercise.availability);
                try writer.print("  {d}\n", .{exercise.revision});
            }
        },
        .json => {
            try std.json.Stringify.value(.{ .schemaVersion = 1, .kind = kind, .data = .{ .commandId = command_id, .disposition = disposition, .exercises = exercises } }, .{ .emit_null_optional_fields = false }, writer);
            try writer.writeByte('\n');
        },
    }
}

/// Human output escapes terminal control characters; JSON keeps the source
/// value and its normal JSON escaping rules.
pub fn writeTerminalText(writer: *std.Io.Writer, value: []const u8) !void {
    return security.writeEscaped(writer, value);
}

pub fn requestedFormat(args: []const []const u8) Format {
    var index: usize = 1;
    while (index + 1 < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--format") and
            std.mem.eql(u8, args[index + 1], "json"))
        {
            return .json;
        }
    }
    return .human;
}

pub fn writeHelp(writer: *std.Io.Writer, help: []const u8) !void {
    try writer.writeAll(help);
}

pub fn writeVersion(writer: *std.Io.Writer, version: []const u8) !void {
    try writer.print("caudex {s}\n", .{version});
}

pub fn writeDatabaseInfo(
    writer: *std.Io.Writer,
    settings: Settings,
    info: DatabaseInfo,
) !void {
    switch (settings.format) {
        .human => try writeHumanDatabaseInfo(writer, settings.useColor(), info),
        .json => try writeJsonDatabaseInfo(writer, info),
    }
}

pub fn writeDatabaseCheck(writer: *std.Io.Writer, settings: Settings, kind: []const u8, check: DatabaseCheck) !void {
    if (settings.quiet) return;
    switch (settings.format) {
        .human => {
            try writer.writeAll("Database: ");
            try writeTerminalText(writer, check.path);
            try writer.writeAll("\nIntegrity: ");
            try writeTerminalText(writer, check.status);
            try writer.writeByte('\n');
        },
        .json => {
            try std.json.Stringify.value(.{ .schemaVersion = 1, .kind = kind, .data = .{ .databasePath = check.path, .integrity = check.status } }, .{}, writer);
            try writer.writeByte('\n');
        },
    }
}

pub fn writeWorkout(
    writer: *std.Io.Writer,
    settings: Settings,
    info: WorkoutInfo,
) !void {
    if (settings.quiet) return;
    switch (settings.format) {
        .human => {
            if (info.disposition) |disposition| {
                try writer.writeAll("Workout ");
                try writeTerminalText(writer, disposition);
                try writer.writeAll(": ");
                try writeTerminalText(writer, info.workout_id);
                try writer.writeByte('\n');
            } else {
                try writer.writeAll("Workout: ");
                try writeTerminalText(writer, info.workout_id);
                try writer.writeByte('\n');
            }
            try writer.writeAll("Status: ");
            try writeTerminalText(writer, info.status);
            try writer.print("\nRevision: {d}\nStarted at: ", .{info.revision});
            try writeTerminalText(writer, info.started_at);
            try writer.writeByte('\n');
            if (info.exercises) |exercises| {
                if (exercises.len == 0) {
                    try writer.writeAll("Exercises: none\n");
                } else {
                    try writer.writeAll("Exercises:\n");
                    for (exercises) |exercise| {
                        try writer.writeAll("  ");
                        try writeTerminalText(writer, exercise.exerciseId);
                        try writer.writeAll("  membership=");
                        try writeTerminalText(writer, exercise.membershipId);
                        try writer.print("  sets={d}\n", .{exercise.setCount});
                    }
                }
            }
        },
        .json => {
            try std.json.Stringify.value(.{
                .schemaVersion = 1,
                .kind = info.document_kind,
                .data = .{
                    .commandId = info.command_id,
                    .disposition = info.disposition,
                    .workoutId = info.workout_id,
                    .hostScopeKey = info.host_scope_key,
                    .athleteId = info.athlete_id,
                    .revision = info.revision,
                    .status = info.status,
                    .startedAt = info.started_at,
                    .completedAt = info.completed_at,
                    .exercises = info.exercises,
                },
            }, .{ .emit_null_optional_fields = false }, writer);
            try writer.writeByte('\n');
        },
    }
}

pub fn writeFailure(
    writer: *std.Io.Writer,
    format: Format,
    failure: errors.Failure,
) !void {
    switch (format) {
        .human => {
            try writer.writeAll("error: ");
            try writeTerminalText(writer, failure.message);
            try writer.writeByte('\n');
            for (failure.candidate_ids) |id| {
                try writer.writeAll("candidate: ");
                try writeTerminalText(writer, id);
                try writer.writeByte('\n');
            }
        },
        .json => {
            try std.json.Stringify.value(.{
                .schemaVersion = 1,
                .kind = "caudex.error",
                .@"error" = .{
                    .code = failure.code,
                    .category = failure.category,
                    .message = failure.message,
                    .details = if (failure.candidate_ids.len == 0)
                        null
                    else
                        .{ .candidateIds = failure.candidate_ids },
                },
            }, .{ .emit_null_optional_fields = false }, writer);
            try writer.writeByte('\n');
        },
    }
}

fn writeHumanDatabaseInfo(
    writer: *std.Io.Writer,
    color: bool,
    info: DatabaseInfo,
) !void {
    const label_start = if (color) "\x1b[1m" else "";
    const label_end = if (color) "\x1b[0m" else "";
    try writer.print("{s}Database:{s} ", .{ label_start, label_end });
    try writeTerminalText(writer, info.path);
    try writer.print("\n{s}Kind:{s} ", .{ label_start, label_end });
    try writeTerminalText(writer, info.database_kind);
    try writer.print("\n{s}Adapter version:{s} ", .{ label_start, label_end });
    try writeTerminalText(writer, info.adapter_version);
    try writer.print("\n{s}Schema version:{s} {d}\n{s}Supported schema:{s} {d}-{d}\n{s}Compatibility:{s} ", .{
        label_start,
        label_end,
        info.database_schema_version,
        label_start,
        label_end,
        info.minimum_schema_version,
        info.latest_schema_version,
        label_start,
        label_end,
    });
    try writeTerminalText(writer, info.compatibility);
    try writer.writeByte('\n');
}

fn writeJsonDatabaseInfo(writer: *std.Io.Writer, info: DatabaseInfo) !void {
    try std.json.Stringify.value(.{
        .schemaVersion = 1,
        .kind = "caudex.database.info",
        .data = .{
            .databasePath = info.path,
            .databaseKind = info.database_kind,
            .adapterVersion = info.adapter_version,
            .databaseSchemaVersion = info.database_schema_version,
            .minimumSchemaVersion = info.minimum_schema_version,
            .latestSchemaVersion = info.latest_schema_version,
            .compatibility = info.compatibility,
        },
    }, .{}, writer);
    try writer.writeByte('\n');
}

test "color policy disables ANSI for JSON and non-terminal auto output" {
    try std.testing.expect(!(Settings{ .format = .json, .color = .always }).useColor());
    try std.testing.expect(!(Settings{
        .color = .auto,
        .is_terminal = false,
    }).useColor());
    try std.testing.expect(!(Settings{
        .color = .always,
        .is_terminal = true,
        .no_color = true,
    }).useColor());
    try std.testing.expect((Settings{
        .color = .auto,
        .is_terminal = true,
    }).useColor());
}

test "human diagnostics escape paths, messages, and candidate identifiers" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeDatabaseCheck(&writer, .{}, "caudex.database.check", .{
        .path = "/tmp/unsafe\n\x1b[2J.sqlite",
        .status = "ok\r",
    });
    try std.testing.expectEqualStrings(
        "Database: /tmp/unsafe\\x0A\\x1B[2J.sqlite\nIntegrity: ok\\x0D\n",
        writer.buffered(),
    );

    writer = std.Io.Writer.fixed(&buffer);
    try writeFailure(&writer, .human, .{
        .exit_class = errors.ExitClass.runtime,
        .code = "client.runtime",
        .category = "runtime",
        .message = "safe\nmessage",
        .candidate_ids = &.{"candidate\x1b[31m"},
    });
    try std.testing.expectEqualStrings("error: safe\\x0Amessage\ncandidate: candidate\\x1B[31m\n", writer.buffered());
}
