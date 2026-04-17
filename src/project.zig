const std = @import("std");
const c = @cImport(@cInclude("stdio.h"));

pub const Project = struct {
    name: [256]u8 = std.mem.zeroes([256]u8),
    path: [1024]u8 = std.mem.zeroes([1024]u8),
    editor: [256]u8 = std.mem.zeroes([256]u8),
    description: [512]u8 = std.mem.zeroes([512]u8),
    last_opened: i64 = 0,
    pinned: bool = false,

    fn getStr(buf: []const u8) []const u8 {
        const len = std.mem.indexOfScalar(u8, buf, 0) orelse buf.len;
        return buf[0..len];
    }

    fn setStr(buf: []u8, val: []const u8) void {
        @memset(buf, 0);
        const copy_len = @min(val.len, buf.len - 1);
        @memcpy(buf[0..copy_len], val[0..copy_len]);
    }

    pub fn getName(self: *const Project) []const u8 {
        return getStr(&self.name);
    }
    pub fn getPath(self: *const Project) []const u8 {
        return getStr(&self.path);
    }
    pub fn getEditor(self: *const Project) []const u8 {
        return getStr(&self.editor);
    }
    pub fn getDescription(self: *const Project) []const u8 {
        return getStr(&self.description);
    }
    pub fn setName(self: *Project, val: []const u8) void {
        setStr(&self.name, val);
    }
    pub fn setPath(self: *Project, val: []const u8) void {
        setStr(&self.path, val);
    }
    pub fn setEditor(self: *Project, val: []const u8) void {
        setStr(&self.editor, val);
    }
    pub fn setDescription(self: *Project, val: []const u8) void {
        setStr(&self.description, val);
    }
};

pub const ProjectStore = struct {
    projects: std.ArrayList(Project),
    storage_path: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, storage_path: []const u8) !ProjectStore {
        return .{
            .projects = .empty,
            .storage_path = try allocator.dupe(u8, storage_path),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProjectStore) void {
        self.projects.deinit(self.allocator);
        self.allocator.free(self.storage_path);
    }

    pub fn add(self: *ProjectStore, project: *const Project) !void {
        for (self.projects.items) |p| {
            if (std.mem.eql(u8, p.getName(), project.getName())) {
                return error.DuplicateName;
            }
        }
        try self.projects.append(self.allocator, project.*);
        try self.persist();
    }

    pub fn update(self: *ProjectStore, project: *const Project) !void {
        for (self.projects.items) |*p| {
            if (std.mem.eql(u8, p.getName(), project.getName())) {
                p.* = project.*;
                try self.persist();
                return;
            }
        }
        return error.NotFound;
    }

    pub fn remove(self: *ProjectStore, name: []const u8) !bool {
        for (self.projects.items, 0..) |p, i| {
            if (std.mem.eql(u8, p.getName(), name)) {
                _ = self.projects.orderedRemove(i);
                try self.persist();
                return true;
            }
        }
        return false;
    }

    pub fn get(self: *const ProjectStore, name: []const u8) ?Project {
        for (self.projects.items) |p| {
            if (std.mem.eql(u8, p.getName(), name)) {
                return p;
            }
        }
        return null;
    }

    pub fn list(self: *const ProjectStore) []const Project {
        return self.projects.items;
    }

    fn persist(self: *const ProjectStore) !void {
        const path_z = try self.allocator.dupeZ(u8, self.storage_path);
        defer self.allocator.free(path_z);

        const fp = c.fopen(path_z.ptr, "w") orelse return error.FileCreate;
        defer _ = c.fclose(fp);

        _ = c.fprintf(fp, "[\n");
        for (self.projects.items, 0..) |p, i| {
            const name = p.getName();
            const path = p.getPath();
            const editor = p.getEditor();
            const desc = p.getDescription();
            _ = c.fprintf(fp, "  {\n");
            _ = c.fprintf(fp, "    \"name\": \"%.*s\",\n", @as(c_int, @intCast(name.len)), name.ptr);
            _ = c.fprintf(fp, "    \"path\": \"%.*s\",\n", @as(c_int, @intCast(path.len)), path.ptr);
            _ = c.fprintf(fp, "    \"editor\": \"%.*s\",\n", @as(c_int, @intCast(editor.len)), editor.ptr);
            _ = c.fprintf(fp, "    \"description\": \"%.*s\",\n", @as(c_int, @intCast(desc.len)), desc.ptr);
            _ = c.fprintf(fp, "    \"last_opened\": %lld,\n", @as(c_longlong, p.last_opened));
            _ = c.fprintf(fp, "    \"pinned\": %s\n", boolStr(p.pinned));
            if (i < self.projects.items.len - 1) {
                _ = c.fprintf(fp, "  },\n");
            } else {
                _ = c.fprintf(fp, "  }\n");
            }
        }
        _ = c.fprintf(fp, "]\n");
    }

    pub fn loadFromDisk(self: *ProjectStore) !void {
        const path_z = try self.allocator.dupeZ(u8, self.storage_path);
        defer self.allocator.free(path_z);

        const fp = c.fopen(path_z.ptr, "r") orelse return;
        defer _ = c.fclose(fp);

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
            if (std.mem.indexOfPos(u8, content, pos, "\"name\"")) |name_key| {
                var proj = Project{};

                const block_end = std.mem.indexOfPos(u8, content, name_key, "}") orelse content.len;

                if (extractJsonString(content, name_key)) |name| proj.setName(name);
                if (findAndExtract(content, name_key, block_end, "\"path\"")) |v| proj.setPath(v);
                if (findAndExtract(content, name_key, block_end, "\"editor\"")) |v| proj.setEditor(v);
                if (findAndExtract(content, name_key, block_end, "\"description\"")) |v| proj.setDescription(v);

                if (proj.getName().len > 0) {
                    try self.projects.append(self.allocator, proj);
                }
                pos = block_end + 1;
            } else {
                break;
            }
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

fn findAndExtract(content: []const u8, start: usize, end: usize, key: []const u8) ?[]const u8 {
    const region = content[start..end];
    if (std.mem.indexOf(u8, region, key)) |rel_pos| {
        return extractJsonString(content, start + rel_pos);
    }
    return null;
}

test "project store basic" {
    var store = try ProjectStore.init(std.testing.allocator, "/tmp/cterm_test_projects.json");
    defer store.deinit();

    var proj = Project{};
    proj.setName("my-project");
    proj.setPath("/home/user/my-project");
    proj.setEditor("code");

    try store.add(&proj);
    const loaded = store.get("my-project");
    try std.testing.expect(loaded != null);
    try std.testing.expectEqualStrings("my-project", loaded.?.getName());
}
