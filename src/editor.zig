// TODO: there is a bug with removing still!
//
//

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
    add_node_single,
    add_node_multi,
};

const Editor = struct {
    state: State,
    active_node_id: ?std.meta.FieldType(Node, .id),
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
        .active_node_id = null,
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
            editor.state = .add_node_single;
        }

        const KEY_SHIFT = rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT);
        if (KEY_SHIFT and rl.IsKeyPressed(rl.KEY_A)) {
            editor.state = .add_node_multi;
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
                if (rl.IsKeyPressed(rl.KEY_ESCAPE)) {
                    editor.active_node_id = null;
                }

                if (editor.active_node_id) |node_id| {
                    var new_node: *Node = undefined;
                    var found = false;

                    for (nodes.items) |*node2| {
                        if (rl.CheckCollisionPointCircle(mouse_pos, node2.pos, 40)) {
                            new_node = node2;
                            found = true;
                            break;
                        }
                    }

                    rl.DrawLineEx(nodes.items[node_id].pos, mouse_pos, LINE_THICKNESS, ACTIVE_COLOR);
                    if (found) {
                        rl.DrawCircleV(new_node.pos, 20, ACTIVE_COLOR);
                    } else {
                        rl.DrawCircleV(mouse_pos, 20, ACTIVE_COLOR);
                    }

                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                        if (!found) {
                            try nodes.append(.{
                                .pos = mouse_pos,
                                .id = nodes.items.len,
                                .edges = std.AutoArrayHashMap(usize, void).init(alloc),
                            });
                            new_node = &nodes.items[nodes.items.len - 1];
                        }
                        try new_node.edges.put(node_id, {});
                        try nodes.items[node_id].edges.put(new_node.id, {});
                        editor.active_node_id = null;
                    }
                } else {
                    for (nodes.items) |*node1| {
                        if (rl.CheckCollisionPointCircle(mouse_pos, node1.pos, 40)) {
                            rl.DrawCircleV(node1.pos, 20, ACTIVE_COLOR);

                            if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                                editor.active_node_id = node1.id;
                            } else if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_RIGHT)) {
                                const removed_id = node1.id;
                                const last_id = nodes.items.len - 1;

                                node1.edges.deinit();
                                _ = nodes.swapRemove(removed_id);
                                for (nodes.items) |*node| {
                                    _ = node.edges.swapRemove(removed_id);
                                }

                                if (editor.active_node_id) |active| {
                                    if (active == node1.id) {
                                        editor.active_node_id = null;
                                    }
                                }

                                if (removed_id != last_id and nodes.items.len > 0) {
                                    nodes.items[removed_id].id = removed_id;
                                    if (editor.active_node_id) |active| {
                                        if (active == node1.id) {
                                            editor.active_node_id = null;
                                        } else if (active == last_id) {
                                            editor.active_node_id = removed_id;
                                        }
                                    }
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
                }
            },
            .add_node_single => {
                rl.DrawCircleV(mouse_pos, 20, ACTIVE_COLOR);

                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    try nodes.append(.{
                        .pos = mouse_pos,
                        .id = nodes.items.len,
                        .edges = std.AutoArrayHashMap(usize, void).init(alloc),
                    });
                }
            },
            .add_node_multi => {
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
