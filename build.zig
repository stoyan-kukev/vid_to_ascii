const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const zigimg = b.dependency("zigimg", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "vid2ascii",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("zigimg", zigimg.module("zigimg"));

    b.default_step.dependOn(&exe.step);

    const install_step = b.addRunArtifact(exe);
    install_step.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        install_step.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&install_step.step);
}
