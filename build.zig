const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Raylib
    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.artifact("raylib");

    const game_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const game_exe = b.addExecutable(.{
        .name = "chauffeur_inc",
        .root_module = game_mod,
    });
    game_exe.linkLibrary(raylib);

    const export_tileset_cmd = b.addSystemCommand(&[_][]const u8{
        "libresprite",
        "-b",
        b.path("src/assets/tileset.ase").getPath(b),
        "--save-as",
        b.path("src/assets/tileset.png").getPath(b),
    });
    game_exe.step.dependOn(&export_tileset_cmd.step);
    b.step("export:tileset", "Export tileset assets").dependOn(&game_exe.step);

    const export_map_cmd = b.addSystemCommand(&[_][]const u8{
        "tiled",
        "--export-map",
        "src/assets/map.tmx",
        "src/assets/map.json",
    });
    export_map_cmd.setEnvironmentVariable("QT_QPA_PLATFORM", "xcb");
    game_exe.step.dependOn(&export_map_cmd.step);
    b.step("export:map", "Export map assets").dependOn(&game_exe.step);

    b.installArtifact(game_exe);

    const editor_mod = b.createModule(.{
        .root_source_file = b.path("src/editor.zig"),
        .target = target,
        .optimize = optimize,
    });
    const editor_exe = b.addExecutable(.{
        .name = "editor",
        .root_module = editor_mod,
    });
    editor_exe.linkLibrary(raylib);
    b.installArtifact(editor_exe);

    const run_game = b.addRunArtifact(game_exe);
    if (b.args) |args| {
        run_game.addArgs(args);
    }
    b.step("run:game", "Run the game").dependOn(&run_game.step);

    const run_editor = b.addRunArtifact(editor_exe);
    if (b.args) |args| {
        run_editor.addArgs(args);
    }
    b.step("run:editor", "Run the editor").dependOn(&run_editor.step);

    // const exe_unit_tests = b.addTest(.{
    //     .root_module = exe_mod,
    // });
    //
    // const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    //
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_exe_unit_tests.step);
}
