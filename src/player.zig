const std = @import("std");

const c = @cImport({
    @cInclude("dbus/dbus.h");
});

const object_path: [:0]const u8 = "/org/mpris/MediaPlayer2";
const properties_iface: [:0]const u8 = "org.freedesktop.DBus.Properties";
const player_iface: [:0]const u8 = "org.mpris.MediaPlayer2.Player";
const method_get: [:0]const u8 = "Get";
const properties_changed: [:0]const u8 = "PropertiesChanged";
const dbus_service: [:0]const u8 = "org.freedesktop.DBus";
const dbus_path: [:0]const u8 = "/org/freedesktop/DBus";
const dbus_iface: [:0]const u8 = "org.freedesktop.DBus";
const dbus_list_names: [:0]const u8 = "ListNames";
const mpris_prefix: []const u8 = "org.mpris.MediaPlayer2.";
const c_allocator = std.heap.c_allocator;

var connection: ?*c.DBusConnection = null;
var match_rule: ?[:0]u8 = null;
var match_player: ?[]u8 = null;

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

fn resetConnection() void {
    if (match_rule) |rule| {
        c_allocator.free(rule);
        match_rule = null;
    }
    if (match_player) |p| {
        c_allocator.free(p);
        match_player = null;
    }
    if (connection) |conn| {
        c.dbus_connection_unref(conn);
        connection = null;
    }
}

fn ensureConnection() !*c.DBusConnection {
    if (connection) |conn| return conn;

    const conn = c.dbus_bus_get(c.DBUS_BUS_SESSION, null) orelse return error.DBusConnectFailed;
    c.dbus_connection_set_exit_on_disconnect(conn, 0);
    connection = conn;
    return conn;
}

fn ensurePropertiesMatch(player: []const u8) !*c.DBusConnection {
    const trimmed = std.mem.trim(u8, player, " ");
    if (trimmed.len == 0) return error.InvalidPlayerName;

    const conn = try ensureConnection();

    if (match_player) |current| {
        if (std.mem.eql(u8, trimmed, current)) return conn;
        if (match_rule) |rule| {
            c.dbus_bus_remove_match(conn, rule.ptr, null);
            c.dbus_connection_flush(conn);
            c_allocator.free(rule);
            match_rule = null;
        }
        c_allocator.free(current);
        match_player = null;
    }

    const new_player = try c_allocator.dupe(u8, trimmed);
    errdefer c_allocator.free(new_player);

    const rule = try std.fmt.allocPrintZ(
        c_allocator,
        "type='signal',interface='{s}',member='{s}',path='{s}',sender='org.mpris.MediaPlayer2.{s}'",
        .{ properties_iface, properties_changed, object_path, trimmed },
    );
    errdefer c_allocator.free(rule);

    c.dbus_bus_add_match(conn, rule.ptr, null);
    c.dbus_connection_flush(conn);
    match_rule = rule;
    match_player = new_player;
    return conn;
}

fn busName(allocator: std.mem.Allocator, player: []const u8) ![:0]u8 {
    const trimmed = std.mem.trim(u8, player, " ");
    if (trimmed.len == 0) return error.InvalidPlayerName;
    return std.fmt.allocPrintZ(allocator, "org.mpris.MediaPlayer2.{s}", .{trimmed});
}

fn sendPropertyGet(
    allocator: std.mem.Allocator,
    player: []const u8,
    property: [:0]const u8,
) !*c.DBusMessage {
    const conn = try ensureConnection();
    const dest = try busName(allocator, player);
    defer allocator.free(dest);

    const dest_ptr: [*:0]const u8 = dest.ptr;
    const msg = c.dbus_message_new_method_call(dest_ptr, object_path.ptr, properties_iface.ptr, method_get.ptr);
    if (msg == null) return error.OutOfMemory;
    const owned_msg = msg.?;
    defer c.dbus_message_unref(owned_msg);

    var iter = c.DBusMessageIter{};
    c.dbus_message_iter_init_append(owned_msg, &iter);

    var iface_ptr = player_iface.ptr;
    const iface_arg: ?*const anyopaque = @ptrCast(&iface_ptr);
    if (c.dbus_message_iter_append_basic(&iter, c.DBUS_TYPE_STRING, iface_arg) == 0)
        return error.DBusMessageAppend;

    var property_ptr = property.ptr;
    const property_arg: ?*const anyopaque = @ptrCast(&property_ptr);
    if (c.dbus_message_iter_append_basic(&iter, c.DBUS_TYPE_STRING, property_arg) == 0)
        return error.DBusMessageAppend;

    const reply = c.dbus_connection_send_with_reply_and_block(conn, owned_msg, -1, null);
    if (reply == null) {
        resetConnection();
        return error.DBusCallFailed;
    }
    const owned_reply = reply.?;
    return owned_reply;
}

fn initVariant(reply: *c.DBusMessage, variant: *c.DBusMessageIter) !c_int {
    var iter = c.DBusMessageIter{};
    if (c.dbus_message_iter_init(reply, &iter) == 0) return error.InvalidReply;
    if (c.dbus_message_iter_get_arg_type(&iter) != c.DBUS_TYPE_VARIANT) return error.TypeMismatch;
    c.dbus_message_iter_recurse(&iter, variant);
    return c.dbus_message_iter_get_arg_type(variant);
}

fn fetchStringProperty(allocator: std.mem.Allocator, player: []const u8, property: [:0]const u8) ![]u8 {
    const reply = try sendPropertyGet(allocator, player, property);
    defer c.dbus_message_unref(reply);

    var variant = c.DBusMessageIter{};
    const t = try initVariant(reply, &variant);
    if (t != c.DBUS_TYPE_STRING and t != c.DBUS_TYPE_OBJECT_PATH) return error.TypeMismatch;

    var str_ptr: [*:0]const u8 = undefined;
    const str_arg: ?*anyopaque = @ptrCast(&str_ptr);
    c.dbus_message_iter_get_basic(&variant, str_arg);
    const slice = std.mem.span(str_ptr);
    return allocator.dupe(u8, slice);
}

fn fetchInt64Property(allocator: std.mem.Allocator, player: []const u8, property: [:0]const u8) !i64 {
    const reply = try sendPropertyGet(allocator, player, property);
    defer c.dbus_message_unref(reply);

    var variant = c.DBusMessageIter{};
    const t = try initVariant(reply, &variant);
    if (t != c.DBUS_TYPE_INT64 and t != c.DBUS_TYPE_UINT64) return error.TypeMismatch;

    var value: i64 = 0;
    if (t == c.DBUS_TYPE_INT64) {
        c.dbus_message_iter_get_basic(&variant, &value);
    } else {
        var uvalue: u64 = 0;
        c.dbus_message_iter_get_basic(&variant, &uvalue);
        value = @as(i64, @intCast(uvalue));
    }
    return value;
}

fn fetchMetadata(allocator: std.mem.Allocator, player: []const u8, meta: *Meta) !void {
    const property: [:0]const u8 = "Metadata";
    const reply = try sendPropertyGet(allocator, player, property);
    defer c.dbus_message_unref(reply);

    var variant = c.DBusMessageIter{};
    const t = try initVariant(reply, &variant);
    if (t != c.DBUS_TYPE_ARRAY) return error.TypeMismatch;

    var dict_iter = c.DBusMessageIter{};
    c.dbus_message_iter_recurse(&variant, &dict_iter);

    while (c.dbus_message_iter_get_arg_type(&dict_iter) != c.DBUS_TYPE_INVALID) {
        var entry_iter = c.DBusMessageIter{};
        c.dbus_message_iter_recurse(&dict_iter, &entry_iter);

        if (c.dbus_message_iter_get_arg_type(&entry_iter) != c.DBUS_TYPE_STRING) {
            if (c.dbus_message_iter_next(&dict_iter) == 0) break;
            continue;
        }

        var key_ptr: [*:0]const u8 = undefined;
        const key_arg: ?*anyopaque = @ptrCast(&key_ptr);
        c.dbus_message_iter_get_basic(&entry_iter, key_arg);
        const key = std.mem.span(key_ptr);

        if (c.dbus_message_iter_next(&entry_iter) == 0) {
            if (c.dbus_message_iter_next(&dict_iter) == 0) break;
            continue;
        }

        if (c.dbus_message_iter_get_arg_type(&entry_iter) != c.DBUS_TYPE_VARIANT) {
            if (c.dbus_message_iter_next(&dict_iter) == 0) break;
            continue;
        }

        var value_iter = c.DBusMessageIter{};
        c.dbus_message_iter_recurse(&entry_iter, &value_iter);
        const value_type = c.dbus_message_iter_get_arg_type(&value_iter);

        if (std.mem.eql(u8, key, "xesam:title")) {
            if (value_type == c.DBUS_TYPE_STRING) {
                var v_ptr: [*:0]const u8 = undefined;
                const v_arg: ?*anyopaque = @ptrCast(&v_ptr);
                c.dbus_message_iter_get_basic(&value_iter, v_arg);
                const slice = std.mem.span(v_ptr);
                if (allocator.dupe(u8, slice)) |copy| {
                    allocator.free(meta.title);
                    meta.title = copy;
                } else |_| {}
            }
        } else if (std.mem.eql(u8, key, "xesam:artist")) {
            if (value_type == c.DBUS_TYPE_ARRAY) {
                var artist_iter = c.DBusMessageIter{};
                c.dbus_message_iter_recurse(&value_iter, &artist_iter);
                if (c.dbus_message_iter_get_arg_type(&artist_iter) == c.DBUS_TYPE_STRING) {
                    var a_ptr: [*:0]const u8 = undefined;
                    const a_arg: ?*anyopaque = @ptrCast(&a_ptr);
                    c.dbus_message_iter_get_basic(&artist_iter, a_arg);
                    const slice = std.mem.span(a_ptr);
                    const trimmed = std.mem.trim(u8, slice, " ");
                    const chosen = blk: {
                        if (std.mem.indexOfScalar(u8, trimmed, ',')) |idx|
                            break :blk trimmed[0..idx];
                        break :blk trimmed;
                    };
                    if (allocator.dupe(u8, chosen)) |copy| {
                        allocator.free(meta.artist);
                        meta.artist = copy;
                    } else |_| {}
                }
            } else if (value_type == c.DBUS_TYPE_STRING) {
                var v_ptr: [*:0]const u8 = undefined;
                const v_arg2: ?*anyopaque = @ptrCast(&v_ptr);
                c.dbus_message_iter_get_basic(&value_iter, v_arg2);
                const slice = std.mem.trim(u8, std.mem.span(v_ptr), " ");
                if (allocator.dupe(u8, slice)) |copy| {
                    allocator.free(meta.artist);
                    meta.artist = copy;
                } else |_| {}
            }
        } else if (std.mem.eql(u8, key, "xesam:album")) {
            if (value_type == c.DBUS_TYPE_STRING) {
                var v_ptr: [*:0]const u8 = undefined;
                const v_arg: ?*anyopaque = @ptrCast(&v_ptr);
                c.dbus_message_iter_get_basic(&value_iter, v_arg);
                const slice = std.mem.span(v_ptr);
                if (allocator.dupe(u8, slice)) |copy| {
                    allocator.free(meta.album);
                    meta.album = copy;
                } else |_| {}
            }
        } else if (std.mem.eql(u8, key, "mpris:length")) {
            if (value_type == c.DBUS_TYPE_INT64 or value_type == c.DBUS_TYPE_UINT64) {
                if (value_type == c.DBUS_TYPE_INT64) {
                    var ns: i64 = 0;
                    c.dbus_message_iter_get_basic(&value_iter, &ns);
                    meta.length = @as(f64, @floatFromInt(ns)) / 1_000_000.0;
                } else {
                    var ns_u: u64 = 0;
                    c.dbus_message_iter_get_basic(&value_iter, &ns_u);
                    meta.length = @as(f64, @floatFromInt(ns_u)) / 1_000_000.0;
                }
            }
        } else if (std.mem.eql(u8, key, "mpris:trackid")) {
            if (value_type == c.DBUS_TYPE_OBJECT_PATH or value_type == c.DBUS_TYPE_STRING) {
                var v_ptr: [*:0]const u8 = undefined;
                const v_arg: ?*anyopaque = @ptrCast(&v_ptr);
                c.dbus_message_iter_get_basic(&value_iter, v_arg);
                const slice = std.mem.span(v_ptr);
                if (allocator.dupe(u8, slice)) |copy| {
                    allocator.free(meta.trackid);
                    meta.trackid = copy;
                } else |_| {}
            }
        }

        if (c.dbus_message_iter_next(&dict_iter) == 0) break;
    }
}

pub fn getPosition(allocator: std.mem.Allocator, player: []const u8) f64 {
    const property: [:0]const u8 = "Position";
    if (fetchInt64Property(allocator, player, property)) |micros| {
        return @as(f64, @floatFromInt(micros)) / 1_000_000.0;
    } else |_| {
        return 0.0;
    }
}

pub fn getStatus(allocator: std.mem.Allocator, player: []const u8) []const u8 {
    const property: [:0]const u8 = "PlaybackStatus";
    if (fetchStringProperty(allocator, player, property)) |value| {
        defer allocator.free(value);
        if (std.mem.eql(u8, value, "Playing")) return "Playing";
        if (std.mem.eql(u8, value, "Paused")) return "Paused";
        return "Stopped";
    } else |_| {
        return "Stopped";
    }
}

pub fn getMeta(allocator: std.mem.Allocator, player: []const u8) Meta {
    var m = Meta{
        .title = allocator.dupe(u8, "") catch unreachable,
        .artist = allocator.dupe(u8, "") catch unreachable,
        .album = allocator.dupe(u8, "") catch unreachable,
        .length = 0.0,
        .trackid = allocator.dupe(u8, "") catch unreachable,
    };

    fetchMetadata(allocator, player, &m) catch {};
    return m;
}

pub fn listPlayers(allocator: std.mem.Allocator) ![][]u8 {
    const conn = try ensureConnection();
    const msg_ptr = c.dbus_message_new_method_call(dbus_service.ptr, dbus_path.ptr, dbus_iface.ptr, dbus_list_names.ptr);
    if (msg_ptr == null) return error.OutOfMemory;
    const msg = msg_ptr.?;
    defer c.dbus_message_unref(msg);

    const reply_ptr = c.dbus_connection_send_with_reply_and_block(conn, msg, -1, null);
    if (reply_ptr == null) {
        resetConnection();
        return error.DBusCallFailed;
    }
    const reply = reply_ptr.?;
    defer c.dbus_message_unref(reply);

    var iter = c.DBusMessageIter{};
    if (c.dbus_message_iter_init(reply, &iter) == 0) return error.InvalidReply;
    if (c.dbus_message_iter_get_arg_type(&iter) != c.DBUS_TYPE_ARRAY) return error.TypeMismatch;

    var array_iter = c.DBusMessageIter{};
    c.dbus_message_iter_recurse(&iter, &array_iter);

    var list = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit();
    }

    while (c.dbus_message_iter_get_arg_type(&array_iter) != c.DBUS_TYPE_INVALID) {
        var name_ptr: [*:0]const u8 = undefined;
        const name_arg: ?*anyopaque = @ptrCast(&name_ptr);
        c.dbus_message_iter_get_basic(&array_iter, name_arg);
        const full = std.mem.span(name_ptr);
        if (std.mem.startsWith(u8, full, mpris_prefix)) {
            const suffix = full[mpris_prefix.len ..];
            const copy = try allocator.dupe(u8, suffix);
            try list.append(copy);
        }
        if (c.dbus_message_iter_next(&array_iter) == 0) break;
    }

    return try list.toOwnedSlice();
}

pub fn waitForChange(player: []const u8, timeout_ms: i32) !bool {
    const conn = try ensurePropertiesMatch(player);
    var clamped = timeout_ms;
    if (clamped < 0) clamped = 0;
    if (clamped > std.math.maxInt(c_int)) clamped = std.math.maxInt(c_int);
    const wait_ms: c_int = @intCast(clamped);
    _ = c.dbus_connection_read_write(conn, wait_ms);

    while (true) {
        const msg_ptr = c.dbus_connection_pop_message(conn);
        if (msg_ptr == null) return false;
        const msg = msg_ptr.?;
        defer c.dbus_message_unref(msg);

        if (c.dbus_message_is_signal(msg, properties_iface.ptr, properties_changed.ptr) != 0) {
            return true;
        }
    }
}
