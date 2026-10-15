#!/usr/bin/env bash
# Runs the headless test suite (road math, streaming, driving integration).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot4 || echo "$HOME/bin/godot4")}"
"$GODOT" --headless --path . --import > /dev/null 2>&1
"$GODOT" --headless --fixed-fps 60 --path . res://tests/TestRunner.tscn
