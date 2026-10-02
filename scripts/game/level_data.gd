class_name LevelData
extends RefCounted
## Levels as ASCII maps, one string per row, one character per grid cell.
##
## Keeping levels as text in source means a level change shows up as a readable
## diff in `git log` instead of an opaque binary scene edit.
##
## Legend:
##   .  empty            #  platform (solid)     =  ladder
##   H  wall (solid)     O  plate (holds one burger)
##   b  bottom bun       t  top bun
##   m  patty            l  lettuce             r  tomato
##   @  chef start       1  hot dog  2  fried egg  3  pickle
##
## A horizontal run of one character is one object, and its width is the length
## of the run: "mm" is a single patty two cells wide, not two one-cell patties.
## This is what lets a level author make a wide bun and a narrow slice of tomato
## while keeping the map one character per cell.
##
## Geometry rules (enforced by validate()):
##   * A ladder cell replaces the platform at its column, so the chef can stand
##     at the walk row above it and climb through.
##   * An ingredient rests on the walk row above a platform, in the same cell the
##     chef walks in - he walks over food, which is what knocking it down means.
##   * Ledges are solid to the chef and transparent to falling food, so a part
##     pushed off any storey falls the whole height of the level to the plate.
##     A burger's parts are therefore stacked in one column above its plate, and
##     the way to move them is from the top down: the cascade carries the lot.
##   * A plate sits on the ground floor. The burger on it grows upward from the
##     plate, so the column above a plate must stay clear for as many layers as
##     that burger needs.
##   * The ground storey is tall on purpose. Ledges are on rows 1/4/7/14, so rows
##     8..12 are open floor above the plates on row 13, and a finished burger
##     sits in that space without standing in any walkway. Putting a ledge on
##     row 10 instead, as an earlier version did, capped every burger at two
##     layers and made all three levels impossible to finish.
##   * Every ingredient must sit in some plate's column, or it can never reach a
##     plate and the level cannot be finished.

const LEGAL_CHARS := ".#H=Obtmlr@123"
const INGREDIENT_CHARS := "btmlr"
const PLATE_CHAR := "O"
const LADDER_CHAR := "="
const CHEF_CHAR := "@"
const ENEMY_CHARS := "123"
const SOLID_CHARS := "#H"

## How far a nasty has to start from the chef, in cells, counted as the number of
## steps between them on the grid rather than as a straight line.
const ENEMY_MIN_DISTANCE := 8

## Map char to Food.Kind, for the ingredient runs.
const INGREDIENT_KINDS := {
	"b": Food.Kind.BUN_BOTTOM,
	"t": Food.Kind.BUN_TOP,
	"m": Food.Kind.PATTY,
	"l": Food.Kind.LETTUCE,
	"r": Food.Kind.TOMATO,
}

## Map char to Enemy.Kind, for spawns.
const ENEMY_KIND := {
	"1": Enemy.Kind.HOTDOG,
	"2": Enemy.Kind.EGG,
	"3": Enemy.Kind.PICKLE,
}


## One horizontal run of one character: an ingredient, a plate, or a ladder.
class Span extends RefCounted:
	var ch: String = "."
	var x: int = 0
	var width: int = 1
	var y: int = 0

	func right() -> int:
		return x + width - 1

	func cells() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for i in width:
			out.append(Vector2i(x + i, y))
		return out

	func overlaps(other: Span) -> bool:
		return x <= other.right() and other.x <= right()


class Level:
	var name: String = ""
	## Which of Cfg.BRANDS this level's tiles are drawn in, by name. Authored
	## rather than by index so a level reads as a place rather than as a number,
	## and so adding a brand to the middle of Cfg.BRANDS does not silently
	## restyle the levels after it. validate() rejects a name that is not in
	## Cfg.BRANDS, so a typo fails the suite rather than quietly falling back to
	## the first one.
	var brand: String = ""
	var map: PackedStringArray = []
	## Every plate, in reading order. The burger each one is building is derived
	## from the ingredients standing in its column, so a level never has to state
	## the recipe twice and the two can never disagree.
	var plates: Array[Span] = []
	## Every ingredient already placed in the maze.
	var ingredients: Array[Span] = []
	var chef: Vector2i = Vector2i(1, 1)
	var enemies: Array[Vector2i] = []
	var enemy_kinds: Dictionary = {}

	## The recipe for a plate: bottom bun first, then whatever stands in its
	## column ordered from the ground up. Because ingredients can only fall, a
	## plate collects them in that same order, so the map doubles as the recipe.
	func recipe(plate: Span) -> Array:
		var column: Array[Span] = []
		for ing in ingredients:
			if ing.overlaps(plate):
				column.append(ing)
		column.sort_custom(func(a: Span, b: Span) -> bool: return a.y > b.y)
		var out: Array = [Food.Kind.BUN_BOTTOM]
		for ing in column:
			out.append(INGREDIENT_KINDS[ing.ch])
		return out

	## How many ingredients are still up in the maze, and therefore how many
	## pushes are left in the level however they are distributed.
	func ingredients_left() -> int:
		return ingredients.size()


## The three levels.
##
## Generated once by tools/make_levels.gd and pasted here, because a level should
## be readable in a diff and editable by hand rather than built at runtime. The
## shape of each is three ingredient storeys on walk rows 0/3/6 over ledges on
## rows 1/4/7, then a tall open ground storey on rows 8..13 above the ledge on
## row 14, with the plates along the ground and a burger's parts stacked in one
## plate's column - the plate collects them in the order they fall, which is the
## order the recipe needs.
##
## The nasties are spread over the three ingredient storeys, one of each kind, and
## start as far from the chef as the maze allows. The ground storey is deliberately
## left clear of them. It is the one lane in the level the chef cannot pass anybody in
## - it is a cell wide, with the plates along it and the parts to be carried down onto
## them - so a nasty walking it turns the ground from somewhere to travel into a place
## the chef can be shut inside, and there is no way past it but pepper. Measured over
## fifteen runs that was the only thing reliably killing the chef inside ten seconds;
## the same three levels with the ground clear survive the whole window. The storeys
## above it are full width, so a nasty there is something to outrun rather than
## something to be trapped by.
const LEVELS: Array = [
	{
		"name": "LUNCH RUSH",
		"brand": "the arches",
		"map": [
			".ttt..ttt..ttt.1",
			"####=#########=#",
			"....=.........=.",
			".lll..rrr2.lll..",
			"#####=######=###",
			".....=......=...",
			".mmm3.mmm..mmm..",
			"=#########=####=",
			"=.........=....=",
			"=.........=....=",
			"=.........=....=",
			"=.........=....=",
			"=.........=....=",
			"@OOO..OOO..OOO..",
			"################",
		],
	},
	{
		"name": "DOUBLE SHIFT",
		"brand": "the flame",
		"map": [
			"....ttt..ttt1ttt",
			"#####=########=#",
			".....=........=.",
			"ttt.lll.2rrr.lll",
			"#######=#######=",
			".......=.......=",
			"mmm.mmm3.mmm.mmm",
			"###=########=###",
			"...=........=...",
			"...=........=...",
			"...=........=...",
			"...=........=...",
			"...=........=...",
			"OOO@OOO..OOO.OOO",
			"################",
		],
	},
	{
		"name": "DINNER RUSH",
		"brand": "the girl",
		"map": [
			".ttt..ttt......3",
			"#########=#####=",
			".........=.....=",
			".lll..rrr..ttt1.",
			"=#########=#####",
			"=.........=.....",
			".mmm2.mmm..mmm..",
			"=####=########=#",
			"=....=........=.",
			"=....=........=.",
			"=....=........=.",
			"=....=........=.",
			"=....=........=.",
			"@OOO..OOO..OOO..",
			"################",
		],
	},
]


static func count() -> int:
	return LEVELS.size()


static func get_level(index: int) -> Level:
	if index < 0 or index >= LEVELS.size():
		return Level.new()
	var raw: Dictionary = LEVELS[index]
	return from_map(String(raw["name"]), raw["map"] as PackedStringArray,
			String(raw.get("brand", "")))


## Builds a level from a map. Shared by get_level and the tests, so a synthetic
## level in a test goes through exactly the same indexing as a shipped one.
static func from_map(level_name: String, map: PackedStringArray,
		brand: String = "") -> Level:
	var lv := Level.new()
	lv.name = level_name
	lv.brand = brand
	lv.map = map.duplicate()
	_index(lv)
	return lv


## Walks the map once and pulls out every run, spawn and plate. Doing this in one
## pass means Board never has to re-derive geometry the level already knows.
static func _index(lv: Level) -> void:
	lv.plates.clear()
	lv.ingredients.clear()
	lv.enemies.clear()
	lv.enemy_kinds.clear()
	var claimed := {}

	for y in lv.map.size():
		var row: String = lv.map[y] if y < lv.map.size() else ""
		var x := 0
		while x < row.length():
			var ch := row[x]
			if ch == "@":
				lv.chef = Vector2i(x, y)
			elif ENEMY_CHARS.contains(ch):
				lv.enemies.append(Vector2i(x, y))
				lv.enemy_kinds[Vector2i(x, y)] = ENEMY_KIND[ch]
			# A run is consumed in one go so the cells inside it are not
			# re-read as the start of another object.
			var run := 1
			while x + run < row.length() and row[x + run] == ch:
				run += 1
			if INGREDIENT_CHARS.contains(ch):
				var span := Span.new()
				span.ch = ch
				span.x = x
				span.y = y
				span.width = run
				lv.ingredients.append(span)
				for i in run:
					claimed[Vector2i(x + i, y)] = true
			elif ch == PLATE_CHAR:
				var plate := Span.new()
				plate.ch = ch
				plate.x = x
				plate.y = y
				plate.width = run
				lv.plates.append(plate)
			x += run


## Returns an array of human-readable problems. Empty means the level is valid.
static func validate(lv: Level) -> PackedStringArray:
	var problems := PackedStringArray()
	if lv.map.is_empty():
		problems.append("level has no rows")
		return problems
	# A level that names no brand is fine - it draws in the first one - but one
	# that names a brand that does not exist is a typo, and Cfg.brand_index would
	# swallow it and draw the level in the wrong colours. Caught here so it cannot
	# reach a capture.
	if lv.brand != "" and not Cfg.has_brand(lv.brand):
		problems.append("level names brand '%s', which is not one of: %s" % [
			lv.brand, ", ".join(Cfg.brand_names())])
	if lv.map.size() != Cfg.GRID_H:
		problems.append("level has %d rows, expected %d" % [lv.map.size(), Cfg.GRID_H])
	for y in lv.map.size():
		var row: String = lv.map[y]
		if row.length() != Cfg.GRID_W:
			problems.append("row %d is %d chars wide, expected %d" % [y, row.length(), Cfg.GRID_W])
			continue
		for x in row.length():
			var c := row[x]
			if not LEGAL_CHARS.contains(c):
				problems.append("row %d col %d has illegal char '%s'" % [y, x, c])

	if lv.plates.is_empty():
		problems.append("no plates: there would be nothing to build a burger on")
	if lv.ingredients.is_empty():
		problems.append("no ingredients in the maze")

	# Every plate must have a buildable recipe, and every ingredient must be able
	# to reach a plate. Both are checked here rather than discovered in play,
	# because an unfinishable level cannot be tested by beating it.
	for plate in lv.plates:
		var recipe := lv.recipe(plate)
		if not Food.stack_is_burger(recipe):
			problems.append("plate at %s needs a stack that is not a burger: %s" % [
				_plate_label(plate), _recipe_label(recipe)])
		problems.append_array(_clearance_problems(lv, plate, recipe.size()))
	for ing in lv.ingredients:
		var home: Span = null
		for plate in lv.plates:
			if ing.overlaps(plate):
				home = plate
				break
		if home == null:
			problems.append("ingredient '%s' at row %d cols %d-%d is not above any plate"
				% [ing.ch, ing.y, ing.x, ing.right()])

	if not _has_char(lv, CHEF_CHAR):
		problems.append("no chef start '%s'" % CHEF_CHAR)
	for cell in lv.enemies:
		if not _supported(lv, cell):
			problems.append("enemy at %s has no floor beneath it" % cell)
	if not _has_char(lv, CHEF_CHAR) or not _supported(lv, lv.chef):
		problems.append("chef start has no floor beneath it")

	# Nasties all starting on the bottom floor turns the opening of a level into
	# a walk along one row, and starting on top of the chef is just unfair. They
	# have to be spread over the storeys and start well clear of him.
	if _has_char(lv, CHEF_CHAR):
		for cell in lv.enemies:
			var away := absi(cell.x - lv.chef.x) + absi(cell.y - lv.chef.y)
			if away < ENEMY_MIN_DISTANCE:
				problems.append("enemy at %s starts only %d cells from the chef, minimum is %d"
					% [cell, away, ENEMY_MIN_DISTANCE])
		var rows := {}
		for cell in lv.enemies:
			rows[cell.y] = true
		if lv.enemies.size() > 1 and rows.size() < 2:
			problems.append("all %d enemies start on row %d: spread them over the storeys"
				% [lv.enemies.size(), lv.enemies[0].y])

	# Ladders are the only way between rows, so a run that does not join two
	# standable rows is a trap rather than a shortcut.
	for run in _ladder_runs(lv):
		var x: int = run["x"]
		var top: int = run["top"]
		var bottom: int = run["bottom"]
		if not _standable(lv, Vector2i(x, bottom + 1)):
			problems.append(
				"ladder in column %d rows %d-%d has no floor at its foot" % [x, top, bottom])
		if not _traversable(lv, Vector2i(x, top - 1)):
			problems.append(
				"ladder in column %d rows %d-%d goes nowhere at its head" % [x, top, bottom])

	# The chef has to be able to walk to every ingredient, and all the way across
	# it - crossing only part of a wide part is not a push. Otherwise a level can
	# be unwinnable with the map looking fine.
	var walkable := _reachable(lv)
	for ing in lv.ingredients:
		for cell in ing.cells():
			if not walkable.has(cell):
				problems.append("ingredient '%s' row %d col %d cannot be reached by the chef"
					% [ing.ch, ing.y, cell.x])
				break
	for cell in lv.enemies:
		if not walkable.has(cell) and not walkable.has(cell + Vector2i.UP):
			problems.append("enemy at %s can never leave its floor" % cell)
	return problems


## Whether the map contains a character anywhere. The whole map is joined once
## and asked with String.contains() rather than rescanned row by row, which also
## gets the "row is shorter than expected" case for free because joining an
## uneven map is still a valid string.
static func _has_char(lv: Level, ch: String) -> bool:
	return "\n".join(lv.map).contains(ch)


## Whether a plate's column has the room to grow a burger of `layers` parts.
##
## A burger on a plate grows upward, one row per layer, across the plate's whole
## width, and a part cannot fall through a platform. So the rows a burger needs
## must be open floor: if a ledge crosses the column, the burger stops growing
## under it and every part above that row can never reach the plate, which leaves
## a level that looks playable and can never be finished.
static func _clearance_problems(lv: Level, plate: Span, layers: int) -> PackedStringArray:
	var problems := PackedStringArray()
	for layer in layers:
		var row := plate.y - 1 - layer
		if row < 0:
			return problems
		for i in plate.width:
			var ch := _char_at(lv, Vector2i(plate.x + i, row))
			if ch in SOLID_CHARS or ch == PLATE_CHAR:
				problems.append(
					"plate at %s has no room for a %d-part burger: row %d col %d is '%s'"
					% [_plate_label(plate), layers, row, plate.x + i, ch])
	return problems


static func _plate_label(plate: Span) -> String:
	return "row %d cols %d-%d" % [plate.y, plate.x, plate.right()]


static func _recipe_label(recipe: Array) -> String:
	var parts := PackedStringArray()
	for kind: int in recipe:
		parts.append(Food.display_name(kind))
	return ", ".join(parts)


## The character at a cell, or "" if the map does not cover it.
##
## The validator has to survive a malformed map - reporting "row 3 is 14 cells
## wide" is the entire reason to run it on one - so every lookup in here is
## bounds-checked rather than trusting the map to be the right shape.
static func _char_at(lv: Level, cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= lv.map.size():
		return ""
	var row: String = lv.map[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return ""
	return row[cell.x]


## Whether the chef can stand in a cell. He needs a floor: a platform, a wall, a
## plate, or the top of a ladder he has just climbed.
static func _standable(lv: Level, cell: Vector2i) -> bool:
	if not _passable(lv, cell):
		return false
	return _char_at(lv, cell + Vector2i.DOWN) in ["#", "H", "=", PLATE_CHAR]


## A cell the chef can be in. Standing somewhere, or partway up a ladder.
static func _traversable(lv: Level, cell: Vector2i) -> bool:
	return _standable(lv, cell) or _is_ladder(lv, cell)


## Ladders and platforms stop him; food does not. He walks over ingredients, and
## crossing one is what knocks it down, so an ingredient cell is walkable floor
## to him exactly as it is in Board.blocks_player().
static func _passable(lv: Level, cell: Vector2i) -> bool:
	if not Cfg.in_grid(cell):
		return false
	return not SOLID_CHARS.contains(_char_at(lv, cell))


static func _is_ladder(lv: Level, cell: Vector2i) -> bool:
	if not Cfg.in_grid(cell):
		return false
	return _char_at(lv, cell) == LADDER_CHAR


## Flood fill of the cells the chef can actually get to, modelling the two
## movements he has: walk along a row, and climb a ladder.
##
## The earlier version of this treated every non-solid cell as walkable, which
## made open air "reachable" and so could never fail - a level with a ladder
## that does not line up with the one above it looked fine and then trapped the
## chef mid-platform in play. Rows are only connected through ladders here, which
## is what makes this check worth having.
static func _reachable(lv: Level) -> Dictionary:
	var seen := {}
	if not _has_char(lv, CHEF_CHAR):
		return seen
	var stack: Array[Vector2i] = [lv.chef]
	seen[lv.chef] = true
	var sides := [Vector2i.LEFT, Vector2i.RIGHT]
	var vertical := [Vector2i.UP, Vector2i.DOWN]
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		for step in sides:
			_walk(lv, seen, stack, cell, cell + step)
		for step in vertical:
			var next: Vector2i = cell + step
			# Changing rows means climbing, and climbing means a ladder on one
			# end of the move or the other.
			if not (_is_ladder(lv, cell) or _is_ladder(lv, next)):
				continue
			_walk(lv, seen, stack, cell, next)
	return seen


static func _walk(lv: Level, seen: Dictionary, stack: Array, from: Vector2i, to: Vector2i) -> void:
	if seen.has(to) or not _traversable(lv, to):
		return
	seen[to] = true
	stack.append(to)


## Every vertical run of ladder cells, bottom-to-top, grouped by column.
##
## A run is only a route if the chef can step on at the bottom and step off at
## the top. Two ladders one column apart, or a ladder that dead-ends against a
## platform, both pass a naive "is there a ladder here" check and both strand the
## chef in play, so each run is checked against the cells just outside it.
static func _ladder_runs(lv: Level) -> Array:
	var runs: Array = []
	for x in Cfg.GRID_W:
		var y := 0
		while y < lv.map.size():
			if not _is_ladder(lv, Vector2i(x, y)):
				y += 1
				continue
			var top := y
			while y < lv.map.size() and _is_ladder(lv, Vector2i(x, y)):
				y += 1
			runs.append({"x": x, "top": top, "bottom": y - 1})
	return runs


static func _supported(lv: Level, cell: Vector2i) -> bool:
	return _char_at(lv, cell + Vector2i.DOWN) in ["#", "H", "="]
