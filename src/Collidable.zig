const rl = @import("raylib.zig").rl;

const Self = @This();

const Shape = enum(usize) {
    RECTANGLE,
    ELLIPSE,
};

shape: Shape,
x: f32,
y: f32,
width: f32,
height: f32,

// mass: f32, // TODO: use this somehow?

pub fn init_rect(x: f32, y: f32, width: f32, height: f32) Self {
    return .{ .shape = .RECTANGLE, .x = x, .y = y, .width = width, .height = height };
}

pub fn init_ellipse(x: f32, y: f32, width: f32, height: f32) Self {
    return .{ .shape = .ELLIPSE, .x = x, .y = y, .width = width, .height = height };
}

pub fn draw(self: *const Self, color: ?rl.Color) void {
    const draw_fn = switch (self.shape) {
        .RECTANGLE => rl.DrawRectangle,
        .ELLIPSE => rl.DrawEllipse,
    };
    draw_fn(self.x, self.y, self.width, self.height, color orelse rl.BLACK);
}

pub fn rect(self: *const Self) rl.Rectangle {
    return .{
        .x = self.x,
        .y = self.y,
        .width = self.width,
        .height = self.height,
    };
}
