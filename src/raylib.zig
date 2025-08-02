pub const rl = @cImport({
    @cInclude("raylib.h");
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
