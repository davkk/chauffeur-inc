const math = @import("std").math;
const rl = @import("raylib.zig").rl;

pub const SCREEN_WIDTH = 1920;
pub const SCREEN_HEIGHT = 1200;

pub const TILE_SIZE = 32;

pub const TARGET_FPS = 60;

pub const FRICTION = 200;
pub const MAX_SPEED = 300;

pub const TILES = [_]rl.Rectangle{
    .{ .x = 2 * TILE_SIZE, .y = 0, .width = TILE_SIZE, .height = TILE_SIZE },
    .{ .x = 3 * TILE_SIZE, .y = 0, .width = TILE_SIZE, .height = TILE_SIZE },
};

pub const SPRITES = [_]rl.Rectangle{
    .{ .x = 3 * TILE_SIZE, .y = TILE_SIZE, .width = 64, .height = 64 },
};

pub const TILE_DEFINITIONS = TILES ++ SPRITES;

pub const SEMI_TRANSPARENT = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 128 };

pub const Direction = enum { top, right, bottom, left };
