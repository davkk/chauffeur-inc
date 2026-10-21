# TODO

## Driving and crashes

- [x] **Collision response / push back.** A crash now resolves the overlap,
  pushes both cars apart, and adds a short stun plus speed loss. Separation keeps
  running during the crash cooldown, so cars no longer stay stuck inside each
  other. The logical path state (`pos`, turns, flips) is untouched; the push is
  a separate physical/visual offset.
- [x] **Accurate collision shapes at intersections.** Collision now uses an
  oriented box built from the car's real drawn angle instead of an axis-aligned
  box from `curr_dir`. Turn control points were also moved out to the turn's own
  lane so the arc no longer cuts across the middle of the junction.
- [x] **Straight-through intersections stay straight.** The turn control point
  for `exit == entry` was using the corner formula, so cars bulged sideways
  while crossing a plain intersection. It now sits on the lane centerline, with
  a headless regression test covering all four directions.
- [x] **Portals: refactor and rethink how they work.** Start/end portals now use
  spawn scheduling and reservation. Agents wait for a free portal, release one at
  a time with spacing and alternating lanes, and spawn points are covered by a
  tunnel texture so cars do not pop into view. Player spawn is protected.
  when several agents spawn at once. Agents stack on the same node, overlap, and
  jam. Add portal occupancy/reservation, spawn one agent at a time, release them
  with enough spacing, and keep the player spawn clear. This needs a proper
  redesign, not another special case in the collision check.

## Rendering

- [x] **Render the static map once.** Game mode bakes tiles, roads, and
  decorations into a cached render texture and draws that single texture each
  frame. Re-renders only when the map is marked dirty.
- [x] **Fix tile seams / flashing gaps / vertical lines.** The cached map is one
  continuous point-filtered texture, so adjacent-tile hairline gaps are gone.
  Checked with two 6-8 frame screenshot sequences and pixel probes over grass /
  road boundaries.
- [x] **Editor cache invalidation.** Editor updates mark the static cache dirty,
  so switching back to game mode rebakes the map.

## Content and polish

- [x] **More car models.** Five 16x32 vehicles (taxi, red/blue sedans, green
  hatchback, white van, purple coupe). Traffic picks a deterministic random
  model only in non-headless mode; headless runs are unchanged. Player remains
  the taxi. Verified in screenshots.
- [ ] **Better map textures.** Improve the tileset in place without changing the
  atlas cell layout: grass, asphalt, lane markings, sidewalks/curbs, junction,
  tree, and props. Keep tiles seamless at cell edges and verify with screenshots.
- [x] **Simple audio effects.** Embedded WAVs for crash, pickup, delivered, and
  expired. Audio initializes only in windowed mode; `M` toggles mute with an
  on-screen indicator. `--sim` and tests do not touch audio. Verified with a
  working PulseAudio device.

## Testing and diagnostics

- [ ] **Overlap and crash telemetry.** The headless tests measure overlap depth
  and the longest persistent overlap, but the `--sim` report still has no
  dedicated overlap or "crash inside the same intersection" counters. Add those
  to make false positives directly measurable in every run.
- [x] **Regression tests.** Headless tests cover crash separation, speed loss,
  and a 30 s bot run with no persistent car/car overlap. `zig build test` and
  the 60 s multi-seed simulations pass.
