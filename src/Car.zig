const std = @import("std");

const rl = @import("raylib.zig").rl;
const vec_rotate = @import("raylib.zig").vec_rotate;
const vec_add = @import("raylib.zig").vec_add;

const math = @import("std").math;
const g = @import("globals.zig");

const Tire = struct {
    size: rl.Vector2,
};

const Tires = struct {
    front: Tire,
    rear: Tire,
};

const Self = @This();

pos: rl.Vector2,
size: rl.Vector2,

throttle: f32,
brake: f32,
steer: f32,

vel: rl.Vector2,
angular_vel: f32,

mass: f32,
inertia: f32,

angle: f32,

tires: Tires,

pub fn init() Self {
    const width = 32;
    const height = 64;
    const mass = 3.0;
    return .{
        .pos = .{
            .x = g.SCREEN_WIDTH / 2.0,
            .y = g.SCREEN_HEIGHT - 3 * height,
        },
        .size = .{
            .x = width,
            .y = height,
        },

        .throttle = 0,
        .brake = 0,
        .steer = 0,

        .vel = .{ .x = 0, .y = 0 },
        .angular_vel = 0,

        .mass = mass,
        .inertia = mass * (width * width + height * height) / 12.0,

        .angle = 0.0,

        .tires = .{
            .front = .{ .size = .{ .x = width / 4, .y = height / 4 } },
            .rear = .{ .size = .{ .x = width / 4, .y = height / 4 } },
        },
    };
}

pub fn update(self: *Self, time: f32) void {
    const forward = rl.Vector2{
        .x = math.sin(self.angle),
        .y = -math.cos(self.angle),
    };
    const right = rl.Vector2{
        .x = forward.y,
        .y = -forward.x,
    };

    const vel_x = rl.Vector2DotProduct(right, self.vel);
    const vel_y = rl.Vector2DotProduct(forward, self.vel);

    if (rl.IsKeyDown(rl.KEY_A)) {
        self.steer = @max(-1, self.steer - g.STEER_SPEED * time);
    } else if (rl.IsKeyDown(rl.KEY_D)) {
        self.steer = @min(1, self.steer + g.STEER_SPEED * time);
    } else {
        self.steer = @max(0, self.steer - math.sign(self.steer) * 2 * g.STEER_SPEED * time);
    }

    if (rl.IsKeyDown(rl.KEY_W)) {
        if (vel_y >= 0) {
            self.throttle = 1;
            self.brake = 0;
        } else {
            self.throttle = 0;
            self.brake = 1;
        }
    } else if (rl.IsKeyDown(rl.KEY_S)) {
        if (vel_y <= 0) {
            self.throttle = -1;
            self.brake = 0;
        } else {
            self.throttle = 0;
            self.brake = 1;
        }
    } else {
        self.throttle = 0;
        self.brake = 0;
    }

    const F_drag = rl.Vector2Scale(self.vel, -g.DRAG_FACTOR * rl.Vector2Length(self.vel));
    const F_rr = rl.Vector2Scale(self.vel, -g.ROLLING_RESISTANCE);

    var F_trac = rl.Vector2Zero();
    if (self.throttle != 0) {
        F_trac = rl.Vector2Scale(forward, self.throttle * g.ENGINE_FORCE);
    }

    var F_break = rl.Vector2Zero();
    if (self.brake != 0) {
        const vel_dir = rl.Vector2Normalize(self.vel);
        F_break = rl.Vector2Scale(vel_dir, -self.brake * g.BRAKE_FORCE);
    }

    const axel = self.size.y / 2;
    const steer_angle = self.steer * g.MAX_STEER_ANGLE;

    const slip_front = math.atan2(vel_x + self.angular_vel * axel, @abs(vel_y)) - math.sign(vel_y) * steer_angle;
    const slip_rear = math.atan2(vel_x - self.angular_vel * axel, @abs(vel_y));

    const F_lat_front_mag = -g.CORNERING_STIFFNESS_FRONT * slip_front;
    const F_lat_rear_mag = -g.CORNERING_STIFFNESS_REAR * slip_rear;

    const F_lat_front = rl.Vector2Scale(right, F_lat_front_mag);
    const F_lat_rear = rl.Vector2Scale(right, F_lat_rear_mag);

    const F_net = vec_add(&.{ F_trac, F_break, F_drag, F_rr, F_lat_front, F_lat_rear });
    const accel = rl.Vector2Scale(F_net, 1 / self.mass);

    self.vel = rl.Vector2Add(self.vel, rl.Vector2Scale(accel, time));
    self.pos = rl.Vector2Add(self.pos, rl.Vector2Scale(self.vel, time));

    const F_torque = axel * (F_lat_front_mag * @cos(steer_angle) - F_lat_rear_mag);
    const angular_accel = F_torque / self.inertia;

    self.angular_vel += angular_accel * time;
    self.angle = @mod(self.angle + self.angular_vel * time, 2 * math.pi);

    if (rl.Vector2Length(self.vel) < g.VELOCITY_THRESHOLD and self.throttle == 0) {
        self.vel = rl.Vector2Zero();
        self.angular_vel = 0;
    }
}

pub fn rect(self: *const Self) rl.Rectangle {
    return .{
        .x = self.pos.x - self.size.x / 2,
        .y = self.pos.y - self.size.y / 2,
        .width = self.size.x,
        .height = self.size.y,
    };
}

pub fn draw(self: *const Self) void {
    const car_rect = rl.Rectangle{
        .x = self.pos.x,
        .y = self.pos.y,
        .width = self.size.x,
        .height = self.size.y,
    };

    self.draw_tire(-4, self.tires.front.size.y / 2, self.tires.front, self.steer * g.MAX_STEER_ANGLE);
    self.draw_tire(-4, self.size.y - self.tires.rear.size.y / 2, self.tires.rear, 0);
    self.draw_tire(self.size.x + 4, self.tires.front.size.y / 2, self.tires.front, self.steer * g.MAX_STEER_ANGLE);
    self.draw_tire(self.size.x + 4, self.size.y - self.tires.rear.size.y / 2, self.tires.rear, 0);

    rl.DrawRectanglePro(
        car_rect,
        .{ .x = self.size.x / 2, .y = self.size.y / 2 },
        self.angle * 180 / math.pi,
        rl.YELLOW,
    );
}

fn draw_tire(self: *const Self, x: f32, y: f32, tire: Tire, steer_angle: f32) void {
    const tire_pos = vec_rotate(
        .{ .x = self.pos.x + x - self.size.x / 2, .y = self.pos.y + y - self.size.y / 2 },
        self.pos,
        self.angle,
    );
    rl.DrawRectanglePro(
        .{
            .x = tire_pos.x,
            .y = tire_pos.y,
            .width = tire.size.x,
            .height = tire.size.y,
        },
        .{ .x = tire.size.x / 2, .y = tire.size.y / 2 },
        (self.angle + steer_angle) * 180 / math.pi,
        rl.BLACK,
    );
}
