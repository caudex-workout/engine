const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.dependency("caudex_core", .{ .target = target, .optimize = optimize });
    const sqlite = b.addModule("caudex_sqlite", .{ .root_source_file = b.path("adapters/sqlite.zig"), .target = target, .optimize = optimize, .imports = &.{
        .{ .name = "caudex", .module = core.module("caudex") },
        .{ .name = "caudex_persistence", .module = core.module("caudex_persistence") },
        .{ .name = "caudex_tracking", .module = core.module("caudex_tracking") },
        .{ .name = "caudex_tracking_protocol", .module = core.module("caudex_tracking_protocol") },
        .{ .name = "caudex_portable", .module = core.module("caudex_portable") },
    } });
    sqlite.link_libc = true;
    sqlite.linkSystemLibrary("sqlite3", .{});
    b.installArtifact(b.addLibrary(.{ .name = "caudex_sqlite", .root_module = sqlite }));
}
