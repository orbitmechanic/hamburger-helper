class_name Board
extends Node2D
## The level grid: what is solid, what is a ladder, where items rest, and all
## static tile drawing.
##
## Everything in the game resolves collisions against this grid rather than
## against physics bodies. That makes movement exact, deterministic, and cheap
## to reason about in tests.

enum Tile { EMPTY, PLATFORM, WALL, LADDER, TABLE, DISPENSER }

const T := Cfg.TILE

## Tile type per cell, indexed y * Cfg.GRID_W + x.
var _tiles := PackedByteArray()
## Resting ingredients and enemies keyed by cell.
var _occupancy := {}
## Burger stacks being assembled, keyed by the table's cell.
var _table_stacks := {}
## Dispensers keyed by cell, mapping to the food kinds they emit in order.
var _dispensers := {}
## Burger stacks that are complete but not yet credited, keyed by table cell.
var _completed := {}

var level: LevelData.Level
var salt_cells: Array[Vector2i] = []
var enemy_spawns: Array[Vector2i] = []
var player_spawn := Vector2i(1, 12)


func setup(lv: LevelData.Level) -> void:
	level = lv
	_tiles = PackedByteArray()
	_tiles.resize(Cfg.GRID_W * Cfg.GRID_H)
	_occupancy.clear()
	_table_stacks.clear()
	_dispensers.clear()
	_completed.clear()
	salt_cells.clear()
	enemy_spawns.clear()

	for y in lv.map.size():
		var row: String = lv.map[y]
		for x in mini(row.length(), Cfg.GRID_W):
			_place(x, y, row[x])

	queue_redraw()


func _place(x: int, y: int, ch: String) -> void:
	var cell := Vector2i(x, y)
	match ch:
		"#":
			_set_tile(cell, Tile.PLATFORM)
		"H":
			_set_tile(cell, Tile.WALL)
		"=":
			_set_tile(cell, Tile.LADDER)
		"T":
			_set_tile(cell, Tile.TABLE)
		"P":
			player_spawn = cell
		"s":
			salt_cells.append(cell)
		"b", "l", "t", "c", "m":
			_set_tile(cell, Tile.DISPENSER)
			_dispensers[cell] = _dispenser_kinds(ch)
		"e", "p", "o":
			enemy_spawns.append(cell)


## Dispensers cycle through these kinds, one per bump. The bun dispenser
## alternates bottom and top so both halves come from the same machine.
func _dispenser_kinds(ch: String) -> Array:
	match ch:
		"b":
			return [Food.Kind.BUN_BOTTOM, Food.Kind.BUN_TOP]
		"l":
			return [Food.Kind.LETTUCE]
		"t":
			return [Food.Kind.TOMATO]
		"c":
			return [Food.Kind.CHEESE]
		"m":
			return [Food.Kind.MEAT]
	return []


func _set_tile(cell: Vector2i, t: Tile) -> void:
	_tiles[cell.y * Cfg.GRID_W + cell.x] = t


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < Cfg.GRID_W and cell.y < Cfg.GRID_H


func tile_at(cell: Vector2i) -> Tile:
	if not in_bounds(cell):
		return Tile.WALL
	return _tiles[cell.y * Cfg.GRID_W + cell.x] as Tile


## True when a cell stops the player from walking into it. Tables are counters:
## the chef steps up onto them, so they do not block.
func blocks_player(cell: Vector2i) -> bool:
	return tile_at(cell) in [Tile.PLATFORM, Tile.WALL, Tile.DISPENSER]


## True when a cell stops a falling ingredient. Tables count here - that is what
## makes them work as assembly surfaces.
func blocks_item(cell: Vector2i) -> bool:
	return tile_at(cell) in [Tile.PLATFORM, Tile.WALL, Tile.DISPENSER, Tile.TABLE]


## Ladder cells hold the player up: stepping onto one must not drop you.
func supports_actor(cell: Vector2i) -> bool:
	return blocks_item(cell) or tile_at(cell) == Tile.LADDER


func is_ladder(cell: Vector2i) -> bool:
	return tile_at(cell) == Tile.LADDER


func is_dispenser(cell: Vector2i) -> bool:
	return _dispensers.has(cell)


## Returns the kinds a dispenser cycles through, or an empty array.
func dispenser_kinds(cell: Vector2i) -> Array:
	return _dispensers.get(cell, [])


# --- Occupancy -------------------------------------------------------------


func occupant_at(cell: Vector2i) -> Node2D:
	return _occupancy.get(cell, null)


func set_occupant(cell: Vector2i, node: Node2D) -> void:
	if not in_bounds(cell):
		return
	_occupancy[cell] = node


func clear_occupant(cell: Vector2i) -> void:
	_occupancy.erase(cell)


# --- Table stacks ----------------------------------------------------------


func table_stack(cell: Vector2i) -> Array:
	return _table_stacks.get(cell, [])


func push_to_table(cell: Vector2i, kind: Food.Kind) -> Array:
	var stack: Array = _table_stacks.get(cell, [])
	stack.append(kind)
	_table_stacks[cell] = stack
	queue_redraw()
	return stack


## Removes and returns the top item of a table stack, or -1 when empty.
func pop_from_table(cell: Vector2i) -> int:
	var stack: Array = _table_stacks.get(cell, [])
	if stack.is_empty():
		return -1
	var top: int = stack.pop_back()
	_completed.erase(cell)
	_table_stacks.erase(cell)
	if not stack.is_empty():
		_table_stacks[cell] = stack
	queue_redraw()
	return top


func clear_table(cell: Vector2i) -> void:
	_table_stacks.erase(cell)
	_completed.erase(cell)
	queue_redraw()


## True when the stack reads as a finished burger: a bottom bun, at least one
## filling, and a top bun on the very top.
func stack_is_burger(stack: Array) -> bool:
	if stack.size() < 3:
		return false
	if not Food.is_bun(stack[0]):
		return false
	if not Food.is_bun(stack[stack.size() - 1]):
		return false
	if Food.is_bun(stack[0]) and String(Food.def(stack[0])["bun_role"]) != "bottom":
		return false
	if String(Food.def(stack[stack.size() - 1])["bun_role"]) != "top":
		return false
	for i in range(1, stack.size() - 1):
		if Food.is_bun(stack[i]):
			return false
	return true


func mark_completed(cell: Vector2i) -> void:
	_completed[cell] = true


func is_completed(cell: Vector2i) -> bool:
	return _completed.has(cell)


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
	if _tiles.is_empty():
		return
	for y in Cfg.GRID_H:
		for x in Cfg.GRID_W:
			var cell := Vector2i(x, y)
			_draw_tile(cell)
	_draw_salt()


func _draw_tile(cell: Vector2i) -> void:
	var rect := Rect2(Vector2(cell) * T, Vector2(T, T))
	match tile_at(cell):
		Tile.PLATFORM:
			draw_rect(rect, Cfg.COL_PLATFORM)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), Cfg.COL_PLATFORM_EDGE)
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 2), Vector2(rect.size.x, 2)), Cfg.COL_PLATFORM_DARK)
		Tile.WALL:
			draw_rect(rect, Cfg.COL_WALL)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)), Cfg.COL_WALL.lightened(0.25))
		Tile.LADDER:
			draw_rect(Rect2(rect.position + Vector2(3, 0), Vector2(2, T)), Cfg.COL_LADDER)
			draw_rect(Rect2(rect.position + Vector2(T - 5, 0), Vector2(2, T)), Cfg.COL_LADDER)
			for rung in 2:
				var ry := 2 + rung * 6
				draw_rect(Rect2(rect.position + Vector2(3, ry), Vector2(T - 6, 2)), Cfg.COL_LADDER.darkened(0.15))
		Tile.DISPENSER:
			_draw_dispenser(rect)
		Tile.TABLE:
			draw_rect(Rect2(rect.position + Vector2(0, 6), Vector2(T, T - 6)), Cfg.COL_TABLE)
			draw_rect(Rect2(rect.position + Vector2(0, 6), Vector2(T, 2)), Cfg.COL_TABLE.darkened(0.3))
			draw_rect(Rect2(rect.position + Vector2(2, T - 4), Vector2(T - 4, 4)), Cfg.COL_PLATE)
		Tile.EMPTY:
			pass


func _draw_dispenser(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y - 3)), Cfg.COL_WALL.lightened(0.1))
	draw_rect(Rect2(rect.position + Vector2(0, 0), Vector2(rect.size.x, 3)), Cfg.COL_PLATFORM)
	draw_rect(Rect2(rect.position + Vector2(2, rect.size.y - 6), Vector2(rect.size.x - 4, 4)), Cfg.COL_OUTLINE)
	draw_rect(Rect2(rect.position + Vector2(2, 3), Vector2(3, 3)), Cfg.COL_PLATFORM_EDGE)


func _draw_salt() -> void:
	for cell in salt_cells:
		var base := Vector2(cell) * T + Vector2(T, T) * 0.5
		draw_rect(Rect2(base + Vector2(-6, -3), Vector2(12, 8)), Cfg.COL_SALT)
		draw_rect(Rect2(base + Vector2(-6, -3), Vector2(12, 2)), Cfg.COL_SALT.darkened(0.15))
		draw_rect(Rect2(base + Vector2(-3, 3), Vector2(6, 2)), Cfg.COL_OUTLINE)
