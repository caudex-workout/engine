const std = @import("std");
const caudex = @import("caudex");

test "public root exports are intentional" {
    const declarations = std.meta.declarations(caudex);

    try std.testing.expectEqual(@as(usize, 6), declarations.len);
    try std.testing.expectEqualStrings("canonical", declarations[0].name);
    try std.testing.expectEqualStrings("diagnostics", declarations[1].name);
    try std.testing.expectEqualStrings("engine", declarations[2].name);
    try std.testing.expectEqualStrings("methodology", declarations[3].name);
    try std.testing.expectEqualStrings("primitives", declarations[4].name);
    try std.testing.expectEqualStrings("training", declarations[5].name);
}

test "core source has no forbidden effect or dependency imports" {
    const sources = .{
        @embedFile("src/root.zig"),
        @embedFile("src/canonical.zig"),
        @embedFile("src/diagnostics.zig"),
        @embedFile("src/engine.zig"),
        @embedFile("src/methodology.zig"),
        @embedFile("src/primitives.zig"),
        @embedFile("src/training.zig"),
    };
    const forbidden = .{
        "std.fs",
        "std.net",
        "std.http",
        "std.process",
        "std.posix",
        "linkLibC",
        "linkSystemLibrary",
        "parseFloat",
        "f32",
        "f64",
        "sqlite",
        "zig-cats",
    };

    inline for (sources) |source| {
        inline for (forbidden) |needle| {
            try std.testing.expect(std.mem.indexOf(u8, source, needle) == null);
        }
    }
}
