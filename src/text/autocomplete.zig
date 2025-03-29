const std = @import("std");
const sysinput = @import("root").sysinput;

const dict = sysinput.text.dictionary;
const insertion = sysinput.text.insertion;

/// Maximum number of suggestions to generate
const MAX_SUGGESTIONS = 5;

/// Autocompletion engine structure
pub const AutocompleteEngine = struct {
    /// Dictionary for base vocabulary
    dictionary: *dict.Dictionary,
    /// User's previously typed words with frequency count
    user_words: std.StringHashMap(u32),
    /// Allocator for dynamic memory
    allocator: std.mem.Allocator,
    /// Current partial word being typed
    current_word: []const u8,

    /// Initialize a new autocompletion engine
    pub fn init(allocator: std.mem.Allocator, dictionary: *dict.Dictionary) !AutocompleteEngine {
        return AutocompleteEngine{
            .dictionary = dictionary,
            .user_words = std.StringHashMap(u32).init(allocator),
            .allocator = allocator,
            .current_word = "",
        };
    }

    /// Clean up resources
    pub fn deinit(self: *AutocompleteEngine) void {
        var it = self.user_words.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.user_words.deinit();
    }

    /// Add a word to the user's vocabulary
    pub fn addWord(self: *AutocompleteEngine, word: []const u8) !void {
        // Don't add short words or empty strings
        if (word.len < 2) return;

        // Convert to lowercase
        var buf: [256]u8 = undefined;
        if (word.len > buf.len) return;

        var i: usize = 0;
        while (i < word.len) : (i += 1) {
            buf[i] = std.ascii.toLower(word[i]);
        }
        const lower_word = buf[0..word.len];

        // Check if the word is already in the user's words
        if (self.user_words.get(lower_word)) |count| {
            try self.user_words.put(lower_word, count + 1);
        } else {
            // Create a copy of the word that we'll own
            const owned_word = try self.allocator.dupe(u8, lower_word);
            errdefer self.allocator.free(owned_word);

            // Add it to the user's words with a count of 1
            try self.user_words.put(owned_word, 1);
        }
    }

    /// Set the current partial word being typed
    pub fn setCurrentWord(self: *AutocompleteEngine, word: []const u8) void {
        self.current_word = word;
    }

    /// Get suggestions based on the current partial word
    pub fn getSuggestions(self: *AutocompleteEngine, results: *std.ArrayList([]const u8)) !void {
        // Clear the results list first
        for (results.items) |item| {
            self.allocator.free(item);
        }
        results.clearRetainingCapacity();

        // Don't provide suggestions for very short partial words
        if (self.current_word.len < 1) return;

        // Convert to lowercase for matching
        var buf: [256]u8 = undefined;
        if (self.current_word.len > buf.len) return;

        var i: usize = 0;
        while (i < self.current_word.len) : (i += 1) {
            buf[i] = std.ascii.toLower(self.current_word[i]);
        }

        // First try user's words
        var user_words_added: usize = 0;
        var it = self.user_words.iterator();
        while (it.next()) |entry| {
            const word = entry.key_ptr.*;

            // If the word starts with the current partial word
            if (std.mem.startsWith(u8, word, buf[0..self.current_word.len]) and
                !std.mem.eql(u8, word, buf[0..self.current_word.len]))
            {
                // Create a copy of the word
                const owned_suggestion = try self.allocator.dupe(u8, word);
                try results.append(owned_suggestion);

                user_words_added += 1;
                if (user_words_added >= MAX_SUGGESTIONS) break;
            }
        }

        // If we don't have enough user words, add suggestions from dictionary
        if (user_words_added < MAX_SUGGESTIONS) {
            var dict_iter = self.dictionary.word_map.keyIterator();
            while (dict_iter.next()) |dict_word| {
                // If the dictionary word starts with the current partial word
                if (std.mem.startsWith(u8, dict_word.*, buf[0..self.current_word.len]) and
                    !std.mem.eql(u8, dict_word.*, buf[0..self.current_word.len]))
                {
                    // Create a copy of the word
                    const owned_suggestion = try self.allocator.dupe(u8, dict_word.*);
                    try results.append(owned_suggestion);

                    if (results.items.len >= MAX_SUGGESTIONS) break;
                }
            }
        }
    }

    /// Process text to extract and learn words
    pub fn processText(self: *AutocompleteEngine, text: []const u8) !void {
        var word_start: ?usize = null;

        for (text, 0..) |char, i| {
            if (insertion.isWordChar(char)) {
                if (word_start == null) {
                    word_start = i;
                }
            } else if (word_start != null) {
                // End of a word found
                const word = text[word_start.?..i];
                try self.addWord(word);
                word_start = null;
            }
        }

        // Handle a word at the end of text
        if (word_start != null) {
            const word = text[word_start.?..];
            try self.addWord(word);
        }
    }

    /// Update the engine with a newly completed word
    pub fn completeWord(self: *AutocompleteEngine, word: []const u8) !void {
        try self.addWord(word);
        self.current_word = "";
    }
};
