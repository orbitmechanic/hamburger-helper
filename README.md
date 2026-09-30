# Hamburger Helper

A 2D burger-stacking arcade game for [Godot](https://godotengine.org) 4.7, in the
tradition of *Burgertime* (Data East, 1991). Walk the length of an ingredient to
knock it down a storey, and use the floor plan to cascade a whole column of
parts onto the plates below until the burgers are made. There is no clock.

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
| Move, and climb ladders | Arrow keys or WASD |
| Jump, or reach up | Space or X |
| Spray seasoning | F, or the gamepad B button |
| Pause | P or Escape |
| Restart | R |

Walking the **full width** of a part knocks it down one storey, so a three-cell
patty has to be crossed end to end. A part falls one storey at a time: if there is
another part in the row it is falling into, that part is knocked out of the way
first and this one takes the row it vacated, so a column cascades down a storey
per push rather than dropping in one lump. Nothing ever comes to rest on top of
another part, so a part can never be left stranded in mid-air when the one under
it moves on. Push from the top and the lot walks down to the plate.

Seasoning is ammo, not a board-wide freeze. A pepper or salt jar on the board adds
one charge to the chef's jar, and the spray key throws a dose about a character and
a half in front of the chef; every nasty it reaches is frozen for five seconds.
One charge is one shot, and with an empty jar the key says `NO PEPPER` rather than
doing nothing quietly. A flattened nasty likewise lies flashing for five seconds
before returning to the ledge it started on, and cannot catch the chef while it is
down.

The jump is a dodge, not a way to climb. The chef can only push off a platform,
never sideways off a ladder, and a sideways hop carries him clean over the cell in
front rather than into it, so a nasty standing in the next cell is gone over rather
than landed on. Jump into a wall and the jump is cancelled; jump beside one and it
is a shorter hop.

Which jump you get is up to what you are holding when you press it. Hold nothing
and the chef reaches straight up, which is how he takes a jar sitting on a plate
above the track he walks; hold a direction and he hops that way, two cells from a
standstill; hold one while he is already running and the stride carries him a cell
further, to three. A hop from a stop is a real leap and arcs twice as high as one
taken at a run, so a standstill jump visibly covers more ground.

Baiting a nasty under a bun is worth real points. When the chef walks the full
width of a part and a nasty is standing on it, the nasty rides the part down a
second storey for the ride bonus and is crushed by it on the way, rather than
just being flattened by the part leaving.

## Design notes

Levels are authored as ASCII maps in `scripts/game/level_data.gd`, one character
per 16x16 grid cell:

| Char | Meaning | Char | Meaning |
|------|---------|------|---------|
| `.`  | empty   | `#`  | platform |
| `H`  | wall    | `=`  | ladder |
| `O`  | plate | `@`  | chef start |
| `b`  | bottom bun | `t` | top bun |
| `m`  | patty | `l` `r` | lettuce / tomato |
| `1`  | hot dog | `2` | fried egg |
| `3`  | pickle | | |

A horizontal run of one character is one object, and the length of the run is its
width: `mm` is a single two-cell patty, not two one-cell patties.

Keeping levels as text means a level tweak is a readable diff rather than an
opaque scene edit. `LevelData.validate()` checks row widths, legal characters,
that every plate has a buildable recipe, that every ingredient stands over a
plate, ladder contiguity, that every plate has **room to grow its burger**, that
every ingredient is reachable by the chef, and that the nasties start spread out
and clear of him.

### Grid shape

Ledges sit on rows 1, 4, 7 and 14, and the chef walks on rows 0, 3, 6 and 13.
The three upper storeys hold the ingredients; the ground storey is deliberately
tall, with rows 8 to 12 left open above the plates on row 13. That is the part
that is easy to get wrong: a burger grows *upward* from its plate, one row per
layer, and a part cannot fall through a platform, so a ledge anywhere in a
plate's column caps that burger. An earlier version put a ledge on row 10, which
capped every burger at two layers and left all three levels impossible to finish.
`LevelData.validate()` now rejects a plate with no room, so that cannot ship
again.

An ingredient's cells have to line up exactly with the plate below it, because a
part keeps its own column all the way down while the finished burger is drawn over
the plate's column. A part narrower or wider than its plate visibly slides as it
boards. Both are checked in tests.

Movement is **cell-to-cell rather than physics-based**. Every actor resolves
collisions against the `Board` grid, which makes movement exact, deterministic,
and testable with no display. A part's drawn position is the centre of the
`Rect2` spanning its cells, so a wide part sits over the middle of the row rather
than to one side of it.

The nasties are spread over the three ingredient storeys, one of each kind, and start
at least `LevelData.ENEMY_MIN_DISTANCE` cells from the chef, so the opening of a level
is spent working rather than dodging. They only leave their own storey when the chef is
within `Enemy.CHASE_RANGE` cells, so they press him where he is working instead of
converging on the one corridor he has to use to reach the plates. The ground storey is
deliberately clear of them: it is a single cell wide, a chef with a nasty in it has no
way past, and the plates along it are somewhere to travel, not somewhere to work.

## Layout

```
scripts/game/     level data, board grid, game flow, HUD, autoloads
scripts/player/   the chef
scripts/food/     ingredient kinds, and the falling parts
scripts/enemies/  roaming hazards
scripts/items/    bonus pickups
assets/sheets/    one animation sheet per character, generated
tools/            level and sheet generators, level checker, screenshots, visual checks
tests/            headless test runner
```

## Characters

The chef and the three nasties are drawn from one PNG each in `assets/sheets/`,
blitted a frame at a time. The game holds no character art code at all, so
replacing a character is replacing a file: drop a `chef.png` in that follows the
layout below and nothing else has to change.

The layout is a contract, written down once in `scripts/game/sheet.gd` and read by
both the game and the generator. There is no single industry-standard sheet
format - "standard" here means the conventions a uniform grid slice implies, which
is also how Unity and Godot slice a sheet by default:

- Every sheet is a whole number of identical cells, `16x24`. No packing, no
  trimmed variants, no rotation.
- One animation per row, in a fixed order, frames left to right.
- **Every** character's sheet uses the identical layout, so any sheet can replace
  any other. Rows shorter than the column count are padded with empty cells rather
  than cropped, so every row starts at the same place on every sheet.
- The anchor is the bottom centre of the cell, so feet stay on the baseline between
  frames and a walk does not look like a bounce. A cell is taller than a grid cell
  because the chef's hat is taller than one cell.

| Row | Animation | Frames | Used by |
|-----|-----------|--------|---------|
| 0 | `IDLE`    | 2 | the chef, breathing while he waits |
| 1 | `WALK`    | 4 | everyone; played off the step, one cycle per cell |
| 2 | `CLIMB`   | 4 | everyone |
| 3 | `JUMP`    | 2 | everyone; also fall and ride |
| 4 | `SQUASH`  | 1 | a nasty that has been flattened |
| 5 | `STUN`    | 1 | a stung nasty, X eyes |

A sheet is therefore `64x144`. The chef's art faces right and the game mirrors it
by scaling, so there is one set of eyes to keep in step with the walk rather than
two that can disagree. A nasty's body colour is baked into its sheet instead of
being tinted on at draw time, which is what lets a sheet be replaced with
deliberately different-looking art.

The art itself is `tools/char_art.gd`, which paints into an `Image` with
`fill_rect` - no viewport and no framebuffer, so it runs headless and its output is
reproducible:

```sh
godot --headless --script res://tools/make_sheets.gd
godot --headless --import          # required: the sheets are committed as PNGs
```

Both steps are needed. The PNGs are committed because they are inputs to the game,
not build scratch - a fresh checkout has to give a game that runs - and the import
is what refreshes Godot's copy. The suite compares every committed sheet against
what `char_art.gd` paints, pixel for pixel, so a regenerated sheet that was not
re-imported, or a PNG edited by hand, fails instead of quietly drifting.

## Levels

Three levels, 16x15 each, validated in tests: `LUNCH RUSH` (3 burgers),
`DOUBLE SHIFT` (4) and `DINNER RUSH` (3). Each opens on a card naming the level
and the job.

The maps are generated by `tools/make_levels.gd` and pasted into
`LevelData.LEVELS`, because a finished level should be readable in a diff rather
than built at runtime:

```sh
godot --headless --script res://tools/make_levels.gd
godot --headless res://tools/check_levels.tscn    # validate them
```

The generator refuses to emit a map that is wrong in the ways that are invisible
on a 16x15 grid: a burger with more parts than there are ingredient storeys, or a
nasty that would stand on an ingredient and silently shorten it.

There is no level select yet, so the screenshot tool reaches levels 2 and 3 with a
development hook: `godot scenes/game.tscn -- --level=1` starts that level
directly (zero-based). The game ignores the argument unless it is given.

## Tests

`tests/run_tests.gd` runs headless and covers level validation and the shape
every level has to keep, the board and landing rules, burger scoring and assembly,
movement, jumps, ladders and falls, the pepper key, and integration paths through
the same calls a player makes.

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

So `tests/run.sh` runs the suite and boots all four scenes, judging each run by
scanning its output for script errors, parse failures and timeouts rather than
trusting the exit status. CI runs the same script.

## Screenshots and visual checks

`tools/shots.sh` renders the real game and saves PNGs of the title, the level
card and each level to `/tmp/hamburger-helper`:

```sh
sudo pacman -S xorg-server-xvfb          # or your distro's equivalent
./tools/shots.sh
```

The PNGs come from `tools/screenshot.gd`, which saves Godot's own framebuffer
(`get_viewport().get_texture().get_image().save_png()`), at the project's native
256x240 so captures are 1:1 with the game. Nothing is scraped off an X window and
no image library is involved.

A display is still needed, because `--headless` gives Godot a dummy renderer with
no framebuffer to read. That is the only reason Xvfb is here.

`tools/visual_check.sh` then asserts things about those PNGs which are easy to
regress without noticing: that the HUD actually draws, that the level card is
present during the intro and gone once play starts, that each level draws a
recognisable amount of geometry, and that no two captures are accidentally the
same picture. The checks are in `tools/visual_check.gd` and count pixels with
`Image.get_pixel()`; it only reads files, so it runs headless. Thresholds are
fractions of the image rather than pixel counts, so they hold at any capture size.

Three details earn their keep, all learned the hard way:

- Rather than guessing a frame count, each shot waits for the scene's own
  `phase` (`SHOT_UNTIL_PHASE`) and then reports the phase it caught. A capture of
  the wrong moment fails loudly instead of quietly writing a plausible picture of
  the wrong thing, which is how a level-4 shot once came back showing the title
  screen.
- One game process per shot, so nothing is left over from an earlier run.
- `godot --headless tools/see.tscn -- <png> [cols]` prints a capture as ASCII. It
  is how you check a level looks like something without a display.
