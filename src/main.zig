const std = @import("std");
const c = @cImport({
    @cInclude("raylib.h");
});

pub fn main() !void {
    const screen_width = 1280.0;
    const screen_height = 720.0;
    const target_fps = 60;

    c.InitWindow(screen_width, screen_height, "Chauffeur Inc");
    c.SetTargetFPS(target_fps);
    defer c.CloseWindow();

    const car_width = 75.0;
    const car_height = 100.0;

    var car_x = @as(c_int, @intFromFloat(screen_width / 2.0 - car_width / 2.0));
    var car_y = @as(c_int, @intFromFloat(screen_height / 2.0 - car_height / 2.0));

    const car_speed = 10;

    while (!c.WindowShouldClose()) {
        inline for (.{ c.KEY_W, c.KEY_S, c.KEY_A, c.KEY_D }) |key| {
            switch (c.IsKeyDown(key)) {
                true => switch (key) {
                    c.KEY_W => car_y -= car_speed,
                    c.KEY_S => car_y += car_speed,
                    c.KEY_A => car_x -= car_speed,
                    c.KEY_D => car_x += car_speed,
                    else => {},
                },
                false => {},
            }
        }

        c.BeginDrawing();
        defer c.EndDrawing();

        c.ClearBackground(c.BLACK);
        c.DrawRectangle(
            car_x,
            car_y,
            car_width,
            car_height,
            c.RED,
        );
    }
}
