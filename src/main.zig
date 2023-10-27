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

    while (true) {
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
    var terminal_size = try terminal.getTerminalSizeEven();

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
