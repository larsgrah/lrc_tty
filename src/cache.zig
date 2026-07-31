const std = @import("std");

fn getEnvOwned(allocator: std.mem.Allocator, name: [*:0]const u8) ?[]u8 {
    const v = std.c.getenv(name) orelse return null;
    return allocator.dupe(u8, std.mem.span(v)) catch null;
}

fn resolveCacheRoot(allocator: std.mem.Allocator) ![]u8 {
    if (getEnvOwned(allocator, "LRC_TTY_CACHE")) |path| {
        return path;
    }

    if (getEnvOwned(allocator, "XDG_CACHE_HOME")) |base| {
        defer allocator.free(base);
        return std.fs.path.join(allocator, &.{ base, "lrc_tty" });
    }

    if (getEnvOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, ".cache", "lrc_tty" });
    }

    return error.NoCacheDir;
}

fn computeHash(track_id: []const u8, artist: []const u8, title: []const u8, length: f64) u64 {
    var hasher = std.hash.XxHash64.init(0);
    if (track_id.len != 0) {
        hasher.update(track_id);
    } else {
        hasher.update(artist);
        hasher.update("|");
        hasher.update(title);
    }
    const len_bits: u64 = @bitCast(length);
    hasher.update(std.mem.asBytes(&len_bits));
    return hasher.final();
}

fn cachePath(
    allocator: std.mem.Allocator,
    io: std.Io,
    track_id: []const u8,
    artist: []const u8,
    title: []const u8,
    length: f64,
) ![]u8 {
    const root = try resolveCacheRoot(allocator);
    defer allocator.free(root);

    try std.Io.Dir.cwd().createDirPath(io, root);

    const hash = computeHash(track_id, artist, title, length);
    return std.fmt.allocPrint(allocator, "{s}/track-{x:016}.lrc", .{ root, hash });
}

pub fn load(
    allocator: std.mem.Allocator,
    io: std.Io,
    track_id: []const u8,
    artist: []const u8,
    title: []const u8,
    length: f64,
) !?[]u8 {
    const path = cachePath(allocator, io, track_id, artist, title, length) catch return null;
    defer allocator.free(path);

    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
}

pub fn store(
    allocator: std.mem.Allocator,
    io: std.Io,
    track_id: []const u8,
    artist: []const u8,
    title: []const u8,
    length: f64,
    data: []const u8,
) !void {
    const path = try cachePath(allocator, io, track_id, artist, title, length);
    defer allocator.free(path);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}
