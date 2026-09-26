class_name Ingredient
extends Node2D
## A loose ingredient falling to rest on a counter or another ingredient.
##
## Like the player, ingredients move one cell at a time and only ever rest on
## exact cell boundaries, so a dropped stack is always tidy.

signal rested

var board: Board
var kind: Food.Kind = Food.Kind.LETTUCE
var cell := Vector2i.ZERO
var resting := false

var _t := 0.0
var _dur := 0.075
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _to_cell := Vector2i.ZERO


func setup(p_board: Board, start_cell: Vector2i, food_kind: Food.Kind) -> void:
	board = p_board
	kind = food_kind
	cell = start_cell
	position = Cfg.cell_to_pixel(start_cell)
	_begin_fall()


func _begin_fall() -> void:
	if _can_fall():
		_from = position
		_to_cell = cell + Vector2i.DOWN
		_to = Cfg.cell_to_pixel(_to_cell)
		_t = _dur
		return
	_settle()


func _can_fall() -> bool:
	var below := cell + Vector2i.DOWN
	if not board.in_bounds(below):
		return false
	if board.blocks_item(below):
		return false
	return board.occupant_at(below) == null


func _settle() -> void:
	resting = true
	position = Cfg.cell_to_pixel(cell)
	board.set_occupant(cell, self)
	rested.emit()
	queue_redraw()


func _process(delta: float) -> void:
	if resting:
		return
	_t -= delta
	var a := clampf(1.0 - _t / _dur, 0.0, 1.0)
	position = _from.lerp(_to, a)
	if _t > 0.0:
		return
	cell = _to_cell
	position = Cfg.cell_to_pixel(cell)
	if _can_fall():
		_begin_fall()
	else:
		_settle()


func _draw() -> void:
	var r := Rect2(-6, -6, 12, 12)
	draw_rect(r.grow(1.0), Cfg.COL_OUTLINE)
	draw_rect(r, Food.color_of(kind))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Food.accent_of(kind))
	draw_rect(Rect2(r.position + Vector2(2, 4), Vector2(8, 2)), Food.accent_of(kind).darkened(0.2))
