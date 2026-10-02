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

## How far a bun's domed corners are rounded, in pixels, and over how many rows.
## Two rows of a half-cell layer is the most curve that leaves pixels either side
## of it to draw the outline in.
const BUN_ROUND := 2

## How tall the highlight strip along the top of a burger layer is.
const ACCENT_H := 2

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
## Where the chef comes back to after being caught, which is not where he started
## the level. See respawn_cell().
var respawn_spawn := Vector2i(1, 1)
## Which level's brand theme the tiles are drawn in, so a level looks like a
## restaurant. Resolved from the level's own name in setup(), so a board cannot
## be drawn in a palette its level did not ask for. See Cfg.BRANDS and
## _brand_style().
var _brand := 0


func setup(lv: LevelData.Level) -> void:
	level = lv
	_brand = Cfg.brand_index(lv.brand)
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

	# After the map is parsed, not before: this reads the tiles to find somewhere to
	# stand, and asked any earlier every cell is still EMPTY and it picks a wall.
	respawn_spawn = _find_respawn_cell()

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


## The centre of the bottom floor: where the chef comes back to after a death.
##
## Every level was sending him back to the cell the level was authored to start him
## in, which on all three was off to one side. That reads as the level restarting
## rather than the chef being put back on his feet, and on a level whose bottom
## floor starts further right it walked him a long way back from wherever he
## actually died. The middle of the floor is the same on every level and is where
## the eye already is, since the whole board is built around it.
##
## Scans the bottom walkable row and takes the middle cell that is not a wall, a
## ledge or a plate, so a level that hangs a platform across the middle drops him
## just clear of it rather than inside it. Falls back to the level's own spawn if a
## level has no floor at all to speak of, which is better than returning a cell in
## a wall and leaving the chef stuck in it.
func _find_respawn_cell() -> Vector2i:
	var row := Cfg.GRID_H - 1
	# The bottom row is a wall on every level so far; the floor is the row above
	# it. Walk up until a row has somewhere to stand rather than assuming the
	# depth, so a level with a thicker base still works.
	while row > 0 and not _row_has_a_stand(row):
		row -= 1
	var open: Array[Vector2i] = []
	for x in Cfg.GRID_W:
		var cell := Vector2i(x, row)
		if not blocks_player(cell) and tile_at(cell) != Tile.PLATE:
			open.append(cell)
	if open.is_empty():
		return chef_spawn
	return open[open.size() / 2]


## Whether any cell of a row is somewhere an actor can stand.
func _row_has_a_stand(row: int) -> bool:
	for x in Cfg.GRID_W:
		if not blocks_player(Vector2i(x, row)):
			return true
	return false


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


## Which brand this board is drawn in, as an index into Cfg.BRANDS. Public because
## it is the one piece of the board's appearance that is not visible in a
## collision query, and the suite has to be able to ask which palette a level
## resolved to without reading pixels.
func brand_index() -> int:
	return _brand


## The tile colours for this level's brand. See Cfg.BRANDS.
func _brand_style() -> Dictionary:
	return Cfg.BRANDS[clampi(_brand, 0, Cfg.BRANDS.size() - 1)]


func _draw_tile(cell: Vector2i) -> void:
	var rect := Rect2(Vector2(cell) * T, Vector2(T, T))
	var style := _brand_style()
	match tile_at(cell):
		Tile.PLATFORM:
			# Body, then the brand band across the middle, then the lit lip on top
			# and the shadow underneath. The band is what carries the identity: three
			# rectangles, one of them placed differently, is enough.
			draw_rect(rect, style["body"])
			draw_rect(Rect2(rect.position + Vector2(0, T / 3),
					Vector2(rect.size.x, T / 3)), style["band"])
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), style["edge"])
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 2),
					Vector2(rect.size.x, 2)), style["dark"])
		Tile.WALL:
			draw_rect(rect, style["wall"])
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)),
					(style["wall"] as Color).lightened(0.25))
		Tile.LADDER:
			draw_rect(Rect2(rect.position + Vector2(3, 0), Vector2(2, T)), style["ladder"])
			draw_rect(Rect2(rect.position + Vector2(T - 5, 0), Vector2(2, T)), style["ladder"])
			for rung in 2:
				var ry := 2 + rung * 6
				draw_rect(Rect2(rect.position + Vector2(3, ry), Vector2(T - 6, 2)),
						(style["ladder"] as Color).darkened(0.15))
		_:
			pass


func _draw_burger(plate: LevelData.Span) -> void:
	# The plate itself sits on the ground, and the burger grows upward from it. It
	# follows the brand rather than being the one white thing on the board, so a
	# plate reads as part of the restaurant the level is drawn in.
	var style := _brand_style()
	var plate_rect := Rect2(Vector2(plate.x, plate.y) * T, Vector2(plate.width * T, 6))
	draw_rect(plate_rect, style["plate"])
	draw_rect(Rect2(plate_rect.position, Vector2(plate_rect.size.x, 2)),
			(style["plate"] as Color).darkened(0.25))

	# Bottom-to-top, so the first entry draws lowest and the lid ends up on top.
	var pile := stack(plate.x)
	for i in pile.size():
		_draw_burger_layer(plate, i, pile[i])


## How far in from each side a layer's row is drawn, top row first.
##
## A bun is not a box, and the corners that tell you so are the ones facing away
## from the burger: a lid is domed, so its top corners round off, and a base sits
## flat, so its bottom corners round off. They are the corners against the sky and
## against the plate, which is where a rectangle looks like a rectangle.
##
## One pixel per row over two rows, which is as much curve as a half-cell layer has
## room for: any more and the bun loses the corners a burger is read by, and the
## outline has no pixels left to be drawn in.
static func _layer_insets(kind: int, h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(h)
	var role: String = Food.DEFS[kind]["bun_role"]
	var rounded := mini(BUN_ROUND, h)
	for i in rounded:
		# A lid rounds off the top, a base the bottom, and everything else squares
		# up. Both are one pixel per row, so the step is even rather than a curve
		# that has to be faked.
		match role:
			"top":
				out[i] = BUN_ROUND - i
			"bottom":
				out[h - 1 - i] = BUN_ROUND - i
	return out


## The rows of a layer grouped into runs that share an inset, so the flat middle of
## a bun is one rect and only the rounded corners cost anything.
static func _inset_runs(insets: PackedInt32Array) -> Array:
	var out := []
	var i := 0
	while i < insets.size():
		var j := i
		while j + 1 < insets.size() and insets[j + 1] == insets[i]:
			j += 1
		out.append({"y": i, "h": j - i + 1, "inset": insets[i]})
		i = j + 1
	return out


## One layer of a plate's burger.
##
## Everything drawn here follows the layer's silhouette rather than its bounding
## box, which is why the silhouette is worked out first: the fill, the highlight
## along the top, the texture and the outline all have to agree about where the
## corners were cut. Stroking a rectangle would put a hard corner back on exactly
## the pixels the rounding removed.
func _draw_burger_layer(plate: LevelData.Span, index: int, kind: int) -> void:
	var r := burger_layer(plate, index)
	var insets := _layer_insets(kind, r.size.y)
	var runs := _inset_runs(insets)
	for run in runs:
		var x := r.position.x + int(run["inset"])
		var w := int(r.size.x) - int(run["inset"]) * 2
		if w <= 0:
			continue
		var y := r.position.y + int(run["y"])
		draw_rect(Rect2(x, y, w, int(run["h"])), Food.color_of(kind))
		# The highlight is the same two-row strip as before, but clipped to the run
		# it falls in so it stops at a rounded corner rather than overhanging it.
		if int(run["y"]) < ACCENT_H:
			var h := mini(int(run["h"]), ACCENT_H - int(run["y"]))
			draw_rect(Rect2(x, y, w, h), Food.accent_of(kind))
	_draw_burger_texture(kind, r, insets)
	_draw_burger_outline(r, runs)


## The texture over a layer, clipped to the layer.
##
## A mark is a single pixel, and the clip is the silhouette rather than the bounding
## box: a speck sitting where a rounded corner was cut away would be a speck on the
## background, which is the one way a texture makes a bun look mouldy.
func _draw_burger_texture(kind: int, r: Rect2, insets: PackedInt32Array) -> void:
	if not Food.has_texture(kind):
		return
	# One row in, so the top pixel of the layer is the highlight's to own.
	var y0 := ACCENT_H
	var color := Food.texture_of(kind)
	var w := int(r.size.x)
	var h := int(r.size.y)
	for y in range(y0, h):
		for x in w:
			if x < insets[y] or x >= w - insets[y]:
				continue
			if Food.texture_at(kind, x, y):
				draw_rect(Rect2(r.position + Vector2(x, y), Vector2.ONE), color)


## The layer's edge, drawn as the edge it is: the sides of every run and the full
## width of the first and last row.
func _draw_burger_outline(r: Rect2, runs: Array) -> void:
	var line := Cfg.COL_OUTLINE
	for i in runs.size():
		var run: Dictionary = runs[i]
		var x := r.position.x + int(run["inset"])
		var w := int(r.size.x) - int(run["inset"]) * 2
		if w <= 0:
			continue
		var y := r.position.y + int(run["y"])
		draw_rect(Rect2(x, y, 1, int(run["h"])), line)
		draw_rect(Rect2(x + w - 1, y, 1, int(run["h"])), line)
		# The topmost and bottommost rows are closed off end to end, which is the
		# step the rounding is made of.
		if i == 0:
			draw_rect(Rect2(x, y, w, 1), line)
		if i == runs.size() - 1:
			draw_rect(Rect2(x, y + int(run["h"]) - 1, w, 1), line)



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
