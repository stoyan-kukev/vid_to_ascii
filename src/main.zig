const std = @import("std");
const zigimg = @import("zigimg");
const terminal = @import("terminal.zig");

const log = std.log;
const print = std.debug.print;
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
        log.err("usage: vid_to_ascii path_to_video", .{});
        return Err.MissingArguments;
    }

    std.fs.cwd().makeDir(".temp") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const file_url = args[1];

    // resize video to terminal size
    try resizeVideo(allocator, file_url);

    var front_buffer: std.ArrayList(u8) = undefined;
    var back_buffer: std.ArrayList(u8) = undefined;

    var frame: usize = 0;
    while (true) : (frame += 2) {
        try makeImage(allocator, frame);
        front_buffer = try imageToFrame(allocator, ".temp/.temp0.png");

        try makeImage(allocator, frame + 1);
        back_buffer = try imageToFrame(allocator, ".temp/.temp1.png");
        print("{s}", .{front_buffer.items});
        // var buffer = try createBuffer(alloc, ".temp.png", &buffers);
        // try clearTty(allocator);

        // try std.fs.Dir.deleteFile(std.fs.cwd(), ".temp/.temp.png");
        // try buffer.flush();
        // std.time.sleep(10_000);
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

fn clearTty(alloc: std.mem.Allocator) !void {
    var proc = std.ChildProcess.init(&.{"clear"}, alloc);
    try proc.spawn();
    _ = try proc.wait();
}

fn getEvenTtySize(size: terminal.TerminalSize) terminal.TerminalSize {
    var terminal_size = size;
    if (terminal_size.rows % 2 != 0) {
        terminal_size.rows -= 1;
    }
    if (terminal_size.cols % 2 != 0) {
        terminal_size.cols -= 1;
    }

    return terminal_size;
}

fn makeImage(allocator: std.mem.Allocator, frame: usize) !void {
    const filter = try std.fmt.allocPrint(allocator, "select=eq(n\\, {})", .{frame});
    const output = try std.fmt.allocPrint(allocator, ".temp/.temp{}.png", .{frame});
    defer allocator.free(filter);
    defer allocator.free(output);

    var proc = std.ChildProcess.init(&.{ "ffmpeg", "-i", ".temp/.temp.mp4", "-vf", filter, "-frames:v", "1", output }, allocator);
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    try proc.spawn();
    _ = try proc.wait();
}

fn resizeVideo(alloc: std.mem.Allocator, file_url: []const u8) !void {
    var terminal_size = getEvenTtySize(try terminal.getTerminalSize());

    const size = try std.fmt.allocPrint(alloc, "scale={}:{}", .{ terminal_size.rows, terminal_size.cols });
    defer alloc.free(size);

    var proc = std.ChildProcess.init(&.{ "ffmpeg", "-i", file_url, "-vf", size, ".temp/.temp.mp4" }, alloc);
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    try proc.spawn();
    _ = try proc.wait();
}

fn imageToFrame(allocator: std.mem.Allocator, file_name: []const u8) !std.ArrayList(u8) {
    var image = try zigimg.Image.fromFilePath(allocator, file_name);
    var buffer = std.ArrayList(u8).init(allocator);

    var iter = image.iterator();
    while (iter.next()) |pix| {
        const avg = 1.0 / @as(f32, chars.len);
        const i = iter.current_index;
        var pix_value = (pix.r + pix.b + pix.g) / 3;
        var index: usize = @intFromFloat(pix_value / avg);
        if (index == chars.len) {
            index -= 1;
        }

        if (i % image.width == 0) {
            try buffer.append('\n');
        } else {
            try buffer.append(chars[index]);
        }
    }

    print("here", .{});

    return buffer;
}
