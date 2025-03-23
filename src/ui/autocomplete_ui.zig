const std = @import("std");
const common = @import("../win32/common.zig");

/// Inline completion UI manager
pub const AutocompleteUI = struct {
    /// Current suggestions
    suggestions: [][]const u8,
    /// Selected suggestion index
    selected_index: i32,
    /// Allocator for operations
    allocator: std.mem.Allocator,
    /// Whether suggestions are active
    is_visible: bool,
    /// Current text in the control
    current_text: []const u8,
    /// Current partial word
    current_word: []const u8,
    /// Current best suggestion
    current_suggestion: ?[]const u8,
    /// Callback for completing a suggestion
    selection_callback: ?*const fn ([]const u8) void,

    /// Initialize the inline completion
    pub fn init(allocator: std.mem.Allocator, instance: common.HINSTANCE) !AutocompleteUI {
        _ = instance; // Not used in this implementation

        return AutocompleteUI{
            .suggestions = &[_][]const u8{},
            .selected_index = -1,
            .allocator = allocator,
            .is_visible = false,
            .current_text = "",
            .current_word = "",
            .current_suggestion = null,
            .selection_callback = null,
        };
    }

    /// Process suggestions for the current text
    pub fn showSuggestions(self: *AutocompleteUI, suggestions: [][]const u8, x: i32, y: i32) !void {
        _ = x; // Not used in this implementation
        _ = y; // Not used in this implementation

        self.suggestions = suggestions;
        self.selected_index = 0;

        // If we have suggestions, mark as visible and try to apply the first one
        if (suggestions.len > 0) {
            self.is_visible = true;
            self.current_suggestion = suggestions[0];

            // Try to apply the suggestion via text selection
            tryInlineCompletion(self.current_word, self.current_suggestion.?);
        } else {
            self.is_visible = false;
            self.current_suggestion = null;
        }
    }

    /// Set current text context
    pub fn setTextContext(self: *AutocompleteUI, full_text: []const u8, current_word: []const u8) void {
        self.current_text = full_text;
        self.current_word = current_word;
    }

    /// Hide the suggestions
    pub fn hideSuggestions(self: *AutocompleteUI) void {
        self.is_visible = false;
        self.current_suggestion = null;
    }

    /// Set the callback for suggestion selection
    pub fn setSelectionCallback(self: *AutocompleteUI, callback: *const fn ([]const u8) void) void {
        self.selection_callback = callback;
    }

    /// Select a suggestion by index
    pub fn selectSuggestion(self: *AutocompleteUI, index: i32) void {
        if (index >= 0 and index < self.suggestions.len) {
            self.selected_index = index;
            self.current_suggestion = self.suggestions[@intCast(index)];

            // Try to apply the new suggestion
            tryInlineCompletion(self.current_word, self.current_suggestion.?);
        }
    }

    /// Accept the current suggestion
    pub fn acceptSuggestion(self: *AutocompleteUI) void {
        if (self.is_visible and self.current_suggestion != null and self.selection_callback != null) {
            self.selection_callback.?(self.current_suggestion.?);
            self.hideSuggestions();
        }
    }

    /// Clean up resources
    pub fn deinit(self: *AutocompleteUI) void {
        // No resources to clean up in this implementation
        _ = self;
    }
};

/// Try to apply inline completion using text selection
fn tryInlineCompletion(partial_word: []const u8, suggestion: []const u8) void {
    // Only proceed if the suggestion starts with the partial word
    if (partial_word.len == 0 or !std.mem.startsWith(u8, suggestion, partial_word)) {
        return;
    }

    // Get the active window and control
    const hwnd = common.GetForegroundWindow();
    if (hwnd == null) return;

    // Get the control with focus (usually the text field)
    const focus_hwnd = common.GetFocus();
    if (focus_hwnd == null) return;

    // Try to get selection/position in text field
    var start: common.DWORD = undefined;
    var end: common.DWORD = undefined;

    // Try different methods to get text selection based on control type
    // Cast to isize since LPARAM is isize
    if (common.SendMessageA(focus_hwnd.?, common.EM_GETSEL, @as(common.WPARAM, @intFromPtr(&start)), @as(common.LPARAM, @intCast(@intFromPtr(&end)))) != 0) {
        // We found a selection, now complete the word

        // Calculate what part of the word we need to add
        const completion = suggestion[partial_word.len..];

        // First, position the cursor at the end of the partial word
        _ = common.SendMessageA(focus_hwnd.?, common.EM_SETSEL, end, end);

        // Insert the completion text as a selected block
        insertTextAsSelection(focus_hwnd.?, completion);
    }
}

/// Insert text as a selected block
fn insertTextAsSelection(hwnd: common.HWND, text: []const u8) void {
    // Create null-terminated text
    const buffer = std.heap.page_allocator.allocSentinel(u8, text.len, 0) catch return;
    defer std.heap.page_allocator.free(buffer);

    // Copy the text to the buffer using @memcpy instead of std.mem.copy
    @memcpy(buffer, text);

    // Insert the text - cast to LPARAM (isize)
    _ = common.SendMessageA(hwnd, common.EM_REPLACESEL, 1, @as(common.LPARAM, @intCast(@intFromPtr(buffer.ptr))));

    // Get current selection
    var start: common.DWORD = undefined;
    var end: common.DWORD = undefined;
    _ = common.SendMessageA(hwnd, common.EM_GETSEL, @as(common.WPARAM, @intFromPtr(&start)), @as(common.LPARAM, @intCast(@intFromPtr(&end))));

    // Select just the inserted text
    _ = common.SendMessageA(hwnd, common.EM_SETSEL, start - text.len, end);
}
