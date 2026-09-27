class_name Game
extends Node2D
## Owns one level: builds the board, spawns actors, runs the clock, and drives
## the win/lose flow.

enum Phase { INTRO, PLAYING, LEVEL_CLEAR, TIME_UP, GAME_OVER, ALL_CLEAR }

## How long a result banner stays up before moving on.
const PHASE_TIME := 2.6

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
		if arg.begins_with("--level="):
			var wanted := int(arg.substr(8))
			if wanted >= 0 and wanted < LevelData.count():
				return wanted
	return GameState.level_index


func start_level(index: int) -> void:
	_clear_actors()
	level = LevelData.get_level(index)
	GameState.set_level(index, level.target, level.seconds)

	board = Board.new()
	_actor_parent().add_child(board)
	board.setup(level)

	player = Player.new()
	player.board = board
	_actor_parent().add_child(player)
	player.place(board.player_spawn)
	player.want_ingredient.connect(_on_want_ingredient)
	player.want_salt.connect(_on_want_salt)
	player.died.connect(_on_player_died)
	player.served.connect(_on_served)

	_spawn_enemies()

	_popups.clear()
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
	for cell in board.enemy_kinds:
		var kind: Enemy.Kind = board.enemy_kinds[cell]
		var enemy := Enemy.new()
		_actor_parent().add_child(enemy)
		enemy.setup(board, cell, kind, player)
		enemy.add_to_group(&"enemies")
		enemy.caught_player.connect(_on_enemy_caught)


# --- Signals from the player ------------------------------------------------


func _on_want_ingredient(cell: Vector2i, kind: Food.Kind) -> void:
	# Backstop for the whole class of bug: a bad kind reaching an Ingredient
	# crashes in its _draw, which reads as the renderer failing rather than a
	# caller passing nonsense, and it would do so every frame until reload.
	if not Food.is_kind(kind):
		push_warning("ignored an ingredient request for invalid kind %d" % kind)
		return
	var ing := Ingredient.new()
	_actor_parent().add_child(ing)
	ing.setup(board, cell, kind)


func _on_want_salt(cell: Vector2i, facing: int) -> void:
	var packet := Salt.new()
	_actor_parent().add_child(packet)
	packet.setup(board, cell, facing, player)
	packet.add_to_group(&"salt")


func _on_enemy_caught() -> void:
	if player != null:
		player.hit()


func _on_player_died() -> void:
	if GameState.lives <= 0:
		_enter(Phase.GAME_OVER)
	else:
		_popup("OUCH!", Cfg.COL_PLATE)


func _on_served(points: int, cell: Vector2i) -> void:
	_popup("+%d" % points, Color("6fc24a"))
	_popup_tween(Cfg.cell_to_pixel(cell))
	if GameState.burgers_served >= GameState.burgers_target:
		_enter(Phase.LEVEL_CLEAR)


# --- Flow -------------------------------------------------------------------


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"pause") and phase == Phase.PLAYING:
		paused = not paused
		if hud != null:
			hud.queue_redraw()
	if paused:
		return

	match phase:
		# Everything that is not PLAYING just runs its phase timer down, which
		# includes the level card, so INTRO deliberately falls through here.
		Phase.PLAYING:
			GameState.tick(delta)
			if GameState.time_left <= 0.0:
				GameState.lose_life()
				_enter(Phase.GAME_OVER if GameState.lives <= 0 else Phase.TIME_UP)
		_:
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
		Phase.INTRO:
			pass
		Phase.PLAYING:
			_set_player_active(true)
		Phase.LEVEL_CLEAR:
			_set_player_active(false)
			_popup("LEVEL CLEAR!", Color("6fc24a"))
			GameState.save_progress()
		Phase.TIME_UP:
			_set_player_active(false)
			_popup("TIME UP", Color("e2453c"))
		Phase.GAME_OVER:
			_set_player_active(false)
			_popup("GAME OVER", Color("e2453c"))
			GameState.save_progress()
		Phase.ALL_CLEAR:
			_set_player_active(false)
			_popup("YOU WIN!", Color("f5c53a"))
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
				_phase_t = PHASE_TIME
		Phase.TIME_UP:
			# Out of time costs the level, not the run.
			GameState.set_time(level.seconds)
			start_level(GameState.level_index)
		Phase.GAME_OVER:
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		Phase.ALL_CLEAR:
			get_tree().change_scene_to_file("res://scenes/main.tscn")


func _popup(text: String, color: Color) -> void:
	_popups.append({"text": text, "t": 0.0, "pos": Vector2.ZERO, "color": color})


func _popup_tween(at: Vector2) -> void:
	if _popups.is_empty():
		return
	_popups.back()["pos"] = at
