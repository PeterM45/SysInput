const std = @import("std");
const sysinput = @import("root").sysinput;

const dict = sysinput.text.dictionary;
const insertion = sysinput.win32.insertion;
const config = sysinput.core.config;
const debug = sysinput.core.debug;

/// Maximum number of suggestions to generate
const MAX_SUGGESTIONS = config.TEXT.MAX_SUGGESTIONS;

/// Recent suggestion cache to avoid recalculating
const SuggestionCache = struct {
    /// The input word that generated these suggestions
    input: [config.TEXT.MAX_SUGGESTION_LEN]u8,
    /// Input length (since input might contain garbage past this)
    input_len: usize,
    /// The cached suggestions
    suggestions: [MAX_SUGGESTIONS][]const u8,
    /// Number of valid suggestions in the cache
    count: usize,
    /// Whether the cache is valid
    valid: bool,

    pub fn init() SuggestionCache {
        return .{
            .input = [_]u8{0} ** config.TEXT.MAX_SUGGESTION_LEN,
            .input_len = 0,
            .suggestions = [_][]const u8{""} ** MAX_SUGGESTIONS,
            .count = 0,
            .valid = false,
        };
    }

    pub fn isMatch(self: *const SuggestionCache, input: []const u8) bool {
        // If caching is disabled in config, always return false
        if (!config.PERFORMANCE.USE_SUGGESTION_CACHE) return false;

        if (!self.valid or input.len != self.input_len) return false;
        return std.mem.eql(u8, input, self.input[0..self.input_len]);
    }

    pub fn update(self: *SuggestionCache, input: []const u8, new_suggestions: [][]const u8) void {
        if (input.len >= self.input.len) return; // Too long for our cache

        @memcpy(self.input[0..input.len], input);
        self.input_len = input.len;

        self.count = @min(new_suggestions.len, MAX_SUGGESTIONS);
        for (0..self.count) |i| {
            self.suggestions[i] = new_suggestions[i];
        }

        self.valid = true;
    }

    pub fn invalidate(self: *SuggestionCache) void {
        self.valid = false;
        self.count = 0;
    }
};

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
    /// Suggestion cache for performance
    cache: SuggestionCache,

    /// Initialize a new autocompletion engine
    pub fn init(allocator: std.mem.Allocator, dictionary: *dict.Dictionary) !AutocompleteEngine {
        return AutocompleteEngine{
            .dictionary = dictionary,
            .user_words = std.StringHashMap(u32).init(allocator),
            .allocator = allocator,
            .current_word = "",
            .cache = SuggestionCache.init(),
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
        // Don't add words that are too short (using config value)
        if (word.len < config.BEHAVIOR.MIN_TRIGGER_LEN) return;

        // Convert to lowercase
        var buf: [config.TEXT.MAX_SUGGESTION_LEN]u8 = undefined;
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

        // Invalidate suggestion cache whenever vocabulary changes
        self.cache.invalidate();
    }

    /// Set the current partial word being typed
    pub fn setCurrentWord(self: *AutocompleteEngine, word: []const u8) void {
        // Only update if the word has changed
        if (!std.mem.eql(u8, self.current_word, word)) {
            self.current_word = word;
        }
    }

    /// Check if a string starts with a prefix (case-insensitive)
    fn startsWithInsensitive(haystack: []const u8, needle: []const u8) bool {
        if (needle.len > haystack.len) return false;

        for (needle, 0..) |n_char, i| {
            const h_char = haystack[i];
            if (std.ascii.toLower(h_char) != std.ascii.toLower(n_char)) {
                return false;
            }
        }

        return true;
    }

    /// Get suggestions based on the current partial word
    pub fn getSuggestions(self: *AutocompleteEngine, results: *std.ArrayList([]const u8)) !void {
        // Clear existing suggestions
        for (results.items) |item| {
            self.allocator.free(item);
        }
        results.clearRetainingCapacity();

        // Don't provide suggestions for very short partial words (using config)
        if (self.current_word.len < config.BEHAVIOR.MIN_TRIGGER_LEN) return;

        // Check cache first
        if (self.cache.isMatch(self.current_word)) {
            debug.debugPrint("Using cached suggestions for '{s}'\n", .{self.current_word});

            // Copy cached suggestions to results
            for (0..self.cache.count) |i| {
                const cached_suggestion = self.cache.suggestions[i];
                const owned_suggestion = try self.allocator.dupe(u8, cached_suggestion);
                try results.append(owned_suggestion);
            }
            return;
        }

        // Convert to lowercase for matching
        var buf: [config.TEXT.MAX_SUGGESTION_LEN]u8 = undefined;
        if (self.current_word.len > buf.len) return;

        var i: usize = 0;
        while (i < self.current_word.len) : (i += 1) {
            buf[i] = std.ascii.toLower(self.current_word[i]);
        }
        const lower_word = buf[0..self.current_word.len];

        // Pre-allocate a buffer to track highest frequency user words
        var top_user_words = std.BoundedArray(struct { word: []const u8, freq: u32 }, MAX_SUGGESTIONS).init(0) catch unreachable;

        // First scan user's words - We'll collect top N by frequency instead of just taking the first N
        var it = self.user_words.iterator();
        var words_checked: usize = 0;
        const max_words_to_check = config.PERFORMANCE.MAX_USER_WORDS_TO_CHECK;

        while (it.next()) |entry| {
            const word = entry.key_ptr.*;
            const freq = entry.value_ptr.*;

            // Limit the number of words we check for performance
            words_checked += 1;
            if (words_checked > max_words_to_check) break;

            // If the word starts with the current partial word (and isn't exactly the same)
            if (startsWithInsensitive(word, lower_word) and
                !std.mem.eql(u8, word, lower_word))
            {
                // Add to our bounded array, maintaining sorting by frequency
                if (top_user_words.len < MAX_SUGGESTIONS) {
                    // Just add it if we have room
                    try top_user_words.append(.{ .word = word, .freq = freq });
                    // Insertion sort to keep it sorted by frequency (highest first)
                    var j = top_user_words.len - 1;
                    while (j > 0 and top_user_words.get(j).freq > top_user_words.get(j - 1).freq) {
                        const temp = top_user_words.get(j);
                        top_user_words.set(j, top_user_words.get(j - 1));
                        top_user_words.set(j - 1, temp);
                        j -= 1;
                    }
                } else if (freq > top_user_words.get(top_user_words.len - 1).freq) {
                    // Replace lowest frequency word if this one is higher
                    top_user_words.set(top_user_words.len - 1, .{ .word = word, .freq = freq });
                    // Bubble up to maintain sorting
                    var j = top_user_words.len - 1;
                    while (j > 0 and top_user_words.get(j).freq > top_user_words.get(j - 1).freq) {
                        const temp = top_user_words.get(j);
                        top_user_words.set(j, top_user_words.get(j - 1));
                        top_user_words.set(j - 1, temp);
                        j -= 1;
                    }
                }
            }
        }

        // Add top user words to results
        for (0..top_user_words.len) |idx| {
            const word = top_user_words.get(idx).word;
            const owned_suggestion = try self.allocator.dupe(u8, word);
            try results.append(owned_suggestion);
        }

        // If we don't have enough user words, add suggestions from dictionary
        if (top_user_words.len < MAX_SUGGESTIONS) {
            // Track how many more suggestions we need
            const needed = MAX_SUGGESTIONS - top_user_words.len;

            var dict_iter = self.dictionary.word_map.keyIterator();
            var dict_count: usize = 0;

            while (dict_iter.next()) |dict_word| {
                // If the dictionary word starts with the current partial word
                if (startsWithInsensitive(dict_word.*, lower_word) and
                    !std.mem.eql(u8, dict_word.*, lower_word))
                {
                    // Skip if this word is already in our results (from user words)
                    var skip = false;
                    for (0..top_user_words.len) |j| {
                        if (std.mem.eql(u8, dict_word.*, top_user_words.get(j).word)) {
                            skip = true;
                            break;
                        }
                    }

                    if (!skip) {
                        // Create a copy of the word
                        const owned_suggestion = try self.allocator.dupe(u8, dict_word.*);
                        try results.append(owned_suggestion);

                        dict_count += 1;
                        if (dict_count >= needed) break;
                    }
                }
            }
        }

        // Update cache with these new suggestions
        if (results.items.len > 0) {
            self.cache.update(self.current_word, results.items);
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

        // Reset cache when a word is completed
        self.cache.invalidate();
    }
};
