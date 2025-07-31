const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const globals = @import("globals.zig");
const collision = @import("collision.zig");

const Car = @import("Car.zig");
const Building = @import("Building.zig");

const GameState = enum {
    Playing,
    GameOver,
};

pub fn main() !void {
    rl.InitWindow(globals.SCREEN_WIDTH, globals.SCREEN_HEIGHT, "Chauffeur Inc");
    rl.SetTargetFPS(globals.TARGET_FPS);

    var game_state = GameState.Playing;

    var car = Car.init();

    const buildings = [_]Building{
        .init(0, 0, 50, globals.SCREEN_HEIGHT),
        .init(globals.SCREEN_WIDTH - 50, 0, 50, globals.SCREEN_HEIGHT),
        .init(0, 0, globals.SCREEN_WIDTH, 50),
        .init(0, globals.SCREEN_HEIGHT - 50, globals.SCREEN_WIDTH, 50),

        .init(200, 150, 80, 120),
        .init(globals.SCREEN_WIDTH - 280, 150, 80, 120),
        .init(200, globals.SCREEN_HEIGHT - 270, 80, 120),
        .init(globals.SCREEN_WIDTH - 280, globals.SCREEN_HEIGHT - 270, 80, 120),
    };

    while (!rl.WindowShouldClose()) {
        const time = rl.GetFrameTime();

        if (game_state == GameState.Playing) {
            car.update(time);

            for (&buildings) |building| {
                if (collision.collide(&car.rect, car.angle, &building.rect, 0)) {
                    game_state = .GameOver;
                    break;
                }
            }
        } else if (game_state == GameState.GameOver) {
            if (rl.IsKeyPressed(rl.KEY_R)) {
                car = Car.init();
                game_state = GameState.Playing;
            }
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.BLACK);

        car.draw();
        // In your main drawing loop, after car.draw()

        const car_vertices = collision.get_vertices(&car.rect, car.angle);
        for (car_vertices, 0..) |vertex, i| {
            const color = switch (i) {
                0 => rl.RED,
                1 => rl.GREEN,
                2 => rl.BLUE,
                3 => rl.YELLOW,
                else => rl.WHITE,
            };
            rl.DrawCircleV(vertex, 5, color);
        }

        for (buildings) |building| {
            rl.DrawRectangleLinesEx(building.rect, 2, rl.BLUE);
        }

        for (&buildings) |building| {
            building.draw();
        }

        if (game_state == GameState.GameOver) {
            rl.DrawRectangle(0, 0, globals.SCREEN_WIDTH, globals.SCREEN_HEIGHT, rl.BLACK);
            rl.DrawText("Game Over!", 0, 0, 64, rl.RED);
        } else {
            rl.DrawText(rl.TextFormat("Velocity: %.1f", car.vel), 10, 10, 20, rl.WHITE);
            rl.DrawText(rl.TextFormat("Steer Angle: %.2f", car.steer_angle * 180.0 / math.pi), 10, 35, 20, rl.WHITE);
            rl.DrawText(rl.TextFormat("Car Angle: %.2f", car.angle * 180.0 / math.pi), 10, 60, 20, rl.WHITE);
        }
    }
}
