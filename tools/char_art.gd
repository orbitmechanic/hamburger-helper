class_name CharArt
extends RefCounted
## The nasties' art, as drawing operations on an Image.
##
## The game does not draw characters with draw_rect: it blits frames out of a
## generated sheet, so the art here and the art on screen cannot drift apart, and
## replacing a character means replacing its sheet rather than editing drawing
## code. The chef is the one exception and it is not an inconsistency: his art is
## a hand-drawn PNG rather than a set of shapes, so it is sliced by tools/chef_art.gd
## and lands in the same grid. Both paths produce a sheet, which is what the tests
## compare against the committed PNG.
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
	if character == Sheet.CHEF:
		# The chef is drawn by hand and sliced, not painted here, so he keeps his
		# own art rather than a description of it. See tools/chef_art.gd.
		ChefArt.paint(image)
		return image
	var p := CharArt.new(image)
	# Only the rows this character actually has art for. Every sheet keeps the
	# identical grid, so a row a character has no use for is left clear rather than
	# dropped from the layout - but it must not be filled with a walk cycle that
	# will never be played either, or the sheet claims a frame it does not mean.
	for anim in Sheet.anims_for(character):
		for frame in int(Sheet.FRAMES[anim]):
			# Point the painter at the cell, then paint in actor coordinates. The
			# art does not know or care which cell it is going into.
			p.cell_at = Vector2i(frame * Sheet.CELL.x, Sheet.row(anim) * Sheet.CELL.y)
			villain(p, character, anim, frame)
	return image


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
