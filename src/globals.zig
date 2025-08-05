const math = @import("std").math;

pub const SCREEN_WIDTH = 1200;
pub const SCREEN_HEIGHT = 1600;
pub const TARGET_FPS = 60;

pub const ENGINE_FORCE: f32 = 2000.0;
pub const BRAKE_FORCE: f32 = 2000.0;

pub const DRAG_FACTOR: f32 = 0.01;
pub const ROLLING_RESISTANCE: f32 = 1.0;

pub const CORNERING_STIFFNESS_FRONT: f32 = 10000;
pub const CORNERING_STIFFNESS_REAR: f32 = 5000;

pub const VELOCITY_THRESHOLD: f32 = 50.0;

pub const MAX_STEER_ANGLE = math.pi / 6.0;
pub const STEER_SPEED = 3;
