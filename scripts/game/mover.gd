class_name Mover
extends Node2D
## Cell-to-cell movement with pixel interpolation.
##
## Every actor snaps to grid cells but is drawn in between, so movement reads as
## smooth animation while collision stays exact.

signal step_finished

## The box that counts as the actor for contact, in node coordinates. The node
## origin is the centre of the grid cell, so this runs from the shoulders down to
## the feet.
##
## Deliberately not the cell and not the sprite. The cell is 16x24 and the chef's
## hat is six pixels of that, so treating a cell as the body gave him a catch zone
## a cell and a half in every direction - the chef died while his sprite was
## visibly a full character away from the nasty that got him, which reads as the
## game lying. The body is what a player reads as the character.
const HITBOX := Rect2(-6, -2, 12, 10)

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


## Where the actor is drawn, relative to the cell it is in. Overridden by anything
## that draws itself somewhere other than its cell, so contact follows the picture.
func visual_offset() -> Vector2:
	return Vector2.ZERO


## The box contact is tested against, in world pixels.
##
## Built from the drawn position rather than the cell, so two actors standing in
## neighbouring cells are not touching - and two actors whose sprites overlap are
## touching even mid-step, which is the case a cell-based check got wrong in both
## directions at once.
func hit_rect() -> Rect2:
	return Rect2(position + visual_offset() + HITBOX.position, HITBOX.size)


## Advances the move. Returns true on the frame the move completes.
##
## Linear, and that is the whole fix for movement looking jerky. There used to be
## an ease-out cubic here, applied to every single cell: each cell covered most of
## its distance in the first third and then crawled to a stop, and the next cell
## launched again from zero. The result is a stutter at every cell boundary that
## looks like dropped frames but is not. Easing belongs to a whole movement, not
## to each step of it; a walk that covers cells in a straight line at one speed is
## what reads as smooth at this resolution.
func tick_step(delta: float) -> bool:
	if not moving:
		return false
	_step_t -= delta
	var t := clampf(1.0 - _step_t / _step_dur, 0.0, 1.0)
	position = _from.lerp(_to, t)
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


## Whether a mover can step into this cell: in bounds and not solid to it.
##
## This is the whole movement rule, and it deliberately does not ask whether the
## cell can support weight. The chef walks through the open space *above* a
## platform, so open floor is somewhere he belongs even though nothing can rest
## on it. board.supports_actor() answers the different question of what holds a
## falling ingredient up, and using it here is what used to strand the chef on
## every ladder: stepping off one needs can_enter(), not supports_actor().
func can_enter(c: Vector2i) -> bool:
	return Cfg.in_grid(c) and not board.blocks_player(c)
