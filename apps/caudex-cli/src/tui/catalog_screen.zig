const std = @import("std");
const actions = @import("actions.zig");

pub const Availability = enum { active, archived };
pub const Item = struct { id: []const u8, name: []const u8, aliases: []const []const u8 = &.{}, equipment: []const []const u8 = &.{}, movements: []const []const u8 = &.{}, unilateral: ?bool = null, availability: Availability = .active };
pub const Screen = struct { items: []const Item, query: []const u8 = "", include_archived: bool = false, selected: usize = 0 };

pub fn matches(screen: Screen, item: Item) bool {
    if (!screen.include_archived and item.availability == .archived) return false;
    if (screen.query.len == 0 or containsFold(item.id, screen.query) or containsFold(item.name, screen.query)) return true;
    for (item.aliases) |alias| if (containsFold(alias, screen.query)) return true;
    return false;
}

pub fn selectedAction(screen: Screen, restore: bool) ?actions.Action {
    var match_index: usize = 0;
    for (screen.items) |item| if (matches(screen, item)) {
        if (match_index == screen.selected) return .{ .catalog = if (restore) .{ .restore = item.id } else .{ .archive = item.id } };
        match_index += 1;
    };
    return null;
}

pub fn render(screen: Screen, writer: *std.Io.Writer) !void {
    try writer.print("Catalog search: {s}\n", .{screen.query});
    var match_index: usize = 0;
    for (screen.items) |item| if (matches(screen, item)) {
        try writer.print("{s} {s} ({s}) [{s}]\n", .{ if (match_index == screen.selected) ">" else " ", item.name, item.id, @tagName(item.availability) });
        if (item.aliases.len > 0) {
            try writer.writeAll("  aliases: ");
            try renderList(item.aliases, writer);
            try writer.writeByte('\n');
        }
        if (item.equipment.len > 0) {
            try writer.writeAll("  equipment: ");
            try renderList(item.equipment, writer);
            try writer.writeByte('\n');
        }
        if (item.movements.len > 0) {
            try writer.writeAll("  movements: ");
            try renderList(item.movements, writer);
            try writer.writeByte('\n');
        }
        match_index += 1;
    };
}

fn containsFold(value: []const u8, query: []const u8) bool {
    if (query.len > value.len) return false;
    var index: usize = 0;
    while (index + query.len <= value.len) : (index += 1) if (std.ascii.eqlIgnoreCase(value[index .. index + query.len], query)) return true;
    return false;
}
fn renderList(values: []const []const u8, writer: *std.Io.Writer) !void {
    for (values, 0..) |value, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.writeAll(value);
    }
}

test "catalog search aliases and archive actions use supported fields only" {
    const aliases = [_][]const u8{"bp"};
    const equipment = [_][]const u8{"barbell"};
    const items = [_]Item{ .{ .id = "bench", .name = "Bench Press", .aliases = &aliases, .equipment = &equipment }, .{ .id = "old", .name = "Old Lift", .availability = .archived } };
    const screen = Screen{ .items = &items, .query = "BP" };
    try std.testing.expect(matches(screen, items[0]));
    try std.testing.expect(!matches(screen, items[1]));
    try std.testing.expect(selectedAction(screen, false).?.catalog == .archive);
    const source = @embedFile("catalog_screen.zig");
    try std.testing.expect(std.mem.indexOf(u8, source, "@import(\"caudex_sqlite\")") == null);
}
