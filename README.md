# map editor

- create a large map in Tiled
- load it as background
- available features
    - add nodes
    - remove nodes
    - move nodes
    - draw lines between nodes
    - draw buildings between edges
    - save map
    - load map

## Development loop

The game has a windowless simulation mode and a deterministic screenshot mode so
changes can be validated without playing manually.

```bash
zig build                              # compile
zig build check                        # compile-only check
zig build test                         # headless gameplay tests
zig build sim                          # 60s headless bot playtest
zig build sim -- --sim 30 --trace      # 30s with per-5s telemetry
zig build sim -- --sim 30 --ascii      # ASCII top-down map snapshots
zig build sim -- --sim 60 --runs 5     # aggregate five seeds

scripts/preview.sh                     # 6-frame contact sheet in /tmp/opencode/game-shots
./zig-out/bin/chauffeur_inc --bot      # watch the autopilot play
./zig-out/bin/chauffeur_inc --editor   # map editor
```

Useful flags for the executable:

- `--seed N` deterministic random seed
- `--bot` autopilot drives (toggle in game with `F1`)
- `--shots DIR --shot-count N --shot-interval S --hidden` deterministic capture
- `--debug` map debug overlay

Controls: `WASD`/arrows drive, `SPACE` brake, `TAB` change lane, `F1` autopilot,
`ESC` pause, `CTRL+SHIFT+E` toggle map editor, `CTRL+SHIFT+D` debug overlay.
