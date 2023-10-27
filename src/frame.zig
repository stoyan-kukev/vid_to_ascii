const std = @import("std");
const terminal = @import("terminal.zig");

pub const Frame = struct {
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, size: terminal.TerminalSize) Frame {
        return Frame{ .buffer = std.ArrayList(u8).initCapacity(allocator, size.rows * size.cols) };
    }
};
