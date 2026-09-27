class_name Hud
extends Control
## Arcade overlay: score, level, burgers, clock, lives, plus phase banners.

const PAD := 6.0
const FONT_SIZE := 8

var game: Game

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	var w := size.x

	_text(Vector2(PAD, PAD + 8), "LEVEL %d" % (GameState.level_index + 1), Color("f4f4ff"), FONT_SIZE)
	_text(Vector2(w * 0.5 - 30, PAD + 8), "%06d" % GameState.score, Color("f5c53a"), FONT_SIZE + 1)

	var burgers := "BURGERS %d/%d" % [GameState.burgers_served, GameState.burgers_target]
	_text(Vector2(PAD, PAD + 18), burgers, Color("f4f4ff"), FONT_SIZE)

	var secs := int(ceil(GameState.time_left))
	var time_col := Color("f4f4ff")
	if secs <= 10:
		time_col = Color("e2453c") if fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.5 else Color("ffffff")
	_text(Vector2(w - 64, PAD + 18), "TIME %d" % secs, time_col, FONT_SIZE)

	_draw_lives(Vector2(w - PAD - 8, PAD + 30))

	if game != null:
		if game.paused:
			_banner("PAUSED", Color("f4f4ff"))
		else:
			match game.phase:
				Game.Phase.INTRO:
					_level_card()
				Game.Phase.LEVEL_CLEAR:
					_banner("LEVEL CLEAR!", Color("6fc24a"))
				Game.Phase.TIME_UP:
					_banner("TIME UP", Color("e2453c"))
				Game.Phase.GAME_OVER:
					_banner("GAME OVER", Color("e2453c"))
				Game.Phase.ALL_CLEAR:
					_banner("YOU WIN!", Color("f5c53a"))


## The card that names the level and the job before the chef moves.
func _level_card() -> void:
	if game.level == null:
		return
	var w := size.x
	var h := size.y
	var card := Rect2(w * 0.5 - 68.0, h * 0.5 - 34.0, 136.0, 68.0)
	draw_rect(card, Cfg.COL_CARD)
	draw_rect(card, Cfg.COL_PLATFORM_EDGE, false, 2.0)

	_centered(card.position.y + 16.0, "LEVEL %d" % (GameState.level_index + 1), Color("f5c53a"), FONT_SIZE + 2)
	_centered(card.position.y + 30.0, game.level.name, Color("f4f4ff"), FONT_SIZE)
	_centered(card.position.y + 46.0, "COOK %d BURGERS" % GameState.burgers_target, Color("6fc24a"), FONT_SIZE)
	_centered(card.position.y + 60.0, "IN %d:%02d" % _minutes(), Color("e8b4b0"), FONT_SIZE)


## Seconds left as whole minutes and seconds, for the card.
func _minutes() -> Array:
	var total := int(ceil(maxf(GameState.time_left, 0.0)))
	return [total / 60, total % 60]


func _centered(y: float, text: String, color: Color, font_size: int) -> void:
	var text_w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2((size.x - text_w) * 0.5, y)
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Cfg.COL_OUTLINE)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_lives(at: Vector2) -> void:
	for i in GameState.lives:
		var x := at.x - i * 10.0
		draw_rect(Rect2(x - 4, at.y - 4, 8, 8), Cfg.PLAYER_COOK_HAT)
		draw_rect(Rect2(x - 4, at.y - 4, 8, 8), Cfg.COL_OUTLINE, false, 1.0)
		draw_rect(Rect2(x - 3, at.y + 1, 6, 3), Cfg.PLAYER_COOK_SHIRT)


func _banner(text: String, color: Color) -> void:
	var font_size := 16
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := Vector2((size.x - width) * 0.5, size.y * 0.42)
	var pad := Vector2(10, 6)
	draw_rect(Rect2(pos - pad, Vector2(width, font_size + 4) + pad * 2.0), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(pos - pad, Vector2(width, font_size + 4) + pad * 2.0), color, false, 1.0)
	_text(pos + Vector2(0, font_size), text, color, font_size)


func _text(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Cfg.COL_OUTLINE)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
