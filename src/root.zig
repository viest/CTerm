// CTerm - Vibe Coding Terminal
// Core library providing configuration, layout, token tracking,
// project management, and agent preset functionality.

pub const config = @import("config.zig");
pub const layout = @import("layout.zig");
pub const token_tracker = @import("token_tracker.zig");
pub const project = @import("project.zig");
pub const agent = @import("agent.zig");

// C API exports
comptime {
    _ = @import("capi.zig");
}

test {
    @import("std").testing.refAllDecls(@This());
}
