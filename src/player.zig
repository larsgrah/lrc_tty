const std = @import("std");

pub const Meta = struct {
    title: []u8,
    artist: []u8,
    album: []u8,
    length: f64,
    trackid: []u8,

    pub fn deinit(self: Meta, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.artist);
        allocator.free(self.album);
        allocator.free(self.trackid);
    }
};

fn runCmd(allocator: std.mem.Allocator, cmdline: []const u8) ![]u8 {
    // simple argv split by spaces; sufficient for our known calls
    var it = std.mem.tokenizeAny(u8, cmdline, " ");
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();
    while (it.next()) |tok| try args.append(tok);

    var child = std.process.Child.init(args.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    var reader = child.stdout.?.reader();
    try reader.readAllArrayList(&out, 1 << 16);

    _ = try child.wait();
    return out.toOwnedSlice();
}

fn playerctl(allocator: std.mem.Allocator, player: []const u8, args: []const u8) ![]u8 {
    var buff = std.ArrayList(u8).init(allocator);
    defer buff.deinit();
    try buff.writer().print("playerctl -p {s} {s}", .{ player, args });
    return runCmd(allocator, buff.items);
}

pub fn getPosition(allocator: std.mem.Allocator, player: []const u8) f64 {
    if (playerctl(allocator, player, "position")) |out| {
        defer allocator.free(out);
        return std.fmt.parseFloat(f64, std.mem.trim(u8, out, " \n\r\t")) catch 0.0;
    } else |_| return 0.0;
}

pub fn getStatus(allocator: std.mem.Allocator, player: []const u8) []const u8 {
    if (playerctl(allocator, player, "status")) |out| {
        defer allocator.free(out);
        return std.mem.trim(u8, out, " \n\r\t");
    } else |_| return "Stopped";
}

pub fn getMeta(allocator: std.mem.Allocator, player: []const u8) Meta {
    var m = Meta{
        .title = allocator.dupe(u8, "") catch unreachable,
        .artist = allocator.dupe(u8, "") catch unreachable,
        .album = allocator.dupe(u8, "") catch unreachable,
        .length = 0.0,
        .trackid = allocator.dupe(u8, "") catch unreachable,
    };

    const keys = [_][]const u8{
        "metadata xesam:title",
        "metadata xesam:artist",
        "metadata xesam:album",
        "metadata mpris:length",
        "metadata mpris:trackid",
    };

    inline for (keys) |k| {
        if (playerctl(allocator, player, k)) |out| {
            defer allocator.free(out);
            const val = std.mem.trim(u8, out, " \n\r\t");
            if (std.mem.eql(u8, k, "metadata xesam:title")) {
                m.title = allocator.dupe(u8, val) catch m.title;
            } else if (std.mem.eql(u8, k, "metadata xesam:artist")) {
                var s = std.mem.trim(u8, val, "[] ");
                if (std.mem.indexOfScalar(u8, s, ',')) |idx| s = s[0..idx];
                m.artist = allocator.dupe(u8, s) catch m.artist;
            } else if (std.mem.eql(u8, k, "metadata xesam:album")) {
                m.album = allocator.dupe(u8, val) catch m.album;
            } else if (std.mem.eql(u8, k, "metadata mpris:length")) {
                const ns = std.fmt.parseInt(i128, val, 10) catch 0;
                m.length = @as(f64, @floatFromInt(ns)) / 1_000_000.0;
            } else if (std.mem.eql(u8, k, "metadata mpris:trackid")) {
                m.trackid = allocator.dupe(u8, val) catch m.trackid;
            }
        } else |_| {}
    }
    return m;
}
