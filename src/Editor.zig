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

pub const State = enum {
    idle,
    eraser,
    add_node,
    fill,
};

const Self = @This();

state: State,
active_tile_type: Map.TileType,
active_node_id: ?usize,

fn hoveredNode(mouse_pos: rl.Vector2, nodes: []Map.Node) ?*Map.Node {
    for (nodes) |*node| {
        if (!node.active) continue;
        if (rl.CheckCollisionPointCircle(mouse_pos, node.pos, 10)) {
            return node;
        }
    }
    return null;
}

fn hoveredEdge(mouse_pos: rl.Vector2, nodes: []Map.Node) ?struct { *Map.Node, *Map.Node } {
    for (nodes) |*node1| {
        if (!node1.active) continue;
        for (node1.edges.keys()) |edge| {
            if (node1.id > edge) continue;

            const node2 = &nodes[edge];
            if (!node2.active) continue;

            if (rl.CheckCollisionPointLine(mouse_pos, node1.pos, node2.pos, 10)) {
                return .{ node1, node2 };
            }
        }
    }
    return null;
}

fn hoveredTile(mouse_pos: rl.Vector2, tiles: Map.TileMap) ?*Map.TilePosition {
    var tile_iter = tiles.iterator();
    while (tile_iter.next()) |entry| {
        const tile_pos = entry.key_ptr;
        const mx: i32 = @intFromFloat(mouse_pos.x);
        const my: i32 = @intFromFloat(mouse_pos.y);
        if (mx == tile_pos.x and my == tile_pos.y) {
            return tile_pos;
        }
    }
    return null;
}

fn snapToGrid(pos: rl.Vector2) rl.Vector2 {
    const tile_size = g.TILE_SIZE * 2;
    const snappedX = @round(pos.x / tile_size) * tile_size;
    const snappedY = @round(pos.y / tile_size) * tile_size;
    return rl.Vector2{ .x = snappedX, .y = snappedY };
}

fn isValidEdge(pos1: rl.Vector2, pos2: rl.Vector2) bool {
    const dx = pos2.x - pos1.x;
    const dy = pos2.y - pos1.y;
    return dx == 0 or dy == 0 or @abs(dx) == @abs(dy);
}

pub fn init() Self {
    return .{
        .state = .idle,
        .active_node_id = null,
        .active_tile_type = .pavement,
    };
}

pub fn draw(self: *Self, alloc: std.mem.Allocator, camera: *rl.Camera2D, map: *Map) !void {
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

    const KEY_SHIFT = rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT);
    const KEY_CTRL = rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL);

    if (KEY_CTRL and rl.IsKeyDown(rl.KEY_EQUAL)) {
        camera.zoom = @min(camera.zoom + 1.0, 4.0);
    } else if (KEY_CTRL and rl.IsKeyDown(rl.KEY_MINUS)) {
        camera.zoom = @max(camera.zoom - 1.0, 1.0);
    } else if (!KEY_SHIFT and !KEY_CTRL) {
        if (rl.IsKeyPressed(rl.KEY_ESCAPE)) {
            if (self.active_node_id) |node_id| {
                if (map.nodes.items[node_id].edges.count() == 0) {
                    map.nodes.items[node_id].active = false;
                }
            }
            self.active_node_id = null;
        } else if (rl.IsKeyPressed(rl.KEY_P)) {
            for (map.nodes.items) |*node| {
                if (!node.active) continue;
                std.debug.print("{}: ", .{node.id});
                for (node.edges.keys()) |edge| {
                    std.debug.print("{}, ", .{edge});
                }
                std.debug.print("\n", .{});
            }
        } else if (rl.IsKeyPressed(rl.KEY_V)) {
            self.state = .idle;
        } else if (rl.IsKeyPressed(rl.KEY_E)) {
            self.state = .eraser;
        } else if (rl.IsKeyPressed(rl.KEY_N)) {
            self.state = .add_node;
        } else if (rl.IsKeyPressed(rl.KEY_F)) {
            self.state = .fill;
        } else if (rl.IsKeyDown(rl.KEY_W) or rl.IsKeyDown(rl.KEY_UP)) {
            camera.target.y -= 30;
        } else if (rl.IsKeyDown(rl.KEY_S) or rl.IsKeyDown(rl.KEY_DOWN)) {
            camera.target.y += 30;
        } else if (rl.IsKeyDown(rl.KEY_A) or rl.IsKeyDown(rl.KEY_LEFT)) {
            camera.target.x -= 30;
        } else if (rl.IsKeyDown(rl.KEY_D) or rl.IsKeyDown(rl.KEY_RIGHT)) {
            camera.target.x += 30;
        }
    }

    if (!KEY_SHIFT and KEY_CTRL and rl.IsKeyPressed(rl.KEY_S)) { // save
        try map.saveToFile();
    }

    // draw grid
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

    const mouse_world_pos = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera.*);
    const mouse_pos = snapToGrid(mouse_world_pos);

    map.draw();

    var tile_iter = map.tiles.iterator();
    while (tile_iter.next()) |entry| {
        const tile = entry.key_ptr.*;
        rl.DrawRectanglePro(
            .{
                .x = @floatFromInt(tile.x),
                .y = @floatFromInt(tile.y),
                .width = 10,
                .height = 10,
            },
            .{ .x = 5, .y = 5 },
            0,
            rl.WHITE,
        );
    }

    switch (self.state) {
        .idle => {},
        .eraser => {
            self.active_node_id = null;
            if (hoveredNode(mouse_pos, map.nodes.items)) |node1| {
                rl.DrawCircleV(node1.pos, 10, ACTIVE_COLOR);
                if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT)) {
                    node1.active = false;
                    for (map.nodes.items) |*node| {
                        if (node.active) {
                            _ = node.edges.swapRemove(node1.id);
                        }
                        if (node.edges.count() == 0) {
                            node.active = false;
                        }
                    }
                    if (self.active_node_id) |active| {
                        if (active == node1.id) {
                            self.active_node_id = null;
                        }
                    }
                }
            } else if (hoveredEdge(mouse_pos, map.nodes.items)) |edge| {
                const node1, const node2 = edge;
                rl.DrawLineEx(node1.pos, node2.pos, LINE_THICKNESS, ACTIVE_COLOR);
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    _ = node1.edges.swapRemove(node2.id);
                    _ = node2.edges.swapRemove(node1.id);
                    if (node1.edges.count() == 0) node1.active = false;
                    if (node2.edges.count() == 0) node2.active = false;
                }
            } else if (hoveredTile(mouse_pos, map.tiles)) |tile_pos| {
                rl.DrawCircleV(
                    .{
                        .x = @floatFromInt(tile_pos.x),
                        .y = @floatFromInt(tile_pos.y),
                    },
                    10,
                    ACTIVE_COLOR,
                );
                if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT)) {
                    map.tiles.removeByPtr(tile_pos);
                }
            }
        },
        .add_node => {
            if (self.active_node_id) |node_id| {
                var new_node: *Map.Node = undefined;
                var found = false;

                if (hoveredNode(mouse_pos, map.nodes.items)) |node2| {
                    new_node = node2;
                    found = true;
                }

                const target_pos = if (found) new_node.pos else mouse_pos;

                rl.DrawLineEx(
                    map.nodes.items[node_id].pos,
                    target_pos,
                    LINE_THICKNESS,
                    if (isValidEdge(map.nodes.items[node_id].pos, target_pos)) ACTIVE_COLOR else BAD_COLOR,
                );

                if (found) {
                    rl.DrawCircleV(new_node.pos, 10, ACTIVE_COLOR);
                } else {
                    rl.DrawCircleV(mouse_pos, 10, ACTIVE_COLOR);
                }

                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and isValidEdge(map.nodes.items[node_id].pos, target_pos)) {
                    if (!found) {
                        try map.nodes.append(Map.Node.init(alloc, mouse_pos, map.nodes.items.len));
                        new_node = &map.nodes.items[map.nodes.items.len - 1];
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
                    try map.nodes.items[node_id].edges.put(new_node.id, {});
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
                    const new_node = Map.Node.init(alloc, mouse_pos, map.nodes.items.len);
                    try map.nodes.append(new_node);
                    const new_node_ptr = &map.nodes.items[map.nodes.items.len - 1];
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
        .fill => {
            const tile_color = switch (self.active_tile_type) {
                .grass => rl.GREEN,
                .water => rl.BLUE,
                .pavement => rl.LIGHTGRAY,
            };
            rl.DrawRectanglePro(
                .{ .x = mouse_pos.x, .y = mouse_pos.y, .width = 2 * g.TILE_SIZE, .height = 2 * g.TILE_SIZE },
                .{ .x = g.TILE_SIZE, .y = g.TILE_SIZE },
                0,
                tile_color,
            );
            rl.DrawCircleV(mouse_pos, 10, rl.WHITE);

            if (rl.IsKeyPressed(rl.KEY_ONE)) {
                self.active_tile_type = .pavement;
            } else if (rl.IsKeyPressed(rl.KEY_TWO)) {
                self.active_tile_type = .grass;
            } else if (rl.IsKeyPressed(rl.KEY_THREE)) {
                self.active_tile_type = .water;
            }

            if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT)) {
                try map.tiles.put(
                    .{
                        .x = @intFromFloat(mouse_pos.x),
                        .y = @intFromFloat(mouse_pos.y),
                    },
                    self.active_tile_type,
                );
            }
        },
    }
}
