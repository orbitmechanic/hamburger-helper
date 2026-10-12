extends Node2D
## Title screen: a plate of burgers and a blinking prompt.
##
## Owns the screen until the human presses start, or until it has sat idle
## long enough to be worth showing what the game does to whoever is not at
## the keyboard - then it hands over to the attract-mode cycle in demo.gd.
## The demo re-loads this scene to show the title, and its own node marks
## itself on the root, so a title under the cycle waits on the demo's timer
## rather than starting a second one.

const Demo := preload("res://scripts/game/demo.gd")

## Idle time before the attract cycle takes over.
const IDLE_DEMO_TIME := 10.0

var _t := 0.0
var _font: Font
var _demo_started := false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	GameState.load_progress()


func _process(delta: float) -> void:
	_t += delta
	if Input.is_action_just_pressed(&"confirm") or Input.is_action_just_pressed(&"jump"):
		# The jump rather than the burger: the burger belongs to finishing a
		# level, and this is not finishing anything.
		Sfx.play("jump")
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	elif not _demo_started and _t >= IDLE_DEMO_TIME:
		_start_demo()
	queue_redraw()


func _start_demo() -> void:
	_demo_started = true
	if get_tree().root.get_node_or_null("Demo") != null:
		return
	var demo := Node.new()
	demo.name = "Demo"
	demo.set_script(Demo)
	# Safe from _process: the root is not setting up children here, so the
	# demo's own _ready can drive a scene change from this frame.
	get_tree().root.add_child(demo)


func _draw() -> void:
	var w := Cfg.GRID_W * Cfg.TILE
	var h := Cfg.GRID_H * Cfg.TILE

	# A tall burger built out of the real ingredients.
	var base := Vector2(w * 0.5, h * 0.56)
	var layers := [
		Food.Kind.BUN_BOTTOM,
		Food.Kind.PATTY,
		Food.Kind.LETTUCE,
		Food.Kind.TOMATO,
		Food.Kind.BUN_TOP,
	]
	for i in layers.size():
		var kind: Food.Kind = layers[i]
		var r := Rect2(base + Vector2(-38, -i * 11.0), Vector2(76, 10))
		draw_rect(r.grow(1.0), Cfg.COL_OUTLINE)
		draw_rect(r, Food.color_of(kind))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Food.accent_of(kind))

	_title(Vector2(w * 0.5, 34.0), "HAMBURGER", Color("f5c53a"), 20)
	_title(Vector2(w * 0.5, 52.0), "HELPER", Color("e2453c"), 20)

	_center(Vector2(w * 0.5, h - 62.0), "WALK ALL THE WAY ACROSS FOOD TO DROP IT", Color("f4f4ff"), 8)
	_center(Vector2(w * 0.5, h - 52.0), "ARROWS OR WASD TO MOVE   UP AND DOWN ON LADDERS", Color("9a9ac0"), 8)
	_center(Vector2(w * 0.5, h - 42.0), "X TO JUMP   F TO THROW PEPPER   P TO PAUSE", Color("9a9ac0"), 8)

	if fposmod(_t, 1.0) < 0.65:
		_center(Vector2(w * 0.5, h - 24.0), "PRESS SPACE", Color("6fc24a"), 10)

	_center(Vector2(w * 0.5, h - 10.0), "HIGH SCORE %06d" % GameState.high_score, Color("9a9ac0"), 8)


func _title(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(pos - Vector2(width * 0.5, 0), text, color, font_size)


func _center(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(pos - Vector2(width * 0.5, 0), text, color, font_size)


func _text(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Cfg.COL_OUTLINE)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
