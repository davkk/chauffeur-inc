const std = @import("std");

const raylib = @import("raylib.zig");
const rl = raylib.rl;
const c = @import("constants.zig");

const Map = @import("Map.zig");
const Game = @import("Game.zig");
const Autopilot = @import("Autopilot.zig");
const Car = @import("Car.zig");

const DT: f32 = 1.0 / @as(f32, @floatFromInt(c.TARGET_FPS));

fn finite(value: f32) bool {
    return !std.math.isNan(value) and !std.math.isInf(value);
}

fn finitePos(pos: rl.Vector2) bool {
    return finite(pos.x) and finite(pos.y);
}

fn inWorld(pos: rl.Vector2) bool {
    return pos.x >= -64 and pos.x <= c.WORLD_WIDTH + 64 and
        pos.y >= -64 and pos.y <= c.WORLD_HEIGHT + 64;
}

test "headless map has a connected, valid road graph" {
    var map = try Map.initHeadless(std.testing.allocator);
    defer map.deinit();

    try std.testing.expect(map.nodes.items.len >= 10);
    try std.testing.expect(map.edges.items.len >= map.nodes.items.len);

    for (map.edges.items) |edge| {
        try std.testing.expect(edge.from < map.nodes.items.len);
        try std.testing.expect(edge.to < map.nodes.items.len);
        try std.testing.expect(edge.from != edge.to);
    }

    // Every node on the graph must be reachable from node 0, otherwise the
    // autopilot can plan a fare it can never drive to.
    var seen = [_]bool{false} ** c.MAX_NODES;
    var queue = [_]usize{0} ** c.MAX_NODES;
    var head: usize = 0;
    var tail: usize = 1;
    seen[0] = true;
    while (head < tail) : (head += 1) {
        const node_index = queue[head];
        for (map.nodes.items[node_index].edges) |maybe_neighbor| {
            const other = maybe_neighbor orelse continue;
            if (seen[other]) continue;
            seen[other] = true;
            queue[tail] = other;
            tail += 1;
        }
    }
    for (map.nodes.items, 0..) |node, index| {
        if (node.active) try std.testing.expect(seen[index]);
    }
}

test "idle game stays finite and inside the world" {
    raylib.seedRandom(7);

    var map = try Map.initHeadless(std.testing.allocator);
    defer map.deinit();

    var game = Game.initHeadless(&map);
    defer game.deinit();

    var step: u32 = 0;
    while (step < 5 * c.TARGET_FPS) : (step += 1) {
        _ = game.step(DT, Game.KeyInput.init(null, false, false), &map);

        try std.testing.expect(finite(game.player.speed));
        try std.testing.expect(finitePos(game.player.pos));
        try std.testing.expect(inWorld(game.player.visualPos()));

        if (game.player.curr_node) |node| try std.testing.expect(node < map.nodes.items.len);
        if (game.player.next_node) |node| try std.testing.expect(node < map.nodes.items.len);

        for (game.agents) |agent| {
            try std.testing.expect(finite(agent.car.speed));
            try std.testing.expect(finitePos(agent.car.pos));
            if (agent.car.curr_node) |node| try std.testing.expect(node < map.nodes.items.len);
            if (agent.car.next_node) |node| try std.testing.expect(node < map.nodes.items.len);
        }
    }
}

fn overlapDepth(a: *const Car, b: *const Car) f32 {
    if (a.isSameSpot(b)) return 0;
    const manifold = a.collidesWith(b) orelse return 0;
    return manifold.depth;
}

test "overlapping cars separate and a crash costs speed" {
    raylib.seedRandom(3);

    var map = try Map.initHeadless(std.testing.allocator);
    defer map.deinit();

    var game = Game.initHeadless(&map);
    defer game.deinit();

    // Only the first agent is in the world, all others are still spawning.
    for (&game.spawn_timers) |*timer| timer.* = 1000.0;
    game.spawn_timers[0] = 0;

    const start = map.nodes.items[0].pos;
    game.player.pos = start;
    game.player.curr_node = 0;
    game.player.next_node = null;
    game.player.curr_dir = .right;
    game.player.angle = 90;
    game.player.speed = 100;
    game.player.vel = .{ .x = 100, .y = 0 };

    const agent = &game.agents[0].car;
    agent.pos = .{ .x = start.x + 8, .y = start.y };
    agent.curr_node = 0;
    agent.next_node = null;
    agent.curr_dir = .right;
    agent.angle = 90;
    agent.speed = 0;
    agent.vel = rl.Vector2Zero();

    // The two boxes overlap before the step.
    try std.testing.expect(overlapDepth(&game.player, agent) > c.SEPARATION_SLOP);

    const result = game.step(DT, Game.KeyInput.init(null, false, false), &map);

    try std.testing.expect(result.crashed);
    try std.testing.expect(game.player.speed < 100);
    try std.testing.expect(game.player.speed <= 100 * c.CRASH_SPEED_LOSS + 2.0);

    // The push separates the boxes, without moving the logical path state.
    const remaining = overlapDepth(&game.player, agent);
    try std.testing.expect(remaining <= c.SEPARATION_SLOP + 1.0);
}

test "long bot run has no persistent car overlap" {
    raylib.seedRandom(1);

    var map = try Map.initHeadless(std.testing.allocator);
    defer map.deinit();

    var game = Game.initHeadless(&map);
    defer game.deinit();

    var autopilot = Autopilot.init();

    const car_count = c.TARGET_AGENT_COUNT + 1;
    const overlap_tolerance: f32 = 2.0;
    const max_persistent_time: f32 = 1.0;

    // Index 0 is the player, index i + 1 is agent i. Timers are per pair, so a
    // pair that separates resets its clock and a new pair cannot inherit it.
    var persistent = [_][car_count]f32{.{0.0} ** car_count} ** car_count;
    var longest: f32 = 0;

    var step: u32 = 0;
    while (step < 30 * c.TARGET_FPS) : (step += 1) {
        _ = game.step(DT, autopilot.nextInput(&game, &map), &map);

        for (0..c.TARGET_AGENT_COUNT) |i| {
            if (game.spawn_timers[i] > 0) continue;

            const player_depth = overlapDepth(&game.player, &game.agents[i].car);
            updateOverlapTimer(&persistent, 0, i + 1, player_depth, overlap_tolerance, &longest);

            for (i + 1..c.TARGET_AGENT_COUNT) |j| {
                if (game.spawn_timers[j] > 0) continue;
                const depth = overlapDepth(&game.agents[i].car, &game.agents[j].car);
                updateOverlapTimer(&persistent, i + 1, j + 1, depth, overlap_tolerance, &longest);
            }
        }
    }

    try std.testing.expect(longest < max_persistent_time);

    // Traffic must keep flowing; a completely jammed pair would show up as
    // zero completed agent routes.
    var resets: u32 = 0;
    for (game.agents) |agent| resets += agent.resets;
    try std.testing.expect(resets > 0);
}

fn updateOverlapTimer(
    timers: *[c.TARGET_AGENT_COUNT + 1][c.TARGET_AGENT_COUNT + 1]f32,
    a: usize,
    b: usize,
    depth: f32,
    tolerance: f32,
    longest: *f32,
) void {
    if (depth > tolerance) {
        timers[a][b] += DT;
        longest.* = @max(longest.*, timers[a][b]);
    } else {
        timers[a][b] = 0;
    }
}

/// Drive straight through `through` and check that the car stays on its lane
/// centerline. A plain intersection is not a turn: the lane offset must not
/// change while crossing the node.
fn expectStraightLane(map: *const Map, from: usize, through: usize, dir: Map.Direction) !void {
    const node = map.nodes.items[through];
    const dir_num: usize = @intFromEnum(dir);
    const dir_vec = c.BASE_VEC[dir_num];
    const right = c.BASE_VEC[(dir_num + 1) % 4];

    var car = Car.initHeadless(&map.nodes.items[from]);
    car.curr_node = from;
    car.next_node = through;
    car.curr_dir = dir;
    car.next_dir = dir;
    car.angle = switch (dir) {
        .up => 0,
        .right => 90,
        .down => 180,
        .left => 270,
    };
    car.pos = rl.Vector2Subtract(node.pos, rl.Vector2Scale(dir_vec, c.TURN_RADIUS - 1.0));
    car.speed = 100;
    car.vel = rl.Vector2Scale(dir_vec, car.speed);
    car.lane_index = 1;
    car.lane_offset = c.LANE_WIDTH;
    car.target_lane_offset = c.LANE_WIDTH;

    var max_deviation: f32 = 0;
    var step: usize = 0;
    while (step < 90) : (step += 1) {
        car.update(DT, map, Game.KeyInput.init(null, false, false));

        const visual = car.visualPos();
        const delta = rl.Vector2Subtract(visual, node.pos);
        const along = rl.Vector2DotProduct(delta, dir_vec);
        const lateral = rl.Vector2DotProduct(delta, right);
        max_deviation = @max(max_deviation, @abs(lateral - c.LANE_WIDTH));

        if (along > 2.0 * c.TURN_RADIUS + c.LANE_WIDTH) break;
    }

    try std.testing.expect(max_deviation < 1.5);
}

test "straight intersections do not push cars sideways" {
    var map = try Map.initHeadless(std.testing.allocator);
    defer map.deinit();

    // One straight-through case in each direction.
    try expectStraightLane(&map, 7, 2, .right);
    try expectStraightLane(&map, 1, 4, .up);
    try expectStraightLane(&map, 12, 7, .down);
    try expectStraightLane(&map, 2, 7, .left);
}

test "autopilot completes a fare without unsafe inputs" {
    raylib.seedRandom(1);

    var map = try Map.initHeadless(std.testing.allocator);
    defer map.deinit();

    var game = Game.initHeadless(&map);
    defer game.deinit();

    var autopilot = Autopilot.init();
    var step: u32 = 0;
    while (step < 30 * c.TARGET_FPS) : (step += 1) {
        const input = autopilot.nextInput(&game, &map);
        try std.testing.expect(!input.dodge);

        _ = game.step(DT, input, &map);
        try std.testing.expect(finitePos(game.player.pos));
        try std.testing.expect(inWorld(game.player.visualPos()));
    }

    try std.testing.expect(game.pickups >= 1);
    try std.testing.expect(game.money > 0);
    try std.testing.expect(game.expired_count == 0);
}
