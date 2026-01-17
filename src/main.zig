const std = @import("std");
const json = std.json;
const math = std.math;

const Editor = @import("Editor.zig");
const Map = @import("Map.zig");
const Car = @import("Car.zig");

const collision = @import("collision.zig");
const g = @import("globals.zig");
const rl = @import("raylib.zig").rl;

const Mode = enum { game, editor };

pub fn main() !void {
    rl.InitWindow(g.SCREEN_WIDTH, g.SCREEN_HEIGHT, "Chauffeur Inc");
    rl.SetTargetFPS(g.TARGET_FPS);
    rl.SetExitKey(0);

    var mode = Mode.editor;

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

    // FIXME: this will probably change once I have levels
    const init_node = map.nodes.items[0];
    var player = Car.init(true, init_node.pos.x, init_node.pos.y, math.pi / 2.0);
    player.curr_node = init_node.id;
    defer player.deinit();

    // var cars = std.array_list.Managed(Car).init(alloc);
    // for (0..3) |_| {
    //     var car = Car.init(false, init_node.pos.x, init_node.pos.y, math.pi / 2.0);
    //     car.curr_node = init_node.id;
    //     try cars.append(car);
    // }

    var editor = Editor.init();

    while (!rl.WindowShouldClose()) {
        const KEY_CTRL = rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL);
        const KEY_SHIFT = rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT);
        if (KEY_CTRL and KEY_SHIFT and rl.IsKeyPressed(rl.KEY_E)) {
            mode = if (mode == .game) Mode.editor else Mode.game;
        }

        rl.BeginDrawing();
        rl.ClearBackground(rl.BLACK);

        switch (mode) {
            .game => {
                const time = rl.GetFrameTime();

                player.update(time, &map);

                camera.zoom = 2;

                const view_half_x = (g.SCREEN_WIDTH / 2) / camera.zoom;
                const view_half_y = (g.SCREEN_HEIGHT / 2) / camera.zoom;
                camera.target = rl.Vector2Lerp(
                    camera.target,
                    .{
                        .x = math.clamp(player.pos.x, view_half_x, g.SCREEN_WIDTH - view_half_x),
                        .y = math.clamp(player.pos.y, view_half_y, g.SCREEN_HEIGHT - view_half_y),
                    },
                    0.2,
                );

                // for (cars.items) |*car| {
                //     car.update(time, &map);
                // }

                rl.BeginMode2D(camera);
                {
                    map.draw(.none);

                    player.draw();
                    // for (cars.items) |*car| {
                    //     car.draw();
                    // }

                    if (player.next_node) |target_index| {
                        const target = map.nodes.items[target_index];
                        rl.DrawCircleV(target.pos, 10, rl.RED);
                    }
                }
                rl.EndMode2D();

                rl.DrawText(rl.TextFormat("vel: %.2f", rl.Vector2Length(player.vel)), 10, 10, 20, rl.WHITE);
                rl.DrawText(rl.TextFormat("pos: %.f, %.f", player.pos.x, player.pos.y), 10, 35, 20, rl.WHITE);
            },
            .editor => {
                try editor.update(&camera, &map);
                rl.BeginMode2D(camera);
                {
                    try editor.drawWorld(&camera, &map, map.tileset.texture);
                }
                rl.EndMode2D();
                editor.drawGui(map.tileset.texture);
            },
        }
        rl.EndDrawing();
    }
}
