class_name Sheet
extends RefCounted
## The animation sheet layout, shared by every character, and the loader for it.
##
## There is no single industry-standard sprite sheet format - "standard" in this
## space means a small set of conventions that tools all agree on, and the ones
## followed here are the ones a uniform grid slice implies, which is also how
## Unity and Godot slice a sheet by default:
##
##   * Every cell is the same size, and the sheet is a whole number of cells
##     across and down. No packing, no trimmed variants, no rotation flags.
##   * One animation per row, in a fixed order, and the frames of that animation
##     run left to right in order.
##   * Every character's sheet uses the identical row order, column count and
##     cell size, so any sheet can replace any other.
##
## That last point is the reason the layout lives here rather than being assumed
## by the drawing code: re-arting a character is dropping a new PNG with the same
## name in, with no code change and no risk of one character's art being laid out
## differently from another's.
##
## Rows shorter than COLUMNS are padded with empty cells rather than cropped, so
## every row starts at the same x on every sheet.
##
## The anchor is the bottom centre of the cell. Characters stand on a baseline
## there, so their feet do not move between frames and a walk cycle does not look
## like the character is bouncing. It also means a cell can be taller than a
## character, which it has to be: the chef's hat is taller than one grid cell.

## One cell, in pixels. Wide enough to hold a character, tall enough to hold the
## chef with his hat on, and the same for everybody.
const CELL := Vector2i(16, 24)
## Cells across the sheet. The widest animation is the chef's run, at six frames.
const COLUMNS := 6

enum Anim {
	IDLE,
	WALK,
	CLIMB,
	JUMP,
	PUNCH,
	VICTORY,
	DEATH,
	PARACHUTE,
	SQUASH,
	STUN
}

## Rows, in sheet order. The index in this array is the row on the sheet, so
## adding one here is what puts it on every sheet at once.
const ROWS := [Anim.IDLE, Anim.WALK, Anim.CLIMB, Anim.JUMP, Anim.PUNCH,
		Anim.VICTORY, Anim.DEATH, Anim.PARACHUTE, Anim.SQUASH, Anim.STUN]

## How many frames each animation has. A character with fewer simply leaves the
## rest of its row empty.
const FRAMES := {
	Anim.IDLE: 4,
	Anim.WALK: 6,
	Anim.CLIMB: 6,
	Anim.JUMP: 4,
	Anim.PUNCH: 3,
	Anim.VICTORY: 5,
	Anim.DEATH: 1,
	Anim.PARACHUTE: 1,
	Anim.SQUASH: 1,
	Anim.STUN: 1,
}

## Frames per second for each animation, so the walk cycles at a speed that
## matches the actor's cell movement rather than looking pasted on.
##
## Only the animations played off a clock of their own read this. WALK, CLIMB and
## JUMP are driven by the actor's step instead, and PUNCH and VICTORY are played
## once and held on the last frame, so none of them use it.
const FPS := {
	Anim.IDLE: 2.0,
	Anim.WALK: 6.0,
	Anim.CLIMB: 6.0,
	Anim.JUMP: 6.0,
	Anim.PUNCH: 8.0,
	Anim.VICTORY: 6.0,
	Anim.DEATH: 4.0,
	Anim.PARACHUTE: 4.0,
	Anim.SQUASH: 4.0,
	Anim.STUN: 4.0,
}

## Which animations each character actually has.
##
## Every sheet keeps the identical grid, so a character that has no use for a row
## simply leaves it blank rather than the row being dropped from the layout - a
## shared layout is the whole reason a sheet can be swapped for any other. This is
## the one thing that is allowed to differ per character: the chef punches, throws
## a victory pose and comes down under a parachute, and a hotdog does not. A blank
## row is therefore expected art, not a missing frame, and the tests ask
## `anims_for()` which rows are meant to be empty.
const CHEF_ANIMS := [Anim.IDLE, Anim.WALK, Anim.CLIMB, Anim.JUMP, Anim.PUNCH,
		Anim.VICTORY, Anim.DEATH, Anim.PARACHUTE]
const VILLAIN_ANIMS := [Anim.IDLE, Anim.WALK, Anim.CLIMB, Anim.JUMP, Anim.SQUASH,
		Anim.STUN]

const DIR := "res://assets/sheets/"

## The chef's own art, as drawn by hand rather than painted by the generator. It
## lives in the repository rather than being read from outside it, because the
## generated sheets are checked against the code that draws them and a sheet that
## could not be rebuilt from a checkout would quietly stop being reproducible.
const CHEF_SOURCE := "res://assets/source/chef_a2.png"

const CHEF := "chef"
const HOTDOG := "hotdog"
const EGG := "egg"
const PICKLE := "pickle"

const CHARACTERS := [CHEF, HOTDOG, EGG, PICKLE]

static var _cache := {}


## The whole sheet, in pixels.
static func size() -> Vector2i:
	return Vector2i(CELL.x * COLUMNS, CELL.y * ROWS.size())


## Which sheet row an animation is on.
static func row(anim: Anim) -> int:
	return ROWS.find(anim)


## Rows down the sheet.
static func row_count() -> int:
	return ROWS.size()


## The animations a character has art for, so a row it has no use for is known to
## be deliberately blank rather than forgotten.
static func anims_for(character: String) -> Array:
	return CHEF_ANIMS if character == CHEF else VILLAIN_ANIMS


## An animation's name, for anything that reports one. "anim 4" is not something
## anyone can act on, and a report about a frame is usually the only clue a sheet
## problem leaves.
static func anim_name(anim: Anim) -> String:
	return Anim.keys()[anim]


## How many frames an animation has, wrapping a looping one and clamping a
## single-frame one.
static func frame_of(anim: Anim, t: float) -> int:
	var count: int = FRAMES[anim]
	if count <= 1:
		return 0
	return posmod(int(t * float(FPS[anim])), count)


## Frame for an animation that movement is driving: `phase` runs 0 to 1 across
## one step, so one cycle plays per cell and the feet land with the movement.
## A cycle on a clock of its own would look right standing still and slide the
## moment the actor moved.
static func frame_at_phase(anim: Anim, phase: float) -> int:
	var count: int = FRAMES[anim]
	return mini(int(phase * float(count)), count - 1)


## The source rectangle for one frame, in sheet pixels.
static func region(anim: Anim, frame: int) -> Rect2:
	var r := row(anim)
	return Rect2(Vector2(frame * CELL.x, r * CELL.y), Vector2(CELL))


## Where to draw a cell so its bottom centre lands on the actor's feet.
##
## The node sits at the centre of a grid cell, and a character's feet are half a
## cell below that, so the sheet cell's bottom edge belongs at +TILE/2 and its top
## edge at TILE/2 - CELL. Horizontally the cell is centred on the node.
##
## Getting this wrong is invisible in a way that is expensive to catch: a cell drawn
## too low hangs off the bottom of the screen, so the actor simply does not appear
## and every other check still passes. The character checks in the suite and the
## chef-pixel checks in tools/visual_check.gd are what notice.
static func offset() -> Vector2:
	return Vector2(-CELL.x * 0.5, Cfg.TILE * 0.5 - float(CELL.y))


## The sheet for a character, or null if the file is missing.
##
## A missing sheet is reported rather than fatal: the game should still run and
## say what is wrong, because the alternative is a character that silently does
## not draw and a bug report that says "the chef has gone missing".
static func texture(character: String) -> Texture2D:
	if _cache.has(character):
		return _cache[character]
	var path := DIR + character + ".png"
	if not ResourceLoader.exists(path):
		push_error("no sheet at %s: run godot --headless --script res://tools/make_sheets.gd" % path)
		_cache[character] = null
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("sheet at %s did not load as a texture" % path)
	_cache[character] = tex
	return tex


## Whether every character has a sheet on disk. Checked by the tests, so a
## forgotten character is caught before anyone wonders why it is invisible.
static func all_present() -> PackedStringArray:
	var missing := PackedStringArray()
	for character in CHARACTERS:
		if texture(character) == null:
			missing.append(character)
	return missing
