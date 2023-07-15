const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "vid2ascii",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.default_step.dependOn(&exe.step);

    const install_step = b.addRunArtifact(exe);
    install_step.step.dependOn(b.getInstallStep());

    // const run_cmd = b.addSystemCommand(&.{ "ffmpeg", "-i", "jeep.mp4", "-an", "-s", "qvga", "images/%06d.png" });
    // run_cmd.step.dependOn(&install_step.step);

    if (b.args) |args| {
        install_step.addArgs(args);
    }
    // .{ .source_file = .{ .path = "deps/zigimg/zigimg.zig" } });
    const zigimg = b.addModule("zigimg", .{ .source_file = .{ .path = "deps/zigimg/zigimg.zig" } });
    exe.addModule("zigimg", zigimg);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&install_step.step);
}
