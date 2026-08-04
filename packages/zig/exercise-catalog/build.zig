const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.dependency("caudex_core", .{ .target = target, .optimize = optimize });
    _ = b.addModule("caudex_exercise_catalog", .{ .root_source_file = b.path("catalog/root.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "caudex", .module = core.module("caudex") }} });
}
