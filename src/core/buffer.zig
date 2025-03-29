const std = @import("std");
const sysinput = @import("root").sysinput;

const debug = sysinput.core.debug;
const insertion = sysinput.text.insertion;

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
    /// The actual text content with gap
    content: [MAX_BUFFER_SIZE]u8,
    /// Continuous representation for quick access
    continuous_content: [MAX_BUFFER_SIZE]u8,
    /// Current length of the text in the buffer
    length: usize,
    /// Current cursor position (gap start)
    gap_start: usize,
    /// Gap end position
    gap_end: usize,
    /// Gap size (gap_end - gap_start)
    gap_size: usize,
    /// Current cursor position info
    cursor: CursorPosition,
    /// Text allocator for any dynamic operations
    allocator: std.mem.Allocator,
    /// Indicates if continuous_content needs updating
    content_dirty: bool,

    /// Initialize a new, empty text buffer
    pub fn init(allocator: std.mem.Allocator) TextBuffer {
        const gap_size = MAX_BUFFER_SIZE / 2;
        return TextBuffer{
            .content = [_]u8{0} ** MAX_BUFFER_SIZE,
            .continuous_content = [_]u8{0} ** MAX_BUFFER_SIZE,
            .length = 0,
            .gap_start = 0,
            .gap_end = gap_size,
            .gap_size = gap_size,
            .cursor = CursorPosition{ .offset = 0, .line = 0, .column = 0 },
            .allocator = allocator,
            .content_dirty = false,
        };
    }

    /// Insert a character at the current cursor position
    pub fn insertChar(self: *TextBuffer, char: u8) !void {
        if (self.length >= MAX_BUFFER_SIZE - self.gap_size) {
            return error.BufferFull;
        }

        // Validate character
        if (char == 0 or (char < 32 and char != '\n' and char != '\r' and char != '\t')) {
            debug.debugPrint("Ignoring invalid character: 0x{X}\n", .{char});
            return;
        }

        // Insert at gap start
        self.content[self.gap_start] = char;
        self.gap_start += 1;
        self.gap_size -= 1;
        self.length += 1;
        self.content_dirty = true;

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
        if (self.gap_start == 0 or self.length == 0) {
            return error.NothingToDelete;
        }

        // Check if we're deleting a newline
        const isNewline = self.content[self.gap_start - 1] == '\n';

        // Just move the gap start backward
        self.gap_start -= 1;
        self.gap_size += 1;
        self.length -= 1;
        self.content_dirty = true;
        self.cursor.offset -= 1;

        if (isNewline) {
            self.cursor.line -= 1;
            // Calculate new column position
            var col: usize = 0;

            // Need to use the continuous representation for this
            self.updateContinuousContent();
            var pos = self.cursor.offset - 1;
            while (pos > 0 and self.continuous_content[pos] != '\n') : (pos -= 1) {
                col += 1;
            }
            self.cursor.column = col;
        } else {
            self.cursor.column -= 1;
        }
    }

    /// Delete a character after the cursor position (delete key)
    pub fn deleteCharForward(self: *TextBuffer) !void {
        if (self.gap_start >= self.length) {
            return error.NothingToDelete;
        }

        // For gap buffer, we need to check character at gap_end
        self.updateContinuousContent();
        const isNewline = self.continuous_content[self.cursor.offset] == '\n';

        // For a gap buffer, deleting forward is just increasing the gap_end
        self.gap_end += 1;
        self.gap_size += 1;
        self.length -= 1;
        self.content_dirty = true;

        // No need to update cursor position for forward delete
        // unless we're specifically tracking line wrapping
        if (isNewline) {
            // Just reduce line count if we're tracking it
            // Full line count would need to be recalculated for more complex edits
        }
    }

    /// Move cursor left by one character
    pub fn moveCursorLeft(self: *TextBuffer) void {
        if (self.cursor.offset == 0) return;

        // First move cursor
        self.cursor.offset -= 1;

        // Then update gap position to match cursor
        if (self.cursor.offset < self.gap_start) {
            // Need to move the gap backward
            // Move the last character before the gap to after the gap
            self.content[self.gap_end - 1] = self.content[self.gap_start - 1];
            self.gap_start -= 1;
            self.gap_end -= 1;
            self.content_dirty = true;
        }

        if (self.cursor.column > 0) {
            self.cursor.column -= 1;
        } else if (self.cursor.line > 0) {
            // We're at the beginning of a line, move up to the end of the previous line
            self.cursor.line -= 1;

            // Calculate the column position (length of the previous line)
            self.updateContinuousContent();
            var col: usize = 0;
            var pos = self.cursor.offset;
            while (pos > 0 and self.continuous_content[pos - 1] != '\n') : (pos -= 1) {
                col += 1;
            }
            self.cursor.column = col;
        }
    }

    /// Move cursor right by one character
    pub fn moveCursorRight(self: *TextBuffer) void {
        if (self.cursor.offset >= self.length) return;

        // First update line tracking
        self.updateContinuousContent();
        if (self.cursor.offset < self.length and
            self.continuous_content[self.cursor.offset] == '\n')
        {
            self.cursor.line += 1;
            self.cursor.column = 0;
        } else {
            self.cursor.column += 1;
        }

        // Next move cursor
        self.cursor.offset += 1;

        // Then update gap position to match cursor
        if (self.cursor.offset > self.gap_start) {
            // Need to move the gap forward
            // Move the first character after the gap to before the gap
            self.content[self.gap_start] = self.content[self.gap_end];
            self.gap_start += 1;
            self.gap_end += 1;
            self.content_dirty = true;
        }
    }

    /// Update the continuous content from the gap buffer
    fn updateContinuousContent(self: *TextBuffer) void {
        if (!self.content_dirty) return;

        // Copy the content before the gap
        @memcpy(self.continuous_content[0..self.gap_start], self.content[0..self.gap_start]);

        // Copy the content after the gap
        const after_gap_len = self.length - self.gap_start;
        if (after_gap_len > 0) {
            @memcpy(self.continuous_content[self.gap_start..self.length], self.content[self.gap_end .. self.gap_end + after_gap_len]);
        }

        self.content_dirty = false;
    }

    /// Get the current text content as a string slice
    pub fn getContent(self: *TextBuffer) []const u8 {
        self.updateContinuousContent();
        return self.continuous_content[0..self.length];
    }

    /// Get the current word under the cursor
    pub fn getCurrentWord(self: TextBuffer) ![]const u8 {
        // If cursor is at the end or buffer is empty
        if (self.length == 0 or self.cursor.offset > self.length) {
            return "";
        }

        var word_buffer: [MAX_BUFFER_SIZE]u8 = undefined;
        var self_copy = self;
        const content = self_copy.getContent();

        // Find word boundaries
        var start = self.cursor.offset;
        var end = self.cursor.offset;

        // Find the start of the word
        while (start > 0 and insertion.isWordChar(content[start - 1])) {
            start -= 1;
        }

        // Find the end of the word
        while (end < content.len and insertion.isWordChar(content[end])) {
            end += 1;
        }

        // Validate the word - check for null bytes or other issues
        if (end - start > word_buffer.len) {
            debug.debugPrint("Word too long for buffer\n", .{});
            return "";
        }

        const word = content[start..end];
        for (word) |c| {
            if (c == 0 or !std.ascii.isPrint(c)) {
                // Found a null or non-printable character
                debug.debugPrint("Warning: Found invalid character in word\n", .{});
                return "";
            }
        }

        // Copy to buffer and return
        @memcpy(word_buffer[0..word.len], word);
        return word_buffer[0..word.len];
    }

    /// Clear the buffer
    pub fn clear(self: *TextBuffer) void {
        self.length = 0;
        self.gap_start = 0;
        self.gap_end = MAX_BUFFER_SIZE / 2;
        self.gap_size = self.gap_end - self.gap_start;
        self.cursor = CursorPosition{ .offset = 0, .line = 0, .column = 0 };
        self.content_dirty = true;
    }
};

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
    pub fn getCurrentText(self: *BufferManager) []const u8 {
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
