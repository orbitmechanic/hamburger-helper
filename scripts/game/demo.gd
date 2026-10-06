extends Node
## Arcade demo mode: cycles between autoplay and title screen.

const PLAY_TIME := 60.0
const TITLE_TIME := 20.0

var _play_time_override := 0.0
var _title_time_override := 0.0

enum State { TITLE, PLAY }

var state := State.TITLE
var _time := 0.0
var _bot: Node = null
var _title_scene: PackedScene = null
var _game_scene: PackedScene = null
var _current: Node = null

func _ready() -> void:
	_title_scene = preload("res://scenes/main.tscn")
	_game_scene = preload("res://scenes/game.tscn")
	_go_title()

func _process(delta: float) -> void:
	_time += delta
	match state:
		State.TITLE:
			var t := _title_time_override if _title_time_override > 0.0 else TITLE_TIME
			if _time >= t:
				_go_play()
		State.PLAY:
			if _bot != null and _bot.has_method("think"):
				_bot.think(delta)
			var t := _play_time_override if _play_time_override > 0.0 else PLAY_TIME
			if _time >= t:
				_go_title()

func _go_title() -> void:
	_clear()
	_time = 0.0
	state = State.TITLE
	_current = _title_scene.instantiate()
	get_tree().root.add_child(_current)

func _go_play() -> void:
	_clear()
	_time = 0.0
	state = State.PLAY
	_current = _game_scene.instantiate()
	get_tree().root.add_child(_current)
	var Bot := load("res://tools/survival_bot.gd")
	_bot = Bot.new()
	_current.add_child(_bot)
	call_deferred("_setup_bot_if_ready")

func _setup_bot_if_ready() -> void:
	if _current == null or _bot == null:
		return
	if _current is Game:
		(_current as Game).start_level(GameState.level_index)
	if _bot.has_method("setup"):
		_bot.setup(_current as Game)

func _clear() -> void:
	if _bot != null:
		_bot.queue_free()
		_bot = null
	if _current != null:
		_current.queue_free()
		_current = null

func _exit_demo() -> void:
	_clear()
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_exit_demo()
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		get_tree().root.get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		_exit_demo()
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		get_tree().root.get_viewport().set_input_as_handled()
