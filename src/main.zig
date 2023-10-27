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
    std.log.info("  main: before main thread", .{});

    var queue = @constCast(&std.atomic.Queue(frame_pak.Frame).init());
    var current_frame = @constCast(&std.atomic.Atomic(u32).init(0));

    while (true) {
        std.log.info("main  : before main thread mutexlock", .{});
        var thread = try std.Thread.spawn(.{}, makeImage, .{ allocator, current_frame, queue.* });
        std.log.info("main  : before thread join", .{});
        queue.mutex.lock();
        if (queue.head) |node| {
            var terminal_buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
            _ = try terminal_buffer.write(node.data.buffer.items);
            try terminal_buffer.flush();
        }
        queue.mutex.unlock();
        thread.join();
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
    var queue_ref = @constCast(&queue);
    const Frame = frame_pak.Frame;
    const frame = frame_num.load(std.atomic.Ordering.Acquire);
    frame_num.store(frame + 1, std.atomic.Ordering.Release);
    std.log.info("thread: in frame {}", .{frame_num.load(std.atomic.Ordering.Acquire)});

    const filter = try std.fmt.allocPrint(allocator, "select=eq(n\\, {})", .{frame});
    const output = try std.fmt.allocPrint(allocator, ".temp/.temp{}.png", .{frame});
    defer allocator.free(filter);
    defer allocator.free(output);

    var proc = std.ChildProcess.init(&.{ "ffmpeg", "-i", ".temp/.temp.mp4", "-vf", filter, "-frames:v", "1", output }, allocator);
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    _ = try proc.spawnAndWait();
    std.log.info("thread: Created image", .{});

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

    std.log.info("thread: Before mutex lock", .{});
    queue_ref.mutex.lock();
    defer queue_ref.mutex.unlock();
    std.log.info("thread: adding head of queue -> {}", .{queue_ref});
    if (queue_ref.head) |head| {
        std.log.info("thread: changing queue head -> {}", .{head.data});
        head.next = @constCast(&std.atomic.Queue(Frame).Node{ .data = Frame{ .buffer = buffer }, .prev = head, .next = null });
    } else {
        queue_ref.head =
            @constCast(&std.atomic.Queue(Frame).Node{ .data = Frame{ .buffer = buffer }, .prev = null, .next = null });
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
