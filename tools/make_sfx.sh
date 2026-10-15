#!/usr/bin/env bash
# Regenerates the synthesized sound effects in assets/audio/sfx/ and reimports them.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot4 || echo "$HOME/bin/godot4")}"
"$GODOT" --headless --path . --script tools/make_sfx.gd
"$GODOT" --headless --path . --import >/dev/null 2>&1
ls -la assets/audio/sfx/*.wav | awk '{print $5, $9}'
