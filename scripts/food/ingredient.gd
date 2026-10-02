class_name Ingredient
extends Node2D
## One wide slice of burger sitting in the maze, waiting to be knocked down.
##
## The core rule of the game lives in knock(): walking the chef all the way
## across a part drops it one level, and if there is another part underneath,
## that one is knocked too, so pushing the top bun of a column walks the whole
## column down a floor at a time. The chef never carries anything.

## Emitted with how many levels the part dropped, for scoring.
signal dropped(floors: int, at: Vector2i)
## Emitted when the part has landed on a plate and joined a burger.
signal boarded(plate: LevelData.Span)
## Emitted when a part was knocked while an enemy was standing on it.
signal carried_rider

## One cell of the chef running over a part removes this much of the part's
## thickness, so a crossing is five steps deep whatever the part's width.
##
## A fixed fifth per cell rather than a share of the width. The marker's job is to
## say how much of *one crossing* is left, and a proportional share makes a wide
## part look barely touched after the chef has crossed most of it: three cells of a
## three-wide part would read as 33% rather than as three fifths of the work done.
##
## The consequence is that the thin end is only reachable on a part four or five
## cells wide, and every part in the shipped levels is three. Tests use a
## synthetic five-wide part so the floor is exercised rather than assumed.
const CROSS_STEP := 5.0
## Never thinner than one step's worth. A run always completes by or before this
## many cells on a part this wide, so the floor is only reached by a part wider
## than any there is - but a part the chef is standing in has to stay visible, and
## zero would be indistinguishable from a cell with nothing in it.
const MIN_THICKNESS := 1.0 / CROSS_STEP

var board: Board
var kind: Food.Kind = Food.Kind.PATTY
## The run of cells this part occupies. Wider parts are drawn wide, and the chef
## has to cross all of them to knock it down.
var cells: Array[Vector2i] = []
var rest_row := 0
## Row of whatever is holding this part up: a platform, another part, or the
## top of a plate's burger. Falling starts below this.
var support_row := 0
var falling := false
## The rows this part is falling through, from the row it left to the row it is
## heading for, or -1 when it is not falling.
##
## This exists because the grid cell a part occupies jumps the whole way down in one
## go: _relocate() claims the destination row immediately and the fall is only a
## tween, so the rows in between are never in the grid at all. Anything that cares
## about the part passing a cell has to ask for the band rather than look the cell
## up, or it only ever sees the start and the end. See swept_cells().
var fall_from_row := -1
var fall_to_row := -1
## How many of this part's cells the chef has run over since he got onto it, which
## is also how much of its thickness is still on it. See set_cross_progress().
##
## Set by the chef as he arrives on a cell rather than accumulated anywhere, so it
## is a function of the crossing's own bookkeeping and cannot drift from it. Zero
## means nothing is counting this part, and the part is drawn at full thickness.
var cross_cells := 0

var _tween: Tween


func setup(p_board: Board, span: LevelData.Span) -> void:
	board = p_board
	kind = LevelData.INGREDIENT_KINDS[span.ch]
	cells = span.cells()
	rest_row = span.y
	support_row = span.y + 1
	if not board.claim(cells, self):
		push_error("ingredient at row %d cols %d-%d overlaps something"
			% [span.y, span.x, span.right()])
	position = _pixels_for_row(rest_row)
	z_index = 4


## Knocks this part down. `extra_floors` is what an enemy riding it buys: in the
## original a part with a nasty on top drops two levels instead of one, which is
## worth 500 to 8000 points.
##
## Returns where the part came to rest, as {"row", "support"} or {"plate"} on the
## plate it joined. The caller needs that because knocking a column from the top
## means the part underneath may end up on a plate and out of the maze, in which
## case there is no longer anything to land on.
func knock(extra_floors: int = 0) -> Dictionary:
	if falling or not is_inside_tree():
		return {"row": rest_row, "support": support_row}
	if extra_floors > 0:
		carried_rider.emit()
	var where := _drop()
	for i in extra_floors:
		if where.has("plate"):
			break
		where = _drop()
	return where


## Records how much of this part the chef has run over. `covered` is the number of
## distinct cells of it he has been on since he got there, not a distance and not a
## count of arrivals, so pacing back and forth over the same cell does not advance
## it.
##
## Pushed rather than polled, and it no-ops when nothing changed, because it is
## called on every arrival the chef makes anywhere - stepping off one part and
## resetting it is a call that almost always arrives with the value it already
## holds.
func set_cross_progress(covered: int) -> void:
	var n := maxi(covered, 0)
	if n == cross_cells:
		return
	cross_cells = n
	queue_redraw()


## How thick this part is drawn right now, as a fraction of a full-thickness one.
## Public because it is the one thing about the marker that is not visible in a
## crossing query, and both the suite and the capture check need to ask how thick
## a part is without reading pixels off it.
func cross_thickness() -> float:
	return maxf((CROSS_STEP - float(cross_cells)) / CROSS_STEP, MIN_THICKNESS)


## Moves down one level, chaining into whatever is underneath.
##
## A knocked part falls exactly one storey. If another part occupies the row it is
## falling onto, that part is knocked down a level of its own first (so the whole
## column cascades a storey at a time), and this part then takes the row it
## vacated. A part therefore never rests on top of another one, and the one with
## nobody left underneath dives to the plate. That is why pushing the top of a
## column walks the lot down one storey per knock, and doing it repeatedly walks
## it onto the plate.
func _drop() -> Dictionary:
	var spot := board.landing_spot(cells, support_row)
	var below: Ingredient = spot.ingredient

	if below != null:
		# Knock the part that is sitting in the landing row out of the way first.
		# Whatever it lands on is already settled because its own drop did the
		# same, so the row is empty by the time this part arrives.
		below.knock()
		var row: int = spot.row + 1
		# Only ever downwards. If the part underneath could not be moved, the row
		# is still occupied and claim() refuses it, so this stays put too rather
		# than piling up on top.
		if row <= rest_row:
			return {"row": rest_row, "support": support_row}
		return _relocate(row, row + 1)

	if spot.plate != null:
		return _board(spot.plate)

	var row: int = spot.row
	# Only ever downwards, and only to a row that is actually below. A part that
	# has reached the floor is asked to fall again and is told no.
	if row <= rest_row:
		return {"row": rest_row, "support": support_row}
	return _relocate(row, row + 1)


## Moves the part to a new row, claiming the cells there. If the destination is
## somehow occupied the part stays put rather than overlapping.
func _relocate(row: int, support: int) -> Dictionary:
	var where := {"row": rest_row, "support": support_row}
	# Vector2i is a value type, so writing to a cell out of `for cell in cells`
	# is lost. Array.map() builds the new array instead, and assign() puts it
	# back into the typed array board.claim() wants - map() on its own returns
	# an untyped Array, which is a different type as far as the call goes.
	var moved: Array[Vector2i] = []
	moved.assign(cells.map(func(cell: Vector2i) -> Vector2i: return Vector2i(cell.x, row)))
	board.release(cells)
	if not board.claim(moved, self):
		board.claim(cells, self)
		return where
	cells = moved
	fall_from_row = rest_row
	rest_row = row
	fall_to_row = row
	support_row = support
	falling = true
	dropped.emit(1, cells[0])
	_fall_to(_pixels_for_row(row))
	return {"row": row, "support": support}


## Joins a plate's burger and leaves the maze for good.
func _board(plate: LevelData.Span) -> Dictionary:
	board.push_to_stack(plate, kind)
	board.release(cells)
	falling = true
	boarded.emit(plate)
	# Nothing about this part is a target any more.
	queue_free()
	return {"plate": plate}


## The fall is a Tween, not a counter. Godot already runs a timed property change
## to completion and reports when it is done, so there is no _t to keep in step
## with delta and no way for the two to disagree about when the part has landed.
func _fall_to(to: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_LINEAR)
	_tween.tween_property(self, "position", to, Cfg.STEP_FALL)
	_tween.finished.connect(_on_fallen)


func _on_fallen() -> void:
	falling = false
	fall_from_row = -1
	fall_to_row = -1
	# Back to full thickness once the part has landed, and not when the crossing
	# completed: a part that was squashed the whole way down and is thin again the
	# moment it lands reads as the crossing being undone, and resetting at the top
	# of the fall instead would pop it back to full in the same frame the drop
	# starts, throwing away the beat the marker just earned. A part knocked by a
	# cascade or a rider while it was partly run over lands the same way.
	#
	# Resetting here rather than in _relocate() is also what makes this the only
	# place to get right: a part is not marked run-over by anything but a crossing,
	# so the end of that crossing's effect on it is the end of a fall.
	cross_cells = 0
	queue_redraw()


## Every cell this part passes through on its way down, including the one it lands
## in and excluding the one it left.
##
## Read off the columns it currently occupies, so it is correct for a part of any
## width without needing to know how wide it is. The row it came from is excluded
## because it was resting there a moment ago and nothing has fallen past it yet; the
## row it lands in is included, because a part coming to rest inside a nasty flattens
## it exactly as a part passing over one does.
func swept_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if fall_from_row < 0 or fall_to_row < 0:
		return out
	for row in range(fall_from_row + 1, fall_to_row + 1):
		for cell in cells:
			out.append(Vector2i(cell.x, row))
	return out


## Pixel position of this run on `row`.
##
## The run is turned into a Rect2 in cell units and asked for its centre, which is
## what keeps a part drawn over the middle of the cells it occupies. Averaging the
## cell coordinates by hand and adding half the run's width put a wide part half
## its own width to the right of where it stood, so a three-cell patty visibly
## slid as it fell and then snapped back onto the plate when it boarded.
func _pixels_for_row(row: int) -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO
	return Rect2(cells[0].x, row, cells.size(), 1).get_center() * Cfg.TILE


func _draw() -> void:
	var w := float(cells.size() * Cfg.TILE)
	# A part the chef has run over is drawn compressed, with its top edge exactly
	# where it always was. He walks *in* a part's cell rather than on top of one, so
	# his boots are at the top of this rect and the top edge is what has to hold
	# still. Letting it drop would open a visible gap between his boots and the
	# patty. The underside is the edge that is free to rise, and a part that thins
	# from underneath reads as pressed down rather than as eaten away.
	var full := Cfg.TILE - 2.0
	var k := cross_thickness()
	var r := Rect2(-w * 0.5 + 1.0, -Cfg.TILE * 0.5 + 1.0, w - 2.0, full * k)
	draw_rect(r, Cfg.COL_OUTLINE)
	draw_rect(r.grow(-1.0), Food.color_of(kind))
	# A highlight along the top and a darker seam below, so a wide part still
	# reads as one slice rather than a row of tiles. Both scale with the part, which
	# is what keeps them in order on a part at its floor: at a fifth of its height
	# the seam lands just above the bottom edge rather than hanging below it, which
	# is what scaling the offsets and the heights independently would do.
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2.0, 4.0 * k)),
		Food.accent_of(kind))
	draw_rect(Rect2(r.position + Vector2(2, r.size.y - 5.0 * k),
			Vector2(r.size.x - 4.0, 2.0 * k)),
		Food.accent_of(kind).darkened(0.25))
