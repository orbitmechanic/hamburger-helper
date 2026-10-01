class_name Enemy
extends Mover
## A nasty. Walks the ledges, works its way towards the chef on ladders, and can be
## avoided three ways: outrun it, drop something on it, or spend pepper.
##
## The three kinds differ only in how they travel and how they are worth points,
## which is how the original plays - a hot dog is the lumbering one you can run
## from, a pickle is quick and drops, an egg climbs.

## Emitted with the kind's score when falling food flattens this nasty.
signal squashed(points: int)
signal returned_to_play

enum Kind { HOTDOG, EGG, PICKLE }
enum St { WALK, CLIMB, FALL, RIDE, STUN, SQUASH }

## Seconds per cell for a nasty: half the pace it had, and a third of the chef's.
## A nasty you cannot walk away from turns a level into a waiting game, and waiting
## is the one thing this has to be about avoiding. Climbing is slowed to match, or
## a nasty would be quick on a ladder and slow on the floor, which reads as two
## different characters. Falling is left alone, because a part of the point of a
## fall is that it is quick.
const STEP := 0.44
const STEP_CLIMB := Cfg.STEP_CLIMB * 2.0
const STEP_FALL := 0.07
## Chance per step of turning around, so packs do not march in lockstep.
const TURN_CHANCE := 0.04
## How close the chef has to be, in cells, before a nasty will abandon its storey and
## make for his row.
##
## Without a limit, every nasty walks to wherever the chef is as soon as he moves, so
## all three of them end up on the one row he is on - which, because he has to climb
## down to the plates, is more often than not the ground corridor, a single cell wide
## with no way past anyone on it and all three of them heading for it. They are then
## not a pack spread over the building, they are a queue in the one passage the chef
## has to use. With a limit, a nasty presses the chef where he is working but keeps its
## own storey when he is only passing through, which is what the original does: the
## threat is local, and outrunning it is a real option.
const CHASE_RANGE := 6
const STUN_TIME := 4.0
## A squashed nasty lies still for this long, then reappears on the ledge it
## started on. Long enough to read as "flattened, not gone" and to give the chef
## a real window to work while it is out, rather than blinking back almost at
## once.
const SQUASH_TIME := 5.0
## A part with a nasty on top drops two levels instead of one. Worth a lot.
const RIDER_BONUS := 2

var kind: Kind = Kind.HOTDOG
var state: St = St.WALK
var facing := -1
var player: Player

## The part this nasty is riding down, if any. Null unless state is RIDE.
var ride: Ingredient = null
var _timer := 0.0
var _anim := 0.0
var _home := Vector2i.ZERO

## The ledge this nasty starts on and is sent back to when the chef is caught.
## Read-only: a nasty's home is where it was put, and nothing should move it.
var home_cell: Vector2i:
	get:
		return _home


func setup(p_board: Board, start_cell: Vector2i, p_kind: Kind, p_player: Player) -> void:
	board = p_board
	kind = p_kind
	player = p_player
	_home = start_cell
	place(start_cell)
	facing = 1 if randf() < 0.5 else -1
	z_index = 8
	queue_redraw()


func points() -> int:
	match kind:
		Kind.EGG:
			return 200
		Kind.PICKLE:
			return 300
		_:
			return 100


## Whether this nasty is standing on a given part and would be carried by it.
## The part is underfoot, so it fills the cell below him rather than his own, and
## that is what it has to be matched against.
func riding(ing: Ingredient) -> bool:
	if ing == null or state in [St.SQUASH, St.RIDE, St.FALL]:
		return false
	for c in ing.cells:
		if c == cell + Vector2i.DOWN:
			return true
	return false


## Whether a part is currently falling through this nasty, either over his head or
## through the cell he is standing in.
##
## Both cells count because a part either lands on him or passes through where he is
## standing, and both flatten him. A rider is excluded by the caller: the part is
## under him rather than through him, and _tick_ride() flattens him when it lands.
func _under_falling_food() -> bool:
	for n in get_tree().get_nodes_in_group(&"ingredients"):
		var ing := n as Ingredient
		if ing == null or not is_instance_valid(ing) or not ing.falling:
			continue
		var swept := ing.swept_cells()
		if swept.has(cell) or swept.has(cell + Vector2i.DOWN):
			return true
	return false


func _process(delta: float) -> void:
	_anim += delta

	# What a falling part does to this nasty, checked before the state machine
	# rather than after it. It used to sit at the bottom, past the early returns, so a
	# stunned or squashed nasty never reached it and a part landing on a stunned one
	# went straight through. It also used to ask `ingredient_at()` about this cell and
	# the one below, which cannot work: a part claims the row it is landing in the
	# instant it is knocked and the fall after that is a tween, so every row it passes
	# on the way down is in no cell at all. A nasty on a ladder two rows into a four
	# row drop was therefore in nothing the check could see, and lived.
	#
	# The part is asked for the band it is sweeping instead, and this nasty for
	# whether it is in it. That is the whole rule, and it makes a ladder irrelevant:
	# a ladder is a place to be high up, not a place to be out of the way.
	if state != St.SQUASH and state != St.RIDE and _under_falling_food():
		_squash()
		return

	match state:
		St.SQUASH:
			_tick_timer(delta)
			return
		St.STUN:
			_tick_timer(delta)
			return
		St.RIDE:
			_tick_ride(delta)
			return
		_:
			pass

	var done := tick_step(delta)

	if done:
		_arrived()
		_drive()
	elif not moving:
		_drive()


## Runs the stun and squash clocks down. A squashed nasty goes back to the ledge
## it started on; a stunned one just starts walking again where it stands.
func _tick_timer(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	if state == St.SQUASH:
		revive()
		return
	state = St.WALK
	_timer = 0.0
	queue_redraw()
	returned_to_play.emit()


func _tick_ride(delta: float) -> void:
	if ride == null or not is_instance_valid(ride):
		# The part boarded a burger and left the maze, so it took the nasty with it.
		ride = null
		_squash()
		return
	# Ride the part down: sit on whichever of its cells is nearest.
	var best := ride.cells[0]
	for c in ride.cells:
		if absi(c.x - cell.x) < absi(best.x - cell.x):
			best = c
	if ride.falling:
		place(best)
		return
	# The part has landed, and it took him down with it, so it has crushed him.
	# The ride itself was already paid for when the part was knocked
	# (carried_rider); the squash is what takes the nasty out of play.
	ride = null
	_squash()


## Picks this nasty up onto a part that is on its way down.
func attach(ing: Ingredient) -> void:
	ride = ing
	state = St.RIDE
	queue_redraw()


func _arrived() -> void:
	if state == St.FALL and board.floor_below(cell):
		state = St.WALK
	queue_redraw()


# --- Movement --------------------------------------------------------------


func _drive() -> void:
	if moving:
		return
	if state == St.FALL:
		_begin_fall()
		return

	# Pepper and falling food are the two ways out of a chase, and both are
	# checked before thinking about where to walk.
	if _chase_target() != cell.y:
		var col := _ladder_column_toward(_chase_target())
		if col != cell.x:
			# A ladder worth using has a rung directly above or below this cell;
			# otherwise walk along until one is underfoot.
			if not _step_toward(col):
				_patrol()
			return
		_climb_toward(_chase_target())
		return
	_patrol()


func _chase_target() -> int:
	if player == null or player.state == Player.St.JUMP:
		return cell.y
	# Further out, walking to the chef would carry the nasty off its own storey and
	# into the corridor for no reason. "Pawn the storey" is the same answer as
	# "patrol", so this just stays where it is.
	if absi(player.cell.x - cell.x) + absi(player.cell.y - cell.y) > CHASE_RANGE:
		return cell.y
	return player.cell.y


## Whether there is a rung above or below this cell to change rows on.
func _on_ladder() -> bool:
	return board.is_ladder(cell + Vector2i.UP) or board.is_ladder(cell + Vector2i.DOWN)


func _climb_toward(target_row: int) -> void:
	var dir := Vector2i.UP if target_row < cell.y else Vector2i.DOWN
	if not board.is_ladder(cell + dir):
		# At the end of the ladder. Stepping off the top is the only way a nasty
		# on a ladder ever gets anywhere: `_patrol()` would send it back to walking
		# the row below, which on a level whose top row is a ledge either means a
		# solid block it cannot enter (it froze there until the level ended) or a
		# four-cell fall to the bottom. Climbing out costs nothing and reads as the
		# nasty topping the ladder.
		if dir == Vector2i.UP and board.is_ladder(cell) and can_enter(cell + dir):
			state = St.CLIMB
			begin_step(cell + dir, STEP_CLIMB)
			return
		_patrol()
		return
	state = St.CLIMB
	begin_step(cell + dir, STEP_CLIMB)


## Nearest column that has a rung on the correct side of this row.
func _ladder_column_toward(target_row: int) -> int:
	var probe := Vector2i.UP if target_row < cell.y else Vector2i.DOWN
	var best := cell.x
	var best_dist := 1 << 30
	for x in Cfg.GRID_W:
		if not board.is_ladder(Vector2i(x, cell.y) + probe):
			continue
		var d := absi(x - cell.x)
		if d < best_dist:
			best = x
			best_dist = d
	return best


func _step_toward(col: int) -> bool:
	if col == cell.x:
		return true
	var dir := signi(col - cell.x)
	var target := cell + Vector2i(dir, 0)
	if board.blocks_player(target):
		return false
	facing = dir
	begin_step(target, STEP)
	return true


func _patrol() -> void:
	if randf() < TURN_CHANCE:
		facing = -facing
	# Turn at a wall.
	if board.blocks_player(cell + Vector2i(facing, 0)):
		facing = -facing
		return
	# Turn or drop at a ledge. A hot dog will not step off the edge; the quicker
	# ones do, which is what makes a pickle worth more than a hot dog.
	if not board.floor_below(cell + Vector2i(facing, 0)):
		if kind == Kind.HOTDOG:
			facing = -facing
			return
		_begin_fall()
		return
	state = St.WALK
	begin_step(cell + Vector2i(facing, 0), STEP)


func _begin_fall() -> void:
	if board.floor_below(cell):
		state = St.WALK
		return
	state = St.FALL
	begin_step(cell + Vector2i.DOWN, STEP_FALL)


func _squash() -> void:
	state = St.SQUASH
	_timer = SQUASH_TIME
	moving = false
	squashed.emit(points())
	queue_redraw()


## Pepper: the nasty stops moving and stops being dangerous until the dose runs
## out. It does not leave the board, it just stops being a threat.
func stun(seconds: float = STUN_TIME) -> void:
	if state == St.SQUASH:
		return
	state = St.STUN
	_timer = seconds
	ride = null
	moving = false
	queue_redraw()


## Back to the ledge it started on, as in the original when a squash wears off.
func revive() -> void:
	state = St.WALK
	ride = null
	_timer = 0.0
	place(_home)
	queue_redraw()
	returned_to_play.emit()


## Sends this nasty back to its start and puts it back into play, for when the
## chef is caught. The original resets every enemy on a death, which is what stops
## a nasty that has parked on the chef's spawn from eating all six chefs in a
## row with no chance to get away.
func reset_for_respawn() -> void:
	state = St.WALK
	ride = null
	_timer = 0.0
	moving = false
	place(_home)
	queue_redraw()


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
	var sheet := Sheet.texture(sheet_name())
	if sheet == null:
		queue_redraw()
		return
	# A squashed nasty blinks for the whole of its five seconds so the player can
	# see it is out of play and about to come back, rather than reading the
	# flattened sprite as a nasty that has simply stopped.
	var blink := state == St.SQUASH and fposmod(_timer, 0.6) < 0.35
	var anim := anim_state()
	draw_set_transform(Vector2(visual_offset().x, 0.0), 0.0, Vector2(facing, 1.0))
	var mod := Color(1, 1, 1, 0.35) if blink else Color.WHITE
	draw_texture_rect_region(sheet, Rect2(Sheet.offset(), Vector2(Sheet.CELL)),
			Sheet.region(anim, anim_frame(anim)), mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	queue_redraw()


## A nasty being carried rides up on the part it is standing on, which is a
## couple of pixels above the cell it is held in. Reported through visual_offset()
## so the contact box is lifted with the picture rather than left behind under the
## plate.
func visual_offset() -> Vector2:
	return Vector2(0, -2) if state == St.RIDE else Vector2.ZERO


## Which sheet this nasty draws from. One sheet per character, so this is the only
## thing that tells the three of them apart at draw time - the body colour is baked
## into the art rather than tinted on, which is what lets a sheet be replaced
## wholesale with different-looking art.
func sheet_name() -> String:
	match kind:
		Kind.EGG:
			return Sheet.EGG
		Kind.PICKLE:
			return Sheet.PICKLE
		_:
			return Sheet.HOTDOG


## Which animation the nasty is in.
func anim_state() -> int:
	match state:
		St.SQUASH:
			return Sheet.Anim.SQUASH
		St.STUN:
			return Sheet.Anim.STUN
		St.CLIMB:
			return Sheet.Anim.CLIMB
		St.FALL, St.RIDE:
			return Sheet.Anim.JUMP
		_:
			return Sheet.Anim.WALK


## Frame within the current animation. The walk is played off the step so the feet
## do not slide, since a nasty walks one cell at a time like everything else.
func anim_frame(anim: int) -> int:
	if anim == Sheet.Anim.WALK and moving:
		return Sheet.frame_at_phase(anim, step_phase())
	return Sheet.frame_of(anim, _anim)
