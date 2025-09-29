const std = @import("std");

pub const Line = struct {
    t: f64,
    text: []const u8,
};

pub const FetchResult = struct {
    lrc: []u8,
    src: []const u8,
};

fn httpGetAlloc(allocator: std.mem.Allocator, url: []const u8, timeout_ms: u64) ![]u8 {
    _ = timeout_ms; // TODO: plumb through zig std http client timeouts once available

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body = std.ArrayList(u8).init(allocator);
    errdefer body.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &body },
        .max_append_size = 1 << 20,
    });

    if (result.status != .ok) return error.BadStatus;

    return body.toOwnedSlice();
}

fn urlEncode(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    for (s) |c| {
        const is_safe = std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~';
        if (is_safe) try out.append(c) else try out.writer().print("%{X:0>2}", .{@as(u8, c)});
    }
    return out.toOwnedSlice();
}

pub fn fetchLrclib(
    allocator: std.mem.Allocator,
    artist: []const u8,
    title: []const u8,
    length: f64,
) ?FetchResult {
    const base = "https://lrclib.net/api";

    const a = urlEncode(allocator, artist) catch return null;
    defer allocator.free(a);
    const t = urlEncode(allocator, title) catch return null;
    defer allocator.free(t);

    var url_buf = std.ArrayList(u8).init(allocator);
    defer url_buf.deinit();

    // direct /get
    url_buf.clearRetainingCapacity();
    url_buf.writer().print("{s}/get?artist_name={s}&track_name={s}", .{ base, a, t }) catch return null;

    if (httpGetAlloc(allocator, url_buf.items, 6000)) |body| {
        defer allocator.free(body);
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch null;
        defer if (parsed) |p| p.deinit();
        if (parsed) |p| switch (p.value) {
            .object => |obj| {
                if (obj.get("syncedLyrics")) |synp| {
                    switch (synp) {
                        .string => |s| return FetchResult{ .lrc = allocator.dupe(u8, s) catch return null, .src = "lrclib:get" },
                        else => {},
                    }
                }
                if (obj.get("plainLyrics")) |plp| {
                    switch (plp) {
                        .string => |s| return FetchResult{ .lrc = allocator.dupe(u8, s) catch return null, .src = "lrclib:get" },
                        else => {},
                    }
                }
            },
            else => {},
        };
    } else |_| {}

    // fallback /search
    url_buf.clearRetainingCapacity();
    url_buf.writer().print("{s}/search?track_name={s}&artist_name={s}", .{ base, t, a }) catch return null;

    if (httpGetAlloc(allocator, url_buf.items, 8000)) |body| {
        defer allocator.free(body);
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch null;
        defer if (parsed) |p| p.deinit();
        if (parsed) |p| switch (p.value) {
            .array => |arr| {
                var best_score: f64 = -1e9;
                var best_lrc: ?[]const u8 = null;

                for (arr.items) |item| {
                    const obj = switch (item) {
                        .object => |o| o,
                        else => continue,
                    };

                    var lrc_txt: ?[]const u8 = null;
                    if (obj.get("syncedLyrics")) |synp| {
                        switch (synp) {
                            .string => |s| {
                                lrc_txt = s;
                            },
                            else => {},
                        }
                    }
                    if (lrc_txt == null) {
                        if (obj.get("plainLyrics")) |plp| {
                            switch (plp) {
                                .string => |s| {
                                    lrc_txt = s;
                                },
                                else => {},
                            }
                        }
                    }
                    if (lrc_txt == null) continue;

                    var score: f64 = 0;
                    var dur: f64 = 0;

                    if (obj.get("duration")) |dp| {
                        switch (dp) {
                            .float => |f| dur = f,
                            .integer => |i| dur = @floatFromInt(i),
                            else => {},
                        }
                    }
                    score -= @abs(dur - length);

                    if (obj.get("artistName")) |ap| {
                        switch (ap) {
                            .string => |s| {
                                if (std.ascii.eqlIgnoreCase(s, artist)) score += 5;
                            },
                            else => {},
                        }
                    }
                    if (obj.get("trackName")) |tp| {
                        switch (tp) {
                            .string => |s| {
                                if (std.ascii.eqlIgnoreCase(s, title)) score += 5;
                            },
                            else => {},
                        }
                    }

                    if (score > best_score) {
                        best_score = score;
                        best_lrc = lrc_txt;
                    }
                }

                if (best_lrc) |l| {
                    return FetchResult{ .lrc = allocator.dupe(u8, l) catch return null, .src = "lrclib:search" };
                }
            },
            else => {},
        };
    } else |_| {}

    return null;
}

pub fn parseLrc(allocator: std.mem.Allocator, text: []const u8) ![]Line {
    var lines = std.ArrayList(Line).init(allocator);
    errdefer {
        for (lines.items) |ln| allocator.free(ln.text);
        lines.deinit();
    }

    var it = std.mem.tokenizeScalar(u8, text, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \r");
        if (line.len == 0) continue;

        // collect all [mm:ss.xx]
        var start: usize = 0;
        var times = std.ArrayList(f64).init(allocator);
        defer times.deinit();

        while (true) {
            if (std.mem.indexOf(u8, line[start..], "[")) |lb| {
                const open = start + lb;
                if (std.mem.indexOf(u8, line[open..], "]")) |rb_rel| {
                    const rb = open + rb_rel;
                    const tag = line[open + 1 .. rb];

                    var mm: u64 = 0;
                    var ss: u64 = 0;
                    var cs: u64 = 0;
                    if (std.mem.indexOfScalar(u8, tag, ':')) |colon| {
                        mm = std.fmt.parseUnsigned(u64, tag[0..colon], 10) catch 0;
                        var rest = tag[colon + 1 ..];
                        const dot_idx = std.mem.indexOfScalar(u8, rest, '.');
                        if (dot_idx) |di| {
                            ss = std.fmt.parseUnsigned(u64, rest[0..di], 10) catch 0;
                            cs = std.fmt.parseUnsigned(u64, rest[di + 1 ..], 10) catch 0;
                        } else {
                            ss = std.fmt.parseUnsigned(u64, rest, 10) catch 0;
                        }
                        const t_value: f64 = @as(f64, @floatFromInt(mm * 60 + ss)) + (@as(f64, @floatFromInt(cs)) / 100.0);
                        try times.append(t_value);
                    }
                    start = rb + 1;
                    continue;
                }
            }
            break;
        }

        const last_rb = std.mem.lastIndexOfScalar(u8, line, ']') orelse 0;
        const lyric = std.mem.trim(u8, line[last_rb + 1 ..], " ");
        if (lyric.len == 0 and times.items.len == 0) continue;

        if (times.items.len == 0) {
            try lines.append(Line{ .t = 0, .text = try allocator.dupe(u8, lyric) });
        } else {
            for (times.items) |tsec| {
                try lines.append(Line{ .t = tsec, .text = try allocator.dupe(u8, lyric) });
            }
        }
    }

    std.sort.block(Line, lines.items, {}, struct {
        fn lessThan(_: void, a: Line, b: Line) bool {
            return a.t < b.t or (a.t == b.t and std.mem.lessThan(u8, a.text, b.text));
        }
    }.lessThan);

    return lines.toOwnedSlice();
}

pub fn synthTimeline(allocator: std.mem.Allocator, text: []const u8) ![]Line {
    var out = std.ArrayList(Line).init(allocator);
    errdefer {
        for (out.items) |ln| allocator.free(ln.text);
        out.deinit();
    }
    var it = std.mem.tokenizeScalar(u8, text, '\n');
    var t: f64 = 0.0;
    while (it.next()) |raw| {
        const s = std.mem.trim(u8, raw, " \r");
        if (s.len == 0) continue;
        try out.append(Line{ .t = t, .text = try allocator.dupe(u8, s) });
        t += 3.2;
    }
    return out.toOwnedSlice();
}
