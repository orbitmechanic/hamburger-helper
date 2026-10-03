extends Node
## Arcade demo mode: cycles between autoplay and title screen.
##
## Plays automatically for 60 seconds, then shows the title for 20 seconds,
## repeating forever.

const DemoBot := preload("res://tools/survival_bot.gd")

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
			if _bot != null:
				_bot.think(delta)
			var t := _play_time_override if _play_time_override > 0.0 else PLAY_TIME
			if _time >= t:
				_go_title()


func _go_title() -> void:
	_clear()
	_time = 0.0
	state = State.TITLE
	_current = _title_scene.instantiate()
	get_tree().root.call_deferred("add_child", _current)


func _go_play() -> void:
	_clear()
	_time = 0.0
	state = State.PLAY
	_current = _game_scene.instantiate()
	get_tree().root.add_child(_current)
	_bot = DemoBot.new()
	_current.add_child(_bot)
	call_deferred("_setup_bot_if_ready")


func _setup_bot_if_ready() -> void:
	if _current == null or _bot == null:
		return
	if _current is Game:
		(_current as Game).start_level(GameState.level_index)
	_bot.setup(_current as Game)


func _clear() -> void:
	if _bot != null:
		_bot.queue_free()
		_bot = null
	if _current != null:
		get_tree().root.remove_child(_current)
		_current.queue_free()
		_current = null
