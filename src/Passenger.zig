const std = @import("std");
const rand = std.crypto.random;
const math = std.math;

const rl = @import("raylib.zig").rl;
const vec_add = @import("raylib.zig").vec_add;
const g = @import("globals.zig");

const Map = @import("Map.zig");
const Self = @This();

start_pos: rl.Vector2,
end_pos: rl.Vector2,
state: enum { waiting, in_car, delivered },

/// start, end are inclusive
fn randPair(start: usize, end: usize) struct { usize, usize } {
    var a: usize = undefined;
    var b: usize = undefined;
    while (a == b) { // WARN: this can go forever, separate thread
        a = rand.intRangeAtMost(usize, start, end);
        b = rand.intRangeAtMost(usize, start, end);
    }
    return .{ a, b };
}

fn randEdgePos() f32 {
    return math.clamp(rand.float(f32), 0.2, 0.8);
}

fn randSideOffset(pos1: *const rl.Vector2, pos2: *const rl.Vector2) rl.Vector2 {
    const dist = rl.Vector2Normalize(rl.Vector2Subtract(pos1.*, pos2.*));
    const perp: rl.Vector2 = .{ .x = dist.y, .y = -dist.x };
    return if (rand.boolean())
        rl.Vector2Scale(perp, g.TILE_SIZE)
    else
        rl.Vector2Scale(perp, -g.TILE_SIZE);
}

pub fn init(map: *const Map) Self {
    const edge_start_idx, const edge_end_idx = randPair(0, map.edges.items.len - 1);

    const edge_start = map.edges.items[edge_start_idx];
    const pos_start_from = map.nodes.items[edge_start.from].pos;
    const pos_start_to = map.nodes.items[edge_start.to].pos;
    const sideOffset = randSideOffset(&pos_start_from, &pos_start_to);
    const start_pos = vec_add(&.{
        pos_start_from,
        rl.Vector2Scale(
            rl.Vector2Subtract(pos_start_to, pos_start_from),
            randEdgePos(),
        ),
        sideOffset,
    });

    const edge_end = map.edges.items[edge_end_idx];
    const pos_end_from = map.nodes.items[edge_end.from].pos;
    const pos_end_to = map.nodes.items[edge_end.to].pos;
    const end_pos = rl.Vector2Add(
        pos_end_from,
        rl.Vector2Scale(
            rl.Vector2Subtract(pos_end_to, pos_end_from),
            randEdgePos(),
        ),
    );

    return .{
        .start_pos = start_pos,
        .end_pos = end_pos,
        .state = .waiting,
    };
}

pub fn draw(self: *Self) void {
    switch (self.state) {
        .waiting => rl.DrawCircleV(self.start_pos, 10, rl.BLUE),
        .in_car => rl.DrawCircleV(
            self.end_pos,
            1.5 * g.TILE_SIZE,
            rl.ColorAlpha(rl.BLUE, 0.5),
        ),
        .delivered => {},
    }
}
