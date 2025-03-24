const std = @import("std");

/// Statistics for tracking suggestion usage
pub const SuggestionStats = struct {
    /// Total suggestions shown
    total_shown: u32 = 0,
    /// Suggestions accepted
    accepted: u32 = 0,
    /// Success rate for insertions
    insertion_success_rate: f32 = 0.0,
    /// Total insertion attempts
    insertion_attempts: u32 = 0,
    /// Successful insertions
    insertion_success: u32 = 0,
    /// Timing stats in milliseconds
    average_insertion_time_ms: f32 = 0.0,
    /// Total insertion time (for average calculation)
    total_insertion_time_ms: u64 = 0,
    /// Method success counts
    clipboard_success: u32 = 0,
    key_simulation_success: u32 = 0,
    direct_message_success: u32 = 0,
};

/// Create new stats tracker
pub fn init() SuggestionStats {
    return SuggestionStats{};
}

/// Record a suggestion being shown
pub fn recordSuggestionShown(stats: *SuggestionStats) void {
    stats.total_shown += 1;
}

/// Record a suggestion being accepted
pub fn recordSuggestionAccepted(stats: *SuggestionStats) void {
    stats.accepted += 1;
}

/// Record an insertion attempt
pub fn recordInsertionAttempt(stats: *SuggestionStats) void {
    stats.insertion_attempts += 1;
}

/// Record a successful insertion
pub fn recordInsertionSuccess(stats: *SuggestionStats) void {
    stats.insertion_success += 1;
    updateSuccessRate(stats);
}

/// Record method-specific success
pub fn recordMethodSuccess(stats: *SuggestionStats, method: u8) void {
    switch (method) {
        0 => stats.clipboard_success += 1,
        1 => stats.key_simulation_success += 1,
        2 => stats.direct_message_success += 1,
        else => {}, // Unknown method
    }
}

/// Record insertion timing
pub fn recordInsertionTime(stats: *SuggestionStats, time_ms: u64) void {
    stats.total_insertion_time_ms += time_ms;
    if (stats.insertion_success > 0) {
        stats.average_insertion_time_ms = @floatFromInt(stats.total_insertion_time_ms);
        stats.average_insertion_time_ms /= @floatFromInt(stats.insertion_success);
    }
}

/// Update the insertion success rate
fn updateSuccessRate(stats: *SuggestionStats) void {
    if (stats.insertion_attempts > 0) {
        stats.insertion_success_rate = @as(f32, @floatFromInt(stats.insertion_success)) /
            @as(f32, @floatFromInt(stats.insertion_attempts)) * 100.0;
    }
}

/// Get the current insertion success rate
pub fn getInsertionSuccessRate(stats: SuggestionStats) f32 {
    return stats.insertion_success_rate;
}

/// Get a formatted string with stats summary
/// Caller must free the returned string
pub fn getStatsSummary(stats: SuggestionStats, allocator: std.mem.Allocator) ![]const u8 {
    var success_percent: f32 = 0;
    var accepted_percent: f32 = 0;

    if (stats.insertion_attempts > 0) {
        success_percent = stats.insertion_success_rate;
    }

    if (stats.total_shown > 0) {
        accepted_percent = @as(f32, @floatFromInt(stats.accepted)) /
            @as(f32, @floatFromInt(stats.total_shown)) * 100.0;
    }

    return try std.fmt.allocPrint(allocator,
        \\Suggestion Stats:
        \\  Shown: {d}
        \\  Accepted: {d} ({d:.1}%)
        \\  Insertion Success: {d}/{d} ({d:.1}%)
        \\  Avg Insertion Time: {d:.1}ms
        \\  Methods Success:
        \\    Clipboard: {d}
        \\    Key Simulation: {d}
        \\    Direct Message: {d}
        \\
    , .{
        stats.total_shown,
        stats.accepted,
        accepted_percent,
        stats.insertion_success,
        stats.insertion_attempts,
        success_percent,
        stats.average_insertion_time_ms,
        stats.clipboard_success,
        stats.key_simulation_success,
        stats.direct_message_success,
    });
}

/// Reset all statistics
pub fn resetStats(stats: *SuggestionStats) void {
    stats.* = init();
}

/// Record a usage session (for future analytics)
pub fn recordSession(stats: SuggestionStats) void {
    // This could save stats to a file/database in the future
    // For now just a placeholder
    _ = stats;
}
