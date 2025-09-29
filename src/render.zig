const std = @import("std");
const lyrics = @import("lyrics.zig");

const TerminalSize = struct {
    rows: u16,
    cols: u16,
};

const RenderSlot = struct {
    present: bool,
    text_ptr: usize,
    t: f64,
    highlight: bool,
};

pub const RenderState = struct {
    allocator: std.mem.Allocator,
    show_timestamp: bool,
    dim_inactive: bool,
    visible_lines: usize,
    initialized: bool,
    last_rows: u16,
    last_cols: u16,
    last_start_row: usize,
    slots: []RenderSlot,

    pub fn init(allocator: std.mem.Allocator, show_timestamp: bool, dim_inactive: bool, visible_lines: usize) !RenderState {
        const slots = try allocator.alloc(RenderSlot, visible_lines);
        for (slots) |*slot| slot.* = RenderSlot{ .present = false, .text_ptr = 0, .t = 0, .highlight = false };
        return RenderState{
            .allocator = allocator,
            .show_timestamp = show_timestamp,
            .dim_inactive = dim_inactive,
            .visible_lines = visible_lines,
            .initialized = false,
            .last_rows = 0,
            .last_cols = 0,
            .last_start_row = 0,
            .slots = slots,
        };
    }

    pub fn deinit(self: *RenderState) void {
        self.allocator.free(self.slots);
        self.slots = &[_]RenderSlot{};
    }

    pub fn reset(self: *RenderState) void {
        self.initialized = false;
        self.last_rows = 0;
        self.last_cols = 0;
        self.last_start_row = 0;
        for (self.slots) |*slot| slot.* = RenderSlot{ .present = false, .text_ptr = 0, .t = 0, .highlight = false };
    }

    pub fn draw(
        self: *RenderState,
        title: []const u8,
        artist: []const u8,
        album: []const u8,
        status: []const u8,
        cur_t: f64,
        lines: []const lyrics.Line,
        src: []const u8,
    ) void {
        _ = title;
        _ = artist;
        _ = album;
        _ = status;
        _ = src;

        const term = getTerminalSize();
        const row_count: usize = @as(usize, if (term.rows == 0) 24 else term.rows);
        const col_count: usize = @as(usize, if (term.cols == 0) 80 else term.cols);
        const line_count: usize = self.visible_lines;
        const top_pad: usize = if (row_count > line_count) (row_count - line_count) / 2 else 0;
        const start_row: usize = top_pad + 1;

        const need_full_clear = !self.initialized or term.rows != self.last_rows or term.cols != self.last_cols or start_row != self.last_start_row;
        if (need_full_clear) {
            clearScreen();
            self.initialized = true;
            self.last_rows = term.rows;
            self.last_cols = term.cols;
            self.last_start_row = start_row;
            for (self.slots) |*slot| slot.* = RenderSlot{ .present = false, .text_ptr = 0, .t = 0, .highlight = false };
        }

        const idx = nearestIndex(lines, cur_t);
        const half = self.visible_lines / 2;
        var base_index: usize = 0;
        if (lines.len != 0) {
            base_index = if (idx > half) idx - half else 0;
            const max_start = if (lines.len > self.visible_lines) lines.len - self.visible_lines else 0;
            if (base_index > max_start) base_index = max_start;
        }

        for (self.slots, 0..) |*slot, i| {
            const line_index = if (lines.len == 0) @as(usize, 0) else base_index + i;
            var line_opt: ?lyrics.Line = null;
            var highlight = false;
            if (lines.len != 0 and line_index < lines.len) {
                line_opt = lines[line_index];
                highlight = line_index == idx;
            }
            if (slotNeedsUpdate(slot.*, line_opt, highlight)) {
                printCenteredLine(start_row + i, line_opt, highlight, col_count, self.show_timestamp, self.dim_inactive);
                rememberSlot(slot, line_opt, highlight);
            }
        }
    }
};

fn getTerminalSize() TerminalSize {
    var size = TerminalSize{ .rows = 24, .cols = 80 };
    const stdout_file = std.io.getStdOut();
    const fd = stdout_file.handle;

    var ws: std.posix.winsize = .{
        .ws_row = 0,
        .ws_col = 0,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    const err = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (std.posix.errno(err) == .SUCCESS and ws.ws_row != 0 and ws.ws_col != 0) {
        size.rows = ws.ws_row;
        size.cols = ws.ws_col;
    }

    return size;
}

fn clearScreen() void {
    std.debug.print("\x1b[2J\x1b[H", .{});
}

fn slotNeedsUpdate(slot: RenderSlot, line_opt: ?lyrics.Line, highlight: bool) bool {
    if (line_opt) |ln| {
        const text_ptr = @intFromPtr(ln.text.ptr);
        return !slot.present or slot.text_ptr != text_ptr or slot.t != ln.t or slot.highlight != highlight;
    } else {
        return slot.present;
    }
}

fn rememberSlot(slot: *RenderSlot, line_opt: ?lyrics.Line, highlight: bool) void {
    if (line_opt) |ln| {
        slot.* = RenderSlot{
            .present = true,
            .text_ptr = @intFromPtr(ln.text.ptr),
            .t = ln.t,
            .highlight = highlight,
        };
    } else {
        slot.* = RenderSlot{ .present = false, .text_ptr = 0, .t = 0, .highlight = false };
    }
}

fn nearestIndex(lines: []const lyrics.Line, t: f64) usize {
    if (lines.len == 0) return 0;
    var lo: usize = 0;
    var hi: usize = lines.len - 1;
    while (lo < hi) {
        const mid = (lo + hi + 1) / 2;
        if (lines[mid].t <= t) lo = mid else hi = mid - 1;
    }
    return lo;
}

fn printCenteredLine(row: usize, line_opt: ?lyrics.Line, highlight: bool, cols: usize, show_timestamp: bool, dim_inactive: bool) void {
    std.debug.print("\x1b[{d};1H", .{row});

    if (line_opt) |ln| {
        var buf: [1024]u8 = undefined;
        const segment = blk: {
            if (show_timestamp) {
                const mm: u64 = @intFromFloat(@floor(ln.t / 60.0));
                const ss: u64 = @intFromFloat(@floor(ln.t - @as(f64, @floatFromInt(mm)) * 60.0));
                const formatted = std.fmt.bufPrint(&buf, "[{d:0>2}:{d:0>2}] {s}", .{ mm, ss, ln.text }) catch null;
                if (formatted) |seg| break :blk seg;
            }
            break :blk ln.text;
        };

        const visual_width = if (cols == 0) segment.len else cols;
        const pad = if (visual_width > segment.len) (visual_width - segment.len) / 2 else 0;

        var i: usize = 0;
        while (i < pad) : (i += 1) {
            std.debug.print(" ", .{});
        }

        if (highlight) {
            std.debug.print("\x1b[7m{s}\x1b[0m", .{segment});
        } else if (dim_inactive) {
            std.debug.print("\x1b[2m{s}\x1b[0m", .{segment});
        } else {
            std.debug.print("{s}", .{segment});
        }
    }

    std.debug.print("\x1b[0m\x1b[K", .{});
}
