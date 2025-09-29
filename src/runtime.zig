const std = @import("std");

var exit_requested = std.atomic.Value(bool).init(false);

fn handleSignal(_: i32) callconv(.C) void {
    const show_cursor = "\x1b[?25h";
    _ = std.posix.system.write(std.posix.STDOUT_FILENO, show_cursor.ptr, show_cursor.len);
    exit_requested.store(true, .seq_cst);
}

pub fn installSignalHandlers() !void {
    var action = std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    try std.posix.sigaction(std.posix.SIG.INT, &action, null);
    try std.posix.sigaction(std.posix.SIG.TERM, &action, null);
}

pub fn shouldExit() bool {
    return exit_requested.load(.seq_cst);
}

pub fn requestExit() void {
    exit_requested.store(true, .seq_cst);
}

fn timespecToNs(ts: std.posix.timespec) u64 {
    const sec = @as(u64, @intCast(ts.tv_sec));
    const nsec = @as(u64, @intCast(ts.tv_nsec));
    return sec * std.time.ns_per_s + nsec;
}

pub fn sleepWithExit(ns: u64) void {
    var remaining = ns;
    while (remaining > 0) {
        if (shouldExit()) return;

        var req = std.posix.timespec{
            .tv_sec = @intCast(remaining / std.time.ns_per_s),
            .tv_nsec = @intCast(remaining % std.time.ns_per_s),
        };
        var rem: std.posix.timespec = undefined;

        const rc = std.posix.system.nanosleep(&req, &rem);
        switch (std.posix.errno(rc)) {
            .SUCCESS => break,
            .INTR => {
                remaining = timespecToNs(rem);
                continue;
            },
            else => return,
        }
    }
}
