const std = @import("std");
const json = std.json;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const RANGE = 200;
const LINE_THICKNESS = 40.0;

const GRID_SIZE = 100;
const GRID_COLOR = rl.Color{ .r = 100, .g = 100, .b = 100, .a = 50 };

const ACTIVE_COLOR = rl.WHITE;
const BAD_COLOR = rl.RED;
const INACTIVE_COLOR = rl.GRAY;

const State = enum {
    idle,
    eraser,
    add_node_single,
    add_node_multi,
};

const Editor = struct {
    state: State,
    active_node_id: ?std.meta.FieldType(Node, .id),
};

const Node = struct {
    pos: rl.Vector2,
    id: usize,
    active: bool = true,
    edges: std.AutoArrayHashMap(usize, void),

    pub fn init(alloc: *const std.mem.Allocator, pos: rl.Vector2, id: usize) Node {
        return Node{
            .active = true,
            .pos = pos,
            .id = id,
            .edges = std.AutoArrayHashMap(usize, void).init(alloc.*),
        };
    }
};

fn hoveredNode(mouse_pos: rl.Vector2, nodes: []Node) ?*Node {
    for (nodes) |*node| {
        if (!node.active) continue;
        if (rl.CheckCollisionPointCircle(mouse_pos, node.pos, 20)) {
            return node;
        }
    }
    return null;
}

fn hoveredEdge(mouse_pos: rl.Vector2, nodes: []Node) ?struct { *Node, *Node } {
    for (nodes) |*node1| {
        if (!node1.active) continue;
        for (node1.edges.keys()) |edge| {
            if (node1.id > edge) continue;

            const node2 = &nodes[edge];
            if (!node2.active) continue;

            if (rl.CheckCollisionPointLine(mouse_pos, node1.pos, node2.pos, 20)) {
                return .{ node1, node2 };
            }
        }
    }
    return null;
}

fn snapToGrid(pos: rl.Vector2) rl.Vector2 {
    const snappedX = @round(pos.x / GRID_SIZE) * GRID_SIZE;
    const snappedY = @round(pos.y / GRID_SIZE) * GRID_SIZE;
    return rl.Vector2{ .x = snappedX, .y = snappedY };
}

fn isValidEdge(pos1: rl.Vector2, pos2: rl.Vector2) bool {
    const dx = pos2.x - pos1.x;
    const dy = pos2.y - pos1.y;
    return dx == 0 or dy == 0 or @abs(dx) == @abs(dy);
}

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
                if (!node.active) continue;
                std.debug.print("{}: ", .{node.id});
                for (node.edges.keys()) |edge| {
                    std.debug.print("{}, ", .{edge});
                }
                std.debug.print("\n", .{});
            }
        }

        if (rl.IsKeyPressed(rl.KEY_V)) {
            editor.state = .idle;
        }

        if (rl.IsKeyPressed(rl.KEY_E)) {
            editor.state = .eraser;
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

        var x: f32 = 0;
        while (x <= 1600) {
            rl.DrawLine(@intFromFloat(x + GRID_SIZE / 2), 0, @intFromFloat(x + GRID_SIZE / 2), 1000, GRID_COLOR);
            x += GRID_SIZE;
        }
        var y: f32 = 0;
        while (y <= 1000) {
            rl.DrawLine(0, @intFromFloat(y + GRID_SIZE / 2), 1600, @intFromFloat(y + GRID_SIZE / 2), GRID_COLOR);
            y += GRID_SIZE;
        }

        const mouse_pos = rl.GetMousePosition();

        for (nodes.items) |*node1| {
            if (!node1.active) continue;
            for (nodes.items) |*node2| {
                if (!node2.active or node1.id > node2.id) continue;
                if (node1.edges.get(node2.id)) |_| {
                    rl.DrawLineEx(node1.pos, node2.pos, LINE_THICKNESS, INACTIVE_COLOR);
                }
            }
            rl.DrawCircleV(node1.pos, 20, INACTIVE_COLOR);
        }

        switch (editor.state) {
            .idle => {},
            .eraser => {
                if (hoveredNode(mouse_pos, nodes.items)) |node1| {
                    rl.DrawCircleV(node1.pos, 20, ACTIVE_COLOR);
                    if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT)) {
                        node1.active = false;
                        for (nodes.items) |*node| {
                            if (node.active) {
                                _ = node.edges.swapRemove(node1.id);
                            }
                        }
                        if (editor.active_node_id) |active| {
                            if (active == node1.id) {
                                editor.active_node_id = null;
                            }
                        }
                    }
                } else {
                    if (hoveredEdge(mouse_pos, nodes.items)) |edge| {
                        const node1, const node2 = edge;
                        rl.DrawLineEx(node1.pos, node2.pos, LINE_THICKNESS, ACTIVE_COLOR);
                        if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT)) {
                            _ = node1.edges.swapRemove(node2.id);
                            _ = node2.edges.swapRemove(node1.id);
                        }
                    }
                }
            },
            .add_node_single => {
                if (rl.IsKeyPressed(rl.KEY_ESCAPE)) {
                    editor.active_node_id = null;
                }

                if (editor.active_node_id) |node_id| {
                    var new_node: *Node = undefined;
                    var found = false;

                    if (hoveredNode(mouse_pos, nodes.items)) |node2| {
                        new_node = node2;
                        found = true;
                    }

                    const snapped_pos = snapToGrid(mouse_pos);
                    rl.DrawLineEx(
                        nodes.items[node_id].pos,
                        snapped_pos,
                        LINE_THICKNESS,
                        if (isValidEdge(nodes.items[node_id].pos, snapped_pos)) ACTIVE_COLOR else BAD_COLOR,
                    );

                    if (found) {
                        rl.DrawCircleV(new_node.pos, 20, ACTIVE_COLOR);
                    } else {
                        rl.DrawCircleV(snapped_pos, 20, ACTIVE_COLOR);
                    }

                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and isValidEdge(nodes.items[node_id].pos, snapped_pos)) {
                        if (!found) {
                            try nodes.append(Node.init(&alloc, snapped_pos, nodes.items.len));
                            new_node = &nodes.items[nodes.items.len - 1];
                        }
                        try new_node.edges.put(node_id, {});
                        try nodes.items[node_id].edges.put(new_node.id, {});
                        editor.active_node_id = new_node.id;
                    }
                } else if (hoveredNode(mouse_pos, nodes.items)) |node1| {
                    rl.DrawCircleV(node1.pos, 20, ACTIVE_COLOR);
                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                        editor.active_node_id = node1.id;
                    }
                } else {
                    const snapped_pos = snapToGrid(mouse_pos);
                    rl.DrawCircleV(snapped_pos, 20, ACTIVE_COLOR);
                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                        const new_node = Node.init(&alloc, snapped_pos, nodes.items.len);
                        try nodes.append(new_node);
                        editor.active_node_id = new_node.id;
                    }
                }
            },
            .add_node_multi => {
                const snapped_pos = snapToGrid(mouse_pos);
                for (nodes.items) |*node| {
                    if (!node.active) continue;
                    if (rl.Vector2Distance(node.pos, snapped_pos) < RANGE) {
                        if (!isValidEdge(node.pos, snapped_pos)) continue;
                        rl.DrawLineEx(node.pos, snapped_pos, LINE_THICKNESS, ACTIVE_COLOR);
                    }
                }

                rl.DrawCircleV(snapped_pos, 20, ACTIVE_COLOR);
                rl.DrawCircleLinesV(snapped_pos, RANGE, ACTIVE_COLOR);

                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    try nodes.append(Node.init(&alloc, snapped_pos, nodes.items.len));
                    const new_node = &nodes.items[nodes.items.len - 1];
                    for (nodes.items) |*node| {
                        if (!node.active or node.id == new_node.id) continue;
                        if (rl.Vector2Distance(node.pos, snapped_pos) < RANGE) {
                            try new_node.edges.put(node.id, {});
                            try nodes.items[node.id].edges.put(new_node.id, {});
                        }
                    }
                }
            },
        }
    }
}
