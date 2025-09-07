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

fn drawRoad(texture: rl.Texture2D, x: i32, y: i32, angle: f32) void {
    rl.DrawTexturePro(
        texture,
        .{ .x = 0, .y = 0, .width = g.TILE_SIZE, .height = g.TILE_SIZE },
        .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = g.TILE_SIZE, .height = g.TILE_SIZE },
        .{ .x = g.TILE_SIZE / 2.0, .y = g.TILE_SIZE / 2.0 },
        angle,
        rl.WHITE,
    );
}

fn drawNode(node: *Node, nodes: []Node, tileset: *const Tileset) void {
    rl.DrawTexturePro(
        tileset.texture,
        .{ .x = g.TILE_SIZE, .y = 0, .width = g.TILE_SIZE * 2, .height = g.TILE_SIZE * 2 },
        .{ .x = node.pos.x, .y = node.pos.y, .width = g.TILE_SIZE * 2, .height = g.TILE_SIZE * 2 },
        .{ .x = g.TILE_SIZE, .y = g.TILE_SIZE },
        0,
        rl.WHITE,
    );

    for (node.edges.keys()) |edge| {
        const other = &nodes[edge];
        if (!other.active) continue;

        const dx = @round(node.pos.x - other.pos.x);
        const dy = @round(node.pos.y - other.pos.y);
        const angle = -math.atan2(-dy, dx) * 180.0 / math.pi - 90;

        rl.DrawTexturePro(
            tileset.texture,
            .{ .x = g.TILE_SIZE * 3, .y = 0, .width = g.TILE_SIZE, .height = g.TILE_SIZE },
            .{ .x = node.pos.x, .y = node.pos.y, .width = g.TILE_SIZE, .height = g.TILE_SIZE },
            .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 },
            angle,
            rl.WHITE,
        );
    }
}

pub fn main() !void {
    rl.InitWindow(g.SCREEN_WIDTH, g.SCREEN_HEIGHT, "Chauffeur Inc - Map Editor");
    rl.SetTargetFPS(g.TARGET_FPS);
    rl.SetExitKey(0);

    const tileset = Tileset.init();
    defer tileset.deinit();

    var road = rl.LoadImageFromTexture(tileset.texture);
    rl.ImageCrop(&road, .{ .x = 0, .y = 0, .width = g.TILE_SIZE, .height = g.TILE_SIZE });
    const road_texture = rl.LoadTextureFromImage(road);
    defer rl.UnloadTexture(road_texture);
    rl.SetTextureWrap(road_texture, rl.TEXTURE_WRAP_REPEAT);

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

    var camera = rl.Camera2D{
        .target = rl.Vector2{ .x = 0, .y = 0 },
        .offset = rl.Vector2{ .x = g.SCREEN_WIDTH / 2.0, .y = g.SCREEN_HEIGHT / 2.0 },
        .rotation = 0,
        .zoom = 1.0,
    };

    while (!rl.WindowShouldClose()) {
        const wheel = rl.GetMouseWheelMove();
        if (wheel != 0) {
            camera.zoom += wheel * 0.1;
            if (camera.zoom < 0.1) camera.zoom = 0.1;
            if (camera.zoom > 5.0) camera.zoom = 5.0;
        }
        if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_MIDDLE)) {
            const delta = rl.GetMouseDelta();
            camera.target.x -= delta.x / camera.zoom;
            camera.target.y -= delta.y / camera.zoom;
        }

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

        rl.BeginMode2D(camera);
        defer rl.EndMode2D();

        if (editor.state != .idle) {
            const world_min_x = camera.target.x - camera.offset.x / camera.zoom;
            const world_max_x = camera.target.x + (g.SCREEN_WIDTH - camera.offset.x) / camera.zoom;
            const world_min_y = camera.target.y - camera.offset.y / camera.zoom;
            const world_max_y = camera.target.y + (g.SCREEN_HEIGHT - camera.offset.y) / camera.zoom;

            var grid_x = @floor(world_min_x / g.TILE_SIZE) * g.TILE_SIZE;
            while (grid_x <= world_max_x) : (grid_x += g.TILE_SIZE) {
                const pos_from = rl.Vector2{ .x = grid_x, .y = world_min_y };
                const pos_to = rl.Vector2{ .x = grid_x, .y = world_max_y };
                rl.DrawLineEx(pos_from, pos_to, 2, GRID_COLOR);
            }
            var grid_y = @floor(world_min_y / g.TILE_SIZE) * g.TILE_SIZE;
            while (grid_y <= world_max_y) : (grid_y += g.TILE_SIZE) {
                const pos_from = rl.Vector2{ .x = world_min_x, .y = grid_y };
                const pos_to = rl.Vector2{ .x = world_max_x, .y = grid_y };
                rl.DrawLineEx(pos_from, pos_to, 2, GRID_COLOR);
            }
        }

        const mouse_world_pos = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera);
        const mouse_pos = snapToGrid(mouse_world_pos);

        for (nodes.items) |*node1| {
            if (!node1.active) continue;
            for (node1.edges.keys()) |edge| {
                const node2 = &nodes.items[edge];
                if (!node2.active or node1.id > node2.id) continue;

                const dx = @round(node1.pos.x - node2.pos.x);
                const dy = @round(node1.pos.y - node2.pos.y);

                const angle = -math.atan2(-dy, dx) * 180.0 / math.pi - 90;

                const mid_x = (node1.pos.x + node2.pos.x) / 2.0;
                const mid_y = (node1.pos.y + node2.pos.y) / 2.0;
                const length = @sqrt(dx * dx + dy * dy);

                rl.DrawTexturePro(
                    road_texture,
                    .{ .x = 0, .y = 0, .width = g.TILE_SIZE, .height = length },
                    .{ .x = mid_x, .y = mid_y, .width = g.TILE_SIZE, .height = length },
                    .{ .x = g.TILE_SIZE / 2.0, .y = length / 2 },
                    angle,
                    rl.WHITE,
                );
            }

            for (node1.edges.keys()) |edge| {
                const node2 = &nodes.items[edge];
                if (!node2.active) continue;

                const dx = @round(node1.pos.x - node2.pos.x);
                const dy = @round(node1.pos.y - node2.pos.y);
                const angle = -math.atan2(-dy, dx) * 180.0 / math.pi - 90;

                rl.DrawTexturePro(
                    tileset.texture,
                    .{ .x = g.TILE_SIZE, .y = 0, .width = g.TILE_SIZE * 2, .height = g.TILE_SIZE * 2 },
                    .{ .x = node1.pos.x, .y = node1.pos.y, .width = g.TILE_SIZE * 2, .height = g.TILE_SIZE * 2 },
                    .{ .x = g.TILE_SIZE, .y = g.TILE_SIZE },
                    angle,
                    rl.WHITE,
                );
            }

            for (node1.edges.keys()) |edge| {
                const node2 = &nodes.items[edge];
                if (!node2.active) continue;

                const dx = @round(node1.pos.x - node2.pos.x);
                const dy = @round(node1.pos.y - node2.pos.y);
                const angle = -math.atan2(-dy, dx) * 180.0 / math.pi - 90;

                rl.DrawTexturePro(
                    tileset.texture,
                    .{ .x = g.TILE_SIZE * 3, .y = 0, .width = g.TILE_SIZE, .height = g.TILE_SIZE },
                    .{ .x = node1.pos.x, .y = node1.pos.y, .width = g.TILE_SIZE, .height = g.TILE_SIZE },
                    .{ .x = g.TILE_SIZE / 2, .y = g.TILE_SIZE / 2 },
                    angle,
                    rl.WHITE,
                );
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
