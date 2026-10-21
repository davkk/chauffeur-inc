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

pub const NEXT_DIR_TIMEOUT = 1.0;
pub const NODE_ARRIVAL_DIST = 2.0;
pub const SPEED_PENALTY_TURN = 0.6;
pub const SPEED_PENALTY_UTURN = 0.3;
pub const SPEED_PENALTY_DODGE = 0.8;

pub const TARGET_AGENT_COUNT = 13;
pub const AGENT_SPAWN_INTERVAL = 1.0;

pub const PORTAL_CLEAR_DISTANCE = 80.0;
pub const PORTAL_SPAWN_GAP = 1.0;
pub const PORTAL_RELEASE_OFFSET = 120.0;
pub const PORTAL_RELEASE_TIMEOUT = 5.0;

pub const PASSENGER_PICKUP_DISTANCE = 2.0 * TILE_SIZE;
pub const PASSENGER_DROPOFF_DISTANCE = 2.0 * TILE_SIZE;
pub const PASSENGER_DROPOFF_MAX_SPEED = 45.0;
pub const PASSENGER_PATIENCE = 40.0;
pub const PASSENGER_DELIVERY_TIME = 35.0;
pub const PASSENGER_RESPAWN_DELAY = 1.25;

pub const PASSENGER_FARE_BASE = 20;
pub const PASSENGER_FARE_PER_PIXEL = 0.05;
pub const PASSENGER_TIP_MAX = 40.0;
pub const COMBO_STEP = 3;
pub const COMBO_MAX_MULT = 4;

pub const CRASH_COOLDOWN = 1.0;
pub const CRASH_SPEED_LOSS = 0.45;
pub const CRASH_FLASH_TIME = 0.35;
pub const CRASH_MONEY_PENALTY = 8;
pub const CRASH_TIME_PENALTY = 1.5;
pub const WRONG_WAY_ACHIEVEMENT_TIME = 10.0;
/// Speed the other car of a crash keeps.
pub const CRASH_OTHER_SPEED_LOSS = 0.6;
/// Speed an agent keeps after it bumped into another car.
pub const BUMP_SPEED_LOSS = 0.85;
/// How long a car stays stunned after a crash, in seconds.
pub const CRASH_STUN_TIME = 0.3;
/// Speed a stunned car loses per second, in px/s.
pub const CRASH_STUN_DECEL = 450.0;
/// Largest physical displacement of a car, in px.
pub const PUSH_OFFSET_MAX = 16.0;
/// How fast the physical push of a crash fades away, in 1/s.
pub const PUSH_OFFSET_DECAY = 4.0;
/// Overlap that is not pushed apart anymore, in px. It keeps cars that just
/// touch from jittering.
pub const SEPARATION_SLOP = 0.5;
pub const PICKUP_FLASH_TIME = 0.5;
pub const HINT_DURATION = 10.0;

pub const DODGE_SPEED = 10.0;
pub const DODGE_DURATION = 0.5;

pub const CAR_WIDTH = 16.0;
pub const CAR_HEIGHT = 32.0;

pub const LANE_WIDTH = TILE_SIZE / 2.0;
pub const ROAD_HALF = 3.0 * TILE_SIZE / 2.0;
pub const NODE_HALF = TILE_SIZE;

pub const TURN_RADIUS = NODE_HALF - CAR_WIDTH / 2.0;
pub const STRAIGHT_COMMIT_DIST = TURN_RADIUS - CAR_WIDTH;
pub const NODE_CLEAR_DIST = TURN_RADIUS + CAR_HEIGHT / 2.0;
pub const FLIP_ARC = math.pi * LANE_WIDTH;

pub const LAT_A_MAX = 800.0;

pub const YIELD_DIST = 80.0;
pub const YIELD_TIE_EPS = 5.0;
pub const YIELD_TIMEOUT = 2.0;
pub const YIELD_MAX_WAIT = 2.0;

pub const ANGLE_CHANGE_SPEED = 25.0;

pub const MAX_NODES = 100;

pub const BASE_VEC: [4]rl.Vector2 = .{
    .{ .x = 0, .y = -1 },
    .{ .x = 1, .y = 0 },
    .{ .x = 0, .y = 1 },
    .{ .x = -1, .y = 0 },
};

pub const SEMI_TRANSPARENT = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 128 };

comptime {
    std.debug.assert(2.0 * LANE_WIDTH + CAR_WIDTH / 2.0 <= ROAD_HALF);
}
