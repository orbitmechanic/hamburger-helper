extends Node2D

const Demo := preload("res://scripts/game/demo.gd")

var _t := 0.0
var _font: Font
var _demo_started := false
var _demo_instance: Node = null

func _ready() -> void:
	_font = ThemeDB.fallback_font
	GameState.load_progress()


func _process(delta: float) -> void:
	_t += delta
	if not _demo_started:
		_start_demo()
		return
	if Input.is_action_just_pressed(&"confirm") or Input.is_action_just_pressed(&"jump"):
		if _demo_instance != null:
			_demo_instance.queue_free()
			_demo_instance = null
		Sfx.play("jump")
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	queue_redraw()


func _start_demo() -> void:
	if get_tree().root.get_node_or_null("Demo") != null or _demo_instance != null:
		return
	_demo_started = true
	var demo := Node.new()
	demo.name = "Demo"
	demo.set_script(Demo)
	get_tree().root.add_child(demo)
	_demo_instance = demo
	# Don't queue_free the title - let demo manage cycling


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == 68:
			if _demo_instance != null:
				_demo_instance.queue_free()
				_demo_instance = null
			Sfx.play("jump")
			get_tree().change_scene_to_file("res://scenes/demo.tscn")
			return
		if _demo_instance != null:
			_demo_instance.queue_free()
			_demo_instance = null
		Sfx.play("jump")
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	elif event is InputEventJoypadButton and event.pressed:
		if _demo_instance != null:
			_demo_instance.queue_free()
			_demo_instance = null
		Sfx.play("jump")
		get_tree().change_scene_to_file("res://scenes/game.tscn")
