const std = @import("std");
const config_mod = @import("config.zig");
const layout_mod = @import("layout.zig");
const token_mod = @import("token_tracker.zig");
const project_mod = @import("project.zig");
const agent_mod = @import("agent.zig");

const allocator = std.heap.smp_allocator;

fn sliceFromC(ptr: ?[*:0]const u8) []const u8 {
    if (ptr) |p| return std.mem.span(p);
    return "";
}

// ============================================================
// Config API
// ============================================================

export fn cterm_config_create() ?*config_mod.Config {
    const cfg = allocator.create(config_mod.Config) catch return null;
    cfg.* = config_mod.Config.init(allocator);
    cfg.setDefaults() catch {};
    return cfg;
}

export fn cterm_config_destroy(cfg: ?*config_mod.Config) void {
    if (cfg) |config| {
        config.deinit();
        allocator.destroy(config);
    }
}

export fn cterm_config_load(cfg: ?*config_mod.Config, path: ?[*:0]const u8) bool {
    if (cfg) |config| {
        config.load(sliceFromC(path)) catch return false;
        return true;
    }
    return false;
}

export fn cterm_config_save(cfg: ?*const config_mod.Config, path: ?[*:0]const u8) bool {
    if (cfg) |config| {
        config.save(sliceFromC(path)) catch return false;
        return true;
    }
    return false;
}

var return_buf: [4096]u8 = undefined;

export fn cterm_config_get(cfg: ?*const config_mod.Config, key: ?[*:0]const u8) ?[*:0]const u8 {
    if (cfg) |config| {
        if (config.get(sliceFromC(key))) |value| {
            if (value.len < return_buf.len) {
                @memcpy(return_buf[0..value.len], value);
                return_buf[value.len] = 0;
                return @ptrCast(&return_buf);
            }
        }
    }
    return null;
}

export fn cterm_config_set(cfg: ?*config_mod.Config, key: ?[*:0]const u8, value: ?[*:0]const u8) void {
    if (cfg) |config| {
        config.set(sliceFromC(key), sliceFromC(value)) catch {};
    }
}

// ============================================================
// Layout API
// ============================================================

const CTermLayout = extern struct {
    name: [256]u8,
    window_frame: extern struct { x: f64, y: f64, width: f64, height: f64 },
    left_sidebar_width: f64,
    right_sidebar_width: f64,
    left_sidebar_visible: bool,
    right_sidebar_visible: bool,
    terminal_split_count: i32,
    split_ratios: [16]f64,
    split_horizontal: bool,
    timestamp: i64,
};

export fn cterm_layout_store_create(path: ?[*:0]const u8) ?*layout_mod.LayoutStore {
    const store = allocator.create(layout_mod.LayoutStore) catch return null;
    store.* = layout_mod.LayoutStore.init(allocator, sliceFromC(path)) catch {
        allocator.destroy(store);
        return null;
    };
    store.loadFromDisk() catch {};
    return store;
}

export fn cterm_layout_store_destroy(store: ?*layout_mod.LayoutStore) void {
    if (store) |s| {
        s.deinit();
        allocator.destroy(s);
    }
}

export fn cterm_layout_save(store: ?*layout_mod.LayoutStore, c_layout: ?*const CTermLayout) bool {
    if (store == null or c_layout == null) return false;
    const cl = c_layout.?;
    var layout = layout_mod.Layout{};
    layout.name = cl.name;
    layout.window_frame = .{
        .x = cl.window_frame.x,
        .y = cl.window_frame.y,
        .width = cl.window_frame.width,
        .height = cl.window_frame.height,
    };
    layout.left_sidebar_width = cl.left_sidebar_width;
    layout.right_sidebar_width = cl.right_sidebar_width;
    layout.left_sidebar_visible = cl.left_sidebar_visible;
    layout.right_sidebar_visible = cl.right_sidebar_visible;
    layout.terminal_split_count = cl.terminal_split_count;
    layout.split_ratios = cl.split_ratios;
    layout.split_horizontal = cl.split_horizontal;
    layout.timestamp = cl.timestamp;

    store.?.save(&layout) catch return false;
    return true;
}

export fn cterm_layout_load(store: ?*layout_mod.LayoutStore, name: ?[*:0]const u8, out: ?*CTermLayout) bool {
    if (store == null or out == null) return false;
    if (store.?.load(sliceFromC(name))) |layout| {
        const o = out.?;
        o.name = layout.name;
        o.window_frame = .{
            .x = layout.window_frame.x,
            .y = layout.window_frame.y,
            .width = layout.window_frame.width,
            .height = layout.window_frame.height,
        };
        o.left_sidebar_width = layout.left_sidebar_width;
        o.right_sidebar_width = layout.right_sidebar_width;
        o.left_sidebar_visible = layout.left_sidebar_visible;
        o.right_sidebar_visible = layout.right_sidebar_visible;
        o.terminal_split_count = layout.terminal_split_count;
        o.split_ratios = layout.split_ratios;
        o.split_horizontal = layout.split_horizontal;
        o.timestamp = layout.timestamp;
        return true;
    }
    return false;
}

export fn cterm_layout_delete(store: ?*layout_mod.LayoutStore, name: ?[*:0]const u8) bool {
    if (store) |s| return s.delete(sliceFromC(name)) catch false;
    return false;
}

export fn cterm_layout_list(store: ?*layout_mod.LayoutStore, out: ?[*]CTermLayout, max_count: i32) i32 {
    if (store == null or out == null or max_count <= 0) return 0;
    const layouts = store.?.list();
    const count: usize = @min(layouts.len, @as(usize, @intCast(max_count)));
    for (layouts[0..count], 0..) |layout, i| {
        out.?[i] = .{
            .name = layout.name,
            .window_frame = .{
                .x = layout.window_frame.x,
                .y = layout.window_frame.y,
                .width = layout.window_frame.width,
                .height = layout.window_frame.height,
            },
            .left_sidebar_width = layout.left_sidebar_width,
            .right_sidebar_width = layout.right_sidebar_width,
            .left_sidebar_visible = layout.left_sidebar_visible,
            .right_sidebar_visible = layout.right_sidebar_visible,
            .terminal_split_count = layout.terminal_split_count,
            .split_ratios = layout.split_ratios,
            .split_horizontal = layout.split_horizontal,
            .timestamp = layout.timestamp,
        };
    }
    return @intCast(count);
}

// ============================================================
// Token Tracker API
// ============================================================

const CTermTokenEntry = extern struct {
    provider: [64]u8,
    model: [128]u8,
    input_tokens: i64,
    output_tokens: i64,
    cache_read_tokens: i64,
    cache_write_tokens: i64,
    cost_usd: f64,
    timestamp: i64,
    session_id: [64]u8,
};

const CTermTokenSummary = extern struct {
    total_input_tokens: i64,
    total_output_tokens: i64,
    total_cache_read_tokens: i64,
    total_cache_write_tokens: i64,
    total_cost_usd: f64,
    entry_count: i32,
};

export fn cterm_token_tracker_create(path: ?[*:0]const u8) ?*token_mod.TokenTracker {
    const tracker = allocator.create(token_mod.TokenTracker) catch return null;
    tracker.* = token_mod.TokenTracker.init(allocator, sliceFromC(path)) catch {
        allocator.destroy(tracker);
        return null;
    };
    tracker.loadFromDisk() catch {};
    return tracker;
}

export fn cterm_token_tracker_destroy(tracker: ?*token_mod.TokenTracker) void {
    if (tracker) |t| {
        t.deinit();
        allocator.destroy(t);
    }
}

export fn cterm_token_record(tracker: ?*token_mod.TokenTracker, c_entry: ?*const CTermTokenEntry) bool {
    if (tracker == null or c_entry == null) return false;
    const ce = c_entry.?;
    var entry = token_mod.TokenEntry{};
    entry.provider = ce.provider;
    entry.model = ce.model;
    entry.input_tokens = ce.input_tokens;
    entry.output_tokens = ce.output_tokens;
    entry.cache_read_tokens = ce.cache_read_tokens;
    entry.cache_write_tokens = ce.cache_write_tokens;
    entry.cost_usd = ce.cost_usd;
    entry.timestamp = ce.timestamp;
    entry.session_id = ce.session_id;
    tracker.?.record(&entry) catch return false;
    return true;
}

fn convertSummary(s: token_mod.TokenSummary) CTermTokenSummary {
    return .{
        .total_input_tokens = s.total_input_tokens,
        .total_output_tokens = s.total_output_tokens,
        .total_cache_read_tokens = s.total_cache_read_tokens,
        .total_cache_write_tokens = s.total_cache_write_tokens,
        .total_cost_usd = s.total_cost_usd,
        .entry_count = s.entry_count,
    };
}

export fn cterm_token_get_session_summary(tracker: ?*token_mod.TokenTracker, session_id: ?[*:0]const u8) CTermTokenSummary {
    if (tracker) |t| return convertSummary(t.getSessionSummary(sliceFromC(session_id)));
    return std.mem.zeroes(CTermTokenSummary);
}

export fn cterm_token_get_total_summary(tracker: ?*token_mod.TokenTracker) CTermTokenSummary {
    if (tracker) |t| return convertSummary(t.getTotalSummary());
    return std.mem.zeroes(CTermTokenSummary);
}

export fn cterm_token_save(tracker: ?*token_mod.TokenTracker) bool {
    if (tracker) |t| {
        t.persist() catch return false;
        return true;
    }
    return false;
}

export fn cterm_token_load(tracker: ?*token_mod.TokenTracker) bool {
    if (tracker) |t| {
        t.loadFromDisk() catch return false;
        return true;
    }
    return false;
}

// ============================================================
// Project API
// ============================================================

const CTermProject = extern struct {
    name: [256]u8,
    path: [1024]u8,
    editor: [256]u8,
    description: [512]u8,
    last_opened: i64,
    pinned: bool,
};

export fn cterm_project_store_create(path: ?[*:0]const u8) ?*project_mod.ProjectStore {
    const store = allocator.create(project_mod.ProjectStore) catch return null;
    store.* = project_mod.ProjectStore.init(allocator, sliceFromC(path)) catch {
        allocator.destroy(store);
        return null;
    };
    store.loadFromDisk() catch {};
    return store;
}

export fn cterm_project_store_destroy(store: ?*project_mod.ProjectStore) void {
    if (store) |s| {
        s.deinit();
        allocator.destroy(s);
    }
}

fn toCTermProject(p: project_mod.Project) CTermProject {
    return .{ .name = p.name, .path = p.path, .editor = p.editor, .description = p.description, .last_opened = p.last_opened, .pinned = p.pinned };
}

fn fromCTermProject(cp: *const CTermProject) project_mod.Project {
    return .{ .name = cp.name, .path = cp.path, .editor = cp.editor, .description = cp.description, .last_opened = cp.last_opened, .pinned = cp.pinned };
}

export fn cterm_project_add(store: ?*project_mod.ProjectStore, cp: ?*const CTermProject) bool {
    if (store == null or cp == null) return false;
    var p = fromCTermProject(cp.?);
    store.?.add(&p) catch return false;
    return true;
}

export fn cterm_project_update(store: ?*project_mod.ProjectStore, cp: ?*const CTermProject) bool {
    if (store == null or cp == null) return false;
    var p = fromCTermProject(cp.?);
    store.?.update(&p) catch return false;
    return true;
}

export fn cterm_project_remove(store: ?*project_mod.ProjectStore, name: ?[*:0]const u8) bool {
    if (store) |s| return s.remove(sliceFromC(name)) catch false;
    return false;
}

export fn cterm_project_list(store: ?*project_mod.ProjectStore, out: ?[*]CTermProject, max_count: i32) i32 {
    if (store == null or out == null or max_count <= 0) return 0;
    const projects = store.?.list();
    const count: usize = @min(projects.len, @as(usize, @intCast(max_count)));
    for (projects[0..count], 0..) |p, i| {
        out.?[i] = toCTermProject(p);
    }
    return @intCast(count);
}

export fn cterm_project_get(store: ?*project_mod.ProjectStore, name: ?[*:0]const u8, out: ?*CTermProject) bool {
    if (store == null or out == null) return false;
    if (store.?.get(sliceFromC(name))) |p| {
        out.?.* = toCTermProject(p);
        return true;
    }
    return false;
}

// ============================================================
// Agent Preset API
// ============================================================

const CTermAgentPreset = extern struct {
    name: [128]u8,
    command: [1024]u8,
    description: [512]u8,
    provider: [64]u8,
    icon: [32]u8,
    working_dir: [1024]u8,
    keyboard_shortcut: [32]u8,
    auto_apply: bool,
};

export fn cterm_agent_store_create(path: ?[*:0]const u8) ?*agent_mod.AgentStore {
    const store = allocator.create(agent_mod.AgentStore) catch return null;
    store.* = agent_mod.AgentStore.init(allocator, sliceFromC(path)) catch {
        allocator.destroy(store);
        return null;
    };
    store.loadFromDisk() catch {};
    if (store.presets.items.len == 0) {
        store.addDefaults() catch {};
    }
    return store;
}

export fn cterm_agent_store_destroy(store: ?*agent_mod.AgentStore) void {
    if (store) |s| {
        s.deinit();
        allocator.destroy(s);
    }
}

fn toCTermPreset(p: agent_mod.AgentPreset) CTermAgentPreset {
    return .{ .name = p.name, .command = p.command, .description = p.description, .provider = p.provider, .icon = p.icon, .working_dir = p.working_dir, .keyboard_shortcut = p.keyboard_shortcut, .auto_apply = p.auto_apply };
}

fn fromCTermPreset(cp: *const CTermAgentPreset) agent_mod.AgentPreset {
    return .{ .name = cp.name, .command = cp.command, .description = cp.description, .provider = cp.provider, .icon = cp.icon, .working_dir = cp.working_dir, .keyboard_shortcut = cp.keyboard_shortcut, .auto_apply = cp.auto_apply };
}

export fn cterm_agent_preset_add(store: ?*agent_mod.AgentStore, cp: ?*const CTermAgentPreset) bool {
    if (store == null or cp == null) return false;
    var p = fromCTermPreset(cp.?);
    store.?.add(&p) catch return false;
    return true;
}

export fn cterm_agent_preset_update(store: ?*agent_mod.AgentStore, cp: ?*const CTermAgentPreset) bool {
    if (store == null or cp == null) return false;
    var p = fromCTermPreset(cp.?);
    store.?.update(&p) catch return false;
    return true;
}

export fn cterm_agent_preset_remove(store: ?*agent_mod.AgentStore, name: ?[*:0]const u8) bool {
    if (store) |s| return s.remove(sliceFromC(name)) catch false;
    return false;
}

export fn cterm_agent_preset_list(store: ?*agent_mod.AgentStore, out: ?[*]CTermAgentPreset, max_count: i32) i32 {
    if (store == null or out == null or max_count <= 0) return 0;
    const presets = store.?.list();
    const count: usize = @min(presets.len, @as(usize, @intCast(max_count)));
    for (presets[0..count], 0..) |p, i| {
        out.?[i] = toCTermPreset(p);
    }
    return @intCast(count);
}

export fn cterm_agent_preset_get(store: ?*agent_mod.AgentStore, name: ?[*:0]const u8, out: ?*CTermAgentPreset) bool {
    if (store == null or out == null) return false;
    if (store.?.get(sliceFromC(name))) |p| {
        out.?.* = toCTermPreset(p);
        return true;
    }
    return false;
}
