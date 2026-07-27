const std = @import("std");
const persistence = @import("caudex_persistence");
const sqlite = @import("caudex_sqlite");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.InvalidArguments;
    const path = try init.arena.allocator().dupeZ(u8, args[1]);
    const adapter = try sqlite.open(path, .{});
    defer adapter.close();
    try adapter.replaceCatalog(init.arena.allocator(), .{
        .host_scope_key = "exercise-integration",
        .as_of = "2026-07-26T12:00:00Z",
    }, &.{
        persistence.canonical.Exercise{
            .id = "bench-press",
            .name = "Bench Press",
            .aliases = &.{"bench"},
        },
        persistence.canonical.Exercise{
            .id = "incline-bench",
            .name = "Incline Bench Press",
        },
    });
}
