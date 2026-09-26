class_name Game
extends Node2D
## Owns one level: builds the board, spawns actors, runs the clock, and drives
## the win/lose flow.

enum Phase { PLAYING, LEVEL_CLEAR, TIME_UP, GAME_OVER, ALL_CLEAR }

## How long a result banner stays up before moving on.
const PHASE_TIME := 2.6

var board: Board
var player: Player
var hud: Control
var phase: Phase = Phase.PLAYING
var level: LevelData.Level
var paused := false

var _phase_t := 0.0
var _popups: Array = []


func _ready() -> void:
	hud = get_node_or_null("HudLayer/Hud")
	if hud != null:
		hud.game = self
	start_level(GameState.level_index)


func start_level(index: int) -> void:
	_clear_actors()
	level = LevelData.get_level(index)
	GameState.set_level(index, level.target, level.seconds)

	board = Board.new()
	add_child(board)
	board.setup(level)

	player = Player.new()
	player.board = board
	add_child(player)
	player.place(board.player_spawn)
	player.want_ingredient.connect(_on_want_ingredient)
	player.want_salt.connect(_on_want_salt)
	player.died.connect(_on_player_died)
	player.served.connect(_on_served)

	_spawn_enemies()

	_popups.clear()
	_phase_t = 0.0
	paused = false
	phase = Phase.PLAYING
	if hud != null:
		hud.queue_redraw()


func _clear_actors() -> void:
	for child in get_children():
		child.queue_free()
	board = null
	player = null
	_popups.clear()


func _spawn_enemies() -> void:
	for cell in board.enemy_kinds:
		var kind: Enemy.Kind = board.enemy_kinds[cell]
		var enemy := Enemy.new()
		add_child(enemy)
		enemy.setup(board, cell, kind, player)
		enemy.add_to_group(&"enemies")
		enemy.caught_player.connect(_on_enemy_caught)


# --- Signals from the player ------------------------------------------------


func _on_want_ingredient(cell: Vector2i, kind: Food.Kind) -> void:
	var ing := Ingredient.new()
	add_child(ing)
	ing.setup(board, cell, kind)


func _on_want_salt(cell: Vector2i, facing: int) -> void:
	var packet := Salt.new()
	add_child(packet)
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


func _enter(next: Phase) -> void:
	phase = next
	_phase_t = PHASE_TIME
	match next:
		Phase.LEVEL_CLEAR:
			_popup("LEVEL CLEAR!", Color("6fc24a"))
			GameState.save_progress()
		Phase.TIME_UP:
			_popup("TIME UP", Color("e2453c"))
		Phase.GAME_OVER:
			_popup("GAME OVER", Color("e2453c"))
			GameState.save_progress()
		Phase.ALL_CLEAR:
			_popup("YOU WIN!", Color("f5c53a"))
			GameState.save_progress()


func _advance() -> void:
	match phase:
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
