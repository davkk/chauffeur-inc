const rl = @import("raylib.zig").rl;
const c = @import("constants.zig");

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
        .cols = @divTrunc(@as(usize, @intCast(tileset_image.width)), c.TILE_SIZE),
        .rows = @divTrunc(@as(usize, @intCast(tileset_image.height)), c.TILE_SIZE),
    };
}

pub fn deinit(self: *const Self) void {
    rl.UnloadTexture(self.texture);
}
