const std = @import("std");

pub const canonical = @import("canonical.zig");
pub const primitives = @import("primitives.zig");

test "library test target is wired" {
    try std.testing.expect(true);
}
