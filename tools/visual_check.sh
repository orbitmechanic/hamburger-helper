#!/usr/bin/env bash
# Visual smoke test entry point. The checks themselves are tools/visual_check.gd,
# which counts pixels with Image.get_pixel() - see that file for why they exist.
#
# Needs xorg-server-xvfb for the capturing; ./tools/shots.sh does that.
set -uo pipefail

cd "$(dirname "$0")/.."

SHOT_DIR="${SHOT_DIR:-/tmp/hamburger-helper}"
GODOT="${GODOT:-godot}"

if [ ! -f "$SHOT_DIR/03-level1-play.png" ]; then
	echo "visual: no captures in $SHOT_DIR; running tools/shots.sh"
	./tools/shots.sh >/tmp/visual-shots.log 2>&1 || {
		echo "visual: shots.sh failed" >&2
		tail -20 /tmp/visual-shots.log >&2
		exit 1
	}
fi

# The check only reads PNGs, so it runs headless; it never needs a display.
SHOT_DIR="$SHOT_DIR" "$GODOT" --headless tools/visual_check.tscn
