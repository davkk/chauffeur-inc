const std = @import("std");

const Game = @import("Game.zig");
const Editor = @import("Editor.zig");
const Audio = @import("Audio.zig");
const Map = @import("Map.zig");
const Autopilot = @import("Autopilot.zig");
const Sim = @import("Sim.zig");
const raylib = @import("raylib.zig");
const c = @import("constants.zig");
const rl = raylib.rl;

const Mode = enum { game, editor };

const Options = struct {
    mode: Mode = .game,
    seed: ?u64 = null,
    sim: ?f32 = null,
    sim_runs: u32 = 1,
    bot: bool = false,
    shots_dir: ?[]const u8 = null,
    shot_count: u32 = 6,
    shot_interval: f32 = 2.0,
    hidden: bool = false,
    debug: bool = false,
    trace: bool = false,
    ascii: bool = false,
};

fn usage() void {
    const text =
        \\chauffeur_inc [options]
        \\
        \\  (no args)           Play the game
        \\  --editor            Start in the map editor
        \\  --seed N            Deterministic random seed
        \\  --bot               Let the autopilot drive (toggle with F1)
        \\  --debug             Start with the map debug overlay
        \\
        \\  --sim SECONDS       Headless simulation, no window
        \\  --runs N            Run N consecutive seeds (sim only)
        \\  --trace             Per-second sim telemetry (sim only)
        \\  --ascii             ASCII world snapshots (sim only)
        \\
        \\  --shots DIR         Capture a deterministic bot-driven screenshot sequence
        \\  --shot-count N      Number of screenshots (default 6)
        \\  --shot-interval S   Sim seconds between screenshots (default 2)
        \\  --hidden            Hide the window (use with --shots)
        \\
    ;
    std.debug.print("{s}", .{text});
}

fn parseArgs(args: []const []const u8) !Options {
    var opts = Options{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--sim")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            opts.sim = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            opts.seed = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--runs")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            opts.sim_runs = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--bot")) {
            opts.bot = true;
        } else if (std.mem.eql(u8, arg, "--editor")) {
            opts.mode = .editor;
        } else if (std.mem.eql(u8, arg, "--game")) {
            opts.mode = .game;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            opts.debug = true;
        } else if (std.mem.eql(u8, arg, "--trace")) {
            opts.trace = true;
        } else if (std.mem.eql(u8, arg, "--ascii")) {
            opts.ascii = true;
        } else if (std.mem.eql(u8, arg, "--hidden")) {
            opts.hidden = true;
        } else if (std.mem.eql(u8, arg, "--shots")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            opts.shots_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--shot-count")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            opts.shot_count = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--shot-interval")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            opts.shot_interval = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            usage();
            std.process.exit(0);
        } else {
            return error.InvalidArguments;
        }
    }
    return opts;
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var arg_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer arg_iter.deinit();

    var args = std.array_list.Managed([]const u8).init(alloc);
    while (arg_iter.next()) |arg| {
        try args.append(try alloc.dupe(u8, arg));
    }

    const opts = parseArgs(args.items) catch {
        usage();
        std.process.exit(2);
    };

    if (opts.seed) |seed| raylib.seedRandom(seed);

    if (opts.sim) |duration| {
        var total_deliveries: u32 = 0;
        var total_earned: u32 = 0;
        var all_pass = true;
        var runs_done: u32 = 0;

        while (runs_done < @max(opts.sim_runs, 1)) : (runs_done += 1) {
            const seed = (opts.seed orelse 1) + runs_done;
            raylib.seedRandom(seed);
            const stats = try Sim.run(alloc, .{
                .seed = seed,
                .duration = duration,
                .bot = opts.bot,
                .trace = opts.trace or (opts.sim_runs <= 1),
                .ascii = opts.ascii,
            });
            total_deliveries += stats.deliveries;
            total_earned += stats.earned;
            all_pass = all_pass and stats.pass;
        }

        if (opts.sim_runs > 1) {
            std.debug.print(
                "\n== {d} runs: deliveries={d} earned=${d} -> {s}\n",
                .{ opts.sim_runs, total_deliveries, total_earned, if (all_pass) "PASS" else "FAIL" },
            );
        }

        if (!all_pass) std.process.exit(1);
        return;
    }

    var config: c_uint = 0;
    if (opts.hidden) config |= @intCast(rl.FLAG_WINDOW_HIDDEN);
    if (config != 0) rl.SetConfigFlags(config);

    rl.InitWindow(c.SCREEN_WIDTH, c.SCREEN_HEIGHT, "Chauffeur Inc");
    defer rl.CloseWindow();
    rl.SetTargetFPS(c.TARGET_FPS);
    rl.SetExitKey(0);

    var mode = opts.mode;
    var is_debug = opts.debug;

    var camera = rl.Camera2D{
        .target = .{ .x = c.WORLD_WIDTH / 2, .y = c.WORLD_HEIGHT / 2 },
        .offset = .{ .x = c.SCREEN_WIDTH / 2 + c.TILE_SIZE, .y = c.SCREEN_HEIGHT / 2 + c.TILE_SIZE },
        .zoom = 1.0,
    };

    var map = try Map.init(alloc);
    defer map.deinit();

    var game = Game.init(&map);
    defer game.deinit();

    var editor = Editor.init();
    var autopilot = Autopilot.init();

    if (opts.shots_dir) |dir| {
        try captureShots(alloc, dir, opts, &game, &map, &camera, &autopilot);
        return;
    }

    var audio = Audio.init();
    defer audio.deinit();

    var bot_enabled = opts.bot;
    var paused = false;

    while (!rl.WindowShouldClose()) {
        const KEY_CTRL = rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL);
        const KEY_SHIFT = rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT);

        if (KEY_CTRL and KEY_SHIFT and rl.IsKeyPressed(rl.KEY_E)) {
            mode = if (mode == .game) Mode.editor else Mode.game;
        }
        if (KEY_CTRL and KEY_SHIFT and rl.IsKeyPressed(rl.KEY_D)) {
            is_debug = !is_debug;
        }
        if (KEY_CTRL and KEY_SHIFT and rl.IsKeyPressed(rl.KEY_P)) {
            game.spawnPassenger(&map);
        }
        if (rl.IsKeyPressed(rl.KEY_F1)) {
            bot_enabled = !bot_enabled;
            autopilot.reset();
        }
        if (rl.IsKeyPressed(rl.KEY_M)) {
            audio.toggleMute();
        }
        if (mode == .game and rl.IsKeyPressed(rl.KEY_ESCAPE)) {
            paused = !paused;
        }
        if (mode == .editor) paused = false;

        rl.BeginDrawing();
        {
            rl.ClearBackground(rl.BLACK);

            switch (mode) {
                .game => {
                    if (!paused) {
                        if (bot_enabled) {
                            const input = autopilot.nextInput(&game, &map);
                            const step = game.step(rl.GetFrameTime(), input, &map);
                            game.updateCamera(&camera);
                            audio.playStep(step);
                        } else {
                            const step = game.update(&camera, &map);
                            audio.playStep(step);
                        }
                    }
                    game.draw(&camera, &map, is_debug);

                    if (paused) {
                        rl.DrawRectangle(0, 0, c.SCREEN_WIDTH, c.SCREEN_HEIGHT, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 150 });
                        rl.DrawText("PAUSED", c.SCREEN_WIDTH / 2 - 90, c.SCREEN_HEIGHT / 2 - 40, 48, rl.WHITE);
                        rl.DrawText("ESC to resume", c.SCREEN_WIDTH / 2 - 74, c.SCREEN_HEIGHT / 2 + 20, 22, rl.GRAY);
                    }

                    if (bot_enabled) {
                        rl.DrawText("AUTOPILOT  (F1)", 12, c.SCREEN_HEIGHT - 30, 20, rl.YELLOW);
                    }
                },
                .editor => {
                    try editor.update(&camera, &map);
                    try editor.draw(&camera, &map, is_debug);
                },
            }

            if (audio.muted) {
                const label = "MUTED (M)";
                const width = rl.MeasureText(label, 20);
                rl.DrawText(label, c.SCREEN_WIDTH - width - 12, c.SCREEN_HEIGHT - 30, 20, rl.GRAY);
            }
        }
        rl.EndDrawing();
    }
}

/// Deterministic, windowed screenshot sequence. Simulation is stepped at a
/// fixed 60 Hz without drawing intermediate frames, so a 12 second demo takes
/// only a handful of rendered frames.
fn captureShots(
    alloc: std.mem.Allocator,
    dir: []const u8,
    opts: Options,
    game: *Game,
    map: *Map,
    camera: *rl.Camera2D,
    autopilot: *Autopilot,
) !void {
    var threaded: std.Io.Threaded = .init(alloc, .{});
    defer threaded.deinit();
    try std.Io.Dir.cwd().createDirPath(threaded.io(), dir);

    const dt: f32 = 1.0 / @as(f32, @floatFromInt(c.TARGET_FPS));
    const steps_per_shot: u32 = @max(1, @as(u32, @intFromFloat(opts.shot_interval / dt)));

    // Let the autopilot leave the spawn point and the camera settle before the
    // first frame, otherwise every capture starts with a wide establishing shot.
    const warmup_steps: u32 = 20;
    var warmup: u32 = 0;
    while (warmup < warmup_steps) : (warmup += 1) {
        const input = autopilot.nextInput(game, map);
        _ = game.step(dt, input, map);
        game.updateCamera(camera);
    }

    var shot: u32 = 0;
    while (shot < @max(opts.shot_count, 1)) : (shot += 1) {
        if (shot > 0) {
            var step: u32 = 0;
            while (step < steps_per_shot) : (step += 1) {
                const input = autopilot.nextInput(game, map);
                _ = game.step(dt, input, map);
                game.updateCamera(camera);
            }
        }

        const path = try std.fmt.allocPrintSentinel(alloc, "{s}/frame_{d:0>3}.png", .{ dir, shot }, 0);

        rl.BeginDrawing();
        rl.ClearBackground(rl.BLACK);
        game.draw(camera, map, opts.debug);

        // Timestamp chip below the minimap, clear of the gameplay HUD.
        const shot_time: f32 = @as(f32, @floatFromInt(warmup_steps)) * dt +
            @as(f32, @floatFromInt(shot)) * opts.shot_interval;
        const chip = rl.Rectangle{
            .x = c.SCREEN_WIDTH - 256,
            .y = 192,
            .width = 92,
            .height = 24,
        };
        rl.DrawRectangleRounded(chip, 0.3, 4, rl.Color{ .r = 16, .g = 18, .b = 22, .a = 215 });
        rl.DrawText(rl.TextFormat("t = %.1fs", shot_time), @intFromFloat(chip.x + 10), @intFromFloat(chip.y + 5), 14, rl.GRAY);

        // Flush the geometry batch and read the framebuffer while it is still
        // the active draw target. Reading after EndDrawing (which swaps buffers)
        // is not deterministic on all drivers.
        rl.rlDrawRenderBatchActive();
        rl.TakeScreenshot(path.ptr);
        rl.EndDrawing();

        std.debug.print("shot {d}: {s}\n", .{ shot, path });
    }
}
