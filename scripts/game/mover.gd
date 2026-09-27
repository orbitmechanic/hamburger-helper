class_name Mover
extends Node2D
## Cell-to-cell movement with pixel interpolation.
##
## Every actor snaps to grid cells but is drawn in between, so movement reads as
## smooth animation while collision stays exact.

signal step_finished

var board: Board
var cell := Vector2i.ZERO
var moving := false

var _step_t := 0.0
var _step_dur := Cfg.STEP_WALK
var _from := Vector2.ZERO
var _to := Vector2.ZERO


func place(at_cell: Vector2i) -> void:
	cell = at_cell
	position = Cfg.cell_to_pixel(at_cell)
	moving = false


## Starts a move to `target`, taking `dur` seconds. The cell is updated
## immediately so collision queries during the move see the destination.
func begin_step(target: Vector2i, dur: float) -> void:
	_from = position
	_to = Cfg.cell_to_pixel(target)
	cell = target
	_step_dur = maxf(dur, 0.001)
	_step_t = _step_dur
	moving = true


## Advances the move. Returns true on the frame the move completes.
func tick_step(delta: float) -> bool:
	if not moving:
		return false
	_step_t -= delta
	var t := clampf(1.0 - _step_t / _step_dur, 0.0, 1.0)
	position = _from.lerp(_to, ease_out(t))
	if _step_t > 0.0:
		return false
	position = _to
	moving = false
	step_finished.emit()
	return true


## Fraction of the current step already elapsed, for animation.
func step_phase() -> float:
	if not moving or _step_dur <= 0.0:
		return 1.0
	return clampf(1.0 - _step_t / _step_dur, 0.0, 1.0)


static func ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < Cfg.GRID_W and c.y < Cfg.GRID_H


## Whether a mover can step into this cell: in bounds and not solid to it.
##
## This is the whole movement rule, and it deliberately does not ask whether the
## cell can support weight. The chef walks through the open space *above* a
## platform, so open floor is somewhere he belongs even though nothing can rest
## on it. board.supports_actor() answers the different question of what holds a
## falling ingredient up, and using it here is what used to strand the chef on
## every ladder: stepping off one needs can_enter(), not supports_actor().
func can_enter(c: Vector2i) -> bool:
	return in_bounds(c) and not board.blocks_player(c)
