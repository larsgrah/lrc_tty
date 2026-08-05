const std = @import("std");

pub const Config = struct {
    show_timestamp: bool,
    visible_lines: usize,
    raw_output: bool,
    dim_inactive: bool,
    player: []u8,
    list_players: bool,
    dump_output: bool,
    artist: ?[]u8,
    title: ?[]u8,
    duration: ?f64,

    pub fn deinit(self: Config, allocator: std.mem.Allocator) void {
        allocator.free(self.player);
        if (self.artist) |v| allocator.free(v);
        if (self.title) |v| allocator.free(v);
    }
};

pub fn parse(allocator: std.mem.Allocator, arena: std.mem.Allocator, proc_args: std.process.Args) !Config {
    // toSlice needs an arena, the result can point into several allocations
    const args = try proc_args.toSlice(arena);

    var show_timestamp = false;
    var visible_lines: usize = 3;
    var raw_output = false;
    var dim_inactive = false;
    var list_players = false;
    var dump_output = false;
    var player_override: ?[]u8 = null;
    errdefer if (player_override) |p| allocator.free(p);

    var artist: ?[]u8 = null;
    errdefer if (artist) |v| allocator.free(v);
    var title: ?[]u8 = null;
    errdefer if (title) |v| allocator.free(v);
    var duration: ?f64 = null;

    var env_player: ?[]u8 = if (std.c.getenv("LRC_TTY_PLAYER")) |v|
        try allocator.dupe(u8, std.mem.span(v))
    else
        null;
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
        } else if (std.mem.eql(u8, arg, "--dump")) {
            dump_output = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--artist")) {
            if (i + 1 >= args.len) {
                std.debug.print("missing value after --artist\n\n", .{});
                usage();
                std.process.exit(1);
            }
            i += 1;
            artist = try allocator.dupe(u8, args[i]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--title")) {
            if (i + 1 >= args.len) {
                std.debug.print("missing value after --title\n\n", .{});
                usage();
                std.process.exit(1);
            }
            i += 1;
            title = try allocator.dupe(u8, args[i]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--duration")) {
            if (i + 1 >= args.len) {
                std.debug.print("missing value after --duration\n\n", .{});
                usage();
                std.process.exit(1);
            }
            i += 1;
            duration = std.fmt.parseFloat(f64, args[i]) catch {
                std.debug.print("invalid --duration value: {s}\n\n", .{args[i]});
                usage();
                std.process.exit(1);
            };
            i += 1;
        } else if (std.mem.eql(u8, arg, "--dim")) {
            dim_inactive = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--list-players")) {
            list_players = true;
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
        .dim_inactive = dim_inactive,
        .player = player_buf,
        .list_players = list_players,
        .dump_output = dump_output,
        .artist = artist,
        .title = title,
        .duration = duration,
    };
}

pub fn usage() void {
    std.debug.print(
        "usage: lrc_tty [--timestamp] [--player NAME]\n" ++
            "       lrc_tty [--help]\n\n" ++
            "Options:\n" ++
            "  --timestamp    Prefix each line with [mm:ss].\n" ++
            "  --player NAME  Select MPRIS player target (default env LRC_TTY_PLAYER or playerctld).\n" ++
            "  --lines NUM    Display NUM lyric rows (default 3).\n" ++
            "  --raw          Print the current lyric line and exit.\n" ++
            "  --dump         Print the whole .lrc for the track and exit.\n" ++
            "  --artist NAME  Look this artist up instead of asking the player.\n" ++
            "  --title NAME   Look this title up instead of asking the player.\n" ++
            "  --duration SEC Track length, used to pick between lrclib matches.\n" ++
            "  --dim          Dim non-focused lines in the TUI.\n" ++
            "  --list-players Show detected MPRIS players and exit.\n" ++
            "  -h, --help     Show this help text.\n",
        .{},
    );
}
