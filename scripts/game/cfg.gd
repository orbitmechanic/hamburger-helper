extends Node
## Global configuration: grid metrics and palette.
##
## Levels are authored as ASCII maps on a discrete cell grid. Every actor in the
## game (player, ingredients, enemies) moves cell-to-cell, which keeps collision
## resolution exact and makes the whole game deterministic enough to test
## headlessly.
##
## This is still an autoload only so the palette reads as Cfg.COL_PEPPER at
## the call site. Nothing here is stateful, and the input bindings deliberately
## live in project.godot instead, where the editor's Input Map can edit them.

const TILE := 16
const GRID_W := 16
const GRID_H := 15
## The playfield as an integer rect, so bounds checks are Rect2i.has_point()
## rather than four comparisons retyped at each call site.
const GRID_RECT := Rect2i(0, 0, GRID_W, GRID_H)

## Seconds spent traversing one cell at each movement speed.
const STEP_WALK := 0.125
const STEP_DASH := 0.055
const STEP_CLIMB := 0.11
const STEP_FALL := 0.075

## How tall one layer of a burger on a plate is drawn, in pixels.
##
## Half a cell. A finished stack is as much decoration as state, and at full
## height four layers filled the whole ground storey and stood in the walkway
## above it. At half height the same burger is two cells tall and tucked under
## the ledge. Only the drawing changes: a part still lands on a plate by joining
## the stack, so no collision moves.
const BURGER_LAYER_H := TILE / 2

# Palette - a warm diner look on a dark background. These are the colours that
# are the same on every level: the background, the HUD, and the level card.
#
# The board's own tiles are per-level rather than global, so that a level reads as
# a different restaurant - see BRANDS below. A level picks one by name in
# LevelData.LEVELS, and LevelData.validate() rejects a name that is not in here,
# so a typo fails the suite rather than quietly drawing the first brand.
const COL_BG := Color("11111f")
const COL_PLATE := Color("f4f4ff")
## The level card panel. Partly transparent, so what lands in a capture is this
## composited over COL_BG rather than this on its own.
const COL_CARD := Color(0.04, 0.04, 0.09, 0.92)
## The lit lip around the level card. Warm, so it reads as a wooden frame rather
## than as part of the panel it outlines.
const COL_CARD_EDGE := Color("f0d0a0")
## Pepper shimmer and the jar in the HUD.
const COL_PEPPER := Color("f5e04a")
const COL_BONUS := Color("6fc24a")
const COL_OUTLINE := Color("14141f")

# --- Brands -----------------------------------------------------------------
#
# One palette per level's look, drawn over the same tiles. These are palettes and
# geometric patterns, not logos: a wide band of one colour across a platform face
# is what makes a level read as a different restaurant at a glance, and nothing
# here imitates any chain's actual trade dress.
#
# Each entry is `body` (the platform face), `band` (the wide stripe across it),
# `edge` (the lit top lip), `dark` (the shadowed underside), plus `wall`, `ladder`
# and `plate` so the rest of the tile set follows the same palette.
#
# A platform tile is body + band + edge + dark in four bands, so roughly a third
# of its pixels are `body`. tools/visual_check.gd counts the whole set rather than
# the body alone, which is what keeps a capture check about "the board drew its
# ledges" instead of about one colour happening to cover a given fraction.
#
# That set is not seven distinct colours: `ladder` is the same colour as `band`
# in every entry here, by design rather than by accident. brand_colors()
# deduplicates because of it, and the duplicate has to be removed rather than
# counted twice - an inflated share is the wrong way round for a floor, since the
# threshold would then also pass on a frame that drew none of it.
const BRANDS := [
	{
		"name": "the arches",
		"body": Color("c8302c"),
		"band": Color("f5c518"),
		"edge": Color("ffd94a"),
		"dark": Color("7a1a18"),
		"wall": Color("8a4a2a"),
		"ladder": Color("f5c518"),
		"plate": Color("fff4d0"),
	},
	{
		"name": "the flame",
		"body": Color("2a5aa0"),
		"band": Color("e8e0d0"),
		"edge": Color("4a8ad0"),
		"dark": Color("18365f"),
		"wall": Color("4a3a2a"),
		"ladder": Color("e8e0d0"),
		"plate": Color("f0e8d8"),
	},
	{
		"name": "the girl",
		"body": Color("2a6a3a"),
		"band": Color("f0f0e4"),
		"edge": Color("5aa86a"),
		"dark": Color("1a4024"),
		"wall": Color("6a4a30"),
		"ladder": Color("f0f0e4"),
		"plate": Color("f8f8ec"),
	},
]

## Every key a brand has to define. This is the contract between a palette and
## the code that draws it: Board._draw_tile asks for `body`, `band`, `edge` and
## `dark` on a platform, and `wall`, `ladder` and `plate` elsewhere, and a brand
## missing one of them would hand draw_rect a null rather than a colour. The suite
## checks every brand against this list, so a palette added with a key left out
## fails there instead of at draw time on one level.
const BRAND_KEYS := ["body", "band", "edge", "dark", "wall", "ladder", "plate"]

## The brand a level names, as an index into BRANDS. An unknown or empty name
## falls back to the first brand rather than failing, because a level that
## renders in the wrong colours is a much smaller problem than a level that
## refuses to draw at all - and validate() catches the typo in the suite.
static func brand_index(brand_name: String) -> int:
	for i in BRANDS.size():
		if BRANDS[i]["name"] == brand_name:
			return i
	return 0


## Whether a name is one of the brands, for LevelData.validate() to say so in
## words rather than letting brand_index() quietly return the first one.
static func has_brand(brand_name: String) -> bool:
	for b in BRANDS:
		if b["name"] == brand_name:
			return true
	return false


## Every brand name, for an error message listing the ones that do exist.
static func brand_names() -> PackedStringArray:
	var out := PackedStringArray()
	for b in BRANDS:
		out.append(b["name"])
	return out


## Every colour a brand is drawn in, which is what tools/visual_check.gd counts to
## decide whether a level drew its board.
##
## Deduplicated, because the keys are roles and not colours: every brand paints
## its ladders the same colour as its band, so counting the list as written would
## count those pixels twice and report a share the frame does not actually have -
## which is the wrong way round for a floor. A threshold set against an inflated
## number is a threshold that no longer catches a blank frame.
static func brand_colors(index: int) -> Array[Color]:
	var out: Array[Color] = []
	var brand: Dictionary = BRANDS[clampi(index, 0, BRANDS.size() - 1)]
	for key in BRAND_KEYS:
		var c: Color = brand[key]
		if not out.has(c):
			out.append(c)
	return out

const PLAYER_COOK_SKIN := Color("f2c8a0")
const PLAYER_COOK_SHIRT := Color("e8e8f0")
const PLAYER_COOK_HAT := Color("ffffff")
const PLAYER_COOK_PANTS := Color("3050a0")


## Whether a cell is on the board. One place, because a bounds check is easy to
## get subtly wrong and every subsystem needs one.
static func in_grid(cell: Vector2i) -> bool:
	return GRID_RECT.has_point(cell)


## Converts a grid cell to the pixel position of its centre.
static func cell_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5


## Converts a pixel position to the grid cell containing it.
static func pixel_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))
