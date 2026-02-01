const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const Map = @import("Map.zig");
const Car = @import("Car.zig");
const Passenger = @import("Passenger.zig");

const Self = @This();

player: Car,
passenger: ?Passenger,
pickups: u32,

pub fn init(map: *const Map) Self {
    const init_node = map.nodes.items[0];

    var player = Car.init(true, init_node.pos.x, init_node.pos.y);
    player.curr_node = init_node.id;

    return .{
        .player = player,
        .passenger = Passenger.init(map),
        .pickups = 0,
    };
}

pub fn deinit(self: *Self) void {
    self.player.deinit();
}

fn clampToScreen(pos: rl.Vector2, padding: f32) rl.Vector2 {
    const w: f32 = @floatFromInt(rl.GetScreenWidth());
    const h: f32 = @floatFromInt(rl.GetScreenHeight());
    return .{
        .x = math.clamp(pos.x, 2 * padding, w - 2 * padding),
        .y = math.clamp(pos.y, 2 * padding, h - 2 * padding),
    };
}

fn isOnScreen(screen_pos: rl.Vector2) bool {
    const w: f32 = @floatFromInt(rl.GetScreenWidth());
    const h: f32 = @floatFromInt(rl.GetScreenHeight());
    return screen_pos.x >= 0 and screen_pos.x <= w and
        screen_pos.y >= 0 and screen_pos.y <= h;
}

pub fn spawnPassenger(self: *Self, map: *const Map) void {
    self.passenger = Passenger.init(map);
}

pub fn update(self: *Self, camera: *rl.Camera2D, map: *const Map) void {
    const time = rl.GetFrameTime();

    self.player.update(time, map);

    if (self.passenger) |*passenger| {
        switch (passenger.state) {
            .waiting => {
                if (rl.Vector2Distance(self.player.pos, passenger.start_pos) <= g.PASSENGER_PICKUP_DISTANCE) {
                    passenger.state = .in_car;
                }
            },
            .in_car => {
                if (rl.Vector2Distance(self.player.pos, passenger.end_pos) <= g.PASSENGER_PICKUP_DISTANCE and self.player.speed == 0) {
                    passenger.state = .delivered;
                }
            },
            .delivered => {
                self.pickups += 1;
                self.spawnPassenger(map);
            },
        }
    }

    camera.zoom = 2;

    const view_half_x = (g.SCREEN_WIDTH / 2) / camera.zoom;
    const view_half_y = (g.SCREEN_HEIGHT / 2) / camera.zoom;
    camera.target = rl.Vector2Lerp(
        camera.target,
        .{
            .x = math.clamp(self.player.pos.x, view_half_x, g.SCREEN_WIDTH - view_half_x),
            .y = math.clamp(self.player.pos.y, view_half_y, g.SCREEN_HEIGHT - view_half_y),
        },
        0.2,
    );
}

pub fn draw(self: *Self, camera: *rl.Camera2D, map: *Map, is_debug: bool) void {
    rl.BeginMode2D(camera.*);
    {
        map.drawTiles(.all);
        map.drawRoads(.all);

        if (self.passenger) |*passenger| passenger.draw();

        map.drawSprites(.all);
        if (is_debug) {
            map.drawDebug();
        }

        self.player.draw();

        if (is_debug) {
            if (self.player.next_node) |target_index| {
                const target = map.nodes.items[target_index];
                rl.DrawCircleV(target.pos, 10, rl.RED);
            }
        }
    }
    rl.EndMode2D();

    if (self.passenger) |passenger| {
        const pos = rl.GetWorldToScreen2D(
            switch (passenger.state) {
                .waiting => passenger.start_pos,
                .in_car, .delivered => passenger.end_pos,
            },
            camera.*,
        );
        if (!isOnScreen(pos)) {
            const size = 32.0;
            const clamped = clampToScreen(pos, size / 2);
            rl.DrawRectanglePro(
                .{ .width = size, .height = size, .x = clamped.x, .y = clamped.y },
                .{ .x = 16, .y = 16 },
                0,
                rl.RED,
            );
        }
    }

    rl.DrawText(rl.TextFormat("vel: %.2f", rl.Vector2Length(self.player.vel)), 10, 10, 20, rl.WHITE);
    rl.DrawText(rl.TextFormat("pos: %.f, %.f", self.player.pos.x, self.player.pos.y), 10, 35, 20, rl.WHITE);

    const mouse_pos = rl.GetMousePosition();
    rl.DrawText(rl.TextFormat("mouse: %.f, %.f", mouse_pos.x, mouse_pos.y), 10, 60, 20, rl.WHITE);

    rl.DrawText(rl.TextFormat("pickups: %d", self.pickups), 10, 85, 20, rl.WHITE);
}
