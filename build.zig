const std = @import("std");

fn linkWin(mod: *std.Build.Module) void {
    mod.linkSystemLibrary("kernel32", .{});
    mod.linkSystemLibrary("user32", .{});
    mod.linkSystemLibrary("shell32", .{});
    mod.linkSystemLibrary("ole32", .{});
    mod.linkSystemLibrary("advapi32", .{});
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ---- Windows GUI ---------------------------------------------------
    const gui_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    linkWin(gui_mod);
    gui_mod.linkSystemLibrary("gdi32", .{});
    gui_mod.linkSystemLibrary("winmm", .{});
    gui_mod.linkSystemLibrary("winhttp", .{});

    const gui = b.addExecutable(.{ .name = "zigtodo", .root_module = gui_mod });
    gui.subsystem = .windows;
    b.installArtifact(gui);

    const run = b.addRunArtifact(gui);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the zigtodo GUI").dependOn(&run.step);

    // ---- CLI (todo.cli) ------------------------------------------------
    const cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    linkWin(cli_mod);

    const cli = b.addExecutable(.{ .name = "todo.cli", .root_module = cli_mod });
    b.installArtifact(cli);

    const gui_tests = b.addTest(.{ .root_module = gui_mod });
    const cli_tests = b.addTest(.{ .root_module = cli_mod });
    const run_gui_tests = b.addRunArtifact(gui_tests);
    const run_cli_tests = b.addRunArtifact(cli_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_gui_tests.step);
    test_step.dependOn(&run_cli_tests.step);
}
