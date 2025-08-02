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
    };

    while (!rl.WindowShouldClose()) {
        const time = rl.GetFrameTime();

        car.update(time);

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.BLACK);

        car.draw();
        for (&buildings) |building| {
            building.draw();
        }

        const car_vertices = collision.get_vertices(&car.rect, car.angle);
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
        rl.DrawText(rl.TextFormat("speed: %.2f", rl.Vector2Length(car.vel)), 10, 35, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("steer: %.2f", car.steer_angle * 180 / math.pi), 10, 60, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("angle: %.2f", car.angle * 180 / math.pi), 10, 85, 20, rl.WHITE);

        const car_center = rl.Vector2{
            .x = car.rect.x + car.rect.width / 2,
            .y = car.rect.y + car.rect.height / 2,
        };
        const vel_end = rl.Vector2Add(car_center, car.vel);
        rl.DrawLineEx(car_center, vel_end, 2, rl.WHITE);
    }
}
