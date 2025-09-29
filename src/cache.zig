const std = @import("std");

fn resolveCacheRoot(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "LRC_TTY_CACHE")) |path| {
        return path;
    } else |_| {}

    if (std.process.getEnvVarOwned(allocator, "XDG_CACHE_HOME")) |base| {
        defer allocator.free(base);
        return std.fs.path.join(allocator, &.{ base, "lrc_tty" });
    } else |_| {}

    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, ".cache", "lrc_tty" });
    } else |_| {}

    return std.fs.getAppDataDir(allocator, "lrc_tty");
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
    track_id: []const u8,
    artist: []const u8,
    title: []const u8,
    length: f64,
) ![]u8 {
    const root = try resolveCacheRoot(allocator);
    defer allocator.free(root);

    try ensureDirExists(root);

    const hash = computeHash(track_id, artist, title, length);
    return std.fmt.allocPrint(allocator, "{s}/track-{x:016}.lrc", .{ root, hash });
}

fn ensureDirExists(path: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        std.fs.makeDirAbsolute(path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    } else {
        try std.fs.cwd().makePath(path);
    }
}

pub fn load(
    allocator: std.mem.Allocator,
    track_id: []const u8,
    artist: []const u8,
    title: []const u8,
    length: f64,
) !?[]u8 {
    const path = cachePath(allocator, track_id, artist, title, length) catch return null;
    defer allocator.free(path);

    const file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const stat = try file.stat();
    var buffer = try allocator.alloc(u8, @intCast(stat.size));
    const read_bytes = try file.readAll(buffer);
    return buffer[0..read_bytes];
}

pub fn store(
    allocator: std.mem.Allocator,
    track_id: []const u8,
    artist: []const u8,
    title: []const u8,
    length: f64,
    data: []const u8,
) !void {
    const path = try cachePath(allocator, track_id, artist, title, length);
    defer allocator.free(path);

    const file = try std.fs.createFileAbsolute(path, .{ .truncate = true, .read = false });
    defer file.close();
    try file.writeAll(data);
}
