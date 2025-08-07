const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const globals = @import("globals.zig");
const collision = @import("collision.zig");

const Car = @import("Car.zig");
const Building = @import("Building.zig");

pub fn main() !void {
    rl.InitWindow(globals.SCREEN_WIDTH, globals.SCREEN_HEIGHT, "Chauffeur Inc");
    rl.SetTargetFPS(globals.TARGET_FPS);

    var car = Car.init();

    const buildings = [_]Building{
        .init(0, 0, 50, globals.SCREEN_HEIGHT),
        .init(globals.SCREEN_WIDTH - 50, 0, 50, globals.SCREEN_HEIGHT),
        .init(0, 0, globals.SCREEN_WIDTH, 50),
        .init(0, globals.SCREEN_HEIGHT - 50, globals.SCREEN_WIDTH, 50),

        .init(globals.SCREEN_WIDTH / 2 - 50, globals.SCREEN_HEIGHT / 2 - 50, 100, 100),
    };

    while (!rl.WindowShouldClose()) {
        const time = rl.GetFrameTime();
        car.update(time);

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.GRAY);

        car.draw();

        for (&buildings) |building| {
            building.draw();

            const result = collision.collide(
                &car.rect(),
                car.angle,
                &building.rect,
                0,
            );

            if (result) |res| {
                const push = rl.Vector2Scale(res.normal, -res.depth);
                car.pos = rl.Vector2Add(car.pos, push);
            }
        }

        const car_vertices = collision.get_vertices(&car.rect(), car.angle);
        for (car_vertices, 0..) |vertex, i| {
            const color = switch (i) {
                0 => rl.RED,
                1 => rl.GREEN,
                2 => rl.BLUE,
                3 => rl.YELLOW,
                else => rl.WHITE,
            };
            rl.DrawCircleV(vertex, 6, color);
        }

        for (buildings) |building| {
            const building_verices = collision.get_vertices(&building.rect, 0);
            for (building_verices, 0..) |vertex, i| {
                const color = switch (i) {
                    0 => rl.RED,
                    1 => rl.GREEN,
                    2 => rl.BLUE,
                    3 => rl.YELLOW,
                    else => rl.WHITE,
                };
                rl.DrawCircleV(vertex, 6, color);
            }
        }

        rl.DrawText(rl.TextFormat("throttle: %.1f", car.throttle), 10, 10, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("brake: %.1f", car.brake), 10, 35, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("steer: %.2f", car.steer), 10, 60, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("angular_vel: %.2f", car.angular_vel), 10, 110, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("vel: %.2f", rl.Vector2Length(car.vel)), 10, 135, 20, rl.WHITE);

        const car_center = car.pos;
        const vel_end = rl.Vector2Add(car_center, car.vel);
        rl.DrawLineEx(car_center, vel_end, 2, rl.WHITE);
    }
}
