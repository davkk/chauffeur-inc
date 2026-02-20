const std = @import("std");
const rand = std.crypto.random;

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
    const a = rand.intRangeLessThan(usize, 0, map.start_nodes.count());
    const start_idx = map.start_nodes.keys()[a];
    const start_node = &map.nodes.items[start_idx];

    const b = rand.intRangeLessThan(usize, 0, map.end_nodes.count());
    const end_idx = map.end_nodes.keys()[b];

    var path: [g.MAX_NODES]?usize = .{null} ** g.MAX_NODES;
    const path_len = constructPath(&path, map, start_idx, end_idx);

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

pub fn update(self: *Self, dt: f32, map: *const Map) void {
    const input = self.decideInput(map);
    self.car.update(dt, map, input);
}

fn constructPath(path: []?usize, map: *const Map, start: usize, end: usize) usize {
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

        if (curr == end) {
            break;
        }

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

fn decideInput(self: *Self, map: *const Map) g.KeyInput {
    if (self.car.curr_node != null and self.car.next_node == null) {
        if (self.path_idx < self.path_len) {
            const target = self.path[self.path_idx] orelse return .{ .dir = null, .brake = false };
            const curr_idx = self.car.curr_node.?;
            const curr_node = map.nodes.items[curr_idx];
            for (curr_node.edges, 0..) |edge, dir_idx| {
                if (edge == target) {
                    self.path_idx += 1;
                    return .{ .dir = @enumFromInt(dir_idx), .brake = false };
                }
            }
        }
    }
    return .{ .dir = null, .brake = false };
}
