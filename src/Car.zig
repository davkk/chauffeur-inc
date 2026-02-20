const std = @import("std");
const g = @import("globals.zig");

const rl = @import("raylib.zig").rl;
const vec_rotate = @import("raylib.zig").vec_rotate;
const vec_add = @import("raylib.zig").vec_add;

const Map = @import("Map.zig");

const Self = @This();

const BASE_VEC: [4]rl.Vector2 = .{
    .{ .x = 0, .y = -1 },
    .{ .x = 1, .y = 0 },
    .{ .x = 0, .y = 1 },
    .{ .x = -1, .y = 0 },
};

texture: rl.Texture2D,

pos: rl.Vector2,
size: rl.Vector2,

curr_node: ?usize,
next_node: ?usize,

speed: f32,
vel: rl.Vector2,

accel: f32,
frict: f32,
brake: f32,

curr_dir: g.Direction,
prev_dir: ?g.Direction,
next_dir: ?g.Direction,
next_dir_timer: f32,

pub fn init(start_node: *const Map.Node) Self {
    const width = 16;
    const height = 32;

    const image = @embedFile("assets/taxi-car.png");
    const taxi_image = rl.LoadImageFromMemory(".png", image.ptr, @intCast(image.len));

    return .{
        .texture = rl.LoadTextureFromImage(taxi_image),

        .pos = .{
            .x = start_node.pos.x,
            .y = start_node.pos.y,
        },
        .size = .{
            .x = width,
            .y = height,
        },

        .curr_node = start_node.id,
        .next_node = null,

        .accel = 80,
        .frict = 100,
        .brake = 300,

        .speed = 0,
        .vel = rl.Vector2Zero(),

        .curr_dir = .right,
        .prev_dir = null,
        .next_dir = null,
        .next_dir_timer = 0,
    };
}

pub fn deinit(self: *Self) void {
    rl.UnloadTexture(self.texture);
}

pub fn update(self: *Self, dt: f32, map: *const Map, input: g.KeyInput) void {
    if (input.dir) |dir| {
        self.next_dir = dir;
        self.next_dir_timer = 0;
    }

    self.next_dir_timer += dt;
    if (self.next_dir_timer > g.NEXT_DIR_TIMEOUT) {
        self.next_dir = null;
    }

    self.prev_dir = self.curr_dir;

    if (self.next_node) |next_idx| {
        const next_node = map.nodes.items[next_idx];

        if (self.next_dir) |next_dir| {
            const opp_dir = oppositeDirection(self.curr_dir);
            const opp_dir_idx = @intFromEnum(opp_dir);
            if (next_dir == opp_dir) {
                self.prev_dir = self.curr_dir;
                self.curr_dir = next_dir;
                self.next_node = next_node.edges[opp_dir_idx];
                self.next_dir = null;
            }
        }

        const dist = rl.Vector2Distance(self.pos, next_node.pos);
        if (dist < 5.0) {
            self.pos = next_node.pos;
            self.curr_node = next_idx;
            self.next_node = null;
            return; // TODO: refactor this, confusing flow
        }
    } else if (self.curr_node) |curr_idx| {
        if (self.next_dir) |next_dir| {
            self.prev_dir = self.curr_dir;
            self.curr_dir = next_dir;
        }

        const curr_node = &map.nodes.items[curr_idx];
        self.next_node = curr_node.edges[@intFromEnum(self.curr_dir)];

        if (self.next_node == null) {
            self.vel = rl.Vector2Zero();
            self.speed = 0;
            return; // TODO: refactor this, confusing flow
        }
    }

    self.speed = @min(self.speed + self.accel * dt, g.MAX_SPEED);
    if (input.brake) {
        self.speed = @max(self.speed - self.brake * dt, 0);
    }

    if (self.prev_dir) |prev_dir| {
        if (self.curr_dir != prev_dir) {
            const curr_dir_idx: i32 = @intFromEnum(self.curr_dir);
            const prev_dir_idx: i32 = @intFromEnum(prev_dir);
            const dir_diff = @mod(curr_dir_idx - prev_dir_idx, 4);
            if (dir_diff == 1 or dir_diff == 3) {
                self.speed *= g.SPEED_PENALTY_TURN;
            } else if (dir_diff == 2) {
                self.speed *= g.SPEED_PENALTY_UTURN;
            }
        }
        self.prev_dir = null;
    }

    self.vel = rl.Vector2Scale(BASE_VEC[@intFromEnum(self.curr_dir)], self.speed);
    self.pos = rl.Vector2Add(self.pos, rl.Vector2Scale(self.vel, dt));
}

pub fn draw(self: *const Self) void {
    const angle: f32 = switch (self.curr_dir) {
        .up => 0,
        .right => 90,
        .down => 180,
        .left => 270,
    };
    rl.DrawTexturePro(
        self.texture,
        .{ .x = 0, .y = 0, .width = self.size.x, .height = self.size.y },
        .{ .x = self.pos.x, .y = self.pos.y, .width = self.size.x, .height = self.size.y },
        .{ .x = self.size.x / 2, .y = self.size.y / 2 },
        angle,
        rl.WHITE,
    );
}

fn oppositeDirection(dir: g.Direction) g.Direction {
    const dir_idx: usize = @intFromEnum(dir);
    return @enumFromInt((dir_idx + 2) % 4);
}

pub fn rect(self: *const Self) rl.Rectangle {
    return .{
        .x = self.pos.x - self.size.x / 2,
        .y = self.pos.y - self.size.y / 2,
        .width = self.size.x,
        .height = self.size.y,
    };
}
