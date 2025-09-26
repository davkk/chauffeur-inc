const std = @import("std");
const math = std.math;
const json = std.json;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const Map = @import("Map.zig");

const LINE_THICKNESS = 4.0;

const GRID_COLOR = rl.Color{ .r = 100, .g = 100, .b = 100, .a = 50 };

const ACTIVE_COLOR = rl.WHITE;
const BAD_COLOR = rl.RED;
const INACTIVE_COLOR = rl.GRAY;

const State = enum {
    idle,
    eraser,
    add_node_single,
};

const Self = @This();

state: State,
active_node_id: ?usize,

fn hoveredNode(mouse_pos: rl.Vector2, nodes: []?Map.Node) ?*Map.Node {
    for (nodes) |*maybe_node| {
        if (maybe_node.*) |*node| {
            if (!node.active) continue;
            if (rl.CheckCollisionPointCircle(mouse_pos, node.pos, 10)) {
                return node;
            }
        }
    }
    return null;
}

fn hoveredEdge(mouse_pos: rl.Vector2, nodes: []?Map.Node) ?struct { *Map.Node, *Map.Node } {
    for (nodes) |*maybe_node1| {
        if (maybe_node1.*) |*node1| {
            if (!node1.active) continue;
            for (node1.edges.keys()) |edge| {
                if (node1.id > edge) continue;

                const node2 = &nodes[edge].?;
                if (!node2.active) continue;

                if (rl.CheckCollisionPointLine(mouse_pos, node1.pos, node2.pos, 10)) {
                    return .{ node1, node2 };
                }
            }
        }
    }
    return null;
}

fn snapToGrid(pos: rl.Vector2) rl.Vector2 {
    const snappedX = @round(pos.x / g.TILE_SIZE) * g.TILE_SIZE;
    const snappedY = @round(pos.y / g.TILE_SIZE) * g.TILE_SIZE;
    return rl.Vector2{ .x = snappedX, .y = snappedY };
}

fn isValidEdge(pos1: rl.Vector2, pos2: rl.Vector2) bool {
    const dx = pos2.x - pos1.x;
    const dy = pos2.y - pos1.y;
    return dx == 0 or dy == 0 or @abs(dx) == @abs(dy);
}

fn orientation(p: rl.Vector2, q: rl.Vector2, r: rl.Vector2) i32 {
    const val = (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);
    if (val == 0) return 0;
    return if (val > 0) 1 else 2;
}

fn doLinesIntersect(a1: rl.Vector2, a2: rl.Vector2, b1: rl.Vector2, b2: rl.Vector2) bool {
    if ((a1.x == b1.x and a1.y == b1.y) or (a1.x == b2.x and a1.y == b2.y) or (a2.x == b1.x and a2.y == b1.y) or (a2.x == b2.x and a2.y == b2.y)) {
        return false;
    }

    const o1 = orientation(a1, a2, b1);
    const o2 = orientation(a1, a2, b2);
    const o3 = orientation(b1, b2, a1);
    const o4 = orientation(b1, b2, a2);

    return o1 != o2 and o3 != o4;
}

fn pointOnSegment(p: rl.Vector2, a: rl.Vector2, b: rl.Vector2) bool {
    const min_x = @min(a.x, b.x);
    const max_x = @max(a.x, b.x);
    const min_y = @min(a.y, b.y);
    const max_y = @max(a.y, b.y);
    if (p.x < min_x or p.x > max_x or p.y < min_y or p.y > max_y) return false;
    const dx_ab = b.x - a.x;
    const dy_ab = b.y - a.y;
    const dx_ap = p.x - a.x;
    const dy_ap = p.y - a.y;
    if (dx_ab == 0) {
        return dx_ap == 0;
    } else if (dy_ab == 0) {
        return dy_ap == 0;
    } else if (@abs(dx_ab) == @abs(dy_ab)) {
        return @abs(dx_ap) == @abs(dy_ap) and (dx_ap * dy_ab == dy_ap * dx_ab);
    }
    return false;
}

fn intersectsAny(nodes: []?Map.Node, start_id: usize, end_pos: rl.Vector2) bool {
    const start_pos = nodes[start_id].?.pos;
    for (nodes) |*maybe_node1| {
        if (maybe_node1.*) |*node1| {
            if (!node1.active) continue;
            for (node1.edges.keys()) |edge_id| {
                const node2 = &nodes[edge_id].?;
                if (!node2.active) continue;
                if (pointOnSegment(end_pos, node1.pos, node2.pos)) continue;
                if (doLinesIntersect(start_pos, end_pos, node1.pos, node2.pos)) {
                    return true;
                }
            }
        }
    }
    return false;
}

pub fn init() Self {
    return .{
        .state = .idle,
        .active_node_id = null,
    };
}

pub fn draw(self: *Self, alloc: *const std.mem.Allocator, camera: *rl.Camera2D, map: *Map) !void {
    const wheel = rl.GetMouseWheelMove();
    if (wheel != 0) {
        camera.zoom += wheel * 0.1;
        if (camera.zoom < 0.1) camera.zoom = 0.1;
        if (camera.zoom > 5.0) camera.zoom = 5.0;
    }
    if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_MIDDLE)) {
        const delta = rl.GetMouseDelta();
        camera.target.x -= delta.x / camera.zoom;
        camera.target.y -= delta.y / camera.zoom;
    }

    // const KEY_SHIFT = rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT);
    const KEY_CTRL = rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL);
    if (rl.IsKeyPressed(rl.KEY_P)) {
        for (map.nodes.items) |*maybe_node| {
            if (maybe_node.*) |*node| {
                if (!node.active) continue;
                std.debug.print("{}: ", .{node.id});
                for (node.edges.keys()) |edge| {
                    std.debug.print("{}, ", .{edge});
                }
                std.debug.print("\n", .{});
            }
        }
    } else if (rl.IsKeyPressed(rl.KEY_V)) {
        self.state = .idle;
    } else if (rl.IsKeyPressed(rl.KEY_E)) {
        self.state = .eraser;
    } else if (rl.IsKeyPressed(rl.KEY_A)) {
        self.state = .add_node_single;
    } else if (KEY_CTRL and rl.IsKeyPressed(rl.KEY_S)) {
        const file = try std.fs.cwd().createFile("src/assets/map.dat", .{});
        defer file.close();

        var buffered_writer = std.io.bufferedWriter(file.writer());
        var writer = buffered_writer.writer();

        for (map.nodes.items) |maybe_node| {
            if (maybe_node) |node| {
                if (node.active) {
                    try writer.print("{d};{d};{d}", .{ node.id, node.pos.x, node.pos.y });
                    for (node.edges.keys()) |edge| {
                        try writer.print(" {d}", .{edge});
                    }
                    try writer.print("\n", .{});
                }
            }
        }

        buffered_writer.flush() catch {
            std.debug.print("Error flushing buffered writer", .{});
        };
    }

    rl.BeginDrawing();
    defer rl.EndDrawing();

    rl.ClearBackground(rl.BLACK);

    rl.BeginMode2D(camera.*);
    defer rl.EndMode2D();

    if (self.state != .idle) {
        const world_min_x = camera.target.x - camera.offset.x / camera.zoom;
        const world_max_x = camera.target.x + (g.SCREEN_WIDTH - camera.offset.x) / camera.zoom;
        const world_min_y = camera.target.y - camera.offset.y / camera.zoom;
        const world_max_y = camera.target.y + (g.SCREEN_HEIGHT - camera.offset.y) / camera.zoom;

        var grid_x = @floor(world_min_x / g.TILE_SIZE) * g.TILE_SIZE;
        while (grid_x <= world_max_x) : (grid_x += g.TILE_SIZE) {
            const pos_from = rl.Vector2{ .x = grid_x, .y = world_min_y };
            const pos_to = rl.Vector2{ .x = grid_x, .y = world_max_y };
            rl.DrawLineEx(pos_from, pos_to, 2, GRID_COLOR);
        }
        var grid_y = @floor(world_min_y / g.TILE_SIZE) * g.TILE_SIZE;
        while (grid_y <= world_max_y) : (grid_y += g.TILE_SIZE) {
            const pos_from = rl.Vector2{ .x = world_min_x, .y = grid_y };
            const pos_to = rl.Vector2{ .x = world_max_x, .y = grid_y };
            rl.DrawLineEx(pos_from, pos_to, 2, GRID_COLOR);
        }
    }

    const mouse_world_pos = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera.*);
    const mouse_pos = snapToGrid(mouse_world_pos);

    map.draw();

    switch (self.state) {
        .idle => {},
        .eraser => {
            if (hoveredNode(mouse_pos, map.nodes.items)) |node1| {
                rl.DrawCircleV(node1.pos, 10, ACTIVE_COLOR);
                if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT)) {
                    node1.active = false;
                    for (map.nodes.items) |*maybe_node| {
                        if (maybe_node.*) |*node| {
                            if (node.active) {
                                _ = node.edges.swapRemove(node1.id);
                            }
                        }
                    }
                    if (self.active_node_id) |active| {
                        if (active == node1.id) {
                            self.active_node_id = null;
                        }
                    }
                }
            } else {
                if (hoveredEdge(mouse_pos, map.nodes.items)) |edge| {
                    const node1, const node2 = edge;
                    rl.DrawLineEx(node1.pos, node2.pos, LINE_THICKNESS, ACTIVE_COLOR);
                    if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT)) {
                        _ = node1.edges.swapRemove(node2.id);
                        _ = node2.edges.swapRemove(node1.id);
                    }
                }
            }
        },
        .add_node_single => {
            if (rl.IsKeyPressed(rl.KEY_ESCAPE)) {
                self.active_node_id = null;
            }

            if (self.active_node_id) |node_id| {
                var new_node: *Map.Node = undefined;
                var found = false;

                if (hoveredNode(mouse_pos, map.nodes.items)) |node2| {
                    new_node = node2;
                    found = true;
                }

                const target_pos = if (found) new_node.pos else mouse_pos;

                rl.DrawLineEx(
                    map.nodes.items[node_id].?.pos,
                    target_pos,
                    LINE_THICKNESS,
                    if (isValidEdge(map.nodes.items[node_id].?.pos, target_pos) and !intersectsAny(map.nodes.items, node_id, target_pos)) ACTIVE_COLOR else BAD_COLOR,
                );

                if (found) {
                    rl.DrawCircleV(new_node.pos, 10, ACTIVE_COLOR);
                } else {
                    rl.DrawCircleV(mouse_pos, 10, ACTIVE_COLOR);
                }

                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and isValidEdge(map.nodes.items[node_id].?.pos, target_pos) and !intersectsAny(map.nodes.items, node_id, target_pos)) {
                    if (!found) {
                        const new_id = map.max_id;
                        map.max_id += 1;
                        if (new_id >= map.nodes.items.len) {
                            try map.nodes.resize(new_id + 1);
                        }
                        map.nodes.items[new_id] = Map.Node.init(alloc, mouse_pos, new_id);
                        new_node = &map.nodes.items[new_id].?;
                        // Check if mouse_pos is on an existing edge and split it
                        if (hoveredEdge(mouse_pos, map.nodes.items)) |split_edge| {
                            const node_a = split_edge[0];
                            const node_b = split_edge[1];
                            _ = node_a.edges.swapRemove(node_b.id);
                            _ = node_b.edges.swapRemove(node_a.id);
                            try node_a.edges.put(new_node.id, {});
                            try node_b.edges.put(new_node.id, {});
                            try new_node.edges.put(node_a.id, {});
                            try new_node.edges.put(node_b.id, {});
                        }
                    }
                    try new_node.edges.put(node_id, {});
                    try map.nodes.items[node_id].?.edges.put(new_node.id, {});
                    self.active_node_id = new_node.id;
                }
            } else if (hoveredNode(mouse_pos, map.nodes.items)) |node1| {
                rl.DrawCircleV(node1.pos, 10, ACTIVE_COLOR);
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    self.active_node_id = node1.id;
                }
            } else {
                rl.DrawCircleV(mouse_pos, 10, ACTIVE_COLOR);
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    const new_id = map.max_id;
                    map.max_id += 1;
                    if (new_id >= map.nodes.items.len) {
                        try map.nodes.resize(new_id + 1);
                    }
                    map.nodes.items[new_id] = Map.Node.init(alloc, mouse_pos, new_id);
                    const new_node_ptr = &map.nodes.items[new_id].?;
                    // Check if mouse_pos is on an existing edge and split it
                    if (hoveredEdge(mouse_pos, map.nodes.items)) |split_edge| {
                        const node_a = split_edge[0];
                        const node_b = split_edge[1];
                        _ = node_a.edges.swapRemove(node_b.id);
                        _ = node_b.edges.swapRemove(node_a.id);
                        try node_a.edges.put(new_node_ptr.id, {});
                        try node_b.edges.put(new_node_ptr.id, {});
                        try new_node_ptr.edges.put(node_a.id, {});
                        try new_node_ptr.edges.put(node_b.id, {});
                    }
                    self.active_node_id = new_node_ptr.id;
                }
            }
        },
    }
}
