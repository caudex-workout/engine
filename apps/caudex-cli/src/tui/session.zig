const std = @import("std");
const actions = @import("actions.zig");
const terminal_lifecycle = @import("terminal.zig");

pub const Outcome = enum { active, completed, cancelled, interrupted };
pub const State = struct {
    outcome: Outcome = .active,
    confirm_cancel: bool = false,
    short_workout: bool = false,
    width: u16 = 80,
    height: u16 = 24,
    recovery_message: ?[]const u8 = null,
};
pub const Event = union(enum) { finish, request_cancel, confirm_cancel, decline_cancel, resize: Size, interrupt, recover };
pub const Size = struct { width: u16, height: u16 };
pub const Transition = struct { state: State, action: ?actions.Action = null };

pub fn update(state: State, event: Event) Transition {
    var next = state;
    return switch (event) {
        .finish => .{ .state = next, .action = .finish_workout },
        .request_cancel => blk: {
            next.confirm_cancel = true;
            break :blk .{ .state = next };
        },
        .confirm_cancel => blk: {
            next.confirm_cancel = false;
            break :blk .{ .state = next, .action = .cancel_workout };
        },
        .decline_cancel => blk: {
            next.confirm_cancel = false;
            break :blk .{ .state = next };
        },
        .resize => |size| blk: {
            next.width = size.width;
            next.height = size.height;
            break :blk .{ .state = next };
        },
        .interrupt => blk: {
            next.outcome = .interrupted;
            next.recovery_message = "Session interrupted; persisted commands remain safe to reload.";
            break :blk .{ .state = next };
        },
        .recover => blk: {
            next.outcome = .active;
            next.recovery_message = null;
            break :blk .{ .state = next };
        },
    };
}

pub fn interruptAndRestore(terminal: *terminal_lifecycle.Terminal, state: State) State {
    terminal.restore();
    return update(state, .interrupt).state;
}

pub fn render(state: State, writer: *std.Io.Writer) !void {
    if (state.confirm_cancel) return writer.writeAll("Cancel workout? [y] confirm  [n/esc] keep workout\n");
    if (state.recovery_message) |message| return writer.print("{s}\nPress r to reload.\n", .{message});
    switch (state.outcome) {
        .active => try writer.print("Live workout ({d}x{d})\nNotes: unavailable in the public command contract\n", .{ state.width, state.height }),
        .completed => try writer.print("Workout completed{s}.\n", .{if (state.short_workout) " (short session accepted)" else ""}),
        .cancelled => try writer.writeAll("Workout cancelled.\n"),
        .interrupted => unreachable,
    }
}

test "completion and cancellation remain distinct and confirmation is escapable" {
    var state = State{ .short_workout = true };
    try std.testing.expect(update(state, .finish).action.? == .finish_workout);
    state = update(state, .request_cancel).state;
    try std.testing.expect(state.confirm_cancel);
    state = update(state, .decline_cancel).state;
    try std.testing.expect(!state.confirm_cancel);
    const confirmed = update(update(state, .request_cancel).state, .confirm_cancel);
    try std.testing.expect(confirmed.action.? == .cancel_workout);
}

test "resize and interruption restore terminal and expose recovery" {
    const fake = @import("terminal/fake.zig");
    var fake_terminal = fake.Fake{};
    var terminal = terminal_lifecycle.Terminal{ .driver = fake.driver(&fake_terminal) };
    try terminal.init();
    var state = update(.{}, .{ .resize = .{ .width = 30, .height = 10 } }).state;
    try std.testing.expectEqual(@as(u16, 30), state.width);
    state = interruptAndRestore(&terminal, state);
    try std.testing.expectEqual(terminal_lifecycle.Stage.restored, terminal.stage);
    try std.testing.expect(state.outcome == .interrupted);
    state = update(state, .recover).state;
    try std.testing.expect(state.outcome == .active);
}
