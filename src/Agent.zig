const std = @import("std");
const rand = std.crypto.random;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const Car = @import("Car.zig");
const Map = @import("Map.zig");

const Self = @This();

car: Car,

path: [g.MAX_NODES]?usize,
path_len: usize,
path_idx: usize,

start_node: usize,
end_node: usize,

pub fn init(map: *const Map) Self {
    const start_idx, const end_idx = pickRandomStartEnd(map);
    const start_node = &map.nodes.items[start_idx];

    var path: [g.MAX_NODES]?usize = .{null} ** g.MAX_NODES;
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
    var queue: [g.MAX_NODES]?usize = .{null} ** g.MAX_NODES;
    var head: usize = 0;
    var tail: usize = 0;

    var seen: [g.MAX_NODES]bool = .{false} ** g.MAX_NODES;
    var parents: [g.MAX_NODES]?usize = .{null} ** g.MAX_NODES;

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

    var segment_path: [g.MAX_NODES]?usize = .{null} ** g.MAX_NODES;

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

fn decideInput(self: *Self, map: *const Map, agents: []const Self, player: *const Car) g.KeyInput {
    const should_brake = self.checkCollisionAhead(agents, player);

    if (self.car.curr_node != null and self.car.next_node == null and self.path_idx < self.path_len) {
        const target = self.path[self.path_idx] orelse return .{ .dir = null, .brake = should_brake };

        const curr_idx = self.car.curr_node.?;
        const curr_node = map.nodes.items[curr_idx];

        for (curr_node.edges, 0..) |edge, dir_idx| {
            if (edge == target) {
                self.path_idx += 1;
                return .{ .dir = @enumFromInt(dir_idx), .brake = should_brake };
            }
        }
    }
    return .{ .dir = null, .brake = should_brake };
}

fn checkCollisionAhead(self: *const Self, agents: []const Self, player: *const Car) bool {
    if (shouldBrakeForCar(&self.car, player)) {
        return true;
    }

    for (agents) |other| {
        const dist_to_other = rl.Vector2Distance(self.car.pos, other.car.pos);
        if (dist_to_other < 5.0) continue;

        if (shouldBrakeForCar(&self.car, &other.car)) {
            return true;
        }
    }

    return false;
}

fn shouldBrakeForCar(self_car: *const Car, other_car: *const Car) bool {
    if (self_car.next_node == null) return false;

    // only brake for cars going the same direction
    if (other_car.next_node != null) {
        const same_dir = self_car.curr_dir == other_car.curr_dir;
        if (!same_dir) return false;
    }

    const dist = rl.Vector2Distance(self_car.pos, other_car.pos);

    if (dist < self_car.size.y * 3) {
        const self_dir_vec = rl.Vector2Scale(g.BASE_VEC[@intFromEnum(self_car.curr_dir)], 1.0);
        const to_other = rl.Vector2Subtract(other_car.pos, self_car.pos);
        const dot_product = self_dir_vec.x * to_other.x + self_dir_vec.y * to_other.y;
        if (dot_product > 0) {
            return true;
        }
    }

    return false;
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

    var path: [g.MAX_NODES]?usize = .{null} ** g.MAX_NODES;
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
}
