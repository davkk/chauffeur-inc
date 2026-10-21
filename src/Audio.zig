const std = @import("std");

const rl = @import("raylib.zig").rl;
const Game = @import("Game.zig");

const Self = @This();

/// Gameplay events, in the same order as `assets` and `volumes`.
const Sfx = enum { crash, pickup, delivered, expired };
const sfx_count = @typeInfo(Sfx).@"enum".fields.len;

const names = [sfx_count][]const u8{ "crash", "pickup", "delivered", "expired" };
const assets = [sfx_count][]const u8{
    @embedFile("assets/audio/crash.wav"),
    @embedFile("assets/audio/pickup.wav"),
    @embedFile("assets/audio/delivered.wav"),
    @embedFile("assets/audio/expired.wav"),
};
const volumes = [sfx_count]f32{ 0.75, 0.55, 0.65, 0.55 };

sounds: [sfx_count]?rl.Sound = @splat(null),
enabled: bool = false,
opened_device: bool = false,
muted: bool = false,

/// Open the audio device and decode the embedded WAV files. A machine without
/// an output device gets a disabled instance: the game keeps running silently.
pub fn init() Self {
    var self = Self{};

    if (!rl.IsAudioDeviceReady()) {
        rl.InitAudioDevice();
        if (!rl.IsAudioDeviceReady()) {
            std.debug.print("audio: no output device, running silent\n", .{});
            return self;
        }
        self.opened_device = true;
    }

    for (assets, 0..) |bytes, index| {
        self.sounds[index] = loadSound(bytes) orelse {
            std.debug.print("audio: failed to load {s}.wav\n", .{names[index]});
            continue;
        };
        rl.SetSoundVolume(self.sounds[index].?, volumes[index]);
    }

    self.enabled = true;
    return self;
}

pub fn deinit(self: *Self) void {
    for (&self.sounds) |*slot| {
        if (slot.*) |sound| {
            rl.UnloadSound(sound);
            slot.* = null;
        }
    }

    self.enabled = false;
    if (self.opened_device) {
        rl.CloseAudioDevice();
        self.opened_device = false;
    }
}

/// Play one effect. A single `Game.Step` is produced per simulation tick, so
/// each field can trigger at most once per frame.
pub fn playStep(self: *Self, step: Game.Step) void {
    if (step.crashed) self.play(.crash);
    if (step.picked_up) self.play(.pickup);
    if (step.delivered) self.play(.delivered);
    if (step.expired) self.play(.expired);
}

pub fn play(self: *Self, sfx: Sfx) void {
    if (!self.enabled or self.muted) return;

    const sound = self.sounds[@intFromEnum(sfx)] orelse return;
    rl.PlaySound(sound);
}

/// Mute is enforced per play call, and master volume drops to zero so a sound
/// that is already playing stops immediately.
pub fn toggleMute(self: *Self) void {
    self.muted = !self.muted;
    if (self.enabled) rl.SetMasterVolume(if (self.muted) 0.0 else 1.0);
}

fn loadSound(bytes: []const u8) ?rl.Sound {
    const wave = rl.LoadWaveFromMemory(".wav", bytes.ptr, @intCast(bytes.len));
    defer rl.UnloadWave(wave);

    if (wave.frameCount == 0) return null;

    const sound = rl.LoadSoundFromWave(wave);
    if (sound.frameCount == 0) return null;
    return sound;
}
