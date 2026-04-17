const std = @import("std");
const c = @cImport(@cInclude("stdio.h"));

pub const Rect = struct {
    x: f64 = 0,
    y: f64 = 0,
    width: f64 = 1400,
    height: f64 = 900,
};

pub const Layout = struct {
    name: [256]u8 = std.mem.zeroes([256]u8),
    window_frame: Rect = .{},
    left_sidebar_width: f64 = 250,
    right_sidebar_width: f64 = 300,
    left_sidebar_visible: bool = true,
    right_sidebar_visible: bool = true,
    terminal_split_count: i32 = 1,
    split_ratios: [16]f64 = std.mem.zeroes([16]f64),
    split_horizontal: bool = false,
    timestamp: i64 = 0,

    pub fn getName(self: *const Layout) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.name, 0) orelse self.name.len;
        return self.name[0..len];
    }

    pub fn setName(self: *Layout, name: []const u8) void {
        @memset(&self.name, 0);
        const copy_len = @min(name.len, self.name.len - 1);
        @memcpy(self.name[0..copy_len], name[0..copy_len]);
    }
};

pub const LayoutStore = struct {
    layouts: std.ArrayList(Layout),
    storage_path: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, storage_path: []const u8) !LayoutStore {
        return .{
            .layouts = .empty,
            .storage_path = try allocator.dupe(u8, storage_path),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LayoutStore) void {
        self.layouts.deinit(self.allocator);
        self.allocator.free(self.storage_path);
    }

    pub fn save(self: *LayoutStore, layout_ptr: *const Layout) !void {
        const name = layout_ptr.getName();

        for (self.layouts.items) |*existing| {
            if (std.mem.eql(u8, existing.getName(), name)) {
                existing.* = layout_ptr.*;
                try self.persist();
                return;
            }
        }

        try self.layouts.append(self.allocator, layout_ptr.*);
        try self.persist();
    }

    pub fn load(self: *const LayoutStore, name: []const u8) ?Layout {
        for (self.layouts.items) |l| {
            if (std.mem.eql(u8, l.getName(), name)) {
                return l;
            }
        }
        return null;
    }

    pub fn delete(self: *LayoutStore, name: []const u8) !bool {
        for (self.layouts.items, 0..) |l, i| {
            if (std.mem.eql(u8, l.getName(), name)) {
                _ = self.layouts.orderedRemove(i);
                try self.persist();
                return true;
            }
        }
        return false;
    }

    pub fn list(self: *const LayoutStore) []const Layout {
        return self.layouts.items;
    }

    fn persist(self: *const LayoutStore) !void {
        const path_z = try self.allocator.dupeZ(u8, self.storage_path);
        defer self.allocator.free(path_z);

        const fp = c.fopen(path_z.ptr, "w") orelse return error.FileCreate;
        defer _ = c.fclose(fp);

        _ = c.fprintf(fp, "[\n");
        for (self.layouts.items, 0..) |l, i| {
            const name = l.getName();
            _ = c.fprintf(fp, "  {\n");
            _ = c.fprintf(fp, "    \"name\": \"%.*s\",\n", @as(c_int, @intCast(name.len)), name.ptr);
            _ = c.fprintf(fp, "    \"x\": %.1f, \"y\": %.1f, \"width\": %.1f, \"height\": %.1f,\n", l.window_frame.x, l.window_frame.y, l.window_frame.width, l.window_frame.height);
            _ = c.fprintf(fp, "    \"left_sidebar_width\": %.1f,\n", l.left_sidebar_width);
            _ = c.fprintf(fp, "    \"right_sidebar_width\": %.1f,\n", l.right_sidebar_width);
            _ = c.fprintf(fp, "    \"left_sidebar_visible\": %s,\n", boolStr(l.left_sidebar_visible));
            _ = c.fprintf(fp, "    \"right_sidebar_visible\": %s,\n", boolStr(l.right_sidebar_visible));
            _ = c.fprintf(fp, "    \"terminal_split_count\": %d,\n", l.terminal_split_count);
            _ = c.fprintf(fp, "    \"split_horizontal\": %s,\n", boolStr(l.split_horizontal));
            _ = c.fprintf(fp, "    \"timestamp\": %lld\n", @as(c_longlong, l.timestamp));
            if (i < self.layouts.items.len - 1) {
                _ = c.fprintf(fp, "  },\n");
            } else {
                _ = c.fprintf(fp, "  }\n");
            }
        }
        _ = c.fprintf(fp, "]\n");
    }

    pub fn loadFromDisk(self: *LayoutStore) !void {
        const path_z = try self.allocator.dupeZ(u8, self.storage_path);
        defer self.allocator.free(path_z);

        const fp = c.fopen(path_z.ptr, "r") orelse return;
        defer _ = c.fclose(fp);

        // Read entire file
        _ = c.fseek(fp, 0, c.SEEK_END);
        const file_size = c.ftell(fp);
        if (file_size <= 0) return;
        _ = c.fseek(fp, 0, c.SEEK_SET);

        const size: usize = @intCast(file_size);
        const content = try self.allocator.alloc(u8, size);
        defer self.allocator.free(content);
        _ = c.fread(content.ptr, 1, size, fp);

        var pos: usize = 0;
        while (pos < content.len) {
            if (std.mem.indexOfPos(u8, content, pos, "\"name\"")) |name_start| {
                if (extractJsonString(content, name_start)) |name| {
                    var layout = Layout{};
                    layout.setName(name);

                    // Find the closing brace for this object
                    const block_end = std.mem.indexOfPos(u8, content, name_start, "}") orelse content.len;

                    if (findJsonNumber(content, name_start, block_end, "\"x\"")) |v| layout.window_frame.x = v;
                    if (findJsonNumber(content, name_start, block_end, "\"y\"")) |v| layout.window_frame.y = v;
                    if (findJsonNumber(content, name_start, block_end, "\"width\"")) |v| layout.window_frame.width = v;
                    if (findJsonNumber(content, name_start, block_end, "\"height\"")) |v| layout.window_frame.height = v;
                    if (findJsonNumber(content, name_start, block_end, "\"left_sidebar_width\"")) |v| layout.left_sidebar_width = v;
                    if (findJsonNumber(content, name_start, block_end, "\"right_sidebar_width\"")) |v| layout.right_sidebar_width = v;
                    if (findJsonNumber(content, name_start, block_end, "\"terminal_split_count\"")) |v| layout.terminal_split_count = @intFromFloat(v);
                    if (findJsonBool(content, name_start, block_end, "\"left_sidebar_visible\"")) |v| layout.left_sidebar_visible = v;
                    if (findJsonBool(content, name_start, block_end, "\"right_sidebar_visible\"")) |v| layout.right_sidebar_visible = v;
                    if (findJsonBool(content, name_start, block_end, "\"split_horizontal\"")) |v| layout.split_horizontal = v;

                    try self.layouts.append(self.allocator, layout);
                    pos = block_end + 1;
                    continue;
                }
            }
            break;
        }
    }
};

fn boolStr(val: bool) [*:0]const u8 {
    return if (val) "true" else "false";
}

fn extractJsonString(content: []const u8, key_pos: usize) ?[]const u8 {
    var pos = key_pos;
    while (pos < content.len and content[pos] != ':') : (pos += 1) {}
    if (pos >= content.len) return null;
    pos += 1;
    while (pos < content.len and content[pos] == ' ') : (pos += 1) {}
    if (pos >= content.len or content[pos] != '"') return null;
    pos += 1;
    const start = pos;
    while (pos < content.len and content[pos] != '"') : (pos += 1) {}
    if (pos > start) return content[start..pos];
    return null;
}

fn findJsonNumber(content: []const u8, start: usize, end: usize, key: []const u8) ?f64 {
    const search_region = content[start..end];
    if (std.mem.indexOf(u8, search_region, key)) |rel_pos| {
        var pos = start + rel_pos + key.len;
        while (pos < end and (content[pos] == ':' or content[pos] == ' ')) : (pos += 1) {}
        const num_start = pos;
        while (pos < end and (content[pos] >= '0' and content[pos] <= '9' or content[pos] == '.' or content[pos] == '-')) : (pos += 1) {}
        if (pos > num_start) {
            return std.fmt.parseFloat(f64, content[num_start..pos]) catch null;
        }
    }
    return null;
}

fn findJsonBool(content: []const u8, start: usize, end: usize, key: []const u8) ?bool {
    const search_region = content[start..end];
    if (std.mem.indexOf(u8, search_region, key)) |rel_pos| {
        var pos = start + rel_pos + key.len;
        while (pos < end and (content[pos] == ':' or content[pos] == ' ')) : (pos += 1) {}
        if (pos + 4 <= end and std.mem.eql(u8, content[pos .. pos + 4], "true")) return true;
        if (pos + 5 <= end and std.mem.eql(u8, content[pos .. pos + 5], "false")) return false;
    }
    return null;
}

test "layout store basic" {
    var store = try LayoutStore.init(std.testing.allocator, "/tmp/cterm_test_layouts.json");
    defer store.deinit();

    var layout = Layout{};
    layout.setName("default");
    layout.window_frame.width = 1200;

    try store.save(&layout);
    const loaded = store.load("default");
    try std.testing.expect(loaded != null);
    try std.testing.expectEqualStrings("default", loaded.?.getName());
}
