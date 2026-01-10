const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const Map = @import("Map.zig");

const LINE_THICKNESS = 4.0;

const GRID_COLOR = rl.Color{ .r = 100, .g = 100, .b = 100, .a = 50 };

const ACTIVE_COLOR = rl.WHITE;
const BAD_COLOR = rl.RED;
const INACTIVE_COLOR = rl.GRAY;

pub const TextureGroupType = enum {
    none,
    tiles,
    road,
    sprites,
};

const TextureGroup = struct {
    type: TextureGroupType,
    tiles: []const rl.Rectangle,
};

const GROUPS = [_]TextureGroup{
    .{ .type = .tiles, .tiles = g.TILES[0..] },
    .{ .type = .sprites, .tiles = g.SPRITES[0..] },
};

pub const State = enum {
    idle,
    eraser,
    add_node,
    fill,
};

const Self = @This();

state: State,
active_tile_type: ?usize,
active_node_id: ?usize,
active_group: TextureGroupType,
group_expanded: [2]bool,

start_pos: ?rl.Vector2,
end_pos: ?rl.Vector2,

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

fn hoveredTile(mouse_pos: rl.Vector2, tiles: Map.TileMap) ?usize {
    const mx: i32 = @intFromFloat(mouse_pos.x);
    const my: i32 = @intFromFloat(mouse_pos.y);
    const col = @as(usize, @intCast(@divFloor(mx, g.TILE_SIZE)));
    const row = @as(usize, @intCast(@divFloor(my, g.TILE_SIZE)));
    if (row < tiles.len and col < tiles[0].len) {
        const tile_id = tiles[row][col];
        if (tile_id != 0) {
            return tile_id;
        }
    }
    return null;
}

fn snapToGrid(pos: rl.Vector2) rl.Vector2 {
    const snappedX = @round(pos.x / g.TILE_SIZE) * g.TILE_SIZE;
    const snappedY = @round(pos.y / g.TILE_SIZE) * g.TILE_SIZE;
    return .{ .x = snappedX, .y = snappedY };
}

fn isValidEdge(pos1: rl.Vector2, pos2: rl.Vector2) bool {
    const dx = pos2.x - pos1.x;
    const dy = pos2.y - pos1.y;
    return dx == 0 or dy == 0;
}

pub fn init() Self {
    return .{
        .state = .idle,
        .active_node_id = null,
        .active_tile_type = null,
        .active_group = .none,
        .group_expanded = [_]bool{ true, true },
        .start_pos = null,
        .end_pos = null,
    };
}

pub fn update(self: *Self, camera: *rl.Camera2D, map: *Map) !void {
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
            self.active_group = .none;
        } else if (rl.IsKeyPressed(rl.KEY_E)) {
            self.state = .eraser;
        } else if (rl.IsKeyPressed(rl.KEY_N)) {
            self.state = .add_node;
        } else if (rl.IsKeyPressed(rl.KEY_F)) {
            self.state = .fill;
        } else if (rl.IsKeyDown(rl.KEY_W) or rl.IsKeyDown(rl.KEY_UP)) {
            camera.target.y = @max(camera.target.y - 30, 0);
        } else if (rl.IsKeyDown(rl.KEY_S) or rl.IsKeyDown(rl.KEY_DOWN)) {
            camera.target.y += 30;
        } else if (rl.IsKeyDown(rl.KEY_A) or rl.IsKeyDown(rl.KEY_LEFT)) {
            camera.target.x = @max(camera.target.x - 30, 0);
        } else if (rl.IsKeyDown(rl.KEY_D) or rl.IsKeyDown(rl.KEY_RIGHT)) {
            camera.target.x += 30;
        }
    }

    if (!KEY_SHIFT and KEY_CTRL and rl.IsKeyPressed(rl.KEY_S)) { // save
        try map.saveToFile();
    }
}

pub fn drawWorld(self: *Self, alloc: std.mem.Allocator, camera: *rl.Camera2D, map: *Map, tileset_texture: rl.Texture2D) !void {
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

    const mouse_screen_pos = rl.GetMousePosition();
    const sidebar_rect = rl.Rectangle{ .x = g.SCREEN_WIDTH - 200, .y = 0, .width = 200, .height = g.SCREEN_HEIGHT };
    const mouse_over_ui = rl.CheckCollisionPointRec(mouse_screen_pos, sidebar_rect);

    const mouse_world_pos = rl.GetScreenToWorld2D(mouse_screen_pos, camera.*);
    const mouse_pos = snapToGrid(mouse_world_pos);

    map.draw(self.active_group);

    switch (self.state) {
        .idle => {},
        .eraser => {
            self.active_node_id = null;
            if (hoveredNode(mouse_pos, map.nodes.items)) |node1| {
                rl.DrawCircleV(node1.pos, 10, ACTIVE_COLOR);
                if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT) and !mouse_over_ui) {
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
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and !mouse_over_ui) {
                    _ = node1.edges.swapRemove(node2.id);
                    _ = node2.edges.swapRemove(node1.id);
                    if (node1.edges.count() == 0) node1.active = false;
                    if (node2.edges.count() == 0) node2.active = false;
                }
            } else if (hoveredTile(mouse_pos, map.tiles)) |tile_id| {
                const tile = g.TILE_DEFINITIONS[tile_id];
                rl.DrawRectanglePro(tile, .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 }, 0, g.SEMI_TRANSPARENT);
                // TODO: remove tile
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

                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and isValidEdge(map.nodes.items[node_id].pos, target_pos) and !mouse_over_ui) {
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
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and !mouse_over_ui) {
                    self.active_node_id = node1.id;
                }
            } else {
                rl.DrawCircleV(mouse_pos, 10, ACTIVE_COLOR);
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and !mouse_over_ui) {
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
            // TODO: make it so that when selected it turns into .fill mode
            rl.DrawRectanglePro(.{ .x = mouse_pos.x, .y = mouse_pos.y, .width = g.TILE_SIZE, .height = g.TILE_SIZE }, .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 }, 0, g.SEMI_TRANSPARENT);
            if (self.active_tile_type) |active_tile_id| {
                const curr_tex = g.TILE_DEFINITIONS[active_tile_id];
                rl.DrawTexturePro(
                    tileset_texture,
                    curr_tex,
                    .{ .x = mouse_pos.x, .y = mouse_pos.y, .width = g.TILE_SIZE, .height = g.TILE_SIZE },
                    .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 },
                    0,
                    rl.WHITE,
                );

                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    self.start_pos = mouse_pos;
                }

                // FIXME: refactor that, make it dry
                if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT) and self.start_pos != null) {
                    self.end_pos = mouse_pos;

                    const min_x: usize = @intFromFloat(@min(self.start_pos.?.x, self.end_pos.?.x));
                    const max_x: usize = @intFromFloat(@max(self.start_pos.?.x, self.end_pos.?.x));
                    const min_y: usize = @intFromFloat(@min(self.start_pos.?.y, self.end_pos.?.y));
                    const max_y: usize = @intFromFloat(@max(self.start_pos.?.y, self.end_pos.?.y));

                    var y: usize = min_y;
                    while (y <= max_y) : (y += g.TILE_SIZE) {
                        var x: usize = min_x;
                        while (x <= max_x) : (x += g.TILE_SIZE) {
                            rl.DrawTexturePro(
                                tileset_texture,
                                curr_tex,
                                .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = g.TILE_SIZE, .height = g.TILE_SIZE },
                                .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 },
                                0,
                                g.SEMI_TRANSPARENT,
                            );
                        }
                    }
                }

                if (rl.IsMouseButtonReleased(rl.MOUSE_BUTTON_LEFT) and self.start_pos != null and self.end_pos != null) {
                    const min_x: usize = @intFromFloat(@min(self.start_pos.?.x, self.end_pos.?.x));
                    const max_x: usize = @intFromFloat(@max(self.start_pos.?.x, self.end_pos.?.x));
                    const min_y: usize = @intFromFloat(@min(self.start_pos.?.y, self.end_pos.?.y));
                    const max_y: usize = @intFromFloat(@max(self.start_pos.?.y, self.end_pos.?.y));

                    var y: usize = min_y;
                    while (y <= max_y) : (y += g.TILE_SIZE) {
                        var x: usize = min_x;
                        while (x <= max_x) : (x += g.TILE_SIZE) {
                            const row = y / g.TILE_SIZE;
                            const col = x / g.TILE_SIZE;
                            if (row < map.tiles.len and col < map.tiles[0].len) {
                                map.tiles[row][col] = active_tile_id;
                            }
                        }
                    }

                    self.start_pos = null;
                    self.end_pos = null;
                }
            }
        },
    }
}

pub fn drawGui(self: *Self, tileset_texture: rl.Texture2D) void {
    const sidebar_x = g.SCREEN_WIDTH - 200;
    const sidebar_y = 0;

    const sidebar_width = 200;
    const sidebar_height = g.SCREEN_HEIGHT;

    _ = rl.GuiPanel(
        .{ .x = sidebar_x, .y = sidebar_y, .width = sidebar_width, .height = sidebar_height },
        "Texture Selector",
    );

    var y_offset: f32 = 30;

    const mouse_screen_pos = rl.GetMousePosition();
    const cols = 3;
    var label_buf: [64]u8 = undefined;

    for (GROUPS, 0..) |group, group_idx| {
        const header_rect = rl.Rectangle{
            .x = sidebar_x + 10,
            .y = sidebar_y + y_offset,
            .width = sidebar_width - 20,
            .height = 20,
        };

        const arrow = if (self.group_expanded[group_idx]) "v" else ">";
        const label = std.fmt.bufPrintZ(&label_buf, "{} {s}", .{ group.type, arrow }) catch "error";
        if (rl.GuiButton(header_rect, label) == 1) {
            self.group_expanded[group_idx] = !self.group_expanded[group_idx];
        }
        y_offset += 25;

        if (self.group_expanded[group_idx]) {
            const rows = (group.tiles.len + cols - 1) / cols;
            for (group.tiles, 0..) |def, tile_i| {
                const global_i = switch (group_idx) {
                    0 => tile_i,
                    1 => g.TILES.len + tile_i,
                    else => 0,
                };

                const row = tile_i / cols;
                const col = tile_i % cols;

                const button_x = sidebar_x + 10 + @as(f32, @floatFromInt(col)) * 60;
                const button_y = sidebar_y + y_offset + @as(f32, @floatFromInt(row)) * 60;

                const button_rect = rl.Rectangle{ .x = button_x, .y = button_y, .width = 50, .height = 50 };

                const is_hovered = rl.CheckCollisionPointRec(mouse_screen_pos, button_rect);

                // thumbnail
                rl.DrawTexturePro(
                    tileset_texture,
                    def,
                    .{ .x = button_x + 5, .y = button_y + 5, .width = 40, .height = 40 },
                    .{ .x = 0, .y = 0 },
                    0,
                    rl.WHITE,
                );

                if (is_hovered and rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    self.active_tile_type = global_i;
                    self.active_group = group.type;
                }

                if (self.active_tile_type == global_i) {
                    rl.DrawRectangleLinesEx(button_rect, 2, rl.YELLOW);
                }
            }
            y_offset += @as(f32, @floatFromInt(rows)) * 60 + 5;
        }
    }
}
