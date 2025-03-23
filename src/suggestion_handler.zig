const std = @import("std");
const sysinput = @import("sysinput.zig");

const api = sysinput.win32.api;
const spellcheck = sysinput.text.spellcheck;
const autocomplete = sysinput.text.autocomplete;
const suggestion_ui = sysinput.ui.suggestion_ui;
const text_inject = sysinput.win32.text_inject;
const buffer_controller = sysinput.buffer_controller;
const dictionary = sysinput.text.dictionary;

/// Global variables for allocator access
var gpa_allocator: std.mem.Allocator = undefined;

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
pub var last_word_processed: []const u8 = "";

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
}

/// Deinitialize components
pub fn deinit() void {
    // Free resources
    for (suggestions.items) |item| {
        gpa_allocator.free(item);
    }
    suggestions.deinit();

    for (autocomplete_suggestions.items) |item| {
        gpa_allocator.free(item);
    }
    autocomplete_suggestions.deinit();

    spell_checker.deinit();
    autocomplete_engine.deinit();
    autocomplete_ui_manager.deinit();
}

/// Process a text for autocomplete suggestions
pub fn processTextForSuggestions(text: []const u8) !void {
    try autocomplete_engine.processText(text);
}

/// Set current word for autocompletion
pub fn setCurrentWord(word: []const u8) void {
    autocomplete_engine.setCurrentWord(word);
}

/// Get autocompletion suggestions
pub fn getAutocompleteSuggestions() !void {
    // Skip processing if the word hasn't changed
    if (std.mem.eql(u8, autocomplete_engine.current_word, last_word_processed) and
        autocomplete_suggestions.items.len > 0)
    {
        return;
    }

    // Store the current word as the last processed
    const current_word = autocomplete_engine.current_word;
    const owned_word = try gpa_allocator.dupe(u8, current_word);
    if (last_word_processed.len > 0) {
        gpa_allocator.free(last_word_processed);
    }
    last_word_processed = owned_word;

    // Clear existing suggestions
    autocomplete_suggestions.clearRetainingCapacity();

    // Get new suggestions
    try autocomplete_engine.getSuggestions(&autocomplete_suggestions);
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
pub fn showSuggestions(current_text: []const u8, current_word: []const u8) !void {
    if (autocomplete_suggestions.items.len > 0 and current_word.len >= 2) {
        // Set context
        autocomplete_ui_manager.setTextContext(current_text, current_word);

        // Show suggestions
        try autocomplete_ui_manager.showSuggestions(autocomplete_suggestions.items, 0, 0);
    } else {
        hideSuggestions();
    }
}

/// Hide suggestions UI
pub fn hideSuggestions() void {
    autocomplete_ui_manager.hideSuggestions();
}

/// Handle suggestion selection from the autocomplete UI
pub fn handleSuggestionSelection(suggestion: []const u8) void {
    // Get the current word being typed
    const current_word = buffer_controller.getCurrentWord() catch {
        std.debug.print("Error getting current word\n", .{});
        return;
    };

    // If there's a current word, replace it with the suggestion
    if (current_word.len > 0) {
        std.debug.print("Replacing word \"{s}\" with suggestion \"{s}\"\n", .{ current_word, suggestion });

        // Approach 1: Try using the text field directly with smart selection
        if (buffer_controller.hasActiveTextField()) {
            const focus_hwnd = api.GetFocus();
            if (focus_hwnd != null) {
                // Try multiple approaches to detect and select the current word

                // 1. First try: Get current selection and guess word boundaries
                const selection = api.SendMessageA(focus_hwnd.?, api.EM_GETSEL, 0, 0);
                const sel_u64: u64 = @bitCast(selection);
                const end_pos: u32 = @truncate((sel_u64 >> 16) & 0xFFFF);

                // Calculate the start of the current word
                const start_pos = if (end_pos >= current_word.len)
                    end_pos - current_word.len
                else
                    0;

                // Select the current word
                _ = api.SendMessageA(focus_hwnd.?, api.EM_SETSEL, start_pos, end_pos);

                // Try more reliable replacement methods
                const replacement = suggestion;

                // Try direct insertion first
                if (text_inject.insertTextAsSelection(focus_hwnd.?, replacement)) {
                    // Now append a space using the same method
                    _ = text_inject.insertTextAsSelection(focus_hwnd.?, " ");

                    // Force a synchronization of our buffer
                    const updated_text = buffer_controller.getActiveFieldText() catch |err| {
                        std.debug.print("Failed to get updated text: {}\n", .{err});
                        return;
                    };
                    defer gpa_allocator.free(updated_text);

                    buffer_controller.resetBuffer();
                    buffer_controller.insertString(updated_text) catch |err| {
                        std.debug.print("Failed to update buffer: {}\n", .{err});
                    };

                    // Add the word to the autocompletion engine
                    autocomplete_engine.completeWord(suggestion) catch |err| {
                        std.debug.print("Error adding word to autocompletion: {}\n", .{err});
                    };

                    // Hide the suggestions UI
                    hideSuggestions();
                    return;
                }
            }
        }

        // Fallback approach: use buffer manipulation
        std.debug.print("Using fallback approach for word replacement\n", .{});

        // First delete the current word by backspacing
        var i: usize = 0;
        while (i < current_word.len) : (i += 1) {
            buffer_controller.processBackspace() catch |err| {
                std.debug.print("Backspace error: {}\n", .{err});
                return;
            };
        }

        // Then insert the suggestion
        buffer_controller.insertString(suggestion) catch |err| {
            std.debug.print("Suggestion insertion error: {}\n", .{err});
            return;
        };

        // Add a space after the suggestion
        buffer_controller.insertString(" ") catch |err| {
            std.debug.print("Space insertion error: {}\n", .{err});
        };

        // Add the word to the autocompletion engine
        autocomplete_engine.completeWord(suggestion) catch |err| {
            std.debug.print("Error adding word to autocompletion: {}\n", .{err});
        };

        // Hide the suggestions UI
        hideSuggestions();
    }
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
    std.debug.print("Selected previous suggestion (index {})\n", .{new_index});
}

/// Navigate to next suggestion
pub fn navigateToNextSuggestion() void {
    // Move to next suggestion
    const new_index = if (autocomplete_ui_manager.selected_index >= autocomplete_suggestions.items.len - 1)
        0
    else
        autocomplete_ui_manager.selected_index + 1;

    autocomplete_ui_manager.selectSuggestion(new_index);
    std.debug.print("Selected next suggestion (index {})\n", .{new_index});
}

/// Accept the current suggestion
pub fn acceptCurrentSuggestion() void {
    std.debug.print("Accepting current suggestion\n", .{});
    autocomplete_ui_manager.acceptSuggestion();
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
