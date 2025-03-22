const std = @import("std");
const win32 = @import("win32/hook.zig");
const buffer = @import("buffer/buffer.zig");
const detection = @import("detection/text_field.zig");

/// General Purpose Allocator for dynamic memory
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Global buffer manager to track typed text
var buffer_manager: buffer.BufferManager = undefined;

/// Global text field manager for detecting active text fields
var text_field_manager: detection.TextFieldManager = undefined;

/// Window timer ID for periodic text field detection
const TEXT_FIELD_DETECTION_TIMER = 1;

/// Time in milliseconds between text field detection checks
const DETECTION_INTERVAL_MS = 500;

/// Low-level keyboard hook callback function
fn keyboardHookProc(nCode: c_int, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.C) win32.LRESULT {
    if (nCode == win32.HC_ACTION) {
        const kbd = @as(*win32.KBDLLHOOKSTRUCT, @ptrFromInt(@as(usize, @bitCast(lParam))));

        if (wParam == win32.WM_KEYDOWN or wParam == win32.WM_SYSKEYDOWN) {
            std.debug.print("Key down: 0x{X}\n", .{kbd.vkCode});

            // Exit application on ESC key
            if (kbd.vkCode == win32.VK_ESCAPE) {
                std.debug.print("ESC pressed - exit\n", .{});
                std.process.exit(0);
            }

            // Special key handling for text editing
            if (kbd.vkCode == win32.VK_BACK) {
                // Backspace key
                buffer_manager.processBackspace() catch |err| {
                    std.debug.print("Backspace error: {}\n", .{err});
                };
                syncTextFieldWithBuffer();
            } else if (kbd.vkCode == win32.VK_DELETE) {
                // Delete key
                buffer_manager.processDelete() catch |err| {
                    std.debug.print("Delete error: {}\n", .{err});
                };
                syncTextFieldWithBuffer();
            } else if (kbd.vkCode == win32.VK_RETURN) {
                // Enter/Return key
                buffer_manager.processKeyPress('\n', true) catch |err| {
                    std.debug.print("Return key error: {}\n", .{err});
                };
                syncTextFieldWithBuffer();
            } else if (kbd.vkCode == win32.VK_TAB) {
                // Tab key might indicate focus change - detect text field
                detectActiveTextField();
            } else if (kbd.vkCode >= 0x20 and kbd.vkCode <= 0x7E) {
                // ASCII character input
                const char: u8 = @truncate(kbd.vkCode);

                buffer_manager.processKeyPress(char, true) catch |err| {
                    std.debug.print("Key processing error: {}\n", .{err});
                };
                syncTextFieldWithBuffer();
            }

            // Debug: print current buffer state
            printBufferState();
        }
    }

    // Always call the next hook in the chain
    return win32.CallNextHookEx(null, nCode, wParam, lParam);
}

/// Debug function to print the current buffer state
fn printBufferState() void {
    const content = buffer_manager.getCurrentText();
    std.debug.print("Buffer: \"{s}\" (len: {})\n", .{ content, content.len });

    const word = buffer_manager.getCurrentWord() catch {
        std.debug.print("Error getting current word\n", .{});
        return;
    };
    std.debug.print("Current word: \"{s}\"\n", .{word});
}

/// Detect the active text field and sync with our buffer
fn detectActiveTextField() void {
    const active_field_found = text_field_manager.detectActiveField();

    if (active_field_found) {
        std.debug.print("Active text field detected\n", .{});

        // Get the text content from the field
        const text = text_field_manager.getActiveFieldText() catch |err| {
            std.debug.print("Failed to get text field content: {}\n", .{err});
            return;
        };
        defer gpa.allocator().free(text);

        // Update our buffer with the current text field content
        buffer_manager.resetBuffer();
        buffer_manager.insertString(text) catch |err| {
            std.debug.print("Failed to sync buffer with text field: {}\n", .{err});
        };

        std.debug.print("Synced buffer with text field content: \"{s}\"\n", .{text});
    } else {
        std.debug.print("No active text field found\n", .{});
    }
}

/// Sync the text field with our buffer content
fn syncTextFieldWithBuffer() void {
    if (!text_field_manager.has_active_field) {
        return;
    }

    const content = buffer_manager.getCurrentText();
    text_field_manager.setActiveFieldText(content) catch |err| {
        std.debug.print("Failed to update text field: {}\n", .{err});
    };
}

/// Sets up the low-level keyboard hook
fn setupKeyboardHook() !win32.HHOOK {
    const hInstance = win32.GetModuleHandleA(null);
    const hook = win32.SetWindowsHookExA(win32.WH_KEYBOARD_LL, keyboardHookProc, hInstance, 0);

    if (hook == null) {
        std.debug.print("Failed to set keyboard hook\n", .{});
        return win32.HookError.SetHookFailed;
    }

    return hook.?;
}

/// Windows message loop function
fn messageLoop() !void {
    var msg: win32.MSG = undefined;

    while (win32.GetMessageA(&msg, null, 0, 0) > 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageA(&msg);
    }
}

/// A helper function to insert a test string
fn insertTestString() void {
    buffer_manager.resetBuffer();
    buffer_manager.insertString("SysInput is working!") catch |err| {
        std.debug.print("Test string insertion error: {}\n", .{err});
    };
    syncTextFieldWithBuffer();
}

pub fn main() !void {
    // Initialize memory allocator
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the buffer manager
    buffer_manager = buffer.BufferManager.init(allocator);

    // Initialize the text field manager
    text_field_manager = detection.TextFieldManager.init(allocator);

    std.debug.print("Starting SysInput...\n", .{});

    // Set up the keyboard hook
    win32.g_hook = try setupKeyboardHook();
    std.debug.print("Keyboard hook installed successfully.\n", .{});

    // Initial text field detection
    detectActiveTextField();

    std.debug.print("Press ESC key to exit.\n", .{});

    // Clean up when the application exits
    defer {
        if (win32.g_hook) |hook| {
            _ = win32.UnhookWindowsHookEx(hook);
            std.debug.print("Keyboard hook removed.\n", .{});
        }
    }

    // Run the message loop to keep the hook active
    try messageLoop();
}

test "basic buffer operations" {
    // Initialize for testing
    const allocator = std.testing.allocator;
    var test_buffer = buffer.BufferManager.init(allocator);

    // Test string insertion
    try test_buffer.insertString("Hello");
    try std.testing.expectEqualStrings("Hello", test_buffer.getCurrentText());

    // Test character insertion
    try test_buffer.insertChar(' ');
    try test_buffer.insertString("World");
    try std.testing.expectEqualStrings("Hello World", test_buffer.getCurrentText());

    // Test backspace
    try test_buffer.processBackspace();
    try std.testing.expectEqualStrings("Hello Worl", test_buffer.getCurrentText());

    // Test clear
    test_buffer.resetBuffer();
    try std.testing.expectEqualStrings("", test_buffer.getCurrentText());
}
