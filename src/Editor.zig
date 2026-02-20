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

const TextureGroup = struct {
    type: Map.DrawMode,
    tiles: []const rl.Rectangle,
};

const GROUPS = [_]TextureGroup{
    .{ .type = .tiles, .tiles = g.TILES[0..] },
    .{ .type = .sprites, .tiles = g.SPRITES[0..] },
};

pub const State = enum {
    idle,
    eraser,
    roads,
    tiles,
    sprites,
};

const Hovered = union(enum) {
    none,
    node: *Map.Node,
    edge: *Map.Edge,
    tile: usize,
    sprite: *Map.Sprite,
};

const Self = @This();

state: State,

mouse_pos: rl.Vector2,
hovered: Hovered,

active_tile_type: ?usize,
active_node_id: ?usize,
active_group: Map.DrawMode,

group_expanded: [2]bool,
panel_expanded: bool,

start_pos: ?rl.Vector2,
end_pos: ?rl.Vector2,

pub fn init() Self {
    return .{
        .state = .idle,
        .active_node_id = null,
        .active_tile_type = null,
        .active_group = .all,
        .mouse_pos = rl.Vector2Zero(),
        .hovered = .none,
        .group_expanded = [_]bool{ true, true },
        .panel_expanded = true,
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
        if (rl.IsKeyPressed(rl.KEY_ONE)) {
            self.panel_expanded = !self.panel_expanded;
        } else if (rl.IsKeyPressed(rl.KEY_ESCAPE)) {
            self.active_node_id = null;
            self.active_group = .all;
            self.active_tile_type = null;
        } else if (rl.IsKeyPressed(rl.KEY_Q)) {
            self.state = .idle;
            self.active_group = .all;
            self.start_pos = null;
            self.end_pos = null;
        } else if (rl.IsKeyPressed(rl.KEY_E)) {
            self.state = .eraser;
            self.active_group = .all;
            self.start_pos = null;
            self.end_pos = null;
        } else if (rl.IsKeyPressed(rl.KEY_R)) {
            self.state = .roads;
            self.active_group = .road;
            self.start_pos = null;
            self.end_pos = null;
        } else if (rl.IsKeyPressed(rl.KEY_T)) {
            self.state = .tiles;
            self.active_group = .all;
            self.start_pos = null;
            self.end_pos = null;
        } else if (rl.IsKeyPressed(rl.KEY_G)) {
            self.state = .sprites;
            self.active_group = .sprites;
            self.start_pos = null;
            self.end_pos = null;
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

    const mouse_screen_pos = rl.GetMousePosition();

    const sidebar_width: f32 = if (self.panel_expanded) 200 else 30;
    const sidebar_rect = rl.Rectangle{ .x = g.SCREEN_WIDTH - sidebar_width, .y = 0, .width = sidebar_width, .height = g.SCREEN_HEIGHT };

    const mouse_world_pos = rl.GetScreenToWorld2D(mouse_screen_pos, camera.*);
    const mouse_over_ui = rl.CheckCollisionPointRec(mouse_screen_pos, sidebar_rect);

    self.mouse_pos = snapToGrid(mouse_world_pos);
    self.hovered = if (!mouse_over_ui) self.detectHover(map) else .none;

    if (self.active_group != .road and self.active_group != .sprites and rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
        self.start_pos = self.mouse_pos;
        self.active_group = switch (self.hovered) {
            .edge, .node => .all,
            .tile, .none, .sprite => .tiles,
        };
    }
    if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT) and self.start_pos != null) {
        self.end_pos = self.mouse_pos;
    }

    try self.handleState(map, camera);
}

pub fn draw(self: *Self, camera: *rl.Camera2D, map: *Map, is_debug: bool) !void {
    rl.BeginMode2D(camera.*);
    {
        try self.drawWorld(camera, map, is_debug);
        self.drawEditorIndicators(camera, map);
    }
    rl.EndMode2D();

    self.drawGui(map.tileset.texture);
}

fn hoveredNode(self: *const Self, nodes: []Map.Node) ?*Map.Node {
    // TODO: use quad tree in the future, probably
    for (nodes) |*node| {
        if (!node.active) continue;
        if (rl.CheckCollisionPointCircle(self.mouse_pos, node.pos, 10)) {
            return node;
        }
    }
    return null;
}

fn hoveredEdge(self: *const Self, nodes: []Map.Node, edges: []Map.Edge) ?*Map.Edge {
    for (edges) |*edge| {
        const node1 = &nodes[edge.from];
        const node2 = &nodes[edge.to];

        if (!node1.active or !node2.active) continue;
        if (node1.id > node2.id) continue;

        if (rl.CheckCollisionPointLine(self.mouse_pos, node1.pos, node2.pos, 10)) {
            return edge;
        }
    }
    return null;
}

fn hoveredTile(self: *const Self, tiles: Map.TileMap) ?usize {
    const mx: i32 = @intFromFloat(self.mouse_pos.x);
    const my: i32 = @intFromFloat(self.mouse_pos.y);
    const col = @divFloor(mx, g.TILE_SIZE);
    const row = @divFloor(my, g.TILE_SIZE);
    if (row >= 0 and col >= 0 and row < tiles.len and col < tiles[0].len) {
        const tile_id = tiles[@intCast(row)][@intCast(col)];
        if (tile_id != 0) {
            return tile_id;
        }
    }
    return null;
}

fn hoveredSprite(self: *const Self, sprites: []Map.Sprite) ?*Map.Sprite {
    for (sprites) |*sprite| {
        const sprite_rect = g.SPRITES[sprite.sprite_id];
        const dest_rect = rl.Rectangle{
            .x = sprite.pos.x - sprite_rect.width / 2,
            .y = sprite.pos.y - sprite_rect.height / 2,
            .width = sprite_rect.width,
            .height = sprite_rect.height,
        };
        if (rl.CheckCollisionPointRec(self.mouse_pos, dest_rect)) {
            return sprite;
        }
    }
    return null;
}

fn detectHover(self: *const Self, map: *const Map) Hovered {
    if (self.active_group == .all or self.active_group == .sprites) {
        if (self.hoveredSprite(map.sprites.items)) |sprite| {
            return .{ .sprite = sprite };
        }
    }
    if (self.active_group == .all or self.active_group == .road) {
        if (self.hoveredNode(map.nodes.items)) |node| {
            return .{ .node = node };
        }
        if (self.hoveredEdge(map.nodes.items, map.edges.items)) |edge| {
            return .{ .edge = edge };
        }
    }
    if (self.active_group == .all or self.active_group == .tiles) {
        if (self.hoveredTile(map.tiles)) |tile_id| {
            return .{ .tile = tile_id };
        }
    }
    return .none;
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

fn handleState(self: *Self, map: *Map, camera: *rl.Camera2D) !void {
    switch (self.state) {
        .idle => {},
        .eraser => {
            self.active_node_id = null;
            switch (self.hovered) {
                .sprite => {
                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                        const sprite_ptr = self.hovered.sprite;
                        const sprite_idx = (@intFromPtr(sprite_ptr) - @intFromPtr(map.sprites.items.ptr)) / @sizeOf(Map.Sprite);
                        _ = map.sprites.orderedRemove(sprite_idx);
                        self.hovered = .none;
                        self.start_pos = null;
                        self.end_pos = null;
                        self.active_group = .all;
                    }
                },
                .node => {
                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                        self.hovered.node.active = false;
                        map.removeAllEdgesToNode(self.hovered.node.id);
                        self.start_pos = null;
                        self.end_pos = null;
                        self.active_group = .all;
                    }
                },
                .edge => {
                    const node1 = &map.nodes.items[self.hovered.edge.from];
                    const node2 = &map.nodes.items[self.hovered.edge.to];
                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                        map.removeEdge(node1, node2);
                        self.hovered = .none;
                        self.start_pos = null;
                        self.end_pos = null;
                        self.active_group = .all;
                    }
                },
                .none, .tile => {
                    if (rl.IsMouseButtonReleased(rl.MOUSE_BUTTON_LEFT) and self.start_pos != null and self.end_pos != null) {
                        var iterCells = Map.CellIterator.init(&self.start_pos.?, &self.end_pos.?);
                        while (iterCells.next()) |*cell| {
                            const row = @divFloor(cell.y, g.TILE_SIZE);
                            const col = @divFloor(cell.x, g.TILE_SIZE);
                            if (row >= 0 and col >= 0 and row < map.tiles.len and col < map.tiles[0].len) {
                                map.tiles[@intFromFloat(row)][@intFromFloat(col)] = 0;
                            }
                        }
                        self.start_pos = null;
                        self.end_pos = null;
                        self.active_group = .all;
                    }
                },
            }
        },
        .roads => {
            if (map.nodes.items.len >= g.MAX_NODES) {
                return;
            }
            if (self.active_node_id) |node_id| {
                var active_node = &map.nodes.items[node_id];
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and isValidEdge(active_node.pos, self.mouse_pos)) {
                    var new_node = if (self.hovered == .node) self.hovered.node else null;
                    if (new_node == null) {
                        new_node = try map.createNode(self.mouse_pos);
                        if (self.hovered == .edge) {
                            const node1 = &map.nodes.items[self.hovered.edge.from];
                            const node2 = &map.nodes.items[self.hovered.edge.to];
                            try map.splitEdge(node1, node2, new_node.?);
                        }
                    }
                    active_node = &map.nodes.items[node_id];
                    try map.connectNodes(active_node, new_node.?);
                    self.active_node_id = new_node.?.id;
                }
            } else if (self.hovered == .node) { // add to existing node
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    self.active_node_id = self.hovered.node.id;
                }
                if (rl.IsKeyPressed(rl.KEY_TAB)) {
                    const node_id = self.hovered.node.id;
                    const curr_type = self.hovered.node.type;
                    const next_type: Map.NodeType = switch (curr_type) {
                        .default => .start,
                        .start => .end,
                        .end => .default,
                    };

                    switch (curr_type) {
                        .start => _ = map.start_nodes.swapRemove(node_id),
                        .end => _ = map.end_nodes.swapRemove(node_id),
                        .default => {},
                    }
                    switch (next_type) {
                        .start => try map.start_nodes.put(node_id, {}),
                        .end => try map.end_nodes.put(node_id, {}),
                        .default => {},
                    }

                    self.hovered.node.type = next_type;
                }
            } else {
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    const new_node = try map.createNode(self.mouse_pos);
                    if (self.hovered == .edge) {
                        const node1 = &map.nodes.items[self.hovered.edge.from];
                        const node2 = &map.nodes.items[self.hovered.edge.to];
                        try map.splitEdge(node1, node2, new_node);
                    }
                    self.active_node_id = new_node.id;
                }
            }
        },
        .tiles => {
            if (self.active_tile_type) |active_tile_id| {
                if (rl.IsMouseButtonReleased(rl.MOUSE_BUTTON_LEFT) and self.start_pos != null and self.end_pos != null) {
                    var iterCells = Map.CellIterator.init(&self.start_pos.?, &self.end_pos.?);
                    while (iterCells.next()) |*cell| {
                        const row = @divFloor(cell.y, g.TILE_SIZE);
                        const col = @divFloor(cell.x, g.TILE_SIZE);
                        if (row >= 0 and col >= 0 and row < map.tiles.len and col < map.tiles[0].len) {
                            map.tiles[@intFromFloat(row)][@intFromFloat(col)] = active_tile_id;
                        }
                    }
                    self.start_pos = null;
                    self.end_pos = null;
                }
            } else if (rl.IsMouseButtonReleased(rl.MOUSE_BUTTON_LEFT) and self.start_pos != null and self.end_pos != null) {
                // TODO: figure out better way to avoid repetition
                self.start_pos = null;
                self.end_pos = null;
            }
        },
        .sprites => {
            if (self.active_tile_type) |active_tile_id| {
                if (active_tile_id >= g.TILES.len and rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    const mouse_world_pos = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera.*);
                    const sprite_id = active_tile_id - g.TILES.len;
                    const sprite = Map.Sprite.init(mouse_world_pos, sprite_id);
                    try map.sprites.append(sprite);
                }
            }
        },
    }
}

fn drawCellHighlight(pos: *const rl.Vector2) void {
    rl.DrawRectanglePro(
        .{ .x = pos.x, .y = pos.y, .width = g.TILE_SIZE, .height = g.TILE_SIZE },
        .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 },
        0,
        g.SEMI_TRANSPARENT,
    );
}

fn drawEditorIndicators(self: *const Self, camera: *const rl.Camera2D, map: *const Map) void {
    drawCellHighlight(&self.mouse_pos);

    switch (self.state) {
        .idle => {},
        .eraser => {
            switch (self.hovered) {
                .sprite => {
                    const sprite_rect = g.SPRITES[self.hovered.sprite.sprite_id];
                    const dest_rect = rl.Rectangle{
                        .x = self.hovered.sprite.pos.x - sprite_rect.width / 2,
                        .y = self.hovered.sprite.pos.y - sprite_rect.height / 2,
                        .width = sprite_rect.width,
                        .height = sprite_rect.height,
                    };
                    rl.DrawRectangleRec(dest_rect, g.SEMI_TRANSPARENT);
                },
                .node => {},
                .edge => {
                    const node1 = &map.nodes.items[self.hovered.edge.from];
                    const node2 = &map.nodes.items[self.hovered.edge.to];
                    var iterCells = Map.CellIterator.init(&node1.pos, &node2.pos);
                    while (iterCells.next()) |*cell| {
                        drawCellHighlight(cell);
                    }
                },
                .none, .tile => {
                    if (self.start_pos != null and self.end_pos != null) {
                        var iterCells = Map.CellIterator.init(&self.start_pos.?, &self.end_pos.?);
                        while (iterCells.next()) |*cell| {
                            drawCellHighlight(cell);
                        }
                    }
                },
            }
        },
        .roads => {
            if (self.active_node_id) |node_id| {
                const active_node = map.nodes.items[node_id];
                drawCellHighlight(&active_node.pos);
                if (isValidEdge(active_node.pos, self.mouse_pos)) {
                    var iterCells = Map.CellIterator.init(&active_node.pos, &self.mouse_pos);
                    while (iterCells.next()) |*cell| {
                        drawCellHighlight(cell);
                    }
                }
            }
        },
        .tiles => {
            if (self.start_pos != null and self.end_pos != null) {
                var iterCells = Map.CellIterator.init(&self.start_pos.?, &self.end_pos.?);
                while (iterCells.next()) |*cell| {
                    drawCellHighlight(cell);
                }
            }
            if (self.active_tile_type) |active_tile_id| {
                if (active_tile_id < g.TILES.len) {
                    const rect = g.TILES[active_tile_id];
                    const mouse_world_pos = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera.*);
                    rl.DrawTexturePro(
                        map.tileset.texture,
                        rect,
                        .{
                            .x = mouse_world_pos.x,
                            .y = mouse_world_pos.y,
                            .width = rect.width,
                            .height = rect.height,
                        },
                        .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 },
                        0,
                        g.SEMI_TRANSPARENT,
                    );
                }
            }
        },
        .sprites => {
            if (self.active_tile_type) |active_tile_id| {
                if (active_tile_id >= g.TILES.len) {
                    const sprite_id = active_tile_id - g.TILES.len;
                    const rect = g.SPRITES[sprite_id];
                    const mouse_world_pos = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera.*);
                    rl.DrawTexturePro(
                        map.tileset.texture,
                        rect,
                        .{
                            .x = mouse_world_pos.x,
                            .y = mouse_world_pos.y,
                            .width = rect.width,
                            .height = rect.height,
                        },
                        .{ .x = rect.width / 2, .y = rect.height / 2 },
                        0,
                        g.SEMI_TRANSPARENT,
                    );
                }
            }
        },
    }
}

fn drawWorld(self: *Self, camera: *rl.Camera2D, map: *Map, is_debug: bool) !void {
    map.drawTiles(self.active_group);
    map.drawRoads(self.active_group);
    map.drawSprites(self.active_group);
    if (is_debug) {
        map.drawDebug();
    }

    const world_min_x = camera.target.x - camera.offset.x / camera.zoom;
    const world_max_x = camera.target.x + (g.SCREEN_WIDTH - camera.offset.x) / camera.zoom;
    const world_min_y = camera.target.y - camera.offset.y / camera.zoom;
    const world_max_y = camera.target.y + (g.SCREEN_HEIGHT - camera.offset.y) / camera.zoom;

    var grid_x = @floor(world_min_x / g.TILE_SIZE) * g.TILE_SIZE - g.TILE_SIZE / 2;
    while (grid_x <= world_max_x) : (grid_x += g.TILE_SIZE) {
        const pos_from = rl.Vector2{ .x = grid_x, .y = world_min_y };
        const pos_to = rl.Vector2{ .x = grid_x, .y = world_max_y };
        const thickness: f32 = if (grid_x == -g.TILE_SIZE / 2) LINE_THICKNESS else 2.0;
        rl.DrawLineEx(pos_from, pos_to, thickness, GRID_COLOR);
    }
    var grid_y = @floor(world_min_y / g.TILE_SIZE) * g.TILE_SIZE - g.TILE_SIZE / 2;
    while (grid_y <= world_max_y) : (grid_y += g.TILE_SIZE) {
        const pos_from = rl.Vector2{ .x = world_min_x, .y = grid_y };
        const pos_to = rl.Vector2{ .x = world_max_x, .y = grid_y };
        const thickness: f32 = if (grid_y == -g.TILE_SIZE / 2) LINE_THICKNESS else 2.0;
        rl.DrawLineEx(pos_from, pos_to, thickness, GRID_COLOR);
    }
}

fn drawGui(self: *Self, tileset_texture: rl.Texture2D) void {
    const sidebar_width: f32 = if (self.panel_expanded) 200 else 30;
    const sidebar_x = g.SCREEN_WIDTH - sidebar_width;
    const sidebar_y = 0;

    const sidebar_height = g.SCREEN_HEIGHT;

    if (self.panel_expanded) {
        _ = rl.GuiPanel(
            .{ .x = sidebar_x, .y = sidebar_y, .width = sidebar_width, .height = sidebar_height },
            "Texture Selector",
        );

        const toggle_rect = rl.Rectangle{
            .x = sidebar_x + 5,
            .y = sidebar_y + 5,
            .width = 25,
            .height = 20,
        };
        if (rl.GuiButton(toggle_rect, "<<") == 1) {
            self.panel_expanded = false;
        }

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
                        if (group.type == .sprites) {
                            self.state = .sprites;
                        } else if (self.state == .sprites) {
                            self.state = .tiles;
                        }
                    }

                    if (self.active_tile_type == global_i) {
                        rl.DrawRectangleLinesEx(button_rect, 2, rl.YELLOW);
                    }
                }
                y_offset += @as(f32, @floatFromInt(rows)) * 60 + 5;
            }
        }
    } else {
        const toggle_rect = rl.Rectangle{
            .x = sidebar_x + 2,
            .y = sidebar_y + g.SCREEN_HEIGHT / 2 - 10,
            .width = 26,
            .height = 20,
        };
        if (rl.GuiButton(toggle_rect, ">>") == 1) {
            self.panel_expanded = true;
        }
    }
}
