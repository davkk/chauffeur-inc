const std = @import("std");
const math = std.math;
const json = std.json;

const rl = @import("raylib.zig").rl;
const g = @import("globals.zig");

const Tileset = @import("Tileset.zig");

const LINE_THICKNESS = 4.0;

const GRID_COLOR = rl.Color{ .r = 100, .g = 100, .b = 100, .a = 50 };

const ACTIVE_COLOR = rl.WHITE;
const BAD_COLOR = rl.RED;
const INACTIVE_COLOR = rl.GRAY;

const State = enum {
    idle,
    eraser,
    add_node_single,
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
        if (rl.CheckCollisionPointCircle(mouse_pos, node.pos, 10)) {
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

            if (rl.CheckCollisionPointLine(mouse_pos, node1.pos, node2.pos, 10)) {
                return .{ node1, node2 };
            }
        }
    }
    return null;
}

fn snapToGrid(pos: rl.Vector2) rl.Vector2 {
    const snappedX = @round(pos.x / g.TILE_SIZE) * g.TILE_SIZE;
    const snappedY = @round(pos.y / g.TILE_SIZE) * g.TILE_SIZE;
    return rl.Vector2{ .x = snappedX, .y = snappedY };
}

fn isValidEdge(pos1: rl.Vector2, pos2: rl.Vector2) bool {
    const dx = pos2.x - pos1.x;
    const dy = pos2.y - pos1.y;
    return dx == 0 or dy == 0 or @abs(dx) == @abs(dy);
}

const Queue = std.DoublyLinkedList(usize);

fn traverse(alloc: *const std.mem.Allocator, adj_list: []Node, tileset: *const Tileset) void {
    var visited = std.AutoArrayHashMap(usize, void).init(alloc.*);
    defer visited.deinit();

    var queue = Queue{};
    for (adj_list) |node| {
        if (node.active) {
            var first = Queue.Node{ .data = node.id };
            queue.append(&first);
            visited.put(node.id, {}) catch unreachable;
            break;
        }
    }

    while (queue.len > 0) {
        const node_id = queue.popFirst().?;
        const node = &adj_list[node_id.data];

        rl.DrawTexturePro(
            tileset.texture,
            rl.Rectangle{ .x = 0, .y = 0, .width = g.TILE_SIZE, .height = g.TILE_SIZE },
            rl.Rectangle{ .x = node.pos.x, .y = node.pos.y, .width = g.TILE_SIZE, .height = g.TILE_SIZE },
            rl.Vector2{ .x = g.TILE_SIZE / 2.0, .y = g.TILE_SIZE / 2.0 },
            0,
            rl.WHITE,
        );

        for (node.edges.keys()) |edge| {
            if (visited.get(edge)) |_| {
                continue;
            }

            var new_node = Queue.Node{ .data = edge };
            queue.append(&new_node);
            visited.put(edge, {}) catch unreachable;
        }
    }
}

fn drawRoad(tileset: *const Tileset, x: i32, y: i32, angle: f32) void {
    rl.DrawTexturePro(
        tileset.texture,
        .{ .x = 0, .y = 0, .width = g.TILE_SIZE, .height = g.TILE_SIZE * @sqrt(2.0) },
        .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = g.TILE_SIZE, .height = g.TILE_SIZE * @sqrt(2.0) },
        .{ .x = g.TILE_SIZE / 2.0, .y = g.TILE_SIZE * @sqrt(2.0) / 2.0 },
        angle,
        rl.WHITE,
    );
}

pub fn main() !void {
    rl.InitWindow(g.SCREEN_WIDTH, g.SCREEN_HEIGHT, "Chauffeur Inc - Map Editor");
    rl.SetTargetFPS(g.TARGET_FPS);
    rl.SetExitKey(0);

    const tileset = Tileset.init();
    defer tileset.deinit();

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
        // const KEY_SHIFT = rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT);
        if (rl.IsKeyPressed(rl.KEY_P)) {
            for (nodes.items) |*node| {
                if (!node.active) continue;
                std.debug.print("{}: ", .{node.id});
                for (node.edges.keys()) |edge| {
                    std.debug.print("{}, ", .{edge});
                }
                std.debug.print("\n", .{});
            }
        } else if (rl.IsKeyPressed(rl.KEY_V)) {
            editor.state = .idle;
        } else if (rl.IsKeyPressed(rl.KEY_E)) {
            editor.state = .eraser;
        } else if (rl.IsKeyPressed(rl.KEY_A)) {
            editor.state = .add_node_single;
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.BLACK);

        if (editor.state != .idle) {
            var grid_x: f32 = 0;
            while (grid_x <= g.SCREEN_WIDTH) {
                rl.DrawLine(@intFromFloat(grid_x), 0, @intFromFloat(grid_x), g.SCREEN_HEIGHT, GRID_COLOR);
                grid_x += g.TILE_SIZE;
            }
            var grid_y: f32 = 0;
            while (grid_y <= g.SCREEN_HEIGHT) {
                rl.DrawLine(0, @intFromFloat(grid_y), g.SCREEN_WIDTH, @intFromFloat(grid_y), GRID_COLOR);
                grid_y += g.TILE_SIZE;
            }
        }

        const mouse_pos = snapToGrid(rl.GetMousePosition());

        for (nodes.items) |*node1| {
            if (!node1.active) continue;
            for (node1.edges.keys()) |edge| {
                const node2 = &nodes.items[edge];
                if (!node2.active or node1.id > node2.id) continue;

                const x1: i32 = @intFromFloat(node1.pos.x);
                const x2: i32 = @intFromFloat(node2.pos.x);
                const y1: i32 = @intFromFloat(node1.pos.y);
                const y2: i32 = @intFromFloat(node2.pos.y);

                const dx: i32 = @intFromFloat(node2.pos.x - node1.pos.x);
                const dy: i32 = @intFromFloat(node2.pos.y - node1.pos.y);

                if (dx == 0) {
                    const min_y = @min(y1, y2);
                    const max_y = @max(y1, y2);
                    var y_pos = min_y + g.TILE_SIZE;
                    while (y_pos < max_y) : (y_pos += g.TILE_SIZE) {
                        drawRoad(&tileset, x1, y_pos, 0);
                    }
                } else if (dy == 0) {
                    const min_x = @min(x1, x2);
                    const max_x = @max(x1, x2);
                    var x_pos = min_x + g.TILE_SIZE;
                    while (x_pos < max_x) : (x_pos += g.TILE_SIZE) {
                        drawRoad(&tileset, x_pos, y1, 90);
                    }
                } else {
                    const angle: f32 = if (dx * dy > 0) -45.0 else 45.0;
                    const steps = @divExact(@abs(dx), g.TILE_SIZE);
                    var step: i32 = 1;
                    while (step < steps) : (step += 1) {
                        const x_pos = x1 + math.sign(dx) * g.TILE_SIZE * step;
                        const y_pos = y1 + math.sign(dy) * g.TILE_SIZE * step;
                        drawRoad(&tileset, x_pos, y_pos, angle);
                    }
                }
            }

            if (editor.state != .idle) {
                rl.DrawCircleV(node1.pos, 10, INACTIVE_COLOR);
            }
        }

        switch (editor.state) {
            .idle => {},
            .eraser => {
                if (hoveredNode(mouse_pos, nodes.items)) |node1| {
                    rl.DrawCircleV(node1.pos, 10, ACTIVE_COLOR);
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

                    rl.DrawLineEx(
                        nodes.items[node_id].pos,
                        mouse_pos,
                        LINE_THICKNESS,
                        if (isValidEdge(nodes.items[node_id].pos, mouse_pos)) ACTIVE_COLOR else BAD_COLOR,
                    );

                    if (found) {
                        rl.DrawCircleV(new_node.pos, 10, ACTIVE_COLOR);
                    } else {
                        rl.DrawCircleV(mouse_pos, 10, ACTIVE_COLOR);
                    }

                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and isValidEdge(nodes.items[node_id].pos, mouse_pos)) {
                        if (!found) {
                            try nodes.append(Node.init(&alloc, mouse_pos, nodes.items.len));
                            new_node = &nodes.items[nodes.items.len - 1];
                        }
                        try new_node.edges.put(node_id, {});
                        try nodes.items[node_id].edges.put(new_node.id, {});
                        editor.active_node_id = new_node.id;
                    }
                } else if (hoveredNode(mouse_pos, nodes.items)) |node1| {
                    rl.DrawCircleV(node1.pos, 10, ACTIVE_COLOR);
                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                        editor.active_node_id = node1.id;
                    }
                } else {
                    rl.DrawCircleV(mouse_pos, 10, ACTIVE_COLOR);
                    if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                        const new_node = Node.init(&alloc, mouse_pos, nodes.items.len);
                        try nodes.append(new_node);
                        editor.active_node_id = new_node.id;
                    }
                }
            },
        }
    }
}
