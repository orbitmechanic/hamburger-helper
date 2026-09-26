class_name Salt
extends Mover
## A thrown salt packet: flies in a straight line and takes out the first enemy
## it touches.

signal expired

const STEP := 0.045
## Cells travelled before the packet is used up.
const RANGE := 5

var facing := 1
var player: Player

var _left := RANGE


func setup(p_board: Board, start_cell: Vector2i, p_facing: int, p_player: Player) -> void:
	board = p_board
	player = p_player
	facing = p_facing
	place(start_cell)
	z_index = 12


func _process(delta: float) -> void:
	if tick_step(delta):
		_on_step_end()
	queue_redraw()


func _on_step_end() -> void:
	if player != null:
		for enemy in get_tree().get_nodes_in_group(&"enemies"):
			var e := enemy as Enemy
			if e == null or e.state == Enemy.St.DYING:
				continue
			if e.cell == cell:
				e.salt()
				_finish()
				return

	_left -= 1
	if _left <= 0:
		_finish()
		return

	var target := cell + Vector2i(facing, 0)
	if not board.in_bounds(target) or board.blocks_player(target):
		_finish()
		return
	begin_step(target, STEP)


func _finish() -> void:
	expired.emit()
	queue_free()


func _draw() -> void:
	draw_rect(Rect2(-5, -4, 10, 8).grow(1.0), Cfg.COL_OUTLINE)
	draw_rect(Rect2(-4, -3, 8, 6), Cfg.COL_SALT)
	draw_rect(Rect2(-4, -3, 8, 2), Cfg.COL_SALT.darkened(0.15))
