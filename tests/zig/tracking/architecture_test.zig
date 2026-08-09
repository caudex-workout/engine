const std = @import("std");
const tracking = @import("caudex_tracking");
const assets = @import("repository_test_assets");

test "tracking package has one public dependency and no effects" {
    _ = tracking.contract_version;
    const source = assets.tracking_root;
    const allowed_import = "@import(\"caudex\")";
    try std.testing.expect(std.mem.indexOf(u8, source, allowed_import) != null);

    inline for (.{
        "std.fs",
        "std.net",
        "std.process",
        "std.posix",
        "sqlite",
        "@import(\"caudex_persistence\")",
        "@import(\"caudex_sqlite\")",
        "Allocator",
        "nanoTimestamp",
        "Random",
    }) |forbidden| {
        try std.testing.expect(std.mem.indexOf(u8, source, forbidden) == null);
    }
}
