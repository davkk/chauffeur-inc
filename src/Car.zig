const std = @import("std");

const rl = @import("raylib.zig").rl;
const vec_rotate = @import("raylib.zig").vec_rotate;
const vec_add = @import("raylib.zig").vec_add;

const math = @import("std").math;
const g = @import("globals.zig");

const Map = @import("Map.zig");

const Action = enum { up, down, left, right };

const Self = @This();

texture: rl.Texture2D,

is_player: bool,

pos: rl.Vector2,
size: rl.Vector2,

curr_node: ?usize,
next_node: ?usize,

speed: f32,
vel: rl.Vector2,

accel: f32,
frict: f32,
brake: f32,

angle: f32,
prev_angle: ?f32,

next_dir: ?g.Direction,
next_dir_timer: f32,

pub fn init(is_player: bool, x: f32, y: f32, angle: f32) Self {
    const width = 16;
    const height = 32;

    const image = @embedFile("assets/taxi-car.png");
    const taxi_image = rl.LoadImageFromMemory(".png", image.ptr, @intCast(image.len));

    return .{
        .is_player = is_player,

        .texture = rl.LoadTextureFromImage(taxi_image),

        .pos = .{
            .x = x,
            .y = y,
        },
        .size = .{
            .x = width,
            .y = height,
        },

        .curr_node = null,
        .next_node = null,

        .accel = 60,
        .frict = 100,
        .brake = 250,

        .speed = 0,
        .vel = rl.Vector2Zero(),

        .angle = angle,
        .prev_angle = null,

        .next_dir = null,
        .next_dir_timer = 0,
    };
}

pub fn deinit(self: *Self) void {
    rl.UnloadTexture(self.texture);
}

fn direction(self: *Self) g.Direction {
    const x: i32 = @intFromFloat(math.sin(self.angle));
    const y: i32 = @intFromFloat(-math.cos(self.angle));
    if (x == 0 and y < 0) return .up;
    if (y == 0 and x > 0) return .right;
    if (x == 0 and y > 0) return .down;
    return .left;
}

fn oppositeDirection(self: *Self) g.Direction {
    const dir_idx: usize = @intFromEnum(self.direction());
    return @enumFromInt((dir_idx + 2) % 4);
}

fn forward(self: *Self) rl.Vector2 {
    return .{
        .x = math.sin(self.angle),
        .y = -math.cos(self.angle),
    };
}

const PI_2: f32 = math.pi / 2.0;

pub fn update(self: *Self, dt: f32, map: *const Map) void {
    if (self.is_player) {
        if (rl.IsKeyPressed(rl.KEY_W)) {
            self.next_dir = .up;
            self.next_dir_timer = 0;
        } else if (rl.IsKeyPressed(rl.KEY_A)) {
            self.next_dir = .left;
            self.next_dir_timer = 0;
        } else if (rl.IsKeyPressed(rl.KEY_S)) {
            self.next_dir = .down;
            self.next_dir_timer = 0;
        } else if (rl.IsKeyPressed(rl.KEY_D)) {
            self.next_dir = .right;
            self.next_dir_timer = 0;
        }
    }

    self.next_dir_timer += dt;
    if (self.next_dir_timer > g.NEXT_DIR_TIMEOUT) {
        self.next_dir = null;
    }

    self.prev_angle = self.angle;

    if (self.next_node) |next_idx| {
        const next_node = map.nodes.items[next_idx];

        if (self.next_dir) |next_dir| {
            const opp_dir = self.oppositeDirection();
            const opp_dir_idx = @intFromEnum(opp_dir);
            if (next_dir == opp_dir) {
                const k: f32 = @floatFromInt(opp_dir_idx);
                self.prev_angle = self.angle;
                self.angle = k * PI_2;
                self.next_node = next_node.edges[opp_dir_idx];
                self.next_dir = null;
            }
        }

        const dist = rl.Vector2Distance(self.pos, next_node.pos);

        if (dist < 5.0) {
            self.pos = next_node.pos;

            self.curr_node = next_idx;
            self.next_node = null;
        }
    } else if (self.curr_node) |curr_idx| {
        if (self.next_dir) |next_dir| {
            const idx: f32 = @floatFromInt(@intFromEnum(next_dir));
            self.prev_angle = self.angle;
            self.angle = idx * PI_2;
        }

        const curr_node = &map.nodes.items[curr_idx];
        self.next_node = curr_node.edges[@intFromEnum(self.direction())];

        if (self.next_node == null) {
            self.vel = rl.Vector2Zero();
            self.speed = 0;
        }
    }

    self.speed = @min(self.speed + self.accel * dt, g.MAX_SPEED);
    if (self.is_player and rl.IsKeyDown(rl.KEY_SPACE)) {
        self.speed = @max(self.speed - self.brake * dt, 0);
    }

    if (self.prev_angle) |prev_angle| {
        if (self.angle != prev_angle) {
            const angle_diff = @abs(self.angle - prev_angle);
            if (angle_diff - PI_2 < 1e-4) {
                self.speed *= g.SPEED_PENALTY_TURN;
            } else if (angle_diff - math.pi < 1e-4) {
                self.speed *= g.SPEED_PENALTY_UTURN;
            }
        }
        self.prev_angle = null;
    }

    self.vel = rl.Vector2Scale(self.forward(), self.speed);
    self.pos.x += self.vel.x * dt;
    self.pos.y += self.vel.y * dt;
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
    // const forward = rl.Vector2{
    //     .x = math.sin(self.angle),
    //     .y = -math.cos(self.angle),
    // };
    // const right = rl.Vector2{
    //     .x = -forward.y,
    //     .y = forward.x,
    // };
    // const offset = vec_add(&.{
    //     self.pos,
    //     rl.Vector2Scale(right, self.size.x),
    // });

    rl.DrawTexturePro(
        self.texture,
        .{ .x = 0, .y = 0, .width = self.size.x, .height = self.size.y },
        .{ .x = self.pos.x, .y = self.pos.y, .width = self.size.x, .height = self.size.y },
        .{ .x = self.size.x / 2, .y = self.size.y / 2 },
        self.angle * 180 / math.pi,
        rl.WHITE,
    );
}
