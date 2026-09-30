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

var facing := 1
var state: St = St.WALK
## Seasoning charges in the jar, and how long the current spray is drawn for.
var pepper_left := 0
var spray_time := 0.0

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
	if spray_time > 0.0:
		spray_time = maxf(spray_time - delta, 0.0)
	_drive()
	var done := tick_step(delta)
	# The hop arc is applied on top of the linear cell-to-cell interpolation, so
	# the jump still ends exactly on a grid cell.
	if state == St.JUMP and moving:
		position.y -= sin(PI * step_phase()) * JUMP_LIFT
	if done:
		_arrived()


## How long a thrown dose is drawn for, so the spray is visible on the way out.
const SPRAY_TIME := 0.18
## How far a dose reaches in front of the chef, in cells: about a character and a
## half. Close enough to zap the nasty he is being chased by, short enough that he
## has to commit to a direction rather than paint the whole floor.
const SPRAY_REACH := 1.5


## Takes one charge out of the jar for a spray the chef is about to throw.
## Returns false when the jar is empty, which the caller reports rather than
## silently doing nothing.
func spend_pepper() -> bool:
	if pepper_left <= 0:
		return false
	pepper_left -= 1
	spray_time = SPRAY_TIME
	return true


## The box a thrown dose covers: out in front of the chef, from his own edge to
## SPRAY_REACH cells away, one cell deep vertically. World pixels, like every
## other body box in the game, so it is compared against the nasties' own boxes.
func spray_rect() -> Rect2:
	var reach := Cfg.TILE * SPRAY_REACH
	var h := Cfg.TILE * 0.6
	var from_x := position.x + float(facing) * Cfg.TILE * 0.4
	var to_x := position.x + float(facing) * reach
	return Rect2(minf(from_x, to_x), position.y - h * 0.5, absf(to_x - from_x), h)


func add_pepper(charges: int = 1) -> void:
	pepper_left += charges


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
	# A jump is a push off a platform, not a leap off a ladder rung. Both halves
	# matter: a ladder cell is not a launch pad even when there is a ledge below
	# it, and a chef with nothing under him is already falling.
	if board.is_ladder(cell) or not board.floor_below(cell):
		return false
	return _jump_landing() != Vector2i.ZERO


## Where a jump puts the chef down. The hop clears the cell in front of him rather
## than landing in it, which is the whole point: the chef used to hop exactly one
## cell, so a nasty in the next cell caught him as he came down and the jump could
## never get him over anything. Carrying the hop to the far side of that cell is
## what makes it a dodge. A wall right in front cancels it; a wall on the far side
## shortens it rather than cancelling it, so a jump beside a wall is still a jump.
func _jump_landing() -> Vector2i:
	var one := cell + Vector2i(facing, 0)
	if board.blocks_player(one):
		return Vector2i.ZERO
	var two := cell + Vector2i(facing * 2, 0)
	if not board.blocks_player(two):
		return two
	return one


func _begin_jump() -> void:
	var landing := _jump_landing()
	# The longer hop is given more time, but not twice as much, so clearing a
	# nasty reads as one quick push-off rather than a slow drift across the floor.
	var dist := absi(landing.x - cell.x)
	state = St.JUMP
	begin_step(landing, JUMP_DUR * (1.0 + 0.4 * float(dist - 1)))


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
		var target := _cross
		_cross = null
		_covered.clear()
		crossed.emit(target)
		return
	_cross = null
	_covered.clear()


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
	draw_chef()
	if spray_time > 0.0:
		_draw_spray()
	queue_redraw()


## The thrown dose, drawn as a puff of specks thrown out in front of the chef and
## thinning as it fades, so the player can see how far a shot reached.
func _draw_spray() -> void:
	var rect := spray_rect()
	var left := rect.position.x
	var f := spray_time / SPRAY_TIME
	for i in 7:
		var t := (float(i) + 0.5) / 7.0
		var x := left + rect.size.x * t
		var spread := sin(t * PI) * 4.0
		var y := position.y + sin(float(i) * 2.1) * spread
		draw_circle(Vector2(x, y), 1.5 + t, Color(Cfg.COL_PEPPER, f * (1.0 - t * 0.5)))


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
