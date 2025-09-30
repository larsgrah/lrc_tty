const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "lrc_tty",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.linkSystemLibrary("dbus-1");

    var code: u8 = undefined;
    const dbus_cflags = b.runAllowFail(&.{ "pkg-config", "--cflags-only-I", "dbus-1" }, &code, .Inherit) catch |err| {
        std.debug.print("failed to query pkg-config for dbus-1 ({s}); ensure pkg-config and libdbus-1 development headers are installed\n", .{@errorName(err)});
        @panic("pkg-config dbus-1");
    };
    defer b.allocator.free(dbus_cflags);

    parsePkgConfigFlags(exe, dbus_cflags);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run lrc_tty");
    run_step.dependOn(&run_cmd.step);
}

fn parsePkgConfigFlags(exe: *std.Build.Step.Compile, flags: []const u8) void {
    var it = std.mem.tokenizeAny(u8, flags, " \n\r\t");

    while (it.next()) |flag| {
        if (flag.len < 2 or flag[0] != '-') continue;
        const tag = flag[1];

        switch (tag) {
            'I' => {
                if (flag.len == 2) {
                    const path = it.next() orelse continue;
                    addInclude(exe, path);
                } else {
                    const path = flag[2..];
                    addInclude(exe, path);
                }
            },
            'D' => {
                if (flag.len == 2) {
                    const value = it.next() orelse continue;
                    addMacro(exe, value);
                } else {
                    const value = flag[2..];
                    addMacro(exe, value);
                }
            },
            'W' => {
                // ignore warning flags from pkg-config
            },
            else => {},
        }
    }
}

fn addInclude(exe: *std.Build.Step.Compile, path: []const u8) void {
    if (std.mem.startsWith(u8, path, "-I")) {
        addInclude(exe, path[2..]);
        return;
    }
    if (path.len == 0) return;
    exe.addIncludePath(.{ .cwd_relative = exe.step.owner.dupe(path) });
}

fn addMacro(exe: *std.Build.Step.Compile, macro: []const u8) void {
    if (std.mem.startsWith(u8, macro, "-D")) {
        addMacro(exe, macro[2..]);
        return;
    }
    if (macro.len == 0) return;
    const eq = std.mem.indexOfScalar(u8, macro, '=');
    if (eq) |idx| {
        const name = macro[0..idx];
        const value = macro[idx + 1 ..];
        exe.root_module.addCMacro(name, value);
    } else {
        exe.root_module.addCMacro(macro, "1");
    }
}
