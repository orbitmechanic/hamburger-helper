class_name ChefArt
extends RefCounted
## The chef's art, cut out of the hand-drawn sheet in assets/source.
##
## The nasties are painted by CharArt out of drawing operations; the chef is not,
## because his art is real art rather than a description of some. He arrives as a
## single PNG of 26 poses and is sliced into the cells Sheet describes, which keeps
## the two things the sheet contract is for: the game still blits a plain grid,
## and the committed sheet is still reproducible from a checkout by re-running the
## generator. The source PNG is committed too, so "re-run the generator" means the
## same thing on any machine.
##
## Three things have to be decided when a drawing that size is cut down to a cell
## this small, and all three are settled here rather than leaking into the game:
##
##   * Scale. The source is drawn on a 32x40 grid to a cell of 16x24, so every
##     figure is halved. Point sampling, not averaging: averaging would blend the
##     seven source colours into shades nobody chose, and a chef with a gradient
##     down his hat is not the chef who was drawn.
##   * Facing. The source chef faces left - the punch, the kick, the victory pose
##     and the swim all throw their action that way - but a sheet holds a
##     right-facing character and the game mirrors it for the other direction. So
##     the import flips. Without it the chef would season the floor behind him and
##     kick away from whatever he was aiming at.
##   * Alignment. Sheet anchors a character on the bottom centre of its cell, so the
##     two things that would otherwise drift between frames are pinned. The body's
##     centre line is taken from the hat: it is wide, symmetric, and in the same
##     place in every pose including the ones where an arm or a leg is thrown out
##     to one side, which is exactly the case where centring the figure's bounding
##     box would walk his torso across the cell. The feet come from one baseline
##     shared by the whole animation, so a run's airborne frames really do rise
##     instead of every frame dropping onto the floor on its own.

## Where the source lives, and the shape of the grid drawn on it: cells 32x40, the
## first one starting at (26, 14).
##
## The source is not flush to its own edges and the last figure stops short of the
## right margin, so the cells are located by an origin and a pitch rather than by
## slicing the image into equal parts. The figures are then found inside each band
## by flood fill rather than by reading the grid, because several poses are wider
## than one cell and run into the next - which is also why the wide ones cannot
## simply be cut on the grid lines.
const SOURCE := Sheet.CHEF_SOURCE
const SRC_PITCH := Vector2i(32, 40)

## The chef's own palette, read off the drawing.
##
## It lives here rather than in Cfg because it is baked into his sheet instead of
## being looked up at draw time, which is the same reason the villains' colours sit
## in CharArt. Two of the seven are worth naming: the toque and apron, which is the
## largest shape on him and what the visual check counts to prove he was drawn, and
## the inked outline, which is what the check looks for to catch an import that
## lost it.
const COL_HAT := Color("ffffeb")
const COL_LINE := Color("190e0e")

## The rows of poses in the source, as the y each band starts at, and how many
## figures it holds.
##
## These are measured positions rather than derived from a running index, because
## the swim band in the middle is deliberately skipped. The bands are therefore not
## consecutive, so an index multiplied out from the origin lands on the wrong row
## of poses and quietly serves a chef who is swimming when he should be seasoning.
## The count is checked for the same reason.
##
## Nothing plays a swim yet, and an unused row would mean either a seventh column
## or an eleventh row of permanently blank cells. The art is not lost - it is in
## the committed source PNG, and putting it in is one entry in each of these.
const BANDS := [14, 54, 94, 174]
const BAND_FIGURES := [6, 6, 5, 3]

## Which figure in which band each frame of each animation comes from.
##
## Two of these are not in source order, and both are because a kick reads
## differently depending on what it is for. The jump is played along the arc of the
## hop, so it runs tucked-first and extends on the way down. The victory is a
## flourish that ends on the celebration, so it plays the sweep in the order it was
## drawn and lands on the pose.
const FRAME_SOURCE := {
	Sheet.Anim.IDLE: [[0, 0], [0, 1], [0, 2], [0, 3]],
	Sheet.Anim.WALK: [[1, 0], [1, 1], [1, 2], [1, 3], [1, 4], [1, 5]],
	# The run doubles as the climb, so a chef on a ladder is a chef running. He
	# keeps his face on the way up, which the old drawn climb deliberately did not.
	Sheet.Anim.CLIMB: [[1, 0], [1, 1], [1, 2], [1, 3], [1, 4], [1, 5]],
	Sheet.Anim.JUMP: [[2, 2], [2, 1], [2, 0], [2, 3]],
	Sheet.Anim.PUNCH: [[3, 0], [3, 1], [3, 2]],
	Sheet.Anim.VICTORY: [[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]],
	Sheet.Anim.DEATH: [[0, 4]],
	Sheet.Anim.PARACHUTE: [[0, 5]],
}

## How many rows at the top of a figure are the hat, for finding the body's centre
## line. The toque is the same block in every pose and always sits at the top, so
## it is the one part of the drawing that can be trusted to mark where the body is
## rather than where a limb happens to be reaching.
const HAT_ROWS := 12

## The source is halved to fit a cell, so a row of the source is two of the cell.
const SCALE := 0.5

static var _source: Image = null
static var _figures := {}


## Paints every chef animation into `image`, which is the sheet being built.
##
## A missing or unreadable source is reported and skipped rather than fatal, for the
## same reason Sheet reports a missing sheet instead of dying: the game should still
## run and say what is wrong. The tests are what turn a silent blank chef into a
## failure, and they fail on a sheet with no art in it either way.
static func paint(image: Image) -> void:
	var src := source()
	if src == null:
		return
	for anim in Sheet.CHEF_ANIMS:
		_paint_anim(image, src, anim)


## The source drawing, loaded once.
static func source() -> Image:
	if _source == null:
		if not FileAccess.file_exists(SOURCE):
			push_error("no chef source at %s" % SOURCE)
			return null
		_source = Image.load_from_file(SOURCE)
	return _source


# --- Slicing ----------------------------------------------------------------


## One animation: every frame of it, aligned against a baseline they all share.
static func _paint_anim(dst: Image, src: Image, anim: int) -> void:
	var picks: Array = FRAME_SOURCE[anim]
	# One entry per frame, in frame order, and a missing pose stays a hole rather
	# than closing up: a short list would slide every later frame one cell to the
	# left, turning one missing pose into a sheet of the wrong chef.
	var figs: Array = []
	for pick in picks:
		figs.append(_figure(src, pick[0], pick[1], anim))
	var base := 0
	for f in figs:
		if f != null:
			base = maxi(base, (f["rect"] as Rect2i).end.y)
	for i in figs.size():
		var f: Variant = figs[i]
		if f == null:
			continue
		var sprite := _scaled(src, f["rect"])
		var cell := Rect2i(Vector2i(i * Sheet.CELL.x, Sheet.row(anim) * Sheet.CELL.y),
				Vector2i(Sheet.CELL))
		_blit(dst, sprite, _where(f, sprite, base, cell), cell)


## Where in its cell a frame lands: body centred, feet on the animation's baseline.
static func _where(f: Dictionary, sprite: Image, base: int, cell: Rect2i) -> Vector2i:
	var rect: Rect2i = f["rect"]
	var size := sprite.get_size()
	# How far this frame's own feet sit above the shared baseline, in cell pixels.
	# The gap is a whole number of source rows, so halving it is exact.
	var lift := int(round(float(base - rect.end.y) * SCALE))
	# The body's centre line, in cell pixels, measured from the sprite's left edge.
	# The source is measured before the flip and mirrored after it, so the centre
	# line ends up measured back from the sprite's right edge.
	var axis := (float(f["axis"]) * 0.5 - float(rect.position.x)) * SCALE
	var flipped := float(size.x) - axis
	return cell.position + Vector2i(
		roundi(float(Sheet.CELL.x) * 0.5 - flipped),
		Sheet.CELL.y - lift - size.y)


## A figure cut out, halved and turned to face right.
static func _scaled(src: Image, rect: Rect2i) -> Image:
	var sprite := src.get_region(rect)
	# Point sampling. The two alternative resamplings are both wrong for pixel art:
	# averaging invents colours, and a smooth filter rounds the outline off.
	sprite.resize(maxi(1, rect.size.x / 2), maxi(1, rect.size.y / 2),
			Image.INTERPOLATE_NEAREST)
	sprite.flip_x()
	return sprite


## Copies a frame into the sheet, clipped to its own cell.
##
## Clipping matters for the same reason it does in CharArt: a figure wider than the
## cell must lose the overshoot rather than smear into the next column, where it
## would show up as a stray frame in a padded cell and as junk in a replacement
## sheet.
static func _blit(dst: Image, sprite: Image, at: Vector2i, cell: Rect2i) -> void:
	var px := Rect2i(at, sprite.get_size()).intersection(cell)
	if px.size.x <= 0 or px.size.y <= 0:
		return
	# Where the kept part starts inside the sprite, so a figure clipped on the left
	# or the top copies from the right place rather than the sprite's corner.
	var from := Vector2i(maxi(0, cell.position.x - at.x), maxi(0, cell.position.y - at.y))
	dst.blit_rect(sprite, Rect2i(from, px.size), px.position)


# --- Finding the poses ------------------------------------------------------


## One figure, by band and index within that band, or null if the band does not
## hold one. Null rather than a substitute: the caller keeps the hole, and the
## sheet tests fail on the frame that came out empty.
static func _figure(src: Image, band: int, index: int, anim: int) -> Variant:
	var found := _band_figures(src, band)
	if index >= found.size():
		push_error("chef source band %d (y%d) has no figure %d for %s"
				% [band, BANDS[band], index, Sheet.anim_name(anim)])
		return null
	return found[index]


## Every figure in one band, left to right, each with its box and its centre line.
static func _band_figures(src: Image, band: int) -> Array:
	if _figures.has(band):
		return _figures[band]
	var y0: int = BANDS[band]
	var y1 := y0 + SRC_PITCH.y - 1
	var w := src.get_width()
	var h := src.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var out := []
	for y in range(maxi(0, y0), mini(h, y1 + 1)):
		for x in w:
			if seen[y * w + x] == 1 or src.get_pixel(x, y).a <= 0.0:
				continue
			# Flood fill, 8-connected: the outlines are one pixel thick and the
			# diagonals between them are how a hat joins a face, so 4-connected
			# would cut every pose in half.
			var stack := [Vector2i(x, y)]
			seen[y * w + x] = 1
			var head := 0
			var box := Rect2i(x, y, 0, 0)
			var hat_lo := x
			var hat_hi := x
			while head < stack.size():
				var p: Vector2i = stack[head]
				head += 1
				box = box.expand(p)
				if p.y < box.position.y + HAT_ROWS:
					hat_lo = mini(hat_lo, p.x)
					hat_hi = maxi(hat_hi, p.x)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := p.x + dx
						var ny := p.y + dy
						if nx < 0 or ny < 0 or nx >= w or ny >= h:
							continue
						if seen[ny * w + nx] == 1 or src.get_pixel(nx, ny).a <= 0.0:
							continue
						seen[ny * w + nx] = 1
						stack.append(Vector2i(nx, ny))
			# `axis` is the hat's left plus right, kept as a doubled centre so the
			# whole thing stays in integers: a half-pixel centre would otherwise
			# round differently for an even-width hat than an odd one.
			out.append({"rect": box, "axis": hat_lo + hat_hi})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["rect"].position.x < b["rect"].position.x)
	if out.size() != int(BAND_FIGURES[band]):
		# Loud, because a band that does not hold what the sheet says it does means
		# every frame after this one is the wrong chef, and the sheet still looks
		# plausible enough to ship.
		push_error("chef source band %d (y%d) has %d figures, expected %d"
				% [band, y0, out.size(), BAND_FIGURES[band]])
	_figures[band] = out
	return out
