const std = @import("std");
const workflows = @import("caudex_workflows");
const assets = @import("repository_test_assets");

test "workflow bridge depends only on pure public domains" {
    _ = workflows.template_schema_version;
    const source = assets.workflows_root;
    inline for (.{
        "std.fs",
        "std.net",
        "std.process",
        "std.posix",
        "sqlite",
        "caudex_persistence",
        "nanoTimestamp",
        "Random",
    }) |forbidden| {
        try std.testing.expect(std.mem.indexOf(u8, source, forbidden) == null);
    }
}
