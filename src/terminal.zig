const std = @import("std");

const TerSizeError = error{GetTerminalSizeFailed};

pub const TerminalSize = struct {
    rows: u16,
    cols: u16,
};

pub fn getTerminalSize() !TerminalSize {
    if (@import("builtin").os.tag == .windows) return winGetSize();
    return unixGetSize();
}

fn winGetSize() !TerminalSize {
    var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(std.io.getStdOut().handle, &info) != std.os.windows.TRUE) {
        return TerSizeError.GetTerminalSizeFailed;
    }

    return .{
        .cols = @intCast(info.srWindow.Right - info.srWindow.Left + 1),
        .rows = @intCast(info.srWindow.Bottom - info.srWindow.Top + 2),
    };
}

fn unixGetSize() !TerminalSize {
    const stdout = std.io.getStdOut();

    var win_size: std.os.system.winsize = undefined;
    const rc = std.os.system.ioctl(stdout.handle, std.os.system.T.IOCGWINSZ, @intFromPtr(&win_size));
    switch (std.os.errno(rc)) {
        .SUCCESS => {},
        else => return TerSizeError.GetTerminalSizeFailed,
    }
    return .{ .cols = win_size.ws_col, .rows = win_size.ws_row };
}
