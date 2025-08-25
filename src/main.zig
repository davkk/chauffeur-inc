const std = @import("std");
const json = std.json;
const math = std.math;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");
const collision = @import("collision.zig");

const Car = @import("Car.zig");
const Building = @import("Building.zig");

const Tileset = struct {
    texture: rl.Texture2D,
    cols: i64,
    rows: i64,

    fn init() Tileset {
        const tileset_image = rl.LoadImage("assets/tileset.png");
        const tileset = rl.LoadTextureFromImage(tileset_image);

        return Tileset{
            .texture = tileset,
            .cols = @divTrunc(tileset_image.width, g.TILE_SIZE),
            .rows = @divTrunc(tileset_image.height, g.TILE_SIZE),
        };
    }

    fn deinit(self: *const Tileset) void {
        rl.UnloadTexture(self.texture);
    }
};

const Layer = struct {
    data: []json.Value,
    cols: i64,
    rows: i64,
};

fn getNumberFloat(value: json.Value) !f32 {
    return switch (value) {
        .integer => |int_val| @floatFromInt(int_val),
        .float => |float_val| @floatCast(float_val),
        else => error.NotANumber,
    };
}

fn getNumberInt(value: json.Value) !i64 {
    return switch (value) {
        .integer => |int_val| @intCast(int_val),
        .float => |float_val| @intFromFloat(float_val),
        else => error.NotANumber,
    };
}

fn drawLayer(tileset: Tileset, layer: Layer) void {
    const layer_rows: usize = @intCast(layer.rows);
    const layer_cols: usize = @intCast(layer.cols);
    const tileset_rows: usize = @intCast(tileset.rows);
    const tileset_cols: usize = @intCast(tileset.cols);

    for (0..layer_rows) |y| {
        for (0..layer_cols) |x| {
            var tile_id: usize = @intCast(layer.data[y * layer_cols + x].integer);
            if (tile_id == 0) continue;

            tile_id -= 1; // subtract firstgid

            // TODO: handle tile rotation
            tile_id &= 0xFF;

            rl.DrawTexturePro(
                tileset.texture,
                .{
                    .x = @floatFromInt(tile_id % tileset_cols * g.TILE_SIZE),
                    .y = @floatFromInt(tile_id / tileset_rows * g.TILE_SIZE),
                    .width = @floatFromInt(g.TILE_SIZE),
                    .height = @floatFromInt(g.TILE_SIZE),
                },
                .{
                    .x = @floatFromInt(x * g.TILE_SIZE),
                    .y = @floatFromInt(y * g.TILE_SIZE),
                    .width = @floatFromInt(g.TILE_SIZE),
                    .height = @floatFromInt(g.TILE_SIZE),
                },
                .{ .x = 0, .y = 0 },
                0,
                rl.WHITE,
            );
        }
    }
}

pub fn main() !void {
    rl.InitWindow(g.SCREEN_WIDTH, g.SCREEN_HEIGHT, "Chauffeur Inc");

    var car = Car.init();
    defer car.deinit();

    var camera = rl.Camera2D{
        .target = rl.Vector2{ .x = car.pos.x, .y = car.pos.y },
        .offset = rl.Vector2{ .x = g.SCREEN_WIDTH / 2.0, .y = g.SCREEN_HEIGHT / 2.0 },
        .rotation = car.angle,
        .zoom = 2,
    };

    rl.SetTargetFPS(g.TARGET_FPS);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const file_contents = try std.fs.cwd().readFileAlloc(allocator, "assets/map.json", 1024 * 1024);
    defer allocator.free(file_contents);

    const parsed = try json.parseFromSlice(json.Value, allocator, file_contents, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const layers = root.object.get("layers").?.array.items;

    std.debug.assert(std.mem.eql(u8, layers[0].object.get("type").?.string, "tilelayer") and
        std.mem.eql(u8, layers[0].object.get("name").?.string, "background"));

    const map_width = root.object.get("width").?.integer;
    const map_height = root.object.get("height").?.integer;

    const background_layer = Layer{
        .data = layers[0].object.get("data").?.array.items,
        .cols = map_width,
        .rows = map_height,
    };

    const buildings_json = layers[2].object.get("objects").?.array.items;
    var buildings = try std.ArrayList(Building).initCapacity(allocator, buildings_json.len);
    defer buildings.deinit();

    for (buildings_json) |b| {
        const x: f32 = try getNumberFloat(b.object.get("x").?);
        const y: f32 = try getNumberFloat(b.object.get("y").?);
        const width: f32 = try getNumberFloat(b.object.get("width").?);
        const height: f32 = try getNumberFloat(b.object.get("height").?);
        const building = Building.init(x, y, width, height);
        try buildings.append(building);
    }

    const tileset = Tileset.init();
    defer tileset.deinit();

    while (!rl.WindowShouldClose()) {
        const time = rl.GetFrameTime();
        car.update(time);

        camera.target = rl.Vector2{ .x = car.pos.x, .y = car.pos.y };

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.GRAY);

        rl.BeginMode2D(camera);

        drawLayer(tileset, background_layer);

        car.draw();

        // for (&buildings) |building| {
        //     building.draw();
        // }

        // const car_vertices = collision.get_vertices(&car.rect(), car.angle);
        // for (car_vertices, 0..) |vertex, i| {
        //     const color = switch (i) {
        //         0 => rl.RED,
        //         1 => rl.GREEN,
        //         2 => rl.BLUE,
        //         3 => rl.YELLOW,
        //         else => rl.WHITE,
        //     };
        //     rl.DrawCircleV(vertex, 6, color);
        // }

        // for (buildings) |building| {
        //     const building_verices = collision.get_vertices(&building.rect, 0);
        //     for (building_verices, 0..) |vertex, i| {
        //         const color = switch (i) {
        //             0 => rl.RED,
        //             1 => rl.GREEN,
        //             2 => rl.BLUE,
        //             3 => rl.YELLOW,
        //             else => rl.WHITE,
        //         };
        //         rl.DrawCircleV(vertex, 6, color);
        //     }
        // }

        // const vel_end = rl.Vector2Add(car.pos, rl.Vector2Scale(car.vel, 0.5));
        // rl.DrawLineEx(car.pos, vel_end, 2, rl.WHITE);

        rl.EndMode2D();

        rl.DrawText(rl.TextFormat("throttle: %.1f", car.throttle), 10, 10, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("brake: %.1f", car.brake), 10, 35, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("steer: %.2f", car.steer), 10, 60, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("angular_vel: %.2f", car.angular_vel), 10, 110, 20, rl.WHITE);
        rl.DrawText(rl.TextFormat("vel: %.2f", rl.Vector2Length(car.vel)), 10, 135, 20, rl.WHITE);

        // for (buildings.items) |building| {
        //     const result = collision.collide(
        //         &car.rect(),
        //         car.angle,
        //         &building.rect,
        //         0,
        //     );
        //
        //     if (result) |res| {
        //         const push = rl.Vector2Scale(res.normal, -res.depth);
        //         car.pos = rl.Vector2Add(car.pos, push);
        //
        //         const tangent = rl.Vector2{ .x = res.normal.y, .y = -res.normal.x };
        //
        //         const num = -g.ELASTICITY * rl.Vector2DotProduct(rl.Vector2Subtract(car.vel, rl.Vector2Zero()), res.normal);
        //         const den_lin = 1 / car.mass;
        //         const den_ang = rl.Vector2DotProduct(res.normal, rl.Vector2Scale(tangent, 1 / car.inertia));
        //         const impulse = num / (den_lin + den_ang);
        //
        //         car.vel = rl.Vector2Add(car.vel, rl.Vector2Scale(res.normal, impulse / car.mass));
        //         car.angular_vel += tangent.x * impulse / car.inertia;
        //     }
        // }
    }
}
