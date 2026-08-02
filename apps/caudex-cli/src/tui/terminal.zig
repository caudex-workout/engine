pub const Stage = enum { idle, raw_mode, alternate_screen, resize_registered, active, restored };
pub const Driver = struct {
    context: *anyopaque,
    enter_raw: *const fn (*anyopaque) anyerror!void,
    leave_raw: *const fn (*anyopaque) void,
    enter_screen: *const fn (*anyopaque) anyerror!void,
    leave_screen: *const fn (*anyopaque) void,
    register_resize: *const fn (*anyopaque) anyerror!void,
    unregister_resize: *const fn (*anyopaque) void,
};

test "initialization failure at every stage restores entered stages once" {
    const fake = @import("terminal/fake.zig");
    var stage: usize = 1;
    while (stage <= 3) : (stage += 1) {
        var value = fake.Fake{ .fail_at = stage };
        var terminal = Terminal{ .driver = fake.driver(&value) };
        try @import("std").testing.expectError(error.Failed, terminal.init());
        try @import("std").testing.expectEqual(if (stage == 1) Stage.idle else Stage.restored, terminal.stage);
        const calls_after_restore = value.calls;
        terminal.restore();
        try @import("std").testing.expectEqual(calls_after_restore, value.calls);
    }
}

test "ordinary restore unregisters resize before screen and raw mode" {
    const fake = @import("terminal/fake.zig");
    var value = fake.Fake{};
    var terminal = Terminal{ .driver = fake.driver(&value) };
    try terminal.init();
    terminal.restore();
    try @import("std").testing.expectEqual(Stage.restored, terminal.stage);
    try @import("std").testing.expectEqual(@as(usize, 6), value.calls);
}
pub const Terminal = struct {
    driver: Driver,
    stage: Stage = .idle,
    pub fn init(self: *Terminal) !void {
        try self.driver.enter_raw(self.driver.context);
        self.stage = .raw_mode;
        errdefer self.restore();
        try self.driver.enter_screen(self.driver.context);
        self.stage = .alternate_screen;
        try self.driver.register_resize(self.driver.context);
        self.stage = .resize_registered;
        self.stage = .active;
    }
    pub fn restore(self: *Terminal) void {
        switch (self.stage) {
            .active, .resize_registered => self.driver.unregister_resize(self.driver.context),
            else => {},
        }
        switch (self.stage) {
            .active, .resize_registered, .alternate_screen => self.driver.leave_screen(self.driver.context),
            else => {},
        }
        switch (self.stage) {
            .active, .resize_registered, .alternate_screen, .raw_mode => self.driver.leave_raw(self.driver.context),
            else => {},
        }
        self.stage = .restored;
    }
};
