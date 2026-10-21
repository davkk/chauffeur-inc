#!/usr/bin/env bash
# Fast visual feedback loop: build, run a deterministic bot-driven demo in a
# hidden window, capture frames, and assemble a contact sheet.
set -euo pipefail

cd "$(dirname "$0")/.."

out="${1:-/tmp/opencode/game-shots}"
count="${2:-6}"
interval="${3:-2}"

rm -rf "$out"
mkdir -p "$out"

zig build
./zig-out/bin/chauffeur_inc \
  --shots "$out" \
  --shot-count "$count" \
  --shot-interval "$interval" \
  --hidden

if command -v magick >/dev/null 2>&1; then
  magick montage "$out"/frame_*.png \
    -thumbnail 640x400 \
    -tile 3x \
    -geometry +6+6 \
    -background '#101010' \
    "$out/contact.png"
  echo "$out/contact.png"
else
  echo "$out"
fi
