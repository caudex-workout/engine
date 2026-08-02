const std = @import("std");
const actions = @import("actions.zig");

pub const Event = union(enum) { up, down, resize: Width, toggle_help, quit };
pub const Width = u16;
pub const Model = struct { selected: usize = 0, help_visible: bool = false, quit_requested: bool = false, width: Width = 80, items: usize };

pub fn update(model: Model, event: Event) Model {
    var next = model;
    switch (event) {
        .up => {
            if (next.selected > 0) next.selected -= 1;
        },
        .down => {
            if (next.selected + 1 < next.items) next.selected += 1;
        },
        .resize => |width| next.width = width,
        .toggle_help => next.help_visible = !next.help_visible,
        .quit => next.quit_requested = true,
    }
    return next;
}

/// Maps terminal events to application intents; execution belongs to the
/// shared client-action layer, never to rendering or terminal code.
pub fn actionFor(event: Event) ?actions.Action {
    return switch (event) {
        .up => .{ .move_selection = .up },
        .down => .{ .move_selection = .down },
        .toggle_help => .show_help,
        .quit => .quit,
        .resize => null,
    };
}

pub fn render(model: Model, writer: *std.Io.Writer) !void {
    if (model.help_visible) return writer.writeAll("Caudex TUI help\n↑/↓ select  ? help  q quit\n");
    try writer.print("Workout ({d} columns)\n", .{if (model.width < 40) @as(u16, 1) else 2});
    try writer.print("Selected: {d}\n", .{model.selected + 1});
}

test "synthetic events update deterministically and render narrow help states" {
    var model = Model{ .items = 2 };
    model = update(model, .down);
    model = update(model, .{ .resize = 20 });
    try std.testing.expectEqual(@as(usize, 1), model.selected);
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try render(model, &writer);
    try std.testing.expectEqualStrings("Workout (1 columns)\nSelected: 2\n", writer.buffered());
    model = update(model, .toggle_help);
    writer = std.Io.Writer.fixed(&buffer);
    try render(model, &writer);
    try std.testing.expectEqualStrings("Caudex TUI help\n↑/↓ select  ? help  q quit\n", writer.buffered());
    try std.testing.expectEqual(actions.Action{ .move_selection = .down }, actionFor(.down).?);
}

test "model actions stay terminal-library free" {
    const source = @embedFile("model.zig");
    const needle = "@im" ++ "port(\"vaxis\")";
    try std.testing.expect(std.mem.indexOf(u8, source, needle) == null);
}
