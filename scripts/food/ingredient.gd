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
	rest_row = row
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
	queue_redraw()


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
	var r := Rect2(-w * 0.5 + 1.0, -Cfg.TILE * 0.5 + 1.0, w - 2.0, Cfg.TILE - 2.0)
	draw_rect(r, Cfg.COL_OUTLINE)
	draw_rect(r.grow(-1.0), Food.color_of(kind))
	# A highlight along the top and a darker seam below, so a wide part still
	# reads as one slice rather than a row of tiles.
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2.0, 4)), Food.accent_of(kind))
	draw_rect(Rect2(r.position + Vector2(2, r.size.y - 5.0), Vector2(r.size.x - 4.0, 2)),
		Food.accent_of(kind).darkened(0.25))
