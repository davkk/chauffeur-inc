const std = @import("std");
const math = std.math;

const rl = @import("raylib.zig").rl;
const c = @import("constants.zig");

const Game = @import("Game.zig");
const Map = @import("Map.zig");

// ------------------------------------------------------------------ palette

const TAXI_YELLOW = rl.Color{ .r = 245, .g = 197, .b = 66, .a = 255 };
const INK = rl.Color{ .r = 16, .g = 18, .b = 22, .a = 255 };
const PANEL = rl.Color{ .r = 16, .g = 18, .b = 22, .a = 215 };
const WHITE = rl.WHITE;
const BLUE = rl.Color{ .r = 70, .g = 150, .b = 255, .a = 255 };
const GREEN = rl.Color{ .r = 90, .g = 210, .b = 130, .a = 255 };
const RED = rl.Color{ .r = 235, .g = 80, .b = 80, .a = 255 };
const GRAY = rl.Color{ .r = 150, .g = 150, .b = 150, .a = 255 };

/// Hairline that separates a panel from the busy world behind it.
const HAIRLINE = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 26 };
/// Unfilled part of the patience / delivery timer bars.
const TRACK = rl.Color{ .r = 60, .g = 60, .b = 60, .a = 255 };

const SCREEN_W: f32 = @floatFromInt(c.SCREEN_WIDTH);
const SCREEN_H: f32 = @floatFromInt(c.SCREEN_HEIGHT);

/// One world pixel is worth this many metres on the HUD.
const PX_PER_METER = 8.0;
/// `Game.setEvent` keeps a popup alive for 1.4 s.
const EVENT_DURATION = 1.4;
/// Combo count from which the combo badge is worth highlighting.
const COMBO_HIGHLIGHT = 3;

// ------------------------------------------------------------------- layout

const TOP_LEFT_RECT = rl.Rectangle{ .x = 16, .y = 16, .width = 240, .height = 96 };
const OBJECTIVE_RECT = rl.Rectangle{ .x = (SCREEN_W - 380) / 2, .y = 16, .width = 380, .height = 72 };
const MINIMAP_RECT = rl.Rectangle{ .x = SCREEN_W - 256, .y = 16, .width = 240, .height = 168 };
const BOTTOM_LEFT_RECT = rl.Rectangle{ .x = 16, .y = SCREEN_H - 90, .width = 240, .height = 74 };

/// The world point the player currently has to reach, plus its HUD colour.
const Objective = struct {
    pos: rl.Vector2,
    color: rl.Color,
};

/// World-space objective markers. Called between BeginMode2D/EndMode2D.
pub fn drawWorld(game: *const Game, camera: rl.Camera2D) void {
    _ = camera;

    // Visual-only pulse: gameplay never reads the clock.
    const t: f32 = @floatCast(rl.GetTime());

    // The player drives the same taxi sprite as the traffic, so a pulsing
    // ring around the car keeps it readable in a crowd. Draw it before the
    // objective marker so a pickup ring always wins when they overlap.
    const player_pos = game.player.visualPos();
    const player_radius = 26.0 + 2.0 * @sin(t * 4.0);
    rl.DrawRing(
        player_pos,
        player_radius - 1.5,
        player_radius,
        0,
        360,
        40,
        rl.ColorAlpha(WHITE, 0.38),
    );

    const objective = currentObjective(game) orelse return;

    const radius = 24.0 + 4.0 * @sin(t * 5.0);
    rl.DrawRing(
        objective.pos,
        radius - 3.0,
        radius,
        0,
        360,
        32,
        rl.ColorAlpha(objective.color, 0.85),
    );

    // Marker triangle hovering ~28 px above the objective, bobbing gently.
    const bob = @sin(t * 3.0) * 3.0;
    const base_y = objective.pos.y - 28.0 + bob;
    const tip = rl.Vector2{ .x = objective.pos.x, .y = base_y + 9.0 };
    const left = rl.Vector2{ .x = objective.pos.x - 10.0, .y = base_y - 8.0 };
    const right = rl.Vector2{ .x = objective.pos.x + 10.0, .y = base_y - 8.0 };
    drawTriangleWithOutline(tip, left, right, objective.color);
}

/// Screen-space HUD: money, timer, minimap, objective arrow and messages.
/// Called outside camera mode.
pub fn drawScreen(game: *const Game, map: *const Map, camera: rl.Camera2D, is_debug: bool) void {
    drawTopLeftPanel(game);
    drawObjectivePanel(game);
    drawMinimap(game, map, camera);
    drawBottomLeftPanel(game);

    // The arrow floats on top of the panels so it is never hidden by them.
    drawObjectiveArrow(game, camera);
    drawFlash(game);
    drawEventPopup(game, camera);
    drawAchievementPopup(game);
    drawHint(game);

    if (is_debug) drawDebugOverlay(game);
}

// ----------------------------------------------------------------- helpers

fn currentObjective(game: *const Game) ?Objective {
    const passenger = game.passenger orelse return null;
    return switch (passenger.state) {
        .waiting => .{ .pos = passenger.start_pos, .color = BLUE },
        .in_car => .{ .pos = passenger.end_pos, .color = TAXI_YELLOW },
        .delivered, .expired => null,
    };
}

fn drawPanel(rect: rl.Rectangle) void {
    rl.DrawRectangleRounded(rect, 0.12, 6, PANEL);
    rl.DrawRectangleLinesEx(rect, 1, HAIRLINE);
}

/// Scale a colour's alpha by `factor` (0 = invisible, 1 = unchanged).
fn fadeColor(color: rl.Color, factor: f32) rl.Color {
    const a = @as(f32, @floatFromInt(color.a)) * factor;
    return .{ .r = color.r, .g = color.g, .b = color.b, .a = @intFromFloat(a) };
}

fn textWidth(text: [*c]const u8, size: c_int) f32 {
    return @floatFromInt(rl.MeasureText(text, size));
}

fn drawText(text: [*c]const u8, x: f32, y: f32, size: c_int, color: rl.Color) void {
    rl.DrawText(text, @intFromFloat(x), @intFromFloat(y), size, color);
}

fn drawTextCentered(text: [*c]const u8, cx: f32, y: f32, size: c_int, color: rl.Color) void {
    drawText(text, cx - textWidth(text, size) / 2.0, y, size, color);
}

fn drawTextRight(text: [*c]const u8, rx: f32, y: f32, size: c_int, color: rl.Color) void {
    drawText(text, rx - textWidth(text, size), y, size, color);
}

fn growAround(p: rl.Vector2, center: rl.Vector2, factor: f32) rl.Vector2 {
    return .{ .x = center.x + (p.x - center.x) * factor, .y = center.y + (p.y - center.y) * factor };
}

/// Filled triangle with a chunky dark outline, drawn as a slightly larger
/// triangle underneath.
fn drawTriangleWithOutline(v1: rl.Vector2, v2: rl.Vector2, v3: rl.Vector2, fill: rl.Color) void {
    const centroid = rl.Vector2{
        .x = (v1.x + v2.x + v3.x) / 3.0,
        .y = (v1.y + v2.y + v3.y) / 3.0,
    };
    rl.DrawTriangle(
        growAround(v1, centroid, 1.28),
        growAround(v2, centroid, 1.28),
        growAround(v3, centroid, 1.28),
        INK,
    );
    rl.DrawTriangle(v1, v2, v3, fill);
}

/// Progress bar with a dark track. Green while there is plenty of time,
/// yellow when it is getting short, red when it is about to run out.
fn drawBar(x0: f32, x1: f32, y: f32, ratio: f32) void {
    const height: f32 = 8.0;
    const clamped = math.clamp(ratio, 0.0, 1.0);
    const width = x1 - x0;

    rl.DrawRectangle(@intFromFloat(x0), @intFromFloat(y), @intFromFloat(width), @intFromFloat(height), TRACK);
    if (clamped > 0.0) {
        const fill = if (clamped > 0.5) GREEN else if (clamped > 0.25) TAXI_YELLOW else RED;
        rl.DrawRectangle(@intFromFloat(x0), @intFromFloat(y), @intFromFloat(width * clamped), @intFromFloat(height), fill);
    }
    rl.DrawRectangleLinesEx(
        .{ .x = x0, .y = y, .width = width, .height = height },
        1,
        INK,
    );
}

fn distanceMeters(from: rl.Vector2, to: rl.Vector2) f32 {
    return rl.Vector2Distance(from, to) / PX_PER_METER;
}

// ------------------------------------------------------------- top left HUD

fn drawTopLeftPanel(game: *const Game) void {
    drawPanel(TOP_LEFT_RECT);

    const money = rl.TextFormat("$%d", @as(c_int, @intCast(game.money)));
    drawText(money, TOP_LEFT_RECT.x + 12, TOP_LEFT_RECT.y + 8, 36, TAXI_YELLOW);

    const delivered = rl.TextFormat("DELIVERED %d", @as(c_int, @intCast(game.pickups)));
    drawText(delivered, TOP_LEFT_RECT.x + 12, TOP_LEFT_RECT.y + 50, 18, WHITE);

    if (game.best_combo >= COMBO_HIGHLIGHT) {
        const best = rl.TextFormat("BEST COMBO x%d", @as(c_int, @intCast(game.best_combo)));
        drawText(best, TOP_LEFT_RECT.x + 12, TOP_LEFT_RECT.y + 72, 16, GRAY);
    }
}

// ---------------------------------------------------------- objective panel

fn drawObjectivePanel(game: *const Game) void {
    drawPanel(OBJECTIVE_RECT);

    const left = OBJECTIVE_RECT.x + 16;
    const right = OBJECTIVE_RECT.x + OBJECTIVE_RECT.width - 16;
    const bar_y = OBJECTIVE_RECT.y + OBJECTIVE_RECT.height - 14;

    const passenger = game.passenger orelse {
        drawText("LOOKING FOR FARE", left, OBJECTIVE_RECT.y + 14, 20, GRAY);
        return;
    };

    switch (passenger.state) {
        .waiting => {
            drawText("PICKUP", left, OBJECTIVE_RECT.y + 10, 20, BLUE);

            const fare = rl.TextFormat("$%d", @as(c_int, @intCast(passenger.fare)));
            drawTextRight(fare, right, OBJECTIVE_RECT.y + 6, 24, TAXI_YELLOW);

            const meters = @as(c_int, @intFromFloat(@round(distanceMeters(game.player.visualPos(), passenger.start_pos))));
            const distance = rl.TextFormat("%d m", @as(c_int, @intCast(meters)));
            drawText(distance, left, OBJECTIVE_RECT.y + 36, 16, GRAY);

            const ratio = if (passenger.patience_max > 0)
                passenger.patience / passenger.patience_max
            else
                0;
            drawBar(left, right, bar_y, ratio);
        },
        .in_car => {
            drawText("DROP OFF", left, OBJECTIVE_RECT.y + 10, 20, TAXI_YELLOW);

            const fare = rl.TextFormat("$%d", @as(c_int, @intCast(passenger.fare)));
            drawTextRight(fare, right, OBJECTIVE_RECT.y + 6, 24, TAXI_YELLOW);

            const meters = @as(c_int, @intFromFloat(@round(distanceMeters(game.player.visualPos(), passenger.end_pos))));
            const distance = rl.TextFormat("%d m", @as(c_int, @intCast(meters)));
            drawText(distance, left, OBJECTIVE_RECT.y + 36, 16, GRAY);

            const ratio = if (passenger.time_max > 0)
                passenger.time_left / passenger.time_max
            else
                0;
            drawBar(left, right, bar_y, ratio);
        },
        .delivered => {
            drawText("DELIVERED", left, OBJECTIVE_RECT.y + 10, 22, GREEN);

            // The earned amount is only known while the delivery event is
            // alive; it outlives the short "delivered" passenger state.
            const earned = if (game.last_event == .delivered) game.event_amount else passenger.fare;
            const amount = rl.TextFormat("+$%d", @as(c_int, @intCast(earned)));
            drawTextRight(amount, right, OBJECTIVE_RECT.y + 6, 24, TAXI_YELLOW);

            drawText("next passenger...", left, OBJECTIVE_RECT.y + 40, 14, GRAY);
        },
        .expired => {
            drawText("PASSENGER LEFT", left, OBJECTIVE_RECT.y + 10, 22, RED);
            drawText("combo reset", left, OBJECTIVE_RECT.y + 40, 14, GRAY);
        },
    }
}

// ----------------------------------------------------------------- minimap

const MiniTransform = struct {
    ox: f32,
    oy: f32,
    scale: f32,

    fn apply(self: MiniTransform, p: rl.Vector2) rl.Vector2 {
        return .{ .x = self.ox + p.x * self.scale, .y = self.oy + p.y * self.scale };
    }
};

fn drawMinimap(game: *const Game, map: *const Map, camera: rl.Camera2D) void {
    drawPanel(MINIMAP_RECT);
    drawText("MAP", MINIMAP_RECT.x + 10, MINIMAP_RECT.y + 6, 14, GRAY);

    // Inner map area: 10 px padding around the edges, extra room on top for
    // the "MAP" caption.
    const inner = rl.Rectangle{
        .x = MINIMAP_RECT.x + 10,
        .y = MINIMAP_RECT.y + 24,
        .width = MINIMAP_RECT.width - 20,
        .height = MINIMAP_RECT.height - 34,
    };

    const world_w: f32 = @floatFromInt(c.WORLD_WIDTH);
    const world_h: f32 = @floatFromInt(c.WORLD_HEIGHT);
    const scale = @min(inner.width / world_w, inner.height / world_h);
    const xf = MiniTransform{
        .ox = inner.x + (inner.width - world_w * scale) / 2.0,
        .oy = inner.y + (inner.height - world_h * scale) / 2.0,
        .scale = scale,
    };

    // Roads: the edge list holds every street twice (once per direction),
    // so only the lower id half is drawn.
    for (map.edges.items) |edge| {
        if (edge.from >= map.nodes.items.len or edge.to >= map.nodes.items.len) continue;
        if (edge.from >= edge.to) continue;
        const a = map.nodes.items[edge.from].pos;
        const b = map.nodes.items[edge.to].pos;
        rl.DrawLineEx(xf.apply(a), xf.apply(b), 4.0, rl.ColorAlpha(GRAY, 0.8));
    }

    for (map.nodes.items) |node| {
        if (!node.active) continue;
        rl.DrawCircleV(xf.apply(node.pos), 2.0, rl.ColorAlpha(GRAY, 0.6));
    }

    // Camera view rectangle, so the player can see what is on screen.
    const zoom = camera.zoom;
    const view_left = camera.target.x - camera.offset.x / zoom;
    const view_top = camera.target.y - camera.offset.y / zoom;
    const view_right = camera.target.x + (SCREEN_W - camera.offset.x) / zoom;
    const view_bottom = camera.target.y + (SCREEN_H - camera.offset.y) / zoom;
    const top_left = xf.apply(.{ .x = view_left, .y = view_top });
    rl.DrawRectangleLinesEx(
        .{
            .x = top_left.x,
            .y = top_left.y,
            .width = (view_right - view_left) * scale,
            .height = (view_bottom - view_top) * scale,
        },
        1,
        rl.Color{ .r = 255, .g = 255, .b = 255, .a = 50 },
    );

    // Traffic.
    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (game.spawn_timers[idx] > 0) continue;
        rl.DrawCircleV(xf.apply(game.agents[idx].car.pos), 3.0, GRAY);
    }

    // The player: a yellow dot with a short tick showing the heading.
    const player_pos = xf.apply(game.player.visualPos());
    rl.DrawCircleV(player_pos, 5.0, TAXI_YELLOW);
    const heading_rad = game.player.angle * math.pi / 180.0;
    const heading = rl.Vector2{ .x = @sin(heading_rad), .y = -@cos(heading_rad) };
    rl.DrawLineEx(player_pos, rl.Vector2Add(player_pos, rl.Vector2Scale(heading, 8.0)), 2.0, WHITE);

    // Passenger objective.
    const t: f32 = @floatCast(rl.GetTime());
    if (game.passenger) |passenger| {
        switch (passenger.state) {
            .waiting => drawMinimapTarget(xf.apply(passenger.start_pos), BLUE, t),
            .in_car => drawMinimapTarget(xf.apply(passenger.end_pos), TAXI_YELLOW, t),
            .delivered, .expired => {},
        }
    }
}

fn drawMinimapTarget(pos: rl.Vector2, color: rl.Color, t: f32) void {
    const radius = 8.0 + 2.0 * @sin(t * 4.0);
    rl.DrawRing(pos, radius - 1.5, radius, 0, 360, 20, rl.ColorAlpha(color, 0.7));
    rl.DrawCircleV(pos, 6.0, color);
}

// --------------------------------------------------------- bottom left HUD

fn drawBottomLeftPanel(game: *const Game) void {
    drawPanel(BOTTOM_LEFT_RECT);

    const left = BOTTOM_LEFT_RECT.x + 12;
    const kmh = @as(c_int, @intFromFloat(@round(game.player.speed * 0.36)));
    const speed = rl.TextFormat("%d", @as(c_int, @intCast(kmh)));
    drawText(speed, left, BOTTOM_LEFT_RECT.y + 8, 32, WHITE);
    drawText("km/h", left + textWidth(speed, 32) + 6, BOTTOM_LEFT_RECT.y + 28, 14, GRAY);

    var combo_text: [*c]const u8 = "x1";
    var combo_color = GRAY;
    if (game.combo >= COMBO_HIGHLIGHT) {
        combo_text = rl.TextFormat("x%d", @as(c_int, @intCast(game.combo)));
        combo_color = TAXI_YELLOW;
    }
    drawTextRight(combo_text, BOTTOM_LEFT_RECT.x + BOTTOM_LEFT_RECT.width - 14, BOTTOM_LEFT_RECT.y + 26, 22, combo_color);
}

// ------------------------------------------------------- objective arrow

/// Arrow at the screen edge pointing at the objective when it is off screen.
fn drawObjectiveArrow(game: *const Game, camera: rl.Camera2D) void {
    const objective = currentObjective(game) orelse return;

    const screen = rl.GetWorldToScreen2D(objective.pos, camera);

    const inset: f32 = 60.0;
    const min_x = inset;
    const max_x = SCREEN_W - inset;
    const min_y = inset;
    const max_y = SCREEN_H - inset;

    if (screen.x >= min_x and screen.x <= max_x and screen.y >= min_y and screen.y <= max_y) return;

    const clamped = rl.Vector2{
        .x = math.clamp(screen.x, min_x, max_x),
        .y = math.clamp(screen.y, min_y, max_y),
    };

    var dir = rl.Vector2Subtract(screen, clamped);
    if (rl.Vector2Length(dir) < 0.001) dir = .{ .x = 0, .y = -1 };
    dir = rl.Vector2Normalize(dir);
    const perp = rl.Vector2{ .x = -dir.y, .y = dir.x };

    const tip = rl.Vector2Add(clamped, rl.Vector2Scale(dir, 10.0));
    const base = rl.Vector2Subtract(clamped, rl.Vector2Scale(dir, 6.0));
    drawTriangleWithOutline(
        tip,
        rl.Vector2Add(base, rl.Vector2Scale(perp, 10.0)),
        rl.Vector2Subtract(base, rl.Vector2Scale(perp, 10.0)),
        objective.color,
    );
}

// ------------------------------------------------------------ event popups

fn drawEventPopup(game: *const Game, camera: rl.Camera2D) void {
    if (game.event_timer <= 0) return;
    if (game.last_event == .none) return;

    const screen = rl.GetWorldToScreen2D(game.event_pos, camera);

    const inset: f32 = 80.0;
    const px = math.clamp(screen.x, inset, SCREEN_W - inset);
    const py = math.clamp(screen.y, inset, SCREEN_H - inset);

    // Float upward while the event is about to expire.
    const progress = math.clamp(1.0 - game.event_timer / EVENT_DURATION, 0.0, 1.0);
    const rise = progress * 34.0;

    switch (game.last_event) {
        .none => {},
        .pickup => {
            drawTextCentered("PICKED UP", px, py - rise, 26, BLUE);
        },
        .delivered => {
            const amount = rl.TextFormat("+$%d", @as(c_int, @intCast(game.event_amount)));
            drawTextCentered(amount, px, py - rise - 12.0, 30, GREEN);

            const multiplier = @min(1 + game.combo / c.COMBO_STEP, c.COMBO_MAX_MULT);
            const mult_text = rl.TextFormat("x%d", @as(c_int, @intCast(multiplier)));
            drawTextCentered(mult_text, px, py - rise + 24.0, 20, TAXI_YELLOW);
        },
        .expired => {
            drawTextCentered("TOO SLOW!", px, py - rise, 28, RED);
        },
        .crash => {
            drawTextCentered("CRASH!", px, py - rise, 28, RED);
        },
    }
}

// ----------------------------------------------------------------- flashes

fn drawFlash(game: *const Game) void {
    if (game.crash_flash > 0) {
        const alpha: u8 = @intFromFloat(@min(90.0 * game.crash_flash / c.CRASH_FLASH_TIME, 255.0));
        rl.DrawRectangle(0, 0, c.SCREEN_WIDTH, c.SCREEN_HEIGHT, .{ .r = 235, .g = 60, .b = 60, .a = alpha });
    }
    if (game.pickup_flash > 0) {
        const alpha: u8 = @intFromFloat(@min(45.0 * game.pickup_flash / c.PICKUP_FLASH_TIME, 255.0));
        rl.DrawRectangle(0, 0, c.SCREEN_WIDTH, c.SCREEN_HEIGHT, .{ .r = 70, .g = 150, .b = 255, .a = alpha });
    }
}

// -------------------------------------------------------- achievement popup
fn achievementName(ach: Game.Achievement) [*c]const u8 {
    return switch (ach) {
        .first_delivery => "First Fare",
        .combo_3 => "Combo x3",
        .combo_6 => "Combo x6",
        .safe_3 => "Safe Driver (3)",
        .safe_7 => "Safe Driver (7)",
        .safe_15 => "Safe Driver (15)",
        .wrong_way_10 => "Wrong Way Pro",
        .speedster => "Top Speed",
        .rich => "Money Bags",
        .marathon => "Marathon Driver",
    };
}

fn drawAchievementPopup(game: *const Game) void {
    const ach = game.achievement_popup orelse return;
    if (game.achievement_timer <= 0) return;

    const fade = @min(game.achievement_timer / 0.5, 1.0);
    const name = achievementName(ach);
    const reward = Game.achievementReward(ach);

    const label = "ACHIEVEMENT UNLOCKED";
    const amount = rl.TextFormat("+$%d", @as(c_int, @intCast(reward)));
    const width = @max(textWidth(label, 18), textWidth(name, 22)) + 40.0;
    const rect = rl.Rectangle{
        .x = (SCREEN_W - width) / 2.0,
        .y = 96,
        .width = width,
        .height = 64,
    };

    rl.DrawRectangleRounded(rect, 0.15, 6, fadeColor(PANEL, fade));
    rl.DrawRectangleLinesEx(rect, 1, fadeColor(TAXI_YELLOW, fade));
    drawTextCentered(label, rect.x + rect.width / 2.0, rect.y + 8, 14, fadeColor(TAXI_YELLOW, fade));
    drawTextCentered(name, rect.x + rect.width / 2.0, rect.y + 26, 20, fadeColor(WHITE, fade));
    drawTextCentered(amount, rect.x + rect.width / 2.0, rect.y + 48, 14, fadeColor(GREEN, fade));
}

// -------------------------------------------------------------- hint panel

fn drawHint(game: *const Game) void {
    if (game.hint_timer <= 0) return;

    // Fade out over the last second.
    const fade = math.clamp(game.hint_timer / 1.0, 0.0, 1.0);

    const line1 = "WASD / ARROWS  drive    SPACE  brake    TAB  change lane    F1  autopilot";
    const line2 = "CTRL+SHIFT+E  map editor";

    const width = @max(textWidth(line1, 16), textWidth(line2, 13)) + 32.0;
    const rect = rl.Rectangle{
        .x = (SCREEN_W - width) / 2.0,
        .y = SCREEN_H - 72,
        .width = width,
        .height = 46,
    };

    rl.DrawRectangleRounded(rect, 0.12, 6, fadeColor(PANEL, fade));
    rl.DrawRectangleLinesEx(rect, 1, fadeColor(HAIRLINE, fade));

    const cx = rect.x + rect.width / 2.0;
    drawTextCentered(line1, cx, rect.y + 8, 16, fadeColor(WHITE, fade));
    drawTextCentered(line2, cx, rect.y + 28, 13, fadeColor(GRAY, fade));
}

// ------------------------------------------------------------------- debug

fn drawDebugOverlay(game: *const Game) void {
    const color = rl.ColorAlpha(GRAY, 0.9);
    var y = TOP_LEFT_RECT.y + TOP_LEFT_RECT.height + 6;

    const fps = rl.TextFormat("FPS %d", rl.GetFPS());
    drawText(fps, TOP_LEFT_RECT.x, y, 14, color);
    y += 16;

    var buf_a: [96]u8 = undefined;
    const node_line = std.fmt.bufPrintZ(&buf_a, "node {?} -> {?} dir {s} speed {d}", .{
        game.player.curr_node,
        game.player.next_node,
        @tagName(game.player.curr_dir),
        @as(c_int, @intFromFloat(@round(game.player.speed))),
    }) catch "node ?";
    drawText(node_line, TOP_LEFT_RECT.x, y, 14, color);
    y += 16;

    var buf_c: [96]u8 = undefined;
    const state_name: [:0]const u8 = if (game.passenger) |passenger| @tagName(passenger.state) else "none";
    const time_left: f32 = if (game.passenger) |passenger| passenger.time_left else 0;
    const pass_line = std.fmt.bufPrintZ(&buf_c, "pass {s} t={d:.1} combo={d}", .{
        state_name,
        time_left,
        game.combo,
    }) catch "pass ?";
    drawText(pass_line, TOP_LEFT_RECT.x, y, 14, color);
    y += 16;

    var moving: u32 = 0;
    var spawned: u32 = 0;
    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (game.spawn_timers[idx] > 0) continue;
        spawned += 1;
        if (game.agents[idx].car.speed > 1.0) moving += 1;
    }
    const agents_line = rl.TextFormat("agents %d/%d", @as(c_int, @intCast(moving)), @as(c_int, @intCast(spawned)));
    drawText(agents_line, TOP_LEFT_RECT.x, y, 14, color);
}
