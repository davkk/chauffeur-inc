const std = @import("std");
const math = std.math;
const rl = @import("raylib.zig").rl;

/// An oriented box. `half_extents.x` is half the width along the local x
/// (right) axis and `half_extents.y` is half the length along the local y
/// (back/down) axis.
pub const Box = struct {
    center: rl.Vector2,
    half_extents: rl.Vector2,
    /// Rotation in radians. Local x is `(cos(angle), sin(angle))` and local y
    /// is `(-sin(angle), cos(angle))`, matching raylib's y-down screen space.
    angle: f32,
};

pub const Manifold = struct {
    /// Unit normal pointing from the first box toward the second.
    normal: rl.Vector2,
    /// Minimum translation depth along `normal`.
    depth: f32,
};

fn axes(angle: f32) [2]rl.Vector2 {
    const cos = math.cos(angle);
    const sin = math.sin(angle);
    return [_]rl.Vector2{
        .{ .x = cos, .y = sin },
        .{ .x = -sin, .y = cos },
    };
}

fn projectedRadius(box: Box, axis: rl.Vector2) f32 {
    const box_axes = axes(box.angle);
    return @abs(rl.Vector2DotProduct(box_axes[0], axis)) * box.half_extents.x +
        @abs(rl.Vector2DotProduct(box_axes[1], axis)) * box.half_extents.y;
}

/// Separating axis test for two oriented boxes. Returns the minimum
/// translation vector needed to separate them, or null when they do not touch.
pub fn collide(a: Box, b: Box) ?Manifold {
    const delta = rl.Vector2Subtract(b.center, a.center);

    var depth = math.inf(f32);
    var normal = rl.Vector2Zero();

    const a_axes = axes(a.angle);
    const b_axes = axes(b.angle);
    const candidates = [4]rl.Vector2{ a_axes[0], a_axes[1], b_axes[0], b_axes[1] };

    for (candidates) |axis| {
        const overlap = projectedRadius(a, axis) + projectedRadius(b, axis) -
            @abs(rl.Vector2DotProduct(delta, axis));
        if (overlap <= 0) return null;

        if (overlap < depth) {
            depth = overlap;
            normal = if (rl.Vector2DotProduct(delta, axis) < 0)
                rl.Vector2Negate(axis)
            else
                axis;
        }
    }

    return .{ .normal = normal, .depth = depth };
}
