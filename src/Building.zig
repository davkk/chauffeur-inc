const rl = @import("raylib.zig").rl;

rect: rl.Rectangle,

const Self = @This();

pub fn init(x: f32, y: f32, width: f32, height: f32) Self {
    return .{
        .rect = .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        },
    };
}

pub fn draw(self: *const Self) void {
    rl.DrawRectangleRec(self.rect, rl.BLACK);
}
