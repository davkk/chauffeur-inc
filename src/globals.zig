const math = @import("std").math;

pub const SCREEN_WIDTH = 1200;
pub const SCREEN_HEIGHT = 1600;
pub const TARGET_FPS = 60;

pub const THROTTLE_SPEED: f32 = 3000.0;
pub const VELOCITY_THRESHOLD: f32 = 30.0;

pub const DRAG_FACTOR: f32 = 0.01;
pub const ROLLING_RESISTANCE: f32 = 3.0;
pub const BREAK_FACTOR: f32 = 10;

pub const MAX_STEER_ANGLE = math.pi / 3.0;
pub const STEER_SPEED = 3;
