class_name CharArt
extends RefCounted
## The character art, as drawing operations on an Image.
##
## This is the only place character art is defined. The game no longer draws
## characters with draw_rect: it blits frames out of the generated sheet, so the
## art here and the art on screen cannot drift apart, and replacing a character
## means replacing its sheet rather than editing drawing code.
##
## The `body_*` calls take actor coordinates, the same ones the old _draw() code
## used: (0, 0) is the centre of the actor's grid cell and its feet are at
## y = 8. A sheet cell is taller than a grid cell, so these are offset by a fixed
## amount rather than scaled, and every character lands on the same baseline
## inside its cell.

## How to turn an actor-space point into cell pixels: shift right by half a cell
## and down by a cell and a half, which puts the feet at the bottom of the cell
## where Sheet's anchor expects them.
const ANCHOR := Vector2(8, 16)

## The nasties are two pixels shorter than the chef, so they are drawn two lower
## to stand on the same baseline. Without this they appear to float above the
## floor next to a chef standing on it.
const VILLAIN_DROP := 2

## Body colour per nasty. This palette lives here now because it is baked into
## their sheets rather than looked up at draw time.
const VILLAIN_COLORS := {
	Sheet.HOTDOG: Color("c8503a"),
	Sheet.EGG: Color("f2e4b8"),
	Sheet.PICKLE: Color("3f8f3a"),
}

var image: Image
## Top left of the cell being painted. The art below is written once, in actor
## coordinates, and lands wherever this points - so the same call paints row 2
## frame 1 and row 4 frame 0 with nothing to adjust.
var cell_at := Vector2i.ZERO


func _init(p_image: Image) -> void:
	image = p_image


# --- Actor space -----------------------------------------------------------


## A filled rect, in actor coordinates.
func body(r: Rect2, c: Color) -> void:
	_rect(_at(r.position), r.size, c)


## A border inside a rect, in actor coordinates.
func body_outline(r: Rect2, c: Color, width: float = 1.0) -> void:
	_outline(_at(r.position), r.size, c, width)


## A 3x3 cross for a stunned nasty's eyes, in actor coordinates.
func body_x_mark(at: Vector2i, c: Color) -> void:
	for i in 3:
		_rect(_at(Vector2(at) + Vector2(i, i)), Vector2.ONE, c)
		_rect(_at(Vector2(at) + Vector2(2 - i, i)), Vector2.ONE, c)


## Actor coordinates to sheet pixels.
func _at(at: Vector2) -> Vector2:
	return Vector2(cell_at) + ANCHOR + at


# --- Cell space ------------------------------------------------------------


## Paints one rect, clipped to the cell rather than to the sheet.
##
## Clipping to the sheet would let a frame that draws too wide smear into the next
## column, which then shows up as a stray frame in a padded cell and as garbage in
## a replacement sheet. Clipping to the cell makes the grid a hard boundary: an
## overshooting frame loses a pixel, the way a sprite would be cut off by its
## bounds, and it cannot corrupt a neighbour.
func _rect(at: Vector2, size: Vector2, c: Color) -> void:
	var cell := Rect2i(cell_at, Vector2i(Sheet.CELL))
	var px := Rect2i(at.round(), size.round()).intersection(cell)
	if px.size.x <= 0 or px.size.y <= 0:
		return
	image.fill_rect(px, c)


func _outline(at: Vector2, size: Vector2, c: Color, width: float) -> void:
	var w := maxi(1, roundi(width))
	_rect(at, Vector2(size.x, w), c)
	_rect(at + Vector2(0, size.y - w), Vector2(size.x, w), c)
	_rect(at, Vector2(w, size.y), c)
	_rect(at + Vector2(size.x - w, 0), Vector2(w, size.y), c)


## A whole sheet for one character, painted in memory.
##
## Shared by the generator and the tests. The tests compare this against the
## committed PNG, which is what catches a sheet that was regenerated on one machine
## and not another, or edited by hand: the art and the file on disk cannot quietly
## disagree.
static func sheet(character: String) -> Image:
	var size := Sheet.size()
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	# Transparent, not the background colour. A sheet is drawn over the level, and
	# a filled cell paints a dark box the size of the cell behind every character -
	# including the part of the cell the character is not standing in, which is the
	# room it has to jump and to be lifted into. The cell has to be see-through for
	# that space to be usable at all.
	image.fill(Color(0, 0, 0, 0))
	var p := CharArt.new(image)
	for anim in Sheet.ROWS:
		for frame in int(Sheet.FRAMES[anim]):
			# Point the painter at the cell, then paint in actor coordinates. The
			# art does not know or care which cell it is going into.
			p.cell_at = Vector2i(frame * Sheet.CELL.x, Sheet.row(anim) * Sheet.CELL.y)
			if character == Sheet.CHEF:
				chef(p, anim, frame)
			else:
				villain(p, character, anim, frame)
	return image


# --- Chef -------------------------------------------------------------------


## Frames for the chef. `frame` is the index within the animation.
static func chef(p: CharArt, anim: int, frame: int) -> void:
	match anim:
		Sheet.Anim.WALK:
			_walking(p, frame)
		Sheet.Anim.CLIMB:
			_climbing(p, frame)
		Sheet.Anim.JUMP:
			_jumping(p, frame)
		_:
			_standing(p, -1 if frame % 2 == 1 else 0, 0, 0)


## The chef on the ground.
##
## `bob` lifts the whole chef a pixel, and `lift_left` / `lift_right` are how many
## pixels each leg is off the floor. Lifting one leg at a time on alternate frames
## is what makes the walk read at this size; a body bob on its own looks like the
## chef is bouncing rather than walking.
static func _standing(p: CharArt, bob: int, lift_left: int, lift_right: int,
		arm_forward: bool = true) -> void:
	# Arms. A blocky chef reads as a torso on legs without them, and the walk needs
	# them anyway: with only the legs to animate, a four-frame cycle can only be two
	# poses wearing four hats, and the whole thing looks like a stutter.
	var back_arm_y := -2 if arm_forward else -1
	var front_arm_x := 5 if arm_forward else 4
	p.body(Rect2(-7, back_arm_y + bob, 2, 4), Cfg.PLAYER_COOK_SHIRT)
	p.body(Rect2(front_arm_x, -1 + bob, 2, 4), Cfg.PLAYER_COOK_SHIRT)
	p.body(Rect2(-5, 3 + bob + lift_left, 4, 5 - lift_left), Cfg.PLAYER_COOK_PANTS)
	p.body(Rect2(1, 3 + bob + lift_right, 4, 5 - lift_right), Cfg.PLAYER_COOK_PANTS)
	p.body(Rect2(-6, -1 + bob, 12, 5), Cfg.PLAYER_COOK_SHIRT)
	# The belt is a single dark row along the hem. It used to be a two-pixel band
	# across the middle of the legs, which left the chef standing in eight visible
	# pixels of trousers - enough to be there, not enough to read as trousers.
	p.body(Rect2(-6, 3 + bob, 12, 1), Cfg.COL_OUTLINE)
	p.body(Rect2(-4, -6 + bob, 8, 6), Cfg.PLAYER_COOK_SKIN)
	# Chef's hat: a band and a puff on top.
	p.body(Rect2(-5, -7 + bob, 10, 3), Cfg.PLAYER_COOK_HAT)
	p.body(Rect2(-6, -10 + bob, 12, 4), Cfg.PLAYER_COOK_HAT)
	p.body_outline(Rect2(-6, -10 + bob, 12, 4), Cfg.COL_OUTLINE)
	# Eyes, looking right. The game mirrors the sheet for the other way, so there
	# is only ever one set of eyes to keep in step with the walk.
	p.body(Rect2(1, -5 + bob, 1, 2), Cfg.COL_OUTLINE)
	p.body(Rect2(3, -5 + bob, 1, 2), Cfg.COL_OUTLINE)


static func _walking(p: CharArt, frame: int) -> void:
	# Four distinct poses: both feet down with the arm forward, right foot up with
	# the arm back, both feet down with the arm back, left foot up with the arm
	# forward. The body bobs on the frames with a foot in the air, which is what
	# carries the weight, and the arm swings against the leading leg.
	var lift := [0, 0, 0, 0]
	if frame % 4 < 2:
		lift[1] = 3
	else:
		lift[0] = 3
	_standing(p, -1 if frame % 2 == 1 else 0, lift[0], lift[1],
		frame == 0 or frame == 3)


static func _climbing(p: CharArt, frame: int) -> void:
	# On a ladder he turns to face it, so there are no eyes, and he pulls himself
	# up one arm at a time. Four frames so each pull gets its own frame instead of
	# both arms moving together.
	var up := 1 if frame % 4 < 2 else -1
	var leg_lift := 3 if frame % 2 == 0 else 0
	p.body(Rect2(-5, 2 + leg_lift, 4, 6 - leg_lift), Cfg.PLAYER_COOK_PANTS)
	p.body(Rect2(1, 2, 4, 6), Cfg.PLAYER_COOK_PANTS)
	p.body(Rect2(-6, -1, 12, 5), Cfg.PLAYER_COOK_SHIRT)
	# The raised arm reaches above the shoulder, the other hangs.
	p.body(Rect2(up * 3, -6, 3, 6), Cfg.PLAYER_COOK_SHIRT)
	p.body(Rect2(-up * 4 - 1, -2, 3, 5), Cfg.PLAYER_COOK_SHIRT)
	p.body(Rect2(-5, 4, 10, 2), Cfg.COL_OUTLINE)
	p.body(Rect2(-4, -6, 8, 6), Cfg.PLAYER_COOK_SKIN)
	p.body(Rect2(-5, -7, 10, 3), Cfg.PLAYER_COOK_HAT)
	p.body(Rect2(-6, -10, 12, 4), Cfg.PLAYER_COOK_HAT)
	p.body_outline(Rect2(-6, -10, 12, 4), Cfg.COL_OUTLINE)


static func _jumping(p: CharArt, frame: int) -> void:
	# The arc is the game moving the node, not the art, so this row only has to
	# say "off the floor" and "coming down".
	#
	# Legs spread in the air, then drawn up into a tuck. The tuck has to move the
	# feet, not just the knees: the torso is drawn over the top of the legs, so
	# shortening them where it cannot be seen leaves two identical frames.
	if frame % 2 == 0:
		p.body(Rect2(-5, 2, 4, 6), Cfg.PLAYER_COOK_PANTS)
		p.body(Rect2(1, 2, 4, 6), Cfg.PLAYER_COOK_PANTS)
	else:
		p.body(Rect2(-4, 1, 4, 5), Cfg.PLAYER_COOK_PANTS)
		p.body(Rect2(0, 1, 4, 5), Cfg.PLAYER_COOK_PANTS)
	p.body(Rect2(-6, -1, 12, 5), Cfg.PLAYER_COOK_SHIRT)
	# Arms out for balance, kept inside the cell so they cannot reach into the
	# next column of the sheet.
	p.body(Rect2(-7, -1, 2, 4), Cfg.PLAYER_COOK_SHIRT)
	p.body(Rect2(5, -1, 2, 4), Cfg.PLAYER_COOK_SHIRT)
	p.body(Rect2(-4, -6, 8, 6), Cfg.PLAYER_COOK_SKIN)
	p.body(Rect2(-5, -7, 10, 3), Cfg.PLAYER_COOK_HAT)
	p.body(Rect2(-6, -10, 12, 4), Cfg.PLAYER_COOK_HAT)
	p.body_outline(Rect2(-6, -10, 12, 4), Cfg.COL_OUTLINE)
	p.body(Rect2(1, -5, 1, 2), Cfg.COL_OUTLINE)
	p.body(Rect2(3, -5, 1, 2), Cfg.COL_OUTLINE)


# --- Nasties ---------------------------------------------------------------


## Frames for a nasty. `character` picks the body colour, which is all that
## differs between them.
static func villain(p: CharArt, character: String, anim: int, frame: int) -> void:
	var body: Color = VILLAIN_COLORS[character]
	if anim == Sheet.Anim.SQUASH:
		# Flattened: a wide, short smear with its underside on the floor, so a
		# squashed nasty looks flattened rather than dropped.
		p.body(Rect2(-7, 3, 14, 5), Cfg.COL_OUTLINE)
		p.body(Rect2(-6, 4, 12, 3), body)
		return
	if anim == Sheet.Anim.STUN:
		_stunned(p, body)
		return
	_villain_walking(p, body, frame)


## A nasty has no arms to work with, so walking and climbing come to the same
## cycle - a two-footed blob on a ladder is not a different picture. The row is
## still there in the layout for a sheet that wants to draw the difference.
static func _villain_walking(p: CharArt, body: Color, frame: int) -> void:
	var bob := -1 if frame % 2 == 1 else 0
	var y := VILLAIN_DROP + bob
	p.body(Rect2(-6, y - 5, 12, 10).grow(1.0), Cfg.COL_OUTLINE)
	p.body(Rect2(-5, y - 4, 10, 8), body)
	p.body(Rect2(-5, y - 4, 10, 2), body.lightened(0.25))
	# Feet, alternating as it moves, with the one coming forward catching the
	# light.
	var swing := 1 if frame % 2 == 0 else -1
	p.body(Rect2(-5, y + 3, 3, 3), Cfg.COL_OUTLINE)
	p.body(Rect2(2, y + 3, 3, 3), Cfg.COL_OUTLINE)
	if swing > 0:
		p.body(Rect2(-5, y + 3, 3, 2), Cfg.COL_OUTLINE.lightened(0.5))
	elif swing < 0:
		p.body(Rect2(2, y + 3, 3, 2), Cfg.COL_OUTLINE.lightened(0.5))
	p.body(Rect2(-4, y - 3, 2, 2), Cfg.COL_PEPPER)
	p.body(Rect2(2, y - 3, 2, 2), Cfg.COL_PEPPER)


static func _stunned(p: CharArt, body: Color) -> void:
	var y := VILLAIN_DROP
	p.body(Rect2(-6, y - 5, 12, 10).grow(1.0), Cfg.COL_OUTLINE)
	p.body(Rect2(-5, y - 4, 10, 8), body)
	p.body(Rect2(-5, y - 4, 10, 2), body.lightened(0.25))
	p.body(Rect2(-5, y + 3, 3, 3), Cfg.COL_OUTLINE)
	p.body(Rect2(2, y + 3, 3, 3), Cfg.COL_OUTLINE)
	p.body_x_mark(Vector2i(-4, y - 3), Cfg.COL_OUTLINE)
	p.body_x_mark(Vector2i(2, y - 3), Cfg.COL_OUTLINE)
