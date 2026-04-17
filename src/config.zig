const std = @import("std");
const c = @cImport(@cInclude("stdio.h"));

pub const Config = struct {
    entries: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .entries = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Config) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.entries.deinit();
    }

    pub fn get(self: *const Config, key: []const u8) ?[]const u8 {
        return self.entries.get(key);
    }

    pub fn set(self: *Config, key: []const u8, value: []const u8) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        if (try self.entries.fetchPut(owned_key, owned_value)) |old| {
            // Map keeps the existing key, so free the new duplicate key
            self.allocator.free(owned_key);
            // Free the old value that was replaced
            self.allocator.free(old.value);
        }
    }

    pub fn load(self: *Config, path: []const u8) !void {
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        const fp = c.fopen(path_z.ptr, "r") orelse return error.FileNotFound;
        defer _ = c.fclose(fp);

        var line_buf: [4096]u8 = undefined;
        while (c.fgets(&line_buf, @intCast(line_buf.len), fp) != null) {
            const line_len = std.mem.indexOfScalar(u8, &line_buf, '\n') orelse
                std.mem.indexOfScalar(u8, &line_buf, 0) orelse continue;
            const trimmed = std.mem.trim(u8, line_buf[0..line_len], " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
                const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");
                if (key.len > 0) {
                    try self.set(key, value);
                }
            }
        }
    }

    pub fn save(self: *const Config, path: []const u8) !void {
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        const fp = c.fopen(path_z.ptr, "w") orelse return error.FileCreate;
        defer _ = c.fclose(fp);

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            _ = c.fprintf(fp, "%.*s = %.*s\n", @as(c_int, @intCast(entry.key_ptr.*.len)), entry.key_ptr.*.ptr, @as(c_int, @intCast(entry.value_ptr.*.len)), entry.value_ptr.*.ptr);
        }
    }

    pub fn setDefaults(self: *Config) !void {
        const defaults = .{
            .{ "font-family", "SF Mono" },
            .{ "font-size", "13" },
            .{ "theme", "dark" },
            .{ "cursor-style", "block" },
            .{ "cursor-blink", "true" },
            .{ "scrollback-lines", "10000" },
            .{ "shell", "/bin/zsh" },
            .{ "editor", "code" },
            .{ "left-sidebar-width", "250" },
            .{ "right-sidebar-width", "300" },
            .{ "left-sidebar-visible", "true" },
            .{ "right-sidebar-visible", "true" },
            .{ "window-width", "1400" },
            .{ "window-height", "900" },
        };

        inline for (defaults) |d| {
            if (self.entries.get(d[0]) == null) {
                try self.set(d[0], d[1]);
            }
        }
    }
};

test "config basic operations" {
    const allocator = std.testing.allocator;
    var cfg = Config.init(allocator);
    defer cfg.deinit();

    try cfg.set("key1", "value1");
    try std.testing.expectEqualStrings("value1", cfg.get("key1").?);

    try cfg.set("key1", "value2");
    try std.testing.expectEqualStrings("value2", cfg.get("key1").?);
}
