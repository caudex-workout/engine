const std = @import("std");
const drivers = @import("drivers.zig");

const seed_cases = [_][]const u8{
    "",
    "{}",
    "{\"schemaVersion\":1}",
    "-0.000000000000000001",
    "9223372036854775807",
    "{\"schemaVersion\":1,\"methodology\":{\"id\":\"caudex.double-progression\",\"configVersion\":1,\"config\":{}}}",
};

test "bounded fuzz smoke covers every driver" {
    var prng = std.Random.DefaultPrng.init(0xCA0DE5F00D);
    const random = prng.random();
    var input: [drivers.max_input_bytes]u8 = undefined;
    var executed: usize = 0;
    for (0..128) |_| {
        const len = random.uintLessThan(usize, 512);
        random.bytes(input[0..len]);
        try drivers.jsonRequest(std.testing.allocator, input[0..len]);
        try drivers.decimal(std.testing.allocator, input[0..len]);
        try drivers.cAbi(std.testing.allocator, input[0..len]);
        try drivers.cliArgs(std.testing.allocator, input[0..len]);
        try drivers.sqliteDecode(std.testing.allocator, input[0..len]);
        try drivers.methodologyConfig(std.testing.allocator, input[0..len]);
        executed += 6;
    }
    for (seed_cases) |seed| {
        try drivers.jsonRequest(std.testing.allocator, seed);
        try drivers.decimal(std.testing.allocator, seed);
        try drivers.cAbi(std.testing.allocator, seed);
        try drivers.cliArgs(std.testing.allocator, seed);
        try drivers.sqliteDecode(std.testing.allocator, seed);
        try drivers.methodologyConfig(std.testing.allocator, seed);
        executed += 6;
    }
    try std.testing.expectEqual(@as(usize, 804), executed);
}
