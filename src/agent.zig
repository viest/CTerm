const std = @import("std");
const c = @cImport(@cInclude("stdio.h"));

pub const AgentPreset = struct {
    name: [128]u8 = std.mem.zeroes([128]u8),
    command: [1024]u8 = std.mem.zeroes([1024]u8),
    description: [512]u8 = std.mem.zeroes([512]u8),
    provider: [64]u8 = std.mem.zeroes([64]u8),
    icon: [32]u8 = std.mem.zeroes([32]u8),
    working_dir: [1024]u8 = std.mem.zeroes([1024]u8),
    keyboard_shortcut: [32]u8 = std.mem.zeroes([32]u8),
    auto_apply: bool = false,

    fn getStr(buf: []const u8) []const u8 {
        const len = std.mem.indexOfScalar(u8, buf, 0) orelse buf.len;
        return buf[0..len];
    }

    fn setStr(buf: []u8, val: []const u8) void {
        @memset(buf, 0);
        const copy_len = @min(val.len, buf.len - 1);
        @memcpy(buf[0..copy_len], val[0..copy_len]);
    }

    pub fn getName(self: *const AgentPreset) []const u8 {
        return getStr(&self.name);
    }
    pub fn getCommand(self: *const AgentPreset) []const u8 {
        return getStr(&self.command);
    }
    pub fn getDescription(self: *const AgentPreset) []const u8 {
        return getStr(&self.description);
    }
    pub fn getProvider(self: *const AgentPreset) []const u8 {
        return getStr(&self.provider);
    }
    pub fn getIcon(self: *const AgentPreset) []const u8 {
        return getStr(&self.icon);
    }
    pub fn getWorkingDir(self: *const AgentPreset) []const u8 {
        return getStr(&self.working_dir);
    }
    pub fn getShortcut(self: *const AgentPreset) []const u8 {
        return getStr(&self.keyboard_shortcut);
    }

    pub fn setName(self: *AgentPreset, val: []const u8) void {
        setStr(&self.name, val);
    }
    pub fn setCommand(self: *AgentPreset, val: []const u8) void {
        setStr(&self.command, val);
    }
    pub fn setDescription(self: *AgentPreset, val: []const u8) void {
        setStr(&self.description, val);
    }
    pub fn setProvider(self: *AgentPreset, val: []const u8) void {
        setStr(&self.provider, val);
    }
    pub fn setIcon(self: *AgentPreset, val: []const u8) void {
        setStr(&self.icon, val);
    }
    pub fn setWorkingDir(self: *AgentPreset, val: []const u8) void {
        setStr(&self.working_dir, val);
    }
    pub fn setShortcut(self: *AgentPreset, val: []const u8) void {
        setStr(&self.keyboard_shortcut, val);
    }
};

pub const AgentStore = struct {
    presets: std.ArrayList(AgentPreset),
    storage_path: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, storage_path: []const u8) !AgentStore {
        return .{
            .presets = .empty,
            .storage_path = try allocator.dupe(u8, storage_path),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AgentStore) void {
        self.presets.deinit(self.allocator);
        self.allocator.free(self.storage_path);
    }

    pub fn add(self: *AgentStore, preset: *const AgentPreset) !void {
        for (self.presets.items) |p| {
            if (std.mem.eql(u8, p.getName(), preset.getName())) {
                return error.DuplicateName;
            }
        }
        try self.presets.append(self.allocator, preset.*);
        try self.persist();
    }

    pub fn update(self: *AgentStore, preset: *const AgentPreset) !void {
        for (self.presets.items) |*p| {
            if (std.mem.eql(u8, p.getName(), preset.getName())) {
                p.* = preset.*;
                try self.persist();
                return;
            }
        }
        return error.NotFound;
    }

    pub fn remove(self: *AgentStore, name: []const u8) !bool {
        for (self.presets.items, 0..) |p, i| {
            if (std.mem.eql(u8, p.getName(), name)) {
                _ = self.presets.orderedRemove(i);
                try self.persist();
                return true;
            }
        }
        return false;
    }

    pub fn get(self: *const AgentStore, name: []const u8) ?AgentPreset {
        for (self.presets.items) |p| {
            if (std.mem.eql(u8, p.getName(), name)) {
                return p;
            }
        }
        return null;
    }

    pub fn list(self: *const AgentStore) []const AgentPreset {
        return self.presets.items;
    }

    pub fn addDefaults(self: *AgentStore) !void {
        const defaults = [_]struct { name: []const u8, cmd: []const u8, desc: []const u8, provider: []const u8, icon: []const u8 }{
            .{ .name = "Claude Code", .cmd = "claude", .desc = "Anthropic Claude Code Agent", .provider = "anthropic", .icon = "brain" },
            .{ .name = "Codex", .cmd = "codex", .desc = "OpenAI Codex CLI Agent", .provider = "openai", .icon = "sparkles" },
            .{ .name = "Gemini CLI", .cmd = "gemini", .desc = "Google Gemini CLI Agent", .provider = "google", .icon = "diamond" },
            .{ .name = "Aider", .cmd = "aider", .desc = "Aider AI Pair Programming", .provider = "multiple", .icon = "wrench" },
            .{ .name = "Copilot", .cmd = "gh copilot", .desc = "GitHub Copilot CLI", .provider = "github", .icon = "rocket" },
        };

        for (defaults) |d| {
            if (self.get(d.name) == null) {
                var preset = AgentPreset{};
                preset.setName(d.name);
                preset.setCommand(d.cmd);
                preset.setDescription(d.desc);
                preset.setProvider(d.provider);
                preset.setIcon(d.icon);
                try self.presets.append(self.allocator, preset);
            }
        }
        try self.persist();
    }

    fn persist(self: *const AgentStore) !void {
        const path_z = try self.allocator.dupeZ(u8, self.storage_path);
        defer self.allocator.free(path_z);

        const fp = c.fopen(path_z.ptr, "w") orelse return error.FileCreate;
        defer _ = c.fclose(fp);

        _ = c.fprintf(fp, "[\n");
        for (self.presets.items, 0..) |p, i| {
            const name = p.getName();
            const cmd = p.getCommand();
            const desc = p.getDescription();
            const prov = p.getProvider();
            const icon = p.getIcon();
            const wdir = p.getWorkingDir();
            const shortcut = p.getShortcut();

            _ = c.fprintf(fp, "  {\n");
            _ = c.fprintf(fp, "    \"name\": \"%.*s\",\n", @as(c_int, @intCast(name.len)), name.ptr);
            _ = c.fprintf(fp, "    \"command\": \"%.*s\",\n", @as(c_int, @intCast(cmd.len)), cmd.ptr);
            _ = c.fprintf(fp, "    \"description\": \"%.*s\",\n", @as(c_int, @intCast(desc.len)), desc.ptr);
            _ = c.fprintf(fp, "    \"provider\": \"%.*s\",\n", @as(c_int, @intCast(prov.len)), prov.ptr);
            _ = c.fprintf(fp, "    \"icon\": \"%.*s\",\n", @as(c_int, @intCast(icon.len)), icon.ptr);
            _ = c.fprintf(fp, "    \"working_dir\": \"%.*s\",\n", @as(c_int, @intCast(wdir.len)), wdir.ptr);
            _ = c.fprintf(fp, "    \"keyboard_shortcut\": \"%.*s\",\n", @as(c_int, @intCast(shortcut.len)), shortcut.ptr);
            _ = c.fprintf(fp, "    \"auto_apply\": %s\n", boolStr(p.auto_apply));
            if (i < self.presets.items.len - 1) {
                _ = c.fprintf(fp, "  },\n");
            } else {
                _ = c.fprintf(fp, "  }\n");
            }
        }
        _ = c.fprintf(fp, "]\n");
    }

    pub fn loadFromDisk(self: *AgentStore) !void {
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
                var preset = AgentPreset{};
                const block_end = std.mem.indexOfPos(u8, content, name_key, "}") orelse content.len;

                if (extractJsonString(content, name_key)) |name| preset.setName(name);
                if (findAndExtract(content, name_key, block_end, "\"command\"")) |v| preset.setCommand(v);
                if (findAndExtract(content, name_key, block_end, "\"description\"")) |v| preset.setDescription(v);
                if (findAndExtract(content, name_key, block_end, "\"provider\"")) |v| preset.setProvider(v);
                if (findAndExtract(content, name_key, block_end, "\"icon\"")) |v| preset.setIcon(v);

                if (preset.getName().len > 0) {
                    try self.presets.append(self.allocator, preset);
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

test "agent store basic" {
    var store = try AgentStore.init(std.testing.allocator, "/tmp/cterm_test_agents.json");
    defer store.deinit();

    var preset = AgentPreset{};
    preset.setName("test-agent");
    preset.setCommand("test-cmd");
    preset.setProvider("test");

    try store.add(&preset);
    const loaded = store.get("test-agent");
    try std.testing.expect(loaded != null);
    try std.testing.expectEqualStrings("test-agent", loaded.?.getName());
}
