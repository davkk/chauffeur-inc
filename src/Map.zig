const std = @import("std");
const json = std.json;
const math = std.math;

const Collidable = @import("Collidable.zig");
const g = @import("globals.zig");
const rl = @import("raylib.zig").rl;
const Tileset = @import("Tileset.zig");

const Self = @This();

const FLIP_HORI: u32 = 0x80000000;
const FLIP_VERT: u32 = 0x40000000;
const FLIP_DIAG: u32 = 0x20000000;

pub const LayerId = enum(usize) {
    BACKGROUND = 0,
    FOREGROUND,
    BUILDINGS,
    COLLIDABLES,
    NUM_LAYERS,
};

const Layer = struct {
    id: LayerId,
    data: std.ArrayList(u32),
    cols: usize,
    rows: usize,

    pub fn init(alloc: std.mem.Allocator, layer_id: usize, data: []json.Value, cols: i64, rows: i64) !Layer {
        var tiles = try std.ArrayList(u32).initCapacity(alloc, data.len);
        for (0..data.len) |idx| {
            try tiles.append(@intCast(data[idx].integer));
        }
        return .{
            .id = @enumFromInt(layer_id),
            .data = tiles,
            .cols = @intCast(cols),
            .rows = @intCast(rows),
        };
    }

    pub fn draw(self: Layer, tileset: Tileset) void {
        for (0..self.rows) |y| {
            for (0..self.cols) |x| {
                var tile_id = self.data.items[y * self.cols + x];
                if (tile_id == 0) continue;

                var angle: f32 = 0;
                switch (tile_id & 0xFF000000) {
                    FLIP_DIAG | FLIP_VERT => angle = -math.pi / 2.0,
                    FLIP_HORI | FLIP_VERT => angle = -math.pi,
                    FLIP_DIAG | FLIP_HORI => angle = -3.0 * math.pi / 2.0,
                    else => {},
                }

                tile_id &= ~(FLIP_HORI | FLIP_VERT | FLIP_DIAG);
                tile_id -= 1; // subtract firstgid

                rl.DrawTexturePro(
                    tileset.texture,
                    .{
                        .x = @floatFromInt(tile_id % tileset.cols * g.TILE_SIZE),
                        .y = @floatFromInt(tile_id / tileset.rows * g.TILE_SIZE),
                        .width = @floatFromInt(g.TILE_SIZE),
                        .height = @floatFromInt(g.TILE_SIZE),
                    },
                    .{
                        .x = @floatFromInt(g.SCALE * (x * g.TILE_SIZE + g.TILE_SIZE / 2)),
                        .y = @floatFromInt(g.SCALE * (y * g.TILE_SIZE + g.TILE_SIZE / 2)),
                        .width = @floatFromInt(g.SCALE * g.TILE_SIZE),
                        .height = @floatFromInt(g.SCALE * g.TILE_SIZE),
                    },
                    .{ .x = g.SCALE * g.TILE_SIZE / 2, .y = g.SCALE * g.TILE_SIZE / 2 },
                    angle * 180 / math.pi,
                    rl.WHITE,
                );
            }
        }
    }
};

fn getNumberFloat(value: json.Value) !f32 {
    return switch (value) {
        .integer => |int_val| @floatFromInt(int_val),
        .float => |float_val| @floatCast(float_val),
        else => error.NotANumber,
    };
}

fn getNumberInt(value: json.Value) !i64 {
    return switch (value) {
        .integer => |int_val| @intCast(int_val),
        .float => |float_val| @intFromFloat(float_val),
        else => error.NotANumber,
    };
}

width: usize,
height: usize,
layers: std.ArrayList(Layer),
collidables: std.ArrayList(Collidable),

pub fn init(alloc: std.mem.Allocator) !Self {
    const map_json = @embedFile("assets/map.json");

    const parsed = try json.parseFromSlice(json.Value, alloc, map_json, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const width = try getNumberInt(root.object.get("width").?);
    const height = try getNumberInt(root.object.get("height").?);

    var layers = std.ArrayList(Layer).init(alloc);
    var collidables = std.ArrayList(Collidable).init(alloc);

    for (root.object.get("layers").?.array.items, 0..) |layer, idx| {
        if (std.mem.eql(u8, layer.object.get("type").?.string, "tilelayer")) {
            try layers.append(
                try Layer.init(
                    alloc,
                    idx,
                    layer.object.get("data").?.array.items,
                    layer.object.get("width").?.integer,
                    layer.object.get("height").?.integer,
                ),
            );
        } else if (std.mem.eql(u8, layer.object.get("type").?.string, "group")) {
            for (layer.object.get("layers").?.array.items) |item| {
                try layers.append(
                    try Layer.init(
                        alloc,
                        idx,
                        item.object.get("data").?.array.items,
                        item.object.get("width").?.integer,
                        item.object.get("height").?.integer,
                    ),
                );
            }
        } else if (std.mem.eql(u8, layer.object.get("type").?.string, "objectgroup")) {
            for (layer.object.get("objects").?.array.items) |obj| {
                try collidables.append(
                    Collidable.init_rect(
                        g.SCALE * try getNumberFloat(obj.object.get("x").?),
                        g.SCALE * try getNumberFloat(obj.object.get("y").?),
                        g.SCALE * try getNumberFloat(obj.object.get("width").?),
                        g.SCALE * try getNumberFloat(obj.object.get("height").?),
                    ),
                );
            }
        }
    }

    return .{
        .width = @intCast(width),
        .height = @intCast(height),
        .layers = layers,
        .collidables = collidables,
    };
}

pub fn deinit(self: *const Self) void {
    self.layers.deinit();
    self.collidables.deinit();
}

pub fn draw_background(self: *const Self, tileset: Tileset) void {
    self.layers.items[@intFromEnum(LayerId.BACKGROUND)].draw(tileset);
}

pub fn draw_foreground(self: *const Self, tileset: Tileset) void {
    for (self.layers.items[@intFromEnum(LayerId.FOREGROUND)..]) |layer| {
        layer.draw(tileset);
    }
}
