class_name Player
extends Mover
## The chef: walks the counters, climbs ladders, runs along surfaces when he
## presses into one, and carries a tray of ingredients overhead.
##
## Note that resting ingredients never block him - he walks over loose food and
## picks it up, which is why picking up is a deliberate action rather than
## automatic.

signal served(points: int, cell: Vector2i)
signal died
signal tray_changed
signal want_ingredient(cell: Vector2i, kind: Food.Kind)
signal want_salt(cell: Vector2i, facing: int)

enum St { NORMAL, CLIMB, FALL, DASH, HURT, DEAD }

## How many ingredients fit on the tray at once.
const TRAY_MAX := 3
## Sentinel tray value for a salt packet rather than food.
const SALT := -1
## Cells travelled by one counter run.
const DASH_STEPS := 7
## Seconds of invulnerability after being hit.
const HURT_TIME := 1.6
## Seconds after respawning during which the chef cannot be caught again.
## The spawn pad is where the chef died, so without this the enemy that landed
## the hit is still standing there and the run ends without any input at all.
const GRACE_TIME := 1.2
## Seconds the death animation holds before respawning.
const DEAD_TIME := 0.9
## Minimum gap between two items from the same dispenser.
const DISPENSER_COOLDOWN := 0.3

var state: St = St.NORMAL
## Foods and salt packets on the tray; index 0 is the bottom of the pile.
var tray: Array = []
var facing := 1

var _dash_left := 0
var _disp_cd := 0.0
var _hurt_t := 0.0
var _dead_t := 0.0
var _grace_t := 0.0
var _anim_t := 0.0
var _steer_used := 0


func _ready() -> void:
	z_index = 10


func _process(delta: float) -> void:
	_anim_t += delta
	_disp_cd = maxf(0.0, _disp_cd - delta)
	_grace_t = maxf(0.0, _grace_t - delta)

	if state == St.DEAD:
		_dead_t -= delta
		if _dead_t <= 0.0:
			respawn()
		queue_redraw()
		return

	if state == St.HURT:
		_hurt_t -= delta
		if _hurt_t <= 0.0:
			state = St.NORMAL
		queue_redraw()
		return

	if tick_step(delta):
		_on_step_end()

	_handle_actions()
	if not moving:
		_decide()
	queue_redraw()


func respawn() -> void:
	place(board.player_spawn)
	state = St.NORMAL
	_grace_t = GRACE_TIME
	_dash_left = 0
	_steer_used = 0
	tray.clear()
	tray_changed.emit()
	queue_redraw()


## Called when an enemy catches the chef. Returns true if it actually landed.
func hit() -> bool:
	if state == St.HURT or state == St.DEAD or _grace_t > 0.0:
		return false
	GameState.lose_life()
	_drop_tray()
	state = St.DEAD
	_dead_t = DEAD_TIME
	died.emit()
	return true


# --- Input -----------------------------------------------------------------


func _handle_actions() -> void:
	if Input.is_action_just_pressed(&"jump"):
		_toggle_carry()
	if Input.is_action_just_pressed(&"throw"):
		_throw_tray()


func _decide() -> void:
	var left := Input.is_action_pressed(&"move_left")
	var right := Input.is_action_pressed(&"move_right")
	var up := Input.is_action_pressed(&"move_up")
	var down := Input.is_action_pressed(&"move_down")
	var horiz := 0
	if left and not right:
		horiz = -1
	elif right and not left:
		horiz = 1

	match state:
		St.DASH:
			_step_dash()
		St.FALL:
			_step_fall(horiz)
		St.CLIMB:
			_step_climb(horiz, up, down)
		_:
			_step_normal(horiz, up, down)


func _step_normal(horiz: int, up: bool, down: bool) -> void:
	if up and _try_climb(Vector2i.UP):
		return
	if down and _try_climb(Vector2i.DOWN):
		return
	if horiz == 0:
		return

	facing = horiz
	var target := cell + Vector2i(horiz, 0)
	if not in_bounds(target):
		return
	if board.blocks_player(target):
		if board.is_dispenser(target):
			_bump_dispenser(target)
			return
		# Pressing into a counter starts a run along its top edge, the same
		# way the original lets you cross a gap you would normally fall into.
		state = St.DASH
		_dash_left = DASH_STEPS
		return
	begin_step(target, Cfg.STEP_WALK)


## Walking into a dispenser ejects its next item at the chef's feet. Held over
## long enough it keeps producing, but not faster than this.
func _bump_dispenser(dispenser: Vector2i) -> void:
	if _disp_cd > 0.0:
		return
	var kind := board.bump_dispenser(dispenser)
	if kind < 0:
		return
	_disp_cd = DISPENSER_COOLDOWN
	want_ingredient.emit(cell, kind)


func _step_dash() -> void:
	var target := cell + Vector2i(facing, 0)
	if not in_bounds(target) or board.blocks_player(target):
		state = St.NORMAL
		_dash_left = 0
		return
	begin_step(target, Cfg.STEP_DASH)
	_dash_left -= 1
	if _dash_left <= 0:
		state = St.NORMAL
		_dash_left = 0


func _step_fall(horiz: int) -> void:
	# One nudge of air control per fall, then gravity has you.
	if horiz != 0 and _steer_used < 1:
		var side := cell + Vector2i(horiz, 0)
		if in_bounds(side) and not board.blocks_player(side):
			_steer_used += 1
			begin_step(side, Cfg.STEP_WALK)
			return
	begin_step(cell + Vector2i.DOWN, Cfg.STEP_FALL)


func _step_climb(horiz: int, up: bool, down: bool) -> void:
	if horiz != 0:
		var target := cell + Vector2i(horiz, 0)
		facing = horiz
		if can_stand(target):
			state = St.CLIMB if board.is_ladder(target) else St.NORMAL
			begin_step(target, Cfg.STEP_WALK)
		return
	if up and _try_climb(Vector2i.UP):
		return
	if down and _try_climb(Vector2i.DOWN):
		return


## Attaches to a ladder if there is one at or above/below this cell, and steps
## onto it. Returns false when there is no ladder to take.
func _try_climb(dir: Vector2i) -> bool:
	var on_ladder := board.is_ladder(cell)
	var ahead := cell + dir
	var ladder_ahead := board.is_ladder(ahead)
	if not (on_ladder or ladder_ahead):
		return false

	if dir == Vector2i.UP:
		if ladder_ahead or can_stand(ahead):
			state = St.CLIMB
			_steer_used = 0
			begin_step(ahead, Cfg.STEP_CLIMB)
			return true
		return false

	# Downwards: keep descending a ladder, or step off the bottom onto a floor.
	if ladder_ahead:
		state = St.CLIMB
		_steer_used = 0
		begin_step(ahead, Cfg.STEP_CLIMB)
		return true
	if on_ladder and can_stand(ahead):
		state = St.NORMAL
		begin_step(ahead, Cfg.STEP_WALK)
		return true
	return false


func _on_step_end() -> void:
	if state == St.DASH and _dash_left <= 0:
		state = St.NORMAL

	if state != St.FALL and not board.supports_actor(cell) and not board.blocks_player(cell):
		state = St.FALL
		_steer_used = 0

	if state == St.FALL:
		var below := cell + Vector2i.DOWN
		if board.blocks_item(below) or board.is_ladder(below):
			state = St.CLIMB if board.is_ladder(cell) else St.NORMAL


# --- Carrying --------------------------------------------------------------


func _toggle_carry() -> void:
	if moving:
		return
	if tray.is_empty():
		_take_one()
	else:
		_place_one()


func _take_one() -> void:
	if tray.size() >= TRAY_MAX:
		return
	if board.tile_at(cell) == Board.Tile.TABLE:
		var from_table := board.pop_from_table(cell)
		if from_table >= 0:
			tray.append(from_table)
			tray_changed.emit()
			return
	var occ := board.occupant_at(cell)
	if occ is Ingredient:
		tray.append(occ.kind)
		board.clear_occupant(cell)
		occ.queue_free()
		tray_changed.emit()
		return
	if board.is_salt(cell):
		tray.append(SALT)
		tray_changed.emit()


## Takes the item at the bottom of the tray. A tray of [bun, lettuce, lid]
## therefore lands on the counter in the order a burger needs built.
func _place_one() -> void:
	var kind: int = tray.pop_front()
	tray_changed.emit()
	if board.tile_at(cell) == Board.Tile.TABLE:
		var stack := board.push_to_table(cell, kind)
		_credit_burger(stack)
	else:
		want_ingredient.emit(cell, kind)


func _credit_burger(stack: Array) -> void:
	if board.is_completed(cell):
		return
	if not board.stack_is_burger(stack):
		return
	board.mark_completed(cell)
	var points := Food.burger_points(stack)
	GameState.add_score(points)
	GameState.burgers_served += 1
	served.emit(points, cell)


func _throw_tray() -> void:
	for i in tray.size():
		var kind: int = tray[i]
		if kind == SALT:
			want_salt.emit(cell, facing)
		else:
			var spot := cell
			for step in 1 + i:
				var ahead := spot + Vector2i(facing, 0)
				if in_bounds(ahead) and not board.blocks_player(ahead):
					spot = ahead
				else:
					break
			want_ingredient.emit(spot, kind)
	tray.clear()
	tray_changed.emit()


func _drop_tray() -> void:
	for kind in tray:
		if kind != SALT:
			want_ingredient.emit(cell, kind)
	tray.clear()
	tray_changed.emit()


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
	if state == St.DEAD:
		_draw_dead()
		return
	# Blink while invulnerable, whether that is the hurt stun or respawn grace.
	if (state == St.HURT or _grace_t > 0.0) and fmod(_anim_t, 0.2) < 0.1:
		return

	_draw_tray()

	# Mirror the whole chef about the cell centre so facing is one transform.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing, 1.0))
	_part(Rect2(-5, -8, 10, 4), Cfg.PLAYER_COOK_HAT)
	_part(Rect2(-4, -4, 8, 4), Cfg.PLAYER_COOK_SKIN)
	_part(Rect2(-4, 0, 8, 6), Cfg.PLAYER_COOK_SHIRT)
	var leg := 0
	if moving:
		leg = 1 if sin(_anim_t * 18.0) > 0.0 else 0
	_part(Rect2(-4, 6, 3, 2), Cfg.PLAYER_COOK_PANTS)
	_part(Rect2(1, 6, 3, 2), Cfg.PLAYER_COOK_PANTS)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if state == St.DASH:
		# Speed lines trailing a counter run.
		var tail := -float(facing) * (3.0 + 5.0 * step_phase())
		draw_rect(Rect2(tail - 3, -2, 3, 2), Color(1, 1, 1, 0.5))
		draw_rect(Rect2(tail - 5, 2, 5, 2), Color(1, 1, 1, 0.35))


func _part(r: Rect2, col: Color) -> void:
	draw_rect(r, col)
	draw_rect(r, Cfg.COL_OUTLINE, false, 1.0)


func _draw_tray() -> void:
	for i in tray.size():
		var kind: int = tray[i]
		var y := -10 - i * 7
		if kind == SALT:
			_part(Rect2(-6, y, 12, 6), Cfg.COL_SALT)
			draw_rect(Rect2(-6, y, 12, 2), Cfg.COL_SALT.darkened(0.2))
			continue
		var r := Rect2(-6, y, 12, 6)
		draw_rect(r.grow(1.0), Cfg.COL_OUTLINE)
		draw_rect(r, Food.color_of(kind))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Food.accent_of(kind))


func _draw_dead() -> void:
	var a := clampf(_dead_t / DEAD_TIME, 0.0, 1.0)
	draw_rect(Rect2(-6, -6, 12, 12), Color(0.9, 0.3, 0.3, a))
	draw_rect(Rect2(-4, -8, 8, 3), Color(Cfg.PLAYER_COOK_HAT, a))
