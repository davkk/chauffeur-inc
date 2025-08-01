const rl = @import("raylib.zig").rl;
const math = @import("std").math;
const globals = @import("globals.zig");
const Building = @import("Building.zig");

rect: rl.Rectangle,

vel: f32,
acc: f32,
decel: f32,
angle: f32,
steer_angle: f32,

const Self = @This();

pub fn init() Self {
    return .{
        .rect = .{
            .x = globals.SCREEN_WIDTH / 2.0 - 16,
            .y = globals.SCREEN_HEIGHT / 2.0 - 32,
            .width = 32,
            .height = 64,
        },
        .vel = 0,
        .acc = 200,
        .decel = 400,
        .angle = 0.0,
        .steer_angle = 0.0,
    };
}

pub fn update(self: *Self, time: f32) void {
    if (rl.IsKeyDown(rl.KEY_W)) {
        if (self.vel >= 0) {
            self.vel = @min(self.vel + self.acc * time, globals.MAX_VEL);
        } else if (self.vel < 0) {
            self.vel = @min(self.vel + self.decel * time, 0);
        }
    } else if (rl.IsKeyDown(rl.KEY_S)) {
        if (self.vel <= 0) {
            self.vel = @max(self.vel - self.acc * time, -globals.MAX_VEL);
        } else if (self.vel > 0) {
            self.vel = @max(self.vel - self.decel * time, 0);
        }
    } else {
        if (self.vel > 0) {
            self.vel = @max(self.vel - globals.FRICTION * time, 0);
        } else if (self.vel < 0) {
            self.vel = @min(self.vel + globals.FRICTION * time, 0);
        }
    }

    if (rl.IsKeyDown(rl.KEY_A)) {
        self.steer_angle = @max(self.steer_angle - globals.STEER_SENSITIVITY * time, -globals.MAX_STEER_ANGLE);
    } else if (rl.IsKeyDown(rl.KEY_D)) {
        self.steer_angle = @min(self.steer_angle + globals.STEER_SENSITIVITY * time, globals.MAX_STEER_ANGLE);
    } else {
        if (self.steer_angle > 0) {
            self.steer_angle = @max(self.steer_angle - globals.STEER_SENSITIVITY * time, 0);
        } else if (self.steer_angle < 0) {
            self.steer_angle = @min(self.steer_angle + globals.STEER_SENSITIVITY * time, 0);
        }
    }

    self.angle = @mod((self.angle + self.steer_angle * time * (self.vel / globals.MAX_VEL)), 2 * math.pi);
    self.rect.x += math.sin(self.angle) * self.vel * time;
    self.rect.y -= math.cos(self.angle) * self.vel * time;
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
