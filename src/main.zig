const std = @import("std");
pub const sysinput = @import("sysinput.zig");

const keyboard = sysinput.input.keyboard;
const buffer = sysinput.core.buffer;
const buffer_controller = sysinput.buffer_controller;
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

    // Test handling special characters
    try test_buffer.insertString("Line1\nLine2\tTabbed");
    try std.testing.expectEqualStrings("Line1\nLine2\tTabbed", test_buffer.getCurrentText());

    // Test word extraction
    const word = try test_buffer.getCurrentWord();
    try std.testing.expectEqualStrings("Tabbed", word);

    // Test buffer limits
    const long_text = try allocator.alloc(u8, 4000);
    defer allocator.free(long_text);
    @memset(long_text, 'A');

    test_buffer.resetBuffer();
    try test_buffer.insertString(long_text);
    try std.testing.expectEqual(long_text.len, test_buffer.getCurrentText().len);
}

test "edit distance calculation" {
    // Test basic edit distance calculation
    try std.testing.expectEqual(@as(usize, 0), edit_distance.enhancedEditDistance("test", "test"));
    try std.testing.expectEqual(@as(usize, 1), edit_distance.enhancedEditDistance("test", "tent"));
    try std.testing.expectEqual(@as(usize, 2), edit_distance.enhancedEditDistance("test", "text"));

    // Test with empty strings
    try std.testing.expectEqual(@as(usize, 4), edit_distance.enhancedEditDistance("test", ""));
    try std.testing.expectEqual(@as(usize, 4), edit_distance.enhancedEditDistance("", "test"));
    try std.testing.expectEqual(@as(usize, 0), edit_distance.enhancedEditDistance("", ""));

    // Test similarity scoring
    const score1 = edit_distance.calculateSuggestionScore("te", "test");
    const score2 = edit_distance.calculateSuggestionScore("te", "tent");
    try std.testing.expect(score1 > score2); // "test" should be a better suggestion for "te" than "tent"
}
