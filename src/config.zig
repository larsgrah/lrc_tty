const std = @import("std");

pub const Config = struct {
    show_timestamp: bool,
    visible_lines: usize,
    raw_output: bool,
    player: []u8,

    pub fn deinit(self: Config, allocator: std.mem.Allocator) void {
        allocator.free(self.player);
    }
};

pub fn parse(allocator: std.mem.Allocator) !Config {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var show_timestamp = false;
    var visible_lines: usize = 3;
    var raw_output = false;
    var player_override: ?[]u8 = null;
    errdefer if (player_override) |p| allocator.free(p);

    var env_player = std.process.getEnvVarOwned(allocator, "LRC_TTY_PLAYER") catch null;
    errdefer if (env_player) |p| allocator.free(p);

    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--timestamp")) {
            show_timestamp = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--player")) {
            if (i + 1 >= args.len) {
                std.debug.print("missing value after --player\n\n", .{});
                usage();
                std.process.exit(1);
            }
            i += 1;
            player_override = try allocator.dupe(u8, args[i]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--lines")) {
            if (i + 1 >= args.len) {
                std.debug.print("missing value after --lines\n\n", .{});
                usage();
                std.process.exit(1);
            }
            i += 1;
            const parsed = std.fmt.parseUnsigned(usize, args[i], 10) catch {
                std.debug.print("invalid --lines value: {s}\n\n", .{args[i]});
                usage();
                std.process.exit(1);
            };
            if (parsed == 0) {
                std.debug.print("--lines must be at least 1\n\n", .{});
                usage();
                std.process.exit(1);
            }
            visible_lines = parsed;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--raw")) {
            raw_output = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--help")) {
            usage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-h")) {
            usage();
            std.process.exit(0);
        } else {
            std.debug.print("unknown argument: {s}\n\n", .{arg});
            usage();
            std.process.exit(1);
        }
    }

    var player_buf: []u8 = undefined;
    if (player_override) |p| {
        player_buf = p;
        if (env_player) |ep| {
            allocator.free(ep);
            env_player = null;
        }
    } else if (env_player) |ep| {
        player_buf = ep;
        env_player = null;
    } else {
        player_buf = try allocator.dupe(u8, "playerctld");
    }

    return Config{
        .show_timestamp = show_timestamp,
        .visible_lines = visible_lines,
        .raw_output = raw_output,
        .player = player_buf,
    };
}

pub fn usage() void {
    std.debug.print(
        "usage: lrc_tty [--timestamp] [--player NAME]\n" ++
            "       lrc_tty [--help]\n\n" ++
            "Options:\n" ++
            "  --timestamp    Prefix each line with [mm:ss].\n" ++
            "  --player NAME  Select playerctl -p target (default env LRC_TTY_PLAYER or playerctld).\n" ++
            "  --lines NUM    Display NUM lyric rows (default 3).\n" ++
            "  --raw          Print the current lyric line and exit.\n" ++
            "  -h, --help     Show this help text.\n",
        .{},
    );
}
