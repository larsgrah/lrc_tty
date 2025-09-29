const std = @import("std");
const config = @import("config.zig");
const runtime = @import("runtime.zig");
const player = @import("player.zig");
const lyrics = @import("lyrics.zig");
const render = @import("render.zig");
const cache = @import("cache.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const gpa_status = gpa.deinit();
        std.debug.assert(gpa_status == .ok);
    }
    const alloc = gpa.allocator();

    const cfg = try config.parse(alloc);
    defer cfg.deinit(alloc);

    if (cfg.raw_output) {
        try runRaw(alloc, cfg);
        return;
    }

    try runtime.installSignalHandlers();
    std.debug.print("\x1b[?25l", .{});
    defer std.debug.print("\x1b[?25h", .{});

    const poll = blk: {
        if (std.process.getEnvVarOwned(alloc, "LRC_TTY_POLL")) |v| {
            defer alloc.free(v);
            break :blk std.fmt.parseFloat(f64, v) catch 0.12;
        } else |_| break :blk 0.12;
    };
    const sleep_ns: u64 = @intFromFloat(poll * @as(f64, @floatFromInt(std.time.ns_per_s)));

    var last_track = try alloc.dupe(u8, "");
    defer alloc.free(last_track);

    var lines: []lyrics.Line = &[_]lyrics.Line{};
    var lines_owned = false;

    var src = try alloc.dupe(u8, "");
    var title = try alloc.dupe(u8, "");
    var artist = try alloc.dupe(u8, "");
    var album = try alloc.dupe(u8, "");

    defer {
        if (lines_owned) {
            freeLines(alloc, lines);
        }
        alloc.free(src);
        alloc.free(title);
        alloc.free(artist);
        alloc.free(album);
    }

    var renderer = try render.RenderState.init(alloc, cfg.show_timestamp, cfg.visible_lines);
    defer renderer.deinit();
    renderer.reset();

    while (true) {
        if (runtime.shouldExit()) break;

        const meta = player.getMeta(alloc, cfg.player);
        defer meta.deinit(alloc);

        const status = player.getStatus(alloc, cfg.player);
        const pos = player.getPosition(alloc, cfg.player);

        if (!std.mem.eql(u8, meta.trackid, last_track)) {
            alloc.free(last_track);
            last_track = try alloc.dupe(u8, meta.trackid);

            alloc.free(title);
            title = try alloc.dupe(u8, meta.title);
            alloc.free(artist);
            artist = try alloc.dupe(u8, meta.artist);
            alloc.free(album);
            album = try alloc.dupe(u8, meta.album);

            if (lines_owned) {
                freeLines(alloc, lines);
                lines_owned = false;
            }
            alloc.free(src);
            src = try alloc.dupe(u8, "");

            const cached_opt = cache.load(alloc, meta.trackid, artist, title, meta.length) catch null;
            if (cached_opt) |cached| {
                defer alloc.free(cached);
                if (std.mem.indexOfScalar(u8, cached, '[') != null) {
                    lines = try lyrics.parseLrc(alloc, cached);
                } else {
                    lines = try lyrics.synthTimeline(alloc, cached);
                }
                lines_owned = true;
                alloc.free(src);
                src = try alloc.dupe(u8, "lrclib:cache");
            } else if (lyrics.fetchLrclib(alloc, artist, title, meta.length)) |res| {
                defer alloc.free(res.lrc);
                alloc.free(src);
                src = try alloc.dupe(u8, res.src);

                if (std.mem.indexOfScalar(u8, res.lrc, '[') != null) {
                    lines = try lyrics.parseLrc(alloc, res.lrc);
                } else {
                    lines = try lyrics.synthTimeline(alloc, res.lrc);
                }
                lines_owned = true;
                cache.store(alloc, meta.trackid, artist, title, meta.length, res.lrc) catch {};
            } else {
                const no = "(no lyrics)";
                lines = try alloc.alloc(lyrics.Line, 1);
                lines[0] = lyrics.Line{ .t = 0, .text = try alloc.dupe(u8, no) };
                lines_owned = true;
                alloc.free(src);
                src = try alloc.dupe(u8, "lrclib:none");
            }

            renderer.reset();
        }

        renderer.draw(title, artist, album, status, pos, lines, src);

        if (runtime.shouldExit()) break;
        runtime.sleepWithExit(sleep_ns);
    }
}

fn freeLines(allocator: std.mem.Allocator, list: []lyrics.Line) void {
    for (list) |ln| allocator.free(ln.text);
    allocator.free(list);
}

fn runRaw(allocator: std.mem.Allocator, cfg: config.Config) !void {
    const meta = player.getMeta(allocator, cfg.player);
    defer meta.deinit(allocator);

    const pos = player.getPosition(allocator, cfg.player);

    var lines: []lyrics.Line = &[_]lyrics.Line{};
    var lines_owned = false;
    defer if (lines_owned) freeLines(allocator, lines);

    const cached_opt = cache.load(allocator, meta.trackid, meta.artist, meta.title, meta.length) catch null;
    if (cached_opt) |cached| {
        defer allocator.free(cached);
        if (std.mem.indexOfScalar(u8, cached, '[') != null) {
            lines = try lyrics.parseLrc(allocator, cached);
        } else {
            lines = try lyrics.synthTimeline(allocator, cached);
        }
        lines_owned = true;
    } else if (lyrics.fetchLrclib(allocator, meta.artist, meta.title, meta.length)) |res| {
        defer allocator.free(res.lrc);
        if (std.mem.indexOfScalar(u8, res.lrc, '[') != null) {
            lines = try lyrics.parseLrc(allocator, res.lrc);
        } else {
            lines = try lyrics.synthTimeline(allocator, res.lrc);
        }
        lines_owned = true;
        cache.store(allocator, meta.trackid, meta.artist, meta.title, meta.length, res.lrc) catch {};
    } else {
        lines = try allocator.alloc(lyrics.Line, 1);
        lines[0] = lyrics.Line{ .t = 0, .text = try allocator.dupe(u8, "(no lyrics)") };
        lines_owned = true;
    }

    const stdout = std.io.getStdOut().writer();
    if (lines.len == 0) {
        try stdout.print("(no lyrics)\n", .{});
        return;
    }

    const idx = nearestLineIndex(lines, pos);
    const line = lines[idx];
    if (cfg.show_timestamp) {
        const mm: u64 = @intFromFloat(@floor(line.t / 60.0));
        const ss: u64 = @intFromFloat(@floor(line.t - @as(f64, @floatFromInt(mm)) * 60.0));
        try stdout.print("[{d:0>2}:{d:0>2}] {s}\n", .{ mm, ss, line.text });
    } else {
        try stdout.print("{s}\n", .{line.text});
    }
}

fn nearestLineIndex(lines: []const lyrics.Line, t: f64) usize {
    if (lines.len == 0) return 0;
    var lo: usize = 0;
    var hi: usize = lines.len - 1;
    while (lo < hi) {
        const mid = (lo + hi + 1) / 2;
        if (lines[mid].t <= t) lo = mid else hi = mid - 1;
    }
    return lo;
}
