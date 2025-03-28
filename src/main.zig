const std = @import("std");
pub const sysinput = @import("sysinput.zig");

const keyboard = sysinput.input.keyboard;
const buffer = sysinput.core.buffer;
const buffer_controller = sysinput.buffer_controller;
const manager = sysinput.suggestion.manager;
const win32 = sysinput.win32.hook;
const debug = sysinput.core.debug;

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
    // Initialize for testing
    const allocator = std.testing.allocator;
    var test_buffer = buffer.BufferManager.init(allocator);

    // Test string insertion
    try test_buffer.insertString("Hello");
    try std.testing.expectEqualStrings("Hello", test_buffer.getCurrentText());

    // Test character insertion
    try test_buffer.insertString(" "); // Using insertString instead of insertChar
    try test_buffer.insertString("World");
    try std.testing.expectEqualStrings("Hello World", test_buffer.getCurrentText());

    // Test backspace
    try test_buffer.processBackspace();
    try std.testing.expectEqualStrings("Hello Worl", test_buffer.getCurrentText());

    // Test clear
    test_buffer.resetBuffer();
    try std.testing.expectEqualStrings("", test_buffer.getCurrentText());
}
