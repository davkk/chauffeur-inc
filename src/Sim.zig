const std = @import("std");

const c = @import("constants.zig");
const rl = @import("raylib.zig").rl;

const Ascii = @import("Ascii.zig");
const Autopilot = @import("Autopilot.zig");
const Car = @import("Car.zig");
const Game = @import("Game.zig");
const Map = @import("Map.zig");

pub const Options = struct {
    seed: u64 = 1,
    duration: f32 = 60.0,
    runs: u32 = 1,
    dt: f32 = 1.0 / @as(f32, @floatFromInt(c.TARGET_FPS)),
    bot: bool = true,
    trace: bool = false,
    ascii: bool = false,
};

pub const Stats = struct {
    seed: u64 = 0,
    sim_time: f32 = 0,
    steps: u64 = 0,
    deliveries: u32 = 0,
    pickups: u32 = 0,
    expired: u32 = 0,
    crashes: u32 = 0,
    earned: u32 = 0,
    distance: f32 = 0,
    player_stuck_time: f32 = 0,
    agent_resets: u32 = 0,
    out_of_bounds: u32 = 0,
    invalid_state: u32 = 0,
    pass: bool = true,
};

/// How often (in simulated seconds) a trace line / ASCII frame is printed.
const trace_interval: f32 = 5.0;

/// How far outside of the world a car may drift before it counts as a bug.
const bounds_margin: f32 = 64.0;

/// The player counts as stuck below this speed ...
const stuck_speed_low: f32 = 5.0;
/// ... and is considered moving again at (or above) this speed.
const stuck_speed_high: f32 = 10.0;

/// The bot must not stay stuck longer than this.
const max_stuck_time: f32 = 15.0;

/// A delivery is expected from this duration on.
const min_delivery_duration: f32 = 20.0;
/// Traffic must keep flowing from this duration on.
const min_traffic_duration: f32 = 30.0;

const max_reasons = 8;
const reason_buf_len = 160;

/// Values that are not part of `Stats` but are needed for the report.
const FinalState = struct {
    money: u32 = 0,
    best_combo: u32 = 0,
    moving: u32 = 0,
    spawned: u32 = 0,
};

/// Run the headless simulation.
///
/// The caller seeds the shared random source (`raylib.seedRandom`) before
/// calling this function, this function never reseeds it.
pub fn run(allocator: std.mem.Allocator, options: Options) !Stats {
    var map = try Map.initHeadless(allocator);
    defer map.deinit();

    const dt: f32 = if (options.dt > 0)
        options.dt
    else
        1.0 / @as(f32, @floatFromInt(c.TARGET_FPS));

    var stats = Stats{ .seed = options.seed };
    var final_state = FinalState{};

    var autopilot = Autopilot.init();

    const run_count = @max(options.runs, 1);
    var run_index: u32 = 0;
    while (run_index < run_count) : (run_index += 1) {
        autopilot.reset();
        final_state = try simulate(allocator, &map, options, dt, &autopilot, &stats);
    }

    var reasons = ReasonList{};
    evaluate(&stats, options, &reasons);
    stats.pass = reasons.len() == 0;

    printReport(&stats, options, final_state);
    for (reasons.items()) |reason| {
        std.debug.print("reason: {s}\n", .{reason});
    }

    return stats;
}

/// Play one simulation from the start to `options.duration` and fold the
/// results into `stats`.
fn simulate(
    allocator: std.mem.Allocator,
    map: *const Map,
    options: Options,
    dt: f32,
    autopilot: *Autopilot,
    stats: *Stats,
) !FinalState {
    var game = Game.initHeadless(map);
    defer game.deinit();

    const idle_input = Game.KeyInput.init(null, false, false);

    // A fixed number of steps keeps the run reproducible: the simulation time
    // is derived from the step index instead of accumulating `dt` (which would
    // drift and produce one step too many).
    const total_steps: u64 = if (options.duration <= 0)
        0
    else
        @intFromFloat(@round(options.duration / dt));

    var next_trace: f32 = trace_interval;
    var stuck_run: f32 = 0;

    var step_index: u64 = 0;
    while (step_index < total_steps) : (step_index += 1) {
        const input = if (options.bot) autopilot.nextInput(&game, map) else idle_input;

        const before = game.player.visualPos();
        const result = game.step(dt, input, map);
        const after = game.player.visualPos();

        const sim_time = @as(f32, @floatFromInt(step_index + 1)) * dt;
        stats.sim_time = sim_time;
        stats.steps += 1;
        stats.distance += rl.Vector2Distance(before, after);

        if (result.delivered) stats.deliveries += 1;
        if (result.picked_up) stats.pickups += 1;
        if (result.expired) stats.expired += 1;
        if (result.crashed) stats.crashes += 1;
        stats.earned += result.earned;

        updateStuckTime(&game, dt, &stuck_run, stats);
        checkBounds(&game, stats);
        checkValidity(&game, map, stats);

        if (sim_time + 1e-3 >= next_trace) {
            next_trace += trace_interval;
            if (options.trace) printTrace(&game, sim_time);
            if (options.ascii) printAscii(allocator, &game, map, sim_time);
        }
    }

    var resets: u32 = 0;
    for (game.agents) |agent| resets += agent.resets;
    stats.agent_resets += resets;

    return .{
        .money = game.money,
        .best_combo = game.best_combo,
        .moving = countMoving(&game),
        .spawned = countSpawned(&game),
    };
}

/// Track the longest continuous time the player stood still while it had a
/// passenger objective (waiting or riding).
fn updateStuckTime(game: *const Game, dt: f32, stuck_run: *f32, stats: *Stats) void {
    const has_target = if (game.passenger) |passenger|
        passenger.state == .waiting or passenger.state == .in_car
    else
        false;

    if (!has_target) {
        stuck_run.* = 0;
        return;
    }

    if (game.player.speed >= stuck_speed_high) {
        stuck_run.* = 0;
        return;
    }

    if (game.player.speed < stuck_speed_low) {
        stuck_run.* += dt;
        if (stuck_run.* > stats.player_stuck_time) stats.player_stuck_time = stuck_run.*;
    }
}

/// Count cars that left the world (or produced a non finite position).
fn checkBounds(game: *const Game, stats: *Stats) void {
    var out_of_bounds = !posInBounds(game.player.visualPos());

    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (game.agent_waiting[idx] or game.spawn_timers[idx] > 0) continue;
        if (!posInBounds(game.agents[idx].car.visualPos())) out_of_bounds = true;
    }

    if (out_of_bounds) stats.out_of_bounds += 1;
}

fn posInBounds(pos: rl.Vector2) bool {
    if (!std.math.isFinite(pos.x) or !std.math.isFinite(pos.y)) return false;
    if (pos.x < -bounds_margin) return false;
    if (pos.y < -bounds_margin) return false;
    if (pos.x > @as(f32, c.WORLD_WIDTH) + bounds_margin) return false;
    if (pos.y > @as(f32, c.WORLD_HEIGHT) + bounds_margin) return false;
    return true;
}

/// Count broken states: impossible node indices, non finite positions.
fn checkValidity(game: *const Game, map: *const Map, stats: *Stats) void {
    var invalid = !carIsValid(&game.player, map.nodes.items.len);

    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (game.agent_waiting[idx] or game.spawn_timers[idx] > 0) continue;
        if (!carIsValid(&game.agents[idx].car, map.nodes.items.len)) invalid = true;
    }

    if (game.passenger) |passenger| {
        if (!std.math.isFinite(passenger.start_pos.x) or !std.math.isFinite(passenger.start_pos.y)) {
            invalid = true;
        }
        if (!std.math.isFinite(passenger.end_pos.x) or !std.math.isFinite(passenger.end_pos.y)) {
            invalid = true;
        }
    }

    if (invalid) stats.invalid_state += 1;
}

fn carIsValid(car: *const Car, node_count: usize) bool {
    if (car.curr_node) |node| {
        if (node >= node_count) return false;
    }
    if (car.next_node) |node| {
        if (node >= node_count) return false;
    }
    if (!std.math.isFinite(car.speed)) return false;
    if (!std.math.isFinite(car.pos.x) or !std.math.isFinite(car.pos.y)) return false;
    return true;
}

fn countSpawned(game: *const Game) u32 {
    var spawned: u32 = 0;
    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (!game.agent_waiting[idx] and game.spawn_timers[idx] <= 0) spawned += 1;
    }
    return spawned;
}

fn countMoving(game: *const Game) u32 {
    var moving: u32 = 0;
    for (0..c.TARGET_AGENT_COUNT) |idx| {
        if (game.agent_waiting[idx] or game.spawn_timers[idx] > 0) continue;
        if (game.agents[idx].car.speed > stuck_speed_low) moving += 1;
    }
    return moving;
}

/// One line of telemetry, printed every `trace_interval` simulated seconds.
fn printTrace(game: *const Game, sim_time: f32) void {
    const player = &game.player;
    const player_pos = player.visualPos();

    var curr_buf: [16]u8 = undefined;
    var next_buf: [16]u8 = undefined;
    const curr_str = nodeStr(&curr_buf, player.curr_node);
    const next_str = nodeStr(&next_buf, player.next_node);

    var pass_state: []const u8 = "none";
    var fare: u32 = 0;
    var target_distance: f32 = 0;
    if (game.passenger) |passenger| {
        pass_state = @tagName(passenger.state);
        fare = passenger.fare;
        target_distance = switch (passenger.state) {
            .waiting => rl.Vector2Distance(player.pos, passenger.start_pos),
            .in_car => rl.Vector2Distance(player.pos, passenger.end_pos),
            .delivered, .expired => 0,
        };
    }

    std.debug.print(
        "t={d:>5.1} | P {d:.0},{d:.0} v={d:.0} node={s} -> {s} dir={s} | pass {s} ${d} d={d:.0} | ${d} combo={d} | traffic {d}/{d}\n",
        .{
            sim_time,
            player_pos.x,
            player_pos.y,
            player.speed,
            curr_str,
            next_str,
            @tagName(player.curr_dir),
            pass_state,
            fare,
            target_distance,
            game.money,
            game.combo,
            countMoving(game),
            countSpawned(game),
        },
    );
}

fn nodeStr(buf: *[16]u8, node: ?usize) []const u8 {
    if (node) |index| {
        return std.fmt.bufPrint(buf, "{d}", .{index}) catch "-";
    }
    return "-";
}

/// Print one ASCII frame of the world.
fn printAscii(allocator: std.mem.Allocator, game: *const Game, map: *const Map, sim_time: f32) void {
    Ascii.setSimTime(sim_time);
    // The frame is not freed here on purpose: it may live in an arena that
    // outlives the frame itself.
    const text = Ascii.render(allocator, game, map) catch |err| {
        std.debug.print("ascii render failed: {s}\n", .{@errorName(err)});
        return;
    };
    std.debug.print("{s}", .{text});
}

/// Check the run against the pass criteria and collect the reasons for a
/// failure. The reasons are sorted, so the report is deterministic.
fn evaluate(stats: *Stats, options: Options, reasons: *ReasonList) void {
    if (stats.out_of_bounds > 0) {
        reasons.add("out of bounds ({d} steps)", .{stats.out_of_bounds});
    }
    if (stats.invalid_state > 0) {
        reasons.add("invalid state ({d} steps)", .{stats.invalid_state});
    }
    if (options.bot and options.duration >= min_delivery_duration and stats.deliveries == 0) {
        reasons.add("no delivery in {d:.0}s", .{options.duration});
    }
    if (options.bot and options.duration >= min_traffic_duration and stats.agent_resets == 0) {
        reasons.add("traffic stalled (no agent reset)", .{});
    }
    if (options.bot and stats.player_stuck_time >= max_stuck_time) {
        reasons.add("player stuck for {d:.1}s", .{stats.player_stuck_time});
    }
}

/// A fixed size list of failure reasons.
const ReasonList = struct {
    bufs: [max_reasons][reason_buf_len]u8 = undefined,
    slices: [max_reasons][]const u8 = undefined,
    count: usize = 0,

    fn add(self: *ReasonList, comptime fmt: []const u8, args: anytype) void {
        if (self.count >= max_reasons) return;
        const text = std.fmt.bufPrint(&self.bufs[self.count], fmt, args) catch return;
        self.slices[self.count] = text;
        self.count += 1;
    }

    fn len(self: *const ReasonList) usize {
        return self.count;
    }

    /// The reasons, sorted alphabetically so the report never changes order.
    fn items(self: *ReasonList) []const []const u8 {
        std.sort.block([]const u8, self.slices[0..self.count], {}, lessThanStr);
        return self.slices[0..self.count];
    }
};

fn lessThanStr(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

/// Print the final report of the run.
fn printReport(stats: *const Stats, options: Options, final_state: FinalState) void {
    std.debug.print(
        "seed={d} duration={d:.1} steps={d}\n",
        .{ stats.seed, options.duration, stats.steps },
    );
    std.debug.print(
        "player: delivered={d} pickups={d} expired={d} crashes={d} distance={d:.0}px stuck={d:.1}s\n",
        .{
            stats.deliveries,
            stats.pickups,
            stats.expired,
            stats.crashes,
            stats.distance,
            stats.player_stuck_time,
        },
    );
    std.debug.print(
        "money: ${d} best_combo={d}\n",
        .{ final_state.money, final_state.best_combo },
    );
    std.debug.print(
        "traffic: agent_resets={d} moving={d}/{d}\n",
        .{ stats.agent_resets, final_state.moving, final_state.spawned },
    );
    std.debug.print(
        "result: {s}\n",
        .{if (stats.pass) "PASS" else "FAIL"},
    );
}
