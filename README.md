# Hamburger Helper

A 2D burger-stacking arcade game for [Godot](https://godotengine.org) 4.7, in the
tradition of *Burgertime* (Data East, 1991). Assemble hamburgers from
dispensed ingredients, deliver them to the plates before the clock runs out, and
keep the hot dogs off your back.

## Running

```sh
godot --path .                                          # play
godot --headless --import                               # build the class cache
./tests/run.sh                                          # run the test suite
```

No export templates are required to run from source.

The test runner is a scene rather than a `godot --script` entry point on
purpose: a `--script` entry is compiled before autoloads are registered, so
autoload identifiers are invisible to it and every script that depends on one
fails to compile.

## Controls

| Action | Keys |
|--------|------|
| Move / climb | Arrow keys or WASD |
| Grab, or place onto a counter | Space or X |
| Throw the tray | Z or C |
| Pause | P or Escape |

Walking into a dispenser drops its next ingredient at your feet, so simply
leaning against one keeps it producing. Pressing into a solid counter starts a
run along its top edge, which is how you cross a gap you would otherwise fall
through.

## Design notes

Levels are authored as ASCII maps in `scripts/game/level_data.gd`, one character
per 16x16 grid cell:

| Char | Meaning | Char | Meaning |
|------|---------|------|---------|
| `.`  | empty   | `#`  | platform |
| `H`  | wall    | `=`  | ladder |
| `T`  | table / plate | `s` | salt pile |
| `b`  | bun dispenser | `l` `t` `c` `m` | lettuce / tomato / cheese / meat |
| `P`  | player start | `e` `p` `o` | hot dog / pickle / onion |

Keeping levels as text means a level tweak is a readable diff rather than an
opaque scene edit, and `LevelData.validate()` checks geometry, player-start
support, ladder contiguity, and reachability of every dispenser and table.

Movement is **cell-to-cell rather than physics-based**. Every actor resolves
collisions against the `Board` grid, which makes movement exact, deterministic,
and testable with no display. Tables are passable for the player (they are
counters you step up onto) but solid for falling ingredients, which is what
makes them work as assembly surfaces.

## Layout

```
scripts/game/     level data, board grid, game flow, autoloads
scripts/player/   the chef
scripts/food/     ingredient definitions, falling items, salt
scripts/enemies/  roaming hazards
tests/            headless test runner
```

## Tests

`tests/run_tests.gd` runs headless and covers level validation (row widths,
legal characters, player-start support, ladder contiguity, and that every
dispenser, table and salt pile is actually reachable), burger scoring and
assembly rules, and integration paths: assembling a burger through the same
calls the player makes, ingredients falling and being collected, taking items
back off a counter, the tray limit, simulated walking and climbing, and
building then tearing down every level in turn.

Run it through `tests/run.sh` rather than invoking the scene directly. Two
things make the obvious commands insufficient, and the script exists because
both bit during development:

- The suite only reports the checks it actually reaches, so a GDScript runtime
  error inside a test aborts that test quietly and can still print `PASS` with
  the coverage missing.
- Booting a scene does not fail on a broken script. A parse error in a script
  attached to a scene still exits `0`, so a smoke test that only checks the exit
  code is not a smoke test. The level card shipped this way: 106 checks passed
  while `hud.gd` failed to parse, because the tests build `Game` directly and
  never load the scene's HUD.

So `tests/run.sh` runs the suite and boots both scenes, judging each run by
scanning its output for script errors, parse failures and timeouts rather than
trusting the exit status. CI runs the same script.

## Screenshots and visual checks

`tools/shots.sh` renders the real game on a headless X server and saves PNGs of
the title, the level card and each level to `/tmp/hamburger-helper`. It needs
`Xvfb` and ImageMagick's `import`:

```sh
sudo pacman -S xorg-server-xvfb imagemagick   # or your distro's equivalent
./tools/shots.sh
```

`tools/visual_check.sh` then asserts things about those PNGs which are easy to
regress without noticing: that the HUD actually draws, that the level card is
present during the intro and gone once play starts, and that no two captures
are accidentally the same picture. Run it after changing the HUD, the level
card or level geometry.

Two details earn their keep, both learned the hard way:

- The game is launched once per shot, and a shot that captures a window left
  over from an earlier run produces a plausible picture of the wrong thing.
  `shots.sh` kills any previous game and refuses to capture if the process it
  launched is not still alive.
- `tools/see.py <png>` prints a capture as ASCII. It is how you check a level
  looks like something without a display.

`tools/screenshot.gd` is a separate root-viewport capture helper for when a
scene needs to be photographed without a window manager. `shots.sh` does not
use it; it drives the shipped scene instead.

There is no level select yet, so the screenshot tool reaches levels 2-4 with a
development hook: `godot scenes/game.tscn -- --level=2` starts that level
directly (zero-based). The game ignores the argument unless it is given.

## Levels

Four hand-built levels, 16x15 each, validated in tests: `LUNCH RUSH` (3 burgers,
75s), `DOUBLE SHIFT` (5, 95s), `DINNER RUSH` (6, 110s) and `LATE SHIFT` (7,
125s). Each level opens on a card naming the level and the job, and the clock
does not start until the card clears.
