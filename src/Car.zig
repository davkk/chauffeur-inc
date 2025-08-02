const std = @import("std");
const rl = @import("raylib.zig").rl;
const vec_add = @import("raylib.zig").vec_add;
const math = @import("std").math;
const g = @import("globals.zig");
const Building = @import("Building.zig");

const Self = @This();

throttle: f32,
breaking: bool,

rect: rl.Rectangle,
vel: rl.Vector2,
angular_vel: f32,

mass: f32,
inertia: f32,

accel: f32,
decel: f32,
angle: f32,
steer_angle: f32,

pub fn init() Self {
    const width = 32;
    const height = 64;
    const mass = 1;
    const accel = 200;
    return .{
        .mass = mass,
        .inertia = mass * (width * width + height * height) / 12,
        .accel = accel,
        .decel = 2 * accel,

        .throttle = 0,
        .breaking = false,

        .rect = .{
            .x = g.SCREEN_WIDTH / 2.0 - width / 2,
            .y = g.SCREEN_HEIGHT - 3 * height,
            .width = width,
            .height = height,
        },
        .vel = .{ .x = 0, .y = 0 },
        .angular_vel = 0,
        .angle = 0.0,
        .steer_angle = 0.0,
    };
}

pub fn update(self: *Self, time: f32) void {
    const forward = rl.Vector2{
        .x = math.sin(self.angle),
        .y = -math.cos(self.angle),
    };
    const vel_y = rl.Vector2DotProduct(forward, self.vel);

    if (rl.IsKeyDown(rl.KEY_A)) {
        self.steer_angle = @max(self.steer_angle - g.STEER_SPEED * time, -g.MAX_STEER_ANGLE);
    } else if (rl.IsKeyDown(rl.KEY_D)) {
        self.steer_angle = @min(self.steer_angle + g.STEER_SPEED * time, g.MAX_STEER_ANGLE);
    } else {
        if (self.steer_angle > 0) {
            self.steer_angle = @max(self.steer_angle - g.STEER_SPEED * time, 0);
        } else if (self.steer_angle < 0) {
            self.steer_angle = @min(self.steer_angle + g.STEER_SPEED * time, 0);
        }
    }

    const R = self.rect.height / @sin(self.steer_angle);
    const omega = rl.Vector2Length(self.vel) / R;

    if (rl.IsKeyDown(rl.KEY_W)) {
        if (vel_y >= 0) {
            self.throttle = @min(self.throttle + g.THROTTLE_SPEED * time, g.THROTTLE_SPEED);
            self.breaking = false;
        } else {
            self.throttle = 0;
            self.breaking = true;
        }
        self.angle = @mod((self.angle + time * omega), math.pi * 2);
    } else if (rl.IsKeyDown(rl.KEY_S)) {
        if (vel_y <= 0) {
            self.throttle = @max(self.throttle - g.THROTTLE_SPEED * time, -g.THROTTLE_SPEED);
            self.breaking = false;
        } else {
            self.throttle = 0;
            self.breaking = true;
        }
        self.angle = @mod((self.angle - time * omega), math.pi * 2);
    } else {
        if (self.throttle >= 0) {
            self.throttle = @max(self.throttle - 2 * g.THROTTLE_SPEED * time, 0);
        } else {
            self.throttle = @min(self.throttle + 2 * g.THROTTLE_SPEED * time, 0);
        }

        self.breaking = false;
    }

    const F_trac = rl.Vector2Scale(forward, self.throttle);
    const F_drag = rl.Vector2Scale(self.vel, -g.DRAG_FACTOR * rl.Vector2Length(self.vel));
    const F_roll = rl.Vector2Scale(self.vel, -g.ROLLING_RESISTANCE);

    var F_brek = rl.Vector2Zero();
    if (self.breaking) {
        F_brek = rl.Vector2Scale(forward, -g.BREAK_FACTOR);
    }

    const F = vec_add(&.{ F_trac, F_drag, F_roll, F_brek });

    const accel = rl.Vector2Scale(F, 1 / self.mass);
    self.vel = rl.Vector2Add(self.vel, rl.Vector2Scale(accel, time));

    if (self.breaking and rl.Vector2Length(self.vel) < g.VELOCITY_THRESHOLD) {
        self.vel = rl.Vector2Zero();
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
