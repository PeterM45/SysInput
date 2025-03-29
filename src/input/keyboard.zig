const std = @import("std");
const sysinput = @import("root").sysinput;

const win32 = sysinput.win32.hook;
const buffer_controller = sysinput.buffer_controller;
const manager = sysinput.suggestion.manager;
const debug = sysinput.core.debug;
const api = sysinput.win32.api;

pub var g_hook: ?win32.HHOOK = null;
pub var g_ctrl_pressed: bool = false;

pub fn setupKeyboardHook() !win32.HHOOK {
    const hInstance = win32.GetModuleHandleA(null);
    const hook = win32.SetWindowsHookExA(win32.WH_KEYBOARD_LL, keyboardHookProc, hInstance, 0);

    if (hook == null) {
        debug.debugPrint("Failed to set keyboard hook\n", .{});
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

        // Track Ctrl key state for both key down and key up events
        if (kbd.vkCode == win32.VK_CONTROL) {
            if (wParam == win32.WM_KEYDOWN or wParam == win32.WM_SYSKEYDOWN) {
                g_ctrl_pressed = true;
                debug.debugPrint("Ctrl key pressed\n", .{});
            } else if (wParam == win32.WM_KEYUP or wParam == win32.WM_SYSKEYUP) {
                g_ctrl_pressed = false;
                debug.debugPrint("Ctrl key released\n", .{});
            }
        }

        // Only process keydown events
        if (wParam == win32.WM_KEYDOWN or wParam == win32.WM_SYSKEYDOWN) {
            // Track if we consumed the key
            var key_consumed = false;

            // Handle navigation keys when autocomplete is visible
            if (manager.isSuggestionUIVisible() and
                (kbd.vkCode == win32.VK_UP or
                    kbd.vkCode == win32.VK_DOWN or
                    kbd.vkCode == win32.VK_TAB or
                    kbd.vkCode == win32.VK_RIGHT or
                    kbd.vkCode == win32.VK_RETURN))
            {
                // Debug output for suggestion navigation
                debug.debugPrint("Suggestion navigation key: 0x{X}\n", .{kbd.vkCode});

                // Handle navigation keys for autocomplete
                switch (kbd.vkCode) {
                    win32.VK_UP => {
                        // Move to previous suggestion
                        manager.navigateToPreviousSuggestion();
                        return 1; // Prevent default handling
                    },
                    win32.VK_DOWN => {
                        // Move to next suggestion
                        manager.navigateToNextSuggestion();
                        return 1; // Prevent default handling
                    },
                    win32.VK_TAB, win32.VK_RIGHT => {
                        debug.debugPrint("Accepting current suggestion\n", .{});
                        // Accept current suggestion
                        manager.acceptCurrentSuggestion();
                        return 1; // Prevent default handling
                    },
                    win32.VK_RETURN => {
                        debug.debugPrint("Accepting current suggestion with enter\n", .{});
                        // Accept current suggestion
                        manager.acceptCurrentSuggestion();

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

            // Special handling for Ctrl+Backspace (whole word deletion)
            if (kbd.vkCode == win32.VK_BACK and g_ctrl_pressed) {
                debug.debugPrint("Ctrl+Backspace detected - deleting whole word\n", .{});

                // First, let the application handle the real Ctrl+Backspace
                // by passing it to the next hook
                _ = win32.CallNextHookEx(null, nCode, wParam, lParam);

                // Add a small delay to let the OS process the keypress
                api.sleep(20);

                // Now force detection of the text field to sync our buffer with the new content
                buffer_controller.detectActiveTextField();

                // After syncing, update autocomplete suggestions
                const word = buffer_controller.getCurrentWord() catch "";
                manager.setCurrentWord(word);
                manager.getAutocompleteSuggestions() catch {};

                // Print current buffer state to verify
                buffer_controller.printBufferState();

                // Return 0 to allow the key to be processed (we've already called the next hook)
                return 0;
            }

            // Limit processing to printable characters and specific control keys
            const is_control_key =
                kbd.vkCode == win32.VK_ESCAPE or
                kbd.vkCode == win32.VK_BACK or
                kbd.vkCode == win32.VK_DELETE or
                kbd.vkCode == win32.VK_RETURN or
                kbd.vkCode == win32.VK_TAB;

            const is_navigation_key = (kbd.vkCode == win32.VK_LEFT or
                kbd.vkCode == win32.VK_RIGHT or
                kbd.vkCode == win32.VK_UP or
                kbd.vkCode == win32.VK_DOWN or
                kbd.vkCode == win32.VK_HOME or
                kbd.vkCode == win32.VK_END or
                kbd.vkCode == win32.VK_PRIOR or // Page Up
                kbd.vkCode == win32.VK_NEXT); // Page Down

            // If suggestions UI is visible, use navigation keys for selection
            if (manager.isSuggestionUIVisible()) {
                if (kbd.vkCode == win32.VK_UP) {
                    manager.navigateToPreviousSuggestion();
                    return 1; // Consume the key
                } else if (kbd.vkCode == win32.VK_DOWN) {
                    manager.navigateToNextSuggestion();
                    return 1; // Consume the key
                } else if (kbd.vkCode == win32.VK_TAB or
                    kbd.vkCode == win32.VK_RETURN or
                    kbd.vkCode == win32.VK_RIGHT)
                {
                    debug.debugPrint("Accepting suggestion via key: 0x{X}\n", .{kbd.vkCode});
                    manager.acceptCurrentSuggestion();
                    return 1; // Consume the key
                }
            } else if (is_navigation_key) {
                // If no suggestion UI, just pass navigation keys through
                return win32.CallNextHookEx(null, nCode, wParam, lParam);
            }

            const is_printable = kbd.vkCode >= 0x20 and kbd.vkCode <= 0x7E;

            if (is_control_key or is_printable) {
                debug.debugPrint("Key down: 0x{X}\n", .{kbd.vkCode});

                // Exit application on ESC key
                if (kbd.vkCode == win32.VK_ESCAPE) {
                    debug.debugPrint("ESC pressed - exit\n", .{});
                    std.process.exit(0);
                }

                // Special key handling for text editing
                if (kbd.vkCode == win32.VK_BACK) {
                    // Backspace key
                    buffer_controller.processBackspace() catch |err| {
                        debug.debugPrint("Backspace error: {}\n", .{err});
                    };

                    // Add a small delay to let the backspace take effect
                    api.sleep(5);

                    // Detect the text field again to ensure sync
                    buffer_controller.detectActiveTextField();

                    // Update suggestions based on new text state
                    const word = buffer_controller.getCurrentWord() catch "";
                    manager.setCurrentWord(word);
                    manager.getAutocompleteSuggestions() catch {};
                } else if (kbd.vkCode == win32.VK_DELETE) {
                    // Delete key
                    buffer_controller.processDelete() catch |err| {
                        debug.debugPrint("Delete error: {}\n", .{err});
                    };
                } else if (kbd.vkCode == win32.VK_RETURN) {
                    // Enter/Return key
                    buffer_controller.processReturn() catch |err| {
                        debug.debugPrint("Return error: {}\n", .{err});
                    };
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
