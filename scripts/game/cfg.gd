extends Node
## Global configuration: grid metrics, physics layers, palette and input map.
##
## Levels are authored as ASCII maps on a discrete cell grid. Every actor in the
## game (player, ingredients, enemies) moves cell-to-cell, which keeps collision
## resolution exact and makes the whole game deterministic enough to test
## headlessly.

const TILE := 16
const GRID_W := 16
const GRID_H := 15

## Seconds spent traversing one cell at each movement speed.
const STEP_WALK := 0.125
const STEP_DASH := 0.055
const STEP_CLIMB := 0.11
const STEP_FALL := 0.075

## Seconds the level card holds before the chef takes over.
const INTRO_TIME := 2.4

const GRAVITY := 1150.0
const MAX_FALL := 520.0

# Physics layer bits (see project.godot [layer_names]).
const L_WORLD := 1 << 0
const L_PLAYER := 1 << 1
const L_SALT := 1 << 2
const L_ENEMY := 1 << 3
const L_PICKUP := 1 << 4
const L_HAZARD := 1 << 5

# Palette - a warm diner look on a dark background.
const COL_BG := Color("11111f")
const COL_PLATFORM := Color("c8a06a")
const COL_PLATFORM_DARK := Color("8a6a42")
const COL_PLATFORM_EDGE := Color("f0d0a0")
const COL_WALL := Color("4a4a6a")
const COL_LADDER := Color("e8c070")
const COL_TABLE := Color("d8d8e8")
const COL_PLATE := Color("f4f4ff")
const COL_SALT := Color("ffffff")
const COL_OUTLINE := Color("14141f")

const PLAYER_COOK_SKIN := Color("f2c8a0")
const PLAYER_COOK_SHIRT := Color("e8e8f0")
const PLAYER_COOK_HAT := Color("ffffff")
const PLAYER_COOK_PANTS := Color("3050a0")


## Registers the input map in code so the bindings live in version control as
## readable source rather than as an opaque editor blob.
func _ready() -> void:
	_add_action(&"move_left", [KEY_LEFT, KEY_A])
	_add_action(&"move_right", [KEY_RIGHT, KEY_D])
	_add_action(&"move_up", [KEY_UP, KEY_W])
	_add_action(&"move_down", [KEY_DOWN, KEY_S])
	_add_action(&"jump", [KEY_SPACE, KEY_X])
	_add_action(&"throw", [KEY_Z, KEY_C])
	_add_action(&"pause", [KEY_ESCAPE, KEY_P])
	_add_action(&"restart", [KEY_R])
	_add_action(&"confirm", [KEY_ENTER, KEY_SPACE])
	_add_joypad_buttons()


func _add_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func _add_joypad_buttons() -> void:
	_add_joy_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis(&"move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis(&"move_down", JOY_AXIS_LEFT_Y, 1.0)
	for pair in [[&"jump", JOY_BUTTON_A], [&"throw", JOY_BUTTON_X], [&"pause", JOY_BUTTON_START]]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = pair[1]
		InputMap.action_add_event(pair[0], ev)


func _add_joy_axis(action: StringName, axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


## Converts a grid cell to the pixel position of its centre.
static func cell_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5


## Converts a pixel position to the grid cell containing it.
static func pixel_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))
