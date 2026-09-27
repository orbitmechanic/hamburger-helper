#!/usr/bin/env bash
# Renders screenshots of the game into $SHOT_DIR (default /tmp/hamburger-helper).
#
# Godot's headless mode uses a dummy renderer and produces no pixels, so this
# needs a real display driver. It does not have to be a physical one:
#
#   Xvfb :99 -screen 0 1152x960x24 &   # xorg-server-xvfb on Arch
#   ./tools/shots.sh
set -uo pipefail

cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
DISPLAY_NUM="${DISPLAY_NUM:-:99}"
SHOT_DIR="${SHOT_DIR:-/tmp/hamburger-helper}"
SCREEN="${SCREEN:-1152x960x24}"

# Wait on the X socket rather than xdpyinfo, so the only thing to install is
# xorg-server-xvfb itself.
socket="/tmp/.X11-unix/X${DISPLAY_NUM#:}"

started_xvfb=""
if [ ! -S "$socket" ]; then
	Xvfb "$DISPLAY_NUM" -screen 0 "$SCREEN" >/tmp/xvfb.log 2>&1 &
	started_xvfb=$!
	trap 'kill '"$started_xvfb"' 2>/dev/null' EXIT
	for _ in $(seq 1 60); do
		[ -S "$socket" ] && break
		sleep 0.25
	done
fi
if [ ! -S "$socket" ]; then
	echo "shots: no X server on $DISPLAY_NUM; install xorg-server-xvfb" >&2
	echo "  sudo pacman -S xorg-server-xvfb" >&2
	sed -n '1,20p' /tmp/xvfb.log >&2 2>/dev/null
	exit 1
fi

mkdir -p "$SHOT_DIR"
fail=0

shoot() {
	local scene="$1" out="$2" frames="${3:-90}"
	echo "--- $scene -> $out"
	DISPLAY="$DISPLAY_NUM" \
		SHOT_SCENE="$scene" SHOT_OUT="$SHOT_DIR/$out" SHOT_FRAMES="$frames" \
		timeout 90 "$GODOT" --rendering-driver opengl3 tools/screenshot.tscn 2>&1 \
		| grep -viE "resources still|RID of type|ObjectDB" | grep -iE "screenshot:|error" || true
	[ -s "$SHOT_DIR/$out" ] || { echo "MISSING: $SHOT_DIR/$out"; fail=1; }
}

shoot "res://scenes/main.tscn" "01-title.png" 30
# Past the level card, which holds the chef still for the first 2.4s.
shoot "res://scenes/game.tscn" "02-level1-card.png" 20
shoot "res://scenes/game.tscn" "03-level1-play.png" 200

[ "$fail" -ne 0 ] && { echo "shots: FAILED"; exit 1; }
echo "shots: written to $SHOT_DIR"
