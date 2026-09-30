class_name Game
extends Node2D
## Owns one level: builds the board, drops the ingredients in, spawns the
## nasties and the bonuses, and runs the win/lose flow.
##
## There is no countdown to run down. The only two ways a level ends are all the
## plates filled and every chef used up.

enum Phase { INTRO, PLAYING, LEVEL_CLEAR, GAME_OVER, ALL_CLEAR }

## How long a result banner stays up before moving on.
const PHASE_TIME := 2.6
## How long the chef's victory runs before he settles on the last frame. Shorter
## than the banner on purpose, so he holds the pose rather than restarting it.
const VICTORY_TIME := 1.2
## How long the chef stays down after being caught, before he is put back. Long
## enough to read the surprised pose, short enough not to feel like a stall.
const DEATH_TIME := 0.7
## A pepper dose the level starts with, as in the original.
const STARTING_PEPPER := 1
## Seconds between random bonuses appearing, and how many can be out at once.
const BONUS_EVERY := 11.0
const BONUS_MAX := 2

var board: Board
var player: Player
var hud: Control
## Container for the board, chef, ingredients and enemies. Level teardown
## clears this and nothing else.
var actors: Node2D
var phase: Phase = Phase.PLAYING
var level: LevelData.Level
var paused := false

var _phase_t := 0.0
var _popups: Array = []
var _bonus_t := 0.0
## Counts the chef down from `DEATH_TIME` while he is on the floor. Overlapping the
## phase timer rather than becoming a phase of its own: the board is still in play
## behind him, it is only waiting for the chef.
var _dying := 0.0


func _ready() -> void:
	actors = get_node_or_null("Actors")
	hud = get_node_or_null("HudLayer/Hud")
	if hud != null:
		hud.game = self
	start_level(_requested_level())


## Development hook: `godot scenes/game.tscn -- --level=2` jumps straight to a
## level. There is no level select yet, so this is the only way to look at
## anything past the first one, which is what tools/shots.sh needs.
## Ignored unless the argument is given.
func _requested_level() -> int:
	for arg in OS.get_cmdline_user_args():
		var text := arg.trim_prefix("--level=")
		if text == arg or not text.is_valid_int():
			continue
		var wanted := text.to_int()
		if wanted >= 0 and wanted < LevelData.count():
			return wanted
	return GameState.level_index


func start_level(index: int) -> void:
	_clear_actors()
	level = LevelData.get_level(index)
	GameState.set_level(index, level.plates.size())

	board = Board.new()
	_actor_parent().add_child(board)
	board.setup(level)

	player = Player.new()
	_actor_parent().add_child(player)
	player.setup(board, board.chef_spawn)
	player.add_pepper(STARTING_PEPPER)
	player.crossed.connect(_on_crossed)

	# The ingredients are already placed in the map, so they are built here rather
	# than pushed in by the chef. Each one is a run of cells; the width is part of
	# the puzzle, since the chef has to cross all of it to move it.
	for span in level.ingredients:
		var ing := Ingredient.new()
		_actor_parent().add_child(ing)
		ing.setup(board, span)
		ing.add_to_group(&"ingredients")
		ing.dropped.connect(_on_ingredient_dropped)
		ing.carried_rider.connect(_on_rider)
		ing.boarded.connect(_on_ingredient_boarded)

	_spawn_enemies()

	_popups.clear()
	_bonus_t = BONUS_EVERY
	paused = false
	_dying = 0.0
	_set_player_active(false)
	phase = Phase.INTRO
	_phase_t = Cfg.INTRO_TIME
	# He comes in under the parachute for the level card. There is no drop and no
	# descent: the level card is a static overlay, so a chef who fell into it would
	# land on a ledge the player has not been shown yet, and the card would be
	# covering the fall. The pose says "arriving" and the card does the timing.
	player.set_pose(Sheet.Anim.PARACHUTE)
	if hud != null:
		hud.queue_redraw()


## Where actors go. A dedicated container rather than the Game node itself,
## because clearing "all children" also removed the scene's own HUD: the level
## card, the score and the clock were destroyed by the first start_level and
## have never been visible since. Falls back to self, since the tests build a
## bare Game.new() with no scene and no container.
func _actor_parent() -> Node:
	return actors if actors != null else self


func _clear_actors() -> void:
	# Null the references first: a node freed at the end of the frame can still
	# run one more _process, and the old actors must not touch the new level.
	board = null
	player = null
	_popups.clear()
	# Detach before queue_free, otherwise the outgoing level keeps processing
	# and drawing for another frame and appears as a ghost behind the new one.
	var parent := _actor_parent()
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _spawn_enemies() -> void:
	for cell in board.enemy_spawns:
		var kind: Enemy.Kind = board.enemy_kinds.get(cell, Enemy.Kind.HOTDOG)
		var enemy := Enemy.new()
		_actor_parent().add_child(enemy)
		enemy.setup(board, cell, kind, player)
		enemy.add_to_group(&"enemies")
		enemy.squashed.connect(_on_enemy_squashed)


# --- Crossing --------------------------------------------------------------


## The chef has walked the full width of a part, so it drops. A nasty standing on
## it at that moment goes down with it, and the part falls two levels rather than
## one - which is the whole reason to bait a nasty under a bun.
func _on_crossed(ing: Ingredient) -> void:
	var riders := 0
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Enemy
		if enemy != null and is_instance_valid(enemy) and enemy.riding(ing):
			riders += 1
			enemy.attach(ing)
	ing.knock(1 if riders > 0 else 0)


func _on_rider() -> void:
	GameState.add_score(Food.POINTS_RIDER)
	_popup("RIDE!", Cfg.COL_BONUS)


func _on_ingredient_dropped(floors: int, at: Vector2i) -> void:
	GameState.add_score(floors * Food.POINTS_PER_FLOOR)


## A part has reached a plate. If that finishes the burger it is worth scoring
## and, if it was the last plate, the level.
func _on_ingredient_boarded(plate: LevelData.Span) -> void:
	GameState.add_score(Food.POINTS_PER_FLOOR)
	if not Food.stack_is_burger(board.stack(plate.x)):
		return
	GameState.count_burger(Food.burger_points(board.stack(plate.x).size()))
	_popup("+%d" % Food.burger_points(board.stack(plate.x).size()), Cfg.COL_BONUS)
	_popup_tween(Cfg.cell_to_pixel(Vector2i(plate.x, plate.y)))
	if GameState.burgers_done >= GameState.burgers_target:
		_enter(Phase.LEVEL_CLEAR)


func _on_enemy_squashed(points: int) -> void:
	GameState.add_score(points)


# --- Bonuses ---------------------------------------------------------------


func _process_bonuses(delta: float) -> void:
	for b in get_tree().get_nodes_in_group(&"bonuses"):
		var bonus := b as Bonus
		if bonus == null or not is_instance_valid(bonus):
			continue
		if bonus.cell == player.cell:
			_collect(bonus)
	_bonus_t -= delta
	if _bonus_t > 0.0:
		return
	_bonus_t = BONUS_EVERY
	if get_tree().get_nodes_in_group(&"bonuses").size() >= BONUS_MAX:
		return
	var at := _random_walk_row_cell()
	if at == Vector2i(-1, -1):
		return
	var bonus := Bonus.new()
	_actor_parent().add_child(bonus)
	bonus.setup(at, _random_bonus_kind())
	bonus.add_to_group(&"bonuses")


func _collect(bonus: Bonus) -> void:
	match bonus.kind:
		Bonus.Kind.PEPPER, Bonus.Kind.SALT:
			player.add_pepper(bonus.charges())
			GameState.add_score(Food.POINTS_PEPPER)
			_popup(bonus.label(), Cfg.COL_PEPPER)
		Bonus.Kind.LIFE:
			GameState.add_chef()
			_popup("1UP", Cfg.COL_BONUS)
	_popup_tween(Cfg.cell_to_pixel(bonus.cell))
	bonus.queue_free()


## Pepper is the one that has to appear where the chef can actually reach it, so
## the cell is drawn from the walk rows rather than the whole grid.
##
## The candidates are collected and sampled with pick_random() instead of rolling
## and rejecting: rejection sampling needed a retry cap that silently degraded to
## "no bonus appears" on a crowded board, and picked a uniform cell from a list
## is both exact and shorter.
func _random_walk_row_cell() -> Vector2i:
	var candidates: Array[Vector2i] = []
	for x in range(1, Cfg.GRID_W - 1):
		for y in Cfg.GRID_H:
			var at := Vector2i(x, y)
			if board.blocks_player(at) or not board.floor_below(at):
				continue
			candidates.append(at)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates.pick_random()


func _random_bonus_kind() -> Bonus.Kind:
	var roll := randf()
	if roll < 0.45:
		return Bonus.Kind.PEPPER
	if roll < 0.9:
		return Bonus.Kind.SALT
	return Bonus.Kind.LIFE


## How long a nasty stays frozen by a dose. Long enough to walk away from it
## and do something else, short enough that it is not gone for the rest of the
## level.
const SPRAY_STUN_TIME := 5.0


## Seasoning is a forward spray the chef throws himself.
##
## Two earlier shapes were wrong for a player. Making the jar freeze every nasty
## the moment it was picked up took the timing out of the player's hands - the
## board paused itself, and the jar decided the moment rather than the player. And
## spending a charge to shimmer until something walked into the chef wasted the
## dose on whichever nasty happened to be nearest, which is rarely the one the
## player was aiming at. So a dose is now aimed: the key throws it the way the
## chef is facing, and whatever the spray reaches is frozen for a count-down.
## One charge is one shot, and with an empty jar the key says so.
func _fire_pepper() -> void:
	if player == null or not is_instance_valid(player):
		return
	if not Input.is_action_just_pressed(&"pepper"):
		return
	if not player.spend_pepper():
		_popup("NO PEPPER", Cfg.COL_PLATE)
		return
	var spray := player.spray_rect()
	var hit := 0
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Enemy
		if enemy != null and is_instance_valid(enemy) and spray.intersects(enemy.hit_rect()):
			enemy.stun(SPRAY_STUN_TIME)
			hit += 1
	_popup("SPRAY!" if hit == 0 else "ZAP x%d" % hit, Cfg.COL_PEPPER)


# --- Loss ------------------------------------------------------------------


## Runs the contact check. The seasoning spray freezes a nasty for five seconds
## rather than removing it, so a frozen nasty must not be able to catch the chef
## either.
func _check_catches() -> void:
	if phase != Phase.PLAYING or player == null or not is_instance_valid(player):
		return
	if player.state == Player.St.JUMP:
		return
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.state == Enemy.St.SQUASH or enemy.state == Enemy.St.STUN:
			continue
		if _touching(enemy):
			_on_player_died()
			return


## Whether the chef and a nasty are actually touching.
##
## Body boxes in world pixels, so this answers the question the player is asking -
## are these two things touching on the screen - and not the easier one the cell
## check answered, which was whether they were in the same cell or next to it. That
## is what let the chef die a cell and a half from the nasty that got him, with
## nothing on screen overlapping: an eight-pixel gap the player could see and the
## game ignored.
func _touching(enemy: Enemy) -> bool:
	return player.hit_rect().intersects(enemy.hit_rect())


func _on_player_died() -> void:
	GameState.lose_chef()
	# Every nasty goes back to its own ledge, as in the original. Without this a
	# nasty sitting next to the chef's spawn eats the run chef after chef, because
	# each respawn puts the chef straight back into its arms.
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Enemy
		if enemy != null and is_instance_valid(enemy):
			enemy.reset_for_respawn()
	# The chef is surprised, and stays that way long enough to be seen, rather than
	# blinking out of one pose and into his spawn in the same frame. He is also out
	# of play for it, so he cannot walk off into a nasty that has just been sent
	# back to its ledge, nor be caught again before he is back.
	player.set_pose(Sheet.Anim.DEATH)
	if GameState.out_of_chefs():
		_enter(Phase.GAME_OVER)
		return
	_popup("OUCH!", Cfg.COL_PLATE)
	_popup_tween(Cfg.cell_to_pixel(board.chef_spawn))
	_dying = DEATH_TIME
	_set_player_active(false)


## Put the chef back where he started. The plate work already done stays done.
func _revive() -> void:
	_dying = 0.0
	if player == null or not is_instance_valid(player):
		return
	# `place` hands the chef back to himself, so the surprised pose goes with it.
	player.place(board.chef_spawn)
	_set_player_active(true)


# --- Flow -------------------------------------------------------------------


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"pause") and phase == Phase.PLAYING:
		paused = not paused
		if hud != null:
			hud.queue_redraw()
	if paused:
		return

	# The chef is down. The board waits on him: no input, no catches, and the
	# banner is not running, because none of that is the point of this beat.
	if _dying > 0.0:
		_dying -= delta
		if _dying <= 0.0:
			_revive()
		if hud != null:
			hud.queue_redraw()
		return

	match phase:
		Phase.PLAYING:
			_process_bonuses(delta)
			_fire_pepper()
			_check_catches()
		_:
			# Everything that is not PLAYING just runs its phase timer down, which
			# includes the level card, so INTRO deliberately falls through here.
			_phase_t -= delta
			_celebrate()
			if _phase_t <= 0.0:
				_advance()

	if hud != null:
		hud.queue_redraw()


## Play the chef's victory off the back of the level-clear banner, which is longer
## than the animation: he finishes the flourish and holds the pose for the rest of
## it, then is gone when the banner is.
func _celebrate() -> void:
	if phase != Phase.LEVEL_CLEAR and phase != Phase.ALL_CLEAR:
		return
	if player == null or not is_instance_valid(player):
		return
	player.set_pose(Sheet.Anim.VICTORY,
			clampf((PHASE_TIME - _phase_t) / VICTORY_TIME, 0.0, 1.0))


## The chef only moves and is only hit while the level is actually running.
func _set_player_active(active: bool) -> void:
	if player != null and is_instance_valid(player):
		player.set_process(active)


func _enter(next: Phase) -> void:
	phase = next
	_phase_t = PHASE_TIME
	# The chef is only ever down during play. Anything that takes the board out of
	# play takes him off the floor with it, or the death beat would swallow the
	# banner it happens during.
	_dying = 0.0
	match next:
		Phase.PLAYING:
			# The parachute was only for the level card, so from here the chef is
			# playing again and animates himself.
			if player != null and is_instance_valid(player):
				player.clear_pose()
			_set_player_active(true)
		Phase.LEVEL_CLEAR:
			_set_player_active(false)
			# Set here as well as from `_celebrate` so the very first frame of the
			# banner is already the start of the flourish and not the last frame of
			# whatever he was doing when the last plate went down.
			if player != null and is_instance_valid(player):
				player.set_pose(Sheet.Anim.VICTORY, 0.0)
			_popup("LEVEL CLEAR!", Cfg.COL_BONUS)
			GameState.save_progress()
		Phase.GAME_OVER:
			_set_player_active(false)
			_popup("GAME OVER", Cfg.COL_PLATE)
			GameState.save_progress()
		Phase.ALL_CLEAR:
			_set_player_active(false)
			_popup("YOU WIN!", Cfg.COL_PEPPER)
			GameState.save_progress()


func _advance() -> void:
	match phase:
		Phase.INTRO:
			_enter(Phase.PLAYING)
		Phase.LEVEL_CLEAR:
			var next_index := GameState.level_index + 1
			if next_index < LevelData.count():
				start_level(next_index)
			else:
				_enter(Phase.ALL_CLEAR)
		Phase.GAME_OVER, Phase.ALL_CLEAR:
			get_tree().change_scene_to_file("res://scenes/main.tscn")


func _popup(text: String, color: Color) -> void:
	_popups.append({"text": text, "t": 0.0, "pos": Vector2.ZERO, "color": color})


func _popup_tween(at: Vector2) -> void:
	if _popups.is_empty():
		return
	_popups.back()["pos"] = at


## For the Hud to draw. Popups live here because only the Game knows where things
## happened.
func popups() -> Array:
	return _popups
