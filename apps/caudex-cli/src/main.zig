const std = @import("std");
const builtin = @import("builtin");
const caudex = @import("caudex");
const persistence = @import("caudex_persistence");
const sqlite = @import("caudex_sqlite");

const version = "0.1.0";

const help_text =
    \\Caudex Workout Engine reference client
    \\
    \\Usage:
    \\  caudex [--database PATH] [--format human|json] database info
    \\  caudex --help
    \\  caudex version
    \\
    \\Environment:
    \\  CAUDEX_DATABASE  Database path used when --database is omitted
    \\
;

const OutputFormat = enum { human, json };

const DatabaseInfoOptions = struct {
    explicit_path: ?[]const u8 = null,
    format: OutputFormat = .human,
};

const PathEnvironment = struct {
    database_override: ?[]const u8 = null,
    xdg_data_home: ?[]const u8 = null,
    home: ?[]const u8 = null,
    local_app_data: ?[]const u8 = null,
};

const Platform = enum { unix, macos, windows };

pub fn main(init: std.process.Init) !void {
    comptime {
        _ = caudex.engine;
        _ = persistence.contract_version;
        _ = sqlite.adapter_version;
    }

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    run(init.io, init.arena.allocator(), init.environ_map, args, stdout) catch |err| {
        const failure = failureFor(err);
        try stderr.writeAll(failure.message);
        try stderr.flush();
        std.process.exit(failure.exit_code);
    };
    try stdout.flush();
}

fn run(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    args: []const []const u8,
    stdout: *std.Io.Writer,
) !void {
    if (args.len == 1 or
        (args.len == 2 and
            (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "help"))))
    {
        try stdout.writeAll(help_text);
        return;
    }

    if (args.len == 2 and std.mem.eql(u8, args[1], "version")) {
        try stdout.print("caudex {s}\n", .{version});
        return;
    }

    const options = try parseDatabaseInfo(args);
    const environment = PathEnvironment{
        .database_override = nonEmpty(environ.get("CAUDEX_DATABASE")),
        .xdg_data_home = nonEmpty(environ.get("XDG_DATA_HOME")),
        .home = nonEmpty(environ.get("HOME")),
        .local_app_data = nonEmpty(environ.get("LOCALAPPDATA")),
    };
    const path = try resolveDatabasePath(
        allocator,
        options.explicit_path,
        environment,
        nativePlatform(),
    );
    try ensureDatabaseDirectory(io, path);

    const adapter = try sqlite.open(path, .{});
    defer adapter.close();
    const metadata = try adapter.metadata();

    switch (options.format) {
        .human => try writeHumanDatabaseInfo(stdout, path, metadata),
        .json => try writeJsonDatabaseInfo(stdout, path, metadata),
    }
}

fn parseDatabaseInfo(args: []const []const u8) !DatabaseInfoOptions {
    var options = DatabaseInfoOptions{};
    var index: usize = 1;
    while (index < args.len and std.mem.startsWith(u8, args[index], "--")) {
        if (std.mem.eql(u8, args[index], "--database")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) return error.InvalidArguments;
            options.explicit_path = args[index];
        } else if (std.mem.eql(u8, args[index], "--format")) {
            index += 1;
            if (index >= args.len) return error.InvalidArguments;
            options.format = if (std.mem.eql(u8, args[index], "human"))
                .human
            else if (std.mem.eql(u8, args[index], "json"))
                .json
            else
                return error.InvalidArguments;
        } else {
            return error.InvalidArguments;
        }
        index += 1;
    }

    if (args.len - index != 2 or
        !std.mem.eql(u8, args[index], "database") or
        !std.mem.eql(u8, args[index + 1], "info"))
    {
        return error.InvalidArguments;
    }
    return options;
}

fn resolveDatabasePath(
    allocator: std.mem.Allocator,
    explicit_path: ?[]const u8,
    environment: PathEnvironment,
    platform: Platform,
) ![:0]u8 {
    if (nonEmpty(explicit_path)) |path| return allocator.dupeZ(u8, path);
    if (nonEmpty(environment.database_override)) |path|
        return allocator.dupeZ(u8, path);

    return switch (platform) {
        .macos => if (nonEmpty(environment.home)) |home|
            std.fs.path.joinZ(
                allocator,
                &.{ home, "Library", "Application Support", "Caudex", "caudex.sqlite" },
            )
        else
            error.DataDirectoryUnavailable,
        .windows => if (nonEmpty(environment.local_app_data)) |data|
            std.fs.path.joinZ(allocator, &.{ data, "Caudex", "caudex.sqlite" })
        else
            error.DataDirectoryUnavailable,
        .unix => if (nonEmpty(environment.xdg_data_home)) |data|
            std.fs.path.joinZ(allocator, &.{ data, "caudex", "caudex.sqlite" })
        else if (nonEmpty(environment.home)) |home|
            std.fs.path.joinZ(
                allocator,
                &.{ home, ".local", "share", "caudex", "caudex.sqlite" },
            )
        else
            error.DataDirectoryUnavailable,
    };
}

fn ensureDatabaseDirectory(io: std.Io, path: []const u8) !void {
    if (std.mem.eql(u8, path, ":memory:")) return;
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0) return;
    try std.Io.Dir.cwd().createDirPath(io, parent);
}

fn writeHumanDatabaseInfo(
    writer: *std.Io.Writer,
    path: []const u8,
    metadata: sqlite.Metadata,
) !void {
    try writer.print(
        \\Database: {s}
        \\Kind: {s}
        \\Adapter version: {s}
        \\Schema version: {d}
        \\Supported schema: {d}-{d}
        \\Compatibility: {s}
        \\
    , .{
        path,
        @tagName(metadata.database_kind),
        metadata.adapter_version,
        metadata.schema_version,
        metadata.minimum_schema_version,
        metadata.latest_schema_version,
        @tagName(metadata.compatibility),
    });
}

fn writeJsonDatabaseInfo(
    writer: *std.Io.Writer,
    path: []const u8,
    metadata: sqlite.Metadata,
) !void {
    try std.json.Stringify.value(.{
        .kind = "caudex.database-info",
        .schema_version = 1,
        .database_path = path,
        .database_kind = @tagName(metadata.database_kind),
        .adapter_version = metadata.adapter_version,
        .database_schema_version = metadata.schema_version,
        .minimum_schema_version = metadata.minimum_schema_version,
        .latest_schema_version = metadata.latest_schema_version,
        .compatibility = @tagName(metadata.compatibility),
    }, .{}, writer);
    try writer.writeByte('\n');
}

fn nonEmpty(value: ?[]const u8) ?[]const u8 {
    const bytes = value orelse return null;
    return if (bytes.len == 0) null else bytes;
}

fn nativePlatform() Platform {
    return switch (builtin.os.tag) {
        .macos => .macos,
        .windows => .windows,
        else => .unix,
    };
}

const Failure = struct {
    exit_code: u8,
    message: []const u8,
};

fn failureFor(err: anyerror) Failure {
    return switch (err) {
        error.InvalidArguments => .{
            .exit_code = 2,
            .message = "error: invalid arguments; run 'caudex --help'\n",
        },
        error.Busy => .{
            .exit_code = 7,
            .message = "error: database is busy\n",
        },
        error.Corrupt,
        error.MigrationFailed,
        error.UnsupportedSchema,
        => .{
            .exit_code = 8,
            .message = "error: database is incompatible or corrupt\n",
        },
        error.DataDirectoryUnavailable => .{
            .exit_code = 70,
            .message = "error: platform data directory is unavailable\n",
        },
        else => .{
            .exit_code = 70,
            .message = "error: database operation failed\n",
        },
    };
}

test "database path precedence is explicit then environment then default" {
    const allocator = std.testing.allocator;
    const environment = PathEnvironment{
        .database_override = "environment.sqlite",
        .xdg_data_home = "/data",
        .home = "/home/test",
    };

    const explicit = try resolveDatabasePath(
        allocator,
        "explicit.sqlite",
        environment,
        .unix,
    );
    defer allocator.free(explicit);
    try std.testing.expectEqualStrings("explicit.sqlite", explicit);

    const overridden = try resolveDatabasePath(allocator, null, environment, .unix);
    defer allocator.free(overridden);
    try std.testing.expectEqualStrings("environment.sqlite", overridden);

    const defaulted = try resolveDatabasePath(
        allocator,
        null,
        .{ .xdg_data_home = "/data", .home = "/home/test" },
        .unix,
    );
    defer allocator.free(defaulted);
    try std.testing.expectEqualStrings("/data/caudex/caudex.sqlite", defaulted);
}

test "platform database defaults follow native conventions" {
    const allocator = std.testing.allocator;

    const unix = try resolveDatabasePath(
        allocator,
        null,
        .{ .home = "/home/test" },
        .unix,
    );
    defer allocator.free(unix);
    try std.testing.expectEqualStrings(
        "/home/test/.local/share/caudex/caudex.sqlite",
        unix,
    );

    const macos = try resolveDatabasePath(
        allocator,
        null,
        .{ .home = "/Users/test" },
        .macos,
    );
    defer allocator.free(macos);
    try std.testing.expectEqualStrings(
        "/Users/test/Library/Application Support/Caudex/caudex.sqlite",
        macos,
    );

    const windows = try resolveDatabasePath(
        allocator,
        null,
        .{ .local_app_data = "C:\\Users\\test\\AppData\\Local" },
        .windows,
    );
    defer allocator.free(windows);
    try std.testing.expectEqualStrings(
        "C:\\Users\\test\\AppData\\Local/Caudex/caudex.sqlite",
        windows,
    );
}

test "empty environment override does not mask platform default" {
    const path = try resolveDatabasePath(
        std.testing.allocator,
        null,
        .{
            .database_override = "",
            .xdg_data_home = "/data",
        },
        .unix,
    );
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("/data/caudex/caudex.sqlite", path);
}

test "missing database directories are created before adapter open" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/missing/nested/caudex.sqlite",
        .{temporary.sub_path},
        0,
    );
    defer std.testing.allocator.free(path);

    try ensureDatabaseDirectory(std.testing.io, path);
    const adapter = try sqlite.open(path, .{});
    defer adapter.close();
    const metadata = try adapter.metadata();
    try std.testing.expectEqual(sqlite.DatabaseKind.file, metadata.database_kind);
}

test "memory database resolves without directory creation" {
    const path = try resolveDatabasePath(
        std.testing.allocator,
        ":memory:",
        .{},
        .unix,
    );
    defer std.testing.allocator.free(path);
    try ensureDatabaseDirectory(std.testing.io, path);
    const adapter = try sqlite.open(path, .{});
    defer adapter.close();
    const metadata = try adapter.metadata();
    try std.testing.expectEqual(sqlite.DatabaseKind.memory, metadata.database_kind);
}

test "client source imports only approved public packages" {
    const source = @embedFile("main.zig");
    const import_prefix = "@im" ++ "port(\"";

    var remainder: []const u8 = source;
    var import_count: usize = 0;
    while (std.mem.indexOf(u8, remainder, import_prefix)) |start| {
        const name_start = start + import_prefix.len;
        const tail = remainder[name_start..];
        const name_end = std.mem.indexOfScalar(u8, tail, '"') orelse
            return error.MalformedImport;
        const name = tail[0..name_end];

        try std.testing.expect(
            std.mem.eql(u8, name, "std") or
                std.mem.eql(u8, name, "builtin") or
                std.mem.eql(u8, name, "caudex") or
                std.mem.eql(u8, name, "caudex_persistence") or
                std.mem.eql(u8, name, "caudex_sqlite"),
        );

        import_count += 1;
        remainder = tail[name_end + 1 ..];
    }

    try std.testing.expectEqual(@as(usize, 5), import_count);
}

test "client source contains no SQL or private path imports" {
    const source = @embedFile("main.zig");
    const forbidden = [_][]const u8{
        ".." ++ "/",
        "core/" ++ "src/",
        "adap" ++ "ters/",
        "migra" ++ "tions/",
        "SEL" ++ "ECT ",
        "INS" ++ "ERT ",
        "UPD" ++ "ATE ",
        "DEL" ++ "ETE ",
    };

    for (forbidden) |needle| {
        try std.testing.expect(std.mem.indexOf(u8, source, needle) == null);
    }
}
