const std = @import("std");
const math = std.math;
const rand = std.crypto.random;

const rl = @import("raylib.zig").rl;

pub const SCREEN_WIDTH = 1920;
pub const SCREEN_HEIGHT = 1200;

pub const TILE_SIZE = 32;

pub const TARGET_FPS = 60;

pub const FRICTION = 200;
pub const MAX_SPEED = 400;

pub const NEXT_DIR_TIMEOUT = 0.4;
pub const NODE_ARRIVAL_DIST = 2.0;
pub const SPEED_PENALTY_TURN = 0.6;
pub const SPEED_PENALTY_UTURN = 0.3;

pub const PASSENGER_PICKUP_DISTANCE = 1.5 * TILE_SIZE;

pub const MAX_NODES = 100;

pub const TILES = [_]rl.Rectangle{
    .{ .x = 2 * TILE_SIZE, .y = 0, .width = TILE_SIZE, .height = TILE_SIZE },
    .{ .x = 3 * TILE_SIZE, .y = 0, .width = TILE_SIZE, .height = TILE_SIZE },
};

pub const SPRITES = [_]rl.Rectangle{
    .{ .x = 3 * TILE_SIZE, .y = TILE_SIZE, .width = 64, .height = 64 },
};

pub const TILE_DEFINITIONS = TILES ++ SPRITES;

pub const SEMI_TRANSPARENT = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 128 };

// TODO: I feel like this should be somewhere else
pub const Direction = enum { up, right, down, left };

pub const KeyInput = struct {
    dir: ?Direction,
    brake: bool,
};

/// start, end are inclusive
pub fn randPair(start: usize, end: usize) struct { usize, usize } {
    std.debug.assert(start < end);
    var a: usize = undefined;
    var b: usize = undefined;
    while (a == b) { // WARN: this can go forever, separate thread
        a = rand.intRangeAtMost(usize, start, end);
        b = rand.intRangeAtMost(usize, start, end);
    }
    return .{ a, b };
}
