const std = @import("std");
const sysinput = @import("root").sysinput;

const dict = sysinput.text.dictionary;
const edit_distance = sysinput.text.edit_distance;

/// Maximum number of suggestions to generate
const MAX_SUGGESTIONS = 5;

/// Spellchecker implementation
pub const SpellChecker = struct {
    /// The dictionary used for word lookup
    dictionary: dict.Dictionary,
    /// Allocator for dynamic memory
    allocator: std.mem.Allocator,

    /// Initialize a new spellchecker with the provided dictionary
    pub fn init(allocator: std.mem.Allocator) !SpellChecker {
        return SpellChecker{
            .dictionary = try dict.Dictionary.init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitialize the spellchecker and free resources
    pub fn deinit(self: *SpellChecker) void {
        self.dictionary.deinit();
    }

    /// Check if a word is spelled correctly
    pub fn isCorrect(self: SpellChecker, word: []const u8) bool {
        // Skip empty words, single characters, and words with digits
        if (word.len <= 1) return true;
        for (word) |c| {
            if (std.ascii.isDigit(c)) return true;
        }

        // Convert to lowercase for checking
        var buf: [256]u8 = undefined;
        if (word.len > buf.len) return false;

        var i: usize = 0;
        while (i < word.len) : (i += 1) {
            buf[i] = std.ascii.toLower(word[i]);
        }

        const lower_word = buf[0..word.len];
        return self.dictionary.contains(lower_word);
    }

    /// Get suggestions for a misspelled word
    pub fn getSuggestions(self: SpellChecker, word: []const u8, results: *std.ArrayList([]const u8)) !void {
        // Skip empty words, single characters, and words with digits
        if (word.len <= 1) return;
        for (word) |c| {
            if (std.ascii.isDigit(c)) return;
        }

        // Convert the input word to lowercase
        var buf: [256]u8 = undefined;
        if (word.len > buf.len) return;
        var i: usize = 0;
        while (i < word.len) : (i += 1) {
            buf[i] = std.ascii.toLower(word[i]);
        }
        const lower_word = buf[0..word.len];

        // If the word is correct and at least 3 characters, don't generate suggestions
        if (word.len >= 3 and self.dictionary.contains(lower_word)) return;

        // Create a priority queue for suggestions
        var suggestion_heap = std.PriorityQueue(edit_distance.Suggestion, void, edit_distance.compareForMinHeap).init(self.allocator, {});
        defer suggestion_heap.deinit();

        // First pass - find words starting with the input (completions)
        var completion_count: usize = 0;
        var dict_iter = self.dictionary.word_map.keyIterator();
        while (dict_iter.next()) |dict_word| {
            if (std.mem.startsWith(u8, dict_word.*, lower_word)) {
                // Don't suggest the exact input word
                if (std.mem.eql(u8, dict_word.*, lower_word)) continue;

                const score = edit_distance.calculateSuggestionScore(lower_word, dict_word.*);
                try suggestion_heap.add(edit_distance.Suggestion{ .word = dict_word.*, .score = score });
                completion_count += 1;
            }
        }

        // Second pass - add corrections only if we don't have enough completions
        if (completion_count < MAX_SUGGESTIONS) {
            dict_iter = self.dictionary.word_map.keyIterator();
            while (dict_iter.next()) |dict_word| {
                // Skip words we already considered as completions
                if (std.mem.startsWith(u8, dict_word.*, lower_word)) continue;

                // Calculate similarity score
                const score = edit_distance.calculateSuggestionScore(lower_word, dict_word.*);

                // Skip very low-scoring words
                if (score < -50) continue;

                try suggestion_heap.add(edit_distance.Suggestion{ .word = dict_word.*, .score = score });

                // Keep top suggestions
                if (suggestion_heap.count() > MAX_SUGGESTIONS * 3) {
                    _ = suggestion_heap.remove();
                }
            }
        }

        // Sort by score
        const num_suggestions = @min(suggestion_heap.count(), MAX_SUGGESTIONS);
        var temp_suggestions = try std.ArrayList(edit_distance.Suggestion).initCapacity(self.allocator, num_suggestions);
        defer temp_suggestions.deinit();

        while (suggestion_heap.count() > 0) {
            try temp_suggestions.append(suggestion_heap.remove());
        }

        // Sort by score (highest first)
        std.sort.pdq(edit_distance.Suggestion, temp_suggestions.items, {}, edit_distance.compareByScore);

        // Extract the best suggestions
        for (temp_suggestions.items) |suggestion| {
            if (results.items.len >= MAX_SUGGESTIONS) break;

            // Create a copy of the suggestion
            const owned_suggestion = try self.allocator.dupe(u8, suggestion.word);
            errdefer self.allocator.free(owned_suggestion);

            results.append(owned_suggestion) catch |err| {
                self.allocator.free(owned_suggestion);
                return err;
            };
        }
    }
};
