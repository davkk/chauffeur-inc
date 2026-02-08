const std = @import("std");

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const Tileset = @import("Tileset.zig");

pub const DrawMode = enum {
    all,
    tiles,
    road,
    sprites,
};

const FILE_NAME = "src/assets/map.map";

pub const TileMap = [g.SCREEN_HEIGHT / g.TILE_SIZE][g.SCREEN_WIDTH / g.TILE_SIZE]usize;

const Self = @This();

pub const NodeType = enum { default, start, end };

pub const Node = struct {
    active: bool,
    type: NodeType,
    id: usize,
    pos: rl.Vector2,
    edges: [4]?usize,

    pub fn init(pos: rl.Vector2, id: usize) Node {
        return Node{
            .active = true,
            .type = .default,
            .id = id,
            .pos = pos,
            .edges = .{ null, null, null, null },
        };
    }
};

pub const Edge = struct {
    from: usize,
    to: usize,
};

pub const Sprite = struct {
    pos: rl.Vector2,
    sprite_id: usize,

    pub fn init(pos: rl.Vector2, sprite_id: usize) Sprite {
        return Sprite{
            .pos = pos,
            .sprite_id = sprite_id,
        };
    }
};

pub const CellIterator = struct {
    min_x: i64,
    max_x: i64,
    min_y: i64,
    max_y: i64,
    current_y: i64,
    current_x: i64,

    pub fn init(start: *const rl.Vector2, end: *const rl.Vector2) @This() {
        const min_x: i64 = @intFromFloat(@min(start.x, end.x));
        const max_x: i64 = @intFromFloat(@max(start.x, end.x));
        const min_y: i64 = @intFromFloat(@min(start.y, end.y));
        const max_y: i64 = @intFromFloat(@max(start.y, end.y));
        return .{
            .min_x = min_x,
            .max_x = max_x,
            .min_y = min_y,
            .max_y = max_y,
            .current_y = min_y,
            .current_x = min_x - g.TILE_SIZE,
        };
    }

    pub fn next(self: *@This()) ?rl.Vector2 {
        self.current_x += g.TILE_SIZE;
        if (self.current_x > self.max_x) {
            self.current_x = self.min_x;
            self.current_y += g.TILE_SIZE;
            if (self.current_y > self.max_y) return null;
        }
        return .{ .x = @floatFromInt(self.current_x), .y = @floatFromInt(self.current_y) };
    }
};

alloc: std.mem.Allocator,

road_texture: [3]rl.Texture2D,
tileset: Tileset,

tiles: TileMap,
nodes: std.array_list.Managed(Node),
edges: std.array_list.Managed(Edge),
sprites: std.array_list.Managed(Sprite),

start_nodes: std.AutoArrayHashMap(usize, void),
end_nodes: std.AutoArrayHashMap(usize, void),

pub fn init(alloc: std.mem.Allocator) !Self {
    const tileset = Tileset.init();

    var road_texture: [3]rl.Texture2D = .{ .{}, .{}, .{} };
    for (0..2) |idx| {
        var image = rl.LoadImageFromTexture(tileset.texture);
        rl.ImageCrop(&image, .{
            .x = @floatFromInt(idx * g.TILE_SIZE),
            .y = 0,
            .width = g.TILE_SIZE,
            .height = g.TILE_SIZE,
        });
        road_texture[idx] = rl.LoadTextureFromImage(image);
        rl.SetTextureWrap(road_texture[idx], rl.TEXTURE_WRAP_REPEAT);
    }
    var node_image = rl.LoadImageFromTexture(tileset.texture);
    rl.ImageCrop(&node_image, .{
        .x = 0,
        .y = g.TILE_SIZE,
        .width = 2 * g.TILE_SIZE,
        .height = 2 * g.TILE_SIZE,
    });
    road_texture[2] = rl.LoadTextureFromImage(node_image);

    const loaded = try loadFromFile(alloc);

    return .{
        .alloc = alloc,
        .tileset = tileset,
        .road_texture = road_texture,
        .tiles = loaded.tiles,
        .nodes = std.array_list.Managed(Node).fromOwnedSlice(alloc, loaded.nodes),
        .edges = std.array_list.Managed(Edge).fromOwnedSlice(alloc, loaded.edges),
        .sprites = std.array_list.Managed(Sprite).fromOwnedSlice(alloc, loaded.sprites),
        .start_nodes = loaded.start_nodes,
        .end_nodes = loaded.end_nodes,
    };
}

pub fn deinit(self: *const Self) void {
    for (self.road_texture) |road| rl.UnloadTexture(road);
    rl.UnloadTexture(self.tileset.texture);

    self.nodes.deinit();
    self.sprites.deinit();
}

pub fn drawTiles(self: *Self, draw_mode: DrawMode) void {
    for (0..self.tiles.len) |tile_y| {
        for (0..self.tiles[0].len) |tile_x| {
            const tile_id = self.tiles[tile_y][tile_x];
            if (tile_id == 0) continue;
            const rect = g.TILE_DEFINITIONS[tile_id];
            rl.DrawTexturePro(
                self.tileset.texture,
                rect,
                .{
                    .x = @floatFromInt(tile_x * g.TILE_SIZE),
                    .y = @floatFromInt(tile_y * g.TILE_SIZE),
                    .width = rect.width,
                    .height = rect.height,
                },
                .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 },
                0,
                if (draw_mode == .all or draw_mode == .tiles) rl.WHITE else g.SEMI_TRANSPARENT,
            );
        }
    }
}

pub fn drawRoads(self: *Self, draw_mode: DrawMode) void {
    // draw nodes
    for (self.nodes.items) |*node1| {
        if (!node1.active) continue;
        rl.DrawTexturePro(
            self.road_texture[2],
            .{ .x = 0, .y = 0, .width = 2 * g.TILE_SIZE, .height = 2 * g.TILE_SIZE },
            .{ .x = node1.pos.x, .y = node1.pos.y, .width = 2 * g.TILE_SIZE, .height = 2 * g.TILE_SIZE },
            .{ .x = g.TILE_SIZE, .y = g.TILE_SIZE },
            0,
            if (draw_mode == .all or draw_mode == .road) rl.WHITE else g.SEMI_TRANSPARENT,
        );
    }
    // draw edges
    const road_color = if (draw_mode == .all or draw_mode == .road) rl.WHITE else g.SEMI_TRANSPARENT;
    for (self.nodes.items) |*node1| {
        if (!node1.active) continue;

        for (node1.edges) |edge_id| {
            if (edge_id == null) continue;

            const node2 = &self.nodes.items[edge_id.?];
            if (!node2.active or node1.id > node2.id) continue;

            const dx = @abs(@round(node1.pos.x - node2.pos.x));
            const dy = @abs(@round(node2.pos.y - node1.pos.y));

            const mid_x = (node1.pos.x + node2.pos.x) / 2.0;
            const mid_y = (node1.pos.y + node2.pos.y) / 2.0;
            const length = (if (dx > dy) dx else dy) - 2; // to avoid overlap at junctions

            const angle: f32 = if (dx == 0) 0 else 90;
            const offset_x: f32 = if (dx == 0) g.TILE_SIZE else 0;
            const offset_y: f32 = if (dy == 0) g.TILE_SIZE else 0;

            // road left
            rl.DrawTexturePro(
                self.road_texture[0],
                .{ .x = g.TILE_SIZE, .y = 0, .width = g.TILE_SIZE, .height = length },
                .{ .x = mid_x - offset_x, .y = mid_y - offset_y, .width = g.TILE_SIZE, .height = length },
                .{ .x = g.TILE_SIZE / 2, .y = length / 2 },
                angle,
                road_color,
            );

            // road line
            rl.DrawTexturePro(
                self.road_texture[1],
                .{ .x = g.TILE_SIZE, .y = 0, .width = g.TILE_SIZE, .height = length },
                .{ .x = mid_x, .y = mid_y, .width = g.TILE_SIZE, .height = length },
                .{ .x = g.TILE_SIZE / 2, .y = length / 2 },
                angle,
                road_color,
            );

            // road right
            rl.DrawTexturePro(
                self.road_texture[0],
                .{ .x = g.TILE_SIZE, .y = 0, .width = g.TILE_SIZE, .height = length },
                .{ .x = mid_x + offset_x, .y = mid_y + offset_y, .width = g.TILE_SIZE, .height = length },
                .{ .x = g.TILE_SIZE / 2, .y = length / 2 },
                angle + 180,
                road_color,
            );
        }
    }
}

pub fn drawSprites(self: *Self, draw_mode: DrawMode) void {
    for (self.sprites.items) |sprite| {
        const rect = g.SPRITES[sprite.sprite_id];
        rl.DrawTexturePro(
            self.tileset.texture,
            rect,
            .{
                .x = sprite.pos.x,
                .y = sprite.pos.y,
                .width = rect.width,
                .height = rect.height,
            },
            .{ .x = rect.width / 2, .y = rect.height / 2 },
            0,
            if (draw_mode == .all or draw_mode == .sprites) rl.WHITE else g.SEMI_TRANSPARENT,
        );
    }
}

pub fn drawDebug(self: *Self) void {
    for (self.nodes.items) |*node| {
        if (!node.active) continue;

        switch (node.type) {
            .start, .end => {
                rl.DrawCircleV(
                    .{ .x = node.pos.x, .y = node.pos.y },
                    g.TILE_SIZE / 2.0,
                    if (node.type == .start) rl.RED else rl.BLUE,
                );
            },
            else => {},
        }

        var buf: [8]u8 = undefined;
        const id_str = std.fmt.bufPrintZ(&buf, "{d}", .{node.id}) catch "??";
        rl.DrawText(@ptrCast(id_str), @intFromFloat(node.pos.x), @intFromFloat(node.pos.y), 20, rl.BLACK);
    }
}

fn getDirection(dx: f32, dy: f32) ?g.Direction {
    if (dy < 0) return .up;
    if (dx > 0) return .right;
    if (dy > 0) return .down;
    if (dx < 0) return .left;
    return null;
}

pub fn createNode(self: *Self, pos: rl.Vector2) !*Node {
    const node = Node.init(pos, self.nodes.items.len);
    try self.nodes.append(node);
    return &self.nodes.items[self.nodes.items.len - 1];
}

pub fn connectNodes(self: *Self, node1: *Node, node2: *Node) !void {
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

    const from_id = if (node1.id < node2.id) node1.id else node2.id;
    const to_id = if (node1.id < node2.id) node2.id else node1.id;
    try self.edges.append(.{ .from = from_id, .to = to_id });
}

pub fn splitEdge(self: *Self, node1: *Node, node2: *Node, new_node: *Node) !void {
    const dx = node2.pos.x - node1.pos.x;
    const dy = node2.pos.y - node1.pos.y;
    const dir = getDirection(dx, dy) orelse return;

    const dir_idx: usize = @intFromEnum(dir);
    const opposite_idx: usize = (dir_idx + 2) % 4;

    const old_from_id = if (node1.id < node2.id) node1.id else node2.id;
    const old_to_id = if (node1.id < node2.id) node2.id else node1.id;

    var i: usize = 0;
    while (i < self.edges.items.len) {
        const edge = &self.edges.items[i];
        if (edge.from == old_from_id and edge.to == old_to_id) {
            _ = self.edges.orderedRemove(i);
        } else {
            i += 1;
        }
    }

    node1.edges[dir_idx] = null;
    node2.edges[opposite_idx] = null;

    node1.edges[dir_idx] = new_node.id;
    node2.edges[opposite_idx] = new_node.id;
    new_node.edges[opposite_idx] = node1.id;
    new_node.edges[dir_idx] = node2.id;

    try self.edges.append(.{ .from = node1.id, .to = new_node.id });
    try self.edges.append(.{ .from = node2.id, .to = new_node.id });
}

pub fn removeEdge(self: *Self, node1: *Node, node2: *Node) void {
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

    const from_id = if (node1.id < node2.id) node1.id else node2.id;
    const to_id = if (node1.id < node2.id) node2.id else node1.id;

    var i: usize = 0;
    while (i < self.edges.items.len) {
        const edge = &self.edges.items[i];
        if (edge.from == from_id and edge.to == to_id) {
            _ = self.edges.orderedRemove(i);
        } else {
            i += 1;
        }
    }
}

pub fn removeAllEdgesToNode(self: *Self, node_id: usize) void {
    for (self.nodes.items) |*node| {
        if (!node.active) continue;
        if (node.id == node_id) continue;
        for (node.edges, 0..) |edge_id, idx| {
            if (edge_id == node_id) {
                node.edges[idx] = null;
            }
        }
    }

    var i: usize = 0;
    while (i < self.edges.items.len) {
        const edge = &self.edges.items[i];
        if (edge.from == node_id or edge.to == node_id) {
            _ = self.edges.orderedRemove(i);
        } else {
            i += 1;
        }
    }
}

fn loadFromFile(alloc: std.mem.Allocator) !struct {
    nodes: []Node,
    edges: []Edge,
    tiles: TileMap,
    sprites: []Sprite,
    start_nodes: @FieldType(Self, "start_nodes"),
    end_nodes: @FieldType(Self, "end_nodes"),
} {
    var nodes = std.array_list.Managed(Node).init(alloc);
    var edges = std.array_list.Managed(Edge).init(alloc);
    var tiles: TileMap = std.mem.zeroes(TileMap);
    var sprites = std.array_list.Managed(Sprite).init(alloc);
    var start_nodes = std.AutoArrayHashMap(usize, void).init(alloc);
    var end_nodes = std.AutoArrayHashMap(usize, void).init(alloc);

    const file = try std.fs.cwd().openFile(FILE_NAME, .{});
    defer file.close();

    var line_buf: [1024]u8 = undefined;
    var reader = file.reader(&line_buf);

    var section: enum { header, tiles, roads, sprites } = .header;
    var section_row: usize = 0;

    while (try reader.interface.takeDelimiter('\n')) |line_trimmed| {
        const line = std.mem.trim(u8, line_trimmed, " \t\r\n");
        if (line.len == 0) continue;

        if (std.mem.startsWith(u8, line, "start_nodes=")) {
            const value_part = line["start_nodes=".len..];
            if (value_part.len > 0) {
                var iter = std.mem.splitSequence(u8, value_part, ",");
                while (iter.next()) |node_id_str| {
                    const trimmed = std.mem.trim(u8, node_id_str, " \t\r\n");
                    if (trimmed.len == 0) continue;
                    const node_id = try std.fmt.parseInt(usize, trimmed, 10);
                    try start_nodes.put(node_id, {});
                }
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "end_nodes=")) {
            const value_part = line["end_nodes=".len..];
            if (value_part.len > 0) {
                var iter = std.mem.splitSequence(u8, value_part, ",");
                while (iter.next()) |node_id_str| {
                    const trimmed = std.mem.trim(u8, node_id_str, " \t\r\n");
                    if (trimmed.len == 0) continue;
                    const node_id = try std.fmt.parseInt(usize, trimmed, 10);
                    try end_nodes.put(node_id, {});
                }
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "[")) {
            if (std.mem.eql(u8, line, "[tiles]")) {
                section = .tiles;
                section_row = 0;
            } else if (std.mem.eql(u8, line, "[roads]")) {
                section = .roads;
            } else if (std.mem.eql(u8, line, "[sprites]")) {
                section = .sprites;
            }
            continue;
        }

        switch (section) {
            .header => {
                // TODO: skip header for now
                continue;
            },
            .tiles => {
                var row_iter = std.mem.splitSequence(u8, line, ",");
                var col: usize = 0;
                while (row_iter.next()) |tile_str| {
                    const tile_id = try std.fmt.parseInt(usize, std.mem.trim(u8, tile_str, " "), 10);
                    if (col < tiles[0].len) {
                        tiles[section_row][col] = tile_id;
                    }
                    col += 1;
                }
                section_row += 1;
            },
            .roads => {
                var iter = std.mem.splitSequence(u8, line, " ");
                const node_head = iter.next() orelse continue;

                var node_iter = std.mem.splitSequence(u8, node_head, ";");

                const id_str = node_iter.next() orelse continue;
                const x_str = node_iter.next() orelse continue;
                const y_str = node_iter.next() orelse continue;

                const id = try std.fmt.parseInt(usize, id_str, 10);
                const x = try std.fmt.parseFloat(f32, x_str);
                const y = try std.fmt.parseFloat(f32, y_str);

                var node = Node.init(.{ .x = x, .y = y }, id);
                for (0..4) |idx| {
                    if (iter.next()) |edge| {
                        const edge_id = try std.fmt.parseInt(i64, std.mem.trim(u8, edge, "\n"), 10);
                        if (edge_id >= 0) {
                            node.edges[idx] = @intCast(edge_id);
                            try edges.append(.{ .from = id, .to = @intCast(edge_id) });
                        } else {
                            node.edges[idx] = null;
                        }
                    }
                }

                if (start_nodes.contains(node.id))
                    node.type = .start
                else if (end_nodes.contains(node.id))
                    node.type = .end;

                try nodes.append(node);
            },
            .sprites => {
                var iter = std.mem.splitSequence(u8, line, ";");
                const sprite_id_str = iter.next() orelse continue;
                const x_str = iter.next() orelse continue;
                const y_str = iter.next() orelse continue;

                const sprite_id = try std.fmt.parseInt(usize, sprite_id_str, 10);
                const x = try std.fmt.parseFloat(f32, x_str);
                const y = try std.fmt.parseFloat(f32, y_str);

                try sprites.append(Sprite.init(.{ .x = x, .y = y }, sprite_id));
            },
        }
    }

    return .{
        .tiles = tiles,
        .nodes = try nodes.toOwnedSlice(),
        .edges = try edges.toOwnedSlice(),
        .sprites = try sprites.toOwnedSlice(),
        .start_nodes = start_nodes,
        .end_nodes = end_nodes,
    };
}

fn normalizeIds(self: *Self, nodes: []Node) ![]Node {
    var id_map = std.AutoHashMap(usize, usize).init(self.alloc);
    defer id_map.deinit();

    var new_id: usize = 0;
    for (nodes) |node| {
        if (!node.active) continue;
        try id_map.put(node.id, new_id);
        new_id += 1;
    }

    var new_nodes = std.array_list.Managed(Node).init(self.alloc);
    for (nodes) |*node| {
        if (!node.active) continue;
        var new_node = Node.init(node.pos, id_map.get(node.id).?);
        for (node.edges, 0..) |edge_id, idx| {
            if (edge_id == null) continue;
            if (id_map.get(edge_id.?)) |new_edge_id| {
                new_node.edges[idx] = new_edge_id;
            }
        }
        try new_nodes.append(new_node);
    }

    return new_nodes.toOwnedSlice();
}

pub fn saveToFile(self: *Self) !void {
    const file = try std.fs.cwd().createFile(FILE_NAME, .{});
    defer file.close();

    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);

    try writer.interface.print("version=1\n", .{});

    try writer.interface.print("start_nodes=", .{});
    for (self.start_nodes.keys(), 0..) |node_id, idx| {
        try writer.interface.print("{}", .{node_id});
        if (idx < self.start_nodes.count() - 1) try writer.interface.print(",", .{});
    }
    try writer.interface.print("\n", .{});

    try writer.interface.print("end_nodes=", .{});
    for (self.end_nodes.keys(), 0..) |node_id, idx| {
        try writer.interface.print("{}", .{node_id});
        if (idx < self.end_nodes.count() - 1) try writer.interface.print(",", .{});
    }
    try writer.interface.print("\n", .{});

    try writer.interface.print("\n", .{});

    // tiles
    try writer.interface.print("[tiles]\n", .{});
    for (0..self.tiles.len) |tile_y| {
        for (0..self.tiles[tile_y].len) |tile_x| {
            if (tile_x > 0) try writer.interface.print(",", .{});
            try writer.interface.print("{d}", .{self.tiles[tile_y][tile_x]});
        }
        try writer.interface.print("\n", .{});
    }
    try writer.interface.print("\n", .{});

    // roads
    try writer.interface.print("[roads]\n", .{});
    const normalized_nodes = try self.normalizeIds(self.nodes.items);
    defer self.alloc.free(normalized_nodes);

    for (normalized_nodes) |node| {
        if (!node.active) continue;

        try writer.interface.print("{d};{d};{d}", .{ node.id, node.pos.x, node.pos.y });
        for (node.edges) |edge_id| {
            const edge: i64 = if (edge_id) |edge| @intCast(edge) else -1;
            try writer.interface.print(" {d}", .{edge});
        }
        try writer.interface.print("\n", .{});
    }
    try writer.interface.print("\n", .{});

    // sprites
    try writer.interface.print("[sprites]\n", .{});
    for (self.sprites.items) |sprite| {
        try writer.interface.print("{d};{d};{d}\n", .{ sprite.sprite_id, sprite.pos.x, sprite.pos.y });
    }

    writer.interface.flush() catch {
        std.debug.print("Error flushing buffered writer", .{});
    };
}
