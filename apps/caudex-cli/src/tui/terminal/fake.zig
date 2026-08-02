const terminal = @import("../terminal.zig");
pub const Fake = struct { calls: usize = 0, fail_at: ?usize = null };
pub fn driver(fake: *Fake) terminal.Driver {
    return .{ .context = fake, .enter_raw = step, .leave_raw = leave, .enter_screen = step, .leave_screen = leave, .register_resize = step, .unregister_resize = leave };
}
fn step(context: *anyopaque) !void {
    const fake: *Fake = @ptrCast(@alignCast(context));
    fake.calls += 1;
    if (fake.fail_at == fake.calls) return error.Failed;
}
fn leave(context: *anyopaque) void {
    const fake: *Fake = @ptrCast(@alignCast(context));
    fake.calls += 1;
}
