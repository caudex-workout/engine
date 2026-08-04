const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const caudex = b.addModule("caudex", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    const tracking = b.addModule("caudex_tracking", .{ .root_source_file = b.path("tracking/root.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "caudex", .module = caudex }} });
    const tracking_protocol = b.addModule("caudex_tracking_protocol", .{ .root_source_file = b.path("tracking/protocol.zig"), .target = target, .optimize = optimize, .imports = &.{
        .{ .name = "caudex", .module = caudex },
        .{ .name = "caudex_tracking", .module = tracking },
    } });
    _ = b.addModule("caudex_workflows", .{ .root_source_file = b.path("workflows/root.zig"), .target = target, .optimize = optimize, .imports = &.{
        .{ .name = "caudex", .module = caudex },
        .{ .name = "caudex_tracking", .module = tracking },
        .{ .name = "caudex_tracking_protocol", .module = tracking_protocol },
    } });
    const portable = b.addModule("caudex_portable", .{ .root_source_file = b.path("portable/protocol.zig"), .target = target, .optimize = optimize, .imports = &.{
        .{ .name = "caudex", .module = caudex },
        .{ .name = "caudex_tracking", .module = tracking },
        .{ .name = "caudex_tracking_protocol", .module = tracking_protocol },
    } });
    _ = b.addModule("caudex_persistence", .{ .root_source_file = b.path("adapters/persistence.zig"), .target = target, .optimize = optimize, .imports = &.{
        .{ .name = "caudex", .module = caudex },
        .{ .name = "caudex_portable", .module = portable },
    } });

    b.installArtifact(b.addLibrary(.{ .name = "caudex", .root_module = caudex }));
}
