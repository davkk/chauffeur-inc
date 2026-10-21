const std = @import("std");
const rand = @import("raylib.zig").rand;
const math = std.math;

const rl = @import("raylib.zig").rl;
const vec_add = @import("raylib.zig").vec_add;
const c = @import("constants.zig");

const Map = @import("Map.zig");
const Self = @This();

pub const State = enum { waiting, in_car, delivered, expired };

/// Matches the HUD's TAXI_YELLOW objective colour, so the world marker and the
/// objective panel read as the same instruction.
const DROP_OFF_COLOR = rl.Color{ .r = 245, .g = 197, .b = 66, .a = 255 };

start_pos: rl.Vector2,
end_pos: rl.Vector2,

/// Which side of the road the passenger stands on: +1 = right side of the
/// travel direction, -1 = left side. The player must be on this side to pick
/// the passenger up.
start_side: i8,

/// Undirected endpoints of the street the passenger stands on / wants to be
/// dropped off on. The autopilot and minimap use these to plan a route.
start_edge: Map.Edge,
end_edge: Map.Edge,

state: State,

/// How long the passenger will wait to be picked up.
patience: f32,
patience_max: f32,

/// Time left to deliver after the pickup. Zero while waiting.
time_left: f32,
time_max: f32,

fare: u32,
distance: f32,

/// Pick two distinct, non-terminal street segments. The old implementation
/// sampled random numbers until it found a pair, which could spin forever on a
/// small map; this always terminates.
fn pickEdgePair(map: *const Map) struct { Map.Edge, Map.Edge } {
    var eligible: [c.MAX_NODES * 4]Map.Edge = undefined;
    var eligible_count: usize = 0;
    var all: [c.MAX_NODES * 4]Map.Edge = undefined;
    var all_count: usize = 0;

    for (map.edges.items) |edge| {
        // Loaded maps contain each edge twice (once per direction). Keep one.
        if (edge.from >= edge.to) continue;
        if (edge.from >= map.nodes.items.len or edge.to >= map.nodes.items.len) continue;

        all[all_count] = edge;
        all_count += 1;

        const touches_terminal = map.start_nodes.contains(edge.from) or
            map.start_nodes.contains(edge.to) or
            map.end_nodes.contains(edge.from) or
            map.end_nodes.contains(edge.to);
        if (!touches_terminal) {
            eligible[eligible_count] = edge;
            eligible_count += 1;
        }
    }

    const pool = if (eligible_count >= 2) eligible[0..eligible_count] else all[0..all_count];
    std.debug.assert(pool.len >= 2);

    const a = rand().intRangeLessThan(usize, 0, pool.len);
    const b = (a + 1 + rand().intRangeLessThan(usize, 0, pool.len - 1)) % pool.len;
    return .{ pool[a], pool[b] };
}

fn randEdgePos() f32 {
    return math.clamp(rand().float(f32), 0.2, 0.8);
}

fn randSideOffset(pos1: *const rl.Vector2, pos2: *const rl.Vector2) rl.Vector2 {
    const dir = rl.Vector2Normalize(rl.Vector2Subtract(pos1.*, pos2.*));
    const perp: rl.Vector2 = .{ .x = dir.y, .y = -dir.x };
    const sign: f32 = if (rand().boolean()) 1.0 else -1.0;
    return rl.Vector2Scale(perp, sign * c.TILE_SIZE);
}

fn edgePoint(map: *const Map, edge: Map.Edge, t: f32) rl.Vector2 {
    const from = map.nodes.items[edge.from].pos;
    const to = map.nodes.items[edge.to].pos;
    return rl.Vector2Add(from, rl.Vector2Scale(rl.Vector2Subtract(to, from), t));
}

pub fn init(map: *const Map) Self {
    const start_edge, const end_edge = pickEdgePair(map);

    const start_from = map.nodes.items[start_edge.from].pos;
    const start_to = map.nodes.items[start_edge.to].pos;
    const travel = rl.Vector2Normalize(rl.Vector2Subtract(start_to, start_from));
    const perp: rl.Vector2 = .{ .x = -travel.y, .y = travel.x };
    const side_sign: i8 = if (rand().boolean()) 1 else -1;
    const side_offset = rl.Vector2Scale(perp, @as(f32, @floatFromInt(side_sign)) * c.TILE_SIZE);
    const start_pos = vec_add(&.{
        edgePoint(map, start_edge, randEdgePos()),
        side_offset,
    });
    const end_pos = edgePoint(map, end_edge, randEdgePos());

    const distance = rl.Vector2Distance(start_pos, end_pos);
    const fare = c.PASSENGER_FARE_BASE +
        @as(u32, @intFromFloat(distance * c.PASSENGER_FARE_PER_PIXEL));

    return .{
        .start_pos = start_pos,
        .end_pos = end_pos,
        .start_side = side_sign,
        .start_edge = start_edge,
        .end_edge = end_edge,
        .state = .waiting,
        .patience = c.PASSENGER_PATIENCE,
        .patience_max = c.PASSENGER_PATIENCE,
        .time_left = 0,
        .time_max = 0,
        .fare = fare,
        .distance = distance,
    };
}

pub fn draw(self: *Self) void {
    switch (self.state) {
        .waiting => {
            const now: f32 = @floatCast(rl.GetTime());
            const pulse: f32 = 1.0 + 0.15 * @sin(now * 6.0);
            rl.DrawCircleV(self.start_pos, 11.0 * pulse, rl.BLUE);
            rl.DrawCircleV(self.start_pos, 6.0, rl.WHITE);
            rl.DrawRing(
                self.start_pos,
                16.0,
                19.0,
                0,
                360,
                32,
                rl.ColorAlpha(rl.BLUE, 0.6),
            );
        },
        .in_car => {
            const now: f32 = @floatCast(rl.GetTime());
            const pulse: f32 = 1.0 + 0.1 * @sin(now * 5.0);
            rl.DrawCircleV(self.end_pos, 1.5 * c.TILE_SIZE * pulse, rl.ColorAlpha(DROP_OFF_COLOR, 0.22));
            rl.DrawRing(
                self.end_pos,
                1.5 * c.TILE_SIZE,
                1.5 * c.TILE_SIZE + 3.0,
                0,
                360,
                40,
                rl.ColorAlpha(DROP_OFF_COLOR, 0.8),
            );
        },
        .delivered, .expired => {},
    }
}
