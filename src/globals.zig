const math = @import("std").math;

pub const SCREEN_WIDTH = 1280;
pub const SCREEN_HEIGHT = 720;
pub const TARGET_FPS = 60;

pub const FRICTION = 200;
pub const MAX_SPEED = 300;

pub const MAX_STEER_ANGLE = 3.0 * math.pi / 4.0;
pub const STEER_SENSITIVITY = 10;
