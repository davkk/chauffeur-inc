const std = @import("std");
const math = std.math;
const c = @cImport({
    @cInclude("raylib.h");
});

const SCREEN_WIDTH = 1280;
const SCREEN_HEIGHT = 720;
const TARGET_FPS = 60;

const FRICTION = 120;
const MAX_VEL = 300;

const MAX_STEER_ANGLE = 3.0 * math.pi / 4.0;
const STEER_SENSITIVITY = 8;

const Car = struct {
    rect: c.Rectangle,

    vel: f32,
    acc: f32,
    decel: f32,
    angle: f32,
    steer_angle: f32,

    const Self = @This();

    pub fn init() Self {
        return .{
            .rect = .{
                .x = SCREEN_WIDTH / 2.0 - 16,
                .y = SCREEN_HEIGHT / 2.0 - 32,
                .width = 32,
                .height = 64,
            },
            .vel = 0,
            .acc = 100,
            .decel = 200,
            .angle = 0.0,
            .steer_angle = 0.0,
        };
    }

    pub fn update(self: *Self, time: f32, buildings: []const Building) void {
        // FIXME: do proper collision detection with angles
        var is_colliding = false;
        for (buildings) |building| {
            if (c.CheckCollisionRecs(self.rect, building.rect)) {
                is_colliding = true;
                break;
            }
        }

        if (is_colliding) {
            return;
        }

        if (c.IsKeyDown(c.KEY_W)) {
            if (self.vel >= 0) {
                self.vel = @min(self.vel + self.acc * time, MAX_VEL);
            } else if (self.vel < 0) {
                self.vel = @min(self.vel + self.decel * time, 0);
            }
        } else if (c.IsKeyDown(c.KEY_S)) {
            if (self.vel <= 0) {
                self.vel = @max(self.vel - self.acc * time, -MAX_VEL);
            } else if (self.vel > 0) {
                self.vel = @max(self.vel - self.decel * time, 0);
            }
        } else {
            if (self.vel > 0) {
                self.vel = @max(self.vel - FRICTION * time, 0);
            } else if (self.vel < 0) {
                self.vel = @min(self.vel + FRICTION * time, 0);
            }
        }

        if (c.IsKeyDown(c.KEY_A)) {
            self.steer_angle = @max(self.steer_angle - STEER_SENSITIVITY * time, -MAX_STEER_ANGLE);
        } else if (c.IsKeyDown(c.KEY_D)) {
            self.steer_angle = @min(self.steer_angle + STEER_SENSITIVITY * time, MAX_STEER_ANGLE);
        } else {
            if (self.steer_angle > 0) {
                self.steer_angle = @max(self.steer_angle - STEER_SENSITIVITY * time, 0);
            } else if (self.steer_angle < 0) {
                self.steer_angle = @min(self.steer_angle + STEER_SENSITIVITY * time, 0);
            }
        }

        if (self.vel != 0) {
            self.angle = @mod((self.angle + self.steer_angle * time * (self.vel / MAX_VEL)), 2 * math.pi);
            self.rect.x += math.sin(self.angle) * self.vel * time;
            self.rect.y -= math.cos(self.angle) * self.vel * time;
        }
    }

    pub fn draw(self: *const Self) void {
        c.DrawRectanglePro(
            self.rect,
            .{ .x = self.rect.width / 2, .y = self.rect.height / 2 },
            self.angle * 180 / math.pi,
            c.YELLOW,
        );
    }
};

const Building = struct {
    rect: c.Rectangle,

    const Self = @This();

    pub fn init(x: f32, y: f32, width: f32, height: f32) Self {
        return .{
            .rect = .{
                .x = x,
                .y = y,
                .width = width,
                .height = height,
            },
        };
    }

    pub fn draw(self: *const Self) void {
        c.DrawRectangleRec(self.rect, c.GRAY);
    }
};

const GameState = enum {
    Playing,
    GameOver,
};

pub fn main() !void {
    c.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Chauffeur Inc");
    c.SetTargetFPS(TARGET_FPS);

    var game_state = GameState.Playing;

    var car = Car.init();

    const buildings = [_]Building{
        .init(0, 0, 50, SCREEN_HEIGHT),
        .init(SCREEN_WIDTH - 50, 0, 50, SCREEN_HEIGHT),
        .init(0, 0, SCREEN_WIDTH, 50),
        .init(0, SCREEN_HEIGHT - 50, SCREEN_WIDTH, 50),

        .init(200, 150, 80, 120),
        .init(SCREEN_WIDTH - 280, 150, 80, 120),
        .init(200, SCREEN_HEIGHT - 270, 80, 120),
        .init(SCREEN_WIDTH - 280, SCREEN_HEIGHT - 270, 80, 120),
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
            c.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, c.BLACK);
            c.DrawText("Game Over!", 0, 0, 64, c.RED);
        } else {
            c.DrawText(c.TextFormat("Velocity: %.1f", car.vel), 10, 10, 20, c.WHITE);
            c.DrawText(c.TextFormat("Steer Angle: %.2f", car.steer_angle), 10, 35, 20, c.WHITE);
            c.DrawText(c.TextFormat("Car Angle: %.2f", car.angle * 180.0 / math.pi), 10, 60, 20, c.WHITE);
        }
    }
}
