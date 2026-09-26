#!/usr/bin/env bash
# Runs the test suite and fails on anything the suite cannot see about itself.
#
# The runner reports PASS/FAIL for the checks it reaches, but a GDScript runtime
# error inside a test aborts that test mid-way: the remaining checks silently
# never run and the suite can still print PASS with its coverage gutted. That
# is not a hypothetical, it is how the level-progression test first reported
# success while testing nothing. So parse the output rather than trust it.
set -uo pipefail

cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

timeout "$TIMEOUT_SECONDS" "$GODOT" --headless res://tests/test_scene.tscn 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

fail=0

if [ "$status" -eq 124 ]; then
	echo "runner: timed out after ${TIMEOUT_SECONDS}s" >&2
	fail=1
fi

if grep -q "SCRIPT ERROR" "$log"; then
	echo "runner: SCRIPT ERROR in output" >&2
	grep -m5 -A2 "SCRIPT ERROR" "$log" >&2
	fail=1
fi

if grep -qE "Parse Error|Failed to load script" "$log"; then
	echo "runner: script failed to parse or load" >&2
	fail=1
fi

if grep -q "FAIL" "$log"; then
	echo "runner: one or more checks failed" >&2
	fail=1
fi

if ! grep -q "PASS" "$log"; then
	echo "runner: suite never reported a result (crash, hang, or abort)" >&2
	fail=1
fi

if [ "$fail" -ne 0 ]; then
	echo "runner: TESTS FAILED" >&2
	exit 1
fi

echo "runner: tests OK"
