const std = @import("std");

pub const Glyphs = struct { selected: []const u8, up: []const u8, down: []const u8 };
pub fn glyphs(unicode: bool) Glyphs {
    return if (unicode) .{ .selected = "●", .up = "↑", .down = "↓" } else .{ .selected = "*", .up = "up", .down = "down" };
}
pub const Layout = enum { narrow, standard, wide };
pub fn layout(width: u16) Layout {
    return if (width < 40) .narrow else if (width < 100) .standard else .wide;
}
pub const KeyAction = enum { up, down, select, help, cancel, quit };
pub fn keyAction(key: []const u8) ?KeyAction {
    if (std.mem.eql(u8, key, "up") or std.mem.eql(u8, key, "k")) return .up;
    if (std.mem.eql(u8, key, "down") or std.mem.eql(u8, key, "j") or std.mem.eql(u8, key, "tab")) return .down;
    if (std.mem.eql(u8, key, "enter") or std.mem.eql(u8, key, " ")) return .select;
    if (std.mem.eql(u8, key, "?") or std.mem.eql(u8, key, "F1")) return .help;
    if (std.mem.eql(u8, key, "esc")) return .cancel;
    if (std.mem.eql(u8, key, "q")) return .quit;
    return null;
}
pub fn writeStatus(writer: *std.Io.Writer, label: []const u8, color: bool) !void {
    if (color) try writer.writeAll("\x1b[1m");
    try writer.writeAll(label);
    if (color) try writer.writeAll("\x1b[0m");
}

test "Unicode always has an ASCII fallback and widths select stable layouts" {
    try std.testing.expectEqualStrings("●", glyphs(true).selected);
    try std.testing.expectEqualStrings("*", glyphs(false).selected);
    try std.testing.expectEqual(Layout.narrow, layout(20));
    try std.testing.expectEqual(Layout.standard, layout(80));
    try std.testing.expectEqual(Layout.wide, layout(120));
}
test "keyboard-only alternatives cover every action" {
    try std.testing.expectEqual(KeyAction.up, keyAction("k").?);
    try std.testing.expectEqual(KeyAction.down, keyAction("tab").?);
    try std.testing.expectEqual(KeyAction.select, keyAction("enter").?);
    try std.testing.expectEqual(KeyAction.help, keyAction("?").?);
    try std.testing.expectEqual(KeyAction.cancel, keyAction("esc").?);
    try std.testing.expectEqual(KeyAction.quit, keyAction("q").?);
}
test "status meaning remains visible without color" {
    var plain_buffer: [64]u8 = undefined;
    var plain = std.Io.Writer.fixed(&plain_buffer);
    try writeStatus(&plain, "CONFLICT: reload required", false);
    try std.testing.expectEqualStrings("CONFLICT: reload required", plain.buffered());
    var color_buffer: [64]u8 = undefined;
    var color = std.Io.Writer.fixed(&color_buffer);
    try writeStatus(&color, "CONFLICT: reload required", true);
    try std.testing.expect(std.mem.indexOf(u8, color.buffered(), "CONFLICT: reload required") != null);
}
