class_name Enemy
extends Mover
## A roaming hazard. Walks the counters, drops off ledges, and turns at walls.
##
## Salt is the answer to all of them, as in the original.

signal caught_player
signal salted

enum Kind { HOTDOG, PICKLE, ONION }
enum St { WALK, FALL, DYING }

const STEP := 0.22
const STEP_FALL := 0.07
## Chance per step of turning around, so packs do not march in lockstep.
const TURN_CHANCE := 0.04
const DYING_TIME := 0.5

var kind: Kind = Kind.HOTDOG
var state: St = St.WALK
var facing := -1
var player: Player

var _t := 0.0
var _dead_t := 0.0
var _anim := 0.0


func setup(p_board: Board, start_cell: Vector2i, p_kind: Kind, p_player: Player) -> void:
	board = p_board
	kind = p_kind
	player = p_player
	place(start_cell)
	z_index = 8


func _process(delta: float) -> void:
	_anim += delta

	if state == St.DYING:
		_dead_t -= delta
		queue_redraw()
		if _dead_t <= 0.0:
			queue_free()
		return

	if tick_step(delta):
		_on_step_end()
	if not moving:
		_decide()
	queue_redraw()


func _decide() -> void:
	if state == St.FALL:
		var below := cell + Vector2i.DOWN
		if not board.blocks_item(below) and board.occupant_at(below) == null and board.in_bounds(below):
			begin_step(below, STEP_FALL)
		else:
			state = St.WALK
		return

	if randf() < TURN_CHANCE:
		facing = -facing

	var target := cell + Vector2i(facing, 0)
	if not board.in_bounds(target) or board.blocks_player(target):
		facing = -facing
		target = cell + Vector2i(facing, 0)
		if not board.in_bounds(target) or board.blocks_player(target):
			return
	begin_step(target, STEP)


func _on_step_end() -> void:
	if state != St.FALL and not board.supports_actor(cell):
		state = St.FALL
	if player != null and player.state != Player.St.DEAD and player.cell == cell:
		caught_player.emit()


## Killed by salt. Plays a brief flash before disappearing.
func salt() -> void:
	if state == St.DYING:
		return
	state = St.DYING
	_dead_t = DYING_TIME
	salted.emit()


func _draw() -> void:
	if state == St.DYING:
		var a := clampf(_dead_t / DYING_TIME, 0.0, 1.0)
		draw_rect(Rect2(-6, -6, 12, 12), Color(1, 1, 1, a))
		return

	draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing, 1.0))
	var body: Color
	match kind:
		Kind.PICKLE:
			body = Color("3f8f3a")
		Kind.ONION:
			body = Color("b57edc")
		_:
			body = Color("c8503a")
	draw_rect(Rect2(-6, -5, 12, 10).grow(1.0), Cfg.COL_OUTLINE)
	draw_rect(Rect2(-5, -4, 10, 8), body)
	draw_rect(Rect2(-5, -4, 10, 2), body.lightened(0.25))
	# Feet, alternating as it walks.
	var swing := 0
	if moving:
		swing = 1 if sin(_anim * 12.0) > 0.0 else 0
	draw_rect(Rect2(-5, 4, 3, 3), Cfg.COL_OUTLINE)
	draw_rect(Rect2(2, 4, 3, 3), Cfg.COL_OUTLINE)
	if swing == 1:
		draw_rect(Rect2(-5, 5, 3, 2), body.darkened(0.3))
	# Eyes
	draw_rect(Rect2(1, -2, 2, 2), Cfg.COL_SALT)
	draw_rect(Rect2(4, -2, 2, 2), Cfg.COL_SALT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
