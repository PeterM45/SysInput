const std = @import("std");

// Compile-time flag for debug mode
pub const DEBUG_MODE = true;

/// Conditionally print debug message only when DEBUG_MODE is true
pub fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (DEBUG_MODE) {
        std.debug.print(fmt, args);
    }
}
