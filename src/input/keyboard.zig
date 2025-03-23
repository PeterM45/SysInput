const std = @import("std");
const sysinput = @import("../sysinput.zig");

const win32 = sysinput.win32.hook;
const buffer_controller = sysinput.buffer_controller;
const suggestion_handler = sysinput.suggestion_handler;

pub var g_hook: ?win32.HHOOK = null;

pub fn setupKeyboardHook() !win32.HHOOK {
    const hInstance = win32.GetModuleHandleA(null);
    const hook = win32.SetWindowsHookExA(win32.WH_KEYBOARD_LL, keyboardHookProc, hInstance, 0);

    if (hook == null) {
        std.debug.print("Failed to set keyboard hook\n", .{});
        return win32.HookError.SetHookFailed;
    }

    return hook.?;
}

/// Low-level keyboard hook callback function
fn keyboardHookProc(nCode: c_int, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.C) win32.LRESULT {
    // First, immediately check if we should pass this to the next hook
    if (nCode < 0) {
        return win32.CallNextHookEx(null, nCode, wParam, lParam);
    }

    if (nCode == win32.HC_ACTION) {
        const kbd = @as(*win32.KBDLLHOOKSTRUCT, @ptrFromInt(@as(usize, @bitCast(lParam))));

        // Only process keydown events
        if (wParam == win32.WM_KEYDOWN or wParam == win32.WM_SYSKEYDOWN) {
            // Track if we consumed the key
            var key_consumed = false;

            // Handle navigation keys when autocomplete is visible
            if (suggestion_handler.isSuggestionUIVisible() and
                (kbd.vkCode == win32.VK_UP or
                    kbd.vkCode == win32.VK_DOWN or
                    kbd.vkCode == win32.VK_TAB or
                    kbd.vkCode == win32.VK_RIGHT or
                    kbd.vkCode == win32.VK_RETURN))
            {
                // Debug output for suggestion navigation
                std.debug.print("Suggestion navigation key: 0x{X}\n", .{kbd.vkCode});

                // Handle navigation keys for autocomplete
                switch (kbd.vkCode) {
                    win32.VK_UP => {
                        // Move to previous suggestion
                        suggestion_handler.navigateToPreviousSuggestion();
                        return 1; // Prevent default handling
                    },
                    win32.VK_DOWN => {
                        // Move to next suggestion
                        suggestion_handler.navigateToNextSuggestion();
                        return 1; // Prevent default handling
                    },
                    win32.VK_TAB, win32.VK_RIGHT => {
                        std.debug.print("Accepting current suggestion\n", .{});
                        // Accept current suggestion
                        suggestion_handler.acceptCurrentSuggestion();
                        return 1; // Prevent default handling
                    },
                    win32.VK_RETURN => {
                        std.debug.print("Accepting current suggestion with enter\n", .{});
                        // Accept current suggestion
                        suggestion_handler.acceptCurrentSuggestion();

                        // Special handling for return key - after accepting suggestion,
                        // we also need to properly handle the return key itself, so we don't
                        // entirely consume it unless explicitly configured otherwise
                        const config_consume_enter = true; // Make this configurable
                        if (!config_consume_enter) {
                            // Let the app handle enter normally
                            key_consumed = false;
                        } else {
                            key_consumed = true;
                        }
                    },
                    else => {},
                }

                // If we consumed the key, prevent default handling
                if (key_consumed) {
                    return 1;
                }
            }

            // Limit processing to printable characters and specific control keys
            const is_control_key =
                kbd.vkCode == win32.VK_ESCAPE or
                kbd.vkCode == win32.VK_BACK or
                kbd.vkCode == win32.VK_DELETE or
                kbd.vkCode == win32.VK_RETURN or
                kbd.vkCode == win32.VK_TAB;

            const is_printable = kbd.vkCode >= 0x20 and kbd.vkCode <= 0x7E;

            if (is_control_key or is_printable) {
                std.debug.print("Key down: 0x{X}\n", .{kbd.vkCode});

                // Exit application on ESC key
                if (kbd.vkCode == win32.VK_ESCAPE) {
                    std.debug.print("ESC pressed - exit\n", .{});
                    std.process.exit(0);
                }

                // Special key handling for text editing
                if (kbd.vkCode == win32.VK_BACK) {
                    // Backspace key
                    buffer_controller.handleBackspace();
                } else if (kbd.vkCode == win32.VK_DELETE) {
                    // Delete key
                    buffer_controller.handleDelete();
                } else if (kbd.vkCode == win32.VK_RETURN) {
                    // Enter/Return key
                    buffer_controller.handleReturn();
                } else if (kbd.vkCode == win32.VK_TAB) {
                    // Tab key might indicate focus change - detect text field
                    buffer_controller.detectActiveTextField();
                } else if (is_printable) {
                    // ASCII character input
                    const char: u8 = @truncate(kbd.vkCode);
                    buffer_controller.handleCharInput(char);
                }

                // Debug: print current buffer state
                buffer_controller.printBufferState();
            }
        }
    }

    // Always call the next hook in the chain
    return win32.CallNextHookEx(null, nCode, wParam, lParam);
}

pub fn messageLoop() !void {
    var msg: win32.MSG = undefined;

    while (win32.GetMessageA(&msg, null, 0, 0) > 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageA(&msg);
    }
}
