const std = @import("std");
const caudex = @import("caudex");

test "public root exports are intentional" {
    const declarations = std.meta.declarations(caudex);

    try std.testing.expectEqual(@as(usize, 1), declarations.len);
    try std.testing.expectEqualStrings("canonical", declarations[0].name);
}

test "core source has no forbidden effect or dependency imports" {
    const sources = .{
        @embedFile("src/root.zig"),
        @embedFile("src/canonical.zig"),
    };
    const forbidden = .{
        "std.fs",
        "std.net",
        "std.http",
        "std.process",
        "std.posix",
        "linkLibC",
        "linkSystemLibrary",
        "sqlite",
        "zig-cats",
    };

    inline for (sources) |source| {
        inline for (forbidden) |needle| {
            try std.testing.expect(std.mem.indexOf(u8, source, needle) == null);
        }
    }
}
