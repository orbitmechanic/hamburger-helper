extends Node
## Arcade demo mode: cycles between autoplay and the title screen.
##
## This node is attached to the root viewport, not to any scene, so it survives
## the scene changes it drives. The cycle is `change_scene_to_file`, nothing
## manual: adding the title or a game as a sibling of the current scene fails
## outright from inside this node's own `_ready` - the root is busy setting up
## children while it is being added - and even when it works it leaves the real
## title running underneath, drawing and eating input.

const PLAY_TIME := 60.0
const TITLE_TIME := 20.0

enum State { TITLE, PLAY }

var state := State.TITLE
## Both entries - an idle title and a standalone boot through
## scenes/demo.tscn - go straight to play: whoever got here has already
## been looking at the title. Between runs the cycle holds the title for
## TITLE_TIME.
var _time := 0.0
var _bot: Node = null
## Set once the bot script turns out to be missing, so its absence is paid
## for once rather than on every attach attempt.
var _no_bot := false


func _ready() -> void:
	state = State.TITLE
	_time = TITLE_TIME


func _process(delta: float) -> void:
	_time += delta
	match state:
		State.TITLE:
			if _time >= TITLE_TIME:
				_go_play()
		State.PLAY:
			if _bot == null and not _no_bot:
				_attach_bot()
			elif _bot != null and _bot.has_method("think"):
				_bot.think(delta)
			if _time >= PLAY_TIME:
				_go_title()


func _go_play() -> void:
	state = State.PLAY
	_time = 0.0
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _go_title() -> void:
	_release_bot()
	state = State.TITLE
	_time = 0.0
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## Retries until the new scene is current, because the scene change is
## deferred out of whatever frame asked for it.
func _attach_bot() -> void:
	var game := get_tree().current_scene as Game
	if game == null:
		return
	# The bot lives in tools/, which the export preset excludes, so a web
	# build cannot load it. Without one there is nothing to autoplay, and
	# the cycle just keeps handing the screen back to the title - which is
	# what it did before autoplay existed - instead of throwing every frame.
	# ResourceLoader.exists rather than load: a failed load logs two errors
	# every time it is tried, and an absent tool is not an error.
	if not ResourceLoader.exists("res://tools/survival_bot.gd"):
		_no_bot = true
		_go_title()
		return
	_bot = load("res://tools/survival_bot.gd").new()
	game.add_child(_bot)
	_bot.setup(game)


func _release_bot() -> void:
	if _bot != null:
		_bot.queue_free()
		_bot = null


func _input(event: InputEvent) -> void:
	var key: bool = event is InputEventKey and event.pressed and not event.is_echo()
	var pad: bool = event is InputEventJoypadButton and event.pressed
	# A tap on the on-screen controls is a press too: the pads drive the game
	# through Input.action_press rather than key events, so without this a
	# mobile player would be steering against the bot for the rest of the
	# sixty-second run.
	var touch: bool = event is InputEventScreenTouch and event.pressed
	if not (key or pad or touch):
		return
	# Any real input hands the machine to the human. On the title screen the
	# press belongs to the title's own start handling and the arrows do not
	# start anything, so leaving is all that happens here. In autoplay it
	# means the chef: the running game is kept rather than replaced, and the
	# bot is taken out of it.
	_release_bot()
	queue_free()
