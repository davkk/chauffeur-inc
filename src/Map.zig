const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const Tileset = @import("Tileset.zig");

const FILE_NAME = "src/assets/map.dat";

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

road_texture: rl.Texture2D,
tileset: Tileset,

nodes: std.ArrayList(Node),

pub fn init(alloc: std.mem.Allocator) !Self {
    const tileset = Tileset.init();

    var road = rl.LoadImageFromTexture(tileset.texture);
    rl.ImageCrop(&road, .{ .x = 0, .y = 0, .width = 2 * g.TILE_SIZE, .height = g.TILE_SIZE });

    const road_texture = rl.LoadTextureFromImage(road);
    rl.SetTextureWrap(road_texture, rl.TEXTURE_WRAP_REPEAT);

    const nodes = try loadFromFile(alloc);

    return .{
        .alloc = alloc,
        .tileset = tileset,
        .road_texture = road_texture,
        .nodes = std.ArrayList(Node).fromOwnedSlice(alloc, nodes),
    };
}

pub fn deinit(self: *const Self) void {
    rl.UnloadTexture(self.road_texture);
    rl.UnloadTexture(self.tileset.texture);

    for (self.nodes.items) |*node| {
        node.edges.deinit();
    }
    self.nodes.deinit();
}

pub fn draw(self: *Self) void {
    for (self.nodes.items) |*node1| {
        if (!node1.active) continue;

        // draw roads
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
                self.road_texture,
                .{ .x = 0, .y = 0, .width = 2 * g.TILE_SIZE, .height = length },
                .{ .x = mid_x, .y = mid_y, .width = 2 * g.TILE_SIZE, .height = length },
                .{ .x = g.TILE_SIZE, .y = length / 2 },
                angle,
                rl.WHITE,
            );
        }

        // draw nodes
        for (node1.edges.keys()) |edge| {
            const node2 = &self.nodes.items[edge];
            if (!node2.active) continue;

            const dx = @round(node1.pos.x - node2.pos.x);
            const dy = @round(node2.pos.y - node1.pos.y);
            const angle = -math.atan2(dy, dx) * 180.0 / math.pi - 90;

            rl.DrawTexturePro(
                self.tileset.texture,
                .{ .x = 2 * g.TILE_SIZE, .y = 0, .width = g.TILE_SIZE * 3, .height = g.TILE_SIZE * 2 },
                .{ .x = node1.pos.x, .y = node1.pos.y, .width = g.TILE_SIZE * 3, .height = g.TILE_SIZE * 2 },
                .{ .x = g.TILE_SIZE * 1.5, .y = g.TILE_SIZE },
                angle,
                rl.WHITE,
            );
        }

        // draw lines
        for (node1.edges.keys()) |edge| {
            const node2 = &self.nodes.items[edge];
            if (!node2.active) continue;

            const dx = @round(node1.pos.x - node2.pos.x);
            const dy = @round(node2.pos.y - node1.pos.y);
            const angle = -math.atan2(dy, dx) * 180.0 / math.pi - 90;

            rl.DrawTexturePro(
                self.tileset.texture,
                .{ .x = g.TILE_SIZE * 5, .y = 0, .width = 2 * g.TILE_SIZE, .height = g.TILE_SIZE },
                .{ .x = node1.pos.x, .y = node1.pos.y, .width = 2 * g.TILE_SIZE, .height = g.TILE_SIZE },
                .{ .x = g.TILE_SIZE, .y = g.TILE_SIZE / 2 },
                angle,
                rl.WHITE,
            );
        }
    }
}

fn loadFromFile(alloc: std.mem.Allocator) ![]Node {
    var nodes = std.ArrayList(Node).init(alloc);

    const file = try std.fs.cwd().openFile(FILE_NAME, .{});
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());
    var reader = buffered_reader.reader();
    var line_buf: [1024]u8 = undefined; // TODO: buffer size?

    while (try reader.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
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

    var new_nodes = std.ArrayList(Node).init(self.alloc);
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

    var buffered_writer = std.io.bufferedWriter(file.writer());
    var writer = buffered_writer.writer();

    const normalized_nodes = try self.normalizeIds(self.nodes.items);
    defer self.alloc.free(normalized_nodes);

    for (normalized_nodes) |node| {
        if (!node.active) continue;

        try writer.print("{d};{d};{d}", .{ node.id, node.pos.x, node.pos.y });
        for (node.edges.keys()) |edge| {
            try writer.print(" {d}", .{edge});
        }
        try writer.print("\n", .{});
    }

    buffered_writer.flush() catch {
        std.debug.print("Error flushing buffered writer", .{});
    };
}
