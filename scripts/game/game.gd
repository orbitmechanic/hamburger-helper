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
	_set_player_active(false)
	phase = Phase.INTRO
	_phase_t = Cfg.INTRO_TIME
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
		Bonus.Kind.PEPPER:
			player.add_pepper(bonus.charges())
			GameState.add_score(Food.POINTS_PEPPER)
			_popup("PEPPER", Cfg.COL_PEPPER)
		Bonus.Kind.STUN:
			for e in get_tree().get_nodes_in_group(&"enemies"):
				(e as Enemy).stun(bonus.stun_seconds())
			GameState.add_score(Food.POINTS_STUN)
			_popup("STUN!", Cfg.COL_PEPPER)
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
	if roll < 0.6:
		return Bonus.Kind.PEPPER
	if roll < 0.9:
		return Bonus.Kind.STUN
	return Bonus.Kind.LIFE


## Pepper is fired, not automatic.
##
## Spending a charge on whichever nasty the chef happened to brush past made the
## jars a resource the player never chose how to use, and the common case was
## wasting one on a nasty who was about to walk off the ledge anyway. So the
## chef throws it himself: the key ghosts him for a moment, and the first nasty
## he touches inside that window is the one that gets zapped. Pressing it with
## nothing left says so rather than doing nothing quietly.
func _fire_pepper() -> void:
	if player == null or not is_instance_valid(player):
		return
	if not Input.is_action_just_pressed(&"pepper"):
		return
	if not player.use_pepper():
		_popup("NO PEPPER", Cfg.COL_PLATE)
		return
	_popup("PEPPER!", Cfg.COL_PEPPER)


# --- Loss ------------------------------------------------------------------


## Runs the contact check. Kept out of the enemy so that the pepper rule lives
## in one place: a ghosted chef cannot be caught, and a stunned nasty cannot
## catch him even without pepper.
func _check_catches() -> void:
	if phase != Phase.PLAYING or player == null or not is_instance_valid(player):
		return
	if player.state == Player.St.JUMP:
		return
	if player.ghost():
		# A thrown pepper has already been paid for by the key press, so the
		# nasty that runs into the shimmer is stunned and no charge is spent.
		for e in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := e as Enemy
			if enemy != null and is_instance_valid(enemy) and _touching(enemy.cell):
				enemy.stun()
				_popup("ZAP!", Cfg.COL_PEPPER)
				return
		return
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.state == Enemy.St.SQUASH or enemy.state == Enemy.St.STUN:
			continue
		if _touching(enemy.cell):
			_on_player_died()
			return


func _touching(cell: Vector2i) -> bool:
	return absi(cell.x - player.cell.x) + absi(cell.y - player.cell.y) <= 1


func _on_player_died() -> void:
	GameState.lose_chef()
	# Every nasty goes back to its own ledge, as in the original. Without this a
	# nasty sitting next to the chef's spawn eats the run chef after chef, because
	# each respawn puts the chef straight back into its arms.
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Enemy
		if enemy != null and is_instance_valid(enemy):
			enemy.reset_for_respawn()
	if GameState.out_of_chefs():
		_enter(Phase.GAME_OVER)
	else:
		_popup("OUCH!", Cfg.COL_PLATE)
		_popup_tween(Cfg.cell_to_pixel(board.chef_spawn))
		# The chef goes back to where he started: the plate work already done
		# stays done.
		player.place(board.chef_spawn)


# --- Flow -------------------------------------------------------------------


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"pause") and phase == Phase.PLAYING:
		paused = not paused
		if hud != null:
			hud.queue_redraw()
	if paused:
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
			if _phase_t <= 0.0:
				_advance()

	if hud != null:
		hud.queue_redraw()


## The chef only moves and is only hit while the level is actually running.
func _set_player_active(active: bool) -> void:
	if player != null and is_instance_valid(player):
		player.set_process(active)


func _enter(next: Phase) -> void:
	phase = next
	_phase_t = PHASE_TIME
	match next:
		Phase.PLAYING:
			_set_player_active(true)
		Phase.LEVEL_CLEAR:
			_set_player_active(false)
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
