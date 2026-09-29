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
## Free-running clock for the animations that are not tied to a step, so standing
## still still breathes.
var _anim := 0.0


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
	_anim += delta
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


## Throws a pepper dose. The caller is the game, on the pepper key: the chef
## shimmers for PEPPER_TIME and the first nasty he touches in that window is
## stunned, so spending a charge is always the player's decision.
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
	draw_chef()
	# A pepper dose shows as a shimmer, so a ghosted chef is never a mystery.
	if ghost():
		draw_rect(Rect2(-7, -11, 14, 14), Cfg.COL_PEPPER, false, 1.0)
	queue_redraw()


## Blits the current frame of the chef's sheet, mirrored to face the way he is
## going. The sheet only ever holds a right-facing chef, so there is one set of
## eyes to keep in step with the walk rather than two that can disagree.
func draw_chef() -> void:
	var anim := anim_state()
	var sheet := Sheet.texture(Sheet.CHEF)
	if sheet == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing, 1.0))
	draw_texture_rect_region(sheet, Rect2(Sheet.offset(), Vector2(Sheet.CELL)),
			Sheet.region(anim, anim_frame(anim)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Which animation the chef is in. Climbing is its own animation with no eyes in
## it, which is why the old code no longer has to fake a facing of zero here -
## and why `facing` is left alone, since movement reads it too.
func anim_state() -> int:
	match state:
		St.CLIMB:
			return Sheet.Anim.CLIMB
		St.JUMP, St.FALL:
			return Sheet.Anim.JUMP
		_:
			return Sheet.Anim.WALK if moving else Sheet.Anim.IDLE


## Frame within the current animation. Walking and climbing are played off the
## step so the feet keep pace with the movement; the rest run on the clock.
func anim_frame(anim: int) -> int:
	if anim == Sheet.Anim.WALK or anim == Sheet.Anim.CLIMB:
		return Sheet.frame_at_phase(anim, step_phase())
	return Sheet.frame_of(anim, _anim)
