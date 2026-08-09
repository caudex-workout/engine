const std = @import("std");
const caudex = @import("caudex");
const assets = @import("repository_test_assets");

test "public root exports are intentional" {
    const declarations = std.meta.declarations(caudex);

    try std.testing.expectEqual(@as(usize, 15), declarations.len);
    try std.testing.expectEqualStrings("canonical", declarations[0].name);
    try std.testing.expectEqualStrings("canonical_json", declarations[1].name);
    try std.testing.expectEqualStrings("diagnostics", declarations[2].name);
    try std.testing.expectEqualStrings("discovery", declarations[3].name);
    try std.testing.expectEqualStrings("double_progression", declarations[4].name);
    try std.testing.expectEqualStrings("duration", declarations[5].name);
    try std.testing.expectEqualStrings("engine", declarations[6].name);
    try std.testing.expectEqualStrings("filtering", declarations[7].name);
    try std.testing.expectEqualStrings("history", declarations[8].name);
    try std.testing.expectEqualStrings("load_math", declarations[9].name);
    try std.testing.expectEqualStrings("methodology", declarations[10].name);
    try std.testing.expectEqualStrings("ordering", declarations[11].name);
    try std.testing.expectEqualStrings("primitives", declarations[12].name);
    try std.testing.expectEqualStrings("rpe_top_set_backoff", declarations[13].name);
    try std.testing.expectEqualStrings("training", declarations[14].name);
}

test "core source has no forbidden effect or dependency imports" {
    const sources = .{
        assets.src_root,      assets.src_canonical,          assets.src_canonical_json,      assets.src_diagnostics,
        assets.src_discovery, assets.src_double_progression, assets.src_duration,            assets.src_engine,
        assets.src_filtering, assets.src_history,            assets.src_load_math,           assets.src_methodology,
        assets.src_ordering,  assets.src_primitives,         assets.src_rpe_top_set_backoff, assets.src_training,
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
        "@caudex-workout/persistence",
        "zig-cats",
    };

    inline for (sources) |source| {
        inline for (forbidden) |needle| {
            try std.testing.expect(std.mem.indexOf(u8, source, needle) == null);
        }
    }
}

test "core npm package has no persistence adapter dependency" {
    const manifest = assets.manifest;
    try std.testing.expect(
        std.mem.indexOf(u8, manifest, "@caudex-workout/persistence") == null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, manifest, "indexeddb") == null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, manifest, "sqlite") == null,
    );
}
