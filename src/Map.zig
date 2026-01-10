const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const TextureGroupType = @import("Editor.zig").TextureGroupType;
const Tileset = @import("Tileset.zig");

const FILE_NAME = "src/assets/map.dat";

pub const TilePosition = struct { x: i32, y: i32 };
pub const TileMap = std.AutoHashMap(TilePosition, usize);

pub const Node = struct {
    pos: rl.Vector2,
    id: usize,
    active: bool = true,
    edges: std.AutoArrayHashMap(usize, void),

    pub fn init(alloc: std.mem.Allocator, pos: rl.Vector2, id: usize) Node {
        return Node{
            .active = true,
            .pos = pos,
            .id = id,
            .edges = std.AutoArrayHashMap(usize, void).init(alloc),
        };
    }
};

const Self = @This();

alloc: std.mem.Allocator,

road_texture: [2]rl.Texture2D,
tileset: Tileset,

nodes: std.array_list.Managed(Node),
tiles: TileMap,

pub fn init(alloc: std.mem.Allocator) !Self {
    const tileset = Tileset.init();

    var road = rl.LoadImageFromTexture(tileset.texture);
    rl.ImageCrop(&road, .{ .x = 0, .y = 0, .width = 2 * g.TILE_SIZE, .height = g.TILE_SIZE });

    var node = rl.LoadImageFromTexture(tileset.texture);
    rl.ImageCrop(&node, .{ .x = 2 * g.TILE_SIZE, .y = 0, .width = g.TILE_SIZE, .height = g.TILE_SIZE });

    const nodes = try loadFromFile(alloc);

    const road_texture = [2]rl.Texture2D{ rl.LoadTextureFromImage(road), rl.LoadTextureFromImage(node) };

    return .{
        .alloc = alloc,
        .tileset = tileset,
        .road_texture = road_texture,
        .nodes = std.array_list.Managed(Node).fromOwnedSlice(alloc, nodes),
        .tiles = TileMap.init(alloc),
    };
}

pub fn deinit(self: *const Self) void {
    for (self.road_texture) |road| rl.UnloadTexture(road);
    rl.UnloadTexture(self.tileset.texture);

    for (self.nodes.items) |*node| {
        node.edges.deinit();
    }
    self.nodes.deinit();
}

const SEMI_TRANSPARENT = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 128 };

pub fn draw(self: *Self, active_group: TextureGroupType) void {
    rl.ClearBackground(rl.BLUE);
    rl.DrawRectangle(0, 0, math.maxInt(c_int), math.maxInt(c_int), rl.BLACK);

    // draw tiles
    var tile_iter = self.tiles.iterator();
    while (tile_iter.next()) |entry| {
        const tile_pos = entry.key_ptr.*;
        const tile_index = entry.value_ptr.*;
        const rect = g.TILE_DEFINITIONS[tile_index];
        rl.DrawTexturePro(
            self.tileset.texture,
            rect,
            .{
                .x = @floatFromInt(tile_pos.x),
                .y = @floatFromInt(tile_pos.y),
                .width = 2 * g.TILE_SIZE,
                .height = 2 * g.TILE_SIZE,
            },
            .{ .x = g.TILE_SIZE, .y = g.TILE_SIZE },
            0,
            if (active_group == .none or active_group == .tiles) rl.WHITE else SEMI_TRANSPARENT,
        );
    }

    // draw edges
    for (self.nodes.items) |*node1| {
        if (!node1.active) continue;

        for (node1.edges.keys()) |edge| {
            const node2 = &self.nodes.items[edge];
            if (!node2.active or node1.id > node2.id) continue;

            const dx = @round(node1.pos.x - node2.pos.x);
            const dy = @round(node2.pos.y - node1.pos.y);

            const angle = -math.atan2(dy, dx) * 180.0 / math.pi - 90;

            const mid_x = (node1.pos.x + node2.pos.x) / 2.0;
            const mid_y = (node1.pos.y + node2.pos.y) / 2.0;
            const length = @sqrt(dx * dx + dy * dy);

            rl.DrawTexturePro(
                self.road_texture[0],
                .{ .x = 0, .y = 0, .width = 2 * g.TILE_SIZE, .height = length },
                .{ .x = mid_x, .y = mid_y, .width = 2 * g.TILE_SIZE, .height = length },
                .{ .x = g.TILE_SIZE, .y = length / 2 },
                angle,
                if (active_group == .none or active_group == .road) rl.WHITE else SEMI_TRANSPARENT,
            );
        }
    }

    // draw nodes
    for (self.nodes.items) |*node1| {
        if (!node1.active) continue;
        const color = if (active_group == .none or active_group == .road) rl.WHITE else SEMI_TRANSPARENT;

        rl.DrawTexturePro(
            self.road_texture[1],
            .{ .x = 0, .y = 0, .width = g.TILE_SIZE, .height = g.TILE_SIZE },
            .{ .x = node1.pos.x, .y = node1.pos.y, .width = 2 * g.TILE_SIZE, .height = 2 * g.TILE_SIZE },
            .{ .x = g.TILE_SIZE, .y = g.TILE_SIZE },
            0,
            color,
        );

        // draw lines
        for (node1.edges.keys()) |edge| {
            const node2 = &self.nodes.items[edge];
            if (!node2.active) continue;

            const dir = rl.Vector2Normalize(rl.Vector2Subtract(node2.pos, node1.pos));

            rl.DrawLineEx(
                rl.Vector2Add(node1.pos, rl.Vector2Scale(dir, g.TILE_SIZE / 2)),
                rl.Vector2Add(node1.pos, rl.Vector2Scale(dir, g.TILE_SIZE)),
                2.0,
                color,
            );
        }
    }

    // TODO: draw collidables
}

fn loadFromFile(alloc: std.mem.Allocator) ![]Node {
    var nodes = std.array_list.Managed(Node).init(alloc);

    const file = try std.fs.cwd().openFile(FILE_NAME, .{});
    defer file.close();

    var line_buf: [1024]u8 = undefined; // TODO: buffer size?
    var reader = file.reader(&line_buf);

    while (try reader.interface.takeDelimiter('\n')) |line| {
        var iter = std.mem.splitSequence(u8, line, " ");
        const node_head = iter.next();

        var node_iter = std.mem.splitSequence(u8, node_head.?, ";");

        const id = try std.fmt.parseInt(usize, node_iter.next().?, 10);
        const x = try std.fmt.parseFloat(f32, node_iter.next().?);
        const y = try std.fmt.parseFloat(f32, node_iter.next().?);

        try nodes.append(Node.init(alloc, .{ .x = x, .y = y }, id));
        const node = &nodes.items[nodes.items.len - 1];

        while (iter.next()) |edge| {
            const edge_id = try std.fmt.parseInt(usize, std.mem.trim(u8, edge, "\n"), 10);
            try node.edges.put(edge_id, {});
        }
    }

    return nodes.toOwnedSlice();
}

fn normalizeIds(self: *Self, nodes: []Node) ![]Node {
    var id_map = std.AutoHashMap(usize, usize).init(self.alloc);
    defer id_map.deinit();

    var new_id: usize = 0;
    for (nodes) |node| {
        if (!node.active or node.edges.count() == 0) continue;
        try id_map.put(node.id, new_id);
        new_id += 1;
    }

    var new_nodes = std.array_list.Managed(Node).init(self.alloc);
    for (nodes) |*node| {
        if (!node.active or node.edges.count() == 0) continue;
        var new_node = Node.init(self.alloc, node.pos, id_map.get(node.id).?);
        for (node.edges.keys()) |edge_id| {
            if (id_map.get(edge_id)) |new_edge_id| {
                try new_node.edges.put(new_edge_id, {});
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

    const normalized_nodes = try self.normalizeIds(self.nodes.items);
    defer self.alloc.free(normalized_nodes);

    for (normalized_nodes) |node| {
        if (!node.active) continue;

        try writer.interface.print("{d};{d};{d}", .{ node.id, node.pos.x, node.pos.y });
        for (node.edges.keys()) |edge| {
            try writer.interface.print(" {d}", .{edge});
        }
        try writer.interface.print("\n", .{});
    }

    writer.interface.flush() catch {
        std.debug.print("Error flushing buffered writer", .{});
    };
}
