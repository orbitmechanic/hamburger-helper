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
## Peak of a running hop, in pixels: a long, low arc that clears a nasty without
## carrying the chef any real height.
const JUMP_LIFT := 13.0
## A stopped hop is a reach rather than a dodge, so it arcs twice as high.
const JUMP_LIFT_STAND := JUMP_LIFT * 2.0
## How far each kind of hop travels, in cells. A stopped hop covers two; adding a
## stride's momentum carries it one cell further.
const JUMP_STAND_CELLS := 2
const JUMP_RUN_CELLS := 3

var facing := 1
var state: St = St.WALK
## Seasoning charges in the jar, and how long the current spray is drawn for.
var pepper_left := 0
var spray_time := 0.0
## Peak of the hop in flight, so a running dodge and a standing reach can arc
## differently.
var _jump_lift := JUMP_LIFT

## The ingredient currently being walked over, and which of its cells have been
## covered. A part is only pushed when every one of them has been.
var _cross: Ingredient = null
var _covered := {}
## Free-running clock for the animations that are not tied to a step, so standing
## still still breathes.
var _anim := 0.0


## A fixed pose the level has put the chef in, or -1 for none. See `set_pose`.
var pose_anim := -1

## How far through a posed animation the chef is, 0 to 1. The level owns this clock
## for the poses it sets, because the chef is not processing while they play.
var pose_progress := 1.0

## Which foot the chef is on, counted in walk steps. Only used to decide whether a
## step makes a noise, and reset by anything that is not walking - so a run starts on
## the same foot whatever he was doing before it.
var _step_foot := 0

## Whether the chef is coming down under his parachute, and the two things the
## descent needs to know: where he started and where he lands.
var dropping := false
var _drop_from := Vector2.ZERO
var _drop_at := Vector2i.ZERO
var _drop_t := 0.0
var _drop_dur := 1.0


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
	# A chef who is standing somewhere is playing, so whatever the level had him
	# doing on the way to that spot is over. Without this a respawn would put him
	# back on the board still wearing the pose he went down in.
	clear_pose()
	# Landing is a normal arrival, so a chef who was coming down under a parachute
	# is not left holding the canopy over a board he is already standing on.
	dropping = false


## Sends the chef in over the top of the screen under his parachute, to land on
## `at` after `dur` seconds.
##
## He starts at the top of the screen rather than at the top of the board: the
## canopy is drawn in the cell above his, so putting the canopy flush with the top
## edge is what puts the whole rig - canopy above, chef hanging below it - on screen
## at the moment the level card comes up. The cell he is logically in stays the
## landing cell the whole way down, so a chef drifting across the board is not
## caught by a nasty he is nowhere near, and the card is over the board he is
## passing anyway.
func begin_drop(at: Vector2i, dur: float) -> void:
	_drop_at = at
	_drop_dur = maxf(dur, 0.001)
	_drop_t = 0.0
	dropping = true
	_drop_from = Vector2(Cfg.cell_to_pixel(at).x, Cfg.TILE * 2.0)
	cell = at
	position = _drop_from
	queue_redraw()


## Where a descending chef is, 0 to 1 through the drop.
func drop_progress() -> float:
	return clampf(_drop_t / _drop_dur, 0.0, 1.0)


## Land a descending chef now, wherever he has got to.
##
## The level calls this when the phase moves on. The drop and the level card run
## off the same duration, so in practice they finish together, but two clocks that
## agree only to within a frame are two clocks, and a frame where they do not is a
## chef playing under a parachute.
func finish_drop() -> void:
	if dropping:
		place(_drop_at)


## Advances the descent and moves the chef along it, landing him on the spawn when
## the drop runs out. Driven by the level rather than the chef's own clock, because
## the chef is not processing while he is coming in - a falling chef answering the
## keyboard is a falling chef who walks off the parachute.
func drop_step(delta: float) -> void:
	if not dropping:
		return
	_drop_t = minf(_drop_t + delta, _drop_dur)
	var to := Cfg.cell_to_pixel(_drop_at)
	# A gentle ease-out, so he arrives rather than stops. A straight line is fine
	# too, but the landing is the one moment the player is watching.
	var t := drop_progress()
	position = _drop_from.lerp(to, 1.0 - pow(1.0 - t, 2.0))
	if _drop_t >= _drop_dur:
		place(_drop_at)


func _process(delta: float) -> void:
	_anim += delta
	if spray_time > 0.0:
		spray_time = maxf(spray_time - delta, 0.0)
	queue_redraw()
	_drive()
	var done := tick_step(delta)
	# The hop arc is applied on top of the linear cell-to-cell interpolation, so
	# the jump still ends exactly on a grid cell.
	if state == St.JUMP and moving:
		position.y -= sin(PI * step_phase()) * _jump_lift
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
	var want := Vector2i.ZERO
	if Input.is_action_pressed(&"move_left"):
		want = Vector2i.LEFT
	elif Input.is_action_pressed(&"move_right"):
		want = Vector2i.RIGHT
	elif Input.is_action_pressed(&"move_up"):
		want = Vector2i.UP
	elif Input.is_action_pressed(&"move_down"):
		want = Vector2i.DOWN

	# The jump key is read outside the direction chain and before the "busy"
	# bail-out, so holding a direction can no longer swallow it - the chef used to
	# have to stop dead before he could jump at all. Where the hop goes is the
	# player's choice: nothing held reaches straight up, a direction held hops that
	# way, and hopping mid-stride carries a cell further.
	if Input.is_action_just_pressed(&"jump") and _can_jump(want, moving):
		_begin_jump(want, moving)
		return

	if moving:
		return
	if state == St.FALL:
		_start_fall()
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


func _can_jump(want: Vector2i, running: bool) -> bool:
	# Only from a standstill or a stride on solid ground: not already mid-hop, not
	# falling, and never off a ladder rung or out of thin air.
	if state != St.WALK:
		return false
	if board.is_ladder(cell) or not board.floor_below(cell):
		return false
	return _jump_landing(want, running) != Vector2i.ZERO


## Where a jump puts the chef down.
##
## The direction is the player's. Nothing held is a reach straight up, to get a
## hand to whatever sits on a plate on the storey above; a direction held is a hop
## that way, and the hop clears the cell in front rather than landing in it, which
## is what turns it into a dodge - the chef used to land in that cell, so a nasty
## standing there caught him as he came down. A hop taken mid-stride covers one cell
## more. A wall shortens the hop; a wall right in front cancels it.
func _jump_landing(want: Vector2i, running: bool) -> Vector2i:
	if want.x == 0:
		var up := cell + Vector2i.UP
		if not Cfg.in_grid(up) or board.blocks_player(up):
			return Vector2i.ZERO
		return up
	var reach := JUMP_RUN_CELLS if running else JUMP_STAND_CELLS
	for i in range(1, reach + 1):
		var target := cell + Vector2i(want.x * i, 0)
		if board.blocks_player(target):
			return cell + Vector2i(want.x * (i - 1), 0) if i > 1 else Vector2i.ZERO
	return cell + Vector2i(want.x * reach, 0)


func _begin_jump(want: Vector2i, running: bool) -> void:
	var landing := _jump_landing(want, running)
	if landing == Vector2i.ZERO:
		return
	if want.x != 0:
		facing = want.x
	# A hop from a stop is a real leap and arcs twice as high; a hop taken
	# mid-stride is a long low skip. Nothing catches the chef while he is in the
	# air, so the height is free to read as effort.
	_jump_lift = JUMP_LIFT if running else JUMP_LIFT_STAND
	state = St.JUMP
	Sfx.play("jump")
	# The longer hop is given more time, but not twice as much, so clearing a
	# nasty reads as one quick push-off rather than a slow drift across the floor.
	# A reach straight up is one cell, so it is the quickest hop of the three.
	var dist := absi(landing.x - cell.x)
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
	# A hop answers itself with a landing, but arriving in a cell by any other means
	# - finishing a fall or a climb - is silent, because the drop and the climb
	# already made their own noise. Keyed off the state on arrival rather than off
	# every arrival so a step onto the same cell twice cannot double it.
	if state == St.JUMP:
		Sfx.play("land")
		_step_foot = 0
		state = St.WALK
	elif state == St.WALK:
		# Every *other* step, alternating between the two effects. One sound per step
		# would be eight a second at STEP_WALK, which is a buzz; every other one is
		# four, which is a footfall - each foot touching down once per two cells. The
		# pair is alternated as well as halved so a run does not sound like it is
		# keeping time with something.
		_step_foot += 1
		if _step_foot % 2 == 0:
			Sfx.play("step" if _step_foot % 4 == 0 else "step_soft")
	_track_crossing()
	if not _supported():
		state = St.FALL
		return
	if state == St.FALL or state == St.CLIMB:
		_step_foot = 0
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


## One redraw a frame is asked for from _process rather than from here. Asking for
## a redraw from inside _draw does not schedule another one, so the chef - and
## every other actor that used the same pattern - froze on the first frame it was
## ever drawn and never animated again.
func _draw() -> void:
	draw_chef()
	if spray_time > 0.0:
		_draw_spray()


## The thrown dose, drawn as a puff of specks thrown out in front of the chef and
## thinning as it fades, so the player can see how far a shot reached.
##
## spray_rect() is in world pixels, because it doubles as the box the nasties are
## tested against. Drawing happens in the chef's own space, so the rect is shifted
## back by the chef's position. Drawn straight it put the whole puff a position
## lower again and off the bottom of the screen, which is why the punch played but
## no dose was ever visible.
func _draw_spray() -> void:
	var rect := spray_rect()
	var left := rect.position.x - position.x
	var mid := rect.position.y - position.y
	var f := spray_time / SPRAY_TIME
	for i in 7:
		var t := (float(i) + 0.5) / 7.0
		var x := left + rect.size.x * t
		var spread := sin(t * PI) * 4.0
		var y := mid + sin(float(i) * 2.1) * spread
		var c := Color(Cfg.COL_PEPPER.r, Cfg.COL_PEPPER.g, Cfg.COL_PEPPER.b, f * (1.0 - t * 0.5))
		draw_circle(Vector2(x, y), 1.5 + t, c)


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
	if dropping:
		_draw_parachute(sheet)


## The canopy, on the cell above the chef's while he is coming in.
##
## Drawn straight rather than mirrored: a canopy is symmetric, so flipping it would
## be inventing a difference. Its strings run to the bottom of its own cell, which
## is the top of the chef's, so they read as hanging from it.
func _draw_parachute(sheet: Texture2D) -> void:
	draw_texture_rect_region(sheet,
			Rect2(Sheet.offset() - Vector2(0.0, Cfg.TILE), Vector2(Sheet.CELL)),
			Sheet.region(Sheet.Anim.PARACHUTE, 0))


## Which animation the chef is in.
##
## A pose set by the level outranks everything, because the moments the level needs
## one are the ones where the chef is not driving himself: he cannot be spraying
## seasoning on the way in through a parachute or celebrating a cleared level. The
## spray is second, and reads as a punch for as long as the puff is in the air.
func anim_state() -> int:
	if dropping:
		# Hanging. The parachute is its own drawing a cell above him rather than a
		# pose he is in, so what he is showing here is a chef doing nothing, which
		# is IDLE: the idle breathing is the only thing that reads as a person
		# waiting rather than a person switched off.
		return Sheet.Anim.IDLE
	if pose_anim >= 0:
		return pose_anim
	if spray_time > 0.0:
		return Sheet.Anim.PUNCH
	match state:
		St.CLIMB:
			return Sheet.Anim.CLIMB
		St.JUMP, St.FALL:
			return Sheet.Anim.JUMP
		_:
			return Sheet.Anim.WALK if moving else Sheet.Anim.IDLE


## Frame within the current animation.
##
## The stepping animations are played off the step, so the feet keep pace with the
## movement, and the jump comes along for it: the hop is a single step, so a jump
## plays its tuck on the way up and its reach on the way down, which is a better
## read than a loop of four frames that keeps playing after he has landed. The spray
## plays the punch out over the puff, and a pose plays off the clock the level
## hands it.
func anim_frame(anim: int) -> int:
	if pose_anim >= 0 and anim == pose_anim:
		return Sheet.frame_at_phase(anim, pose_progress)
	if anim == Sheet.Anim.PUNCH:
		return Sheet.frame_at_phase(anim, 1.0 - spray_time / SPRAY_TIME)
	if anim == Sheet.Anim.WALK or anim == Sheet.Anim.CLIMB or anim == Sheet.Anim.JUMP:
		# A fall is one cell and about four frames of real time, so playing a
		# four-frame arc across it would strobe rather than read. A fall holds the
		# reach: the chef is dropping, not hopping.
		if anim == Sheet.Anim.JUMP and state == St.FALL:
			return Sheet.frame_at_phase(anim, 1.0)
		return Sheet.frame_at_phase(anim, step_phase())
	return Sheet.frame_of(anim, _anim)


## Put the chef in a fixed pose instead of what he is doing, for the moments the
## level rather than the player is in charge. `progress` runs 0 to 1 through an
## animation and is ignored for a single frame.
func set_pose(anim: int, progress: float = 1.0) -> void:
	pose_anim = anim
	pose_progress = progress
	queue_redraw()


## Hand the chef back to himself.
func clear_pose() -> void:
	pose_anim = -1
	pose_progress = 1.0
	queue_redraw()
