# Hamburger Helper

A 2D burger-stacking arcade game for [Godot](https://godotengine.org) 4.7, in the
tradition of *Burgertime* (Data East, 1991). Assemble hamburgers from
dispensed ingredients, deliver them to the plates before the clock runs out, and
keep the hot dogs off your back.

## Running

```sh
godot --path .                 # play
godot --headless --script res://tests/run_tests.gd   # run the test suite
```

No export templates are required to run from source.

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
scripts/food/     ingredient definitions, dispensers
scripts/enemies/  roaming hazards
tests/            headless test runner
```
