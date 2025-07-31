const c = @cImport({ @cInclude("raylib.h"); });

rect: c.Rectangle,

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
    c.DrawRectangleRec(self.rect, c.GRAY);
}
