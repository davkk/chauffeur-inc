const rl = @import("raylib.zig").rl;
const math = @import("std").math;
const g = @import("globals.zig");
const Building = @import("Building.zig");

rect: rl.Rectangle,
vel: rl.Vector2,

accel: f32,
decel: f32,
angle: f32,
steer_angle: f32,

const Self = @This();

pub fn init() Self {
    return .{
        .rect = .{
            .x = g.SCREEN_WIDTH / 2.0 - 16,
            .y = g.SCREEN_HEIGHT / 2.0 - 32,
            .width = 32,
            .height = 64,
        },
        .vel = .{
            .x = 0,
            .y = 0,
        },
        .accel = 200,
        .decel = 400,
        .angle = 0.0,
        .steer_angle = 0.0,
    };
}

pub fn update(self: *Self, time: f32) void {
    const forward = rl.Vector2{
        .x = @sin(self.angle),
        .y = -@cos(self.angle), // -y is up
    };
    const right = rl.Vector2{
        .x = forward.y,
        .y = -forward.x,
    };

    const vel_x = rl.Vector2DotProduct(self.vel, right);
    const vel_y = rl.Vector2DotProduct(self.vel, forward);

    const speed_x = vel_x * 0.4 * time;

    var speed_y = vel_y;
    if (rl.IsKeyDown(rl.KEY_W)) {
        speed_y += self.accel * time;
    } else if (rl.IsKeyDown(rl.KEY_S)) {
        speed_y -= self.accel * time;
    } else {
        if (speed_y > 0) {
            speed_y = @max(speed_y - g.FRICTION * time, 0);
        } else if (speed_y < 0) {
            speed_y = @min(speed_y + g.FRICTION * time, 0);
        }
    }
    speed_y = @min(@max(speed_y, -g.MAX_SPEED), g.MAX_SPEED);

    self.vel = rl.Vector2Add(
        rl.Vector2Scale(forward, speed_y),
        rl.Vector2Scale(right, speed_x),
    );

    if (rl.IsKeyDown(rl.KEY_A)) {
        self.steer_angle = @max(self.steer_angle - g.STEER_SENSITIVITY * time, -g.MAX_STEER_ANGLE);
    } else if (rl.IsKeyDown(rl.KEY_D)) {
        self.steer_angle = @min(self.steer_angle + g.STEER_SENSITIVITY * time, g.MAX_STEER_ANGLE);
    } else {
        if (self.steer_angle > 0) {
            self.steer_angle = @max(self.steer_angle - g.STEER_SENSITIVITY * time, 0);
        } else if (self.steer_angle < 0) {
            self.steer_angle = @min(self.steer_angle + g.STEER_SENSITIVITY * time, 0);
        }
    }

    const speed = rl.Vector2Length(self.vel);
    if (speed > 0) {
        const dir: f32 = if (vel_y >= 0) 1.0 else -1.0;
        self.angle = @mod((self.angle + dir * self.steer_angle * time * (speed / g.MAX_SPEED)), 2 * math.pi);
    }

    self.rect.x += self.vel.x * time;
    self.rect.y += self.vel.y * time;
}

pub fn draw(self: *const Self) void {
    rl.DrawRectanglePro(
        .{
            .x = self.rect.x + self.rect.width / 2,
            .y = self.rect.y + self.rect.height / 2,
            .width = self.rect.width,
            .height = self.rect.height,
        },
        .{ .x = self.rect.width / 2, .y = self.rect.height / 2 },
        self.angle * 180 / math.pi,
        rl.YELLOW,
    );
}
