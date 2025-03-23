const std = @import("std");

/// Maximum text buffer size
const MAX_BUFFER_SIZE = 4096;

/// Represents a position in the text buffer
pub const CursorPosition = struct {
    /// Character offset from the start of the buffer
    offset: usize,
    /// Line number (0-based)
    line: usize,
    /// Column number (0-based)
    column: usize,
};

/// The main text buffer structure
pub const TextBuffer = struct {
    /// The actual text content
    content: [MAX_BUFFER_SIZE]u8,
    /// Current length of the text in the buffer
    length: usize,
    /// Current cursor position
    cursor: CursorPosition,
    /// Text allocator for any dynamic operations
    allocator: std.mem.Allocator,

    /// Initialize a new, empty text buffer
    pub fn init(allocator: std.mem.Allocator) TextBuffer {
        return TextBuffer{
            .content = [_]u8{0} ** MAX_BUFFER_SIZE,
            .length = 0,
            .cursor = CursorPosition{ .offset = 0, .line = 0, .column = 0 },
            .allocator = allocator,
        };
    }

    /// Insert a character at the current cursor position
    pub fn insertChar(self: *TextBuffer, char: u8) !void {
        if (self.length >= MAX_BUFFER_SIZE - 1) {
            return error.BufferFull;
        }

        // Make space for the new character
        var i = self.length;
        while (i > self.cursor.offset) : (i -= 1) {
            self.content[i] = self.content[i - 1];
        }

        // Insert the character
        self.content[self.cursor.offset] = char;
        self.length += 1;

        // Update cursor position
        self.cursor.offset += 1;
        self.cursor.column += 1;

        // Handle newline character
        if (char == '\n') {
            self.cursor.line += 1;
            self.cursor.column = 0;
        }
    }

    /// Insert a string at the current cursor position
    pub fn insertString(self: *TextBuffer, str: []const u8) !void {
        for (str) |char| {
            try self.insertChar(char);
        }
    }

    /// Delete a character before the cursor position (backspace)
    pub fn deleteCharBackward(self: *TextBuffer) !void {
        if (self.cursor.offset == 0 or self.length == 0) {
            return error.NothingToDelete;
        }

        // Check if we're deleting a newline
        const isNewline = self.content[self.cursor.offset - 1] == '\n';

        // Shift content to the left
        var i = self.cursor.offset - 1;
        while (i < self.length - 1) : (i += 1) {
            self.content[i] = self.content[i + 1];
        }

        self.length -= 1;
        self.cursor.offset -= 1;

        if (isNewline) {
            self.cursor.line -= 1;
            // Calculate new column position
            var col: usize = 0;
            var pos = self.cursor.offset - 1;
            while (pos > 0 and self.content[pos] != '\n') : (pos -= 1) {
                col += 1;
            }
            self.cursor.column = col;
        } else {
            self.cursor.column -= 1;
        }
    }

    /// Delete a character after the cursor position (delete key)
    pub fn deleteCharForward(self: *TextBuffer) !void {
        if (self.cursor.offset >= self.length) {
            return error.NothingToDelete;
        }

        // Check if we're deleting a newline
        const isNewline = self.content[self.cursor.offset] == '\n';

        // Shift content to the left
        var i = self.cursor.offset;
        while (i < self.length - 1) : (i += 1) {
            self.content[i] = self.content[i + 1];
        }

        self.length -= 1;

        // No need to update cursor position for forward delete
        // unless we're specifically tracking line wrapping
        if (isNewline) {
            // Handle line count update but cursor position stays the same
        }
    }

    /// Move cursor left by one character
    pub fn moveCursorLeft(self: *TextBuffer) void {
        if (self.cursor.offset == 0) return;

        self.cursor.offset -= 1;

        if (self.cursor.column > 0) {
            self.cursor.column -= 1;
        } else if (self.cursor.line > 0) {
            // We're at the beginning of a line, move up to the end of the previous line
            self.cursor.line -= 1;

            // Calculate the column position (length of the previous line)
            var col: usize = 0;
            var pos = self.cursor.offset;
            while (pos > 0 and self.content[pos - 1] != '\n') : (pos -= 1) {
                col += 1;
            }
            self.cursor.column = col;
        }
    }

    /// Move cursor right by one character
    pub fn moveCursorRight(self: *TextBuffer) void {
        if (self.cursor.offset >= self.length) return;

        if (self.content[self.cursor.offset] == '\n') {
            self.cursor.line += 1;
            self.cursor.column = 0;
        } else {
            self.cursor.column += 1;
        }

        self.cursor.offset += 1;
    }

    /// Get the current text content as a string slice
    pub fn getContent(self: TextBuffer) []const u8 {
        return self.content[0..self.length];
    }

    /// Get the current word under the cursor
    pub fn getCurrentWord(self: TextBuffer) ![]const u8 {
        // If cursor is at the end or buffer is empty
        if (self.length == 0 or self.cursor.offset > self.length) {
            return "";
        }

        // Find word boundaries
        var start = self.cursor.offset;
        var end = self.cursor.offset;

        // Find the start of the word
        while (start > 0 and isWordChar(self.content[start - 1])) {
            start -= 1;
        }

        // Find the end of the word
        while (end < self.length and isWordChar(self.content[end])) {
            end += 1;
        }

        return self.content[start..end];
    }

    /// Clear the buffer
    pub fn clear(self: *TextBuffer) void {
        self.length = 0;
        self.cursor = CursorPosition{ .offset = 0, .line = 0, .column = 0 };
    }
};

/// Check if a character is part of a word
fn isWordChar(c: u8) bool {
    // Only include letters, numbers, underscore, and apostrophe (for contractions)
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '\'';
}

/// Text buffer manager to handle multiple text fields across applications
pub const BufferManager = struct {
    /// The active text buffer being edited
    active_buffer: TextBuffer,
    /// Whether the buffer has changed since last checked
    changed: bool,
    /// Allocator for buffer operations
    allocator: std.mem.Allocator,

    /// Initialize the buffer manager
    pub fn init(allocator: std.mem.Allocator) BufferManager {
        return BufferManager{
            .active_buffer = TextBuffer.init(allocator),
            .changed = false,
            .allocator = allocator,
        };
    }

    /// Process a key press and update the buffer
    pub fn processKeyPress(self: *BufferManager, key: u8, is_char: bool) !void {
        if (is_char) {
            try self.active_buffer.insertChar(key);
            self.changed = true;
        }
    }

    /// Insert a string into the buffer
    pub fn insertString(self: *BufferManager, str: []const u8) !void {
        try self.active_buffer.insertString(str);
        self.changed = true;
    }

    /// Process backspace key
    pub fn processBackspace(self: *BufferManager) !void {
        try self.active_buffer.deleteCharBackward();
        self.changed = true;
    }

    /// Process delete key
    pub fn processDelete(self: *BufferManager) !void {
        try self.active_buffer.deleteCharForward();
        self.changed = true;
    }

    /// Get the current text buffer content
    pub fn getCurrentText(self: BufferManager) []const u8 {
        return self.active_buffer.getContent();
    }

    /// Get the current word at cursor position
    pub fn getCurrentWord(self: BufferManager) ![]const u8 {
        return try self.active_buffer.getCurrentWord();
    }

    /// Clear the changed flag
    pub fn clearChanged(self: *BufferManager) void {
        self.changed = false;
    }

    /// Reset the active buffer
    pub fn resetBuffer(self: *BufferManager) void {
        self.active_buffer.clear();
        self.changed = false;
    }
};
