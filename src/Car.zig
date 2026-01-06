const std = @import("std");

const rl = @import("raylib.zig").rl;
const vec_rotate = @import("raylib.zig").vec_rotate;
const vec_add = @import("raylib.zig").vec_add;

const math = @import("std").math;
const g = @import("globals.zig");

const Map = @import("Map.zig");

const Action = enum { left, right, straight };

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
    for (curr.edges.keys()) |edge_id| {
        const node = &map.nodes.items[edge_id];
        const dir = rl.Vector2Subtract(node.pos, pos);
        if (@floor(rl.Vector2DotProduct(forward, dir)) > 0) {
            return edge_id;
        }
    }
    return null;
}

pub fn update(self: *Self, time: f32, map: *const Map) void {
    if (self.is_player) {
        if (rl.IsKeyPressed(rl.KEY_W)) {
            self.next_action = .straight;
        } else if (rl.IsKeyPressed(rl.KEY_D)) {
            self.next_action = .right;
        } else if (rl.IsKeyPressed(rl.KEY_A)) {
            self.next_action = .left;
        }
    }

    if (self.next_node) |target_index| {
        const target = map.nodes.items[target_index];
        const dist = rl.Vector2Distance(self.pos, target.pos);
        if (dist < 5.0) {
            self.pos = target.pos;
            self.curr_node = target_index;
            self.next_node = null;

            if (!self.is_player) {
                const pi_2: f32 = math.pi / 2.0;
                // FIXME: this is dangerous
                while (true) {
                    const action = std.crypto.random.enumValue(Action);
                    const angle = self.angle + switch (action) {
                        .left => -pi_2,
                        .right => pi_2,
                        .straight => 0.0,
                    };
                    if (findNextNode(self.pos, angle, target_index, map) != null) {
                        self.next_action = action;
                        break;
                    }
                }
            }
            if (self.next_action == .left or self.next_action == .right) {
                self.speed *= 0.6;
            }
            return;
        }

        self.speed = @min(self.speed + self.accel * time, g.MAX_SPEED);
        if (rl.IsKeyDown(rl.KEY_S)) {
            self.speed = @max(self.speed - self.brake * time, 0);
        }

        const dir = rl.Vector2Normalize(rl.Vector2Subtract(target.pos, self.pos));
        self.vel = rl.Vector2Scale(dir, self.speed);
        self.pos.x += self.vel.x * time;
        self.pos.y += self.vel.y * time;
        return;
    }

    if (self.curr_node) |curr_index| {
        if (self.next_action) |next_action| {
            switch (next_action) {
                .left => self.angle -= math.pi / 2.0,
                .right => self.angle += math.pi / 2.0,
                .straight => {},
            }
            self.next_action = null;
        }
        self.next_node = findNextNode(self.pos, self.angle, curr_index, map);
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
    rl.DrawTexturePro(
        self.texture,
        .{ .x = 0, .y = 0, .width = self.size.x, .height = self.size.y },
        .{ .x = self.pos.x, .y = self.pos.y, .width = self.size.x, .height = self.size.y },
        .{ .x = self.size.x / 2, .y = self.size.y / 2 },
        self.angle * 180 / math.pi,
        rl.WHITE,
    );
}
