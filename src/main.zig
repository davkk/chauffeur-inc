const std = @import("std");
const math = std.math;
const c = @cImport({
    @cInclude("raylib.h");
});

const globals = @import("globals.zig");

const Car = @import("Car.zig");
const Building = @import("Building.zig");

const GameState = enum {
    Playing,
    GameOver,
};

pub fn main() !void {
    c.InitWindow(globals.SCREEN_WIDTH, globals.SCREEN_HEIGHT, "Chauffeur Inc");
    c.SetTargetFPS(globals.TARGET_FPS);

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

    while (!c.WindowShouldClose()) {
        const time = c.GetFrameTime();

        if (game_state == GameState.Playing) {
            car.update(time, &buildings);
            for (&buildings) |building| {
                if (c.CheckCollisionRecs(car.rect, building.rect)) {
                    game_state = GameState.GameOver;
                    break;
                }
            }
        } else if (game_state == GameState.GameOver) {
            if (c.IsKeyPressed(c.KEY_R)) {
                car = Car.init();
                game_state = GameState.Playing;
            }
        }

        c.BeginDrawing();
        defer c.EndDrawing();

        c.ClearBackground(c.BLACK);

        car.draw();

        for (&buildings) |building| {
            building.draw();
        }

        if (game_state == GameState.GameOver) {
            c.DrawRectangle(0, 0, globals.SCREEN_WIDTH, globals.SCREEN_HEIGHT, c.BLACK);
            c.DrawText("Game Over!", 0, 0, 64, c.RED);
        } else {
            c.DrawText(c.TextFormat("Velocity: %.1f", car.vel), 10, 10, 20, c.WHITE);
            c.DrawText(c.TextFormat("Steer Angle: %.2f", car.steer_angle), 10, 35, 20, c.WHITE);
            c.DrawText(c.TextFormat("Car Angle: %.2f", car.angle * 180.0 / math.pi), 10, 60, 20, c.WHITE);
        }
    }
}
