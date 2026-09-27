#!/usr/bin/env bash
# Screenshots the real game by running it on a virtual display and grabbing the
# display, rather than instantiating the scene from a helper script.
#
# That indirection was tried first and is not trustworthy: capturing through a
# helper scene produced byte-identical frames from 10 to 500 while the game
# underneath was demonstrably running (phase advanced, clock counted down), so
# it showed a stale render. Running the actual main scene and grabbing the X
# display captures exactly what a player would see, with no scene-tree
# differences to account for.
#
#   sudo pacman -S xorg-server-xvfb
#   ./tools/shots.sh
set -uo pipefail

cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
DISPLAY_NUM="${DISPLAY_NUM:-:99}"
SHOT_DIR="${SHOT_DIR:-/tmp/hamburger-helper}"
SCREEN="${SCREEN:-1280x1024x24}"
# Software GL is slow, so the game is given a generous head start before the
# grab. Anything less and the capture catches a half-built first frame.
SETTLE="${SETTLE:-14}"
RES="${RES:-640x480}"

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

# Make sure no game window is left over. Without this a capture can pick up a
# previous window that outlived its kill, which is how a level-4 shot came back
# byte-identical to the title screen. pkill -x matches the process name exactly,
# unlike pkill -f, which also matches this script's own command line.
clean_display() {
	pkill -x godot 2>/dev/null
	for _ in $(seq 1 24); do
		pgrep -x godot >/dev/null 2>&1 || return 0
		sleep 0.25
	done
	pkill -9 -x godot 2>/dev/null
	sleep 1
}

# shoot <out-name> <scene> <settle-seconds> [extra godot args...]
shoot() {
	local out="$1" scene="$2" settle="$3"
	shift 3
	clean_display
	echo "--- $out ($scene, ${settle}s settle$*)"
	DISPLAY="$DISPLAY_NUM" "$GODOT" --rendering-driver opengl3 \
		--resolution "$RES" --position 0,0 "$scene" "$@" >/tmp/shots-game.log 2>&1 &
	local pid=$!
	sleep "$settle"
	# import can block on a busy or wedged X server; never wait forever.
	DISPLAY="$DISPLAY_NUM" timeout 30 import -window root "$SHOT_DIR/$out" 2>/dev/null
	# The window has to be gone before the next launch, or the capture picks up
	# whichever window happens to be on top. A level-4 capture came back
	# byte-identical to the title screen because the title window outlived it.
	kill "$pid" 2>/dev/null
	for _ in $(seq 1 24); do
		kill -0 "$pid" 2>/dev/null || break
		sleep 0.25
	done
	kill -9 "$pid" 2>/dev/null
	wait "$pid" 2>/dev/null

	if [ ! -s "$SHOT_DIR/$out" ]; then
		echo "MISSING: $SHOT_DIR/$out"
		sed -n '1,20p' /tmp/shots-game.log
		fail=1
		return
	fi
	# Report the dominant colours so a blank or all-background frame is obvious
	# without having to look at the file.
	convert "$SHOT_DIR/$out" -depth 8 +dither -colors 8 -format %c histogram:info: \
		2>/dev/null | sort -rn | head -4 | sed 's/^/    /'
}

# The level card holds for 2.4s, so the short settle catches it and a longer one
# catches play.
shoot "01-title.png" "res://scenes/main.tscn" "$SETTLE"
shoot "02-level1-card.png" "res://scenes/game.tscn" 1.5
shoot "03-level1-play.png" "res://scenes/game.tscn" "$SETTLE"
shoot "04-level2-play.png" "res://scenes/game.tscn" "$SETTLE" -- --level=1
shoot "05-level3-play.png" "res://scenes/game.tscn" "$SETTLE" -- --level=2
shoot "06-level4-play.png" "res://scenes/game.tscn" "$SETTLE" -- --level=3

if [ "$fail" -ne 0 ]; then
	echo "shots: FAILED" >&2
	exit 1
fi
echo "shots: written to $SHOT_DIR"
ls -la "$SHOT_DIR"
