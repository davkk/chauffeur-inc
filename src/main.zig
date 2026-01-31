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

fn clampToScreen(pos: rl.Vector2, padding: f32) rl.Vector2 {
    const w: f32 = @floatFromInt(rl.GetScreenWidth());
    const h: f32 = @floatFromInt(rl.GetScreenHeight());
    return .{
        .x = math.clamp(pos.x, 2 * padding, w - 2 * padding),
        .y = math.clamp(pos.y, 2 * padding, h - 2 * padding),
    };
}

fn isOnScreen(screen_pos: rl.Vector2) bool {
    const w: f32 = @floatFromInt(rl.GetScreenWidth());
    const h: f32 = @floatFromInt(rl.GetScreenHeight());
    return screen_pos.x >= 0 and screen_pos.x <= w and
        screen_pos.y >= 0 and screen_pos.y <= h;
}

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

    // FIXME: this will probably change once I have levels
    const init_node = map.nodes.items[0];
    var player = Car.init(true, init_node.pos.x, init_node.pos.y);
    player.curr_node = init_node.id;
    defer player.deinit();

    map.spawnPassenger();

    // var cars = std.array_list.Managed(Car).init(alloc);
    // for (0..3) |_| {
    //     var car = Car.init(false, init_node.pos.x, init_node.pos.y, math.pi / 2.0);
    //     car.curr_node = init_node.id;
    //     try cars.append(car);
    // }

    var editor = Editor.init();
    var pickups: u32 = 0; // TODO: this should be in some game state

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
                const time = rl.GetFrameTime();

                player.update(time, &map);

                if (map.passenger) |*passenger| {
                    switch (passenger.state) {
                        .waiting => {
                            if (rl.Vector2Distance(player.pos, passenger.start_pos) < 20) {
                                passenger.state = .in_car;
                            }
                        },
                        .in_car => {
                            if (rl.Vector2Distance(player.pos, passenger.end_pos) < 20) {
                                passenger.state = .delivered;
                            }
                        },
                        .delivered => {
                            map.spawnPassenger();
                            pickups += 1;
                        },
                    }
                }

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
                    map.draw(.none, is_debug);

                    player.draw();
                    // for (cars.items) |*car| {
                    //     car.draw();
                    // }

                    if (is_debug) {
                        if (player.next_node) |target_index| {
                            const target = map.nodes.items[target_index];
                            rl.DrawCircleV(target.pos, 10, rl.RED);
                        }
                    }
                }
                rl.EndMode2D();

                if (map.passenger) |passenger| {
                    const pos = rl.GetWorldToScreen2D(
                        switch (passenger.state) {
                            .waiting => passenger.start_pos,
                            .in_car, .delivered => passenger.end_pos,
                        },
                        camera,
                    );
                    if (!isOnScreen(pos)) {
                        const size = 32.0;
                        const clamped = clampToScreen(pos, size / 2);
                        rl.DrawRectanglePro(
                            .{ .width = size, .height = size, .x = clamped.x, .y = clamped.y },
                            .{ .x = 16, .y = 16 },
                            0,
                            rl.RED,
                        );
                    }
                }

                rl.DrawText(rl.TextFormat("vel: %.2f", rl.Vector2Length(player.vel)), 10, 10, 20, rl.WHITE);
                rl.DrawText(rl.TextFormat("pos: %.f, %.f", player.pos.x, player.pos.y), 10, 35, 20, rl.WHITE);

                const mouse_pos = rl.GetMousePosition();
                rl.DrawText(rl.TextFormat("mouse: %.f, %.f", mouse_pos.x, mouse_pos.y), 10, 60, 20, rl.WHITE);

                // TODO: add this to game UI overlay later
                rl.DrawText(rl.TextFormat("pickups: %d", pickups), 10, 85, 20, rl.WHITE);
            },
            .editor => {
                try editor.update(&camera, &map);
                rl.BeginMode2D(camera);
                {
                    try editor.drawWorld(&camera, &map, map.tileset.texture, is_debug);
                }
                rl.EndMode2D();
                editor.drawGui(map.tileset.texture);
            },
        }
        rl.EndDrawing();
    }
}
