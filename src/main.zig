const std = @import("std");
const zigimg = @import("zigimg");
const terminal = @import("terminal.zig");

const log = std.log;
const print = std.debug.print;
const stdout = std.io.getStdOut().writer();

const chars = " .:-=+*#%$8@";
const arr = strToArr(chars);

const Err = error{MissingArguments};
pub fn main() !void {
    removeTempFiles();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        log.err("usage: vid_to_ascii path_to_video", .{});
        return Err.MissingArguments;
    }

    const file_url = args[1];
    try resizeVideo(alloc, file_url);

    var frame: usize = 1;
    while (true) : (frame += 1) {
        const filter = try std.fmt.allocPrint(alloc, "select=eq(n\\, {})", .{frame});
        defer alloc.free(filter);

        try makeFrame(alloc, frame);

        if (std.fs.cwd().openFile(".temp.png", .{})) |*file| {
            try clearTty(alloc);
            defer file.close();

            var image = try zigimg.Image.fromFile(alloc, @constCast(file));
            var iter = image.iterator();

            var buffer = std.io.bufferedWriter(std.io.getStdOut().writer());

            while (iter.next()) |pix| {
                const avg = 1.0 / @as(f32, chars.len);
                var pix_value = (pix.r + pix.b + pix.g) / 3;
                var index: usize = @intFromFloat(pix_value / avg);
                if (index == arr.len) {
                    index -= 1;
                }

                _ = try buffer.write(&[_]u8{arr[index]});

                if (iter.current_index % image.width == 0) {
                    _ = try buffer.write(&[_]u8{'\n'});
                }
            }

            try std.fs.Dir.deleteFile(std.fs.cwd(), ".temp.png");
            try buffer.flush();
            // std.time.sleep(10_000_000);
        } else |err| switch (err) {
            error.FileNotFound => std.os.exit(0),
            else => {},
        }
    }

    removeTempFiles();
}

fn strToArr(comptime str: []const u8) [str.len]u8 {
    var result: [str.len]u8 = undefined;
    for (str, 0..) |ch, i| {
        result[i] = ch;
    }
    return result;
}

fn removeTempFiles() void {
    std.fs.Dir.deleteFile(std.fs.cwd(), ".temp.png") catch |err| switch (err) {
        else => {},
    };

    std.fs.Dir.deleteFile(std.fs.cwd(), ".temp.mp4") catch |err| switch (err) {
        else => {},
    };
}

fn clearTty(alloc: std.mem.Allocator) !void {
    var proc = std.ChildProcess.init(&.{"clear"}, alloc);
    try proc.spawn();
    _ = try proc.wait();
}

fn makeFrame(alloc: std.mem.Allocator, start: usize, num: usize) !void {
    const filter = try std.fmt.allocPrint(alloc, "select=eq(n\\, {})", .{start});
    defer alloc.free(filter);

    var proc = std.ChildProcess.init(&.{ "ffmpeg", "-i", ".temp.mp4", "-vf", filter, "-frames:v", num, ".temp.png" }, alloc);
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    try proc.spawn();
    _ = try proc.wait();
}

fn resizeVideo(alloc: std.mem.Allocator, file_url: []const u8) !void {
    var terminal_size = try terminal.getTerminalSize();
    if (terminal_size.rows % 2 != 0) {
        terminal_size.rows -= 1;
    }
    if (terminal_size.cols % 2 != 0) {
        terminal_size.cols -= 1;
    }

    const size = try std.fmt.allocPrint(alloc, "scale={}:{}", .{ terminal_size.cols, terminal_size.rows });
    defer alloc.free(size);

    var proc = std.ChildProcess.init(&.{ "ffmpeg", "-i", file_url, "-vf", size, ".temp.mp4" }, alloc);
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    try proc.spawn();
    _ = try proc.wait();
}
