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
        .target = rl.Vector2{ .x = 0, .y = 0 },
        .zoom = 1,
    };

    var map = try Map.init(alloc);
    defer map.deinit();

    // FIXME: this will probably change once I have levels
    const init_node = map.nodes.items[0];
    var player = Car.init(true, init_node.pos.x, init_node.pos.y, math.pi / 2.0);
    player.curr_node = init_node.id;
    defer player.deinit();

    var cars = std.array_list.Managed(Car).init(alloc);
    for (0..3) |_| {
        var car = Car.init(false, init_node.pos.x, init_node.pos.y, math.pi / 2.0);
        car.curr_node = init_node.id;
        try cars.append(car);
    }

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
                for (cars.items) |*car| {
                    car.update(time, &map);
                }

                rl.BeginMode2D(camera);
                {
                    map.draw();

                    player.draw();
                    for (cars.items) |*car| {
                        car.draw();
                    }

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
                rl.BeginMode2D(camera);
                {
                    try editor.draw(alloc, &camera, &map);
                }
                rl.EndMode2D();
            },
        }
        rl.EndDrawing();

        // for (map.collidables.items) |collidable| {
        //     const result = collision.collide(
        //         &car.rect(),
        //         car.angle,
        //         &collidable.rect(),
        //         0,
        //     );
        //
        //     if (result) |res| {
        //         const push = rl.Vector2Scale(res.normal, -res.depth);
        //         car.pos = rl.Vector2Add(car.pos, push);
        //
        //         const tangent = rl.Vector2{ .x = res.normal.y, .y = -res.normal.x };
        //
        //         const num = -g.ELASTICITY * rl.Vector2DotProduct(rl.Vector2Subtract(car.vel, rl.Vector2Zero()), res.normal);
        //         const den_lin = 1 / car.mass;
        //         const den_ang = rl.Vector2DotProduct(res.normal, rl.Vector2Scale(tangent, 1 / car.inertia));
        //         const impulse = num / (den_lin + den_ang);
        //
        //         car.vel = rl.Vector2Add(car.vel, rl.Vector2Scale(res.normal, impulse / car.mass));
        //         car.angular_vel += tangent.x * impulse / car.inertia;
        //     }
        // }
    }
}
