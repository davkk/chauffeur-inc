const std = @import("std");
const rl = @import("raylib.zig").rl;
const c = @import("constants.zig");

const Game = @import("Game.zig");
const Map = @import("Map.zig");
const Passenger = @import("Passenger.zig");

const Self = @This();
const Direction = Map.Direction;

/// Rebuild the route at least this often, even when the objective did not
/// change. Safety net so that a stale route can never trap the bot.
const REPLAN_PERIOD: u32 = 30;

/// Braking deceleration of the car (see `Car.init`). Only used to predict the
/// stopping distance, this is not a new gameplay constant.
const BRAKE_DECEL: f32 = 800.0;

/// "No route" marker for the BFS tables.
const UNREACHABLE: usize = std.math.maxInt(usize);

/// Planned route as node ids. `path[0]` is the first node after the node the
/// route was planned from.
path: [c.MAX_NODES]usize,
path_len: usize,
path_idx: usize,

/// The objective the stored route belongs to. A different passenger state or a
/// different street invalidates the route.
plan_state: ?Passenger.State,
plan_from: usize,
plan_to: usize,

/// Set when a route rebuild was requested while the car was not able to
/// follow a new route yet (mid turn).
plan_dirty: bool,

/// Calls since the last route was built.
frames_since_plan: u32,

/// BFS scratch buffers. Fixed size, the bot never allocates.
bfs_dist: [c.MAX_NODES]usize,
bfs_parent: [c.MAX_NODES]usize,

/// Result of following the route: the direction to steer to and whether the
/// route turned out to be stale.
const Steer = struct { dir: ?Direction, broken: bool };

/// A simple driver that follows the road graph to the current passenger
/// objective. Used by `--sim`, `--bot`, and screenshot capture.
pub fn init() Self {
    return .{
        .path = [_]usize{0} ** c.MAX_NODES,
        .path_len = 0,
        .path_idx = 0,
        .plan_state = null,
        .plan_from = 0,
        .plan_to = 0,
        .plan_dirty = true,
        .frames_since_plan = 0,
        .bfs_dist = [_]usize{0} ** c.MAX_NODES,
        .bfs_parent = [_]usize{0} ** c.MAX_NODES,
    };
}

pub fn reset(self: *Self) void {
    self.path_len = 0;
    self.path_idx = 0;
    self.plan_state = null;
    self.plan_from = 0;
    self.plan_to = 0;
    self.plan_dirty = true;
    self.frames_since_plan = 0;
}

pub fn nextInput(self: *Self, game: *const Game, map: *const Map) Game.KeyInput {
    const player = &game.player;

    const passenger = game.passenger orelse return Game.KeyInput.init(null, false, false);
    switch (passenger.state) {
        .delivered, .expired => return Game.KeyInput.init(null, false, false),
        .waiting, .in_car => {},
    }

    const stop = passenger.state == .in_car;
    const target_pos = if (stop) passenger.end_pos else passenger.start_pos;
    const street = if (stop) passenger.end_edge else passenger.start_edge;

    // A street is undirected, so its endpoints are always compared in order.
    const street_a = @min(street.from, street.to);
    const street_b = @max(street.from, street.to);

    self.frames_since_plan +%= 1;

    const target_changed = self.plan_state == null or
        self.plan_state.? != passenger.state or
        self.plan_from != street_a or
        self.plan_to != street_b;
    const route_used_up = self.path_idx >= self.path_len;
    const route_stale = self.frames_since_plan >= REPLAN_PERIOD;

    // While the turn arc runs the exit direction is already committed to the
    // car. A new route could pick a different exit and make the car turn the
    // wrong way, so the rebuild waits until the car is straight again.
    const turning = player.turn_t != null;

    if (self.plan_dirty or target_changed or route_used_up or route_stale) {
        if (turning) {
            self.plan_dirty = true;
        } else {
            self.buildRoute(game, map, street_a, street_b, passenger.state, target_pos);
        }
    }

    var dir: ?Direction = null;
    if (turning) {
        // Keep the committed exit direction. The car drops it when the turn
        // finishes, so the route can be rebuilt cleanly afterwards.
        dir = player.turn_exit;
    } else {
        const steer = self.followRoute(game, map);
        dir = steer.dir;
        if (steer.broken) {
            // The car is not on the planned street any more: rebuild the route
            // and drive straight for this frame.
            self.buildRoute(game, map, street_a, street_b, passenger.state, target_pos);
            dir = null;
        }
    }

    return Game.KeyInput.init(dir, shouldBrake(game, target_pos, stop), false);
}

/// Rebuild the route to the objective. The route ends on the far end of the
/// objective street, because the objective itself sits between the two
/// endpoints of that street.
fn buildRoute(
    self: *Self,
    game: *const Game,
    map: *const Map,
    street_a: usize,
    street_b: usize,
    state: Passenger.State,
    target_pos: rl.Vector2,
) void {
    self.plan_state = state;
    self.plan_from = street_a;
    self.plan_to = street_b;
    self.plan_dirty = false;
    self.frames_since_plan = 0;
    self.path_len = 0;
    self.path_idx = 0;

    // The objective is on the street the car drives on right now and still
    // ahead of it: no route needed, the car just keeps going straight.
    if (objectiveAheadOnCurrentStreet(game, map, street_a, street_b, target_pos)) return;

    const player = &game.player;
    var start: ?usize = player.next_node;
    if (start == null) start = player.curr_node;
    const start_node = start orelse return;
    if (start_node >= map.nodes.items.len) return;
    if (street_a >= map.nodes.items.len or street_b >= map.nodes.items.len) return;

    self.bfs(map, start_node);

    const dist_a = self.bfs_dist[street_a];
    const dist_b = self.bfs_dist[street_b];
    if (dist_a == UNREACHABLE and dist_b == UNREACHABLE) return;

    // Drive to the end of the street that is closer and traverse the whole
    // street afterwards: the objective sits between the two endpoints.
    const near: usize = if (dist_b < dist_a) street_b else street_a;
    const far: usize = if (near == street_a) street_b else street_a;

    // Rebuild start -> near from the BFS parents.
    var scratch: [c.MAX_NODES]usize = undefined;
    var len: usize = 0;
    var node = near;
    while (node != start_node and len < scratch.len) {
        scratch[len] = node;
        len += 1;
        const parent = self.bfs_parent[node];
        if (parent == UNREACHABLE or parent == node) break;
        node = parent;
    }

    var i: usize = 0;
    while (i < len) : (i += 1) {
        self.path[i] = scratch[len - 1 - i];
    }
    self.path_len = len;

    // The far end of the street completes the traversal. When the car already
    // sits on `near` the path to it is empty and this hop is all that is left.
    if (self.path_len < self.path.len and areNeighbours(map, near, far)) {
        self.path[self.path_len] = far;
        self.path_len += 1;
    }
}

/// Breadth first search over the road graph. Fills the distance and parent
/// tables, no allocation.
fn bfs(self: *Self, map: *const Map, start: usize) void {
    @memset(self.bfs_dist[0..], UNREACHABLE);
    @memset(self.bfs_parent[0..], UNREACHABLE);

    var queue: [c.MAX_NODES]usize = undefined;
    var head: usize = 0;
    var tail: usize = 0;

    self.bfs_dist[start] = 0;
    self.bfs_parent[start] = start;
    queue[tail] = start;
    tail += 1;

    while (head < tail) {
        const curr = queue[head];
        head += 1;
        if (curr >= map.nodes.items.len) continue;

        for (map.nodes.items[curr].edges) |maybe_edge| {
            const edge = maybe_edge orelse continue;
            if (edge >= map.nodes.items.len) continue;
            if (self.bfs_dist[edge] != UNREACHABLE) continue;

            self.bfs_dist[edge] = self.bfs_dist[curr] + 1;
            self.bfs_parent[edge] = curr;
            if (tail >= queue.len) break;
            queue[tail] = edge;
            tail += 1;
        }
    }
}

/// Steer along the stored route.
fn followRoute(self: *Self, game: *const Game, map: *const Map) Steer {
    const player = &game.player;

    // Drop entries the car has already passed.
    if (player.curr_node) |curr| {
        while (self.path_idx < self.path_len and self.path[self.path_idx] == curr) {
            self.path_idx += 1;
        }
    }

    if (self.path_idx >= self.path_len) return .{ .dir = null, .broken = false };

    if (player.next_node) |next_node| {
        // The turn happens at next_node and is already committed, so the route
        // continues from there.
        if (self.path[self.path_idx] == next_node) self.path_idx += 1;
        if (self.path_idx >= self.path_len) return .{ .dir = null, .broken = false };
        const dir = directionBetween(map, next_node, self.path[self.path_idx]);
        return .{ .dir = dir, .broken = dir == null };
    }

    const curr_node = player.curr_node orelse return .{ .dir = null, .broken = false };
    const dir = directionBetween(map, curr_node, self.path[self.path_idx]);
    return .{ .dir = dir, .broken = dir == null };
}

/// Braking for the drop-off. A pickup is never braked for: the passenger is
/// picked up when the car drives past.
fn shouldBrake(game: *const Game, target_pos: rl.Vector2, stop: bool) bool {
    if (!stop) return false;

    const player = &game.player;
    const dist = rl.Vector2Distance(player.pos, target_pos);

    if (dist <= c.PASSENGER_DROPOFF_DISTANCE + 10) {
        // Inside the drop-off zone: brake down to a crawl. Below that speed the
        // brake is released so that a small overshoot can be undone.
        return player.speed > 4;
    }

    // Outside the zone: brake early enough to still stop in time.
    const stop_distance = player.speed * player.speed / (2 * BRAKE_DECEL) + 25;
    return dist <= stop_distance;
}

/// Direction of the street that leads from `from` to `to`, or null when the
/// two nodes are not connected.
fn directionBetween(map: *const Map, from: usize, to: usize) ?Direction {
    if (from >= map.nodes.items.len or to >= map.nodes.items.len) return null;

    const src = map.nodes.items[from];
    const dst = map.nodes.items[to];

    const dx = dst.pos.x - src.pos.x;
    const dy = dst.pos.y - src.pos.y;
    const dir: Direction = if (dx > 0) .right else if (dy > 0) .down else if (dx < 0) .left else if (dy < 0) .up else return null;

    // Only steer along a street that really exists.
    if (src.edges[@intFromEnum(dir)]) |edge| {
        if (edge == to) return dir;
    }

    // Fall back to the edge list: the graph is the authority for driving.
    for (src.edges, 0..) |maybe_edge, dir_idx| {
        if (maybe_edge) |edge| {
            if (edge == to) return @enumFromInt(dir_idx);
        }
    }
    return null;
}

/// True when the objective is on the street the car drives on right now and is
/// still ahead of the car.
fn objectiveAheadOnCurrentStreet(
    game: *const Game,
    map: *const Map,
    street_a: usize,
    street_b: usize,
    target_pos: rl.Vector2,
) bool {
    const player = &game.player;
    const curr = player.curr_node orelse return false;
    const next = player.next_node orelse return false;
    if (curr >= map.nodes.items.len or next >= map.nodes.items.len) return false;

    const same_street = (curr == street_a and next == street_b) or
        (curr == street_b and next == street_a);
    if (!same_street) return false;

    // "Ahead" means further along the edge the car is driving.
    const travel = rl.Vector2Subtract(map.nodes.items[next].pos, map.nodes.items[curr].pos);
    const to_target = rl.Vector2Subtract(target_pos, player.pos);
    return rl.Vector2DotProduct(travel, to_target) > 0;
}

fn areNeighbours(map: *const Map, a: usize, b: usize) bool {
    if (a >= map.nodes.items.len or b >= map.nodes.items.len) return false;
    for (map.nodes.items[a].edges) |maybe_edge| {
        if (maybe_edge) |edge| {
            if (edge == b) return true;
        }
    }
    return false;
}
