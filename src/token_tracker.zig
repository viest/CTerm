const std = @import("std");
const c = @cImport(@cInclude("stdio.h"));

pub const TokenEntry = struct {
    provider: [64]u8 = std.mem.zeroes([64]u8),
    model: [128]u8 = std.mem.zeroes([128]u8),
    input_tokens: i64 = 0,
    output_tokens: i64 = 0,
    cache_read_tokens: i64 = 0,
    cache_write_tokens: i64 = 0,
    cost_usd: f64 = 0,
    timestamp: i64 = 0,
    session_id: [64]u8 = std.mem.zeroes([64]u8),

    fn getStr(buf: []const u8) []const u8 {
        const len = std.mem.indexOfScalar(u8, buf, 0) orelse buf.len;
        return buf[0..len];
    }

    pub fn getProvider(self: *const TokenEntry) []const u8 {
        return getStr(&self.provider);
    }
    pub fn getModel(self: *const TokenEntry) []const u8 {
        return getStr(&self.model);
    }
    pub fn getSessionId(self: *const TokenEntry) []const u8 {
        return getStr(&self.session_id);
    }
};

pub const TokenSummary = struct {
    total_input_tokens: i64 = 0,
    total_output_tokens: i64 = 0,
    total_cache_read_tokens: i64 = 0,
    total_cache_write_tokens: i64 = 0,
    total_cost_usd: f64 = 0,
    entry_count: i32 = 0,
};

pub const TokenTracker = struct {
    entries: std.ArrayList(TokenEntry),
    storage_path: []const u8,
    allocator: std.mem.Allocator,
    session_cache: std.StringHashMap(TokenSummary),

    pub fn init(allocator: std.mem.Allocator, storage_path: []const u8) !TokenTracker {
        return .{
            .entries = .empty,
            .storage_path = try allocator.dupe(u8, storage_path),
            .allocator = allocator,
            .session_cache = std.StringHashMap(TokenSummary).init(allocator),
        };
    }

    pub fn deinit(self: *TokenTracker) void {
        var it = self.session_cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.session_cache.deinit();
        self.entries.deinit(self.allocator);
        self.allocator.free(self.storage_path);
    }

    fn addToCache(self: *TokenTracker, entry: *const TokenEntry) !void {
        const sid = entry.getSessionId();
        if (self.session_cache.getPtr(sid)) |summary| {
            summary.total_input_tokens += entry.input_tokens;
            summary.total_output_tokens += entry.output_tokens;
            summary.total_cache_read_tokens += entry.cache_read_tokens;
            summary.total_cache_write_tokens += entry.cache_write_tokens;
            summary.total_cost_usd += entry.cost_usd;
            summary.entry_count += 1;
            return;
        }
        const key_copy = try self.allocator.dupe(u8, sid);
        errdefer self.allocator.free(key_copy);
        try self.session_cache.put(key_copy, .{
            .total_input_tokens = entry.input_tokens,
            .total_output_tokens = entry.output_tokens,
            .total_cache_read_tokens = entry.cache_read_tokens,
            .total_cache_write_tokens = entry.cache_write_tokens,
            .total_cost_usd = entry.cost_usd,
            .entry_count = 1,
        });
    }

    pub fn record(self: *TokenTracker, entry: *const TokenEntry) !void {
        try self.entries.append(self.allocator, entry.*);
        try self.addToCache(entry);
    }

    pub fn getSessionSummary(self: *const TokenTracker, session_id: []const u8) TokenSummary {
        return self.session_cache.get(session_id) orelse TokenSummary{};
    }

    pub fn getTotalSummary(self: *const TokenTracker) TokenSummary {
        var summary = TokenSummary{};
        for (self.entries.items) |e| {
            summary.total_input_tokens += e.input_tokens;
            summary.total_output_tokens += e.output_tokens;
            summary.total_cache_read_tokens += e.cache_read_tokens;
            summary.total_cache_write_tokens += e.cache_write_tokens;
            summary.total_cost_usd += e.cost_usd;
            summary.entry_count += 1;
        }
        return summary;
    }

    pub fn persist(self: *const TokenTracker) !void {
        const path_z = try self.allocator.dupeZ(u8, self.storage_path);
        defer self.allocator.free(path_z);

        const fp = c.fopen(path_z.ptr, "w") orelse return error.FileCreate;
        defer _ = c.fclose(fp);

        for (self.entries.items) |e| {
            const provider = e.getProvider();
            const model = e.getModel();
            const session = e.getSessionId();
            _ = c.fprintf(
                fp,
                "%.*s\t%.*s\t%lld\t%lld\t%lld\t%lld\t%.6f\t%lld\t%.*s\n",
                @as(c_int, @intCast(provider.len)),
                provider.ptr,
                @as(c_int, @intCast(model.len)),
                model.ptr,
                @as(c_longlong, e.input_tokens),
                @as(c_longlong, e.output_tokens),
                @as(c_longlong, e.cache_read_tokens),
                @as(c_longlong, e.cache_write_tokens),
                e.cost_usd,
                @as(c_longlong, e.timestamp),
                @as(c_int, @intCast(session.len)),
                session.ptr,
            );
        }
    }

    pub fn loadFromDisk(self: *TokenTracker) !void {
        const path_z = try self.allocator.dupeZ(u8, self.storage_path);
        defer self.allocator.free(path_z);

        const fp = c.fopen(path_z.ptr, "r") orelse return;
        defer _ = c.fclose(fp);

        var line_buf: [4096]u8 = undefined;
        while (c.fgets(&line_buf, @intCast(line_buf.len), fp) != null) {
            const line_len = std.mem.indexOfScalar(u8, &line_buf, '\n') orelse
                std.mem.indexOfScalar(u8, &line_buf, 0) orelse continue;
            if (line_len == 0) continue;
            const line = line_buf[0..line_len];

            var entry = TokenEntry{};
            var field_idx: u32 = 0;
            var it = std.mem.splitScalar(u8, line, '\t');

            while (it.next()) |field| {
                switch (field_idx) {
                    0 => setFixedStr(&entry.provider, field),
                    1 => setFixedStr(&entry.model, field),
                    2 => entry.input_tokens = std.fmt.parseInt(i64, field, 10) catch 0,
                    3 => entry.output_tokens = std.fmt.parseInt(i64, field, 10) catch 0,
                    4 => entry.cache_read_tokens = std.fmt.parseInt(i64, field, 10) catch 0,
                    5 => entry.cache_write_tokens = std.fmt.parseInt(i64, field, 10) catch 0,
                    6 => entry.cost_usd = std.fmt.parseFloat(f64, field) catch 0,
                    7 => entry.timestamp = std.fmt.parseInt(i64, field, 10) catch 0,
                    8 => setFixedStr(&entry.session_id, field),
                    else => {},
                }
                field_idx += 1;
            }

            if (field_idx >= 2) {
                try self.entries.append(self.allocator, entry);
                try self.addToCache(&entry);
            }
        }
    }
};

fn setFixedStr(buf: []u8, val: []const u8) void {
    @memset(buf, 0);
    const copy_len = @min(val.len, buf.len - 1);
    @memcpy(buf[0..copy_len], val[0..copy_len]);
}

test "token tracker basic" {
    var tracker = try TokenTracker.init(std.testing.allocator, "/tmp/cterm_test_tokens.tsv");
    defer tracker.deinit();

    var entry = TokenEntry{};
    @memcpy(entry.provider[0..6], "claude");
    @memcpy(entry.session_id[0..4], "ses1");
    entry.input_tokens = 1000;
    entry.output_tokens = 500;
    entry.cost_usd = 0.05;

    try tracker.record(&entry);

    const summary = tracker.getSessionSummary("ses1");
    try std.testing.expectEqual(@as(i64, 1000), summary.total_input_tokens);
    try std.testing.expectEqual(@as(i64, 500), summary.total_output_tokens);
}
