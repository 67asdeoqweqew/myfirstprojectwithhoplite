#!/bin/sh
# «ДЕД, СТОЯТЬ!» — starts both game windows: host (Player 1, WASD+FGH) and client (Player 2, arrows + , . /).
# Extra arguments are passed to both windows, e.g. ./play.sh --low
cd "$(dirname "$0")/grandpa_game" || exit 1
godot --path . -- --host "$@" &
sleep 2
exec godot --path . -- --join "$@"
