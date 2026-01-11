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

next_action: ?Action,

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

        .next_action = null,
    };
}

pub fn deinit(self: *Self) void {
    rl.UnloadTexture(self.texture);
}

fn findNextNode(pos: rl.Vector2, angle: f32, curr_index: usize, map: *const Map) ?usize {
    const curr = &map.nodes.items[curr_index];
    const forward = rl.Vector2{
        .x = math.sin(angle),
        .y = -math.cos(angle),
    };
    for (curr.edges) |edge_id| {
        if (edge_id == null) continue;
        const node = &map.nodes.items[edge_id.?];
        const dir = rl.Vector2Subtract(node.pos, pos);
        if (@floor(rl.Vector2DotProduct(forward, dir)) > 0) {
            return edge_id;
        }
    }
    return null;
}

const PI_2: f32 = math.pi / 2.0;

pub fn update(self: *Self, time: f32, map: *const Map) void {
    if (self.is_player) {
        // TODO: make steering relative to the map and not the car, like in pacman
        if (rl.IsKeyPressed(rl.KEY_W)) {
            self.next_action = .up;
        } else if (rl.IsKeyPressed(rl.KEY_A)) {
            self.next_action = .left;
        } else if (rl.IsKeyPressed(rl.KEY_S)) {
            self.next_action = .down;
        } else if (rl.IsKeyPressed(rl.KEY_D)) {
            self.next_action = .right;
        }
    }

    if (self.next_node) |next_idx| {
        const target = map.nodes.items[next_idx];
        const dist = rl.Vector2Distance(self.pos, target.pos);

        if (dist < self.size.y and self.next_action == .right or dist < 5.0) {
            self.curr_node = next_idx;
            self.next_node = null;

            // TODO: this needs to happen based on forward direction
            // if (self.next_action == .left or self.next_action == .right) {
            //     self.speed *= 0.6;
            // }

            if (self.next_action) |next_action| {
                switch (next_action) {
                    .left => {
                        self.angle = math.pi + PI_2;
                        self.pos = target.pos;
                    },
                    .right => {
                        self.angle = PI_2;
                        self.pos = target.pos;
                        // const forward = rl.Vector2{
                        //     .x = math.sin(self.angle),
                        //     .y = -math.cos(self.angle),
                        // };
                        // self.pos = rl.Vector2Add(target.pos, rl.Vector2Scale(forward, self.size.y));
                    },
                    .up => {
                        self.angle = 0;
                        self.pos = target.pos;
                    },
                    .down => {
                        self.angle = math.pi;
                        self.pos = target.pos;
                    }
                }
                self.next_action = null;
            }

            // if (!self.is_player) {
            //     // TODO: this will be changed when I implement path finding for ai cars
            //     const action = std.crypto.random.enumValue(Action);
            //     if (findNextNode(target.pos, self.angle, next_idx, map)) |next_next_idx| {
            //         self.next_action = action;
            //         self.next_node = next_next_idx;
            //     } else {
            //         self.vel = rl.Vector2Zero();
            //         self.speed = 0;
            //         self.pos = rl.Vector2{ .x = -1000, .y = -1000 };
            //     }
            // }

            return;
        }

        self.speed = @min(self.speed + self.accel * time, g.MAX_SPEED);
        if (self.is_player and rl.IsKeyDown(rl.KEY_SPACE)) {
            self.speed = @max(self.speed - self.brake * time, 0);
        }

        const dir = rl.Vector2Normalize(rl.Vector2Subtract(target.pos, self.pos));
        self.vel = rl.Vector2Scale(dir, self.speed);
        self.pos.x += self.vel.x * time;
        self.pos.y += self.vel.y * time;
        return;
    }

    if (self.curr_node) |curr_idx| {
        const curr_node = &map.nodes.items[curr_idx];
        self.next_node = findNextNode(curr_node.pos, self.angle, curr_idx, map);
        if (self.next_node == null) {
            self.vel = rl.Vector2Zero();
            self.speed = 0;
            // TODO: game over, hit a wall
        }
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
    const forward = rl.Vector2{
        .x = math.sin(self.angle),
        .y = -math.cos(self.angle),
    };
    const right = rl.Vector2{
        .x = -forward.y,
        .y = forward.x,
    };

    const offset = vec_add(&.{
        self.pos,
        rl.Vector2Scale(right, self.size.x),
    });

    rl.DrawTexturePro(
        self.texture,
        .{ .x = 0, .y = 0, .width = self.size.x, .height = self.size.y },
        .{ .x = offset.x, .y = offset.y, .width = self.size.x, .height = self.size.y },
        .{ .x = self.size.x / 2, .y = self.size.y / 2 },
        self.angle * 180 / math.pi,
        rl.WHITE,
    );
}
