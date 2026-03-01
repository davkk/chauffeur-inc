const std = @import("std");
const rand = std.crypto.random;

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
    };
}

pub fn update(self: *Self, dt: f32, map: *const Map, agents: []const Self, player: *const Car) void {
    const input = self.decideInput(map, agents, player);
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
    const waypoint_count = rand.intRangeAtMost(usize, 2, 4);

    var total_len: usize = 0;
    var current = start;

    var segment_path: [c.MAX_NODES]?usize = .{null} ** c.MAX_NODES;

    for (0..waypoint_count) |_| {
        // TODO: we should not pick other start/end nodes as waypoints
        const waypoint = rand.intRangeLessThan(usize, 0, map.nodes.items.len);
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

fn decideInput(self: *Self, map: *const Map, agents: []const Self, player: *const Car) KeyInput {
    var should_brake = false;
    var should_dodge = false;

    const forward = c.BASE_VEC[@intFromEnum(self.car.curr_dir)];

    // FIXME: allow for multiple deciders for input brake/dodge
    // agents should look at player and other agents at the same time
    // so both checks (player & agents) should not interfere with each other
    const to_player = rl.Vector2Subtract(player.pos, self.car.pos);
    const dot_player = rl.Vector2DotProduct(forward, to_player);
    if (dot_player > 0 and rl.Vector2Length(to_player) <= self.car.size.y * 4) {
        const same_dir = self.car.curr_dir == player.curr_dir;
        const opp_dir = self.car.curr_dir == oppositeDirection(player.curr_dir);
        should_brake = same_dir;
        should_dodge = opp_dir;
    }

    for (agents) |*other| {
        const to_other = rl.Vector2Subtract(other.car.pos, self.car.pos);
        const dot = rl.Vector2DotProduct(forward, to_other);
        if (dot > 0 and rl.Vector2Length(to_other) <= self.car.size.y * 4) {
            const same_dir = self.car.curr_dir == other.car.curr_dir;
            const opp_dir = self.car.curr_dir == oppositeDirection(other.car.curr_dir);
            should_brake = same_dir;
            should_dodge = opp_dir;
            if (should_brake or should_dodge) break;
        }
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

fn oppositeDirection(dir: Direction) Direction {
    const dir_idx: usize = @intFromEnum(dir);
    return @enumFromInt((dir_idx + 2) % 4);
}

pub fn isAtEnd(self: *const Self) bool {
    return self.path_idx >= self.path_len and self.car.curr_node == self.end_node and self.car.next_node == null;
}

fn pickRandomStartEnd(map: *const Map) struct { usize, usize } {
    const a = rand.intRangeLessThan(usize, 0, map.start_nodes.count());
    const start_idx = map.start_nodes.keys()[a];
    const b = rand.intRangeLessThan(usize, 0, map.end_nodes.count());
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
}
