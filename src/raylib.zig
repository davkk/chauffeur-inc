const std = @import("std");
const math = std.math;
pub const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raygui.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
});

pub fn vec_add(vectors: []const rl.Vector2) rl.Vector2 {
    var result = rl.Vector2Zero();
    for (vectors) |vector| {
        result = rl.Vector2Add(result, vector);
    }
    return result;
}

pub fn vec_rotate(vec: rl.Vector2, center: rl.Vector2, angle: f32) rl.Vector2 {
    const cos = math.cos(angle);
    const sin = math.sin(angle);
    const x = vec.x - center.x;
    const y = vec.y - center.y;
    return .{
        .x = x * cos - y * sin + center.x,
        .y = x * sin + y * cos + center.y,
    };
}

var prng: std.Random.DefaultPrng = .init(0);
var prng_seeded: bool = false;

/// System-seeded shared random source (replaces removed `std.crypto.random`).
pub fn rand() std.Random {
    if (!prng_seeded) {
        var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
        defer threaded.deinit();
        var seed: u64 = undefined;
        threaded.io().random(std.mem.asBytes(&seed));
        prng.seed(seed);
        prng_seeded = true;
    }
    return prng.random();
}

/// Make the shared random source deterministic. Call this once before creating
/// the game (`--seed` in the CLI, tests, replays).
pub fn seedRandom(seed: u64) void {
    prng.seed(seed);
    prng_seeded = true;
}
