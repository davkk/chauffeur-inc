const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const Tileset = @import("Tileset.zig");

pub const Node = struct {
    pos: rl.Vector2,
    id: usize,
    active: bool = true,
    edges: std.AutoArrayHashMap(usize, void),

    pub fn init(alloc: *const std.mem.Allocator, pos: rl.Vector2, id: usize) Node {
        return Node{
            .active = true,
            .pos = pos,
            .id = id,
            .edges = std.AutoArrayHashMap(usize, void).init(alloc.*),
        };
    }
};

const Self = @This();

road_texture: rl.Texture2D,
tileset: Tileset,

nodes: std.ArrayList(?Node),
max_id: usize,

pub fn init(alloc: std.mem.Allocator) !Self {
    const tileset = Tileset.init();

    var road = rl.LoadImageFromTexture(tileset.texture);
    rl.ImageCrop(&road, .{ .x = 0, .y = 0, .width = 2 * g.TILE_SIZE, .height = g.TILE_SIZE });

    const road_texture = rl.LoadTextureFromImage(road);
    rl.SetTextureWrap(road_texture, rl.TEXTURE_WRAP_REPEAT);

    var nodes = std.ArrayList(?Node).init(alloc);

    const file = try std.fs.cwd().openFile("src/assets/map.dat", .{});
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());
    var reader = buffered_reader.reader();
    var line_buf: [1024]u8 = undefined; // TODO: buffer size?

    var temp_nodes = std.ArrayList(Node).init(alloc);
    defer temp_nodes.deinit();

    while (try reader.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
        var iter = std.mem.splitSequence(u8, line, " ");
        const node_head = iter.next();

        var node_iter = std.mem.splitSequence(u8, node_head.?, ";");

        const id = try std.fmt.parseInt(usize, node_iter.next().?, 10);
        const x = try std.fmt.parseFloat(f32, node_iter.next().?);
        const y = try std.fmt.parseFloat(f32, node_iter.next().?);

        try temp_nodes.append(Node.init(&alloc, .{ .x = x, .y = y }, id));
        const node = &temp_nodes.items[temp_nodes.items.len - 1];

        while (iter.next()) |edge| {
            const edge_id = try std.fmt.parseInt(usize, std.mem.trim(u8, edge, "\n"), 10);
            try node.edges.put(edge_id, {});
        }
    }

    const max_id = if (temp_nodes.items.len == 0) 0 else temp_nodes.items[temp_nodes.items.len - 1].id + 1;
    try nodes.resize(max_id);
    for (temp_nodes.items) |node| {
        nodes.items[node.id] = node;
    }

    return .{
        .tileset = tileset,
        .road_texture = road_texture,
        .nodes = nodes,
        .max_id = max_id,
    };
}

pub fn deinit(self: *const Self) void {
    rl.UnloadTexture(self.road_texture);
    rl.UnloadTexture(self.tileset.texture);

    for (self.nodes.items) |*maybe_node| {
        if (maybe_node.*) |*node| {
            node.edges.deinit();
        }
    }
    self.nodes.deinit();
}

pub fn draw(self: *Self) void {
    for (self.nodes.items) |*maybe_node1| {
        if (maybe_node1.*) |*node1| {
            if (!node1.active) continue;

            // draw roads
            for (node1.edges.keys()) |edge| {
                const node2 = &self.nodes.items[edge].?;
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
                const node2 = &self.nodes.items[edge].?;
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
                const node2 = &self.nodes.items[edge].?;
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
}
