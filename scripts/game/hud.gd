class_name Hud
extends Control
## Arcade overlay: score, level, burgers built, chefs left, pepper charges, and
## phase banners.
##
## There is no clock here, deliberately. The original has no countdown either, and
## a clock is the one piece of furniture from the old tray game that had no place
## in this one.

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
	_text(Vector2(w * 0.5 - 30, PAD + 8), "%06d" % GameState.score, Cfg.COL_PEPPER, FONT_SIZE + 1)
	_text(Vector2(PAD, PAD + 18), "BURGERS %d/%d" % [GameState.burgers_done, GameState.burgers_target],
		Color("f4f4ff"), FONT_SIZE)

	_draw_chefs(Vector2(PAD, PAD + 24))
	_draw_pepper(Vector2(w - PAD - 8, PAD + 24))

	if game != null:
		if game.paused:
			_banner("PAUSED", Color("f4f4ff"))
		else:
			match game.phase:
				Game.Phase.INTRO:
					_level_card()
				Game.Phase.LEVEL_CLEAR:
					_banner("LEVEL CLEAR!", Cfg.COL_BONUS)
				Game.Phase.GAME_OVER:
					_banner("GAME OVER", Color("e2453c"))
				Game.Phase.ALL_CLEAR:
					_banner("YOU WIN!", Cfg.COL_PEPPER)
		_draw_popups()


## Spare chefs, as little hats.
func _draw_chefs(at: Vector2) -> void:
	for i in mini(GameState.chefs, 6):
		var x := at.x + i * 10.0
		draw_rect(Rect2(x, at.y, 8, 8), Cfg.PLAYER_COOK_HAT)
		draw_rect(Rect2(x, at.y, 8, 8), Cfg.COL_OUTLINE, false, 1.0)
		draw_rect(Rect2(x + 1, at.y + 5, 6, 3), Cfg.PLAYER_COOK_SHIRT)


## Pepper charges, as little jars. This is the one piece of information the chef
## actually has to watch, because it is the difference between a nasty being a
## death and a nasty being a five second breather.
func _draw_pepper(at: Vector2) -> void:
	var charges := 0
	if game != null and game.player != null and is_instance_valid(game.player):
		charges = game.player.pepper_left
	for i in charges:
		var x := at.x - i * 11.0
		draw_rect(Rect2(x - 4, at.y, 8, 9), Cfg.COL_OUTLINE)
		draw_rect(Rect2(x - 3, at.y + 1, 6, 7), Cfg.COL_PEPPER)
		draw_rect(Rect2(x - 4, at.y, 8, 2), Cfg.COL_BONUS)
	if charges == 0:
		_text(Vector2(at.x - 30, at.y + 8), "NO PEPPER", Color("6a6a90"), FONT_SIZE - 1)


## The card that names the level and the job before the chef moves.
func _level_card() -> void:
	if game.level == null:
		return
	var card := Rect2(size.x * 0.5 - 68.0, size.y * 0.5 - 30.0, 136.0, 60.0)
	draw_rect(card, Cfg.COL_CARD)
	draw_rect(card, Cfg.COL_CARD_EDGE, false, 2.0)

	_centered(card.position.y + 16.0, "LEVEL %d" % (GameState.level_index + 1), Cfg.COL_PEPPER, FONT_SIZE + 2)
	_centered(card.position.y + 30.0, game.level.name, Color("f4f4ff"), FONT_SIZE)
	_centered(card.position.y + 46.0, "BUILD %d BURGERS" % GameState.burgers_target, Cfg.COL_BONUS, FONT_SIZE)


## Score popups, drawn where the thing happened rather than in a fixed corner so
## the eye is already looking there.
func _draw_popups() -> void:
	for p in game.popups():
		var text := String(p["text"])
		var color: Color = p["color"]
		var at: Vector2 = p["pos"]
		if at == Vector2.ZERO:
			continue
		_centered_at(at, text, color, FONT_SIZE)


func _centered(y: float, text: String, color: Color, font_size: int) -> void:
	_centered_at(Vector2(size.x * 0.5, y), text, color, font_size)


func _centered_at(mid: Vector2, text: String, color: Color, font_size: int) -> void:
	var text_w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2(mid.x - text_w * 0.5, mid.y)
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Cfg.COL_OUTLINE)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


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
