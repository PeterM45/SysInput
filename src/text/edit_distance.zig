const std = @import("std");
const sysinput = @import("../sysinput.zig");

const config = sysinput.core.config;

/// Maximum edit distance to consider for suggestions
pub const MAX_EDIT_DISTANCE = config.BEHAVIOR.MAX_EDIT_DISTANCE;

/// A word suggestion with scoring
pub const Suggestion = struct {
    /// The suggested word
    word: []const u8,
    /// Score for this suggestion (higher is better)
    score: i32,
};

/// Compare two suggestions for priority queue ordering (for min-heap)
pub fn compareForMinHeap(context: void, a: Suggestion, b: Suggestion) std.math.Order {
    _ = context;
    return std.math.order(a.score, b.score); // Keep lowest scores in queue
}

/// Compare two suggestions for sorting (for final results)
pub fn compareByScore(context: void, a: Suggestion, b: Suggestion) bool {
    _ = context;
    return a.score > b.score; // Higher score comes first
}

/// Calculate Levenshtein edit distance between two strings with enhancements
pub fn enhancedEditDistance(a: []const u8, b: []const u8) usize {
    // Handle simple cases immediately
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;
    if (std.mem.eql(u8, a, b)) return 0; // Identical strings

    // Early termination for strings with very different lengths
    const len_diff = if (a.len > b.len) a.len - b.len else b.len - a.len;
    if (len_diff > MAX_EDIT_DISTANCE) {
        return len_diff; // Will exceed max distance anyway, so return early
    }

    // Quick check of first few characters
    if (a.len > 2 and b.len > 2) {
        var diff_count: usize = 0;
        const check_len = @min(3, @min(a.len, b.len));

        for (0..check_len) |i| {
            if (a[i] != b[i]) {
                diff_count += 1;
            }
        }

        // If first few chars are very different, likely a poor match
        if (diff_count >= 2) {
            return MAX_EDIT_DISTANCE + 1; // Return value that exceeds our threshold
        }
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

            // Lower substitution cost for similar characters (e.g., i/y, o/a)
            var substitution_cost = v0[j];
            if (a[i] != b[j]) {
                // Check for common character substitutions
                const is_similar = ((a[i] == 'a' and b[j] == 'e') or
                    (a[i] == 'e' and b[j] == 'a') or
                    (a[i] == 'i' and b[j] == 'y') or
                    (a[i] == 'y' and b[j] == 'i') or
                    (a[i] == 'o' and b[j] == 'u') or
                    (a[i] == 'u' and b[j] == 'o') or
                    (a[i] == 'c' and b[j] == 'k') or
                    (a[i] == 'k' and b[j] == 'c') or
                    (a[i] == 's' and b[j] == 'z') or
                    (a[i] == 'z' and b[j] == 's'));

                substitution_cost += if (is_similar) @as(usize, 1) else 2;
            }

            // Use the minimum cost operation
            v1[j + 1] = @min(deletion_cost, @min(insertion_cost, substitution_cost));

            // Bonus for transposition (e.g., "teh" -> "the")
            if (i > 0 and j > 0 and a[i] == b[j - 1] and a[i - 1] == b[j]) {
                v1[j + 1] = @min(v1[j + 1], v0[j - 1] + 1);
            }
        }

        // Swap v0 and v1
        i = 0;
        while (i <= b.len) : (i += 1) {
            v0[i] = v1[i];
        }
    }

    return v0[b.len];
}

/// Calculate a suggestion score for word similarity with prefix matching for autocompletion
pub fn calculateSuggestionScore(input_word: []const u8, candidate_word: []const u8) i32 {
    // Strongly favor words that start with the input (completion candidates)
    const is_prefix = std.mem.startsWith(u8, candidate_word, input_word);

    if (is_prefix) {
        // Special case for completion - high base score
        var score: i32 = 50;

        // Shorter completions are often better (e.g., "help" vs "helping" for "hel")
        const completion_length = candidate_word.len - input_word.len;

        // Ideal completion length is 2-5 characters longer than the input
        if (completion_length <= 5) {
            score += 10;
        } else if (completion_length > 10) {
            // Penalize very long completions
            score -= @as(i32, @intCast(completion_length - 10));
        }

        // Favor common shorter words
        if (candidate_word.len <= 6) {
            score += 5;
        }

        return score;
    }

    // Not a prefix - calculate similarity as a correction
    // Skip words with very different lengths
    if (candidate_word.len < input_word.len / 2 or candidate_word.len > input_word.len * 2) {
        return -1000; // Very low score
    }

    // Calculate basic edit distance
    const distance = enhancedEditDistance(input_word, candidate_word);

    // Too dissimilar
    if (distance > MAX_EDIT_DISTANCE) {
        return -1000; // Very low score
    }

    // Start with a base score based on edit distance
    var score: i32 = @intCast(10 - distance * 3);

    // Bonus for starting with the same letter
    if (input_word.len > 0 and candidate_word.len > 0 and input_word[0] == candidate_word[0]) {
        score += 5;
    }

    // Penalty for length difference
    const len_diff = if (candidate_word.len > input_word.len)
        candidate_word.len - input_word.len
    else
        input_word.len - candidate_word.len;

    score -= @as(i32, @intCast(len_diff * 2));

    // Bonus for common prefix
    var prefix_len: usize = 0;
    const min_len = @min(candidate_word.len, input_word.len);
    while (prefix_len < min_len and candidate_word[prefix_len] == input_word[prefix_len]) {
        prefix_len += 1;
    }
    score += @as(i32, @intCast(prefix_len * 3));

    // Bonus for common suffix
    var suffix_len: usize = 0;
    while (suffix_len < min_len and
        candidate_word[candidate_word.len - 1 - suffix_len] ==
            input_word[input_word.len - 1 - suffix_len])
    {
        suffix_len += 1;
    }
    score += @as(i32, @intCast(suffix_len * 2));

    // Bonus for frequently used words
    if (candidate_word.len <= 4) {
        // Shorter words are often more common
        score += 2;
    }

    return score;
}

/// Word similarity as a percentage (100% = identical)
pub fn wordSimilarityPercent(a: []const u8, b: []const u8) f32 {
    const distance = enhancedEditDistance(a, b);
    const max_len = @max(a.len, b.len);
    if (max_len == 0) return 100.0;

    const dist_float: f32 = @floatFromInt(distance);
    const len_float: f32 = @floatFromInt(max_len);
    return (1.0 - dist_float / len_float) * 100.0;
}
