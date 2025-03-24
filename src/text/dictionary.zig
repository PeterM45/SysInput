const std = @import("std");
const sysinput = @import("../sysinput.zig");

const debug = sysinput.core.debug;

/// Fallback dictionary of common English words in case file loading fails
/// This is much smaller than a full dictionary but provides basic functionality
pub const FALLBACK_WORDS = [_][]const u8{
    "the",  "be",  "to",  "of", "and",  "a",    "in", "that", "have", "I",
    "it",   "for", "not", "on", "with", "he",   "as", "you",  "do",   "at",
    "this", "but", "his", "by", "from", "they", "we", "say",  "her",  "she",
};

/// Dictionary structure for efficient word lookup
pub const Dictionary = struct {
    /// Word lookup map
    word_map: std.StringHashMap(void),
    /// Allocator used for the dictionary
    allocator: std.mem.Allocator,

    /// Initialize a new dictionary with words from a file
    /// Falls back to built-in common words if file loading fails
    pub fn init(allocator: std.mem.Allocator) !Dictionary {
        var dict = Dictionary{
            .word_map = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };

        // Try to load dictionary from multiple possible locations
        const dictionary_paths = [_][]const u8{
            "dictionary.txt", // Current directory
            "resources/dictionary.txt", // Resources subdirectory
            "../resources/dictionary.txt", // Up one level
            "../../resources/dictionary.txt", // Up two levels
        };

        var success = false;
        for (dictionary_paths) |path| {
            success = dict.loadFromFile(path) catch |err| {
                debug.debugPrint("Error loading dictionary from {s}: {}\n", .{ path, err });
                continue;
            };
            if (success) {
                debug.debugPrint("Successfully loaded dictionary from {s}\n", .{path});
                break;
            }
        }

        // If file loading failed, use fallback words
        if (!success) {
            debug.debugPrint("Could not find dictionary file, using fallback dictionary\n", .{});
            // Add fallback common words to the dictionary
            for (FALLBACK_WORDS) |word| {
                try dict.word_map.put(word, {});
            }
        }

        return dict;
    }

    /// Load dictionary words from a file
    /// Returns true if successful, false if file not found
    fn loadFromFile(self: *Dictionary, filename: []const u8) !bool {
        // Open the dictionary file
        const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return false;
            }
            return err;
        };
        defer file.close();

        // Read the file
        const stat = try file.stat();
        if (stat.size > 10_000_000) {
            // Limit dictionary size to prevent excessive memory usage
            return error.FileTooLarge;
        }

        // Allocate buffer for file content
        const buffer = try self.allocator.alloc(u8, @intCast(stat.size));
        defer self.allocator.free(buffer);

        // Read file content
        const bytes_read = try file.readAll(buffer);
        if (bytes_read != stat.size) {
            return error.ReadError;
        }

        // Define whitespace characters
        const whitespace = " \t\r\n";

        // Split file content by lines and add each word
        var line_iter = std.mem.splitScalar(u8, buffer, '\n');
        var word_count: usize = 0;

        while (line_iter.next()) |line| {
            // Skip empty lines
            if (line.len == 0) continue;

            // Trim whitespace manually
            var start: usize = 0;
            var end: usize = line.len;

            // Trim leading whitespace
            while (start < end and std.mem.indexOfScalar(u8, whitespace, line[start]) != null) {
                start += 1;
            }

            // Trim trailing whitespace
            while (end > start and std.mem.indexOfScalar(u8, whitespace, line[end - 1]) != null) {
                end -= 1;
            }

            const trimmed_line = line[start..end];

            // Skip if too short or too long
            if (trimmed_line.len < 2 or trimmed_line.len > 30) continue;

            // Create a lowercase copy that we'll own
            const owned_word = try self.allocator.dupe(u8, trimmed_line);
            errdefer self.allocator.free(owned_word);

            // Convert to lowercase
            for (owned_word) |*c| {
                c.* = std.ascii.toLower(c.*);
            }

            // Add to dictionary
            try self.word_map.put(owned_word, {});
            word_count += 1;
        }

        debug.debugPrint("Loaded {d} words from dictionary file\n", .{word_count});
        return true;
    }

    /// Deinitialize the dictionary and free resources
    pub fn deinit(self: *Dictionary) void {
        var it = self.word_map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.word_map.deinit();
    }

    /// Check if a word exists in the dictionary
    pub fn contains(self: Dictionary, word: []const u8) bool {
        // Create a lowercase copy of the word for case-insensitive comparison
        var buf: [256]u8 = undefined;
        if (word.len > buf.len) return false;

        var i: usize = 0;
        while (i < word.len) : (i += 1) {
            buf[i] = std.ascii.toLower(word[i]);
        }

        const lower_word = buf[0..word.len];
        return self.word_map.contains(lower_word);
    }

    /// Add a word to the dictionary
    pub fn addWord(self: *Dictionary, word: []const u8) !void {
        // Create a lowercase copy that we'll own
        const owned_word = try self.allocator.dupe(u8, word);
        errdefer self.allocator.free(owned_word);

        // Convert to lowercase
        for (owned_word) |*c| {
            c.* = std.ascii.toLower(c.*);
        }

        // Add to dictionary
        try self.word_map.put(owned_word, {});
    }
};
