const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Raylib's package build compiles the library from its C sources and exposes
    // a translated Zig module. The locked dependency is fetched automatically
    // the first time this build runs.
    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .Wayland,
    });

    const exe = b.addExecutable(.{
        .name = "life",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{
                .name = "raylib",
                .module = raylib_dep.module("raylib"),
            }},
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Build and run the raylib demo");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    if (b.args) |args| run_cmd.addArgs(args);
}
