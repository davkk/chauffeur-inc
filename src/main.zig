const std = @import("std");

const Game = @import("Game.zig");
const Editor = @import("Editor.zig");
const Map = @import("Map.zig");
const g = @import("globals.zig");
const rl = @import("raylib.zig").rl;

const Mode = enum { game, editor };

pub fn main() !void {
    rl.InitWindow(g.SCREEN_WIDTH, g.SCREEN_HEIGHT, "Chauffeur Inc");
    rl.SetTargetFPS(g.TARGET_FPS);
    rl.SetExitKey(0);

    var mode = Mode.editor;
    var is_debug = false;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var camera = rl.Camera2D{
        .target = .{ .x = g.SCREEN_WIDTH / 4 - g.TILE_SIZE / 2, .y = g.SCREEN_HEIGHT / 4 - g.TILE_SIZE / 2 },
        .offset = .{ .x = g.SCREEN_WIDTH / 2 + g.TILE_SIZE, .y = g.SCREEN_HEIGHT / 2 + g.TILE_SIZE },
        .zoom = 2,
    };

    var map = try Map.init(alloc);
    defer map.deinit();

    var game = Game.init(&map);
    defer game.deinit();

    var editor = Editor.init();

    while (!rl.WindowShouldClose()) {
        const KEY_CTRL = rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL);
        const KEY_SHIFT = rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT);
        if (KEY_CTRL and KEY_SHIFT and rl.IsKeyPressed(rl.KEY_E)) {
            mode = if (mode == .game) Mode.editor else Mode.game;
        }
        if (KEY_CTRL and KEY_SHIFT and rl.IsKeyPressed(rl.KEY_D)) {
            is_debug = !is_debug;
        }
        if (KEY_CTRL and KEY_SHIFT and rl.IsKeyPressed(rl.KEY_P)) {
            map.spawnPassenger();
        }

        rl.BeginDrawing();
        rl.ClearBackground(rl.BLACK);

        switch (mode) {
            .game => {
                game.update(&camera, &map);
                game.draw(&camera, &map, is_debug);
            },
            .editor => {
                try editor.update(&camera, &map);
                try editor.draw(&camera, &map, is_debug);
            },
        }
        rl.EndDrawing();
    }
}
