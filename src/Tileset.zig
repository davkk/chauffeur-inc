const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const Self = @This();

texture: rl.Texture2D,
cols: usize,
rows: usize,

pub fn init() Self {
    const image = @embedFile("assets/tileset.png");
    const tileset_image = rl.LoadImageFromMemory(".png", image.ptr, @intCast(image.len));
    const tileset = rl.LoadTextureFromImage(tileset_image);
    return .{
        .texture = tileset,
        .cols = @divTrunc(@as(usize, @intCast(tileset_image.width)), g.TILE_SIZE),
        .rows = @divTrunc(@as(usize, @intCast(tileset_image.height)), g.TILE_SIZE),
    };
}

pub fn deinit(self: *const Self) void {
    rl.UnloadTexture(self.texture);
}
