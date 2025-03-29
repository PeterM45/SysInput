const std = @import("std");

// Compile-time flag for debug mode
pub const DEBUG_MODE = true;

/// Debug level enum to control verbosity
pub const DebugLevel = enum {
    Error, // Only critical errors
    Warning, // Errors and warnings
    Info, // General information
    Debug, // Detailed debug info
    Trace, // Very verbose output
};

/// Current debug level - change this to control output verbosity
pub const CURRENT_LEVEL = DebugLevel.Debug;

/// Conditionally print debug message only when DEBUG_MODE is true
pub fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (DEBUG_MODE) {
        std.debug.print(fmt, args);
    }
}

/// Enhanced debug logging with level control
pub fn log(
    comptime level: DebugLevel,
    comptime module: []const u8,
    comptime fmt: []const u8,
    args: anytype,
) void {
    // Skip if debugging is disabled or level is too detailed
    if (!DEBUG_MODE or @intFromEnum(level) > @intFromEnum(CURRENT_LEVEL)) {
        return;
    }

    // Level prefix
    const level_prefix = switch (level) {
        .Error => "[ERROR] ",
        .Warning => "[WARN] ",
        .Info => "[INFO] ",
        .Debug => "[DEBUG] ",
        .Trace => "[TRACE] ",
    };

    // Print with module context
    std.debug.print(level_prefix ++ "[{s}] " ++ fmt, .{module} ++ args);
}
