const std = @import("std");
const rand = @import("raylib.zig").rand;

const rl = @import("raylib.zig").rl;
const c = @import("constants.zig");

const KeyInput = @import("Game.zig").KeyInput;
const Car = @import("Car.zig");
const Map = @import("Map.zig");
const Direction = Map.Direction;

const Self = @This();

car: Car,

path: [c.MAX_NODES]?usize,
path_len: usize,
path_idx: usize,

start_node: usize,
end_node: usize,

yield_timer: f32,

pub fn init(map: *const Map) Self {
    const start_idx, const end_idx = pickRandomStartEnd(map);
    const start_node = &map.nodes.items[start_idx];

    var path: [c.MAX_NODES]?usize = .{null} ** c.MAX_NODES;
    const path_len = buildPath(&path, map, start_idx, end_idx);

    const car = Car.init(start_node);

    return .{
        .car = car,
        .start_node = start_idx,
        .end_node = end_idx,
        .path = path,
        .path_len = path_len,
        .path_idx = 0,
        .yield_timer = 0,
    };
}

pub fn update(self: *Self, dt: f32, map: *const Map, agents: []const Self, self_idx: usize, player: *const Car) void {
    const input = self.decideInput(dt, map, agents, self_idx, player);
    self.car.update(dt, map, input);

    if (self.isAtEnd()) {
        self.reset(map);
    }
}

fn findShortestPath(path: []?usize, map: *const Map, start: usize, end: usize) usize {
    var queue: [c.MAX_NODES]?usize = .{null} ** c.MAX_NODES;
    var head: usize = 0;
    var tail: usize = 0;

    var seen: [c.MAX_NODES]bool = .{false} ** c.MAX_NODES;
    var parents: [c.MAX_NODES]?usize = .{null} ** c.MAX_NODES;

    queue[tail] = start;
    tail += 1;
    seen[start] = true;

    while (head < tail) {
        const curr = queue[head] orelse break;
        head += 1;
        if (curr == end) break;
        for (map.nodes.items[curr].edges) |maybe_edge| {
            if (maybe_edge) |edge| {
                if (seen[edge]) continue;
                seen[edge] = true;
                parents[edge] = curr;
                queue[tail] = edge;
                tail += 1;
            }
        }
    }

    var curr_node: usize = end;
    var path_len: usize = 0;
    while (parents[curr_node]) |parent| {
        path[path_len] = curr_node;
        path_len += 1;
        curr_node = parent;
    }

    var idx: usize = 0;
    while (idx < path_len / 2) : (idx += 1) {
        std.mem.swap(?usize, &path[idx], &path[path_len - 1 - idx]);
    }

    return path_len;
}

fn buildPath(path: []?usize, map: *const Map, start: usize, end: usize) usize {
    const waypoint_count = rand().intRangeAtMost(usize, 2, 4);

    var total_len: usize = 0;
    var current = start;

    var segment_path: [c.MAX_NODES]?usize = .{null} ** c.MAX_NODES;

    for (0..waypoint_count) |_| {
        // TODO: we should not pick other start/end nodes as waypoints
        const waypoint = rand().intRangeLessThan(usize, 0, map.nodes.items.len);
        const seg_len = findShortestPath(&segment_path, map, current, waypoint);

        for (0..seg_len) |i| {
            if (total_len < path.len) {
                path[total_len] = segment_path[i];
                total_len += 1;
            }
        }
        current = waypoint;
    }

    const final_len = findShortestPath(&segment_path, map, current, end);
    for (0..final_len) |i| {
        if (total_len < path.len) {
            path[total_len] = segment_path[i];
            total_len += 1;
        }
    }

    return total_len;
}

fn decideInput(self: *Self, dt: f32, map: *const Map, agents: []const Self, self_idx: usize, player: *const Car) KeyInput {
    var should_brake = false;
    var should_dodge = false;

    const forward = c.BASE_VEC[@intFromEnum(self.car.curr_dir)];

    // Mid-block follow / head-on: OR-accumulate so player + agents don't clobber.
    // Brake wins over dodge (safer).
    const to_player = rl.Vector2Subtract(player.pos, self.car.pos);
    const dot_player = rl.Vector2DotProduct(forward, to_player);
    if (dot_player > 0 and rl.Vector2Length(to_player) <= self.car.size.y * 4) {
        const same_dir = self.car.curr_dir == player.curr_dir;
        const opp_dir = self.car.curr_dir == oppositeDirection(player.curr_dir);
        should_brake = should_brake or same_dir;
        should_dodge = should_dodge or opp_dir;
    }

    for (agents, 0..) |*other, oi| {
        if (oi == self_idx) continue;
        const to_other = rl.Vector2Subtract(other.car.pos, self.car.pos);
        const dot = rl.Vector2DotProduct(forward, to_other);
        if (dot > 0 and rl.Vector2Length(to_other) <= self.car.size.y * 4) {
            const same_dir = self.car.curr_dir == other.car.curr_dir;
            const opp_dir = self.car.curr_dir == oppositeDirection(other.car.curr_dir);
            should_brake = should_brake or same_dir;
            should_dodge = should_dodge or opp_dir;
            if (should_brake) break;
        }
    }
    if (should_brake) should_dodge = false;

    // Intersection yield-to-right. Yield outside the box, never inside
    // (inside cars always proceed to clear -> no deadlock cycle).
    // Total order: closer wins -> right-hand wins -> lower id wins (player=0).
    // YIELD_TIMEOUT force-go guarantees liveness on 4-way simultaneous arrival.
    const my_id: isize = @intCast(self_idx + 1);
    var should_yield = false;
    const yield_target = self.yieldTargetNode(map);
    if (yield_target) |target_idx| {
        if (nodeDegree(map, target_idx) >= 3) {
            const target_pos = map.nodes.items[target_idx].pos;
            const self_dist = rl.Vector2Distance(self.car.pos, target_pos);
            if (self_dist < c.YIELD_DIST and self_dist > c.NODE_CLEAR_DIST) {
                if (self.contestedBy(player, 0, my_id, target_idx, target_pos, self_dist, forward)) {
                    should_yield = true;
                } else {
                    for (agents, 0..) |*other, oi| {
                        if (oi == self_idx) continue;
                        const other_id: isize = @intCast(oi + 1);
                        if (self.contestedBy(&other.car, other_id, my_id, target_idx, target_pos, self_dist, forward)) {
                            should_yield = true;
                            break;
                        }
                    }
                }
            }
        }
    }

    if (should_yield) {
        self.yield_timer += dt;
        if (self.yield_timer > c.YIELD_TIMEOUT) {
            // Liveness backstop: force go, reset so we can yield again later.
            should_yield = false;
            self.yield_timer = 0;
        }
    } else {
        self.yield_timer = 0;
    }

    if (should_yield) {
        // Hold at stop line: brake, no dodge, suppress departure dir.
        return KeyInput.init(null, true, false);
    }

    if (self.car.curr_node != null and self.car.next_node == null and self.path_idx < self.path_len) {
        const target = self.path[self.path_idx] orelse return KeyInput.init(null, should_brake, should_dodge);
        const curr_idx = self.car.curr_node.?;
        const curr_node = map.nodes.items[curr_idx];
        for (curr_node.edges, 0..) |edge, dir_idx| {
            if (edge == target) {
                self.path_idx += 1;
                return .{ .dir = @enumFromInt(dir_idx), .brake = should_brake, .dodge = should_dodge };
            }
        }
    }

    return KeyInput.init(null, should_brake, should_dodge);
}

fn yieldTargetNode(self: *const Self, map: *const Map) ?usize {
    // Approaching: next_node is the contested intersection.
    if (self.car.next_node) |next_idx| return next_idx;
    // Stopped at node, about to depart: path target is contested.
    if (self.car.curr_node != null and self.path_idx < self.path_len) {
        if (self.path[self.path_idx]) |t| {
            // Only yield if t is a real neighbor (avoid stale path entries).
            const curr_idx = self.car.curr_node.?;
            if (curr_idx < map.nodes.items.len) {
                for (map.nodes.items[curr_idx].edges) |edge| {
                    if (edge == t) return t;
                }
            }
        }
    }
    return null;
}

fn nodeDegree(map: *const Map, idx: usize) usize {
    if (idx >= map.nodes.items.len) return 0;
    var n: usize = 0;
    for (map.nodes.items[idx].edges) |edge| {
        if (edge != null) n += 1;
    }
    return n;
}

fn contestedBy(
    self: *const Self,
    other_car: *const Car,
    other_id: isize,
    my_id: isize,
    target_idx: usize,
    target_pos: rl.Vector2,
    self_dist: f32,
    forward: rl.Vector2,
) bool {
    const contesting = (other_car.next_node == target_idx) or (other_car.curr_node == target_idx);
    if (!contesting) return false;
    const other_dist = rl.Vector2Distance(other_car.pos, target_pos);
    if (other_dist > c.YIELD_DIST + c.NODE_CLEAR_DIST) return false;

    // Someone already inside the box has the reservation.
    if (other_dist < c.NODE_CLEAR_DIST) return true;

    const diff = self_dist - other_dist;
    if (diff > c.YIELD_TIE_EPS) return true; // other clearly closer
    if (diff < -c.YIELD_TIE_EPS) return false; // self clearly closer
    // Tie: right-hand rule. cross > 0 means other is on my right (y-down coords).
    const to_other = rl.Vector2Subtract(other_car.pos, self.car.pos);
    if (rl.Vector2Length(to_other) < 1.0) return other_id < my_id;
    const cross = forward.x * to_other.y - forward.y * to_other.x;
    if (cross > 1.0) return true; // other on my right -> I yield
    if (cross < -1.0) return false; // other on my left -> I go
    return other_id < my_id; // collinear/simultaneous -> lower id (player=0) wins
}

fn oppositeDirection(dir: Direction) Direction {
    const dir_idx: usize = @intFromEnum(dir);
    return @enumFromInt((dir_idx + 2) % 4);
}

pub fn isAtEnd(self: *const Self) bool {
    return self.path_idx >= self.path_len and self.car.curr_node == self.end_node and self.car.next_node == null;
}

fn pickRandomStartEnd(map: *const Map) struct { usize, usize } {
    const a = rand().intRangeLessThan(usize, 0, map.start_nodes.count());
    const start_idx = map.start_nodes.keys()[a];
    const b = rand().intRangeLessThan(usize, 0, map.end_nodes.count());
    const end_idx = map.end_nodes.keys()[b];
    return .{ start_idx, end_idx };
}

pub fn reset(self: *Self, map: *const Map) void {
    const start_idx, const end_idx = pickRandomStartEnd(map);
    const start_node = &map.nodes.items[start_idx];

    var path: [c.MAX_NODES]?usize = .{null} ** c.MAX_NODES;
    const path_len = buildPath(&path, map, start_idx, end_idx);

    // TODO: make tunnels - reaching end node moves to start node
    self.start_node = start_idx;
    self.end_node = end_idx;
    self.path = path;
    self.path_len = path_len;
    self.path_idx = 0;

    self.car.pos = start_node.pos;
    self.car.curr_node = start_idx;
    self.car.next_node = null;
    self.car.speed = 0;
    self.car.vel = rl.Vector2Zero();
    self.car.next_dir = null;
    self.car.next_dir_timer = 0;
    self.car.lane_offset = 0;
    self.car.target_lane_offset = 0;
    self.car.dodge_timer = 0;
    self.yield_timer = 0;
}
