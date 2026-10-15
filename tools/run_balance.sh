#!/usr/bin/env bash
# Drives a level with the autopilot on several traffic seeds and prints the
# time left. The bot is a careful driver, so treat its times as a floor.
#   tools/run_balance.sh                                   # Kickoff, 5 seeds
#   LEVEL=res://data/levels/02_x.tres SEEDS=1,2,3 tools/run_balance.sh
#   CAR=res://data/cars/truck.tres tools/run_balance.sh  # another car (default SUV)
#   SKILL=1 tools/run_balance.sh                          # a confident driver instead of a careful one
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot4 || echo "$HOME/bin/godot4")}"
"$GODOT" --headless --path . --import > /dev/null 2>&1
"$GODOT" --headless --fixed-fps 60 --path . res://tests/BalanceBot.tscn 2>&1 | grep -v '^Godot Engine'
