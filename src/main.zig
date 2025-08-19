const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");
const collision = @import("collision.zig");

const Car = @import("Car.zig");
const Building = @import("Building.zig");

pub fn main() !void {
    rl.InitWindow(g.SCREEN_WIDTH, g.SCREEN_HEIGHT, "Chauffeur Inc");

    var car = Car.init();
    defer car.deinit();

    var camera = rl.Camera2D{
        .target = rl.Vector2{ .x = car.pos.x, .y = car.pos.y },
        .offset = rl.Vector2{ .x = g.SCREEN_WIDTH / 2.0, .y = g.SCREEN_HEIGHT / 2.0 },
        .rotation = car.angle,
        .zoom = 2,
    };

    rl.SetTargetFPS(g.TARGET_FPS);

    // const buildings = [_]Building{
    //     Building.init(0, 0, g.SCREEN_WIDTH / 3, 8 * g.SCREEN_HEIGHT),
    //     Building.init(2 * g.SCREEN_WIDTH / 3, 0, g.SCREEN_WIDTH / 3, 8 * g.SCREEN_HEIGHT),
    // };

    const buildings = [_]Building{
        Building.init(0, 0, g.SCREEN_WIDTH, g.SCREEN_HEIGHT / 3),
        Building.init(0, 2 * g.SCREEN_WIDTH / 3, g.SCREEN_WIDTH, g.SCREEN_HEIGHT / 3),
    };

    // var buildings: [20 * 20]Building = undefined;
    // for (0..20) |row| {
    //     for (0..20) |col| {
    //         const x = col * g.SCREEN_WIDTH / 2 + g.SCREEN_WIDTH / 4;
    //         const y = row * g.SCREEN_HEIGHT / 2 + g.SCREEN_HEIGHT / 4;
    //         const width = g.SCREEN_WIDTH / 4;
    //         const height = g.SCREEN_HEIGHT / 4;
    //         const building = Building.init(@floatFromInt(x), @floatFromInt(y), width, height);
    //         buildings[row * 20 + col] = building;
    //     }
    // }

    while (!rl.WindowShouldClose()) {
        const time = rl.GetFrameTime();
        car.update(time);

        camera.target = rl.Vector2{ .x = car.pos.x, .y = car.pos.y };

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.GRAY);

        rl.BeginMode2D(camera);

        car.draw();

        for (&buildings) |building| {
            building.draw();
        }

        // const car_vertices = collision.get_vertices(&car.rect(), car.angle);
        // for (car_vertices, 0..) |vertex, i| {
        //     const color = switch (i) {
        //         0 => rl.RED,
        //         1 => rl.GREEN,
        //         2 => rl.BLUE,
        //         3 => rl.YELLOW,
        //         else => rl.WHITE,
        //     };
        //     rl.DrawCircleV(vertex, 6, color);
        // }

        // for (buildings) |building| {
        //     const building_verices = collision.get_vertices(&building.rect, 0);
        //     for (building_verices, 0..) |vertex, i| {
        //         const color = switch (i) {
        //             0 => rl.RED,
        //             1 => rl.GREEN,
        //             2 => rl.BLUE,
        //             3 => rl.YELLOW,
        //             else => rl.WHITE,
        //         };
        //         rl.DrawCircleV(vertex, 6, color);
        //     }
        // }

        // const vel_end = rl.Vector2Add(car.pos, rl.Vector2Scale(car.vel, 0.5));
        // rl.DrawLineEx(car.pos, vel_end, 2, rl.WHITE);

        rl.EndMode2D();

        rl.DrawText(rl.TextFormat("throttle: %.1f", car.throttle), 10, 10, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("brake: %.1f", car.brake), 10, 35, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("steer: %.2f", car.steer), 10, 60, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("angular_vel: %.2f", car.angular_vel), 10, 110, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("vel: %.2f", rl.Vector2Length(car.vel)), 10, 135, 20, rl.WHITE);

        for (&buildings) |building| {
            const result = collision.collide(
                &car.rect(),
                car.angle,
                &building.rect,
                0,
            );

            if (result) |res| {
                const push = rl.Vector2Scale(res.normal, -res.depth);
                car.pos = rl.Vector2Add(car.pos, push);

                const tangent = rl.Vector2{ .x = res.normal.y, .y = -res.normal.x };

                const num = -1.5 * rl.Vector2DotProduct(rl.Vector2Subtract(car.vel, rl.Vector2Zero()), res.normal);
                const den_lin = 1 / car.mass;
                const den_ang = rl.Vector2DotProduct(res.normal, rl.Vector2Scale(tangent, 1 / car.inertia));
                const impulse = num / (den_lin + den_ang);

                car.vel = rl.Vector2Add(car.vel, rl.Vector2Scale(res.normal, impulse / car.mass));
            }
        }
    }
}
