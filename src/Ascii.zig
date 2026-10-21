const std = @import("std");

const c = @import("constants.zig");
const rl = @import("raylib.zig").rl;

const Game = @import("Game.zig");
const Map = @import("Map.zig");

/// Width of the ASCII grid, in characters.
pub const COLS = 96;

/// Height of the ASCII grid, in characters.
pub const ROWS = 36;

/// Simulated time (in seconds) of the frame that is being rendered.
///
/// The renderer has no access to the simulation clock (the game state does not
/// keep one), so the caller pushes the current time in before rendering. It is
/// only used for the summary line at the bottom of the frame.
var sim_time: f32 = 0;

/// Tell the renderer which simulated time the next frame belongs to.
pub fn setSimTime(t: f32) void {
    sim_time = t;
}

/// Cheap top-down text view of the world for terminal-only iteration.
///
/// The world (0..WORLD_WIDTH x 0..WORLD_HEIGHT) is squeezed into a fixed
/// COLS x ROWS character grid. The returned slice is owned by the caller and
/// is allocated with `allocator`.
pub fn render(allocator: std.mem.Allocator, game: *const Game, map: *const Map) ![]u8 {
    var grid: [ROWS][COLS]u8 = undefined;
    for (&grid) |*row| @memset(row, ' ');

    const scale_x = @as(f32, COLS) / @as(f32, c.WORLD_WIDTH);
    const scale_y = @as(f32, ROWS) / @as(f32, c.WORLD_HEIGHT);

    // Roads first, they are the background.
    for (map.edges.items) |edge| {
        if (edge.from >= map.nodes.items.len or edge.to >= map.nodes.items.len) continue;
        const from = map.nodes.items[edge.from].pos;
        const to = map.nodes.items[edge.to].pos;
        drawLine(&grid, from, to, scale_x, scale_y, '#');
    }

    // Nodes on top of the roads.
    for (map.nodes.items) |node| {
        const ch: u8 = switch (node.type) {
            .start => 'S',
            .end => 'E',
            .default => 'o',
        };
        putPoint(&grid, node.pos, scale_x, scale_y, ch);
    }

    // Traffic.
    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (game.spawn_timers[idx] > 0) continue;
        putPoint(&grid, game.agents[idx].car.visualPos(), scale_x, scale_y, 'a');
    }

    // Passenger: '1' while it waits on the street, '2' while it rides along.
    if (game.passenger) |passenger| {
        switch (passenger.state) {
            .waiting => putPoint(&grid, passenger.start_pos, scale_x, scale_y, '1'),
            .in_car => putPoint(&grid, passenger.end_pos, scale_x, scale_y, '2'),
            .delivered, .expired => {},
        }
    }

    // The player is drawn last, it must never be hidden by the traffic.
    putPoint(&grid, game.player.visualPos(), scale_x, scale_y, '@');

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    try out.ensureTotalCapacity(allocator, (ROWS + 3) * (COLS + 2));

    for (0..ROWS) |row| {
        try out.appendSlice(allocator, &grid[row]);
        try out.append(allocator, '\n');
    }

    try out.appendSlice(allocator, "legend: @ player  a agent  o node  S start  E end  # road  1 waiting  2 in-car\n");

    const player_pos = game.player.visualPos();
    const target = targetOf(game, map);
    const pass_state: []const u8 = if (game.passenger) |passenger| @tagName(passenger.state) else "none";

    try out.print(
        allocator,
        "t={d:>5.1} P@({d:.0},{d:.0}) pass={s} target=({d:.0},{d:.0}) money=${d} combo={d}\n",
        .{
            sim_time,
            player_pos.x,
            player_pos.y,
            pass_state,
            target.x,
            target.y,
            game.money,
            game.combo,
        },
    );

    return out.toOwnedSlice(allocator);
}

/// The point the player is currently heading for: the passenger while it is
/// active, otherwise the next node on the road.
fn targetOf(game: *const Game, map: *const Map) rl.Vector2 {
    if (game.passenger) |passenger| {
        switch (passenger.state) {
            .waiting => return passenger.start_pos,
            .in_car => return passenger.end_pos,
            .delivered, .expired => {},
        }
    }

    if (game.player.next_node) |next_index| {
        if (next_index < map.nodes.items.len) return map.nodes.items[next_index].pos;
    }

    return game.player.visualPos();
}

/// Convert a world position into grid coordinates.
fn toCell(pos: rl.Vector2, scale_x: f32, scale_y: f32) struct { col: i32, row: i32 } {
    const col = @as(i32, @intFromFloat(@floor(pos.x * scale_x)));
    const row = @as(i32, @intFromFloat(@floor(pos.y * scale_y)));
    return .{
        .col = std.math.clamp(col, 0, @as(i32, COLS) - 1),
        .row = std.math.clamp(row, 0, @as(i32, ROWS) - 1),
    };
}

/// Absolute value of a signed integer (`@abs` would return an unsigned type).
fn absI32(value: i32) i32 {
    return if (value < 0) -value else value;
}

/// Write a single character into the grid.
fn putPoint(
    grid: *[ROWS][COLS]u8,
    pos: rl.Vector2,
    scale_x: f32,
    scale_y: f32,
    ch: u8,
) void {
    if (!std.math.isFinite(pos.x) or !std.math.isFinite(pos.y)) return;
    const cell = toCell(pos, scale_x, scale_y);
    grid[@intCast(cell.row)][@intCast(cell.col)] = ch;
}

/// Bresenham line between two world positions.
fn drawLine(
    grid: *[ROWS][COLS]u8,
    from: rl.Vector2,
    to: rl.Vector2,
    scale_x: f32,
    scale_y: f32,
    ch: u8,
) void {
    if (!std.math.isFinite(from.x) or !std.math.isFinite(from.y)) return;
    if (!std.math.isFinite(to.x) or !std.math.isFinite(to.y)) return;

    const start = toCell(from, scale_x, scale_y);
    const end = toCell(to, scale_x, scale_y);

    var x = start.col;
    var y = start.row;
    const dx = absI32(end.col - start.col);
    const dy = -absI32(end.row - start.row);
    const step_x: i32 = if (start.col < end.col) 1 else -1;
    const step_y: i32 = if (start.row < end.row) 1 else -1;
    var err = dx + dy;

    while (true) {
        grid[@intCast(y)][@intCast(x)] = ch;
        if (x == end.col and y == end.row) break;

        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x += step_x;
        }
        if (e2 <= dx) {
            err += dx;
            y += step_y;
        }
    }
}
