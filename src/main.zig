const std = @import("std");
const win32 = @import("win32/hook.zig");
const common = @import("win32/common.zig");
const buffer = @import("buffer/buffer.zig");
const detection = @import("detection/text_field.zig");
const spellcheck = @import("spellcheck/spellchecker.zig");
const autocomplete = @import("autocomplete/autocomplete.zig");
const autocomplete_ui = @import("ui/autocomplete_ui.zig");

/// General Purpose Allocator for dynamic memory
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Global buffer manager to track typed text
var buffer_manager: buffer.BufferManager = undefined;

/// Global text field manager for detecting active text fields
var text_field_manager: detection.TextFieldManager = undefined;

/// Global spellchecker
var spell_checker: spellcheck.SpellChecker = undefined;

/// Global autocompletion engine
var autocomplete_engine: autocomplete.AutocompleteEngine = undefined;

/// List for storing word suggestions
var suggestions: std.ArrayList([]const u8) = undefined;

/// Autocompletion suggestions list
var autocomplete_suggestions: std.ArrayList([]const u8) = undefined;

/// Global UI for autocompletion suggestions
var autocomplete_ui_manager: autocomplete_ui.AutocompleteUI = undefined;

/// Window timer ID for periodic text field detection
const TEXT_FIELD_DETECTION_TIMER = 1;

/// Time in milliseconds between text field detection checks
const DETECTION_INTERVAL_MS = 500;

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
            // Check if autocomplete UI is visible for navigation keys

            if (autocomplete_ui_manager.is_visible and
                (kbd.vkCode == win32.VK_UP or
                    kbd.vkCode == win32.VK_DOWN or
                    kbd.vkCode == win32.VK_TAB or
                    kbd.vkCode == win32.VK_RIGHT or
                    kbd.vkCode == win32.VK_RETURN))
            {
                // Handle navigation keys for autocomplete
                switch (kbd.vkCode) {
                    win32.VK_UP => {
                        // Move to previous suggestion
                        const new_index = if (autocomplete_ui_manager.selected_index <= 0)
                            @as(i32, @intCast(autocomplete_suggestions.items.len - 1))
                        else
                            autocomplete_ui_manager.selected_index - 1;

                        autocomplete_ui_manager.selectSuggestion(new_index);
                        return 1; // Prevent default handling
                    },
                    win32.VK_DOWN => {
                        // Move to next suggestion
                        const new_index = if (autocomplete_ui_manager.selected_index >= autocomplete_suggestions.items.len - 1)
                            0
                        else
                            autocomplete_ui_manager.selected_index + 1;

                        autocomplete_ui_manager.selectSuggestion(new_index);
                        return 1; // Prevent default handling
                    },
                    win32.VK_TAB, win32.VK_RIGHT, win32.VK_RETURN => {
                        // Accept current suggestion
                        autocomplete_ui_manager.acceptSuggestion();
                        return 1; // Prevent default handling
                    },
                    else => {},
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
                } else if (is_printable) {
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
    }

    // Always call the next hook in the chain
    return win32.CallNextHookEx(null, nCode, wParam, lParam);
}

/// Print the current buffer state and process text for autocompletion
fn printBufferState() void {
    const content = buffer_manager.getCurrentText();
    // Print content with safe escaping for non-printable characters
    std.debug.print("Buffer: \"", .{});
    for (content) |c| {
        if (std.ascii.isPrint(c)) {
            std.debug.print("{c}", .{c});
        } else {
            std.debug.print("\\x{X:0>2}", .{c});
        }
    }
    std.debug.print("\" (len: {})\n", .{content.len});

    const word = buffer_manager.getCurrentWord() catch {
        std.debug.print("Error getting current word\n", .{});
        return;
    };

    // Print word with safe escaping
    std.debug.print("Current word: \"", .{});
    for (word) |c| {
        if (std.ascii.isPrint(c)) {
            std.debug.print("{c}", .{c});
        } else {
            std.debug.print("\\x{X:0>2}", .{c});
        }
    }
    std.debug.print("\"\n", .{});

    // Process the text through the autocompletion engine
    autocomplete_engine.processText(content) catch |err| {
        std.debug.print("Error processing text for autocompletion: {}\n", .{err});
    };

    // Set the current word for autocompletion
    autocomplete_engine.setCurrentWord(word);

    // Get autocompletion suggestions
    autocomplete_suggestions.clearRetainingCapacity();
    autocomplete_engine.getSuggestions(&autocomplete_suggestions) catch |err| {
        std.debug.print("Error getting autocompletion suggestions: {}\n", .{err});
    };

    // Apply autocompletion if we have suggestions and the word is at least 2 characters
    if (autocomplete_suggestions.items.len > 0 and word.len >= 2) {
        std.debug.print("Autocompletion suggestions: ", .{});
        for (autocomplete_suggestions.items, 0..) |suggestion, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("\"{s}\"", .{suggestion});
        }
        std.debug.print("\n", .{});

        // Pass the current text context to the UI manager
        autocomplete_ui_manager.setTextContext(content, word);

        // Try to show suggestions (this will now apply inline completion)
        autocomplete_ui_manager.showSuggestions(autocomplete_suggestions.items, 0, 0) catch |err| {
            std.debug.print("Error applying suggestions: {}\n", .{err});
        };
    } else if (word.len < 2) {
        // Hide suggestions if word is too short
        autocomplete_ui_manager.hideSuggestions();
    }

    // Spell checking
    if (word.len >= 2) {
        if (!spell_checker.isCorrect(word)) {
            // Safely print the word that has a spelling error
            std.debug.print("Spelling error detected: \"", .{});
            for (word) |c| {
                if (std.ascii.isPrint(c)) {
                    std.debug.print("{c}", .{c});
                } else {
                    std.debug.print("\\x{X:0>2}", .{c});
                }
            }
            std.debug.print("\"\n", .{});

            // Limit suggestion generation to avoid excessive CPU usage
            const should_generate_suggestions = word.len < 15; // Skip very long words

            if (should_generate_suggestions) {
                // Clear existing suggestions
                for (suggestions.items) |item| {
                    gpa.allocator().free(item);
                }
                suggestions.clearRetainingCapacity();

                // Get spelling suggestions
                spell_checker.getSuggestions(word, &suggestions) catch |err| {
                    std.debug.print("Error getting suggestions: {}\n", .{err});
                    return;
                };

                // Print suggestions
                if (suggestions.items.len > 0) {
                    std.debug.print("Suggestions: ", .{});
                    for (suggestions.items, 0..) |suggestion, i| {
                        if (i > 0) std.debug.print(", ", .{});
                        std.debug.print("\"{s}\"", .{suggestion});
                    }
                    std.debug.print("\n", .{});
                } else {
                    std.debug.print("No suggestions available\n", .{});
                }
            }
        }
    }
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

/// Handle suggestion selection from the autocomplete UI
fn handleSuggestionSelection(suggestion: []const u8) void {
    // Get the current word being typed
    const current_word = buffer_manager.getCurrentWord() catch {
        std.debug.print("Error getting current word\n", .{});
        return;
    };

    // If there's a current word, replace it with the suggestion
    if (current_word.len > 0) {
        std.debug.print("Replacing word \"{s}\" with suggestion \"{s}\"\n", .{ current_word, suggestion });

        // Approach 1: Try using the text field directly
        if (text_field_manager.has_active_field) {
            const focus_hwnd = common.GetFocus();
            if (focus_hwnd != null) {
                // Get text selection
                const selection = common.SendMessageA(focus_hwnd.?, common.EM_GETSEL, 0, 0);
                const sel_u64: u64 = @bitCast(selection);
                const end_pos: u32 = @truncate((sel_u64 >> 16) & 0xFFFF);

                // Calculate the start of the current word
                const start_pos = if (end_pos >= current_word.len)
                    end_pos - current_word.len
                else
                    0;

                // Select the current word
                _ = common.SendMessageA(focus_hwnd.?, common.EM_SETSEL, start_pos, end_pos);
                // Insert the replacement
                const replacement_buffer = std.heap.page_allocator.allocSentinel(u8, suggestion.len, 0) catch {
                    std.debug.print("Failed to allocate buffer for text replacement\n", .{});
                    return;
                };
                defer std.heap.page_allocator.free(replacement_buffer);

                @memcpy(replacement_buffer, suggestion);
                _ = common.SendMessageA(focus_hwnd.?, common.EM_REPLACESEL, 1, // True to allow undo
                    @as(common.LPARAM, @intCast(@intFromPtr(replacement_buffer.ptr))));

                // Append a space
                const space_buffer = std.heap.page_allocator.allocSentinel(u8, 1, 0) catch return;
                defer std.heap.page_allocator.free(space_buffer);
                space_buffer[0] = ' ';

                _ = common.SendMessageA(focus_hwnd.?, common.EM_REPLACESEL, 1, @as(common.LPARAM, @intCast(@intFromPtr(space_buffer.ptr))));

                // Force a synchronization of our buffer
                const updated_text = text_field_manager.getActiveFieldText() catch |err| {
                    std.debug.print("Failed to get updated text: {}\n", .{err});
                    return;
                };
                defer gpa.allocator().free(updated_text);

                buffer_manager.resetBuffer();
                buffer_manager.insertString(updated_text) catch |err| {
                    std.debug.print("Failed to update buffer: {}\n", .{err});
                };

                // Add the word to the autocompletion engine
                autocomplete_engine.completeWord(suggestion) catch |err| {
                    std.debug.print("Error adding word to autocompletion: {}\n", .{err});
                };

                // Hide the suggestions UI
                autocomplete_ui_manager.hideSuggestions();
                return;
            }
        }

        // Fallback approach: use buffer manipulation
        std.debug.print("Using fallback approach for word replacement\n", .{});

        // First delete the current word by backspacing
        var i: usize = 0;
        while (i < current_word.len) : (i += 1) {
            buffer_manager.processBackspace() catch |err| {
                std.debug.print("Backspace error: {}\n", .{err});
                return;
            };
        }

        // Then insert the suggestion
        buffer_manager.insertString(suggestion) catch |err| {
            std.debug.print("Suggestion insertion error: {}\n", .{err});
            return;
        };

        // Add a space after the suggestion
        buffer_manager.insertString(" ") catch |err| {
            std.debug.print("Space insertion error: {}\n", .{err});
        };

        // Sync with text field
        syncTextFieldWithBuffer();

        // Add the word to the autocompletion engine
        autocomplete_engine.completeWord(suggestion) catch |err| {
            std.debug.print("Error adding word to autocompletion: {}\n", .{err});
        };

        // Hide the suggestions UI
        autocomplete_ui_manager.hideSuggestions();
    }
}

pub fn main() !void {
    // Initialize memory allocator
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the buffer manager
    buffer_manager = buffer.BufferManager.init(allocator);

    // Initialize the text field manager
    text_field_manager = detection.TextFieldManager.init(allocator);

    // Initialize the spellchecker
    spell_checker = try spellcheck.SpellChecker.init(allocator);
    defer spell_checker.deinit();

    // Initialize suggestions list
    suggestions = std.ArrayList([]const u8).init(allocator);
    defer {
        for (suggestions.items) |item| {
            allocator.free(item);
        }
        suggestions.deinit();
    }

    // Initialize the autocompletion engine
    autocomplete_engine = try autocomplete.AutocompleteEngine.init(allocator, &spell_checker.dictionary);
    defer autocomplete_engine.deinit();

    // Initialize autocompletion suggestions list
    autocomplete_suggestions = std.ArrayList([]const u8).init(allocator);
    defer {
        for (autocomplete_suggestions.items) |item| {
            allocator.free(item);
        }
        autocomplete_suggestions.deinit();
    }

    // Initialize the autocompletion UI
    const hInstance = win32.GetModuleHandleA(null);
    autocomplete_ui_manager = try autocomplete_ui.AutocompleteUI.init(allocator, hInstance);
    defer autocomplete_ui_manager.deinit();

    // Set up the selection callback
    autocomplete_ui_manager.setSelectionCallback(handleSuggestionSelection);

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
