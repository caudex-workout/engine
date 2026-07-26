const std = @import("std");
const caudex = @import("caudex");
const persistence = @import("caudex_persistence");
const sqlite = @import("caudex_sqlite");

const version = "0.1.0";

const help_text =
    \\Caudex Workout Engine reference client
    \\
    \\Usage:
    \\  caudex --help
    \\  caudex version
    \\
;

pub fn main(init: std.process.Init) !void {
    comptime {
        _ = caudex.engine;
        _ = persistence.contract_version;
        _ = sqlite.adapter_version;
    }

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (args.len == 1 or
        (args.len == 2 and
            (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "help"))))
    {
        try stdout.writeAll(help_text);
        try stdout.flush();
        return;
    }

    if (args.len == 2 and std.mem.eql(u8, args[1], "version")) {
        try stdout.print("caudex {s}\n", .{version});
        try stdout.flush();
        return;
    }

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try stderr.print("unknown command; run '{s} --help'\n", .{args[0]});
    try stderr.flush();
    std.process.exit(2);
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
                std.mem.eql(u8, name, "caudex") or
                std.mem.eql(u8, name, "caudex_persistence") or
                std.mem.eql(u8, name, "caudex_sqlite"),
        );

        import_count += 1;
        remainder = tail[name_end + 1 ..];
    }

    try std.testing.expectEqual(@as(usize, 4), import_count);
}

test "client source contains no private path imports" {
    const source = @embedFile("main.zig");
    const forbidden_paths = [_][]const u8{
        ".." ++ "/",
        "core/" ++ "src/",
        "adap" ++ "ters/",
        "migra" ++ "tions/",
    };

    for (forbidden_paths) |path| {
        try std.testing.expect(std.mem.indexOf(u8, source, path) == null);
    }
}
