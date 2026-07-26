const std = @import("std");
const caudex = @import("caudex");

test "public root exports are intentional" {
    const declarations = std.meta.declarations(caudex);

    try std.testing.expectEqual(@as(usize, 14), declarations.len);
    try std.testing.expectEqualStrings("canonical", declarations[0].name);
    try std.testing.expectEqualStrings("canonical_json", declarations[1].name);
    try std.testing.expectEqualStrings("diagnostics", declarations[2].name);
    try std.testing.expectEqualStrings("double_progression", declarations[3].name);
    try std.testing.expectEqualStrings("duration", declarations[4].name);
    try std.testing.expectEqualStrings("engine", declarations[5].name);
    try std.testing.expectEqualStrings("filtering", declarations[6].name);
    try std.testing.expectEqualStrings("history", declarations[7].name);
    try std.testing.expectEqualStrings("load_math", declarations[8].name);
    try std.testing.expectEqualStrings("methodology", declarations[9].name);
    try std.testing.expectEqualStrings("ordering", declarations[10].name);
    try std.testing.expectEqualStrings("primitives", declarations[11].name);
    try std.testing.expectEqualStrings("rpe_top_set_backoff", declarations[12].name);
    try std.testing.expectEqualStrings("training", declarations[13].name);
}

test "core source has no forbidden effect or dependency imports" {
    const sources = .{
        @embedFile("src/root.zig"),
        @embedFile("src/canonical.zig"),
        @embedFile("src/canonical_json.zig"),
        @embedFile("src/diagnostics.zig"),
        @embedFile("src/double_progression.zig"),
        @embedFile("src/duration.zig"),
        @embedFile("src/engine.zig"),
        @embedFile("src/filtering.zig"),
        @embedFile("src/history.zig"),
        @embedFile("src/load_math.zig"),
        @embedFile("src/methodology.zig"),
        @embedFile("src/ordering.zig"),
        @embedFile("src/primitives.zig"),
        @embedFile("src/rpe_top_set_backoff.zig"),
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
        "@import(\"persistence",
        "adapters/persistence",
        "@caudex/persistence",
        "zig-cats",
    };

    inline for (sources) |source| {
        inline for (forbidden) |needle| {
            try std.testing.expect(std.mem.indexOf(u8, source, needle) == null);
        }
    }
}
