const c = @cImport({
    @cInclude("raylib.h");
});
const math = @import("std").math;
const globals = @import("globals.zig");
const Building = @import("Building.zig");

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
            .x = globals.SCREEN_WIDTH / 2.0 - 16,
            .y = globals.SCREEN_HEIGHT / 2.0 - 32,
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
            self.vel = @min(self.vel + self.acc * time, globals.MAX_VEL);
        } else if (self.vel < 0) {
            self.vel = @min(self.vel + self.decel * time, 0);
        }
    } else if (c.IsKeyDown(c.KEY_S)) {
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

    if (c.IsKeyDown(c.KEY_A)) {
        self.steer_angle = @max(self.steer_angle - globals.STEER_SENSITIVITY * time, -globals.MAX_STEER_ANGLE);
    } else if (c.IsKeyDown(c.KEY_D)) {
        self.steer_angle = @min(self.steer_angle + globals.STEER_SENSITIVITY * time, globals.MAX_STEER_ANGLE);
    } else {
        if (self.steer_angle > 0) {
            self.steer_angle = @max(self.steer_angle - globals.STEER_SENSITIVITY * time, 0);
        } else if (self.steer_angle < 0) {
            self.steer_angle = @min(self.steer_angle + globals.STEER_SENSITIVITY * time, 0);
        }
    }

    if (self.vel != 0) {
        self.angle = @mod((self.angle + self.steer_angle * time * (self.vel / globals.MAX_VEL)), 2 * math.pi);
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
