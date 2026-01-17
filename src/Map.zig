const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const TextureGroupType = @import("Editor.zig").TextureGroupType;
const Tileset = @import("Tileset.zig");

const FILE_NAME = "src/assets/map.map";

pub const TileMap = [g.SCREEN_HEIGHT / g.TILE_SIZE][g.SCREEN_WIDTH / g.TILE_SIZE]usize;

pub const Node = struct {
    pos: rl.Vector2,
    id: usize,
    active: bool = true,
    edges: [4]?usize,

    pub fn init(pos: rl.Vector2, id: usize) Node {
        return Node{
            .active = true,
            .pos = pos,
            .id = id,
            .edges = .{ null, null, null, null },
        };
    }
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

const Self = @This();

alloc: std.mem.Allocator,

road_texture: [3]rl.Texture2D,
tileset: Tileset,

nodes: std.array_list.Managed(Node),
tiles: TileMap,
sprites: std.array_list.Managed(Sprite),

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
        .nodes = std.array_list.Managed(Node).fromOwnedSlice(alloc, loaded.nodes),
        .tiles = loaded.tiles,
        .sprites = std.array_list.Managed(Sprite).fromOwnedSlice(alloc, loaded.sprites),
    };
}

pub fn deinit(self: *const Self) void {
    for (self.road_texture) |road| rl.UnloadTexture(road);
    rl.UnloadTexture(self.tileset.texture);

    self.nodes.deinit();
    self.sprites.deinit();
}

// TODO: I hate that I pass active group here...
pub fn draw(self: *Self, active_group: TextureGroupType) void {
    const tile_color = if (active_group == .none or active_group == .tiles) rl.WHITE else g.SEMI_TRANSPARENT;
    const road_color = if (active_group == .none or active_group == .road) rl.WHITE else g.SEMI_TRANSPARENT;

    // draw tiles
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
                tile_color,
            );
        }
    }

    // draw nodes
    for (self.nodes.items) |*node1| {
        if (!node1.active) continue;
        const color = if (active_group == .none or active_group == .road) rl.WHITE else g.SEMI_TRANSPARENT;

        rl.DrawTexturePro(
            self.road_texture[2],
            .{ .x = 0, .y = 0, .width = 2 * g.TILE_SIZE, .height = 2 * g.TILE_SIZE },
            .{ .x = node1.pos.x, .y = node1.pos.y, .width = 2 * g.TILE_SIZE, .height = 2 * g.TILE_SIZE },
            .{ .x = g.TILE_SIZE, .y = g.TILE_SIZE },
            0,
            color,
        );
    }

    // draw edges
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

    const sprite_color = if (active_group == .none or active_group == .sprites) rl.WHITE else g.SEMI_TRANSPARENT;

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
            sprite_color,
        );
    }

}

fn loadFromFile(alloc: std.mem.Allocator) !struct { nodes: []Node, tiles: TileMap, sprites: []Sprite } {
    var nodes = std.array_list.Managed(Node).init(alloc);
    var tiles: TileMap = std.mem.zeroes(TileMap);
    var sprites = std.array_list.Managed(Sprite).init(alloc);

    const file = try std.fs.cwd().openFile(FILE_NAME, .{});
    defer file.close();

    var line_buf: [1024]u8 = undefined;
    var reader = file.reader(&line_buf);

    var section: enum { header, tiles, roads, sprites } = .header;
    var section_row: usize = 0;

    while (try reader.interface.takeDelimiter('\n')) |line_trimmed| {
        const line = std.mem.trim(u8, line_trimmed, " \t\r\n");
        if (line.len == 0) continue;

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
                // skip header for now
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

                try nodes.append(Node.init(.{ .x = x, .y = y }, id));
                const node = &nodes.items[nodes.items.len - 1];

                for (0..4) |idx| {
                    if (iter.next()) |edge| {
                        const edge_id = try std.fmt.parseInt(i64, std.mem.trim(u8, edge, "\n"), 10);
                        node.edges[idx] = if (edge_id >= 0) @intCast(edge_id) else null;
                    }
                }
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

    return .{ .nodes = try nodes.toOwnedSlice(), .tiles = tiles, .sprites = try sprites.toOwnedSlice() };
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
