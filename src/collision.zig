const std = @import("std");
const assert = std.debug.assert;
const math = @import("std").math;
const rl = @import("raylib.zig").rl;

fn rotate(v: rl.Vector2, cv: rl.Vector2, angle: f32) rl.Vector2 {
    const cos = math.cos(angle);
    const sin = math.sin(angle);
    const x = v.x - cv.x;
    const y = v.y - cv.y;
    return .{
        .x = x * cos - y * sin + cv.x,
        .y = x * sin + y * cos + cv.y,
    };
}

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
        rotate(top_left, rect_center, angle),
        rotate(top_right, rect_center, angle),
        rotate(bottom_left, rect_center, angle),
        rotate(bottom_right, rect_center, angle),
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

pub fn collide(
    rect1: *const rl.Rectangle,
    angle1: f32,
    rect2: *const rl.Rectangle,
    angle2: f32,
) ?rl.Vector2 {
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
            if (overlap1 < overlap2) {
                depth = overlap1;
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
            if (overlap1 < overlap2) {
                depth = overlap1;
                normal = axis;
            }
        }
    }

    return rl.Vector2Normalize(normal);
}
