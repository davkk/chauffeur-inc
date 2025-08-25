const std = @import("std");
const json = std.json;
const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const Node = struct {
    pos: rl.Vector2,
};

const Cell = rl.Rectangle;

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();
    //
    // const file_contents = try std.fs.cwd().readFileAlloc(allocator, "assets/map.json", 1024 * 1024);
    // defer allocator.free(file_contents);
    //
    // const parsed = try json.parseFromSlice(json.Value, allocator, file_contents, .{});
    // defer parsed.deinit();
    //
    // const root = parsed.value;
    // const buildings = root.object.get("layers").?.array.items[1].object.get("objects").?.array.items[0];

    // rl.InitWindow(1600, 1000, "Chauffeur Inc - Map Editor");
    // rl.SetTargetFPS(g.TARGET_FPS);
    //
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const alloc = gpa.allocator();
    //
    // var nodes = std.ArrayList(Node).init(alloc);
    // defer nodes.deinit();
    //
    // while (!rl.WindowShouldClose()) {
    //     const mouse_pos = rl.GetMousePosition();
    //
    //     if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
    //         try nodes.append(.{
    //             .pos = mouse_pos,
    //         });
    //     }
    //
    //     rl.BeginDrawing();
    //     defer rl.EndDrawing();
    //
    //     rl.ClearBackground(rl.BLACK);
    //
    //     rl.DrawCircleV(mouse_pos, 20, rl.PINK);
    //
    //     for (nodes.items) |node| {
    //         rl.DrawCircleV(node.pos, 20, rl.RED);
    //     }
    //
    //     rl.DrawFPS(10, 10);
    // }
}
