const std = @import("std");
const dict = @import("dictionary.zig");

/// Maximum number of suggestions to generate
const MAX_SUGGESTIONS = 5;

/// Maximum edit distance to consider for suggestions
const MAX_EDIT_DISTANCE = 2;

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

        return self.dictionary.contains(word);
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

        // If the word is correct, don't generate suggestions
        if (self.dictionary.contains(lower_word)) return;

        // Find words with similar edit distance
        var suggestion_heap = std.PriorityQueue(Suggestion, void, compareSuggestion).init(self.allocator, {});
        defer suggestion_heap.deinit();

        // Check all words in the dictionary
        var dict_iter = self.dictionary.word_map.keyIterator();
        while (dict_iter.next()) |dict_word| {
            const distance = levenshteinDistance(lower_word, dict_word.*);
            if (distance <= MAX_EDIT_DISTANCE) {
                try suggestion_heap.add(Suggestion{ .word = dict_word.*, .distance = distance });
                if (suggestion_heap.count() > MAX_SUGGESTIONS) {
                    _ = suggestion_heap.remove();
                }
            }
        }

        // Extract from heap in order
        while (suggestion_heap.count() > 0) {
            const suggestion = suggestion_heap.remove();
            const owned_suggestion = try self.allocator.dupe(u8, suggestion.word);
            errdefer self.allocator.free(owned_suggestion);
            try results.append(owned_suggestion);
        }
    }
};

/// A word suggestion with edit distance
const Suggestion = struct {
    /// The suggested word
    word: []const u8,
    /// Edit distance from the original word (lower is better)
    distance: usize,
};

/// Compare two suggestions for priority queue ordering
fn compareSuggestion(context: void, a: Suggestion, b: Suggestion) std.math.Order {
    _ = context;
    return std.math.order(b.distance, a.distance); // Lower distance is better
}

/// Calculate Levenshtein edit distance between two strings
fn levenshteinDistance(a: []const u8, b: []const u8) usize {
    // Handle edge cases
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    // Skip calculation for strings with very different lengths (optimization)
    const len_diff = if (a.len > b.len) a.len - b.len else b.len - a.len;
    if (len_diff > MAX_EDIT_DISTANCE) {
        return len_diff; // Return early as this will exceed our max edit distance
    }

    // Early return for strings that share no characters at all
    var has_common_char = false;
    for (a) |char_a| {
        for (b) |char_b| {
            if (char_a == char_b) {
                has_common_char = true;
                break;
            }
        }
        if (has_common_char) break;
    }

    const long_enough = a.len > 2 or b.len > 2;
    if (!has_common_char and long_enough) {
        return @max(a.len, b.len); // Return early for completely different strings
    }

    // Efficiently calculate using dynamic programming
    var v0: [256]usize = undefined;
    var v1: [256]usize = undefined;

    // Initialize first row
    var i: usize = 0;
    while (i <= b.len) : (i += 1) {
        v0[i] = i;
    }

    // Calculate rows
    i = 0;
    while (i < a.len) : (i += 1) {
        v1[0] = i + 1;

        var j: usize = 0;
        while (j < b.len) : (j += 1) {
            const deletion_cost = v0[j + 1] + 1;
            const insertion_cost = v1[j] + 1;
            const substitution_cost = v0[j] + @as(usize, if (a[i] == b[j]) 0 else 1);
            v1[j + 1] = @min(deletion_cost, @min(insertion_cost, substitution_cost));
        }

        // Swap v0 and v1
        i = 0;
        while (i <= b.len) : (i += 1) {
            v0[i] = v1[i];
        }
    }

    return v0[b.len];
}

/// Calculate word similarity as a percentage (100% = identical)
pub fn wordSimilarity(a: []const u8, b: []const u8) f32 {
    const distance = levenshteinDistance(a, b);
    const max_len = @max(a.len, b.len);
    if (max_len == 0) return 100.0;

    const dist_float: f32 = @floatFromInt(distance);
    const len_float: f32 = @floatFromInt(max_len);
    return (1.0 - dist_float / len_float) * 100.0;
}

// Unit tests
test "levenshtein distance" {
    try std.testing.expectEqual(@as(usize, 0), levenshteinDistance("kitten", "kitten"));
    try std.testing.expectEqual(@as(usize, 1), levenshteinDistance("kitten", "sitten"));
    try std.testing.expectEqual(@as(usize, 2), levenshteinDistance("kitten", "sittin"));
    try std.testing.expectEqual(@as(usize, 3), levenshteinDistance("kitten", "sitting"));
    try std.testing.expectEqual(@as(usize, 3), levenshteinDistance("saturday", "sunday"));
}

test "spell checker basic functionality" {
    const allocator = std.testing.allocator;

    var checker = try SpellChecker.init(allocator);
    defer checker.deinit();

    // Test correct words
    try std.testing.expect(checker.isCorrect("the"));
    try std.testing.expect(checker.isCorrect("code"));
    try std.testing.expect(checker.isCorrect("function"));

    // Test incorrect words
    try std.testing.expect(!checker.isCorrect("teh"));
    try std.testing.expect(!checker.isCorrect("codd"));
    try std.testing.expect(!checker.isCorrect("functoin"));

    // Test suggestions
    var suggestions_list = std.ArrayList([]const u8).init(allocator);
    defer {
        for (suggestions_list.items) |item| {
            allocator.free(item);
        }
        suggestions_list.deinit();
    }

    try checker.getSuggestions("teh", &suggestions_list);
    try std.testing.expect(suggestions_list.items.len > 0);

    // Check if "the" is among the suggestions
    var found = false;
    for (suggestions_list.items) |suggestion| {
        if (std.mem.eql(u8, suggestion, "the")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}
