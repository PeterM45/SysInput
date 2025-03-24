const std = @import("std");
const sysinput = @import("../sysinput.zig");
const api = sysinput.win32.api;
const debug = sysinput.core.debug;
const buffer_controller = sysinput.buffer_controller;
const insertion = sysinput.text.insertion;

/// Known window classes and their preferred insertion methods
pub const WindowClassPreference = struct {
    class_name: []const u8,
    preferred_method: u8,
};

/// Table of known window classes with their preferred insertion methods
pub const KNOWN_CLASSES = [_]WindowClassPreference{
    .{ .class_name = "Edit", .preferred_method = @intFromEnum(insertion.InsertMethod.Clipboard) },
    .{ .class_name = "RichEdit", .preferred_method = @intFromEnum(insertion.InsertMethod.DirectMessage) },
    .{ .class_name = "RichEdit20W", .preferred_method = @intFromEnum(insertion.InsertMethod.DirectMessage) },
    .{ .class_name = "RichEdit20A", .preferred_method = @intFromEnum(insertion.InsertMethod.DirectMessage) },
    .{ .class_name = "RICHEDIT50W", .preferred_method = @intFromEnum(insertion.InsertMethod.DirectMessage) },
    .{ .class_name = "RICHEDIT60W", .preferred_method = @intFromEnum(insertion.InsertMethod.DirectMessage) },
    .{ .class_name = "Notepad", .preferred_method = 3 }, // Special value for Notepad
    .{ .class_name = "TextBox", .preferred_method = @intFromEnum(insertion.InsertMethod.Clipboard) },
};

/// Get preferred insertion method for a window
pub fn getPreferredMethodForWindow(hwnd: api.HWND) u8 {
    var class_name: [128]u8 = undefined;
    const class_len = api.getClassName(hwnd, @ptrCast(&class_name), 128);
    if (class_len <= 0) return @intFromEnum(insertion.InsertMethod.Clipboard);

    const class_str = class_name[0..@intCast(class_len)];
    debug.debugPrint("Looking up preferred method for window class: '{s}'\n", .{class_str});

    // First check if we've successfully used a method with this class before
    if (buffer_controller.window_class_to_mode.get(class_str)) |method| {
        debug.debugPrint("Using learned method ({d}) for class '{s}'\n", .{ method, class_str });
        return method;
    }

    // Otherwise check against known classes
    for (KNOWN_CLASSES) |known_class| {
        if (std.mem.eql(u8, class_str, known_class.class_name)) {
            debug.debugPrint("Using predefined method ({d}) for class '{s}'\n", .{ known_class.preferred_method, class_str });
            return known_class.preferred_method;
        }
    }

    debug.debugPrint("No method found for '{s}', using default\n", .{class_str});
    return @intFromEnum(insertion.InsertMethod.Clipboard); // Default fallback
}

/// Store successful method for window class
pub fn storeSuccessfulMethod(hwnd: api.HWND, method: u8, allocator: std.mem.Allocator) void {
    var class_name: [128]u8 = undefined;
    const class_len = api.getClassName(hwnd, @ptrCast(&class_name), 128);
    if (class_len <= 0) return;

    const class_str = class_name[0..@intCast(class_len)];

    // Check if this is different from what we already know
    if (buffer_controller.window_class_to_mode.get(class_str)) |existing| {
        if (existing == method) return; // No change needed
    }

    // Store the successful method
    const owned_class = allocator.dupe(u8, class_str) catch {
        debug.debugPrint("Failed to allocate for class name\n", .{});
        return;
    };

    buffer_controller.window_class_to_mode.put(owned_class, method) catch {
        allocator.free(owned_class);
        debug.debugPrint("Failed to store class preference\n", .{});
    };

    debug.debugPrint("Learned: Method {d} works best with '{s}'\n", .{ method, class_str });
}
