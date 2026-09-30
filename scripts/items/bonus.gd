class_name Bonus
extends Node2D
## A pickup that appears on a walk row and is taken by walking into it.
##
## Seasoning is the important one: it appears at a random spot on the board and
## picking a jar up puts one charge in the chef's jar. The jar in the HUD shows
## the charges, and a level can start with one already in it. There is no
## whole-board effect on pickup - freezing everything the moment a jar is touched
## took the timing out of the player's hands, so every jar is simply ammo for the
## forward spray, and the player decides when to spend it.

signal collected(kind: Kind)

enum Kind { PEPPER, SALT, LIFE }

const LIFE_TIME := 9.0
const POINTS := 500

var kind: Kind = Kind.PEPPER
var cell := Vector2i.ZERO
var _t := 0.0


func setup(at: Vector2i, p_kind: Kind) -> void:
	cell = at
	kind = p_kind
	position = Cfg.cell_to_pixel(at)
	_t = LIFE_TIME
	z_index = 6
	queue_redraw()


## How many seasoning charges this is worth, for the HUD.
func charges() -> int:
	return 0 if kind == Kind.LIFE else 1


func label() -> String:
	match kind:
		Kind.SALT:
			return "SALT"
		Kind.LIFE:
			return "1UP"
		_:
			return "PEPPER"


func _process(delta: float) -> void:
	# Pickups expire so they cannot be left sitting on a ledge forever, but the
	# last second blinks to warn.
	_t -= delta
	if _t <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _t < 1.5 and fposmod(_t, 0.3) > 0.15:
		return
	var box := Rect2(-5, -6, 10, 12)
	draw_rect(box.grow(1.0), Cfg.COL_OUTLINE)
	match kind:
		Kind.SALT:
			# A salt shaker, another dose of the same seasoning spray.
			draw_rect(box, Color("dfe3e8"))
			draw_rect(Rect2(-1, -6, 2, 3), Cfg.COL_OUTLINE)
			draw_rect(Rect2(-4, -1, 8, 2), Cfg.COL_OUTLINE.darkened(0.3))
		Kind.LIFE:
			# A little chef's hat for a spare life.
			draw_rect(Rect2(-5, 0, 10, 6), Cfg.PLAYER_COOK_SHIRT)
			draw_rect(Rect2(-6, -5, 12, 5), Cfg.PLAYER_COOK_HAT)
		_:
			# A pepper: red body, green stalk.
			draw_rect(box, Color("d8402f"))
			draw_rect(Rect2(-5, -6, 10, 3), Color("6fc24a"))
			draw_rect(Rect2(-2, -6, 4, 3), Color("4c9a2c"))
	queue_redraw()
