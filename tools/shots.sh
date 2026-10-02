#!/usr/bin/env bash
# Captures the real game by driving tools/screenshot.gd, which saves the PNG from
# Godot's own framebuffer via get_viewport().get_texture().get_image().
#
# A display is still needed, because Godot's --headless uses a dummy renderer
# and has no framebuffer to read. That is the only reason Xvfb is here; the
# capture itself, the pixel counting and the frame waiting are all Godot.
#
# Captures land at the project's native 256x240, straight from the viewport, so
# they are 1:1 with the game rather than upscaled window grabs.
#
#   sudo pacman -S xorg-server-xvfb
#   ./tools/shots.sh
#
# Env: SHOT_DIR (default /tmp/hamburger-helper), DISPLAY_NUM (default :99).
set -uo pipefail

cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
DISPLAY_NUM="${DISPLAY_NUM:-:99}"
SHOT_DIR="${SHOT_DIR:-/tmp/hamburger-helper}"
SCREEN="${SCREEN:-1280x1024x24}"
GL_ARGS="${GL_ARGS:---rendering-driver opengl3 --resolution 256x240}"

fail=0
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

# shot <out> <scene> <until-phase|-> <cap> <scale> <settle> [user args]
shot() {
	local out="$1" scene="$2" phase="$3" cap="$4" scale="$5" settle="$6"
	shift 6
	local log="/tmp/shot-$out.log"
	# env, not a bare assignment prefix: bash only treats FOO=bar as an assignment
	# when it is unquoted, and a quoted array element would be run as a command.
	local -a envs=(
		"DISPLAY=$DISPLAY_NUM"
		"SHOT_SCENE=$scene"
		"SHOT_OUT=$SHOT_DIR/$out.png"
		"SHOT_TIME_SCALE=$scale"
		"SHOT_FRAMES=$cap"
		"SHOT_SETTLE_FRAMES=$settle"
	)
	[ "$phase" != "-" ] && envs+=("SHOT_UNTIL_PHASE=$phase")
	echo "  $out ..."
	if ! timeout 240 env "${envs[@]}" "$GODOT" $GL_ARGS tools/screenshot.tscn -- "$@" >"$log" 2>&1; then
		echo "  DIED: $out" >&2
		tail -15 "$log" >&2
		fail=1
		return
	fi
	grep -E "^state:|^screenshot:" "$log" | sed 's/^/    /'
	if [ ! -s "$SHOT_DIR/$out.png" ]; then
		echo "  MISSING: $out.png was not written" >&2
		fail=1
	fi
}

# scripted <out> <action> <level>
#
# As shot(), but the state is reached by driving the game rather than by waiting
# for it, and the tool prints the level and the state it actually got. That print
# is the point: a capture of the wrong moment should be obvious in the log here
# rather than discovered later as "the effect is broken".
scripted() {
	local out="$1" action="$2" level="$3"
	local log="/tmp/shot-$out.log"
	# env, not a bare assignment prefix: see the note in shot().
	local -a envs=(
		"DISPLAY=$DISPLAY_NUM"
		"SHOT_SCENE=res://tools/shot_scripted.tscn"
		"SHOT_OUT=$SHOT_DIR/$out.png"
		"SHOT_TIME_SCALE=1"
		"SHOT_FRAMES=30"
		"SHOT_SETTLE_FRAMES=4"
		"SHOT_ACTION=$action"
		"SHOT_LEVEL=$level"
	)
	echo "  $out ($action, level $level) ..."
	if ! timeout 240 env "${envs[@]}" "$GODOT" $GL_ARGS tools/screenshot.tscn >"$log" 2>&1; then
		echo "  DIED: $out" >&2
		tail -15 "$log" >&2
		fail=1
		return
	fi
	grep -E "^shot_scripted:|^screenshot:" "$log" | sed 's/^/    /'
	# The tool reports the action and the level it reached. A mismatch here means
	# the capture is not of what was asked for, which a later pixel check cannot
	# tell apart from a working capture of the wrong thing.
	if grep -q "SCRIPT ERROR" "$log" || grep -q "Parse Error" "$log"; then
		echo "  SCRIPT ERROR: $out" >&2
		grep -m3 -A2 "SCRIPT ERROR\|Parse Error" "$log" >&2
		fail=1
	fi
	if [ ! -s "$SHOT_DIR/$out.png" ]; then
		echo "  MISSING: $out.png was not written" >&2
		fail=1
	fi
}

echo "shots: writing to $SHOT_DIR"
# The title screen has no phase, so there is nothing to wait for; real time, a
# short cap, since it is already on screen by the first frame.
shot 01-title       scenes/main.tscn -   90   1 0
# The card is phase 0. Real time and a settle, so the card is up and painted
# rather than a half-built first frame, and so the 2.4s intro has not expired.
shot 02-level1-card scenes/game.tscn  0   400  1 30
# Play is phase 1. Software GL is slow, so 8x time reaches it in ~60 frames
# instead of the hundreds a real-time run would need; the small settle then
# lets the last of the level land.
shot 03-level1-play scenes/game.tscn  1   900  8 10
shot 04-level2-play scenes/game.tscn  1   900  8 10 --level=1
shot 05-level3-play scenes/game.tscn  1   900  8 10 --level=2

# The states that have to be caused rather than waited for: a spray in the air, a
# chef under his parachute, a popup that should have taken itself off the board, a
# frozen nasty, a finished burger. tools/shot_scripted.gd drives the real game to
# each one and prints what it did, so these are reproducible rather than a list of
# env vars to retype by hand - and the log line is what tells you a capture is of
# the moment you asked for.
#
# No phase to wait for: the tool decides the frame itself, having driven the game
# to the state, so the cap is just a ceiling on how long to let it settle.
#
# 06 is the baseline the rest are measured against: the same tool, the same
# frames, the same level, with the action left as "play". Every other one has to
# come out different from it, which is the only way to catch an action that
# quietly did nothing - a capture of the level as it always looks is worse than no
# capture, because it looks like the thing working.
scripted 06-play         play        0
scripted 07-pepper       pepper      0
scripted 08-respawn      respawn     0
scripted 09-popup-gone   popup_gone  0
scripted 10-stunned      stunned     0
scripted 11-ground       ground      0
# A second level, so SHOT_LEVEL is exercised by the script rather than only by
# hand. The brand palettes differ per level, so this also shows level 3's tiles
# where 11 shows level 1's.
scripted 12-ground-l3    ground      2

if [ "$fail" -ne 0 ]; then
	echo "shots: FAILED" >&2
	exit 1
fi
echo "shots: done"
