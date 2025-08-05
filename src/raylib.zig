const math = @import("std").math;
pub const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
});

pub fn vec_add(vectors: []const rl.Vector2) rl.Vector2 {
    var result = rl.Vector2Zero();
    for (vectors) |vector| {
        result = rl.Vector2Add(result, vector);
    }
    return result;
}

pub fn vec_rotate(vec: rl.Vector2, center: rl.Vector2, angle: f32) rl.Vector2 {
    const cos = math.cos(angle);
    const sin = math.sin(angle);
    const x = vec.x - center.x;
    const y = vec.y - center.y;
    return .{
        .x = x * cos - y * sin + center.x,
        .y = x * sin + y * cos + center.y,
    };
}
