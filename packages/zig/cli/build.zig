const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.dependency("caudex_core", .{ .target = target, .optimize = optimize });
    const sqlite = b.dependency("caudex_sqlite", .{ .target = target, .optimize = optimize });
    _ = b.dependency("caudex_exercise_catalog", .{ .target = target, .optimize = optimize });
    const executable = b.addExecutable(.{ .name = "caudex", .root_module = b.createModule(.{
        .root_source_file = b.path("apps/caudex-cli/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "caudex", .module = core.module("caudex") },
            .{ .name = "caudex_persistence", .module = core.module("caudex_persistence") },
            .{ .name = "caudex_tracking", .module = core.module("caudex_tracking") },
            .{ .name = "caudex_sqlite", .module = sqlite.module("caudex_sqlite") },
        },
    }) });
    b.installArtifact(executable);
}
