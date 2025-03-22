const std = @import("std");
const win32 = @import("win32/hook.zig");
const buffer = @import("buffer/buffer.zig");

/// General Purpose Allocator for any dynamic memory needed by the application
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Global buffer manager to track typed text
var buffer_manager: buffer.BufferManager = undefined;

/// Low-level keyboard hook callback function
/// Called by Windows whenever a keyboard event occurs
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

            // Process backspace key
            if (kbd.vkCode == win32.VK_BACK) {
                buffer_manager.processBackspace() catch |err| {
                    std.debug.print("Backspace error: {}\n", .{err});
                };
                printBufferState();
            }
            // Process delete key
            else if (kbd.vkCode == win32.VK_DELETE) {
                buffer_manager.processDelete() catch |err| {
                    std.debug.print("Delete error: {}\n", .{err});
                };
                printBufferState();
            }
            // Process return/enter key
            else if (kbd.vkCode == win32.VK_RETURN) {
                buffer_manager.processKeyPress('\n', true) catch |err| {
                    std.debug.print("Return key error: {}\n", .{err});
                };
                printBufferState();
            }
            // Basic character input
            else if (kbd.vkCode >= 0x20 and kbd.vkCode <= 0x7E) {
                // This is a simple ASCII mapping - a more comprehensive solution
                // would handle shift key, language layouts, etc.
                // Explicitly truncate the virtual key code to 8 bits
                const char: u8 = @truncate(kbd.vkCode);

                buffer_manager.processKeyPress(char, true) catch |err| {
                    std.debug.print("Key processing error: {}\n", .{err});
                };
                printBufferState();
            }
        }
    }

    // Always call the next hook in the chain
    return win32.CallNextHookEx(null, nCode, wParam, lParam);
}

/// Debug function to print the current buffer state
fn printBufferState() void {
    const content = buffer_manager.getCurrentText();
    std.debug.print("Buffer: \"{s}\" (len: {})\n", .{ content, content.len });

    const word = buffer_manager.getCurrentWord() catch |err| {
        std.debug.print("Error getting current word: {}\n", .{err});
        return;
    };
    std.debug.print("Current word: \"{s}\"\n", .{word});
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

/// Runs the Windows message loop
fn messageLoop() !void {
    var msg: win32.MSG = undefined;

    while (win32.GetMessageA(&msg, null, 0, 0) > 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageA(&msg);
    }
}

pub fn main() !void {
    // Initialize memory allocator
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the buffer manager
    buffer_manager = buffer.BufferManager.init(allocator);

    std.debug.print("Starting SysInput keyboard hook...\n", .{});

    // Set up the keyboard hook
    win32.g_hook = try setupKeyboardHook();
    std.debug.print("Keyboard hook installed successfully.\n", .{});
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

test "simple test" {
    std.debug.print("Running tests...\n", .{});
    try std.testing.expectEqual(true, true);
}
