const std = @import("std");
const Build = std.Build;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "SysInput",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link with Windows user32 library (needed for keyboard hooks and window functions)
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("user32");
        exe.linkSystemLibrary("gdi32"); // Also link GDI32 for UI functions
        exe.linkLibC(); // Link C library for Windows API compatibility
    }

    // Install the executable
    b.installArtifact(exe);

    // Copy resources directory to the output directory
    const install_resources = b.addInstallDirectory(.{
        .source_dir = b.path("resources"),
        .install_dir = .{ .custom = "bin" },
        .install_subdir = "resources",
    });
    b.getInstallStep().dependOn(&install_resources.step);

    // Create run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run SysInput");
    run_step.dependOn(&run_cmd.step);

    // Create tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
