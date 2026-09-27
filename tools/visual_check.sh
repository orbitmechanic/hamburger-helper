#!/usr/bin/env bash
# Visual smoke test: renders the real game on a virtual display and asserts on
# the pixels, so "the HUD vanished" cannot pass again.
#
# This exists because of a bug that every other check missed. Level teardown
# cleared every child of the Game node, which included the scene's own HUD, so
# the score, the clock and the level card were destroyed by the first
# start_level and had never once been drawn. All 106 headless checks passed the
# whole time: they build a bare Game.new() with no scene, and a headless boot
# cannot see pixels. It took looking at an actual capture to find it.
#
# Needs xorg-server-xvfb and ImageMagick; ./tools/shots.sh does the capturing.
set -uo pipefail

cd "$(dirname "$0")/.."

SHOT_DIR="${SHOT_DIR:-/tmp/hamburger-helper}"
fail=0

# count <file> <hex>  -> number of pixels of roughly that colour
count() {
	convert "$1" -depth 8 +dither -format %c histogram:info: 2>/dev/null \
		| grep -i "$2" | head -1 | cut -d: -f1 | tr -d ' '
}

# check <description> <actual> <comparison> <expected>
check() {
	local desc="$1" actual="$2" op="$3" want="$4"
	local ok=0
	case "$op" in
		gt) [ "${actual:-0}" -gt "$want" ] && ok=1 ;;
		eq) [ "${actual:-0}" -eq "$want" ] && ok=1 ;;
		lt) [ "${actual:-0}" -lt "$want" ] && ok=1 ;;
	esac
	if [ "$ok" -eq 1 ]; then
		printf '  ok   %-52s %s\n' "$desc" "${actual:-0}"
	else
		printf '  FAIL %-52s %s (wanted %s %s)\n' "$desc" "${actual:-0}" "$op" "$want"
		fail=1
	fi
}

check_distinct() {
	local a="$1" b="$2" desc="$3"
	if cmp -s "$SHOT_DIR/$a" "$SHOT_DIR/$b"; then
		printf '  FAIL %-52s identical files\n' "$desc"
		fail=1
	else
		printf '  ok   %-52s distinct\n' "$desc"
	fi
}

if [ ! -f "$SHOT_DIR/03-level1-play.png" ]; then
	echo "visual: no captures in $SHOT_DIR; running tools/shots.sh"
	./tools/shots.sh >/tmp/visual-shots.log 2>&1 || {
		echo "visual: shots.sh failed" >&2
		tail -20 /tmp/visual-shots.log >&2
		exit 1
	}
fi

echo "visual: checking $SHOT_DIR"

# The HUD's text colour. Zero of these means the HUD is not being drawn at all,
# which is exactly what the teardown bug caused.
for shot in 02-level1-card 03-level1-play 04-level2-play 05-level3-play 06-level4-play; do
	check "$shot draws HUD text" "$(count "$SHOT_DIR/$shot.png" '244,244,255')" gt 200
done

# The level card's panel colour: present over the card, gone once play starts.
check "level card is drawn" "$(count "$SHOT_DIR/02-level1-card.png" '11,11,25')" gt 2000
check "level card is cleared for play" "$(count "$SHOT_DIR/03-level1-play.png" '11,11,25')" eq 0

# A stale-window capture is byte-identical to whatever was on screen before,
# which is how a level-4 shot came back showing the title screen.
check_distinct 01-title.png 02-level1-card.png "title and level card differ"
check_distinct 02-level1-card.png 03-level1-play.png "level card and play differ"
check_distinct 03-level1-play.png 04-level2-play.png "level 1 and 2 differ"
check_distinct 04-level2-play.png 05-level3-play.png "level 2 and 3 differ"
check_distinct 05-level3-play.png 06-level4-play.png "level 3 and 4 differ"
check_distinct 01-title.png 06-level4-play.png "title and level 4 differ"

# A frame that is only background means the level failed to build or draw.
for shot in 03-level1-play 04-level2-play 05-level3-play 06-level4-play; do
	check "$shot draws the level" "$(count "$SHOT_DIR/$shot.png" '200,160,106')" gt 20000
done

if [ "$fail" -ne 0 ]; then
	echo "visual: FAILED" >&2
	exit 1
fi
echo "visual: all green"
