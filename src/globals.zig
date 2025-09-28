const math = @import("std").math;

pub const TILE_SIZE = 64;

pub const SCREEN_WIDTH = 1920;
pub const SCREEN_HEIGHT = 1200;

pub const SCALE: i32 = 2;

pub const TARGET_FPS = 60;

pub const ENGINE_FORCE: f32 = 1500.0;
pub const BRAKE_FORCE: f32 = 1000.0;

pub const DRAG_FACTOR: f32 = 0.02;
pub const ROLLING_RESISTANCE: f32 = 0.6;

pub const CORNERING_STIFFNESS_FRONT: f32 = 5000;
pub const CORNERING_STIFFNESS_REAR: f32 = 4500;

pub const MAX_GRIP: f32 = 12000;

pub const VELOCITY_THRESHOLD: f32 = 30.0;

pub const MAX_STEER_ANGLE = math.pi / 6.0;
pub const STEER_SPEED = 3;

pub const ELASTICITY = 2;
