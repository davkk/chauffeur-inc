const std = @import("std");
const json = std.json;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const Node = struct {
    pos: rl.Vector2,
    id: usize,
    edges: std.AutoArrayHashMap(usize, void),
};

const Cell = rl.Rectangle;

const RANGE = 200;
const LINE_THICKNESS = 40.0;

const ACTIVE_COLOR = rl.WHITE;
const INACTIVE_COLOR = rl.GRAY;

const State = enum {
    idle,
    adding_node,
};

const Editor = struct {
    state: State,
};

pub fn main() !void {
    rl.InitWindow(1600, 1000, "Chauffeur Inc - Map Editor");
    rl.SetTargetFPS(g.TARGET_FPS);
    rl.SetExitKey(0);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var nodes = std.ArrayList(Node).init(alloc);
    defer {
        for (nodes.items) |*node| {
            node.edges.deinit();
        }
        nodes.deinit();
    }

    var editor = Editor{
        .state = .idle,
    };

    while (!rl.WindowShouldClose()) {
        if (rl.IsKeyPressed(rl.KEY_P)) {
            for (nodes.items) |*node| {
                std.debug.print("{}: ", .{node.id});
                for (node.edges.keys()) |edge| {
                    std.debug.print("{}, ", .{edge});
                }
                std.debug.print("\n", .{});
            }
        }

        if (rl.IsKeyPressed(rl.KEY_ESCAPE)) {
            editor.state = .idle;
        }

        if (rl.IsKeyPressed(rl.KEY_A)) {
            editor.state = .adding_node;
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.BLACK);

        const mouse_pos = rl.GetMousePosition();

        for (nodes.items) |*node1| {
            for (nodes.items) |*node2| {
                if (node1.id == node2.id) continue;
                if (node1.edges.get(node2.id)) |_| {
                    rl.DrawLineEx(node1.pos, node2.pos, LINE_THICKNESS, INACTIVE_COLOR);
                }
            }
            rl.DrawCircleV(node1.pos, 20, INACTIVE_COLOR);
        }

        switch (editor.state) {
            .idle => {
                for (nodes.items) |*node1| {
                    if (rl.CheckCollisionPointCircle(mouse_pos, node1.pos, 40)) {
                        rl.DrawCircleV(node1.pos, 20, ACTIVE_COLOR);
                        if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_RIGHT)) {
                            const removed_id = node1.id;
                            const last_id = nodes.items.len - 1;

                            node1.edges.deinit();
                            _ = nodes.swapRemove(removed_id);

                            if (removed_id != last_id and nodes.items.len > 0) {
                                nodes.items[removed_id].id = removed_id;
                                for (nodes.items) |*node| {
                                    if (node.edges.get(last_id)) |_| {
                                        _ = node.edges.swapRemove(last_id);
                                        try node.edges.put(removed_id, {});
                                    }
                                }
                            }
                            for (nodes.items) |*node| {
                                _ = node.edges.swapRemove(removed_id);
                            }
                        }
                        break;
                    }
                    for (node1.edges.keys()) |edge| {
                        const node2 = &nodes.items[edge];
                        if (rl.CheckCollisionPointLine(mouse_pos, node1.pos, node2.pos, 20)) {
                            rl.DrawLineEx(node1.pos, node2.pos, LINE_THICKNESS, ACTIVE_COLOR);
                            if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_RIGHT)) {
                                _ = node1.edges.swapRemove(node2.id);
                                _ = node2.edges.swapRemove(node1.id);
                            }
                            break;
                        }
                    }
                }
            },
            .adding_node => {
                for (nodes.items) |*node| {
                    if (rl.Vector2Distance(node.pos, mouse_pos) < RANGE) {
                        rl.DrawLineEx(node.pos, mouse_pos, LINE_THICKNESS, ACTIVE_COLOR);
                    }
                }
                rl.DrawCircleV(mouse_pos, 20, ACTIVE_COLOR);
                rl.DrawCircleLinesV(mouse_pos, RANGE, ACTIVE_COLOR);

                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    try nodes.append(.{
                        .pos = mouse_pos,
                        .id = nodes.items.len,
                        .edges = std.AutoArrayHashMap(usize, void).init(alloc),
                    });
                    const new_node = &nodes.items[nodes.items.len - 1];
                    for (nodes.items) |*node| {
                        if (node.id == new_node.id) continue;
                        if (rl.Vector2Distance(node.pos, mouse_pos) < RANGE) {
                            try new_node.edges.put(node.id, {});
                            try nodes.items[node.id].edges.put(new_node.id, {});
                        }
                    }
                }
            },
        }
    }
}
