const std = @import("std");
const caudex = @import("caudex");
const c_api = @import("caudex_c_api");
const cli = @import("caudex_cli");
const sqlite = @import("caudex_sqlite");

pub const max_input_bytes: usize = 64 * 1024;
pub const max_args: usize = 32;
pub const max_arg_bytes: usize = 256;

fn bounded(input: []const u8) []const u8 {
    return input[0..@min(input.len, max_input_bytes)];
}

pub fn jsonRequest(allocator: std.mem.Allocator, input: []const u8) !void {
    const parsed = caudex.canonical_json.decodeRecommendationRequest(
        allocator,
        bounded(input),
        .{ .max_input_bytes = max_input_bytes, .max_collection_items = 64, .max_string_bytes = 4096 },
    ) catch return;
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.schemaVersion);
    if (parsed.value.methodology.id.len != 0) {
        try std.testing.expect(parsed.value.methodology.id.len <= 200);
    }
}

pub fn decimal(allocator: std.mem.Allocator, input: []const u8) !void {
    _ = allocator;
    const value = caudex.primitives.Decimal.parse(bounded(input)) catch return;
    var encoded: [64]u8 = undefined;
    const text = try value.format(&encoded);
    const reparsed = try caudex.primitives.Decimal.parse(text);
    try std.testing.expectEqual(value.mantissa, reparsed.mantissa);
    try std.testing.expectEqual(value.scale, reparsed.scale);
    const zero = try caudex.primitives.Decimal.parse("0");
    const sum = caudex.primitives.Decimal.add(value, zero) catch return;
    try std.testing.expectEqual(value.mantissa, sum.mantissa);
    try std.testing.expectEqual(value.scale, sum.scale);
}

pub fn cAbi(allocator: std.mem.Allocator, input: []const u8) !void {
    _ = allocator;
    var runtime: ?*c_api.Runtime = null;
    try std.testing.expectEqual(c_api.Status.ok, c_api.caudex_runtime_create(&runtime));
    defer c_api.caudex_runtime_destroy(runtime);
    const bytes = bounded(input);
    var output: [4096]u8 = undefined;
    var required: usize = 0;
    const request_ptr: ?[*]const u8 = if (bytes.len == 0) null else bytes.ptr;
    const output_ptr: ?[*]u8 = output[0..].ptr;
    _ = c_api.caudex_runtime_execute(runtime, request_ptr, bytes.len, output_ptr, output.len, &required);
    _ = c_api.caudex_runtime_execute(null, request_ptr, bytes.len, output_ptr, output.len, &required);
    _ = c_api.caudex_runtime_execute(runtime, null, 0, null, 0, &required);
    try std.testing.expect(required <= max_input_bytes + 1024);
}

pub fn cliArgs(allocator: std.mem.Allocator, input: []const u8) !void {
    _ = allocator;
    var args: [max_args][]const u8 = undefined;
    var count: usize = 0;
    var start: usize = 0;
    const bytes = bounded(input);
    while (start <= bytes.len and count < max_args) {
        const end = @min(start + max_arg_bytes, bytes.len);
        args[count] = bytes[start..end];
        count += 1;
        if (end == bytes.len) break;
        start = end;
    }
    const command_index = cli.fuzzParseGlobalOptions(args[0..count]) catch return;
    try std.testing.expect(command_index <= count);
}

pub fn sqliteDecode(allocator: std.mem.Allocator, input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    sqlite.fuzzDecodePersistedExercise(arena.allocator(), bounded(input)) catch return;
}

pub fn methodologyConfig(allocator: std.mem.Allocator, input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const config = std.json.parseFromSliceLeaky(
        caudex.double_progression.Config,
        arena.allocator(),
        bounded(input),
        .{ .allocate = .alloc_always, .ignore_unknown_fields = false },
    ) catch return;
    var issues: [16]caudex.canonical.ValidationIssue = undefined;
    var writer = caudex.diagnostics.IssueWriter.init(&issues);
    _ = caudex.double_progression.validateConfig(config, &writer) catch return;
}
