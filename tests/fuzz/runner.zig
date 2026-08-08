const std = @import("std");
const drivers = @import("drivers.zig");

const Target = enum { json, decimal, c_abi, cli_args, sqlite, methodology_config };

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    var target: ?Target = null;
    var iterations: usize = 10_000;
    var seed: u64 = 0xCA0DE5F00D;
    var reproduction_path: ?[]const u8 = null;
    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--target=")) {
            target = std.meta.stringToEnum(Target, arg["--target=".len..]) orelse return error.InvalidArgument;
        } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
            iterations = try std.fmt.parseUnsigned(usize, arg["--iterations=".len..], 10);
            if (iterations > 100_000) return error.InvalidArgument;
        } else if (std.mem.startsWith(u8, arg, "--seed=")) {
            seed = try std.fmt.parseUnsigned(u64, arg["--seed=".len..], 0);
        } else if (std.mem.startsWith(u8, arg, "--repro=")) {
            reproduction_path = arg["--repro=".len..];
        } else return error.InvalidArgument;
    }
    const selected = target orelse return error.InvalidArgument;
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    var input: [drivers.max_input_bytes]u8 = undefined;
    const runCase = struct {
        fn call(target_value: Target, bytes: []const u8) !void {
            switch (target_value) {
                .json => try drivers.jsonRequest(std.heap.page_allocator, bytes),
                .decimal => try drivers.decimal(std.heap.page_allocator, bytes),
                .c_abi => try drivers.cAbi(std.heap.page_allocator, bytes),
                .cli_args => try drivers.cliArgs(std.heap.page_allocator, bytes),
                .sqlite => try drivers.sqliteDecode(std.heap.page_allocator, bytes),
                .methodology_config => try drivers.methodologyConfig(std.heap.page_allocator, bytes),
            }
        }
    }.call;
    if (reproduction_path) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(drivers.max_input_bytes));
        runCase(selected, bytes) catch |err| {
            std.debug.print("reproducer failed target={s} path={s} error={s}\n", .{ @tagName(selected), path, @errorName(err) });
            return err;
        };
        return;
    }
    for (0..iterations) |case_index| {
        const length = random.uintLessThan(usize, 1025);
        random.bytes(input[0..length]);
        runCase(selected, input[0..length]) catch |err| {
            try std.Io.Dir.cwd().createDirPath(init.io, ".zig-cache/fuzz");
            const artifact_path = try std.fmt.allocPrint(allocator, ".zig-cache/fuzz/{s}-0x{x}-{d}.input", .{ @tagName(selected), seed, case_index });
            var artifact = try std.Io.Dir.cwd().createFile(init.io, artifact_path, .{ .truncate = true });
            defer artifact.close(init.io);
            try artifact.writeStreamingAll(init.io, input[0..length]);
            std.debug.print("reproducer target={s} seed=0x{x} case={d} path={s}\n", .{ @tagName(selected), seed, case_index, artifact_path });
            return err;
        };
    }
    std.debug.print("fuzz target={s} iterations={d} seed=0x{x}\n", .{ @tagName(selected), iterations, seed });
}
