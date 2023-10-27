const std = @import("std");
const zigimg = @import("zigimg");
const terminal = @import("terminal.zig");
const frame_pak = @import("frame.zig");

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
    const file_url = args[1];

    std.fs.cwd().makeDir(".temp") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // resize video to terminal size
    try resizeVideo(allocator, file_url);

    var queue = std.atomic.Queue(frame_pak.Frame).init();
    var current_frame = std.atomic.Atomic(u32).init(0);

    while (true) {
        var thread = try std.Thread.spawn(.{}, makeImage, .{ allocator, &current_frame, queue });
        thread.join();
        if (queue.mutex.tryLock()) {
            if (queue.get()) |frame| {
                var terminal_buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
                _ = try terminal_buffer.write(frame.data.buffer.items);
                try terminal_buffer.flush();
            }
        }
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

fn makeImage(allocator: std.mem.Allocator, frame_num: *std.atomic.Atomic(u32), queue: std.atomic.Queue(frame_pak.Frame)) !void {
    const frame = frame_num.load(std.atomic.Ordering.Acquire);
    frame_num.store(frame + 1, std.atomic.Ordering.Release);

    const filter = try std.fmt.allocPrint(allocator, "select=eq(n\\, {})", .{frame});
    const output = try std.fmt.allocPrint(allocator, ".temp/.temp{}.png", .{frame});
    defer allocator.free(filter);
    defer allocator.free(output);

    var proc = std.ChildProcess.init(&.{ "ffmpeg", "-i", ".temp/.temp.mp4", "-vf", filter, "-frames:v", "1", output }, allocator);
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    try proc.spawn();
    _ = try proc.wait();

    var image = try zigimg.Image.fromFilePath(allocator, output);
    defer image.deinit();
    var buffer = std.ArrayList(u8).init(allocator);

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
            try buffer.append('\n');
        } else {
            try buffer.append(chars[index]);
        }
    }

    if (queue.mutex.tryLock()) {
        queue.put(frame_pak.Frame{ .buffer = buffer });
    }

    std.fs.cwd().deleteFile(output) catch |err| switch (err) {
        error.FileNotFound => std.os.exit(0),
        else => {},
    };
}

fn resizeVideo(allocator: std.mem.Allocator, file_url: []const u8) !void {
    var terminal_size = try terminal.getTerminalSizeEven();

    const size = try std.fmt.allocPrint(allocator, "scale={}:{}", .{ terminal_size.rows, terminal_size.cols });
    defer allocator.free(size);

    var proc = std.ChildProcess.init(&.{ "ffmpeg", "-i", file_url, "-vf", size, ".temp/.temp.mp4" }, allocator);
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    try proc.spawn();
    _ = try proc.wait();
}
