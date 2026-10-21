const std = @import("std");
const math = std.math;
const c = @import("constants.zig");

const rl = @import("raylib.zig").rl;
const vec_rotate = @import("raylib.zig").vec_rotate;
const vec_add = @import("raylib.zig").vec_add;
const collision = @import("collision.zig");

const Game = @import("Game.zig");
const Map = @import("Map.zig");
const Direction = Map.Direction;

const Self = @This();

/// Visual body of a car. Every model uses the same 16x32 collision size and
/// points its nose toward local -Y, so the driving logic is model-agnostic.
pub const Model = enum {
    taxi,
    red_sedan,
    blue_sedan,
    green_hatchback,
    white_van,
    purple_coupe,

    const assets = [_][]const u8{
        @embedFile("assets/taxi-car.png"),
        @embedFile("assets/cars/red-sedan.png"),
        @embedFile("assets/cars/blue-sedan.png"),
        @embedFile("assets/cars/green-hatchback.png"),
        @embedFile("assets/cars/white-van.png"),
        @embedFile("assets/cars/purple-coupe.png"),
    };

    fn textureBytes(self: Model) []const u8 {
        return assets[@intFromEnum(self)];
    }
};

texture: ?rl.Texture2D,
model: Model,

pos: rl.Vector2,
size: rl.Vector2,

curr_node: ?usize,
next_node: ?usize,

speed: f32,
vel: rl.Vector2,

accel: f32,
brake: f32,

curr_dir: Direction,
prev_dir: ?Direction,
next_dir: ?Direction,
next_dir_timer: f32,

lane_offset: f32,
target_lane_offset: f32,
lane_index: i8,
dodge_timer: f32,
angle: f32,

/// Physical displacement from a crash. This is visual/collision state only:
/// `pos` keeps the logical path so turns and flips are not disturbed.
push_offset: rl.Vector2,
stun_timer: f32,

turn_t: ?f32,
turn_node: usize,
turn_entry: Direction,
turn_exit: Direction,

flip_t: ?f32,
flip_from: Direction,
flip_center: rl.Vector2,
flip_sign: f32,

pub fn init(start_node: *const Map.Node) Self {
    return initInternal(start_node, true, .taxi);
}

/// Spawn a car with a specific body. Traffic uses this so the player keeps the
/// taxi while the rest of the road gets a mix of vehicles.
pub fn initWithModel(start_node: *const Map.Node, model: Model) Self {
    return initInternal(start_node, true, model);
}

/// Headless variant: no GPU context is required, so the whole game can be
/// simulated in a terminal (used by `--sim` and the automated tests).
pub fn initHeadless(start_node: *const Map.Node) Self {
    return initInternal(start_node, false, .taxi);
}

fn initInternal(start_node: *const Map.Node, load_texture: bool, model: Model) Self {
    const width = c.CAR_WIDTH;
    const height = c.CAR_HEIGHT;

    const texture: ?rl.Texture2D = if (load_texture) blk: {
        const bytes = model.textureBytes();
        const image = rl.LoadImageFromMemory(".png", bytes.ptr, @intCast(bytes.len));
        const loaded = rl.LoadTextureFromImage(image);
        rl.UnloadImage(image);
        break :blk loaded;
    } else null;

    return .{
        .texture = texture,
        .model = model,
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

        .accel = 200,
        .brake = 800,

        .speed = 0,
        .vel = rl.Vector2Zero(),

        .curr_dir = .right,
        .prev_dir = null,
        .next_dir = null,
        .next_dir_timer = 0,

        .lane_offset = c.LANE_WIDTH,
        .target_lane_offset = c.LANE_WIDTH,
        .lane_index = 1,
        .dodge_timer = 0,
        .angle = 90,
        .push_offset = rl.Vector2Zero(),
        .stun_timer = 0,
        .turn_t = null,
        .turn_node = start_node.id,
        .turn_entry = .right,
        .turn_exit = .right,
        .flip_t = null,
        .flip_from = .right,
        .flip_center = .{ .x = 0, .y = 0 },
        .flip_sign = 1.0,
    };
}

pub fn deinit(self: *Self) void {
    if (self.texture) |texture| rl.UnloadTexture(texture);
}

pub fn update(self: *Self, dt: f32, map: *const Map, input: Game.KeyInput) void {
    self.decayPush(dt);
    if (self.stun_timer > 0) {
        self.stun_timer = @max(0, self.stun_timer - dt);
    }

    if (input.dir) |dir| {
        self.next_dir = dir;
        self.next_dir_timer = 0;
    }

    if (input.lane_toggle) {
        self.lane_index = -self.lane_index;
    }

    if (input.dodge) {
        self.dodge_timer = c.DODGE_DURATION;
    }

    if (self.dodge_timer > 0) {
        self.dodge_timer -= dt;
    }

    self.prev_dir = self.curr_dir;

    if (self.turn_t == null and self.flip_t == null) {
        if (self.next_node) |next_idx| {
            const next_node = map.nodes.items[next_idx];

            if (self.next_dir) |next_dir| {
                const opp_dir = oppositeDirection(self.curr_dir);
                if (next_dir == opp_dir) {
                    const d = rl.Vector2Distance(self.pos, next_node.pos);
                    if (d >= c.TURN_RADIUS and self.curr_node != null) {
                        // Mid-edge U-turn: loop forward in place, then head back to the node we left.
                        // Reverse the graph state too, not just the heading.
                        // After the flip the node we were driving toward is
                        // behind us and the node we came from is the target.
                        // Leaving `next_node == curr_node` here made a second
                        // U-turn drive away from that node forever (cars
                        // escaped the map on the right edge).
                        const behind = self.curr_node;
                        self.curr_node = self.next_node;
                        self.next_node = behind;

                        self.flip_t = 0.0;
                        self.flip_from = self.curr_dir;
                        self.flip_center = self.pos;
                        self.flip_sign = if (self.lane_index < 0) -1.0 else 1.0;
                        self.next_dir = null;
                        // Draw this frame at the lane position, not the centerline.
                        self.pos = rl.Vector2Add(self.flip_center, rl.Vector2Scale(laneRightVec(self.angle), self.lane_offset));
                        return;
                    }
                }
            }

            if (self.next_node) |tgt_idx| {
                const tgt = map.nodes.items[tgt_idx];
                const dist = rl.Vector2Distance(self.pos, tgt.pos);

                const exit_dir = self.next_dir orelse self.curr_dir;
                // With no input, wait until the last moment to commit straight so a late key press can still turn.
                const commit_dist: f32 = if (self.next_dir != null) c.TURN_RADIUS else c.STRAIGHT_COMMIT_DIST;
                if (dist < commit_dist) {
                    const can_leave = tgt.edges[@intFromEnum(exit_dir)] != null;
                    if (can_leave) {
                        const pts = turnPoints(self.curr_dir, exit_dir, self.lane_offset, tgt.pos, tgt.edges[@intFromEnum(self.curr_dir)] != null);
                        const arc = bezierLen(pts.p0, pts.p1, pts.p2_lane);
                        self.turn_t = @min((c.TURN_RADIUS - dist) / arc, 0.9);
                        self.turn_node = tgt_idx;
                        self.turn_entry = self.curr_dir;
                        self.turn_exit = exit_dir;
                    }
                }

                // Robust arrival. The car moves up to `speed * dt` in a single
                // step, so a fixed 5px window can be overshot on a frame-time
                // spike: the car leaps past the node to the far side, `dist`
                // starts growing again, and if no turn could commit here
                // (`can_leave == false`, e.g. a dead-end) it sails off the map.
                // Trigger whenever we'd reach *or* pass the node this step.
                const arrive_dist = @max(5.0, self.speed * dt);
                if (self.turn_t == null and dist < arrive_dist) {
                    self.pos = tgt.pos;
                    self.curr_node = tgt_idx;
                    self.next_node = null;
                    self.next_dir = null;
                    return;
                }
            }
        } else if (self.curr_node) |curr_idx| {
            if (self.next_dir) |next_dir| {
                self.prev_dir = self.curr_dir;
                self.curr_dir = next_dir;
                self.next_dir = null;
            }

            const curr_node = &map.nodes.items[curr_idx];
            self.next_node = curr_node.edges[@intFromEnum(self.curr_dir)];

            if (self.next_node == null) {
                self.vel = rl.Vector2Zero();
                self.speed = 0;
                return;
            }
        }
    }

    if (self.turn_t) |t| {
        self.applyAcceleration(dt, input.brake);
        const pts = turnPoints(self.turn_entry, self.turn_exit, self.lane_offset, map.nodes.items[self.turn_node].pos, map.nodes.items[self.turn_node].edges[@intFromEnum(self.turn_entry)] != null);
        const cap = @min(c.MAX_SPEED, @sqrt(c.LAT_A_MAX * minCurveRadius(pts.p0, pts.p1, pts.p2_lane)));
        self.speed = math.lerp(self.speed, @min(self.speed, cap), @min(5.0 * dt, 1.0));
        if (input.dodge or self.dodge_timer > 0) {
            self.target_lane_offset = self.size.x;
        } else {
            self.target_lane_offset = @as(f32, @floatFromInt(self.lane_index)) * c.LANE_WIDTH;
        }
        self.lane_offset = math.lerp(self.lane_offset, self.target_lane_offset, c.DODGE_SPEED * dt);

        const nt = t + self.speed * dt / bezierLen(pts.p0, pts.p1, pts.p2_lane);

        if (nt >= 1.0) {
            const exit = self.turn_exit;
            self.pos = pts.p2;
            self.curr_node = self.turn_node;
            self.curr_dir = exit;
            self.prev_dir = null;
            self.turn_t = null;
            const node = &map.nodes.items[self.turn_node];
            self.next_node = node.edges[@intFromEnum(exit)];
            if (self.next_dir) |nd| {
                if (nd == exit) self.next_dir = null;
            }
            self.angle = dirToAngle(exit);
            self.vel = rl.Vector2Scale(c.BASE_VEC[@intFromEnum(exit)], self.speed);
        } else {
            self.turn_t = nt;
            const st = nt * nt * (3.0 - 2.0 * nt);
            const mt: f32 = 1.0 - nt;
            self.pos = .{
                .x = mt * mt * pts.p0.x + 2.0 * mt * nt * pts.p1.x + nt * nt * pts.p2_lane.x,
                .y = mt * mt * pts.p0.y + 2.0 * mt * nt * pts.p1.y + nt * nt * pts.p2_lane.y,
            };
            const a0 = dirToAngle(self.turn_entry);
            const a1 = dirToAngle(self.turn_exit);
            var d = a1 - a0;
            d = @mod(d + 180.0, 360.0) - 180.0;
            self.angle = @mod(a0 + d * st, 360.0);
            const tangent = rl.Vector2Normalize(.{
                .x = 2.0 * (1.0 - nt) * (pts.p1.x - pts.p0.x) + 2.0 * nt * (pts.p2_lane.x - pts.p1.x),
                .y = 2.0 * (1.0 - nt) * (pts.p1.y - pts.p0.y) + 2.0 * nt * (pts.p2_lane.y - pts.p1.y),
            });
            self.vel = rl.Vector2Scale(tangent, self.speed);
        }
        return;
    }

    if (self.flip_t) |t| {
        self.applyAcceleration(dt, input.brake);
        // Semicircle of radius LANE_WIDTH; cap speed from lateral grip.
        const cap = @min(c.MAX_SPEED, @sqrt(c.LAT_A_MAX * c.LANE_WIDTH));
        self.speed = math.lerp(self.speed, @min(self.speed, cap), @min(5.0 * dt, 1.0));

        // Floor advance at FLIP_ARC so braking can't stall the loop (<1s).
        const nt = t + @max(self.speed, c.FLIP_ARC) * dt / c.FLIP_ARC;
        const a0 = dirToAngle(self.flip_from);
        if (nt >= 1.0) {
            self.curr_dir = oppositeDirection(self.flip_from);
            self.prev_dir = null;
            self.angle = dirToAngle(self.curr_dir);
            self.pos = self.flip_center;
            self.flip_t = null;
            if (self.next_dir) |nd| {
                if (nd == self.flip_from) self.next_dir = null;
            }
            self.vel = rl.Vector2Scale(c.BASE_VEC[@intFromEnum(self.curr_dir)], self.speed);
        } else {
            self.flip_t = nt;
            self.angle = @mod(a0 - 180.0 * nt * self.flip_sign, 360.0);
            // Bake lane into pos: sweep the semicircle around flip_center, nose forward.
            self.pos = rl.Vector2Add(self.flip_center, rl.Vector2Scale(laneRightVec(self.angle), self.lane_offset));
            const rad = self.angle * math.pi / 180.0;
            self.vel = rl.Vector2Scale(.{ .x = math.sin(rad), .y = -math.cos(rad) }, self.speed);
        }
        return;
    }

    self.applyAcceleration(dt, input.brake);

    if (input.dodge or self.dodge_timer > 0) {
        self.target_lane_offset = self.size.x;
        self.speed = @max(self.speed - self.brake * 0.5 * dt, 0.5 * c.MAX_SPEED);
    } else {
        self.target_lane_offset = @as(f32, @floatFromInt(self.lane_index)) * c.LANE_WIDTH;
    }
    self.lane_offset = math.lerp(self.lane_offset, self.target_lane_offset, c.DODGE_SPEED * dt);

    if (self.prev_dir) |prev_dir| {
        if (self.curr_dir != prev_dir) {
            const curr_dir_idx: i32 = @intFromEnum(self.curr_dir);
            const prev_dir_idx: i32 = @intFromEnum(prev_dir);

            const dir_diff = @mod(curr_dir_idx - prev_dir_idx, 4);
            if (dir_diff == 1 or dir_diff == 3) {
                self.speed *= c.SPEED_PENALTY_TURN;
            } else if (dir_diff == 2) {
                self.speed *= c.SPEED_PENALTY_UTURN;
            }
        }
        self.prev_dir = null;
    }

    const target_angle: f32 = switch (self.curr_dir) {
        .up => 0,
        .right => 90,
        .down => 180,
        .left => 270,
    };
    var diff = target_angle - self.angle;
    diff = @mod(diff + 180.0, 360.0) - 180.0;
    self.angle = @mod(self.angle + diff * @min(c.ANGLE_CHANGE_SPEED * dt, 1.0), 360.0);

    self.vel = rl.Vector2Scale(c.BASE_VEC[@intFromEnum(self.curr_dir)], self.speed);
    self.pos = rl.Vector2Add(self.pos, rl.Vector2Scale(self.vel, dt));
}

/// Where the car actually appears on screen. `pos` is the logical centerline
/// position while driving, but during a turn/flip the lane offset is baked
/// into `pos`, so the drawn position is `pos` directly. The camera and any
/// other "where is the car" queries must use this, not `pos`, or they'll see a
/// full LANE_WIDTH jump at the start and end of every turn.
/// Point the car in `dir` immediately, including the drawn angle and velocity.
/// Used when agents respawn at a new start node so they do not spend a frame
/// facing into a wall.
pub fn face(self: *Self, dir: Direction) void {
    self.curr_dir = dir;
    self.prev_dir = null;
    self.angle = dirToAngle(dir);
    self.vel = rl.Vector2Scale(c.BASE_VEC[@intFromEnum(dir)], self.speed);
}

/// Add a physical displacement from a collision, clamped so repeated overlaps
/// cannot fling a car across the map.
pub fn applyPush(self: *Self, delta: rl.Vector2) void {
    self.push_offset = rl.Vector2Add(self.push_offset, delta);
    const len = rl.Vector2Length(self.push_offset);
    if (len > c.PUSH_OFFSET_MAX) {
        self.push_offset = rl.Vector2Scale(self.push_offset, c.PUSH_OFFSET_MAX / len);
    }
}

/// The physical push of a crash fades away, the car eases back to its lane.
fn decayPush(self: *Self, dt: f32) void {
    self.push_offset = rl.Vector2Scale(self.push_offset, @exp(-c.PUSH_OFFSET_DECAY * dt));
    const len = rl.Vector2Length(self.push_offset);
    if (len > c.PUSH_OFFSET_MAX) {
        self.push_offset = rl.Vector2Scale(self.push_offset, c.PUSH_OFFSET_MAX / len);
    }
}

/// Oriented collision box at the drawn position using the real drawn angle.
///
/// The box is built in the car's own frame: `half_extents.x` is half the
/// width across the car, `half_extents.y` half its length. The angle is the
/// drawn angle in radians, so the box follows the sprite through a turn.
pub fn collisionBox(self: *const Self) collision.Box {
    return .{
        .center = self.visualPos(),
        .half_extents = .{ .x = self.size.x / 2.0, .y = self.size.y / 2.0 },
        .angle = self.angle * math.pi / 180.0,
    };
}

/// Overlap with another car, `null` when the two cars do not touch.
pub fn collidesWith(self: *const Self, other: *const Self) ?collision.Manifold {
    return collision.collide(self.collisionBox(), other.collisionBox());
}

/// True when both cars sit on the exact same spot. That is the intentional
/// spawn overlap (two cars parked on the same node), it is not a crash.
pub fn isSameSpot(self: *const Self, other: *const Self) bool {
    return self.curr_node == other.curr_node and
        self.pos.x == other.pos.x and
        self.pos.y == other.pos.y;
}

fn applyAcceleration(self: *Self, dt: f32, brake: bool) void {
    // A stunned car does not accelerate any more, it bleeds off its speed
    // instead. Braking still works, the driver can always stop.
    if (self.stun_timer > 0) {
        self.speed = @max(self.speed - c.CRASH_STUN_DECEL * dt, 0);
    } else {
        self.speed = @min(self.speed + self.accel * dt, c.MAX_SPEED);
    }
    if (brake) {
        self.speed = @max(self.speed - self.brake * dt, 0);
    }
}

pub fn visualPos(self: *const Self) rl.Vector2 {
    const path_pos = if (self.turn_t != null or self.flip_t != null)
        self.pos
    else
        rl.Vector2Add(self.pos, rl.Vector2Scale(laneRightVec(self.angle), self.lane_offset));
    return rl.Vector2Add(path_pos, self.push_offset);
}

pub fn draw(self: *const Self, alpha: f32) void {
    const texture = self.texture orelse return;
    const draw_pos = self.visualPos();

    const color = rl.ColorAlpha(rl.WHITE, alpha);
    rl.DrawTexturePro(
        texture,
        .{ .x = 0, .y = 0, .width = self.size.x, .height = self.size.y },
        .{
            .x = draw_pos.x,
            .y = draw_pos.y,
            .width = self.size.x,
            .height = self.size.y,
        },
        .{ .x = self.size.x / 2, .y = self.size.y / 2 },
        self.angle,
        color,
    );
}

fn oppositeDirection(dir: Direction) Direction {
    const dir_idx: usize = @intFromEnum(dir);
    return @enumFromInt((dir_idx + 2) % 4);
}

fn dirToAngle(dir: Direction) f32 {
    return switch (dir) {
        .up => 0,
        .right => 90,
        .down => 180,
        .left => 270,
    };
}

fn rightVec(dir: Direction) rl.Vector2 {
    const dir_idx: usize = @intFromEnum(dir);
    return c.BASE_VEC[(dir_idx + 1) % 4];
}

fn laneRightVec(angle_deg: f32) rl.Vector2 {
    const rad = angle_deg * math.pi / 180.0;
    return .{ .x = math.cos(rad), .y = math.sin(rad) };
}

const TurnPts = struct { p0: rl.Vector2, p1: rl.Vector2, p2_lane: rl.Vector2, p2: rl.Vector2 };

fn turnPoints(entry: Direction, exit: Direction, lane: f32, node_pos: rl.Vector2, straight_ok: bool) TurnPts {
    const entry_vec = c.BASE_VEC[@intFromEnum(entry)];
    const exit_vec = c.BASE_VEC[@intFromEnum(exit)];
    const re = rightVec(entry);
    const rx = rightVec(exit);
    const p1: rl.Vector2 = if (exit == entry)
        rl.Vector2Add(node_pos, rl.Vector2Scale(re, lane))
    else if (exit == oppositeDirection(entry))
        if (straight_ok)
            rl.Vector2Add(node_pos, rl.Vector2Scale(entry_vec, c.TURN_RADIUS))
        else
            rl.Vector2Add(node_pos, rl.Vector2Scale(entry_vec, c.CAR_WIDTH / 2.0))
    else
        .{
            // The control point is where the entry and exit tangents meet. For a
            // perpendicular turn that is one lane offset from the node toward the
            // outside of the turn, so the arc stays in its own lane instead of
            // cutting across the middle of the intersection.
            .x = node_pos.x + (re.x + rx.x) * lane,
            .y = node_pos.y + (re.y + rx.y) * lane,
        };
    return .{
        .p0 = .{
            .x = node_pos.x - entry_vec.x * c.TURN_RADIUS + re.x * lane,
            .y = node_pos.y - entry_vec.y * c.TURN_RADIUS + re.y * lane,
        },
        .p1 = p1,
        .p2_lane = .{
            .x = node_pos.x + exit_vec.x * c.TURN_RADIUS + rx.x * lane,
            .y = node_pos.y + exit_vec.y * c.TURN_RADIUS + rx.y * lane,
        },
        .p2 = .{
            .x = node_pos.x + exit_vec.x * c.TURN_RADIUS,
            .y = node_pos.y + exit_vec.y * c.TURN_RADIUS,
        },
    };
}

fn bezierLen(p0: rl.Vector2, p1: rl.Vector2, p2: rl.Vector2) f32 {
    var len: f32 = 0;
    var prev = p0;
    var i: usize = 1;
    while (i <= 8) : (i += 1) {
        const t: f32 = @as(f32, @floatFromInt(i)) / 8.0;
        const mt = 1.0 - t;
        const p = rl.Vector2{
            .x = mt * mt * p0.x + 2.0 * mt * t * p1.x + t * t * p2.x,
            .y = mt * mt * p0.y + 2.0 * mt * t * p1.y + t * t * p2.y,
        };
        len += rl.Vector2Distance(prev, p);
        prev = p;
    }
    return len;
}

fn minCurveRadius(p0: rl.Vector2, p1: rl.Vector2, p2: rl.Vector2) f32 {
    var min_r: f32 = math.inf(f32);
    var i: usize = 0;
    while (i <= 8) : (i += 1) {
        const t: f32 = @as(f32, @floatFromInt(i)) / 8.0;
        const d1 = rl.Vector2{
            .x = 2.0 * (1.0 - t) * (p1.x - p0.x) + 2.0 * t * (p2.x - p1.x),
            .y = 2.0 * (1.0 - t) * (p1.y - p0.y) + 2.0 * t * (p2.y - p1.y),
        };
        const d2 = rl.Vector2{
            .x = 2.0 * (p0.x - 2.0 * p1.x + p2.x),
            .y = 2.0 * (p0.y - 2.0 * p1.y + p2.y),
        };
        const cross = @abs(d1.x * d2.y - d1.y * d2.x);
        const sp = rl.Vector2Length(d1);
        if (sp > 1e-3 and cross > 1e-6) {
            min_r = @min(min_r, sp * sp * sp / cross);
        }
    }
    return min_r;
}
