const std = @import("std");
const caudex = @import("caudex");

test "public root exports are intentional" {
    const declarations = std.meta.declarations(caudex);

    try std.testing.expectEqual(@as(usize, 11), declarations.len);
    try std.testing.expectEqualStrings("canonical", declarations[0].name);
    try std.testing.expectEqualStrings("diagnostics", declarations[1].name);
    try std.testing.expectEqualStrings("double_progression", declarations[2].name);
    try std.testing.expectEqualStrings("duration", declarations[3].name);
    try std.testing.expectEqualStrings("engine", declarations[4].name);
    try std.testing.expectEqualStrings("filtering", declarations[5].name);
    try std.testing.expectEqualStrings("history", declarations[6].name);
    try std.testing.expectEqualStrings("methodology", declarations[7].name);
    try std.testing.expectEqualStrings("ordering", declarations[8].name);
    try std.testing.expectEqualStrings("primitives", declarations[9].name);
    try std.testing.expectEqualStrings("training", declarations[10].name);
}

test "core source has no forbidden effect or dependency imports" {
    const sources = .{
        @embedFile("src/root.zig"),
        @embedFile("src/canonical.zig"),
        @embedFile("src/diagnostics.zig"),
        @embedFile("src/double_progression.zig"),
        @embedFile("src/duration.zig"),
        @embedFile("src/engine.zig"),
        @embedFile("src/filtering.zig"),
        @embedFile("src/history.zig"),
        @embedFile("src/methodology.zig"),
        @embedFile("src/ordering.zig"),
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
