const std = @import("std");
const builtin = @import("builtin");
const caudex = @import("caudex");
const persistence = @import("caudex_persistence");
const sqlite = @import("caudex_sqlite");
const tracking = @import("caudex_tracking");
const errors = @import("errors.zig");
const output = @import("output.zig");

const version = "0.1.0";

const help_text =
    \\Caudex Workout Engine reference client
    \\
    \\Usage:
    \\  caudex [--database PATH] [--format human|json] [--color auto|always|never] database info
    \\  caudex [global options] workout start [start options]
    \\  caudex [global options] workout show --workout ID
    \\  caudex --help
    \\  caudex version
    \\
    \\Environment:
    \\  CAUDEX_DATABASE  Database path used when --database is omitted
    \\
    \\Global options:
    \\  --scope ID        Host scope (default: local)
    \\  --athlete ID      Optional athlete within the host scope
    \\
    \\Workout start options:
    \\  --command-id ID   Idempotency key (generated when omitted)
    \\  --workout ID      Workout ID (generated when omitted)
    \\  --started-at TIME RFC 3339 start time (current UTC time when omitted)
    \\  --occurred-at TIME RFC 3339 command time (defaults to started-at)
    \\
;

const GlobalOptions = struct {
    database_path: ?[]const u8 = null,
    format: output.Format = .human,
    color: output.Color = .auto,
    scope: []const u8 = "local",
    athlete: ?[]const u8 = null,
    command_index: usize = 1,
};

const StartOptions = struct {
    command_id: ?[]const u8 = null,
    workout_id: ?[]const u8 = null,
    started_at: ?[]const u8 = null,
    occurred_at: ?[]const u8 = null,
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

    const requested_format = output.requestedFormat(args);
    const maybe_failure = run(
        init.io,
        init.arena.allocator(),
        init.environ_map,
        args,
        stdout,
    ) catch |err| errors.fromError(err);
    if (maybe_failure) |failure| {
        output.writeFailure(stderr, requested_format, failure) catch {};
        stderr_writer.flush() catch {};
        std.process.exit(@intFromEnum(failure.exit_class));
    }
    stdout_writer.flush() catch |err| switch (err) {
        error.BrokenPipe => return,
        else => |unexpected| return unexpected,
    };
}

fn run(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    args: []const []const u8,
    stdout: *std.Io.Writer,
) !?errors.Failure {
    if (args.len == 1 or
        (args.len == 2 and
            (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "help"))))
    {
        try output.writeHelp(stdout, help_text);
        return null;
    }

    if (args.len == 2 and std.mem.eql(u8, args[1], "version")) {
        try output.writeVersion(stdout, version);
        return null;
    }

    const global = try parseGlobalOptions(args);
    const environment = PathEnvironment{
        .database_override = nonEmpty(environ.get("CAUDEX_DATABASE")),
        .xdg_data_home = nonEmpty(environ.get("XDG_DATA_HOME")),
        .home = nonEmpty(environ.get("HOME")),
        .local_app_data = nonEmpty(environ.get("LOCALAPPDATA")),
    };
    const path = try resolveDatabasePath(
        allocator,
        global.database_path,
        environment,
        nativePlatform(),
    );
    try ensureDatabaseDirectory(io, path);

    const adapter = try sqlite.open(path, .{});
    defer adapter.close();

    const no_color = environ.get("NO_COLOR") != null;
    const is_terminal = std.Io.File.stdout().isTty(io) catch false;
    const settings = output.Settings{
        .format = global.format,
        .color = global.color,
        .is_terminal = is_terminal,
        .no_color = no_color,
    };
    const remaining = args[global.command_index..];
    if (remaining.len == 2 and
        std.mem.eql(u8, remaining[0], "database") and
        std.mem.eql(u8, remaining[1], "info"))
    {
        const metadata = try adapter.metadata();
        try output.writeDatabaseInfo(stdout, settings, .{
            .path = path,
            .database_kind = @tagName(metadata.database_kind),
            .adapter_version = metadata.adapter_version,
            .database_schema_version = metadata.schema_version,
            .minimum_schema_version = metadata.minimum_schema_version,
            .latest_schema_version = metadata.latest_schema_version,
            .compatibility = @tagName(metadata.compatibility),
        });
        return null;
    }
    if (remaining.len >= 2 and
        std.mem.eql(u8, remaining[0], "workout") and
        std.mem.eql(u8, remaining[1], "start"))
    {
        return try startWorkout(
            io,
            allocator,
            adapter,
            global,
            remaining[2..],
            settings,
            stdout,
        );
    }
    if (remaining.len >= 2 and
        std.mem.eql(u8, remaining[0], "workout") and
        std.mem.eql(u8, remaining[1], "show"))
    {
        return try showWorkout(
            allocator,
            adapter,
            global,
            remaining[2..],
            settings,
            stdout,
        );
    }
    return error.InvalidArguments;
}

fn parseGlobalOptions(args: []const []const u8) !GlobalOptions {
    var options = GlobalOptions{};
    var index: usize = 1;
    while (index < args.len and std.mem.startsWith(u8, args[index], "--")) {
        if (std.mem.eql(u8, args[index], "--database")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) return error.InvalidArguments;
            options.database_path = args[index];
        } else if (std.mem.eql(u8, args[index], "--format")) {
            index += 1;
            if (index >= args.len) return error.InvalidArguments;
            options.format = if (std.mem.eql(u8, args[index], "human"))
                .human
            else if (std.mem.eql(u8, args[index], "json"))
                .json
            else
                return error.InvalidArguments;
        } else if (std.mem.eql(u8, args[index], "--scope")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) return error.InvalidArguments;
            options.scope = args[index];
        } else if (std.mem.eql(u8, args[index], "--athlete")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) return error.InvalidArguments;
            options.athlete = args[index];
        } else if (std.mem.eql(u8, args[index], "--color")) {
            index += 1;
            if (index >= args.len) return error.InvalidArguments;
            options.color = if (std.mem.eql(u8, args[index], "auto"))
                .auto
            else if (std.mem.eql(u8, args[index], "always"))
                .always
            else if (std.mem.eql(u8, args[index], "never"))
                .never
            else
                return error.InvalidArguments;
        } else {
            return error.InvalidArguments;
        }
        index += 1;
    }
    options.command_index = index;
    return options;
}

fn startWorkout(
    io: std.Io,
    allocator: std.mem.Allocator,
    adapter: *sqlite.Adapter,
    global: GlobalOptions,
    args: []const []const u8,
    settings: output.Settings,
    stdout: *std.Io.Writer,
) !?errors.Failure {
    const options = try parseStartOptions(args);
    const command_id = options.command_id orelse try generateId(io, allocator, "command");
    const workout_id = options.workout_id orelse try generateId(io, allocator, "workout");
    const started_at = options.started_at orelse try currentTimestamp(io, allocator);
    const occurred_at = options.occurred_at orelse started_at;
    const scope = tracking.Scope{
        .host_scope_key = try tracking.Id.parse(global.scope),
        .athlete_id = if (global.athlete) |athlete|
            try tracking.Id.parse(athlete)
        else
            null,
    };

    const result = try adapter.startWorkout(allocator, .{
        .metadata = .{
            .command_id = try tracking.Id.parse(command_id),
            .occurred_at = try tracking.Timestamp.parse(occurred_at),
        },
        .scope = scope,
        .workout_id = try tracking.Id.parse(workout_id),
        .started_at = try tracking.Timestamp.parse(started_at),
    });
    switch (result) {
        .accepted => |accepted| {
            try output.writeWorkout(stdout, settings, .{
                .document_kind = "caudex.workout.start",
                .command_id = accepted.command_id.bytes,
                .disposition = @tagName(accepted.disposition),
                .workout_id = accepted.workout.id.bytes,
                .host_scope_key = accepted.workout.scope.host_scope_key.bytes,
                .athlete_id = if (accepted.workout.scope.athlete_id) |id|
                    id.bytes
                else
                    null,
                .revision = accepted.workout.revision,
                .status = @tagName(accepted.workout.status),
                .started_at = accepted.workout.started_at.bytes,
                .completed_at = null,
            });
            return null;
        },
        .rejected => |rejected| {
            if (rejected.issues.len == 0) return error.InvalidTrackingResult;
            return errors.fromTrackingIssue(rejected.issues[0]);
        },
    }
}

fn showWorkout(
    allocator: std.mem.Allocator,
    adapter: *sqlite.Adapter,
    global: GlobalOptions,
    args: []const []const u8,
    settings: output.Settings,
    stdout: *std.Io.Writer,
) !?errors.Failure {
    if (args.len != 2 or !std.mem.eql(u8, args[0], "--workout"))
        return error.InvalidArguments;
    const scope = tracking.Scope{
        .host_scope_key = try tracking.Id.parse(global.scope),
        .athlete_id = if (global.athlete) |athlete|
            try tracking.Id.parse(athlete)
        else
            null,
    };
    const result = try adapter.readWorkout(allocator, .{
        .scope = scope,
        .workout_id = try tracking.Id.parse(args[1]),
    });
    switch (result) {
        .found => |workout| {
            try output.writeWorkout(stdout, settings, .{
                .document_kind = "caudex.workout.show",
                .workout_id = workout.id.bytes,
                .host_scope_key = workout.scope.host_scope_key.bytes,
                .athlete_id = if (workout.scope.athlete_id) |id| id.bytes else null,
                .revision = workout.revision,
                .status = @tagName(workout.status),
                .started_at = workout.started_at.bytes,
                .completed_at = if (workout.completed_at) |timestamp|
                    timestamp.bytes
                else
                    null,
            });
            return null;
        },
        .not_found => |issue| return errors.fromTrackingIssue(issue),
    }
}

fn parseStartOptions(args: []const []const u8) !StartOptions {
    var options = StartOptions{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const target: *?[]const u8 = if (std.mem.eql(u8, args[index], "--command-id"))
            &options.command_id
        else if (std.mem.eql(u8, args[index], "--workout"))
            &options.workout_id
        else if (std.mem.eql(u8, args[index], "--started-at"))
            &options.started_at
        else if (std.mem.eql(u8, args[index], "--occurred-at"))
            &options.occurred_at
        else
            return error.InvalidArguments;
        index += 1;
        if (index >= args.len or args[index].len == 0 or target.* != null)
            return error.InvalidArguments;
        target.* = args[index];
    }
    return options;
}

fn generateId(io: std.Io, allocator: std.mem.Allocator, prefix: []const u8) ![]const u8 {
    var random_bytes: [16]u8 = undefined;
    try io.randomSecure(&random_bytes);
    const encoded = std.fmt.bytesToHex(random_bytes, .lower);
    return std.fmt.allocPrint(allocator, "{s}-{s}", .{ prefix, encoded });
}

fn currentTimestamp(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    const seconds = std.Io.Clock.real.now(io).toSeconds();
    if (seconds < 0) return error.ClockBeforeUnixEpoch;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(seconds) };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        },
    );
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
                std.mem.eql(u8, name, "caudex_sqlite") or
                std.mem.eql(u8, name, "caudex_tracking") or
                std.mem.eql(u8, name, "errors.zig") or
                std.mem.eql(u8, name, "output.zig"),
        );

        import_count += 1;
        remainder = tail[name_end + 1 ..];
    }

    try std.testing.expectEqual(@as(usize, 8), import_count);
}

test "client sources contain no SQL or private path imports" {
    const sources = [_][]const u8{
        @embedFile("main.zig"),
        @embedFile("errors.zig"),
        @embedFile("output.zig"),
    };
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

    for (sources) |source| {
        for (forbidden) |needle| {
            try std.testing.expect(std.mem.indexOf(u8, source, needle) == null);
        }
    }
}
