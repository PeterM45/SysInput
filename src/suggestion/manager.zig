const std = @import("std");
const sysinput = @import("root").sysinput;

const api = sysinput.win32.api;
const spellcheck = sysinput.text.spellcheck;
const autocomplete = sysinput.text.autocomplete;
const suggestion_ui = sysinput.ui.suggestion_ui;
const buffer_controller = sysinput.buffer_controller;
const debug = sysinput.core.debug;
const position = sysinput.ui.position;
const insertion = sysinput.text.insertion;
const window_detection = sysinput.input.window_detection;
const stats = sysinput.suggestion.stats;
const config = sysinput.core.config;

/// Global variables for allocator access
var gpa_allocator: std.mem.Allocator = undefined;

/// Stats instance
var stats_instance = sysinput.suggestion.stats.init();

/// Global spellchecker
pub var spell_checker: spellcheck.SpellChecker = undefined;

/// Global autocompletion engine
pub var autocomplete_engine: autocomplete.AutocompleteEngine = undefined;

/// List for storing word suggestions
pub var suggestions: std.ArrayList([]const u8) = undefined;

/// Autocompletion suggestions list
pub var autocomplete_suggestions: std.ArrayList([]const u8) = undefined;

/// Global UI for autocompletion suggestions
pub var autocomplete_ui_manager: suggestion_ui.AutocompleteUI = undefined;

/// Last word processed for suggestions
pub var last_word: [256]u8 = undefined;
pub var last_word_len: usize = 0;

// Replace the clearSuggestions function with this:
pub fn clearSuggestions() void {
    // Destroy the entire list and create a new one
    autocomplete_suggestions.deinit();
    autocomplete_suggestions = std.ArrayList([]const u8).init(gpa_allocator);
}

// Update getAutocompleteSuggestions
pub fn getAutocompleteSuggestions() !void {
    // Get current word
    const current_word = autocomplete_engine.current_word;

    // Skip processing if the word hasn't changed
    if (current_word.len > 0 and current_word.len == last_word_len and
        std.mem.eql(u8, current_word, last_word[0..last_word_len]) and
        autocomplete_suggestions.items.len > 0)
    {
        return error.NoSuggestionsNeeded;
    }

    // Store current word for next comparison
    if (current_word.len > 0 and current_word.len < last_word.len) {
        @memcpy(last_word[0..current_word.len], current_word);
        last_word_len = current_word.len;
    } else {
        // Too long or empty
        last_word_len = 0;
    }

    // Clear suggestions by recreating the list
    clearSuggestions();

    // Get new suggestions
    try autocomplete_engine.getSuggestions(&autocomplete_suggestions);
}

/// Initialize suggestion handling components
pub fn init(allocator: std.mem.Allocator, module_instance: anytype) !void {
    gpa_allocator = allocator;

    // Initialize spellchecker
    spell_checker = try spellcheck.SpellChecker.init(allocator);

    // Initialize suggestions lists
    suggestions = std.ArrayList([]const u8).init(allocator);
    autocomplete_suggestions = std.ArrayList([]const u8).init(allocator);

    // Initialize autocompletion engine
    autocomplete_engine = try autocomplete.AutocompleteEngine.init(allocator, &spell_checker.dictionary);

    // Initialize UI
    autocomplete_ui_manager = try suggestion_ui.AutocompleteUI.init(allocator, module_instance);

    // Set callback
    autocomplete_ui_manager.setSelectionCallback(handleSuggestionSelection);

    // Reset stats
    stats_instance = sysinput.suggestion.stats.init();
}

/// Process a text for autocomplete suggestions
pub fn processTextForSuggestions(text: []const u8) !void {
    try autocomplete_engine.processText(text);
}

/// Set current word for autocompletion
pub fn setCurrentWord(word: []const u8) void {
    autocomplete_engine.setCurrentWord(word);
}

/// Check if a word is spelled correctly
pub fn isWordCorrect(word: []const u8) bool {
    return spell_checker.isCorrect(word);
}

/// Get spelling suggestions for a word
pub fn getSpellingSuggestions(word: []const u8) !void {
    // Clear existing suggestions
    for (suggestions.items) |item| {
        gpa_allocator.free(item);
    }
    suggestions.clearRetainingCapacity();

    // Get suggestions
    try spell_checker.getSuggestions(word, &suggestions);
}

/// Show suggestions in UI
pub fn showSuggestions(current_text: []const u8, current_word: []const u8, x: i32, y: i32) !void {
    debug.debugPrint("Handler showSuggestions called with word '{s}'\n", .{current_word});
    debug.debugPrint("Have {d} suggestions to display\n", .{autocomplete_suggestions.items.len});

    // Print first few suggestions
    for (autocomplete_suggestions.items, 0..) |sugg, i| {
        if (i < 5) {
            debug.debugPrint("  Suggestion {d}: '{s}'\n", .{ i, sugg });
        }
    }

    // Use config for minimum word length to show suggestions
    if (autocomplete_suggestions.items.len > 0 and
        current_word.len >= config.BEHAVIOR.MIN_TRIGGER_LEN)
    {
        // Only show suggestions if auto-show is enabled
        if (config.BEHAVIOR.AUTO_SHOW_SUGGESTIONS) {
            // Set context
            autocomplete_ui_manager.setTextContext(current_text, current_word);

            // Show suggestions at the specified position
            try autocomplete_ui_manager.showSuggestions(autocomplete_suggestions.items, x, y);

            // Update stats
            if (config.STATS.COLLECT_STATS) {
                sysinput.suggestion.stats.recordSuggestionShown(&stats_instance);
            }
        }
    } else {
        debug.debugPrint("No suggestions to show (word len: {d})\n", .{current_word.len});
        hideSuggestions();
    }
}

/// Update the position of suggestions if visible
pub fn updateSuggestionPosition() void {
    if (autocomplete_ui_manager.is_visible) {
        const pos = position.getCaretPosition();
        if (pos.x != 0 or pos.y != 0) {
            // Offset below caret
            autocomplete_ui_manager.updatePosition(pos.x, pos.y + 20);
        }
    }
}

/// Enhanced suggestion word replacement that tries multiple methods
/// Returns true if successful
pub fn replaceSuggestionWord(current_word: []const u8, suggestion: []const u8) bool {
    debug.debugPrint("Replacing word '{s}' with '{s}'\n", .{ current_word, suggestion });

    // Skip if no word to replace
    if (current_word.len == 0) {
        debug.debugPrint("No current word to replace\n", .{});
        return false;
    }

    // Track metrics and timing
    sysinput.suggestion.stats.recordInsertionAttempt(&stats_instance);
    const start_time = std.time.milliTimestamp();

    // Get focus window for class detection
    const focus_hwnd = api.getFocus();
    var success = false;

    // Add this at the top of replaceSuggestionWord function
    if (focus_hwnd != null) {
        // Use direct Windows API call to get raw class name
        var raw_class: [128]u8 = undefined;
        const raw_class_len = api.GetClassNameA(focus_hwnd.?, @ptrCast(&raw_class), 128);

        if (raw_class_len > 0) {
            const class_str = raw_class[0..@intCast(raw_class_len)];
            debug.debugPrint("Raw window class: '{s}' (len: {d})\n", .{ class_str, raw_class_len });

            // Check if it contains "Edit" or "Notepad" case-insensitively
            var is_notepad = false;

            // Check each character in lowercase
            for (0..class_str.len - 3) |i| {
                if (i + 4 <= class_str.len) {
                    const slice = class_str[i .. i + 4];
                    if (std.ascii.eqlIgnoreCase(slice, "edit")) {
                        is_notepad = true;
                        break;
                    }
                }

                if (i + 7 <= class_str.len) {
                    const slice = class_str[i .. i + 7];
                    if (std.ascii.eqlIgnoreCase(slice, "notepad")) {
                        is_notepad = true;
                        break;
                    }
                }
            }

            // For common Windows Notepad class
            if (class_str.len == 5 and std.ascii.eqlIgnoreCase(class_str, "Notepad")) {
                is_notepad = true;
            }

            // Also check for generic Windows text control classes
            if (class_str.len == 4 and std.ascii.eqlIgnoreCase(class_str, "Edit")) {
                is_notepad = true;
            }

            if (is_notepad) {
                debug.debugPrint("*** NOTEPAD DETECTED! ***\n", .{});

                // Now use direct key simulation for Notepad
                debug.debugPrint("Using key simulation for Notepad\n", .{});

                // Set window to foreground to ensure it receives input
                _ = api.setForegroundWindow(focus_hwnd.?);

                // 1. Delete the current word with backspace
                for (0..current_word.len) |_| {
                    // Send backspace character by character
                    var input: api.INPUT = undefined;
                    input.type = api.INPUT_KEYBOARD;
                    input.ki.wVk = api.VK_BACK;
                    input.ki.wScan = 0;
                    input.ki.dwFlags = 0; // Key down
                    input.ki.time = 0;
                    input.ki.dwExtraInfo = 0;
                    _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                    // Key up
                    input.ki.dwFlags = api.KEYEVENTF_KEYUP;
                    _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                    api.sleep(5); // Short delay between keys
                }

                // 2. Insert the suggestion character by character
                for (suggestion) |c| {
                    // Send character using unicode method
                    var input: api.INPUT = undefined;
                    input.type = api.INPUT_KEYBOARD;
                    input.ki.wVk = 0;
                    input.ki.wScan = c;
                    input.ki.dwFlags = api.KEYEVENTF_UNICODE;
                    input.ki.time = 0;
                    input.ki.dwExtraInfo = 0;
                    _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                    // Key up
                    input.ki.dwFlags = api.KEYEVENTF_UNICODE | api.KEYEVENTF_KEYUP;
                    _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                    api.sleep(5); // Short delay between keys
                }

                // 3. Add a space
                var space_input: api.INPUT = undefined;
                space_input.type = api.INPUT_KEYBOARD;
                space_input.ki.wVk = api.VK_SPACE;
                space_input.ki.wScan = 0;
                space_input.ki.dwFlags = 0;
                space_input.ki.time = 0;
                space_input.ki.dwExtraInfo = 0;
                _ = api.sendInput(1, &space_input, @sizeOf(api.INPUT));

                // Key up
                space_input.ki.dwFlags = api.KEYEVENTF_KEYUP;
                _ = api.sendInput(1, &space_input, @sizeOf(api.INPUT));

                // 4. Update buffer manually
                resyncBufferWithTextField();

                // Add to autocomplete engine
                autocomplete_engine.completeWord(suggestion) catch {};

                debug.debugPrint("Key simulation completed\n", .{});
                success = true;
                return true;
            } else {
                debug.debugPrint("Not a Notepad/Edit window\n", .{});
            }
        }
    }

    // Fallback to backspace-and-type approach
    if (!success) {
        debug.debugPrint("Using backspace-and-type approach\n", .{});

        // Delete the current word by backspacing
        var i: usize = 0;
        while (i < current_word.len) : (i += 1) {
            buffer_controller.processBackspace() catch |err| {
                debug.debugPrint("Backspace error: {}\n", .{err});
                return false;
            };
        }

        // Insert the suggestion
        buffer_controller.insertString(suggestion) catch |err| {
            debug.debugPrint("Suggestion insertion error: {}\n", .{err});
            return false;
        };

        // Add a space after the suggestion
        buffer_controller.insertString(" ") catch |err| {
            debug.debugPrint("Space insertion error: {}\n", .{err});
        };

        // Add to autocomplete engine
        autocomplete_engine.completeWord(suggestion) catch |err| {
            debug.debugPrint("Error adding word to autocomplete: {}\n", .{err});
        };

        debug.debugPrint("Backspace-and-type approach succeeded\n", .{});
        success = true;
    }

    // Update metrics
    if (success) {
        sysinput.suggestion.stats.recordInsertionSuccess(&stats_instance);
    }

    // Record timing
    const elapsed = std.time.milliTimestamp() - start_time;
    sysinput.suggestion.stats.recordInsertionTime(&stats_instance, @intCast(elapsed));

    debug.debugPrint("Word replacement {s} after {d}ms\n", .{ if (success) "succeeded" else "failed", elapsed });

    return success;
}

/// Handle suggestion selection from the autocomplete UI
pub fn handleSuggestionSelection(suggestion: []const u8) void {
    // Get the current word being typed
    debug.debugPrint("Handling suggestion selection for: '{s}'\n", .{suggestion});

    const current_word = buffer_controller.getCurrentWord() catch {
        debug.debugPrint("Error getting current word\n", .{});
        return;
    };

    // If there's a current word, replace it with the suggestion
    if (current_word.len > 0) {
        debug.debugPrint("Current word: '{s}'\n", .{current_word});

        // Simply call replaceSuggestionWord which contains all the logic
        if (replaceSuggestionWord(current_word, suggestion)) {
            // Update stats
            sysinput.suggestion.stats.recordSuggestionAccepted(&stats_instance);
        }
    }
}

/// Accept the current suggestion
pub fn acceptCurrentSuggestion() void {
    if (!autocomplete_ui_manager.is_visible or autocomplete_ui_manager.current_suggestion == null) {
        return;
    }

    const suggestion = autocomplete_ui_manager.current_suggestion.?;
    debug.debugPrint("Accepting suggestion: '{s}'\n", .{suggestion});

    // Get the current word
    const current_word = buffer_controller.getCurrentWord() catch {
        debug.debugPrint("Error getting current word\n", .{});
        return;
    };

    if (current_word.len == 0) {
        debug.debugPrint("No current word to replace\n", .{});
        return;
    }

    debug.debugPrint("Replacing '{s}' with '{s}'\n", .{ current_word, suggestion });

    // Try multiple methods to get the target window
    var target_hwnd: ?api.HWND = null;

    // 1. First try GetFocus to get directly focused control
    target_hwnd = api.getFocus();
    if (target_hwnd != null) {
        debug.debugPrint("Using focused window\n", .{});
    }
    // 2. If that fails, try text_field_manager's active field
    else if (buffer_controller.text_field_manager.has_active_field) {
        target_hwnd = buffer_controller.text_field_manager.active_field.handle;
        debug.debugPrint("Using text field manager's active field\n", .{});
    }
    // 3. Last resort: use foreground window
    else {
        target_hwnd = api.getForegroundWindow();
        debug.debugPrint("Using foreground window\n", .{});
    }

    if (target_hwnd == null) {
        debug.debugPrint("Could not find any target window\n", .{});
        return;
    }

    // Try to ensure window has focus
    _ = api.setForegroundWindow(target_hwnd.?);

    // Get the preferred method for this window class
    const method = window_detection.getPreferredMethodForWindow(target_hwnd.?);
    var success = false;

    // Record insertion attempt
    if (config.STATS.COLLECT_STATS) {
        sysinput.suggestion.stats.recordInsertionAttempt(&stats_instance);
    }
    const start_time = std.time.milliTimestamp();

    // Try the preferred method first
    success = insertion.tryInsertionMethod(target_hwnd.?, current_word, suggestion, method, gpa_allocator);

    // If preferred method failed, try others in fallback order
    if (!success) {
        debug.debugPrint("Preferred method failed, trying fallbacks\n", .{});
        const fallback_methods = [_]u8{
            @intFromEnum(insertion.InsertMethod.Clipboard),
            @intFromEnum(insertion.InsertMethod.KeySimulation),
            @intFromEnum(insertion.InsertMethod.DirectMessage),
        };

        for (fallback_methods) |fallback_method| {
            if (fallback_method == method) continue; // Skip the already-tried method

            success = insertion.tryInsertionMethod(target_hwnd.?, current_word, suggestion, fallback_method, gpa_allocator);
            if (success) break;
        }
    }

    // If any method succeeded
    if (success) {
        // Remember this successful method for this window class
        window_detection.storeSuccessfulMethod(target_hwnd.?, method, gpa_allocator);

        // Wait for the changes to take effect
        api.sleep(config.PERFORMANCE.TEXT_INSERTION_DELAY_MS);

        // Force text field detection
        buffer_controller.detectActiveTextField();

        // Manually update buffer with suggestion + space if configured
        buffer_controller.resetBuffer();
        buffer_controller.insertString(suggestion) catch |err| {
            debug.debugPrint("Failed to update buffer with suggestion: {}\n", .{err});
        };

        // Add space if configured
        if (config.BEHAVIOR.INSERT_SPACE_AFTER_COMPLETION) {
            buffer_controller.insertString(" ") catch |err| {
                debug.debugPrint("Failed to add space to buffer: {}\n", .{err});
            };
        }

        // Add to vocabulary if learning is enabled
        if (config.BEHAVIOR.LEARN_FROM_ACCEPTED) {
            autocomplete_engine.completeWord(suggestion) catch |err| {
                debug.debugPrint("Error adding to vocabulary: {}\n", .{err});
            };
        }

        // Update stats if enabled
        if (config.STATS.COLLECT_STATS) {
            sysinput.suggestion.stats.recordInsertionSuccess(&stats_instance);
            sysinput.suggestion.stats.recordSuggestionAccepted(&stats_instance);
            sysinput.suggestion.stats.recordMethodSuccess(&stats_instance, method);
        }
    } else {
        debug.debugPrint("All text replacement methods failed\n", .{});
    }

    // Record timing if stats enabled
    if (config.STATS.COLLECT_STATS) {
        const elapsed = std.time.milliTimestamp() - start_time;
        sysinput.suggestion.stats.recordInsertionTime(&stats_instance, @intCast(elapsed));
    }

    // Hide suggestions UI regardless of success
    hideSuggestions();
}

/// Hide suggestions UI
pub fn hideSuggestions() void {
    autocomplete_ui_manager.hideSuggestions();
}

/// Resync the buffer with the text field after modification
fn resyncBufferWithTextField() void {
    if (!buffer_controller.hasActiveTextField()) {
        return;
    }

    const text = buffer_controller.getActiveFieldText() catch |err| {
        debug.debugPrint("Failed to get updated text: {}\n", .{err});
        return;
    };
    defer gpa_allocator.free(text);

    buffer_controller.resetBuffer();
    buffer_controller.insertString(text) catch |err| {
        debug.debugPrint("Failed to update buffer: {}\n", .{err});
    };
}

/// Check if suggestions UI is visible
pub fn isSuggestionUIVisible() bool {
    return autocomplete_ui_manager.is_visible;
}

/// Navigate to previous suggestion
pub fn navigateToPreviousSuggestion() void {
    // Move to previous suggestion
    const new_index = if (autocomplete_ui_manager.selected_index <= 0)
        @as(i32, @intCast(autocomplete_suggestions.items.len - 1))
    else
        autocomplete_ui_manager.selected_index - 1;

    autocomplete_ui_manager.selectSuggestion(new_index);
    debug.debugPrint("Selected previous suggestion (index {})\n", .{new_index});
}

/// Navigate to next suggestion
pub fn navigateToNextSuggestion() void {
    // Move to next suggestion
    const new_index = if (autocomplete_ui_manager.selected_index >= autocomplete_suggestions.items.len - 1)
        0
    else
        autocomplete_ui_manager.selected_index + 1;

    autocomplete_ui_manager.selectSuggestion(new_index);
    debug.debugPrint("Selected next suggestion (index {})\n", .{new_index});
}

/// Get selected suggestion index
pub fn getSelectedSuggestionIndex() i32 {
    return autocomplete_ui_manager.selected_index;
}

/// Select a suggestion by index
pub fn selectSuggestion(index: i32) void {
    autocomplete_ui_manager.selectSuggestion(index);
}

/// Get number of available suggestions
pub fn getSuggestionCount() usize {
    return autocomplete_suggestions.items.len;
}

/// Add a word to the autocompletion engine's vocabulary
pub fn addWordToVocabulary(word: []const u8) !void {
    try autocomplete_engine.addWord(word);
}

/// Deinitialize components
pub fn deinit() void {
    // Free resources
    suggestions.deinit();
    autocomplete_suggestions.deinit();

    spell_checker.deinit();
    autocomplete_engine.deinit();
    autocomplete_ui_manager.deinit();
}
