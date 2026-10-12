const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;

pub const SCREEN_WIDTH = 1280;
pub const SCREEN_HEIGHT = 800;

pub const WORLD_WIDTH = 1920;
pub const WORLD_HEIGHT = 1200;

pub const TILE_SIZE = 32;

pub const TARGET_FPS = 60;

pub const MAX_SPEED = 200;

pub const NEXT_DIR_TIMEOUT = 0.4;
pub const NODE_ARRIVAL_DIST = 2.0;
pub const SPEED_PENALTY_TURN = 0.6;
pub const SPEED_PENALTY_UTURN = 0.3;
pub const SPEED_PENALTY_DODGE = 0.8;

pub const TARGET_AGENT_COUNT = 3;
pub const AGENT_SPAWN_INTERVAL = 1.0;

pub const PASSENGER_PICKUP_DISTANCE = 1.5 * TILE_SIZE;

pub const DODGE_SPEED = 10.0;
pub const DODGE_DURATION = 0.5;

pub const ANGLE_CHANGE_SPEED = 25.0;

pub const MAX_NODES = 100;

pub const BASE_VEC: [4]rl.Vector2 = .{
    .{ .x = 0, .y = -1 },
    .{ .x = 1, .y = 0 },
    .{ .x = 0, .y = 1 },
    .{ .x = -1, .y = 0 },
};

pub const SEMI_TRANSPARENT = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 128 };
