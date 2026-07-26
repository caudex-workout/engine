const std = @import("std");
const errors = @import("errors.zig");

pub const Format = enum { human, json };
pub const Color = enum { auto, always, never };

pub const Settings = struct {
    format: Format = .human,
    color: Color = .auto,
    is_terminal: bool = false,
    no_color: bool = false,

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

pub fn writeFailure(
    writer: *std.Io.Writer,
    format: Format,
    failure: errors.Failure,
) !void {
    switch (format) {
        .human => try writer.print("error: {s}\n", .{failure.message}),
        .json => {
            try std.json.Stringify.value(.{
                .schemaVersion = 1,
                .kind = "caudex.error",
                .@"error" = .{
                    .code = failure.code,
                    .category = failure.category,
                    .message = failure.message,
                },
            }, .{}, writer);
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
    try writer.print(
        \\{s}Database:{s} {s}
        \\{s}Kind:{s} {s}
        \\{s}Adapter version:{s} {s}
        \\{s}Schema version:{s} {d}
        \\{s}Supported schema:{s} {d}-{d}
        \\{s}Compatibility:{s} {s}
        \\
    , .{
        label_start,
        label_end,
        info.path,
        label_start,
        label_end,
        info.database_kind,
        label_start,
        label_end,
        info.adapter_version,
        label_start,
        label_end,
        info.database_schema_version,
        label_start,
        label_end,
        info.minimum_schema_version,
        info.latest_schema_version,
        label_start,
        label_end,
        info.compatibility,
    });
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
