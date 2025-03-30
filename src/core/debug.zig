const std = @import("std");
const config = @import("config.zig");

// Use config for debug mode flag
pub const DEBUG_MODE = config.DEBUG.DEBUG_MODE;

/// Debug level enum to control verbosity
pub const DebugLevel = enum(u8) {
    Error = 1, // Only critical errors
    Warning = 2, // Errors and warnings
    Info = 3, // General information
    Debug = 4, // Detailed debug info
    Trace = 5, // Very verbose output
};

/// Current debug level - use config value
pub const CURRENT_LEVEL = @as(DebugLevel, @enumFromInt(config.DEBUG.DEBUG_LEVEL));

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

// Special logging functions that check config flags
pub fn logCaretPosition(fmt: []const u8, args: anytype) void {
    if (DEBUG_MODE and config.DEBUG.LOG_CARET_POSITIONS) {
        std.debug.print("[CARET] " ++ fmt, args);
    }
}

pub fn logBufferChange(fmt: []const u8, args: anytype) void {
    if (DEBUG_MODE and config.DEBUG.LOG_BUFFER_CHANGES) {
        std.debug.print("[BUFFER] " ++ fmt, args);
    }
}

pub fn logSuggestion(fmt: []const u8, args: anytype) void {
    if (DEBUG_MODE and config.DEBUG.LOG_SUGGESTIONS) {
        std.debug.print("[SUGGESTION] " ++ fmt, args);
    }
}

pub fn logInsertion(fmt: []const u8, args: anytype) void {
    if (DEBUG_MODE and config.DEBUG.LOG_INSERTION_METHODS) {
        std.debug.print("[INSERTION] " ++ fmt, args);
    }
}
