extends Node2D
## Title screen: a plate of burgers and a blinking prompt.

const Demo := preload("res://scripts/game/demo.gd")

var _t := 0.0
var _font: Font
var _demo_started := false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	GameState.load_progress()


func _process(delta: float) -> void:
	_t += delta
	if not _demo_started:
		_start_demo()
		return
	if Input.is_action_just_pressed(&"confirm") or Input.is_action_just_pressed(&"jump"):
		# The jump rather than the burger: the burger belongs to finishing a level,
		# and this is not finishing anything.
		Sfx.play("jump")
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	queue_redraw()



func _start_demo() -> void:
	if get_tree().root.get_node_or_null("Demo") != null:
		return
	_demo_started = true
	var demo := Node.new()
	demo.name = "Demo"
	demo.set_script(Demo)
	get_tree().root.add_child(demo)
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == 68:
		Sfx.play("jump")
		get_tree().change_scene_to_file("res://scenes/demo.tscn")
