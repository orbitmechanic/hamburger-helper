class_name Board
extends Node2D
## The level grid: what is solid, what is a ladder, where a plate is, and all
## static tile drawing.
##
## Everything in the game resolves collisions against this grid rather than
## against physics bodies. That makes movement exact, deterministic, and cheap
## to reason about in tests.
##
## The interesting part is landing_spot(): where a falling ingredient comes to
## rest. That one function is the whole "walk across it and it drops a level"
## rule, including knocking down whatever is underneath.

enum Tile { EMPTY, PLATFORM, WALL, LADDER, PLATE }

const T := Cfg.TILE

## Tile type per cell, indexed y * Cfg.GRID_W + x.
var _tiles := PackedByteArray()
## Ingredients by cell. An ingredient is wide, so it holds one entry per cell
## and clearing it means clearing the whole run.
var _ingredients := {}
## The burger being built on each plate, bottom-to-top, keyed by the plate's
## leftmost cell.
var _stacks := {}
## Plates in the order they appear in the level.
var plates: Array[LevelData.Span] = []

var level: LevelData.Level
var chef_spawn := Vector2i(1, 1)
var enemy_spawns: Array[Vector2i] = []
var enemy_kinds := {}


func setup(lv: LevelData.Level) -> void:
	level = lv
	_tiles.resize(Cfg.GRID_W * Cfg.GRID_H)
	_tiles.fill(Tile.EMPTY)
	_ingredients.clear()
	_stacks.clear()
	plates = lv.plates
	chef_spawn = lv.chef
	enemy_spawns = lv.enemies.duplicate()
	enemy_kinds = lv.enemy_kinds.duplicate()

	for y in lv.map.size():
		var row: String = lv.map[y]
		for x in mini(row.length(), Cfg.GRID_W):
			_place(x, y, row[x])

	# Every plate starts with a bottom bun on it. A burger is assembled from the
	# bottom up, so this is the one part that is never in the maze: there would
	# be no way to get a second one under the rest.
	for plate in plates:
		_stacks[plate.x] = [Food.Kind.BUN_BOTTOM]

	queue_redraw()


func _place(x: int, y: int, ch: String) -> void:
	match ch:
		"#":
			_set_tile(Vector2i(x, y), Tile.PLATFORM)
		"H":
			_set_tile(Vector2i(x, y), Tile.WALL)
		"=":
			_set_tile(Vector2i(x, y), Tile.LADDER)
		LevelData.PLATE_CHAR:
			_set_tile(Vector2i(x, y), Tile.PLATE)


func _set_tile(cell: Vector2i, t: Tile) -> void:
	_tiles[cell.y * Cfg.GRID_W + cell.x] = t


func tile_at(cell: Vector2i) -> Tile:
	if not Cfg.in_grid(cell):
		return Tile.WALL
	return _tiles[cell.y * Cfg.GRID_W + cell.x] as Tile


## True when a cell stops the chef walking into it.
##
## Ingredients are deliberately not here: he walks over food, and crossing it
## fully is what knocks it down. Ladders and plates are walkable too - a plate
## is on the ground and a ladder is the way up.
func blocks_player(cell: Vector2i) -> bool:
	return tile_at(cell) in [Tile.PLATFORM, Tile.WALL]


## True when a cell holds something up, so standing on it does not mean falling.
func supports_actor(cell: Vector2i) -> bool:
	return tile_at(cell) in [Tile.PLATFORM, Tile.WALL, Tile.LADDER, Tile.PLATE]


## Whether there is something to stand on directly below a cell. Ingredients
## count: the chef walks on top of food exactly as he walks on a ledge, and when
## the food drops out from under him he falls.
func floor_below(cell: Vector2i) -> bool:
	var below := cell + Vector2i.DOWN
	if not Cfg.in_grid(below):
		return false
	return supports_actor(below) or _ingredients.has(below)


func is_ladder(cell: Vector2i) -> bool:
	return tile_at(cell) == Tile.LADDER


func is_plate(cell: Vector2i) -> bool:
	return tile_at(cell) == Tile.PLATE


# --- Ingredients -----------------------------------------------------------


func ingredient_at(cell: Vector2i) -> Ingredient:
	return _ingredients.get(cell, null)


## Claims every cell of a span for an ingredient. Returns false if any cell is
## already taken, and claims nothing in that case, so a wide ingredient can never
## end up half-placed on top of another.
func claim(cells: Array[Vector2i], ing: Ingredient) -> bool:
	for cell in cells:
		if not Cfg.in_grid(cell) or _ingredients.has(cell):
			return false
		# A part is never allowed to sit inside geometry. This is the backstop
		# behind landing_spot: if a scan ever says a part belongs somewhere it
		# cannot go, the claim is refused and the part stays where it was rather
		# than sinking into a ledge.
		if tile_at(cell) in [Tile.PLATFORM, Tile.WALL]:
			return false
	for cell in cells:
		_ingredients[cell] = ing
	return true


func release(cells: Array[Vector2i]) -> void:
	for cell in cells:
		_ingredients.erase(cell)


# --- Plates ----------------------------------------------------------------


## The stack growing on a plate, bottom-to-top. Keyed by the plate's leftmost
## cell, which is where the level put it.
func stack(plate_x: int) -> Array:
	return _stacks.get(plate_x, [])


## The row the next part dropped on this plate would come to rest at.
func stack_top_row(plate: LevelData.Span) -> int:
	return plate.y - stack(plate.x).size()


## Adds a part to a plate's burger. Returns the finished stack, so the caller can
## check whether the burger is done.
func push_to_stack(plate: LevelData.Span, kind: Food.Kind) -> Array:
	var pile: Array = _stacks.get(plate.x, [Food.Kind.BUN_BOTTOM])
	pile.append(kind)
	_stacks[plate.x] = pile
	queue_redraw()
	return pile


func burgers_done() -> int:
	var done := 0
	for plate in plates:
		if Food.stack_is_burger(stack(plate.x)):
			done += 1
	return done


# --- Falling ---------------------------------------------------------------


## Where an ingredient spanning `cells` would come to rest if it were knocked
## right now, given that it is currently held up by whatever is on row
## `support_row`.
##
## Scans straight down and stops at the first thing in the way: a ledge, another
## ingredient, or the top of a plate's burger.
##
## A part dropped off a storey lands on the storey below, which is why pushing a
## part moves it one level rather than dropping it the whole height of the level
## in a single push. The exception is the storey the part is already standing on:
## `support_row` is that ledge, so the scan starts below it and the part falls
## off the front onto whatever is next.
##
## Stops on another ingredient are the chain: the caller knocks that one too, so
## pushing the top bun of a column walks the whole column down a storey at a
## time, and doing that repeatedly walks it onto the plate.
##
## Returns {"row": int, "ingredient": Ingredient or null, "plate": Span or null}.
## "row" is where the falling ingredient ends up, which is one above the thing it
## landed on.
func landing_spot(cells: Array[Vector2i], support_row: int) -> Dictionary:
	for y in range(support_row + 1, Cfg.GRID_H):
		var hit_ing: Ingredient = null
		for cell in cells:
			if cell.x < 0 or cell.x >= Cfg.GRID_W:
				continue
			var at := Vector2i(cell.x, y)
			match tile_at(at):
				Tile.PLATFORM, Tile.WALL:
					return {"row": y - 1, "ingredient": null, "plate": null}
				Tile.PLATE:
					var plate := plate_span_at(at)
					if plate != null and _plate_blocks(plate, y):
						return {"row": y - 1, "ingredient": null, "plate": plate}
			var ing := ingredient_at(at)
			if ing != null and hit_ing == null:
				hit_ing = ing
		if hit_ing != null:
			return {"row": y - 1, "ingredient": hit_ing, "plate": null}
	# Nothing below. Unreachable with a solid floor under every column, but a
	# part that somehow got here has to be told to stay put rather than be handed
	# a row underneath the world.
	return {"row": cells[0].y, "ingredient": null, "plate": null}



## A plate's burger occupies the cells above it, growing upward, so a falling
## part is stopped by the stack rather than passing through to the plate.
func _plate_blocks(plate: LevelData.Span, y: int) -> bool:
	var size := stack(plate.x).size()
	var top := plate.y - size + 1
	return y >= top and y <= plate.y


## The plate whose column covers this cell, or null.
func plate_span_at(cell: Vector2i) -> LevelData.Span:
	for plate in plates:
		if cell.y == plate.y and cell.x >= plate.x and cell.x <= plate.right():
			return plate
	return null


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
	if _tiles.is_empty():
		return
	for y in Cfg.GRID_H:
		for x in Cfg.GRID_W:
			_draw_tile(Vector2i(x, y))
	for plate in plates:
		_draw_burger(plate)


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
		_:
			pass


func _draw_burger(plate: LevelData.Span) -> void:
	# The plate itself sits on the ground, and the burger grows upward from it.
	var plate_rect := Rect2(Vector2(plate.x, plate.y) * T, Vector2(plate.width * T, 6))
	draw_rect(plate_rect, Cfg.COL_PLATE)
	draw_rect(Rect2(plate_rect.position, Vector2(plate_rect.size.x, 2)), Cfg.COL_PLATE.darkened(0.25))

	# Bottom-to-top, so the first entry draws lowest and the lid ends up on top.
	var pile := stack(plate.x)
	for i in pile.size():
		var kind: int = pile[i]
		var r := burger_layer(plate, i)
		draw_rect(r, Food.color_of(kind))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Food.accent_of(kind))
		draw_rect(r, Cfg.COL_OUTLINE, false, 1.0)


## Where one layer of a plate's burger is drawn, counting up from the bottom.
##
## Layers are half a cell tall and are measured up from the top of the plate
## rather than taking a cell each. That is the point: a burger is as much
## decoration as it is state, and at a cell per layer a four-layer burger reached
## four rows up into the floor the chef and the nasties walk on. Only the drawing
## changed - a part still lands by joining the logical stack, and where it stops
## has not moved - so nothing about the game got easier or harder.
func burger_layer(plate: LevelData.Span, index: int) -> Rect2:
	return Rect2(
		Vector2(plate.x * T, float(plate.y * T) - float(index + 1) * Cfg.BURGER_LAYER_H),
		Vector2(plate.width * T, Cfg.BURGER_LAYER_H))
