extends Node
## Global configuration: grid metrics and palette.
##
## Levels are authored as ASCII maps on a discrete cell grid. Every actor in the
## game (player, ingredients, enemies) moves cell-to-cell, which keeps collision
## resolution exact and makes the whole game deterministic enough to test
## headlessly.
##
## This is still an autoload only so the palette reads as Cfg.COL_PLATFORM at
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

## Seconds the level card holds before the chef takes over.
const INTRO_TIME := 2.4

# Palette - a warm diner look on a dark background.
const COL_BG := Color("11111f")
const COL_PLATFORM := Color("c8a06a")
const COL_PLATFORM_DARK := Color("8a6a42")
const COL_PLATFORM_EDGE := Color("f0d0a0")
const COL_WALL := Color("4a4a6a")
const COL_LADDER := Color("e8c070")
const COL_TABLE := Color("d8d8e8")
const COL_PLATE := Color("f4f4ff")
const COL_SALT := Color("ffffff")
const COL_OUTLINE := Color("14141f")

const PLAYER_COOK_SKIN := Color("f2c8a0")
const PLAYER_COOK_SHIRT := Color("e8e8f0")
const PLAYER_COOK_HAT := Color("ffffff")
const PLAYER_COOK_PANTS := Color("3050a0")


## Converts a grid cell to the pixel position of its centre.
static func cell_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5


## Converts a pixel position to the grid cell containing it.
static func pixel_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))
