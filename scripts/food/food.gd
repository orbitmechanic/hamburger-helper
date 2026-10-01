class_name Food
extends Resource
## The burger parts and how a finished burger is put together.
##
## Definitions live in code rather than as .tres assets so that the whole
## ingredient set is reviewable in a diff and needs no import step.

enum Kind {
	BUN_BOTTOM,
	BUN_TOP,
	LETTUCE,
	TOMATO,
	PATTY,
}

const DEFS := {
	Kind.BUN_BOTTOM: {
		"name": "Bun",
		"color": Color("d9a05b"),
		"accent": Color("b87a3c"),
		"is_bun": true,
		"bun_role": "bottom",
	},
	Kind.BUN_TOP: {
		"name": "Bun Lid",
		"color": Color("eec27f"),
		"accent": Color("c98f4a"),
		"is_bun": true,
		"bun_role": "top",
	},
	Kind.LETTUCE: {
		"name": "Lettuce",
		"color": Color("6fc24a"),
		"accent": Color("4c9a2c"),
		"is_bun": false,
		"bun_role": "",
	},
	Kind.TOMATO: {
		"name": "Tomato",
		"color": Color("e2453c"),
		"accent": Color("b02a24"),
		"is_bun": false,
		"bun_role": "",
	},
	Kind.PATTY: {
		"name": "Patty",
		"color": Color("7b4a2a"),
		"accent": Color("5a3320"),
		"is_bun": false,
		"bun_role": "",
	},
}

## Textures, as a mask in a second colour over a layer's own colour.
##
## A mask rather than an image, one character per pixel: a mark is drawn, a dot is
## left alone. A burger layer is a few dozen pixels across and half a cell tall, so
## the tile is as tall as a layer and a mark is a single pixel. Anything bigger
## would be detail nobody can see at this scale, and anything stored as a texture
## would be a file the colours in DEFS could quietly drift out of step with.
##
## The patty is the black one and the lettuce the white, which is the way round
## round they read at a glance: a speckled brown patty and a ribbed green leaf. The
## patty's black is a very dark brown rather than a true black, because a true black
## speck is the same colour as the outline a layer is stroked in and the texture
## disappears into the edge instead of sitting on the patty.
const TEXTURES := {
	Kind.PATTY: {
		"name": "black",
		"color": Color("1d1410"),
		"tile": [
			"#...",
			"....",
			"..#.",
			"....",
			"....",
			"#...",
			"....",
			"..#.",
		],
	},
	Kind.LETTUCE: {
		"name": "white",
		"color": Color("e6f4d8"),
		"tile": [
			"..#.",
			".##.",
			"..#.",
			"....",
			".#..",
			"..#.",
			".##.",
			"....",
		],
	},
}

## The minimum a burger can be: something to sit on, a patty, and a lid.
const MIN_STACK := 3

## Scoring, in the spirit of the original's escalating rewards.
##
## Dropping a part a level is the bread and butter, so it pays a little. A
## finished burger pays a lot more and more of it the bigger the burger is, which
## is what makes building the tall stack a better plan than pushing whatever is
## nearest. Squashing a nasty or riding one down is worth more again, because
## both take nerve rather than a walk across a bun.
const POINTS_PER_FLOOR := 50
const POINTS_PER_SQUASH := {0: 100, 1: 200, 2: 300}
## Indexed by the number of parts in the finished burger.
const POINTS_BURGER := [0, 0, 0, 500, 1000, 2000, 3000, 5000, 8000]
## Carrying a nasty down a part is the hardest thing in the game to do.
const POINTS_RIDER := 1000
const POINTS_PEPPER := 500
const POINTS_STUN := 1000
const POINTS_LIFE := 0


static func burger_points(levels: int) -> int:
	if levels < 0 or levels >= POINTS_BURGER.size():
		return 0
	return POINTS_BURGER[levels]


static func squash_points(kind: int) -> int:
	return POINTS_PER_SQUASH.get(kind, 100)


static func def(kind: Kind) -> Dictionary:
	return DEFS[kind]


## Whether this is a real burger part.
##
## Every caller here is handed a kind that came from somewhere else - a map
## character, a level recipe, a plate stack - so the guard is kept deliberately.
## Indexing DEFS with a bad value throws, and because the throw came from _draw
## it surfaced as the renderer crashing rather than as the caller that caused it.
static func is_kind(kind: int) -> bool:
	return DEFS.has(kind)


static func display_name(kind: Kind) -> String:
	return String(DEFS[kind]["name"])


static func is_bun(kind: Kind) -> bool:
	return bool(DEFS[kind]["is_bun"])


static func color_of(kind: Kind) -> Color:
	return DEFS[kind]["color"]


static func accent_of(kind: Kind) -> Color:
	return DEFS[kind]["accent"]


## Whether a kind has a texture. A bun has none: its rounding is the detail, and a
## speckled dome reads as dirt rather than as a bun.
static func has_texture(kind: Kind) -> bool:
	return TEXTURES.has(kind)


## The colour a kind's texture is drawn in.
static func texture_of(kind: Kind) -> Color:
	return TEXTURES[kind]["color"]


## Whether the pixel at a layer-local position is one of a kind's texture marks.
##
## The mask repeats every four columns and every `tile.size()` rows. A layer is
## half a cell tall, so it never shows the same row of the tile twice, and the
## offset the board applies per layer stops two stacked patties from lining their
## specks up into stripes.
static func texture_at(kind: Kind, x: int, y: int) -> bool:
	if not TEXTURES.has(kind):
		return false
	var tile: Array = TEXTURES[kind]["tile"]
	var row: String = tile[posmod(y, tile.size())]
	return row.substr(posmod(x, row.length()), 1) == "#"


## Whether a burger stacked bottom-to-top reads as finished.
##
## A burger is, in order: a bottom bun, a patty, any number of lettuce and
## tomato slices, and a top bun on the very top. Every position is checked
## rather than just "does it contain a patty", so a burger assembled inside out -
## the patty landing before the base bun, say - is rejected instead of scored.
static func stack_is_burger(stack: Array) -> bool:
	if stack.size() < MIN_STACK:
		return false
	for kind: int in stack:
		if not is_kind(kind):
			return false
	# The base has to actually be the base and the lid has to be on top.
	if int(stack[0]) != Kind.BUN_BOTTOM:
		return false
	if int(stack[stack.size() - 1]) != Kind.BUN_TOP:
		return false
	# The patty sits directly on the base bun. A bun stacked straight on a bun
	# is a lid on a plate, not a burger, and a patty buried under the toppings
	# is not what the recipe calls for.
	if int(stack[1]) != Kind.PATTY:
		return false
	# Everything between the patty and the lid is optional, and only toppings:
	# no second bun and no second patty can hide in the middle of a burger.
	for i in range(2, stack.size() - 1):
		if int(stack[i]) not in [Kind.LETTUCE, Kind.TOMATO]:
			return false
	return true
