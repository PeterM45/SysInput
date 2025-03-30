const std = @import("std");
pub const sysinput = @import("module_exports.zig");

const keyboard = sysinput.input.keyboard;
const buffer = sysinput.core.buffer;
const buffer_controller = sysinput.core.buffer_controller;
const manager = sysinput.suggestion.manager;
const win32 = sysinput.win32.hook;
const debug = sysinput.core.debug;
const edit_distance = sysinput.text.edit_distance;

/// General Purpose Allocator for dynamic memory
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    // Initialize memory allocator
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize buffer controller
    try buffer_controller.init(allocator);

    // Get module instance for UI initialization
    const hInstance = win32.GetModuleHandleA(null);

    // Initialize suggestion handler
    try manager.init(allocator, hInstance);
    defer manager.deinit();

    debug.debugPrint("Starting SysInput...\n", .{});

    // Set up the keyboard hook
    keyboard.g_hook = try keyboard.setupKeyboardHook();
    debug.debugPrint("Keyboard hook installed successfully.\n", .{});

    // Initial text field detection
    buffer_controller.detectActiveTextField();

    debug.debugPrint("Press ESC key to exit.\n", .{});

    // Clean up when the application exits
    defer {
        if (keyboard.g_hook) |hook| {
            _ = win32.UnhookWindowsHookEx(hook);
            debug.debugPrint("Keyboard hook removed.\n", .{});
        }
    }

    // Run the message loop to keep the hook active
    keyboard.messageLoop() catch |err| {
        std.debug.print("Message loop error: {}\n", .{err});
    };
}

test "basic buffer operations" {
    // TODO: Implement basic buffer operation tests
    // Tests should cover:
    // - Buffer initialization
    // - String insertion
    // - Character insertion
    // - Backspace functionality
    // - Buffer reset
    // - Special character handling
    // - Word extraction
    // - Buffer size limits
}

test "edit distance calculation" {
    // TODO: Implement edit distance calculation tests
    // Tests should cover:
    // - Basic edit distance between similar words
    // - Edit distance with empty strings
    // - Similarity scoring for suggestions
    // - Edge cases for the algorithm
}
