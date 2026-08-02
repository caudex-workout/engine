const std = @import("std");
const actions = @import("actions.zig");

pub const Metadata = struct { path: []const u8, adapter_version: []const u8, current_schema: u32, minimum_schema: u32, latest_schema: u32, integrity: []const u8 };
pub const Failure = enum { busy, corrupt, incompatible, newer_schema, unavailable };
pub const Switch = union(enum) { idle, validating: []const u8, ready: Metadata, failed: Failure };
pub const Screen = struct { current: Metadata, switching: Switch = .idle, message: ?[]const u8 = null };

pub fn requestSwitch(path: []const u8) Switch {
    return if (path.len == 0) .{ .failed = .unavailable } else .{ .validating = path };
}
pub fn validated(metadata: Metadata) Switch {
    return if (!std.mem.eql(u8, metadata.integrity, "ok")) .{ .failed = .corrupt } else .{ .ready = metadata };
}
pub fn switchAction(state: Switch) ?actions.Action {
    return switch (state) {
        .ready => |metadata| .{ .database = .{ .switch_to = metadata.path } },
        else => null,
    };
}
pub fn backupAction(path: []const u8) ?actions.Action {
    return if (path.len == 0) null else .{ .database = .{ .backup = path } };
}
pub fn restoreAction(path: []const u8, confirmed: bool) ?actions.Action {
    return if (path.len == 0 or !confirmed) null else .{ .database = .{ .restore = path } };
}

pub fn render(screen: Screen, writer: *std.Io.Writer) !void {
    try renderMetadata("Current database", screen.current, writer);
    switch (screen.switching) {
        .idle => {},
        .validating => |path| try writer.print("Validating: {s}\n", .{path}),
        .ready => |metadata| {
            try renderMetadata("Validated database", metadata, writer);
            try writer.writeAll("Press enter to switch.\n");
        },
        .failed => |failure| try writer.print("Database unavailable: {s}. Press r to retry or esc to keep the current database.\n", .{@tagName(failure)}),
    }
    if (screen.message) |message| try writer.print("{s}\n", .{message});
}
fn renderMetadata(label: []const u8, metadata: Metadata, writer: *std.Io.Writer) !void {
    try writer.print("{s}: {s}\nAdapter: {s}\nSchema: {d} (supported {d}-{d})\nIntegrity: {s}\n", .{ label, metadata.path, metadata.adapter_version, metadata.current_schema, metadata.minimum_schema, metadata.latest_schema, metadata.integrity });
}

test "database switch requires validated public metadata" {
    const metadata = Metadata{ .path = "next.sqlite", .adapter_version = "0.1.0", .current_schema = 7, .minimum_schema = 1, .latest_schema = 7, .integrity = "ok" };
    try std.testing.expect(switchAction(requestSwitch("next.sqlite")) == null);
    try std.testing.expect(switchAction(validated(metadata)).?.database == .switch_to);
    try std.testing.expect(backupAction("backup.sqlite") != null);
    try std.testing.expect(restoreAction("backup.sqlite", false) == null);
    var corrupt = metadata;
    corrupt.integrity = "corrupt";
    try std.testing.expect(validated(corrupt) == .failed);
}
test "screen exposes no raw database browser" {
    const source = @embedFile("data_screen.zig");
    const forbidden = [_][]const u8{ "SEL" ++ "ECT ", "sqlite_" ++ "master", "table " ++ "browser" };
    for (forbidden) |needle| try std.testing.expect(std.mem.indexOf(u8, source, needle) == null);
}
