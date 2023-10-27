const std = @import("std");
const zigimg = @import("zigimg");
const terminal = @import("terminal.zig");
const frame = @import("frame.zig");

const stdout = std.io.getStdOut().writer();

const chars = " .:-=+*#%$8@";

const Err = error{MissingArguments};
pub fn main() !void {
    removeTempFiles();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.err("usage: vid_to_ascii path_to_video", .{});
        return Err.MissingArguments;
    }
    const file_url = args[1];

    std.fs.cwd().makeDir(".temp") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // resize video to terminal size
    try resizeVideo(allocator, file_url);

    var current: u32 = 0;
    while (true) : (current += 1) {
        try terminal.clearTerminal(allocator);
        try makeImage(allocator, current);
        var terminal_buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
        try terminal_buffer.flush();
    }

    removeTempFiles();
}

fn removeTempFiles() void {
    std.fs.Dir.deleteFile(std.fs.cwd(), ".temp/.temp.png") catch |err| switch (err) {
        else => {},
    };

    std.fs.Dir.deleteFile(std.fs.cwd(), ".temp/.temp.mp4") catch |err| switch (err) {
        else => {},
    };
}

fn makeImage(allocator: std.mem.Allocator, num: u32) !void {
    const filter = try std.fmt.allocPrint(allocator, "select=eq(n\\, {})", .{num});
    const output = ".temp/.temp.png";
    defer allocator.free(filter);

    var proc = std.ChildProcess.init(&.{ "ffmpeg", "-i", ".temp/.temp.mp4", "-vf", filter, "-frames:v", "1", output }, allocator);
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    _ = try proc.spawnAndWait();

    var image = try zigimg.Image.fromFilePath(allocator, output);
    defer image.deinit();
    var terminal_buffer = std.io.bufferedWriter(std.io.getStdOut().writer());

    var iter = image.iterator();
    while (iter.next()) |pix| {
        const avg = 1.0 / @as(f32, chars.len);
        const i = iter.current_index;
        var pix_value = (pix.r + pix.b + pix.g + pix.a) / 4;
        var index: usize = @intFromFloat(pix_value / avg);
        if (index == chars.len) {
            index -= 1;
        }

        if (i % image.width == 0) {
            _ = try terminal_buffer.write(&.{'\n'});
        } else {
            _ = try terminal_buffer.write(&.{chars[index]});
        }
    }

    std.fs.cwd().deleteFile(output) catch |err| switch (err) {
        error.FileNotFound => std.os.exit(0),
        else => {},
    };
}

fn resizeVideo(allocator: std.mem.Allocator, file_url: []const u8) !void {
    var terminal_size = try terminal.getTerminalSizeEven();

    const size = try std.fmt.allocPrint(allocator, "scale={}:{}", .{ terminal_size.cols, terminal_size.rows });
    defer allocator.free(size);

    var proc = std.ChildProcess.init(&.{ "ffmpeg", "-i", file_url, "-vf", size, ".temp/.temp.mp4" }, allocator);
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    try proc.spawn();
    _ = try proc.wait();
}
