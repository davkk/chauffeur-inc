const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Raylib
    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
        .raygui = true,
    });
    const raylib = raylib_dep.artifact("raylib");
    // Raylib's C code (bundled GLFW/RGFW gamepad polling) contains known
    // out-of-bounds address computations that are benign in C but trap under
    // Zig's C safety checks in Debug (see raysan5/raylib#3674). Disable C
    // sanitization for the raylib module only; our Zig code keeps full checks.
    raylib.root_module.sanitize_c = .off;

    const game_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_mod.linkLibrary(raylib);
    const game_exe = b.addExecutable(.{
        .name = "chauffeur_inc",
        .root_module = game_mod,
    });

    const export_tileset_cmd = b.addSystemCommand(&[_][]const u8{
        "libresprite",
        "-b",
        b.path("src/assets/tileset.ase").getPath(b),
        "--save-as",
        b.path("src/assets/tileset.png").getPath(b),
    });
    b.step("export:tileset", "Export tileset assets").dependOn(&export_tileset_cmd.step);

    // const export_map_cmd = b.addSystemCommand(&[_][]const u8{
    //     "tiled",
    //     "--export-map",
    //     "src/assets/map.tmx",
    //     "src/assets/map.json",
    // });
    // export_map_cmd.setEnvironmentVariable("QT_QPA_PLATFORM", "xcb");
    // game_exe.step.dependOn(&export_map_cmd.step);
    // b.step("export:map", "Export map assets").dependOn(&game_exe.step);

    b.installArtifact(game_exe);

    const run_game = b.addRunArtifact(game_exe);
    if (b.args) |args| {
        run_game.addArgs(args);
    }
    b.step("run:game", "Run the game").dependOn(&run_game.step);

    const run_sim = b.addRunArtifact(game_exe);
    run_sim.addArgs(&.{ "--sim", "60", "--bot" });
    if (b.args) |args| {
        run_sim.addArgs(args);
    }
    b.step("sim", "Run a headless bot-driven simulation").dependOn(&run_sim.step);

    const exe_check = b.addExecutable(.{
        .name = "chauffeur_inc",
        .root_module = game_mod,
    });
    const check = b.step("check", "Check if chauffeur compiles");
    check.dependOn(&exe_check.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.linkLibrary(raylib);
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run headless gameplay tests");
    test_step.dependOn(&run_unit_tests.step);
}
