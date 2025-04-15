const builtin = @import("builtin");
const std = @import("std");
const Build = std.Build;
const Step = std.Build.Step;

const examples = [_][]const u8{
    "example-dxwindow",
    "example-window-zwin",
    "example-window",
    "helloworld",
    "mem-mapped-ntd",
    "mem-mapped",
    "view-within-a-file",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Root module to use
    const zwin_mod = b.addModule("zwin", .{
        .root_source_file = b.path("src/zwin.zig"),
        .optimize = optimize,
        .target = target,
    });

    const zigwin32_dep = b.dependency("zigwin32", .{});
    const zigwin32_mod = zigwin32_dep.module("win32");

    zwin_mod.addImport("win32", zigwin32_mod);

    const examples_step = b.step("examples", "Build examples");
    inline for (examples) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path("examples/" ++ example_name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });

        // Add imports and/or link libraries if necessary
        example.root_module.addImport("win32", zigwin32_mod);
        example.root_module.addImport("zwin", zwin_mod);

        const compile_step = b.step(example_name, "Build " ++ example_name);
        compile_step.dependOn(&b.addInstallArtifact(example, .{}).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = b.addRunArtifact(example);
        run_cmd.step.dependOn(compile_step);

        // This allows the user to pass arguments to the application in the build
        // command itself, like this: `zig build run -- arg1 arg2 etc`
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run-" ++ example_name, "Run " ++ example_name);
        run_step.dependOn(&run_cmd.step);
    }

    const test_step = b.step("test", "Run tests");
    const tests = b.addTest(.{
        .root_source_file = b.path("src/zwin.zig"),
        .optimize = optimize,
        .target = target,
    });
    tests.root_module.addImport("win32", zigwin32_mod);
    tests.root_module.addImport("zwin", zwin_mod);
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(test_step);
    all_step.dependOn(examples_step);

    b.default_step.dependOn(all_step);
}
