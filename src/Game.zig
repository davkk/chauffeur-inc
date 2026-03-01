const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const c = @import("constants.zig");

const Game = @import("Game.zig");
const Map = @import("Map.zig");
const Direction = Map.Direction;
const Car = @import("Car.zig");
const Agent = @import("Agent.zig");
const Passenger = @import("Passenger.zig");

const Self = @This();

pub const KeyInput = struct {
    dir: ?Direction,
    brake: bool,
    dodge: bool,

    pub fn init(dir: ?Direction, brake: bool, dodge: bool) KeyInput {
        return .{ .dir = dir, .brake = brake, .dodge = dodge };
    }
};

player: Car,
passenger: ?Passenger,
pickups: u32,

agents: [c.TARGET_AGENT_COUNT]Agent,
spawn_timers: [c.TARGET_AGENT_COUNT]f32,

pub fn init(map: *const Map) Self {
    const init_node = &map.nodes.items[0];

    const player = Car.init(init_node);

    var agents: [c.TARGET_AGENT_COUNT]Agent = undefined;
    var spawn_timers: [c.TARGET_AGENT_COUNT]f32 = undefined;

    for (0..c.TARGET_AGENT_COUNT) |idx| {
        agents[idx] = Agent.init(map);
        const delay: f32 = @floatFromInt(idx);
        spawn_timers[idx] = delay * c.AGENT_SPAWN_INTERVAL;
    }

    return .{
        .player = player,
        .passenger = Passenger.init(map),
        .pickups = 0,
        .agents = agents,
        .spawn_timers = spawn_timers,
    };
}

pub fn deinit(self: *Self) void {
    self.player.deinit();
}

pub fn update(self: *Self, camera: *rl.Camera2D, map: *const Map) void {
    const time = rl.GetFrameTime();

    const player_input = getPlayerInput();
    self.player.update(time, map, player_input);

    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (self.spawn_timers[idx] > 0) {
            self.spawn_timers[idx] -= time;
            continue;
        }
        var agent = &self.agents[idx];
        agent.update(time, map, &self.agents, &self.player);
    }

    if (self.passenger) |*passenger| {
        switch (passenger.state) {
            .waiting => {
                if (rl.Vector2Distance(self.player.pos, passenger.start_pos) <= c.PASSENGER_PICKUP_DISTANCE) {
                    passenger.state = .in_car;
                }
            },
            .in_car => {
                if (rl.Vector2Distance(self.player.pos, passenger.end_pos) <= c.PASSENGER_PICKUP_DISTANCE and self.player.speed == 0) {
                    passenger.state = .delivered;
                }
            },
            .delivered => {
                self.pickups += 1;
                self.spawnPassenger(map);
            },
        }
    }

    camera.zoom = 1.5;

    const view_half_x = (c.SCREEN_WIDTH / 2) / camera.zoom;
    const view_half_y = (c.SCREEN_HEIGHT / 2) / camera.zoom;
    camera.target = rl.Vector2Lerp(
        camera.target,
        .{
            .x = math.clamp(self.player.pos.x, view_half_x, c.SCREEN_WIDTH - view_half_x),
            .y = math.clamp(self.player.pos.y, view_half_y, c.SCREEN_HEIGHT - view_half_y),
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

        const player_alpha: f32 = if (self.isOverlappingWithAny(&self.player)) 0.5 else 1.0;
        self.player.draw(player_alpha);

        for (0..c.TARGET_AGENT_COUNT) |idx| {
            if (self.spawn_timers[idx] <= 0) {
                const alpha: f32 = if (self.isOverlappingWithAny(&self.agents[idx].car)) 0.5 else 1.0;
                self.agents[idx].car.draw(alpha);
            }
        }

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

fn isOverlappingWithAny(self: *const Self, car: *const Car) bool {
    const car_rect = car.getCollisionRect();

    if (car.curr_node != self.player.curr_node or car.pos.x != self.player.pos.x or car.pos.y != self.player.pos.y) {
        const player_rect = self.player.getCollisionRect();
        if (rl.CheckCollisionRecs(car_rect, player_rect)) {
            return true;
        }
    }

    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (self.spawn_timers[idx] > 0) continue;

        const other = &self.agents[idx].car;
        if (car.curr_node == other.curr_node and car.pos.x == other.pos.x and car.pos.y == other.pos.y) continue;

        const other_rect = other.getCollisionRect();
        if (rl.CheckCollisionRecs(car_rect, other_rect)) {
            return true;
        }
    }

    return false;
}

pub fn spawnPassenger(self: *Self, map: *const Map) void {
    self.passenger = Passenger.init(map);
}

fn getPlayerInput() Game.KeyInput {
    const dir = if (rl.IsKeyDown(rl.KEY_W) or rl.IsKeyDown(rl.KEY_UP))
        Direction.up
    else if (rl.IsKeyDown(rl.KEY_S) or rl.IsKeyDown(rl.KEY_DOWN))
        Direction.down
    else if (rl.IsKeyDown(rl.KEY_A) or rl.IsKeyDown(rl.KEY_LEFT))
        Direction.left
    else if (rl.IsKeyDown(rl.KEY_D) or rl.IsKeyDown(rl.KEY_RIGHT))
        Direction.right
    else
        null;

    return .{
        .dir = dir,
        .brake = rl.IsKeyDown(rl.KEY_SPACE),
        .dodge = rl.IsKeyDown(rl.KEY_P),
    };
}
