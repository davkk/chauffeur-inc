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
panel_expanded: bool,

start_pos: ?rl.Vector2,
end_pos: ?rl.Vector2,

fn hoveredNode(mouse_pos: rl.Vector2, nodes: []Map.Node) ?*Map.Node {
    // TODO: use quad tree in the future, probably
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
        for (node1.edges) |edge_id| {
            if (edge_id == null) continue;
            if (node1.id > edge_id.?) continue;

            const node2 = &nodes[edge_id.?];
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
        if (rl.IsKeyPressed(rl.KEY_TAB) or rl.IsKeyPressed(rl.KEY_H)) {
            self.panel_expanded = !self.panel_expanded;
        } else if (rl.IsKeyPressed(rl.KEY_ESCAPE)) {
            self.active_node_id = null;
            self.active_group = .none;
            self.active_tile_type = null;
        } else if (rl.IsKeyPressed(rl.KEY_V)) {
            self.state = .idle;
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

fn getDirection(dx: f32, dy: f32) ?g.Direction {
    if (dy < 0) return .up;
    if (dx > 0) return .right;
    if (dy > 0) return .down;
    if (dx < 0) return .left;
    return null;
}

fn createNode(map: *Map, pos: rl.Vector2) !*Map.Node {
    const node = Map.Node.init(pos, map.nodes.items.len);
    try map.nodes.append(node);
    return &map.nodes.items[map.nodes.items.len - 1];
}

fn connectNodes(node1: *Map.Node, node2: *Map.Node) void {
    const dx = node2.pos.x - node1.pos.x;
    const dy = node2.pos.y - node1.pos.y;
    const dir = getDirection(dx, dy) orelse return;

    const dir_idx: usize = @intFromEnum(dir);
    const opposite_idx: usize = (dir_idx + 2) % 4;

    if (node1.edges[dir_idx] != null or node2.edges[opposite_idx] != null) {
        return;
    }

    node1.edges[dir_idx] = node2.id;
    node2.edges[opposite_idx] = node1.id;
}

fn splitEdge(a: *Map.Node, b: *Map.Node, new_node: *Map.Node) void {
    const dx = b.pos.x - a.pos.x;
    const dy = b.pos.y - a.pos.y;
    const dir = getDirection(dx, dy) orelse return;

    const dir_idx: usize = @intFromEnum(dir);
    const opposite_idx: usize = (dir_idx + 2) % 4;

    a.edges[dir_idx] = null;
    b.edges[opposite_idx] = null;

    a.edges[dir_idx] = new_node.id;
    b.edges[opposite_idx] = new_node.id;
    new_node.edges[opposite_idx] = a.id;
    new_node.edges[dir_idx] = b.id;
}

fn removeEdge(node1: *Map.Node, node2: *Map.Node) void {
    for (node1.edges, 0..) |edge_id, idx| {
        if (edge_id) |id| {
            if (id == node2.id) {
                node1.edges[idx] = null;
                break;
            }
        }
    }
    for (node2.edges, 0..) |edge_id, idx| {
        if (edge_id) |id| {
            if (id == node1.id) {
                node2.edges[idx] = null;
                break;
            }
        }
    }
}

fn removeAllEdgesToNode(node_id: usize, nodes: []Map.Node) void {
    for (nodes) |*node| {
        if (!node.active) continue;
        if (node.id == node_id) continue;
        for (node.edges, 0..) |edge_id, idx| {
            if (edge_id == node_id) {
                node.edges[idx] = null;
            }
        }
    }
}

fn drawWorld(self: *Self, camera: *rl.Camera2D, map: *Map, tileset_texture: rl.Texture2D, is_debug: bool) !void {
    // draw grid
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

    const mouse_screen_pos = rl.GetMousePosition();
    const sidebar_width: f32 = if (self.panel_expanded) 200 else 30;
    const sidebar_rect = rl.Rectangle{ .x = g.SCREEN_WIDTH - sidebar_width, .y = 0, .width = sidebar_width, .height = g.SCREEN_HEIGHT };
    const mouse_over_ui = rl.CheckCollisionPointRec(mouse_screen_pos, sidebar_rect);

    const mouse_world_pos = rl.GetScreenToWorld2D(mouse_screen_pos, camera.*);
    const mouse_pos = snapToGrid(mouse_world_pos);

    map.draw(self.active_group, is_debug);

    // TODO: move that switch to separate function
    switch (self.state) {
        .idle => {},
        .eraser => {
            self.active_node_id = null;

            if (hoveredNode(mouse_pos, map.nodes.items)) |node1| {
                rl.DrawCircleV(node1.pos, 10, ACTIVE_COLOR);
                if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT) and !mouse_over_ui) {
                    node1.active = false;
                    removeAllEdgesToNode(node1.id, map.nodes.items);
                }
            }

            if (hoveredEdge(mouse_pos, map.nodes.items)) |edge| {
                const node1, const node2 = edge;
                rl.DrawLineEx(node1.pos, node2.pos, LINE_THICKNESS, ACTIVE_COLOR);
                if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT) and !mouse_over_ui) {
                    removeEdge(node1, node2);
                }
            }

            if (hoveredTile(mouse_pos, map.tiles)) |_| {
                rl.DrawRectanglePro(
                    .{ .x = mouse_pos.x, .y = mouse_pos.y, .width = g.TILE_SIZE, .height = g.TILE_SIZE },
                    .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 },
                    0,
                    g.SEMI_TRANSPARENT,
                );
                if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT) and !mouse_over_ui) {
                    const mx: i32 = @intFromFloat(mouse_pos.x);
                    const my: i32 = @intFromFloat(mouse_pos.y);
                    const col = @divFloor(mx, g.TILE_SIZE);
                    const row = @divFloor(my, g.TILE_SIZE);
                    if (row >= 0 and col >= 0 and row < map.tiles.len and col < map.tiles[0].len) {
                        map.tiles[@intCast(row)][@intCast(col)] = 0;
                    }
                }
            }
        },
        .add_node => {
            if (self.active_node_id) |node_id| {
                var active_node = &map.nodes.items[node_id];
                rl.DrawLineEx(
                    active_node.pos,
                    mouse_pos,
                    LINE_THICKNESS,
                    if (isValidEdge(active_node.pos, mouse_pos)) ACTIVE_COLOR else BAD_COLOR,
                );
                rl.DrawCircleV(mouse_pos, 10, ACTIVE_COLOR);

                if (!mouse_over_ui and rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and isValidEdge(active_node.pos, mouse_pos)) {
                    var new_node: ?*Map.Node = if (hoveredNode(mouse_pos, map.nodes.items)) |node2| node2 else null;
                    if (new_node == null) {
                        new_node = try createNode(map, mouse_pos);
                        if (hoveredEdge(mouse_pos, map.nodes.items)) |split_edge| {
                            const a, const b = split_edge;
                            splitEdge(a, b, new_node.?);
                        }
                    }
                    active_node = &map.nodes.items[node_id]; // re-lookup active node after append to nodes ArrayList
                    connectNodes(active_node, new_node.?);
                    self.active_node_id = new_node.?.id;
                }
            } else if (hoveredNode(mouse_pos, map.nodes.items)) |node1| { // add to existing node
                rl.DrawCircleV(node1.pos, 10, ACTIVE_COLOR);
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and !mouse_over_ui) {
                    self.active_node_id = node1.id;
                }
            } else {
                rl.DrawCircleV(mouse_pos, 10, ACTIVE_COLOR);
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and !mouse_over_ui) {
                    const new_node = try createNode(map, mouse_pos);
                    if (hoveredEdge(mouse_pos, map.nodes.items)) |split_edge| {
                        const a, const b = split_edge;
                        splitEdge(a, b, new_node);
                    }
                    self.active_node_id = new_node.id;
                }
            }
        },
        .fill => {
            rl.DrawRectanglePro(.{ .x = mouse_pos.x, .y = mouse_pos.y, .width = g.TILE_SIZE, .height = g.TILE_SIZE }, .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 }, 0, g.SEMI_TRANSPARENT);
            if (self.active_tile_type) |active_tile_id| {
                if (self.active_group == .sprites) {
                    const sprite_id = active_tile_id - g.TILES.len;
                    const curr_tex = g.SPRITES[sprite_id];

                    rl.DrawTexturePro(
                        tileset_texture,
                        curr_tex,
                        .{ .x = mouse_world_pos.x, .y = mouse_world_pos.y, .width = curr_tex.width, .height = curr_tex.height },
                        .{ .x = curr_tex.width / 2, .y = curr_tex.height / 2 },
                        0,
                        g.SEMI_TRANSPARENT,
                    );

                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and !mouse_over_ui) {
                        const sprite = Map.Sprite.init(mouse_world_pos, sprite_id);
                        try map.sprites.append(sprite);
                    }
                } else {
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

                    if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT) and self.start_pos != null) {
                        self.end_pos = mouse_pos;

                        const min_x: i64 = @intFromFloat(@min(self.start_pos.?.x, self.end_pos.?.x));
                        const max_x: i64 = @intFromFloat(@max(self.start_pos.?.x, self.end_pos.?.x));
                        const min_y: i64 = @intFromFloat(@min(self.start_pos.?.y, self.end_pos.?.y));
                        const max_y: i64 = @intFromFloat(@max(self.start_pos.?.y, self.end_pos.?.y));

                        var y = min_y;
                        while (y <= max_y) : (y += g.TILE_SIZE) {
                            var x = min_x;
                            while (x <= max_x) : (x += g.TILE_SIZE) {
                                rl.DrawTexturePro(
                                    tileset_texture,
                                    curr_tex,
                                    .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = curr_tex.width, .height = curr_tex.height },
                                    .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 },
                                    0,
                                    g.SEMI_TRANSPARENT,
                                );
                            }
                        }
                    }

                    if (rl.IsMouseButtonReleased(rl.MOUSE_BUTTON_LEFT) and self.start_pos != null and self.end_pos != null) {
                        const min_x: i64 = @intFromFloat(@min(self.start_pos.?.x, self.end_pos.?.x));
                        const max_x: i64 = @intFromFloat(@max(self.start_pos.?.x, self.end_pos.?.x));
                        const min_y: i64 = @intFromFloat(@min(self.start_pos.?.y, self.end_pos.?.y));
                        const max_y: i64 = @intFromFloat(@max(self.start_pos.?.y, self.end_pos.?.y));

                        var y = min_y;
                        while (y <= max_y) : (y += g.TILE_SIZE) {
                            var x = min_x;
                            while (x <= max_x) : (x += g.TILE_SIZE) {
                                const row = @divFloor(y, g.TILE_SIZE);
                                const col = @divFloor(x, g.TILE_SIZE);
                                if (row >= 0 and col >= 0 and row < map.tiles.len and col < map.tiles[0].len) {
                                    map.tiles[@intCast(row)][@intCast(col)] = active_tile_id;
                                }
                            }
                        }

                        self.start_pos = null;
                        self.end_pos = null;
                    }
                }
            }
        },
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

pub fn draw(self: *Self, camera: *rl.Camera2D, map: *Map, is_debug: bool) !void {
    rl.BeginMode2D(camera.*);
    {
        try self.drawWorld(camera, map, map.tileset.texture, is_debug);
    }
    rl.EndMode2D();

    self.drawGui(map.tileset.texture);
}
