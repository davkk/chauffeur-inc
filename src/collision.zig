const std = @import("std");
const assert = std.debug.assert;
const math = @import("std").math;
const rl = @import("raylib.zig").rl;
const vec_rotate = @import("raylib.zig").vec_rotate;

pub fn get_vertices(rect: *const rl.Rectangle, angle: f32) [4]rl.Vector2 {
    const top_left = rl.Vector2{
        .x = rect.x,
        .y = rect.y,
    };
    const top_right = rl.Vector2{
        .x = rect.x + rect.width,
        .y = rect.y,
    };
    const bottom_left = rl.Vector2{
        .x = rect.x,
        .y = rect.y + rect.height,
    };
    const bottom_right = rl.Vector2{
        .x = rect.x + rect.width,
        .y = rect.y + rect.height,
    };

    const rect_center = rl.Vector2{
        .x = rect.x + rect.width / 2,
        .y = rect.y + rect.height / 2,
    };

    return [_]rl.Vector2{
        vec_rotate(top_left, rect_center, angle),
        vec_rotate(top_right, rect_center, angle),
        vec_rotate(bottom_left, rect_center, angle),
        vec_rotate(bottom_right, rect_center, angle),
    };
}

pub fn get_rect_axes(angle: f32) [2]rl.Vector2 {
    const cos = math.cos(angle);
    const sin = math.sin(angle);
    return [_]rl.Vector2{
        .{ .x = cos, .y = sin },
        .{ .x = -sin, .y = cos },
    };
}

fn project(rect: *const rl.Rectangle, angle: f32, axis: *const rl.Vector2) struct { f32, f32 } {
    var min = math.inf(f32);
    var max = -math.inf(f32);

    const vertices = get_vertices(rect, angle);

    for (vertices) |vertex| {
        const dot = rl.Vector2DotProduct(vertex, axis.*);
        if (dot < min) {
            min = dot;
        }
        if (dot > max) {
            max = dot;
        }
    }

    return .{ min, max };
}

const CollisionResult = struct { normal: rl.Vector2, depth: f32 };

pub fn collide(
    rect1: *const rl.Rectangle,
    angle1: f32,
    rect2: *const rl.Rectangle,
    angle2: f32,
) ?CollisionResult {
    var depth: f32 = math.inf(f32);
    var normal: rl.Vector2 = undefined;

    const axes1 = get_rect_axes(angle1);
    for (axes1) |axis| {
        const min1, const max1 = project(rect1, angle1, &axis);
        const min2, const max2 = project(rect2, angle2, &axis);

        if (max1 < min2 or max2 < min1) {
            return null;
        } else {
            const overlap1 = max1 - min2;
            const overlap2 = max2 - min1;
            const current_overlap = @min(overlap1, overlap2);
            if (current_overlap < depth) {
                depth = current_overlap;
                normal = axis;
            }
        }
    }

    const axes2 = get_rect_axes(angle2);
    for (axes2) |axis| {
        const min1, const max1 = project(rect1, angle1, &axis);
        const min2, const max2 = project(rect2, angle2, &axis);

        if (max1 < min2 or max2 < min1) {
            return null;
        } else {
            const overlap1 = max1 - min2;
            const overlap2 = max2 - min1;
            const current_overlap = @min(overlap1, overlap2);
            if (current_overlap < depth) {
                depth = current_overlap;
                normal = axis;
            }
        }
    }

    const center1 = rl.Vector2{ .x = rect1.x + rect1.width / 2, .y = rect1.y + rect1.height / 2 };
    const center2 = rl.Vector2{ .x = rect2.x + rect2.width / 2, .y = rect2.y + rect2.height / 2 };
    const dir = rl.Vector2Subtract(center2, center1);

    if (rl.Vector2DotProduct(dir, normal) < 0) {
        normal = rl.Vector2Scale(normal, -1);
    }

    return .{ .normal = normal, .depth = depth };
}
