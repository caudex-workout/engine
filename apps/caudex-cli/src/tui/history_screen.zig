const std = @import("std");
const actions = @import("actions.zig");

pub const Query = struct { from: ?[]const u8 = null, through: ?[]const u8 = null, exercise_id: ?[]const u8 = null, search: []const u8 = "", limit: u16 = 25, after: ?Cursor = null };
pub const Cursor = struct { completed_at: []const u8, workout_id: []const u8 };
pub const Item = struct { workout_id: []const u8, completed_at: []const u8, exercise_ids: []const []const u8 };
pub const Detail = struct { item: Item, last_performance: ?Item = null };
pub const Conflict = union(enum) { none, refresh_required, explanation: []const u8 };
pub const Screen = struct { query: Query, items: []const Item, selected: usize = 0, detail: ?Detail = null, conflict: Conflict = .none };

pub fn bounded(query: Query) Query {
    var result = query;
    if (result.limit == 0) result.limit = 1;
    if (result.limit > 100) result.limit = 100;
    return result;
}
pub fn matches(query: Query, item: Item) bool {
    if (query.search.len == 0) return true;
    if (containsFold(item.workout_id, query.search)) return true;
    for (item.exercise_ids) |id| if (containsFold(id, query.search)) return true;
    return false;
}
pub fn correction(workout_id: []const u8, membership_id: []const u8, set_id: []const u8, metrics: []const actions.MetricInput, confirmed: bool) ?actions.Action {
    if (!confirmed or workout_id.len == 0 or membership_id.len == 0 or set_id.len == 0 or metrics.len == 0) return null;
    return .{ .correct_historical_set = .{ .workout_id = workout_id, .membership_id = membership_id, .set_id = set_id, .metrics = metrics, .confirmed = true } };
}
pub fn render(screen: Screen, writer: *std.Io.Writer) !void {
    switch (screen.conflict) {
        .refresh_required => return writer.writeAll("History changed. Reload before correcting; nothing was overwritten.\n"),
        .explanation => |message| return writer.print("Correction conflict: {s}\n", .{message}),
        .none => {},
    }
    if (screen.detail) |detail| {
        try writer.print("Workout {s}\nCompleted: {s}\n", .{ detail.item.workout_id, detail.item.completed_at });
        if (detail.last_performance) |last| try writer.print("Last performance: {s} at {s}\n", .{ last.workout_id, last.completed_at });
        return;
    }
    var shown: usize = 0;
    const limit = bounded(screen.query).limit;
    for (screen.items) |item| if (matches(screen.query, item) and shown < limit) {
        try writer.print("{s} {s}\n", .{ item.completed_at, item.workout_id });
        shown += 1;
    };
}
fn containsFold(value: []const u8, query: []const u8) bool {
    if (query.len > value.len) return false;
    var index: usize = 0;
    while (index + query.len <= value.len) : (index += 1) if (std.ascii.eqlIgnoreCase(value[index .. index + query.len], query)) return true;
    return false;
}

test "history queries are bounded and correction is explicit" {
    try std.testing.expectEqual(@as(u16, 100), bounded(.{ .limit = 500 }).limit);
    const exercises = [_][]const u8{"bench"};
    const item = Item{ .workout_id = "w1", .completed_at = "2026-07-28T09:04:00Z", .exercise_ids = &exercises };
    try std.testing.expect(matches(.{ .search = "BEN" }, item));
    const metrics = [_]actions.MetricInput{.{ .code = "repetitions", .decimal = "8", .unit = "count" }};
    try std.testing.expect(correction("w1", "m1", "s1", &metrics, false) == null);
    try std.testing.expect(correction("w1", "m1", "s1", &metrics, true).? == .correct_historical_set);
}
test "history conflict never overwrites" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try render(.{ .query = .{}, .items = &.{}, .conflict = .refresh_required }, &writer);
    try std.testing.expectEqualStrings("History changed. Reload before correcting; nothing was overwritten.\n", writer.buffered());
}
