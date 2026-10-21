const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const c = @import("constants.zig");

const Game = @import("Game.zig");
const Map = @import("Map.zig");
const Direction = Map.Direction;
const Car = @import("Car.zig");
const Agent = @import("Agent.zig");
const Passenger = @import("Passenger.zig");
const Hud = @import("Hud.zig");

const Self = @This();

pub const KeyInput = struct {
    dir: ?Direction,
    brake: bool,
    dodge: bool,
    lane_toggle: bool = false,

    pub fn init(dir: ?Direction, brake: bool, dodge: bool) KeyInput {
        return .{ .dir = dir, .brake = brake, .dodge = dodge };
    }
};

pub const EventKind = enum { none, pickup, delivered, expired, crash };

/// What happened during one simulation tick. The HUD uses it for popups and
/// the headless simulator sums it into its report.
pub const Step = struct {
    picked_up: bool = false,
    delivered: bool = false,
    expired: bool = false,
    crashed: bool = false,
    earned: u32 = 0,
    tip: u32 = 0,
    multiplier: u32 = 1,
};

pub const Achievement = enum {
    first_delivery,
    combo_3,
    combo_6,
    safe_3,
    safe_7,
    safe_15,
    wrong_way_10,
    speedster,
    rich,
    marathon,
};

player: Car,
passenger: ?Passenger,

/// Delivered fares (kept as `pickups` for compatibility with old callers).
pickups: u32,
money: u32,
combo: u32,
best_combo: u32,
expired_count: u32,

deliveries_since_crash: u32,
wrong_way_time: f32,

achievement_mask: u64,
achievement_popup: ?Achievement,
achievement_timer: f32,

respawn_timer: f32,
hint_timer: f32,
crash_flash: f32,
pickup_flash: f32,
crash_cooldown: f32,

last_event: EventKind,
event_timer: f32,
event_amount: u32,
event_pos: rl.Vector2,

agents: [c.TARGET_AGENT_COUNT]Agent,
spawn_timers: [c.TARGET_AGENT_COUNT]f32,
agent_waiting: [c.TARGET_AGENT_COUNT]bool,

portal_timers: [c.MAX_NODES]f32,
portal_next_lane: [c.MAX_NODES]i8,

pub fn init(map: *const Map) Self {
    return initInternal(map, false);
}

/// Build the game without loading textures, for `--sim` and tests.
pub fn initHeadless(map: *const Map) Self {
    return initInternal(map, true);
}

fn initInternal(map: *const Map, headless: bool) Self {
    const init_node = &map.nodes.items[0];

    const player = if (headless) Car.initHeadless(init_node) else Car.init(init_node);

    var agents: [c.TARGET_AGENT_COUNT]Agent = undefined;
    var spawn_timers: [c.TARGET_AGENT_COUNT]f32 = undefined;

    for (0..c.TARGET_AGENT_COUNT) |idx| {
        agents[idx] = if (headless) Agent.initHeadless(map) else Agent.init(map);
        const delay: f32 = @floatFromInt(idx);
        spawn_timers[idx] = delay * c.AGENT_SPAWN_INTERVAL;
    }

    const agent_waiting: [c.TARGET_AGENT_COUNT]bool = .{false} ** c.TARGET_AGENT_COUNT;

    const portal_timers: [c.MAX_NODES]f32 = .{0} ** c.MAX_NODES;
    const portal_next_lane: [c.MAX_NODES]i8 = .{1} ** c.MAX_NODES;

    return .{
        .player = player,
        .passenger = Passenger.init(map),
        .pickups = 0,
        .money = 0,
        .combo = 0,
        .best_combo = 0,
        .expired_count = 0,
        .deliveries_since_crash = 0,
        .wrong_way_time = 0,
        .achievement_mask = 0,
        .achievement_popup = null,
        .achievement_timer = 0,
        .respawn_timer = 0,
        .hint_timer = c.HINT_DURATION,
        .crash_flash = 0,
        .pickup_flash = 0,
        .crash_cooldown = 0,
        .last_event = .none,
        .event_timer = 0,
        .event_amount = 0,
        .event_pos = rl.Vector2Zero(),
        .agents = agents,
        .spawn_timers = spawn_timers,
        .agent_waiting = agent_waiting,
        .portal_timers = portal_timers,
        .portal_next_lane = portal_next_lane,
    };
}

pub fn deinit(self: *Self) void {
    self.player.deinit();
    for (&self.agents) |*agent| agent.car.deinit();
}

pub fn update(self: *Self, camera: *rl.Camera2D, map: *const Map) Step {
    const dt = rl.GetFrameTime();
    const result = self.step(dt, getPlayerInput(), map);
    self.updateCamera(camera);
    return result;
}

/// Advance the world by `dt` with an explicit input. This never reads the
/// keyboard, so a bot, a replay, or a test can drive the exact same logic.
pub fn step(self: *Self, dt: f32, input: KeyInput, map: *const Map) Step {
    var result = Step{};

    self.crash_cooldown = @max(0, self.crash_cooldown - dt);
    self.crash_flash = @max(0, self.crash_flash - dt);
    self.pickup_flash = @max(0, self.pickup_flash - dt);
    self.hint_timer = @max(0, self.hint_timer - dt);
    self.achievement_timer = @max(0, self.achievement_timer - dt);
    if (self.achievement_timer == 0) self.achievement_popup = null;
    if (self.event_timer > 0) {
        self.event_timer = @max(0, self.event_timer - dt);
        if (self.event_timer == 0) self.last_event = .none;
    }

    self.player.update(dt, map, input);

    if (self.player.lane_index < 0 and self.player.speed > 20.0) {
        self.wrong_way_time += dt;
    } else {
        self.wrong_way_time = 0;
    }

    // Decrement portal reservations.
    for (0..c.MAX_NODES) |idx| {
        self.portal_timers[idx] = @max(0, self.portal_timers[idx] - dt);
    }

    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (self.agent_waiting[idx]) continue;
        if (self.spawn_timers[idx] > 0) {
            self.spawn_timers[idx] -= dt;
            continue;
        }
        var agent = &self.agents[idx];
        agent.update(dt, map, &self.agents, idx, &self.player);
        if (agent.reset_pending) {
            self.agent_waiting[idx] = true;
        }
    }

    const passenger_result = self.updatePassenger(dt);
    result.picked_up = passenger_result.picked_up;
    result.delivered = passenger_result.delivered;
    result.expired = passenger_result.expired;
    result.earned = passenger_result.earned;
    result.tip = passenger_result.tip;
    result.multiplier = passenger_result.multiplier;

    self.resolveCollisions(&result);

    self.updateRespawn(dt, map);

    self.releaseWaitingAgents(dt, map);

    if (self.checkAchievements()) |ach| {
        self.achievement_popup = ach;
        self.achievement_timer = 3.0;
    }

    return result;
}

fn updatePassenger(self: *Self, dt: f32) Step {
    var result = Step{};

    if (self.passenger) |*passenger| {
        switch (passenger.state) {
            .waiting => {
                passenger.patience = @max(0, passenger.patience - dt);
                if (rl.Vector2Distance(self.player.pos, passenger.start_pos) <= c.PASSENGER_PICKUP_DISTANCE) {
                    passenger.state = .in_car;
                    passenger.time_left = c.PASSENGER_DELIVERY_TIME;
                    passenger.time_max = c.PASSENGER_DELIVERY_TIME;
                    self.pickup_flash = c.PICKUP_FLASH_TIME;
                    result.picked_up = true;
                    self.setEvent(.pickup, 0, passenger.start_pos);
                } else if (passenger.patience <= 0) {
                    passenger.state = .expired;
                    self.combo = 0;
                    self.expired_count += 1;
                    self.respawn_timer = c.PASSENGER_RESPAWN_DELAY;
                    result.expired = true;
                    self.setEvent(.expired, 0, passenger.start_pos);
                }
            },
            .in_car => {
                passenger.time_left = @max(0, passenger.time_left - dt);

                const dist = rl.Vector2Distance(self.player.pos, passenger.end_pos);
                const slow_enough = self.player.speed <= c.PASSENGER_DROPOFF_MAX_SPEED;
                if (dist <= c.PASSENGER_DROPOFF_DISTANCE and slow_enough) {
                    const tip_ratio = if (passenger.time_max > 0)
                        passenger.time_left / passenger.time_max
                    else
                        0;
                    result.tip = @intFromFloat(@round(c.PASSENGER_TIP_MAX * tip_ratio));

                    self.combo += 1;
                    if (self.combo > self.best_combo) self.best_combo = self.combo;
                    result.multiplier = @min(1 + self.combo / c.COMBO_STEP, c.COMBO_MAX_MULT);
                    result.earned = (passenger.fare + result.tip) * result.multiplier;
                    self.money += result.earned;
                    self.pickups += 1;
                    self.deliveries_since_crash += 1;

                    passenger.state = .delivered;
                    self.respawn_timer = c.PASSENGER_RESPAWN_DELAY;
                    result.delivered = true;
                    self.setEvent(.delivered, result.earned, passenger.end_pos);
                } else if (passenger.time_left <= 0) {
                    passenger.state = .expired;
                    self.combo = 0;
                    self.expired_count += 1;
                    self.respawn_timer = c.PASSENGER_RESPAWN_DELAY;
                    result.expired = true;
                    self.setEvent(.expired, 0, passenger.end_pos);
                }
            },
            .delivered, .expired => {},
        }
    }

    return result;
}

fn updateRespawn(self: *Self, dt: f32, map: *const Map) void {
    const passenger = self.passenger orelse return;
    if (passenger.state != .delivered and passenger.state != .expired) return;

    self.respawn_timer -= dt;
    if (self.respawn_timer <= 0) {
        self.spawnPassenger(map);
    }
}

fn releaseWaitingAgents(self: *Self, dt: f32, map: *const Map) void {
    var released_this_step: [c.MAX_NODES]bool = .{false} ** c.MAX_NODES;

    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (!self.agent_waiting[idx]) continue;
        var agent = &self.agents[idx];
        if (!agent.reset_pending) {
            self.agent_waiting[idx] = false;
            self.spawn_timers[idx] = 0;
            continue;
        }

        agent.reset_wait_timer += dt;

        const start_idx = agent.start_node;
        if (start_idx >= map.nodes.items.len) continue;
        const node_pos = map.nodes.items[start_idx].pos;

        const force = agent.reset_wait_timer >= c.PORTAL_RELEASE_TIMEOUT;

        if (released_this_step[start_idx]) continue;

        const portal_ready = self.portal_timers[start_idx] <= 0;
        var clear = true;

        if (rl.Vector2Distance(self.player.pos, node_pos) <= c.PORTAL_CLEAR_DISTANCE) clear = false;
        if (self.player.curr_node == start_idx) clear = false;

        if (clear) {
            for (0..c.TARGET_AGENT_COUNT) |j| {
                if (j == idx) continue;
                if (self.agent_waiting[j]) continue;
                if (self.spawn_timers[j] > 0) continue;
                const other_pos = self.agents[j].car.pos;
                if (rl.Vector2Distance(other_pos, node_pos) <= c.PORTAL_CLEAR_DISTANCE) {
                    clear = false;
                    break;
                }
            }
        }

        const can_release = force or (portal_ready and clear);
        if (!can_release) continue;

        released_this_step[start_idx] = true;
        self.portal_timers[start_idx] = c.PORTAL_SPAWN_GAP;

        const lane: i8 = 1;

        const path_len = agent.path_len;
        if (path_len > 0) {
            if (agent.path[0]) |first| {
                if (first < map.nodes.items.len) {
                    const first_pos = map.nodes.items[first].pos;
                    const dx = first_pos.x - node_pos.x;
                    const dy = first_pos.y - node_pos.y;
                    const dir: Map.Direction = if (dy < 0) .up else if (dx > 0) .right else if (dy > 0) .down else .left;

                    agent.car.curr_node = start_idx;
                    agent.car.next_node = first;
                    agent.car.speed = 0;
                    agent.car.vel = rl.Vector2Zero();
                    agent.car.lane_index = lane;
                    agent.car.lane_offset = c.LANE_WIDTH;
                    agent.car.target_lane_offset = c.LANE_WIDTH;
                    agent.car.turn_t = null;
                    agent.car.flip_t = null;
                    agent.car.next_dir = null;
                    agent.car.next_dir_timer = 0;
                    agent.car.dodge_timer = 0;
                    agent.car.push_offset = rl.Vector2Zero();
                    agent.car.stun_timer = 0;

                    const dir_vec = c.BASE_VEC[@intFromEnum(dir)];
                    const offset = c.PORTAL_RELEASE_OFFSET;
                    // Spawn inside the portal (behind the node) so the agent
                    // emerges from the tunnel instead of appearing on top of it.
                    agent.car.pos = .{
                        .x = node_pos.x - dir_vec.x * offset,
                        .y = node_pos.y - dir_vec.y * offset,
                    };

                    agent.car.face(dir);
                }
            }
        } else {
            agent.car.pos = node_pos;
            agent.car.curr_node = start_idx;
            agent.car.next_node = null;
            agent.car.speed = 0;
            agent.car.vel = rl.Vector2Zero();
            agent.car.lane_index = lane;
            agent.car.lane_offset = c.LANE_WIDTH;
            agent.car.target_lane_offset = c.LANE_WIDTH;
        }

        agent.path_idx = 0;
        agent.yield_timer = 0;
        agent.yield_target = null;
        agent.reset_pending = false;
        agent.reset_wait_timer = 0;

        self.agent_waiting[idx] = false;
        self.spawn_timers[idx] = 0;
    }
}

/// Push overlapping cars apart and apply the crash response.
///
/// Every overlap is separated on every frame, but the crash event (with its
/// speed loss and the stun) is only raised when the crash cooldown allows
/// it. Otherwise a single crash would emit an event on every frame.
fn resolveCollisions(self: *Self, result: *Step) void {
    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (self.agent_waiting[idx] or self.spawn_timers[idx] > 0) continue;
        self.resolvePair(&self.player, &self.agents[idx].car, true, result);
    }

    for (0..c.TARGET_AGENT_COUNT) |i| {
        if (self.agent_waiting[i] or self.spawn_timers[i] > 0) continue;
        for (i + 1..c.TARGET_AGENT_COUNT) |j| {
            if (self.agent_waiting[j] or self.spawn_timers[j] > 0) continue;
            self.resolvePair(&self.agents[i].car, &self.agents[j].car, false, result);
        }
    }
}

fn resolvePair(self: *Self, a: *Car, b: *Car, a_is_player: bool, result: *Step) void {
    const manifold = a.collidesWith(b) orelse return;

    // Contact thinner than the slop is ignored. Cars that merely touch must
    // not bump or crash on every frame.
    const push_depth = manifold.depth - c.SEPARATION_SLOP;
    if (push_depth <= 0) return;

    // Push each car apart by half the minimum translation, then let the push
    // offset decay in Car.update. This keeps `pos` (the logical path) intact.
    const half_push = rl.Vector2Scale(manifold.normal, push_depth / 2.0);
    a.applyPush(rl.Vector2Negate(half_push));
    b.applyPush(half_push);

    // Cars parked at the exact same node/position are an intentional spawn
    // overlap: they are pushed apart, but that is not a crash.
    if (a.isSameSpot(b)) return;

    if (a_is_player) {
        // Keep separating during the cooldown, but do not emit a crash on
        // every frame.
        if (self.crash_cooldown > 0) return;

        self.crash_cooldown = c.CRASH_COOLDOWN;
        self.crash_flash = c.CRASH_FLASH_TIME;
        result.crashed = true;
        if (self.last_event == .none) {
            self.setEvent(.crash, 0, self.player.visualPos());
        }

        self.combo = 0;
        self.deliveries_since_crash = 0;
        if (self.money >= c.CRASH_MONEY_PENALTY) {
            self.money -= c.CRASH_MONEY_PENALTY;
        } else {
            self.money = 0;
        }
        if (self.passenger) |*passenger| {
            if (passenger.state == .in_car) {
                passenger.time_left = @max(0, passenger.time_left - c.CRASH_TIME_PENALTY);
            } else if (passenger.state == .waiting) {
                passenger.patience = @max(0, passenger.patience - c.CRASH_TIME_PENALTY / 2.0);
            }
        }

        applyCrash(a, c.CRASH_SPEED_LOSS);
        applyCrash(b, c.CRASH_OTHER_SPEED_LOSS);
        return;
    }

    // Agent vs agent: bleed a little speed only when the cars are actually
    // closing. A long, shallow contact is separated by the push alone;
    // draining speed every frame would stall the traffic.
    if (rl.Vector2DotProduct(rl.Vector2Subtract(a.vel, b.vel), manifold.normal) > 0) {
        applyBump(a);
        applyBump(b);
    }
}

/// The crash response: the car loses speed and is stunned for a moment, so a
/// crash feels like a hit and not like a number change.
fn applyCrash(car: *Car, speed_loss: f32) void {
    car.speed *= speed_loss;
    car.vel = rl.Vector2Scale(car.vel, speed_loss);
    car.stun_timer = c.CRASH_STUN_TIME;
}

/// A light bump between two agents. They keep most of their speed, the
/// traffic must not come to a stop because two cars brushed each other.
fn applyBump(car: *Car) void {
    car.speed *= c.BUMP_SPEED_LOSS;
    car.vel = rl.Vector2Scale(car.vel, c.BUMP_SPEED_LOSS);
}

fn hasAchievement(self: *const Self, ach: Achievement) bool {
    return (self.achievement_mask & (@as(u64, 1) << @intFromEnum(ach))) != 0;
}

pub fn achievementReward(ach: Achievement) u32 {
    return switch (ach) {
        .first_delivery => 25,
        .combo_3 => 40,
        .combo_6 => 80,
        .safe_3 => 50,
        .safe_7 => 100,
        .safe_15 => 250,
        .wrong_way_10 => 75,
        .speedster => 60,
        .rich => 200,
        .marathon => 500,
    };
}

fn checkAchievements(self: *Self) ?Achievement {
    const checks = [_]struct { ach: Achievement, ok: bool }{
        .{ .ach = .first_delivery, .ok = self.pickups >= 1 },
        .{ .ach = .combo_3, .ok = self.combo >= 3 },
        .{ .ach = .combo_6, .ok = self.combo >= 6 },
        .{ .ach = .safe_3, .ok = self.deliveries_since_crash >= 3 },
        .{ .ach = .safe_7, .ok = self.deliveries_since_crash >= 7 },
        .{ .ach = .safe_15, .ok = self.deliveries_since_crash >= 15 },
        .{ .ach = .wrong_way_10, .ok = self.wrong_way_time >= c.WRONG_WAY_ACHIEVEMENT_TIME },
        .{ .ach = .speedster, .ok = self.player.speed >= c.MAX_SPEED - 1.0 },
        .{ .ach = .rich, .ok = self.money >= 1000 },
        .{ .ach = .marathon, .ok = self.pickups >= 25 },
    };

    var newly: ?Achievement = null;
    for (checks) |check| {
        if (!self.hasAchievement(check.ach) and check.ok) {
            self.achievement_mask |= @as(u64, 1) << @intFromEnum(check.ach);
            self.money += achievementReward(check.ach);
            newly = check.ach;
        }
    }
    return newly;
}

fn setEvent(self: *Self, kind: EventKind, amount: u32, pos: rl.Vector2) void {
    self.last_event = kind;
    self.event_timer = 1.4;
    self.event_amount = amount;
    self.event_pos = pos;
}

pub fn updateCamera(self: *Self, camera: *rl.Camera2D) void {
    camera.zoom = 1.0;

    // Visible world half-extents are offset-aware (matching Editor.drawWorld):
    // main.zig sets offset = SCREEN/2 + TILE_SIZE, so a plain SCREEN/2 clamp
    // would let a 32px black strip of void show past the left/top world edge.
    const view_left = camera.offset.x / camera.zoom;
    const view_top = camera.offset.y / camera.zoom;
    const view_right = (c.SCREEN_WIDTH - camera.offset.x) / camera.zoom;
    const view_bottom = (c.SCREEN_HEIGHT - camera.offset.y) / camera.zoom;

    // Follow where the car is actually drawn, not the logical centerline `pos`:
    // during a turn the lane offset is baked into `pos`, so tracking `pos` gives
    // the camera a full LANE_WIDTH lateral kick at the start and end of every turn.
    const player_visual = self.player.visualPos();
    camera.target = rl.Vector2Lerp(
        camera.target,
        .{
            .x = math.clamp(player_visual.x, view_left, c.WORLD_WIDTH - view_right),
            .y = math.clamp(player_visual.y, view_top, c.WORLD_HEIGHT - view_bottom),
        },
        0.2,
    );
}

pub fn draw(self: *Self, camera: *rl.Camera2D, map: *Map, is_debug: bool) void {
    // Render the static layer before camera mode: BeginMode2D would bake the
    // camera transform into the cached texture.
    map.prepareStatic();

    rl.BeginMode2D(camera.*);
    {
        map.drawStatic();

        if (self.passenger) |*passenger| passenger.draw();

        if (is_debug) {
            map.drawDebug();
        }

        const player_alpha: f32 = if (self.isOverlappingWithAny(&self.player)) 0.5 else 1.0;
        self.player.draw(player_alpha);

        for (0..c.TARGET_AGENT_COUNT) |idx| {
            if (!self.agent_waiting[idx] and self.spawn_timers[idx] <= 0) {
                const alpha: f32 = if (self.isOverlappingWithAny(&self.agents[idx].car)) 0.5 else 1.0;
                self.agents[idx].car.draw(alpha);
            }
        }

        // Prolong the road under each portal tunnel so released agents have
        // space to accelerate before emerging.
        for (map.start_nodes.keys()) |node_idx| {
            if (node_idx >= map.nodes.items.len) continue;
            const node = map.nodes.items[node_idx];
            const pos = node.pos;

            var outgoing_idx2: usize = 0;
            var has_outgoing2 = false;
            for (node.edges, 0..) |edge, dir_idx| {
                if (edge != null) {
                    outgoing_idx2 = dir_idx;
                    has_outgoing2 = true;
                    break;
                }
            }
            if (!has_outgoing2) continue;
            const incoming_idx2 = (outgoing_idx2 + 2) % 4;

            const road_w2: f32 = 3.0 * c.TILE_SIZE;
            const road_len2: f32 = 320.0;
            var rx2: f32 = 0;
            var ry2: f32 = 0;
            var rw2: f32 = 0;
            var rh2: f32 = 0;
            switch (incoming_idx2) {
                0 => { rx2 = pos.x - road_w2 / 2.0; ry2 = pos.y - road_len2; rw2 = road_w2; rh2 = road_len2; },
                1 => { rx2 = pos.x; ry2 = pos.y - road_w2 / 2.0; rw2 = road_len2; rh2 = road_w2; },
                2 => { rx2 = pos.x - road_w2 / 2.0; ry2 = pos.y; rw2 = road_w2; rh2 = road_len2; },
                3 => { rx2 = pos.x - road_len2; ry2 = pos.y - road_w2 / 2.0; rw2 = road_len2; rh2 = road_w2; },
                else => {},
            }
            rl.DrawRectangleRec(.{ .x = rx2, .y = ry2, .width = rw2, .height = rh2 }, rl.Color{ .r = 80, .g = 80, .b = 80, .a = 255 });
        }

        for (map.start_nodes.keys()) |node_idx| {
            if (node_idx >= map.nodes.items.len) continue;
            const node = map.nodes.items[node_idx];
            const pos = node.pos;

            // Find the outgoing direction, then extend the tunnel the opposite way.
            var outgoing_idx: usize = 0;
            var has_outgoing = false;
            for (node.edges, 0..) |edge, dir_idx| {
                if (edge != null) {
                    outgoing_idx = dir_idx;
                    has_outgoing = true;
                    break;
                }
            }
            if (!has_outgoing) continue;
            const incoming_idx = (outgoing_idx + 2) % 4;

            const road_w: f32 = 3.0 * c.TILE_SIZE;
            const tunnel_len: f32 = 2000.0;
            var rx: f32 = 0;
            var ry: f32 = 0;
            var rw: f32 = 0;
            var rh: f32 = 0;
            switch (incoming_idx) {
                0 => { // up: tunnel extends upward (negative Y)
                    rx = pos.x - road_w / 2.0;
                    ry = pos.y - tunnel_len;
                    rw = road_w;
                    rh = tunnel_len;
                },
                1 => { // right
                    rx = pos.x;
                    ry = pos.y - road_w / 2.0;
                    rw = tunnel_len;
                    rh = road_w;
                },
                2 => { // down
                    rx = pos.x - road_w / 2.0;
                    ry = pos.y;
                    rw = road_w;
                    rh = tunnel_len;
                },
                3 => { // left
                    rx = pos.x - tunnel_len;
                    ry = pos.y - road_w / 2.0;
                    rw = tunnel_len;
                    rh = road_w;
                },
                else => {},
            }

            rl.DrawRectangleRounded(
                .{ .x = rx, .y = ry, .width = rw, .height = rh },
                0.05,
                8,
                rl.Color{ .r = 18, .g = 18, .b = 22, .a = 245 },
            );
            // Inner opening, inset on the cross-axis only so the tunnel reads
            // as a tube rather than a solid slab.
            const inset: f32 = 6.0;
            rl.DrawRectangle(
                @intFromFloat(rx + if (incoming_idx == 0 or incoming_idx == 2) inset else 0),
                @intFromFloat(ry + if (incoming_idx == 0 or incoming_idx == 2) 0 else inset),
                @intFromFloat(if (incoming_idx == 0 or incoming_idx == 2) road_w - 2.0 * inset else tunnel_len),
                @intFromFloat(if (incoming_idx == 0 or incoming_idx == 2) tunnel_len else road_w - 2.0 * inset),
                rl.Color{ .r = 34, .g = 34, .b = 40, .a = 255 },
            );
        }

        if (is_debug) {
            if (self.player.next_node) |target_index| {
                const target = map.nodes.items[target_index];
                rl.DrawCircleV(target.pos, 10, rl.RED);
            }
        }

        Hud.drawWorld(self, camera.*);
    }
    rl.EndMode2D();

    Hud.drawScreen(self, map, camera.*, is_debug);
}

fn clampToScreen(pos: rl.Vector2, padding: f32) rl.Vector2 {
    const w: f32 = @floatFromInt(rl.GetScreenWidth());
    const h: f32 = @floatFromInt(rl.GetScreenHeight());
    return .{
        .x = math.clamp(pos.x, 2 * padding, w - 2 * padding),
        .y = math.clamp(pos.y, 2 * padding, h - 2 * padding),
    };
}

fn isOnScreen(screen_pos: rl.Vector2) bool {
    const w: f32 = @floatFromInt(rl.GetScreenWidth());
    const h: f32 = @floatFromInt(rl.GetScreenHeight());
    return screen_pos.x >= 0 and screen_pos.x <= w and
        screen_pos.y >= 0 and screen_pos.y <= h;
}

fn isOverlappingWithAny(self: *const Self, car: *const Car) bool {
    if (car != &self.player and !car.isSameSpot(&self.player)) {
        if (car.collidesWith(&self.player) != null) {
            return true;
        }
    }

    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (self.agent_waiting[idx] or self.spawn_timers[idx] > 0) continue;

        const other = &self.agents[idx].car;
        if (other == car) continue;
        if (car.isSameSpot(other)) continue;

        if (car.collidesWith(other) != null) {
            return true;
        }
    }

    return false;
}

pub fn spawnPassenger(self: *Self, map: *const Map) void {
    self.passenger = Passenger.init(map);
    self.respawn_timer = 0;
}

fn getPlayerInput() Game.KeyInput {
    const dir = if (rl.IsKeyDown(rl.KEY_W) or rl.IsKeyDown(rl.KEY_UP))
        Direction.up
    else if (rl.IsKeyDown(rl.KEY_S) or rl.IsKeyDown(rl.KEY_DOWN))
        Direction.down
    else if (rl.IsKeyDown(rl.KEY_A) or rl.IsKeyDown(rl.KEY_LEFT))
        Direction.left
    else if (rl.IsKeyDown(rl.KEY_D) or rl.IsKeyDown(rl.KEY_RIGHT))
        Direction.right
    else
        null;

    const KEY_CTRL = rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL);
    const KEY_SHIFT = rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT);

    return .{
        .dir = dir,
        .brake = rl.IsKeyDown(rl.KEY_SPACE),
        .dodge = false,
        // Plain P only: Ctrl+Shift+P is the spawn-passenger shortcut.
        .lane_toggle = rl.IsKeyPressed(rl.KEY_TAB) and !KEY_CTRL and !KEY_SHIFT,
    };
}
