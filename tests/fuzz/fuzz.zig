const std = @import("std");
const drivers = @import("drivers.zig");

fn run(comptime driver: fn (std.mem.Allocator, []const u8) anyerror!void, smith: *std.testing.Smith) !void {
    var bytes: [drivers.max_input_bytes]u8 = undefined;
    const length: usize = smith.valueRangeAtMost(u32, 0, @intCast(drivers.max_input_bytes));
    smith.bytes(bytes[0..length]);
    try driver(std.testing.allocator, bytes[0..length]);
}

test "fuzz json request boundary" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *std.testing.Smith) !void {
            try run(drivers.jsonRequest, smith);
        }
    }.testOne, .{});
}

test "fuzz decimal boundary" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *std.testing.Smith) !void {
            try run(drivers.decimal, smith);
        }
    }.testOne, .{});
}

test "fuzz C ABI boundary" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *std.testing.Smith) !void {
            try run(drivers.cAbi, smith);
        }
    }.testOne, .{});
}

test "fuzz CLI argument boundary" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *std.testing.Smith) !void {
            try run(drivers.cliArgs, smith);
        }
    }.testOne, .{});
}

test "fuzz SQLite decoding boundary" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *std.testing.Smith) !void {
            try run(drivers.sqliteDecode, smith);
        }
    }.testOne, .{});
}

test "fuzz methodology configuration boundary" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, smith: *std.testing.Smith) !void {
            try run(drivers.methodologyConfig, smith);
        }
    }.testOne, .{});
}
