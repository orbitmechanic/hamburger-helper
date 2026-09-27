extends Node2D
## Title screen: a plate of burgers and a blinking prompt.

var _t := 0.0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	GameState.load_progress()


func _process(delta: float) -> void:
	_t += delta
	if Input.is_action_just_pressed(&"confirm") or Input.is_action_just_pressed(&"jump"):
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	queue_redraw()


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
	_center(Vector2(w * 0.5, h - 42.0), "X TO JUMP   P TO PAUSE", Color("9a9ac0"), 8)

	if fmod(_t, 1.0) < 0.65:
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
