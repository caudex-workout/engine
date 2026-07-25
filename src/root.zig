const std = @import("std");

test "library test target is wired" {
    try std.testing.expect(true);
}
