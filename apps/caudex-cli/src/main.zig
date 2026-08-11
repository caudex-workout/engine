const std = @import("std");
const builtin = @import("builtin");
const caudex = @import("caudex");
const persistence = @import("caudex_persistence");
const sqlite = @import("caudex_sqlite");
const tracking = @import("caudex_tracking");
const errors = @import("errors.zig");
const output = @import("output.zig");
const security = @import("security.zig");
const use_cases = @import("use_cases.zig");
const commands = @import("commands.zig");
const tui_actions = @import("tui/actions.zig");

const version = "0.1.0";

const help_text =
    \\Caudex Workout Engine reference client
    \\
    \\Usage:
    \\  caudex [--database PATH] [--format human|json] [--color auto|always|never] database info|check
    \\  caudex [global options] database backup DESTINATION
    \\  caudex [global options] database restore SOURCE --yes
    \\  caudex [global options] doctor
    \\  caudex [global options] workout start [start options]
    \\  caudex [global options] workout add-exercise EXERCISE [options]
    \\  caudex [global options] workout show [--workout ID]
    \\  caudex [global options] set log [--workout ID] [--exercise ID] [--set ID] [METRICS...]
    \\  caudex [global options] set skip [--workout ID] [--exercise ID] [--set ID]
    \\  caudex [global options] set reopen [--workout ID] [--exercise ID] --set ID
    \\  caudex [global options] workout finish [--workout ID]
    \\  caudex [global options] workout cancel [--workout ID] [--yes]
    \\  caudex [global options] exercise create ID --name NAME [exercise options]
    \\  caudex [global options] exercise edit EXERCISE [exercise options]
    \\  caudex [global options] exercise show EXERCISE
    \\  caudex [global options] exercise list [--limit N] [--include-archived]
    \\  caudex [global options] exercise search TEXT [--limit N] [--include-archived]
    \\  caudex [global options] exercise archive|restore EXERCISE [command options]
    \\  caudex [global options] history list [--from TIME] [--through TIME] [--limit N]
    \\  caudex [global options] history show WORKOUT
    \\  caudex [global options] history exercise EXERCISE [--limit N]
    \\  caudex [global options] history last EXERCISE
    \\  caudex [global options] history correct-set --workout ID --exercise ID --set ID METRICS... [--yes]
    \\  caudex [global options] config path|show|set (color|table) VALUE
    \\  caudex batch FILE
    \\  caudex completion bash|zsh|fish
    \\  caudex command-reference
    \\  caudex --help
    \\  caudex version
    \\
    \\Environment:
    \\  CAUDEX_DATABASE  Database path used when --database is omitted
    \\
    \\Global options:
    \\  --scope ID        Host scope (default: local)
    \\  --athlete ID      Optional athlete within the host scope
    \\  --quiet           Suppress successful command output
    \\
    \\Set log metrics:
    \\  --reps N  --load N UNIT  --rir N  --rpe N  --duration N UNIT
    \\  Shorthand examples: 70kg 8r @2rir
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
    quiet: bool = false,
};

const StartOptions = struct {
    command_id: ?[]const u8 = null,
    workout_id: ?[]const u8 = null,
    started_at: ?[]const u8 = null,
    occurred_at: ?[]const u8 = null,
};

const AddExerciseOptions = struct {
    reference: []const u8,
    workout_id: ?[]const u8 = null,
    command_id: ?[]const u8 = null,
    membership_id: ?[]const u8 = null,
    occurred_at: ?[]const u8 = null,
    before: ?[]const u8 = null,
    after: ?[]const u8 = null,
};

const SetOptions = struct {
    workout_id: ?[]const u8 = null,
    exercise_id: ?[]const u8 = null,
    set_id: ?[]const u8 = null,
    command_id: ?[]const u8 = null,
    occurred_at: ?[]const u8 = null,
    metrics: [5]tracking.Metric = undefined,
    metric_count: usize = 0,
};

const EndOptions = struct {
    workout_id: ?[]const u8 = null,
    command_id: ?[]const u8 = null,
    occurred_at: ?[]const u8 = null,
    yes: bool = false,
};

const CatalogOptions = struct {
    reference: ?[]const u8 = null,
    name: ?[]const u8 = null,
    aliases: [32][]const u8 = undefined,
    alias_count: usize = 0,
    equipment: [32][]const u8 = undefined,
    equipment_count: usize = 0,
    movements: [32][]const u8 = undefined,
    movement_count: usize = 0,
    unilateral: ?bool = null,
    command_id: ?[]const u8 = null,
    occurred_at: ?[]const u8 = null,
    limit: u16 = 25,
    include_archived: bool = false,
};

const HistoryOptions = struct {
    reference: ?[]const u8 = null,
    workout_id: ?[]const u8 = null,
    exercise_id: ?[]const u8 = null,
    set_id: ?[]const u8 = null,
    command_id: ?[]const u8 = null,
    occurred_at: ?[]const u8 = null,
    from: ?[]const u8 = null,
    through: ?[]const u8 = null,
    limit: u16 = 25,
    yes: bool = false,
    metrics: [5]tracking.Metric = undefined,
    metric_count: usize = 0,
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
    ) catch |err| blk: {
        if (security.isClosedOutput(err)) return;
        break :blk errors.fromError(err);
    };
    if (maybe_failure) |failure| {
        output.writeFailure(stderr, requested_format, failure) catch |err| {
            if (security.isClosedOutput(err)) return;
        };
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
) anyerror!?errors.Failure {
    try security.validateArgs(args);
    if (args.len == 1 or
        (args.len == 2 and
            (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "help"))))
    {
        try output.writeHelp(stdout, help_text);
        return null;
    }

    if (args.len == 2 and std.mem.eql(u8, args[1], "version")) {
        try stdout.print("caudex {s}\nengine: {s} (schema {d})\npersistence contract: {d}\ntracking contract: {d}\nsqlite adapter: {s} (schema {d}-{d})\n", .{ version, caudex.engine.engine_version, caudex.engine.schema_version, persistence.contract_version, tracking.contract_version, sqlite.adapter_version, sqlite.minimum_schema_version, sqlite.schema_version });
        return null;
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "batch")) {
        return try runBatch(io, allocator, environ, args[2], stdout);
    }

    const global = try parseGlobalOptions(args);
    const command = args[global.command_index..];
    // Help is a parser concern, not a database command. Handle it before
    // resolving paths or opening SQLite so `history --help` works on a fresh
    // machine and never creates state as a side effect.
    if (command.len > 0 and
        (std.mem.eql(u8, command[command.len - 1], "--help") or
            std.mem.eql(u8, command[command.len - 1], "help")))
    {
        try output.writeHelp(stdout, help_text);
        return null;
    }
    if (command.len == 2 and std.mem.eql(u8, command[0], "completion")) {
        const shell = commands.parseCompletionShell(command[1]) orelse return error.InvalidArguments;
        try commands.writeCompletion(stdout, shell);
        return null;
    }
    if (command.len == 1 and std.mem.eql(u8, command[0], "command-reference")) {
        try commands.writeReference(stdout);
        return null;
    }
    const environment = PathEnvironment{
        .database_override = nonEmpty(environ.get("CAUDEX_DATABASE")),
        .xdg_data_home = nonEmpty(environ.get("XDG_DATA_HOME")),
        .home = nonEmpty(environ.get("HOME")),
        .local_app_data = nonEmpty(environ.get("LOCALAPPDATA")),
    };
    const no_color = environ.get("NO_COLOR") != null;
    const is_terminal = std.Io.File.stdout().isTty(io) catch false;
    const settings = output.Settings{
        .format = global.format,
        .color = global.color,
        .is_terminal = is_terminal,
        .no_color = no_color,
        .quiet = global.quiet,
    };
    var remaining = args[global.command_index..];
    // Config is a client-side preference command. Dispatch it before resolving
    // or opening the default database so `config path` and `config show` do not
    // create unrelated database state.
    if (remaining.len >= 2 and std.mem.eql(u8, remaining[0], "config"))
        return try configCommand(io, allocator, environment, remaining[1..], settings, stdout);
    const path = try resolveDatabasePath(
        allocator,
        global.database_path,
        environment,
        nativePlatform(),
    );
    try security.validatePath(path);
    try ensureDatabaseDirectory(io, path);
    try rejectSymlink(io, path);

    const adapter = try sqlite.open(path, .{});
    defer adapter.close();
    try setPrivateFilePermissions(io, path);
    if (remaining.len > 0) {
        const alias: ?[]const u8 = if (std.mem.eql(u8, remaining[0], "w")) "workout" else if (std.mem.eql(u8, remaining[0], "s")) "set" else if (std.mem.eql(u8, remaining[0], "e")) "exercise" else if (std.mem.eql(u8, remaining[0], "h")) "history" else null;
        if (alias) |noun| {
            const expanded = try allocator.dupe([]const u8, remaining);
            expanded[0] = noun;
            remaining = expanded;
        }
    }
    if (remaining.len >= 2 and std.mem.eql(u8, remaining[0], "history"))
        return try historyCommand(io, allocator, adapter, global, remaining[1], remaining[2..], settings, stdout);
    if (remaining.len >= 2 and std.mem.eql(u8, remaining[0], "exercise"))
        return try catalogCommand(io, allocator, adapter, global, remaining[1], remaining[2..], settings, stdout);
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
    if (remaining.len == 3 and std.mem.eql(u8, remaining[0], "database") and std.mem.eql(u8, remaining[1], "backup")) {
        const destination = try allocator.dupeZ(u8, remaining[2]);
        try adapter.backup(io, destination);
        if (!settings.quiet) {
            try stdout.writeAll("Backup created: ");
            try output.writeTerminalText(stdout, remaining[2]);
            try stdout.writeByte('\n');
        }
        return null;
    }
    if (remaining.len == 4 and std.mem.eql(u8, remaining[0], "database") and std.mem.eql(u8, remaining[1], "restore") and std.mem.eql(u8, remaining[3], "--yes")) {
        const source = try allocator.dupeZ(u8, remaining[2]);
        try adapter.restore(io, source);
        if (!settings.quiet) {
            try stdout.writeAll("Database restored from: ");
            try output.writeTerminalText(stdout, remaining[2]);
            try stdout.writeByte('\n');
        }
        return null;
    }
    if ((remaining.len == 2 and std.mem.eql(u8, remaining[0], "database") and std.mem.eql(u8, remaining[1], "check")) or
        (remaining.len == 1 and std.mem.eql(u8, remaining[0], "doctor")))
    {
        const report = try adapter.integrity();
        try output.writeDatabaseCheck(stdout, settings, if (remaining.len == 1) "caudex.database.doctor" else "caudex.database.check", .{
            .path = path,
            .status = @tagName(report.status),
        });
        return null;
    }
    if (remaining.len >= 2 and
        std.mem.eql(u8, remaining[0], "set"))
    {
        if (std.mem.eql(u8, remaining[1], "log"))
            return try changeSet(io, allocator, adapter, global, remaining[2..], settings, stdout, .log);
        if (std.mem.eql(u8, remaining[1], "skip"))
            return try changeSet(io, allocator, adapter, global, remaining[2..], settings, stdout, .skip);
        if (std.mem.eql(u8, remaining[1], "reopen"))
            return try changeSet(io, allocator, adapter, global, remaining[2..], settings, stdout, .reopen);
    }
    if (remaining.len >= 2 and
        std.mem.eql(u8, remaining[0], "workout") and
        (std.mem.eql(u8, remaining[1], "finish") or std.mem.eql(u8, remaining[1], "cancel")))
    {
        return try endWorkout(io, allocator, adapter, global, remaining[2..], settings, stdout, if (std.mem.eql(u8, remaining[1], "finish")) .finish else .cancel);
    }
    if (remaining.len >= 2 and
        std.mem.eql(u8, remaining[0], "workout") and
        std.mem.eql(u8, remaining[1], "add-exercise"))
    {
        return try addExercise(
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

const BatchOperation = struct { args: []const []const u8 };

fn runBatch(io: std.Io, allocator: std.mem.Allocator, environ: *const std.process.Environ.Map, path: []const u8, stdout: *std.Io.Writer) !?errors.Failure {
    try security.validatePath(path);
    try rejectSymlink(io, path);
    const input = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(security.max_batch_bytes));
    var lines = std.mem.splitScalar(u8, input, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (line.len > security.max_batch_line_bytes or count == security.max_batch_operations) return error.InvalidArguments;
        const parsed = std.json.parseFromSlice(BatchOperation, allocator, line, .{ .duplicate_field_behavior = .@"error", .ignore_unknown_fields = false, .allocate = .alloc_always }) catch return error.InvalidArguments;
        defer parsed.deinit();
        if (parsed.value.args.len == 0 or std.mem.eql(u8, parsed.value.args[0], "batch")) return error.InvalidArguments;
        const command = try allocator.alloc([]const u8, parsed.value.args.len + 3);
        command[0] = "caudex";
        command[1] = "--format";
        command[2] = "json";
        @memcpy(command[3..], parsed.value.args);
        if (try run(io, allocator, environ, command, stdout)) |failure|
            try output.writeFailure(stdout, .json, failure);
        count += 1;
    }
    return null;
}

fn configCommand(io: std.Io, allocator: std.mem.Allocator, environment: PathEnvironment, args: []const []const u8, settings: output.Settings, stdout: *std.Io.Writer) !?errors.Failure {
    const path = try resolveConfigPath(allocator, environment, nativePlatform());
    try security.validatePath(path);
    try ensurePrivateDirectory(io, path);
    try rejectSymlink(io, path);
    if (args.len == 1 and std.mem.eql(u8, args[0], "path")) {
        if (settings.format == .json) {
            try std.json.Stringify.value(.{ .schemaVersion = 1, .kind = "caudex.config.path", .data = .{ .path = path } }, .{}, stdout);
        } else {
            try output.writeTerminalText(stdout, path);
        }
        if (settings.format == .json) try stdout.writeByte('\n');
        if (settings.format == .human) try stdout.writeByte('\n');
        return null;
    }
    if (args.len == 1 and std.mem.eql(u8, args[0], "show")) {
        const value = readConfig(allocator, io, path) catch "color=auto\ntable=compact\n";
        if (settings.format == .json) try std.json.Stringify.value(.{ .schemaVersion = 1, .kind = "caudex.config.show", .data = .{ .path = path, .preferences = value } }, .{}, stdout) else try stdout.writeAll(value);
        if (settings.format == .json) try stdout.writeByte('\n');
        return null;
    }
    if (args.len != 3 or !std.mem.eql(u8, args[0], "set") or (!std.mem.eql(u8, args[1], "color") and !std.mem.eql(u8, args[1], "table"))) return error.InvalidArguments;
    if (std.mem.eql(u8, args[1], "color") and !std.mem.eql(u8, args[2], "auto") and !std.mem.eql(u8, args[2], "always") and !std.mem.eql(u8, args[2], "never")) return error.InvalidArguments;
    if (std.mem.eql(u8, args[1], "table") and !std.mem.eql(u8, args[2], "compact") and !std.mem.eql(u8, args[2], "wide")) return error.InvalidArguments;
    const existing = readConfig(allocator, io, path) catch "color=auto\ntable=compact\n";
    const updated = if (std.mem.eql(u8, args[1], "color")) try std.fmt.allocPrint(allocator, "color={s}\ntable={s}\n", .{ args[2], configValue(existing, "table") orelse "compact" }) else try std.fmt.allocPrint(allocator, "color={s}\ntable={s}\n", .{ configValue(existing, "color") orelse "auto", args[2] });
    try writeConfigAtomically(io, path, updated);
    if (settings.format == .json) {
        try std.json.Stringify.value(.{ .schemaVersion = 1, .kind = "caudex.config.set", .data = .{ .path = path, .key = args[1], .value = args[2] } }, .{}, stdout);
        try stdout.writeByte('\n');
    } else try stdout.print("{s}={s}\n", .{ args[1], args[2] });
    return null;
}

fn historyCommand(io: std.Io, allocator: std.mem.Allocator, adapter: *sqlite.Adapter, global: GlobalOptions, verb: []const u8, args: []const []const u8, settings: output.Settings, stdout: *std.Io.Writer) !?errors.Failure {
    const scope = try trackingScope(global);
    if (std.mem.eql(u8, verb, "list")) {
        const options = try parseHistoryOptions(args, false, false);
        const page = try adapter.listHistory(allocator, .{ .scope = scope, .from = if (options.from) |value| try tracking.Timestamp.parse(value) else null, .through = if (options.through) |value| try tracking.Timestamp.parse(value) else null, .max_results = options.limit });
        try writeHistoryPage(allocator, stdout, settings, "caudex.history.list", page);
        return null;
    }
    if (std.mem.eql(u8, verb, "show")) {
        const options = try parseHistoryOptions(args, true, false);
        const result = try adapter.readWorkout(allocator, .{ .scope = scope, .workout_id = try tracking.Id.parse(options.reference.?) });
        const workout = switch (result) {
            .found => |value| value,
            .not_found => return errors.workoutNotFound(),
        };
        if (workout.status != .completed) return errors.managedExerciseNotFound();
        try writeWorkoutState(allocator, stdout, settings, "caudex.history.show", null, null, workout);
        return null;
    }
    if (std.mem.eql(u8, verb, "exercise") or std.mem.eql(u8, verb, "last")) {
        const options = try parseHistoryOptions(args, true, false);
        const exercise = switch (try use_cases.resolveManagedExercise(adapter, allocator, scope.host_scope_key, options.reference.?)) {
            .found => |value| value,
            .not_found => return errors.managedExerciseNotFound(),
            .ambiguous => |values| return errors.ambiguousExercise(try managedExerciseIds(allocator, values)),
        };
        if (std.mem.eql(u8, verb, "last")) {
            const result = try adapter.lastPerformance(allocator, .{ .scope = scope, .exercise_id = .{ .bytes = exercise.exercise.id } });
            const workout = switch (result) {
                .found => |value| value,
                .not_found => return errors.workoutNotFound(),
            };
            try writeHistoryPage(allocator, stdout, settings, "caudex.history.last", .{ .workouts = &.{workout} });
            return null;
        }
        const page = try adapter.listHistory(allocator, .{ .scope = scope, .exercise_id = .{ .bytes = exercise.exercise.id }, .max_results = options.limit });
        try writeHistoryPage(allocator, stdout, settings, "caudex.history.exercise", page);
        return null;
    }
    if (!std.mem.eql(u8, verb, "correct-set")) return error.InvalidArguments;
    const options = try parseHistoryOptions(args, false, true);
    if (!options.yes) {
        if (!(std.Io.File.stdin().isTty(io) catch false)) return errors.confirmationRequired();
        try stdout.writeAll("Correct this completed set? [y/N] ");
        try stdout.flush();
        var buffer: [16]u8 = undefined;
        var reader = std.Io.File.stdin().reader(io, &buffer);
        const answer = (try reader.interface.takeDelimiter('\n')) orelse return errors.cancelledByUser();
        if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, answer, " \r\t"), "y") and !std.ascii.eqlIgnoreCase(std.mem.trim(u8, answer, " \r\t"), "yes")) return errors.cancelledByUser();
    }
    const current = switch (try adapter.readWorkout(allocator, .{ .scope = scope, .workout_id = try tracking.Id.parse(options.workout_id.?) })) {
        .found => |value| value,
        .not_found => return errors.workoutNotFound(),
    };
    const result = try adapter.correctSet(allocator, .{ .metadata = .{ .command_id = try tracking.Id.parse(options.command_id orelse try generateId(io, allocator, "command")), .occurred_at = try tracking.Timestamp.parse(options.occurred_at orelse try currentTimestamp(io, allocator)) }, .scope = scope, .workout_id = current.id, .expected_revision = current.revision, .membership_id = try tracking.Id.parse(options.exercise_id.?), .set_id = try tracking.Id.parse(options.set_id.?), .actual_metrics = options.metrics[0..options.metric_count], .completed_at = try tracking.Timestamp.parse(options.occurred_at orelse try currentTimestamp(io, allocator)) });
    switch (result) {
        .accepted => |accepted| {
            try writeWorkoutState(allocator, stdout, settings, "caudex.history.set_corrected", accepted.command_id.bytes, @tagName(accepted.disposition), accepted.workout);
            return null;
        },
        .rejected => |rejected| return errors.fromTrackingIssue(rejected.issues[0]),
    }
}

fn writeHistoryPage(allocator: std.mem.Allocator, stdout: *std.Io.Writer, settings: output.Settings, kind: []const u8, page: tracking.HistoryPage) !void {
    const values = try allocator.alloc(output.HistoryInfo, page.workouts.len);
    for (page.workouts, 0..) |workout, index| values[index] = .{ .workoutId = workout.id.bytes, .revision = workout.revision, .completedAt = workout.completed_at.?.bytes, .exerciseCount = workout.exercises.len };
    try output.writeHistory(stdout, settings, kind, values);
}

fn parseHistoryOptions(args: []const []const u8, require_reference: bool, correction: bool) !HistoryOptions {
    var options = HistoryOptions{};
    var index: usize = 0;
    if (require_reference) {
        if (args.len == 0 or std.mem.startsWith(u8, args[0], "--")) return error.InvalidArguments;
        options.reference = args[0];
        index = 1;
    }
    while (index < args.len) : (index += 1) {
        const token = args[index];
        if (correction and std.mem.eql(u8, token, "--yes")) {
            if (options.yes) return error.InvalidArguments;
            options.yes = true;
            continue;
        }
        if (correction and !std.mem.startsWith(u8, token, "--")) {
            const metric = try parseMetricShorthand(token);
            try appendHistoryMetric(&options, metric.code, metric.value, metric.unit);
            continue;
        }
        const target: *?[]const u8 = if (std.mem.eql(u8, token, "--workout")) &options.workout_id else if (std.mem.eql(u8, token, "--exercise")) &options.exercise_id else if (std.mem.eql(u8, token, "--set")) &options.set_id else if (std.mem.eql(u8, token, "--command-id")) &options.command_id else if (std.mem.eql(u8, token, "--occurred-at")) &options.occurred_at else if (std.mem.eql(u8, token, "--from")) &options.from else if (std.mem.eql(u8, token, "--through")) &options.through else if (std.mem.eql(u8, token, "--limit")) {
            index += 1;
            if (index >= args.len) return error.InvalidArguments;
            options.limit = std.fmt.parseInt(u16, args[index], 10) catch return error.InvalidArguments;
            continue;
        } else return error.InvalidArguments;
        index += 1;
        if (index >= args.len or target.* != null or args[index].len == 0) return error.InvalidArguments;
        target.* = args[index];
    }
    if (options.limit == 0 or options.limit > 100) return error.InvalidArguments;
    if (correction and (options.workout_id == null or options.exercise_id == null or options.set_id == null or options.metric_count == 0)) return error.InvalidArguments;
    return options;
}

fn appendHistoryMetric(options: *HistoryOptions, code: []const u8, value: tracking.Decimal, unit: caudex.primitives.Unit) !void {
    if (options.metric_count == options.metrics.len) return error.InvalidArguments;
    for (options.metrics[0..options.metric_count]) |metric| if (std.mem.eql(u8, metric.code.bytes, code)) return error.InvalidArguments;
    options.metrics[options.metric_count] = .{ .code = try tracking.Id.parse(code), .value = .{ .value = value, .unit = unit } };
    options.metric_count += 1;
}

fn catalogCommand(io: std.Io, allocator: std.mem.Allocator, adapter: *sqlite.Adapter, global: GlobalOptions, verb: []const u8, args: []const []const u8, settings: output.Settings, stdout: *std.Io.Writer) !?errors.Failure {
    const scope = try tracking.Id.parse(global.scope);
    if (std.mem.eql(u8, verb, "list")) {
        const options = try parseCatalogQueryOptions(args, false);
        return writeCatalogQuery(allocator, stdout, settings, "caudex.exercise.list", try adapter.listExercises(allocator, .{ .host_scope_key = scope, .max_results = options.limit, .include_archived = options.include_archived }));
    }
    if (std.mem.eql(u8, verb, "search")) {
        const options = try parseCatalogQueryOptions(args, true);
        return writeCatalogQuery(allocator, stdout, settings, "caudex.exercise.search", try adapter.searchExercises(allocator, .{ .host_scope_key = scope, .text = options.reference.?, .max_results = options.limit, .include_archived = options.include_archived }));
    }
    if (!std.mem.eql(u8, verb, "create") and !std.mem.eql(u8, verb, "edit") and !std.mem.eql(u8, verb, "show") and !std.mem.eql(u8, verb, "archive") and !std.mem.eql(u8, verb, "restore")) return error.InvalidArguments;
    const options = try parseCatalogMutationOptions(args, verb);
    if (std.mem.eql(u8, verb, "show")) {
        const managed = switch (try use_cases.resolveManagedExercise(adapter, allocator, scope, options.reference.?)) {
            .found => |value| value,
            .not_found => return errors.managedExerciseNotFound(),
            .ambiguous => |values| return errors.ambiguousExercise(try managedExerciseIds(allocator, values)),
        };
        try writeManagedExercises(allocator, stdout, settings, "caudex.exercise.show", null, null, &.{managed});
        return null;
    }
    const occurred_at = options.occurred_at orelse try currentTimestamp(io, allocator);
    const metadata: tracking.CommandMetadata = .{ .command_id = try tracking.Id.parse(options.command_id orelse try generateId(io, allocator, "command")), .occurred_at = try tracking.Timestamp.parse(occurred_at) };
    const result: tracking.CatalogCommandResult = if (std.mem.eql(u8, verb, "create"))
        try adapter.createExercise(allocator, .{ .metadata = metadata, .host_scope_key = scope, .exercise = .{ .id = options.reference.?, .name = options.name, .aliases = options.aliases[0..options.alias_count], .equipmentIds = options.equipment[0..options.equipment_count], .movementTags = options.movements[0..options.movement_count], .unilateral = options.unilateral } })
    else blk: {
        const current = switch (try use_cases.resolveManagedExercise(adapter, allocator, scope, options.reference.?)) {
            .found => |value| value,
            .not_found => return errors.managedExerciseNotFound(),
            .ambiguous => |values| return errors.ambiguousExercise(try managedExerciseIds(allocator, values)),
        };
        if (std.mem.eql(u8, verb, "edit")) {
            var exercise = current.exercise;
            if (options.name) |name| exercise.name = name;
            if (options.alias_count != 0) exercise.aliases = options.aliases[0..options.alias_count];
            if (options.equipment_count != 0) exercise.equipmentIds = options.equipment[0..options.equipment_count];
            if (options.movement_count != 0) exercise.movementTags = options.movements[0..options.movement_count];
            if (options.unilateral) |value| exercise.unilateral = value;
            break :blk try adapter.editExercise(allocator, .{ .metadata = metadata, .host_scope_key = scope, .exercise = exercise, .expected_revision = current.revision });
        }
        const change: tracking.ChangeExerciseAvailabilityCommand = .{ .metadata = metadata, .host_scope_key = scope, .exercise_id = .{ .bytes = current.exercise.id }, .expected_revision = current.revision };
        break :blk if (std.mem.eql(u8, verb, "archive")) try adapter.archiveExercise(allocator, change) else try adapter.restoreExercise(allocator, change);
    };
    switch (result) {
        .accepted => |accepted| {
            try writeManagedExercises(allocator, stdout, settings, if (std.mem.eql(u8, verb, "create")) "caudex.exercise.created" else if (std.mem.eql(u8, verb, "edit")) "caudex.exercise.edited" else if (std.mem.eql(u8, verb, "archive")) "caudex.exercise.archived" else "caudex.exercise.restored", accepted.command_id.bytes, @tagName(accepted.disposition), &.{accepted.exercise});
            return null;
        },
        .rejected => |rejected| return errors.fromTrackingIssue(rejected.issues[0]),
    }
}

fn writeCatalogQuery(allocator: std.mem.Allocator, stdout: *std.Io.Writer, settings: output.Settings, kind: []const u8, result: tracking.SearchExercisesResult) !?errors.Failure {
    return switch (result) {
        .found => |values| blk: {
            try writeManagedExercises(allocator, stdout, settings, kind, null, null, values);
            break :blk null;
        },
        .rejected => |issue| errors.fromTrackingIssue(issue),
    };
}

fn writeManagedExercises(allocator: std.mem.Allocator, stdout: *std.Io.Writer, settings: output.Settings, kind: []const u8, command_id: ?[]const u8, disposition: ?[]const u8, values: []const tracking.ManagedExercise) !void {
    const infos = try allocator.alloc(output.ExerciseInfo, values.len);
    for (values, 0..) |value, index| infos[index] = .{ .id = value.exercise.id, .name = value.exercise.name, .aliases = value.exercise.aliases, .equipmentIds = value.exercise.equipmentIds, .movementTags = value.exercise.movementTags, .unilateral = value.exercise.unilateral, .knowledge = value.exercise.knowledge, .revision = value.revision, .availability = @tagName(value.availability), .updatedAt = value.updated_at.bytes };
    try output.writeExercises(stdout, settings, kind, command_id, disposition, infos);
}

fn managedExerciseIds(allocator: std.mem.Allocator, values: []const tracking.ManagedExercise) ![]const []const u8 {
    const ids = try allocator.alloc([]const u8, values.len);
    for (values, 0..) |value, index| ids[index] = value.exercise.id;
    return ids;
}

fn parseCatalogQueryOptions(args: []const []const u8, require_reference: bool) !CatalogOptions {
    var options = CatalogOptions{};
    var index: usize = 0;
    if (require_reference) {
        if (args.len == 0 or std.mem.startsWith(u8, args[0], "--")) return error.InvalidArguments;
        options.reference = args[0];
        index = 1;
    }
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--include-archived")) {
            options.include_archived = true;
            continue;
        }
        if (!std.mem.eql(u8, args[index], "--limit") or index + 1 >= args.len) return error.InvalidArguments;
        index += 1;
        options.limit = std.fmt.parseInt(u16, args[index], 10) catch return error.InvalidArguments;
    }
    if (options.limit == 0 or options.limit > 100) return error.InvalidArguments;
    return options;
}

fn parseCatalogMutationOptions(args: []const []const u8, verb: []const u8) !CatalogOptions {
    if (args.len == 0 or std.mem.startsWith(u8, args[0], "--")) return error.InvalidArguments;
    var options = CatalogOptions{ .reference = args[0] };
    if (std.mem.eql(u8, verb, "show") and args.len != 1) return error.InvalidArguments;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const token = args[index];
        if (std.mem.eql(u8, token, "--unilateral") or std.mem.eql(u8, token, "--bilateral")) {
            if (options.unilateral != null) return error.InvalidArguments;
            options.unilateral = std.mem.eql(u8, token, "--unilateral");
            continue;
        }
        index += 1;
        if (index >= args.len or args[index].len == 0) return error.InvalidArguments;
        if (std.mem.eql(u8, token, "--name")) {
            if (options.name != null) return error.InvalidArguments;
            options.name = args[index];
        } else if (std.mem.eql(u8, token, "--alias")) {
            if (options.alias_count == options.aliases.len) return error.InvalidArguments;
            options.aliases[options.alias_count] = args[index];
            options.alias_count += 1;
        } else if (std.mem.eql(u8, token, "--equipment")) {
            if (options.equipment_count == options.equipment.len) return error.InvalidArguments;
            options.equipment[options.equipment_count] = args[index];
            options.equipment_count += 1;
        } else if (std.mem.eql(u8, token, "--movement")) {
            if (options.movement_count == options.movements.len) return error.InvalidArguments;
            options.movements[options.movement_count] = args[index];
            options.movement_count += 1;
        } else if (std.mem.eql(u8, token, "--command-id")) {
            if (options.command_id != null) return error.InvalidArguments;
            options.command_id = args[index];
        } else if (std.mem.eql(u8, token, "--occurred-at")) {
            if (options.occurred_at != null) return error.InvalidArguments;
            options.occurred_at = args[index];
        } else return error.InvalidArguments;
    }
    if (std.mem.eql(u8, verb, "create") and options.name == null) return error.InvalidArguments;
    if ((std.mem.eql(u8, verb, "archive") or std.mem.eql(u8, verb, "restore")) and (options.name != null or options.alias_count != 0 or options.equipment_count != 0 or options.movement_count != 0 or options.unilateral != null)) return error.InvalidArguments;
    return options;
}

fn addExercise(
    io: std.Io,
    allocator: std.mem.Allocator,
    adapter: *sqlite.Adapter,
    global: GlobalOptions,
    args: []const []const u8,
    settings: output.Settings,
    stdout: *std.Io.Writer,
) !?errors.Failure {
    const options = try parseAddExerciseOptions(args);
    const scope = try trackingScope(global);
    const explicit_id: ?tracking.Id = if (options.workout_id) |id|
        try tracking.Id.parse(id)
    else
        null;
    const workout = switch (try use_cases.resolveWorkout(
        adapter,
        allocator,
        scope,
        explicit_id,
    )) {
        .found => |found| found,
        .not_found => return errors.workoutNotFound(),
        .ambiguous => |workouts| {
            const ids = try workoutIds(allocator, workouts);
            return errors.ambiguousWorkout(ids);
        },
    };
    const occurred_at = options.occurred_at orelse
        try currentTimestamp(io, allocator);
    const exercise = switch (try use_cases.resolveExercise(
        adapter,
        allocator,
        scope.host_scope_key.bytes,
        occurred_at,
        options.reference,
    )) {
        .found => |found| found,
        .not_found => return errors.exerciseNotFound(),
        .ambiguous => |exercises| {
            const ids = try allocator.alloc([]const u8, exercises.len);
            for (exercises, 0..) |candidate, index| ids[index] = candidate.id;
            return errors.ambiguousExercise(ids);
        },
    };
    const command_id = options.command_id orelse
        try generateId(io, allocator, "command");
    const membership_id = options.membership_id orelse
        try generateId(io, allocator, "membership");
    const anchor: tracking.ExerciseAnchor = if (options.before) |id|
        .{ .before = try tracking.Id.parse(id) }
    else if (options.after) |id|
        .{ .after = try tracking.Id.parse(id) }
    else
        .end;
    const result = try adapter.addExercise(allocator, .{
        .metadata = .{
            .command_id = try tracking.Id.parse(command_id),
            .occurred_at = try tracking.Timestamp.parse(occurred_at),
        },
        .scope = scope,
        .workout_id = workout.id,
        .expected_revision = workout.revision,
        .membership_id = try tracking.Id.parse(membership_id),
        .exercise_id = try tracking.Id.parse(exercise.id),
        .anchor = anchor,
    });
    switch (result) {
        .accepted => |accepted| {
            try writeWorkoutState(
                allocator,
                stdout,
                settings,
                "caudex.workout.exercise_added",
                accepted.command_id.bytes,
                @tagName(accepted.disposition),
                accepted.workout,
            );
            return null;
        },
        .rejected => |rejected| {
            if (rejected.issues.len == 0) return error.InvalidTrackingResult;
            return errors.fromTrackingIssue(rejected.issues[0]);
        },
    }
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
        } else if (std.mem.eql(u8, args[index], "--quiet")) {
            options.quiet = true;
        } else {
            return error.InvalidArguments;
        }
        index += 1;
    }
    options.command_index = index;
    return options;
}

/// Small, allocation-free parser probe used by the bounded fuzz harness.
/// It intentionally returns only the stable fact the harness needs, keeping
/// CLI option representation private to the reference client.
pub fn fuzzParseGlobalOptions(args: []const []const u8) !usize {
    return (try parseGlobalOptions(args)).command_index;
}

const SetAction = tui_actions.SetAction;
const EndAction = tui_actions.WorkoutEndAction;

fn endWorkout(
    io: std.Io,
    allocator: std.mem.Allocator,
    adapter: *sqlite.Adapter,
    global: GlobalOptions,
    args: []const []const u8,
    settings: output.Settings,
    stdout: *std.Io.Writer,
    action: EndAction,
) !?errors.Failure {
    const options = try parseEndOptions(args, action);
    if (action == .cancel and !options.yes) {
        if (!(std.Io.File.stdin().isTty(io) catch false)) return errors.confirmationRequired();
        try stdout.writeAll("Cancel this workout? [y/N] ");
        try stdout.flush();
        var input_buffer: [16]u8 = undefined;
        var stdin_reader = std.Io.File.stdin().reader(io, &input_buffer);
        const answer = (try stdin_reader.interface.takeDelimiter('\n')) orelse return errors.cancelledByUser();
        if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, answer, " \r\t"), "y") and
            !std.ascii.eqlIgnoreCase(std.mem.trim(u8, answer, " \r\t"), "yes"))
            return errors.cancelledByUser();
    }
    const scope = try trackingScope(global);
    const workout = switch (try use_cases.resolveWorkout(adapter, allocator, scope, if (options.workout_id) |id| try tracking.Id.parse(id) else null)) {
        .found => |value| value,
        .not_found => return errors.workoutNotFound(),
        .ambiguous => |values| return errors.ambiguousWorkout(try workoutIds(allocator, values)),
    };
    const occurred_at = options.occurred_at orelse try currentTimestamp(io, allocator);
    const metadata: tracking.CommandMetadata = .{
        .command_id = try tracking.Id.parse(options.command_id orelse try generateId(io, allocator, "command")),
        .occurred_at = try tracking.Timestamp.parse(occurred_at),
    };
    const result = switch (action) {
        .finish => try adapter.completeWorkout(allocator, .{
            .metadata = metadata,
            .scope = scope,
            .workout_id = workout.id,
            .expected_revision = workout.revision,
            .completed_at = metadata.occurred_at,
        }),
        .cancel => try adapter.cancelWorkout(allocator, .{
            .metadata = metadata,
            .scope = scope,
            .workout_id = workout.id,
            .expected_revision = workout.revision,
            .cancelled_at = metadata.occurred_at,
        }),
    };
    switch (result) {
        .accepted => |accepted| {
            try writeWorkoutState(allocator, stdout, settings, if (action == .finish) "caudex.workout.finished" else "caudex.workout.cancelled", accepted.command_id.bytes, @tagName(accepted.disposition), accepted.workout);
            return null;
        },
        .rejected => |rejected| return errors.fromTrackingIssue(rejected.issues[0]),
    }
}

fn parseEndOptions(args: []const []const u8, action: EndAction) !EndOptions {
    var options = EndOptions{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--yes")) {
            if (action != .cancel or options.yes) return error.InvalidArguments;
            options.yes = true;
            continue;
        }
        const target: *?[]const u8 = if (std.mem.eql(u8, args[index], "--workout")) &options.workout_id else if (std.mem.eql(u8, args[index], "--command-id")) &options.command_id else if (std.mem.eql(u8, args[index], "--occurred-at")) &options.occurred_at else return error.InvalidArguments;
        index += 1;
        if (index >= args.len or target.* != null or args[index].len == 0) return error.InvalidArguments;
        target.* = args[index];
    }
    return options;
}

fn changeSet(
    io: std.Io,
    allocator: std.mem.Allocator,
    adapter: *sqlite.Adapter,
    global: GlobalOptions,
    args: []const []const u8,
    settings: output.Settings,
    stdout: *std.Io.Writer,
    action: SetAction,
) !?errors.Failure {
    var options = try parseSetOptions(args, action);
    const scope = try trackingScope(global);
    var workout = switch (try use_cases.resolveWorkout(adapter, allocator, scope, if (options.workout_id) |id| try tracking.Id.parse(id) else null)) {
        .found => |value| value,
        .not_found => return errors.workoutNotFound(),
        .ambiguous => |values| return errors.ambiguousWorkout(try workoutIds(allocator, values)),
    };
    const membership = resolveMembership(workout, options.exercise_id) orelse
        return errors.membershipNotFound();
    const occurred_at = options.occurred_at orelse try currentTimestamp(io, allocator);
    var set_id = options.set_id;
    if (action == .log and (set_id == null or !hasSet(membership.sets, set_id.?))) {
        const generated = set_id orelse try generateId(io, allocator, "set");
        const add_result = try adapter.addSet(allocator, .{
            .metadata = .{ .command_id = try tracking.Id.parse(try generateId(io, allocator, "command")), .occurred_at = try tracking.Timestamp.parse(occurred_at) },
            .scope = scope,
            .workout_id = workout.id,
            .expected_revision = workout.revision,
            .membership_id = membership.id,
            .set_id = try tracking.Id.parse(generated),
            .kind = try tracking.Id.parse("working"),
            .anchor = .end,
        });
        workout = switch (add_result) {
            .accepted => |accepted| accepted.workout,
            .rejected => |rejected| return errors.fromTrackingIssue(rejected.issues[0]),
        };
        set_id = generated;
    }
    const selected_set = set_id orelse inferSet(membership.sets, action) orelse
        return errors.setNotFound();
    const command_id = options.command_id orelse try generateId(io, allocator, "command");
    const metadata: tracking.CommandMetadata = .{
        .command_id = try tracking.Id.parse(command_id),
        .occurred_at = try tracking.Timestamp.parse(occurred_at),
    };
    const result = switch (action) {
        .log => try adapter.logSet(allocator, .{
            .metadata = metadata,
            .scope = scope,
            .workout_id = workout.id,
            .expected_revision = workout.revision,
            .membership_id = membership.id,
            .set_id = try tracking.Id.parse(selected_set),
            .actual_metrics = options.metrics[0..options.metric_count],
            .completed_at = metadata.occurred_at,
        }),
        .skip => try adapter.skipSet(allocator, .{
            .metadata = metadata,
            .scope = scope,
            .workout_id = workout.id,
            .expected_revision = workout.revision,
            .membership_id = membership.id,
            .set_id = try tracking.Id.parse(selected_set),
            .skipped_at = metadata.occurred_at,
        }),
        .reopen => try adapter.reopenSet(allocator, .{
            .metadata = metadata,
            .scope = scope,
            .workout_id = workout.id,
            .expected_revision = workout.revision,
            .membership_id = membership.id,
            .set_id = try tracking.Id.parse(selected_set),
        }),
    };
    switch (result) {
        .accepted => |accepted| {
            try writeWorkoutState(allocator, stdout, settings, switch (action) {
                .log => "caudex.set.logged",
                .skip => "caudex.set.skipped",
                .reopen => "caudex.set.reopened",
            }, accepted.command_id.bytes, @tagName(accepted.disposition), accepted.workout);
            return null;
        },
        .rejected => |rejected| return errors.fromTrackingIssue(rejected.issues[0]),
    }
}

fn hasSet(sets: []const tracking.TrackedSet, id: []const u8) bool {
    for (sets) |set| if (std.mem.eql(u8, set.id.bytes, id)) return true;
    return false;
}

fn resolveMembership(workout: tracking.Workout, reference: ?[]const u8) ?tracking.ExerciseMembership {
    if (reference) |value| {
        var match: ?tracking.ExerciseMembership = null;
        for (workout.exercises) |membership| {
            if (std.mem.eql(u8, membership.id.bytes, value)) return membership;
            if (std.mem.eql(u8, membership.exercise_id.bytes, value)) {
                if (match != null) return null;
                match = membership;
            }
        }
        return match;
    }
    return if (workout.exercises.len == 1) workout.exercises[0] else null;
}

fn inferSet(sets: []const tracking.TrackedSet, action: SetAction) ?[]const u8 {
    var found: ?[]const u8 = null;
    for (sets) |set| {
        const eligible = switch (action) {
            .log, .skip => set.status == .open,
            .reopen => set.status != .open,
        };
        if (eligible) {
            if (found != null) return null;
            found = set.id.bytes;
        }
    }
    return found;
}

fn parseSetOptions(args: []const []const u8, action: SetAction) !SetOptions {
    var options = SetOptions{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const token = args[index];
        if (std.mem.startsWith(u8, token, "--")) {
            if (std.mem.eql(u8, token, "--workout") or std.mem.eql(u8, token, "--exercise") or
                std.mem.eql(u8, token, "--set") or std.mem.eql(u8, token, "--command-id") or
                std.mem.eql(u8, token, "--occurred-at"))
            {
                const target: *?[]const u8 = if (std.mem.eql(u8, token, "--workout")) &options.workout_id else if (std.mem.eql(u8, token, "--exercise")) &options.exercise_id else if (std.mem.eql(u8, token, "--set")) &options.set_id else if (std.mem.eql(u8, token, "--command-id")) &options.command_id else &options.occurred_at;
                index += 1;
                if (index >= args.len or target.* != null or args[index].len == 0) return error.InvalidArguments;
                target.* = args[index];
                continue;
            }
            if (action != .log) return error.InvalidArguments;
            const code: []const u8 = if (std.mem.eql(u8, token, "--reps")) tracking.metric_codes.repetitions else if (std.mem.eql(u8, token, "--rir")) tracking.metric_codes.rir else if (std.mem.eql(u8, token, "--rpe")) tracking.metric_codes.rpe else if (std.mem.eql(u8, token, "--load")) tracking.metric_codes.load else if (std.mem.eql(u8, token, "--duration")) tracking.metric_codes.duration else return error.InvalidArguments;
            index += 1;
            if (index >= args.len) return error.InvalidArguments;
            const value = try tracking.Decimal.parse(args[index]);
            const unit = if (std.mem.eql(u8, code, tracking.metric_codes.repetitions)) .count else if (std.mem.eql(u8, code, tracking.metric_codes.rir)) .rir else if (std.mem.eql(u8, code, tracking.metric_codes.rpe)) .rpe else blk: {
                index += 1;
                if (index >= args.len) return error.InvalidArguments;
                break :blk try caudex.primitives.Unit.parse(args[index]);
            };
            try appendMetric(&options, code, value, unit);
        } else {
            if (action != .log) return error.InvalidArguments;
            const parsed = try parseMetricShorthand(token);
            try appendMetric(&options, parsed.code, parsed.value, parsed.unit);
        }
    }
    if (action == .log and options.metric_count == 0) return error.InvalidArguments;
    if (action == .reopen and options.set_id == null) return error.InvalidArguments;
    return options;
}

const ParsedMetric = struct { code: []const u8, value: tracking.Decimal, unit: caudex.primitives.Unit };

fn parseMetricShorthand(token: []const u8) !ParsedMetric {
    var text = token;
    if (text.len > 0 and text[0] == '@') text = text[1..];
    const suffixes = [_]struct { suffix: []const u8, code: []const u8, unit: caudex.primitives.Unit }{
        .{ .suffix = "rir", .code = tracking.metric_codes.rir, .unit = .rir },
        .{ .suffix = "rpe", .code = tracking.metric_codes.rpe, .unit = .rpe },
        .{ .suffix = "kg", .code = tracking.metric_codes.load, .unit = .kg },
        .{ .suffix = "lb", .code = tracking.metric_codes.load, .unit = .lb },
        .{ .suffix = "min", .code = tracking.metric_codes.duration, .unit = .min },
        .{ .suffix = "s", .code = tracking.metric_codes.duration, .unit = .s },
        .{ .suffix = "r", .code = tracking.metric_codes.repetitions, .unit = .count },
    };
    for (suffixes) |entry| if (std.mem.endsWith(u8, text, entry.suffix)) {
        const number = text[0 .. text.len - entry.suffix.len];
        return .{ .code = entry.code, .value = try tracking.Decimal.parse(number), .unit = entry.unit };
    };
    return error.InvalidArguments;
}

fn appendMetric(options: *SetOptions, code: []const u8, value: tracking.Decimal, unit: caudex.primitives.Unit) !void {
    for (options.metrics[0..options.metric_count]) |metric|
        if (std.mem.eql(u8, metric.code.bytes, code)) return error.InvalidArguments;
    if (options.metric_count == options.metrics.len) return error.InvalidArguments;
    options.metrics[options.metric_count] = .{ .code = try tracking.Id.parse(code), .value = .{ .value = value, .unit = unit } };
    options.metric_count += 1;
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
    if (args.len != 0 and
        (args.len != 2 or !std.mem.eql(u8, args[0], "--workout")))
        return error.InvalidArguments;
    const scope = tracking.Scope{
        .host_scope_key = try tracking.Id.parse(global.scope),
        .athlete_id = if (global.athlete) |athlete|
            try tracking.Id.parse(athlete)
        else
            null,
    };
    const explicit_id: ?tracking.Id = if (args.len == 2)
        try tracking.Id.parse(args[1])
    else
        null;
    switch (try use_cases.resolveWorkout(adapter, allocator, scope, explicit_id)) {
        .found => |workout| {
            try writeWorkoutState(
                allocator,
                stdout,
                settings,
                "caudex.workout.show",
                null,
                null,
                workout,
            );
            return null;
        },
        .not_found => return errors.workoutNotFound(),
        .ambiguous => |workouts| {
            const ids = try allocator.alloc([]const u8, workouts.len);
            for (workouts, 0..) |workout, index| ids[index] = workout.id.bytes;
            return errors.ambiguousWorkout(ids);
        },
    }
}

fn writeWorkoutState(
    allocator: std.mem.Allocator,
    stdout: *std.Io.Writer,
    settings: output.Settings,
    document_kind: []const u8,
    command_id: ?[]const u8,
    disposition: ?[]const u8,
    workout: tracking.Workout,
) !void {
    const exercises = try allocator.alloc(
        output.WorkoutExerciseInfo,
        workout.exercises.len,
    );
    for (workout.exercises, 0..) |exercise, index| {
        exercises[index] = .{
            .membershipId = exercise.id.bytes,
            .exerciseId = exercise.exercise_id.bytes,
            .setCount = exercise.sets.len,
        };
    }
    try output.writeWorkout(stdout, settings, .{
        .document_kind = document_kind,
        .command_id = command_id,
        .disposition = disposition,
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
        .exercises = exercises,
    });
}

fn workoutIds(
    allocator: std.mem.Allocator,
    workouts: []const tracking.Workout,
) ![]const []const u8 {
    const ids = try allocator.alloc([]const u8, workouts.len);
    for (workouts, 0..) |workout, index| ids[index] = workout.id.bytes;
    return ids;
}

fn trackingScope(global: GlobalOptions) !tracking.Scope {
    return .{
        .host_scope_key = try tracking.Id.parse(global.scope),
        .athlete_id = if (global.athlete) |athlete|
            try tracking.Id.parse(athlete)
        else
            null,
    };
}

fn parseAddExerciseOptions(args: []const []const u8) !AddExerciseOptions {
    if (args.len == 0 or args[0].len == 0 or
        std.mem.startsWith(u8, args[0], "--"))
        return error.InvalidArguments;
    var options = AddExerciseOptions{ .reference = args[0] };
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const target: *?[]const u8 = if (std.mem.eql(u8, args[index], "--workout"))
            &options.workout_id
        else if (std.mem.eql(u8, args[index], "--command-id"))
            &options.command_id
        else if (std.mem.eql(u8, args[index], "--membership-id"))
            &options.membership_id
        else if (std.mem.eql(u8, args[index], "--occurred-at"))
            &options.occurred_at
        else if (std.mem.eql(u8, args[index], "--before"))
            &options.before
        else if (std.mem.eql(u8, args[index], "--after"))
            &options.after
        else
            return error.InvalidArguments;
        index += 1;
        if (index >= args.len or args[index].len == 0 or target.* != null)
            return error.InvalidArguments;
        target.* = args[index];
    }
    if (options.before != null and options.after != null)
        return error.InvalidArguments;
    return options;
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

fn resolveConfigPath(allocator: std.mem.Allocator, environment: PathEnvironment, platform: Platform) ![:0]u8 {
    return switch (platform) {
        .macos => if (nonEmpty(environment.home)) |home| std.fs.path.joinZ(allocator, &.{ home, "Library", "Application Support", "Caudex", "config" }) else error.DataDirectoryUnavailable,
        .windows => if (nonEmpty(environment.local_app_data)) |data| std.fs.path.joinZ(allocator, &.{ data, "Caudex", "config" }) else error.DataDirectoryUnavailable,
        .unix => if (nonEmpty(environment.xdg_data_home)) |data| std.fs.path.joinZ(allocator, &.{ data, "caudex", "config" }) else if (nonEmpty(environment.home)) |home| std.fs.path.joinZ(allocator, &.{ home, ".local", "share", "caudex", "config" }) else error.DataDirectoryUnavailable,
    };
}

fn readConfig(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4096));
}

fn writeConfigAtomically(io: std.Io, path: []const u8, value: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return error.DataDirectoryUnavailable;
    try std.Io.Dir.cwd().createDirPath(io, parent);
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .replace = true, .permissions = privateFilePermissions() });
    defer atomic.deinit(io);
    var buffer: [512]u8 = undefined;
    var writer = atomic.file.writer(io, &buffer);
    try writer.interface.writeAll(value);
    try writer.interface.flush();
    try atomic.replace(io);
}

fn configValue(config: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, config, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, key) or line.len <= key.len or line[key.len] != '=') continue;
        return line[key.len + 1 ..];
    }
    return null;
}

fn ensureDatabaseDirectory(io: std.Io, path: []const u8) !void {
    if (std.mem.eql(u8, path, ":memory:")) return;
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0) return;
    _ = try std.Io.Dir.cwd().createDirPathStatus(io, parent, privateDirectoryPermissions());
}

fn ensurePrivateDirectory(io: std.Io, path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0) return;
    _ = try std.Io.Dir.cwd().createDirPathStatus(io, parent, privateDirectoryPermissions());
}

fn rejectSymlink(io: std.Io, path: []const u8) !void {
    if (std.mem.eql(u8, path, ":memory:")) return;
    const stat = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    if (stat.kind == .sym_link) return error.Symlink;
}

fn setPrivateFilePermissions(io: std.Io, path: []const u8) !void {
    if (std.mem.eql(u8, path, ":memory:") or builtin.os.tag == .windows) return;
    try std.Io.Dir.cwd().setFilePermissions(io, path, privateFilePermissions(), .{ .follow_symlinks = false });
}

fn privateFilePermissions() std.Io.File.Permissions {
    if (builtin.os.tag == .windows) return .default_file;
    return std.Io.File.Permissions.fromMode(0o600);
}

fn privateDirectoryPermissions() std.Io.Dir.Permissions {
    if (builtin.os.tag == .windows) return .default_dir;
    return std.Io.Dir.Permissions.fromMode(0o700);
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
    try setPrivateFilePermissions(std.testing.io, path);
    if (builtin.os.tag != .windows) {
        const stat = try std.Io.Dir.cwd().statFile(std.testing.io, path, .{ .follow_symlinks = false });
        try std.testing.expectEqual(@as(std.posix.mode_t, 0o600), stat.permissions.toMode() & 0o777);
    }
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

test "set metric parser accepts exact long and shorthand forms" {
    const long = try parseSetOptions(&.{
        "--reps",     "8",  "--load", "70.5", "kg", "--rir", "2",
        "--duration", "45", "s",
    }, .log);
    try std.testing.expectEqual(@as(usize, 4), long.metric_count);
    try std.testing.expectEqual(@as(i64, 705), long.metrics[1].value.value.mantissa);
    try std.testing.expectEqual(@as(u8, 1), long.metrics[1].value.value.scale);
    try std.testing.expectEqual(caudex.primitives.Unit.kg, long.metrics[1].value.unit);

    const shorthand = try parseSetOptions(&.{ "70kg", "8r", "@2rir" }, .log);
    try std.testing.expectEqual(@as(usize, 3), shorthand.metric_count);
    try std.testing.expectEqualStrings("load", shorthand.metrics[0].code.bytes);
    try std.testing.expectEqualStrings("repetitions", shorthand.metrics[1].code.bytes);
}

test "set metric parser rejects invalid ambiguous and conflicting input" {
    try std.testing.expectError(error.InvalidArguments, parseSetOptions(&.{"70"}, .log));
    try std.testing.expectError(error.InvalidArguments, parseSetOptions(&.{ "8r", "--reps", "8" }, .log));
    try std.testing.expectError(error.UnknownUnit, parseSetOptions(&.{ "--load", "70", "stone" }, .log));
    try std.testing.expectError(error.InvalidArguments, parseSetOptions(&.{ "--reps", "8" }, .skip));
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
                std.mem.eql(u8, name, "output.zig") or
                std.mem.eql(u8, name, "use_cases.zig") or
                std.mem.eql(u8, name, "commands.zig") or
                std.mem.eql(u8, name, "tui/actions.zig") or
                std.mem.eql(u8, name, "security.zig"),
        );

        import_count += 1;
        remainder = tail[name_end + 1 ..];
    }

    try std.testing.expectEqual(@as(usize, 12), import_count);
}

test "line client does not import libvaxis" {
    const source = @embedFile("main.zig");
    const needle = "@im" ++ "port(\"vaxis\")";
    try std.testing.expect(std.mem.indexOf(u8, source, needle) == null);
}

test "client sources contain no SQL or private path imports" {
    const sources = [_][]const u8{
        @embedFile("main.zig"),
        @embedFile("errors.zig"),
        @embedFile("output.zig"),
        @embedFile("commands.zig"),
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
