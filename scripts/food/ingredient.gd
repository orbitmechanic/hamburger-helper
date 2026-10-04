class_name Ingredient
extends Node2D
## One wide slice of burger sitting in the maze, waiting to be stomped down.
##
## The core rule of the game lives in knock(): stomping every cell of a part drops it
## one level, and if there is another part underneath, that one is knocked too, so
## pushing the top bun of a column walks the whole column down a floor at a time.
## The chef never carries anything.
##
## A part is several cells wide and each cell is its own space. The chef pressing one
## moves that cell down and leaves the rest of the part exactly as it was, so the
## marker is a row of keys going down one at a time rather than a slice getting
## thinner. Nothing but a stomping ever marks a part, which is why the marks are
## cleared where a fall ends and nowhere else.

## Emitted with how many levels the part dropped, for scoring.
signal dropped(floors: int, at: Vector2i)
## Emitted when the part has landed on a plate and joined a burger.
signal boarded(plate: LevelData.Span)
## Emitted when a part was knocked while an enemy was standing on it.
signal carried_rider

## How far down a stomped cell sits, as a fraction of the part's own height.
##
## A stomp moves one cell and leaves the rest of the part exactly as it was, so this
## is a fraction of what a cell is drawn at rather than of the part's width: a fifth
## of an ingredient height, however wide the ingredient is.
##
## It is small enough that a single cell reads as a key pressed rather than as a
## part breaking, and the staircase three or four cells make together is what says
## how much of the part is left.
const STOMP_FRACTION := 1.0 / 5.0

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
## Which of this part's cells the chef has stomped, one flag per cell of `cells`.
##
## The part owns this rather than being told a count, because the count was never
## the thing worth knowing: what matters is *which* spaces are down, and a number
## pushed in from outside could disagree with the way the part is drawn without
## anything noticing. See stomp().
var _stomped: Array[bool] = []

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
	_stomped.resize(cells.size())
	_stomped.fill(false)
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


## Presses one cell of this part down. Returns true if this stomp was the one that
## filled the last cell still at rest, which is the signal to drop the part.
##
## Idempotent, and it takes the cell rather than an index so the caller can hand
## over the grid cell the chef is standing in without first working out which space
## of the part that is. A cell that is not part of this part is ignored rather than
## being clamped to an end, because the only thing that can get here with the wrong
## cell is a part that has already fallen out from under him.
##
## Stomps are *not* given back when the chef steps off. That is the whole difference
## between this and a progress meter along the part's thickness: a jammed key stays
## jammed, and the only thing that un-jams this part is the part landing somewhere.
## It also means a part can be half stomped, left alone for a while, and finished
## later, which is what makes one sitting out on the ground floor worth walking to.
func stomp(cell: Vector2i) -> bool:
	var i := cells.find(cell)
	if i < 0 or _stomped[i]:
		return false
	_stomped[i] = true
	queue_redraw()
	return all_stomped()


## Whether one cell of this part has been stomped.
func is_stomped(cell: Vector2i) -> bool:
	var i := cells.find(cell)
	return i >= 0 and _stomped[i]


## Whether every cell of this part has been stomped, which is the only thing that
## drops it.
func all_stomped() -> bool:
	for down in _stomped:
		if not down:
			return false
	return not _stomped.is_empty()


## How many cells of this part are currently pressed down.
func stomped_count() -> int:
	var n := 0
	for down in _stomped:
		if down:
			n += 1
	return n


## Puts every cell back up. Called when the part lands and nothing else, because a
## part is only ever marked by a stomping and the end of a stomping's effect on it is
## the end of a fall.
func clear_stomps() -> void:
	var was_down := stomped_count() > 0
	_stomped.fill(false)
	if was_down:
		queue_redraw()


## How far one stomped cell sits below its neighbours, in pixels.
##
## Public because it is the one thing about the marker that is not visible in a
## crossing query, and both the suite and the capture check need to ask how far a
## part has moved without reading pixels off it.
func stomp_drop() -> float:
	return CELL_H * STOMP_FRACTION


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
	# Every cell back up once the part has landed, and not when the last one was
	# stomped: a part pressed down the whole way down and popped back the moment it
	# landed reads as the stomps being undone, and clearing at the top of the fall
	# instead would put it back up in the same frame the drop starts, throwing away
	# the beat the marker just earned. Pressed cells travel down and fill out on
	# landing, which reads as squeeze and release. A part knocked by a cascade or a
	# rider while it was partly stomped lands the same way.
	clear_stomps()


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


## How tall one cell of a part is drawn, in pixels: a cell less a pixel of outline
## on each side, so a part at rest fills its row the way a slice of burger should.
const CELL_H := Cfg.TILE - 2.0

## How thick the highlight along the top of a cell is.
const ACCENT_H := 4.0


## Where the top of one cell is drawn, in this part's own space.
##
## Stomped cells sit lower than the rest and nothing else about them changes. The
## part's own height is the unit rather than the tile, so the step is a fifth of a
## slice whether or not the part is wide.
func _top_of(index: int) -> float:
	var y := -Cfg.TILE * 0.5 + 1.0
	if _stomped[index]:
		y += stomp_drop()
	return y


## One cell's draw rect. Cells are a tile wide and run edge to edge, so a part at
## rest is one unbroken slice; only the outline below knows that they can differ.
func _cell_rect(index: int) -> Rect2:
	var x := float(index - (cells.size() - 1) * 0.5) * Cfg.TILE
	return Rect2(x - Cfg.TILE * 0.5, _top_of(index), Cfg.TILE, CELL_H)


func _draw() -> void:
	var fill := Food.color_of(kind)
	var accent := Food.accent_of(kind)
	# Fills first, in one pass with no seam between cells: a part nobody has stomped
	# yet has to look exactly as it always has, one slice. The highlight and the seam
	# are per cell rather than one strip across the part, so a cell that has gone
	# down takes its own bands with it instead of leaving them floating at the old
	# height.
	for i in cells.size():
		var r := _cell_rect(i)
		draw_rect(r, fill)
		draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2.0, ACCENT_H)),
				accent)
		draw_rect(Rect2(r.position + Vector2(2, r.size.y - 5.0),
				Vector2(r.size.x - 4.0, 2.0)), accent.darkened(0.25))
	# Then the outline, which follows the silhouette rather than each cell's box.
	# Every cell gets its top and bottom, the part gets its two outside edges, and a
	# shared edge is drawn only where two neighbours are at different heights - and
	# that edge is the step. Outlining every cell boundary instead would make a part
	# at rest read as a row of tiles, which is the one thing this has to avoid.
	for i in cells.size():
		var r := _cell_rect(i)
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1.0), Cfg.COL_OUTLINE)
		draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0), Cfg.COL_OUTLINE)
		var down_left := i > 0 and r.position.y != _cell_rect(i - 1).position.y
		var down_right := i < cells.size() - 1 and r.position.y != _cell_rect(i + 1).position.y
		if i == 0 or down_left:
			draw_rect(Rect2(r.position.x, r.position.y, 1.0, r.size.y), Cfg.COL_OUTLINE)
		if i == cells.size() - 1 or down_right:
			draw_rect(Rect2(r.end.x - 1.0, r.position.y, 1.0, r.size.y), Cfg.COL_OUTLINE)
