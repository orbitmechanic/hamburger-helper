#!/usr/bin/env bash
# Gate on "nothing is broken", not just "the suite said PASS".
#
# Two things make the obvious commands insufficient:
#
# 1. The suite only reports the checks it reaches. A GDScript runtime error
#    inside a test aborts that test quietly and the suite can still print PASS
#    with the coverage gutted. That is not hypothetical, it is how the
#    level-progression test first reported success while testing nothing.
#
# 2. Booting a scene does not fail on a broken script. A parse error in a
#    script attached to a scene still exits 0, so a smoke test that only checks
#    the exit code ships a scene that cannot run. The level card landed this
#    way: 106 checks passed while hud.gd failed to parse, because the tests
#    build Game directly and never load the scene's HUD.
#
# So every run below is checked by scanning its output, not its exit status.
set -uo pipefail

cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

fail=0

# Reports why a log is unacceptable. Returns non-zero if the log is bad.
reject() {
	local label="$1" status="$2"
	local bad=0
	if [ "$status" -eq 124 ]; then
		echo "$label: timed out after ${TIMEOUT_SECONDS}s" >&2
		bad=1
	fi
	if grep -q "SCRIPT ERROR" "$log"; then
		echo "$label: SCRIPT ERROR" >&2
		grep -m5 -A2 "SCRIPT ERROR" "$log" >&2
		bad=1
	fi
	if grep -qE "Parse Error|Failed to load script" "$log"; then
		echo "$label: script failed to parse or load" >&2
		bad=1
	fi
	return "$bad"
}

# --- the test suite ---------------------------------------------------------
timeout "$TIMEOUT_SECONDS" "$GODOT" --headless res://tests/test_scene.tscn 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
fail=0
reject "tests" "$status" || fail=1
if grep -q "FAIL" "$log"; then
	echo "tests: one or more checks failed" >&2
	fail=1
fi
if ! grep -q "PASS" "$log"; then
	echo "tests: suite never reported a result (crash, hang, or abort)" >&2
	fail=1
fi

# --- scene boots ------------------------------------------------------------
# Short budgets on purpose: these only have to load, draw a few hundred frames
# and exit. A longer run would just make a hang slower to notice.
#
# The tools are in this list because they were not, and tools/visual_check.gd
# sat with a parse error nobody could see: CI never loaded it, so a tool that
# could not run looked exactly like a tool that had not been run. A tool scene
# that needs captures or input reports that on stderr and exits non-zero, which
# is fine here - reject() only looks for timeouts and script errors, not for the
# tool's own opinion of whether it had what it needed.
for scene in "title:" "game:scenes/game.tscn" \
		"tool-levels:tools/check_levels.tscn" \
		"tool-visual:tools/visual_check.tscn"; do
	label="${scene%%:*}"
	target="${scene#*:}"
	# shellcheck disable=SC2086
	timeout 90 "$GODOT" --headless ${target:+$target} --quit-after 400 >"$log" 2>&1
	status=$?
	reject "boot $label" "$status" || fail=1
	# shellcheck disable=SC2086
	echo "boot $label: ok (${target:-res://scenes/main.tscn})"
done

# --- scripted action branches ------------------------------------------------
# The capture tool has six actions and booting it bare reaches one of them, so
# the other five are driven explicitly here.
#
# This is a narrower gap than the one above and worth being precise about,
# because the comment above overstates the guarantee: booting a scene does catch
# a parse error, but a *runtime* error inside a branch nothing enters does not.
# shots.sh is the only thing that ran the rest, and CI does not run shots.sh -
# it needs a display. So the action branches had no automated execution at all,
# which is the same failure run.sh's own history describes one step further on:
# a tool that cannot run looking exactly like a tool that was never run.
#
# No captures needed here. Each boot drives the real game into its state and the
# point is that the branch executes without a script error - reject() catches
# that, and the tool quits non-zero on an unknown action or an out-of-range
# level, so a typo in the action list is caught too.
for action in play pepper respawn popup_gone stunned ground crossing \
		crossing_unmarked; do
	# shellcheck disable=SC2086
	SHOT_ACTION="$action" timeout 90 "$GODOT" --headless \
		tools/shot_scripted.tscn --quit-after 400 >"$log" 2>&1
	status=$?
	reject "boot tool-scripted/$action" "$status" || fail=1
	# shellcheck disable=SC2086
	echo "boot tool-scripted/$action: ok"
done

if [ "$fail" -ne 0 ]; then
	echo "runner: FAILED" >&2
	exit 1
fi

echo "runner: all green"
