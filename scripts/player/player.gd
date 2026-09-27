class_name Player
extends Mover
## The chef.
##
## He does not carry anything. The whole game is walking across a burger part so
## that it drops one level, so the things that used to be the core of this script
## - the tray, the stack on it, grabbing, throwing, salting - are gone. What is
## left is movement across the grid plus one rule: notice which part of which
## ingredient he has walked over, and knock it down when he has covered the lot.

## Emitted with the ingredient he just walked the full width of.
signal crossed(ing: Ingredient)

enum St { WALK, CLIMB, FALL, JUMP }

const JUMP_DUR := 0.17
## Peak of the hop, in pixels. A one-cell hop that clears an enemy but not much
## more: the jump is a dodge, not a way to climb a storey.
const JUMP_LIFT := 13.0
const PEPPER_TIME := 5.0

var facing := 1
var state: St = St.WALK
## Pepper charges in the jar, and how long the current dose lasts.
var pepper_left := 0
var pepper_time := 0.0

## The ingredient currently being walked over, and which of its cells have been
## covered. A part is only pushed when every one of them has been.
var _cross: Ingredient = null
var _covered := {}


func setup(p_board: Board, start: Vector2i) -> void:
	board = p_board
	place(start)
	facing = 1
	z_index = 10
	queue_redraw()


## Puts the chef somewhere, clearing any crossing in progress. Used for the start
## of a level and for a respawn after being caught: either way a part the chef was
## halfway across must not stay half counted, or respawning on top of a part would
## knock it down without the chef having walked anywhere.
func place(at: Vector2i) -> void:
	super.place(at)
	_cross = null
	_covered.clear()
	moving = false
	state = St.WALK


func _process(delta: float) -> void:
	if pepper_time > 0.0:
		pepper_time = maxf(pepper_time - delta, 0.0)
	_drive()
	var done := tick_step(delta)
	# The hop arc is applied on top of the linear cell-to-cell interpolation, so
	# the jump still ends exactly on a grid cell.
	if state == St.JUMP and moving:
		position.y -= sin(PI * step_phase()) * JUMP_LIFT
	if done:
		_arrived()


## Whether enemies should pass harmlessly through him right now.
func ghost() -> bool:
	return pepper_time > 0.0


func add_pepper(charges: int = 1) -> void:
	pepper_left += charges


func use_pepper() -> bool:
	if pepper_left <= 0:
		return false
	pepper_left -= 1
	pepper_time = PEPPER_TIME
	return true


# --- Input -----------------------------------------------------------------


func _drive() -> void:
	if moving:
		return
	if state == St.FALL:
		_start_fall()
		return

	var want := Vector2i.ZERO
	if Input.is_action_pressed(&"move_left"):
		want = Vector2i.LEFT
	elif Input.is_action_pressed(&"move_right"):
		want = Vector2i.RIGHT
	elif Input.is_action_pressed(&"move_up"):
		want = Vector2i.UP
	elif Input.is_action_pressed(&"move_down"):
		want = Vector2i.DOWN
	elif Input.is_action_just_pressed(&"jump") and _can_jump():
		_begin_jump()
		return

	if want != Vector2i.ZERO:
		_step(want)


func _step(dir: Vector2i) -> void:
	if dir == Vector2i.UP or dir == Vector2i.DOWN:
		_climb(dir)
		return
	# Walking into a wall turns the chef round rather than stopping him, which is
	# what lets you hold a direction and pace back and forth over a part.
	if board.blocks_player(cell + dir):
		facing = -facing
		return
	facing = dir.x
	begin_step(cell + dir, Cfg.STEP_WALK)


func _climb(dir: Vector2i) -> void:
	var target := cell + dir
	# Rows are only connected by a ladder, and the chef has to be able to stand at
	# the far end of the climb - otherwise he can climb halfway up and be stuck.
	if not (board.is_ladder(cell) or board.is_ladder(target)):
		return
	if board.blocks_player(target):
		return
	if not (board.is_ladder(target) or board.floor_below(target)):
		return
	state = St.CLIMB
	begin_step(target, Cfg.STEP_CLIMB)


func _can_jump() -> bool:
	if state == St.CLIMB:
		return false
	return not board.blocks_player(cell + Vector2i(facing, 0))


func _begin_jump() -> void:
	state = St.JUMP
	begin_step(cell + Vector2i(facing, 0), JUMP_DUR)


func _start_fall() -> void:
	if _supported():
		state = St.WALK
		return
	state = St.FALL
	begin_step(cell + Vector2i.DOWN, Cfg.STEP_FALL)


## Whether the chef can stay put in the cell he is in. A ladder holds him up just
## as well as a ledge does: without this he climbs one rung and immediately falls
## back off, and can never get anywhere.
func _supported() -> bool:
	return board.is_ladder(cell) or board.floor_below(cell)


# --- Arriving --------------------------------------------------------------


func _arrived() -> void:
	if state == St.JUMP:
		state = St.WALK
	_track_crossing()
	if not _supported():
		state = St.FALL
		return
	if state == St.FALL or state == St.CLIMB:
		state = St.WALK
	queue_redraw()


## Notices which cells of which ingredient the chef has stood in, and pushes the
## part once he has been all the way across it. Crossing is measured in cells
## covered rather than distance travelled, so pacing back and forth over a wide
## part still works, and a part is never pushed by a brush against its edge.
func _track_crossing() -> void:
	var here := board.ingredient_at(cell)
	if here != _cross:
		_close_crossing()
		_cross = here
	if _cross != null:
		_covered[cell] = true


func _close_crossing() -> void:
	if _cross != null and _covered.size() >= _cross.cells.size():
		crossed.emit(_cross)
		_cross.knock()
	_cross = null
	_covered.clear()


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
	var bob := 0
	if moving and state != St.JUMP:
		bob = -1 if sin(step_phase() * PI) > 0.0 else 0
	var climbing := state == St.CLIMB
	if climbing:
		facing = 0

	# Legs, then torso, then head and hat. Drawn from the feet up so the jump
	# arc reads as a hop rather than a resize.
	draw_rect(Rect2(-5, 2 + bob, 4, 6), Cfg.PLAYER_COOK_PANTS)
	draw_rect(Rect2(1, 2 + bob, 4, 6), Cfg.PLAYER_COOK_PANTS)
	draw_rect(Rect2(-6, -1 + bob, 12, 5), Cfg.PLAYER_COOK_SHIRT)
	draw_rect(Rect2(-5, 4 + bob, 10, 2), Cfg.COL_OUTLINE)
	draw_rect(Rect2(-4, -6 + bob, 8, 6), Cfg.PLAYER_COOK_SKIN)
	# Chef's hat: a band and a puff on top.
	draw_rect(Rect2(-5, -7 + bob, 10, 3), Cfg.PLAYER_COOK_HAT)
	draw_rect(Rect2(-6, -10 + bob, 12, 4), Cfg.PLAYER_COOK_HAT)
	draw_rect(Rect2(-6, -10 + bob, 12, 4), Cfg.COL_OUTLINE, false, 1.0)
	# Eyes, which only show when he is facing a direction.
	if facing != 0:
		var ex := 2 * signi(facing)
		draw_rect(Rect2(ex - 1, -5 + bob, 1, 2), Cfg.COL_OUTLINE)
		draw_rect(Rect2(ex + 1, -5 + bob, 1, 2), Cfg.COL_OUTLINE)

	# A pepper dose shows as a shimmer, so a ghosted chef is never a mystery.
	if ghost():
		draw_rect(Rect2(-7, -11 + bob, 14, 14), Cfg.COL_PEPPER, false, 1.0)
	queue_redraw()
