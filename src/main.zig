const std = @import("std");
const json = std.json;
const math = std.math;

const collision = @import("collision.zig");
const g = @import("globals.zig");
const rl = @import("raylib.zig").rl;

const Map = @import("Map.zig");
const Car = @import("Car.zig");
const Tileset = @import("Tileset.zig");

pub fn main() !void {
    rl.InitWindow(g.SCREEN_WIDTH, g.SCREEN_HEIGHT, "Chauffeur Inc");
    rl.SetTargetFPS(g.TARGET_FPS);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const map = try Map.init(alloc);
    defer map.deinit();

    const tileset = Tileset.init();
    defer tileset.deinit();

    var car = Car.init();
    defer car.deinit();

    var camera = rl.Camera2D{
        .target = rl.Vector2{ .x = car.pos.x, .y = car.pos.y },
        .offset = rl.Vector2{ .x = g.SCREEN_WIDTH / 2.0, .y = g.SCREEN_HEIGHT / 2.0 },
        .rotation = car.angle,
        .zoom = 2,
    };

    while (!rl.WindowShouldClose()) {
        const time = rl.GetFrameTime();
        car.update(time);

        camera.target = rl.Vector2{ .x = car.pos.x, .y = car.pos.y };

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.GRAY);

        rl.BeginMode2D(camera);
        {
            map.draw_background(tileset);
            car.draw();
            map.draw_foreground(tileset);
        }
        rl.EndMode2D();

        rl.DrawText(rl.TextFormat("throttle: %.1f", car.throttle), 10, 10, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("brake: %.1f", car.brake), 10, 35, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("steer: %.2f", car.steer), 10, 60, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("angular_vel: %.2f", car.angular_vel), 10, 110, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("vel: %.2f", rl.Vector2Length(car.vel)), 10, 135, 20, rl.WHITE);

        for (map.collidables.items) |collidable| {
            const result = collision.collide(
                &car.rect(),
                car.angle,
                &collidable.rect(),
                0,
            );

            if (result) |res| {
                const push = rl.Vector2Scale(res.normal, -res.depth);
                car.pos = rl.Vector2Add(car.pos, push);

                const tangent = rl.Vector2{ .x = res.normal.y, .y = -res.normal.x };

                const num = -g.ELASTICITY * rl.Vector2DotProduct(rl.Vector2Subtract(car.vel, rl.Vector2Zero()), res.normal);
                const den_lin = 1 / car.mass;
                const den_ang = rl.Vector2DotProduct(res.normal, rl.Vector2Scale(tangent, 1 / car.inertia));
                const impulse = num / (den_lin + den_ang);

                car.vel = rl.Vector2Add(car.vel, rl.Vector2Scale(res.normal, impulse / car.mass));
                car.angular_vel += tangent.x * impulse / car.inertia;
            }
        }
    }
}
