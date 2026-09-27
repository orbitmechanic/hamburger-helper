extends SceneTree
## Level map authoring aid, not part of the game.
##
##   godot --headless --script res://tools/make_levels.gd
##
## BurgerTime levels are not really free-form: the walk rows have to line up
## with the platform rows, a ladder has to be a contiguous vertical run that
## joins two walk rows, every ingredient has to stand in a plate's column, and
## the column above a plate has to stay clear for every layer that plate's
## burger needs. Those are four easy things to get wrong by hand and impossible
## to eyeball on a 16x15 grid.
##
## So the shape of a level is described here as intent - which burgers exist,
## what is in each, where the ladders go, where the nasties start - and this
## prints the ASCII map. The output is pasted into LevelData.LEVELS, which
## stays the source of truth: a finished level should be readable in a diff,
## not generated at runtime.
##
## The one non-obvious thing here is the shape of the grid. A burger grows
## upward from its plate, one row per layer, and it has to have room to finish
## without standing in a doorway. So the top of the maze is a regular stack of
## three ingredient storeys, and then the ground storey is deliberately tall:
## rows 8..13 are all open, which is five clear rows above a plate on row 13.
## Four layers reach row 9 and stop, still clear of the row 7 ledge and clear of
## every walk row, so a finished burger sits in the middle of the ground floor
## and blocks nothing. An earlier version put a ledge on row 10, which meant a
## burger could never get past two layers and no level could be completed.

const W := 16
const H := 15
## Solid ledges. The chef stands on the row above each of these.
const PLATFORM_ROWS := [1, 4, 7, 14]
## Rows he can stand in. Note the gap between 6 and 13: that is the ground
## storey, and it is empty on purpose so a burger has somewhere to grow.
const WALK_ROWS := [0, 3, 6, 13]
## Where a burger's parts wait, deepest first, and the order a plate collects
## them in. Three storeys, so three parts plus the base bun: a four-part burger.
const INGREDIENT_ROWS := [6, 3, 0]
## The ground row a plate sits on.
const PLATE_ROW := 13


class Grid:
	var rows := PackedStringArray()

	func _init(platform_rows: Array) -> void:
		var blank := ""
		for i in W:
			blank += "."
		for i in H:
			rows.append(blank)
		for y in platform_rows:
			rows[y] = "".lpad(W, "#")

	func put(x: int, y: int, ch: String) -> void:
		if x < 0 or x >= W or y < 0 or y >= H:
			return
		rows[y] = rows[y].substr(0, x) + ch + rows[y].substr(x + 1)

	func as_map() -> PackedStringArray:
		return rows.duplicate()


## A burger: a plate on the ground and the parts that will be stacked on it.
## `parts` is bottom-to-top excluding the base bun, which the plate provides.
class Burger:
	var x := 0
	var width := 3
	var parts: Array = []

	func _init(p_x: int, p_w: int, p_parts: Array) -> void:
		x = p_x
		width = p_w
		parts = p_parts

	func right() -> int:
		return x + width - 1


## `ladder_bands` is one list of columns per gap between walk rows, bottom first:
## [columns joining the ground to row 6, 6 to 3, 3 to 0].
##
## Columns in the ground band land in the tall storey, so they must avoid every
## plate's column or a ladder would run straight up through a finished burger.
func build(ladder_bands: Array, burgers: Array, chef_x: int, enemies: Array) -> PackedStringArray:
	var g := Grid.new(PLATFORM_ROWS)

	# Ladders are punched first: a run has to pass through the platform row, and
	# that cell is already solid by the time anything else is drawn.
	for i in ladder_bands.size():
		var lower: int = WALK_ROWS[WALK_ROWS.size() - 1 - i]
		var upper: int = WALK_ROWS[WALK_ROWS.size() - 2 - i]
		for x: int in ladder_bands[i]:
			for y in range(upper + 1, lower):
				g.put(x, y, "=")

	# Plates, then the ingredients standing above them. Parts go on the walk rows
	# from the ground up, which is the order a plate collects them in.
	#
	# Every ingredient cell is recorded as off limits, because put() will happily
	# overwrite one and a nastie standing on a bun silently shortens the burger.
	var taken := {}
	for burger: Burger in burgers:
		for i in burger.width:
			g.put(burger.x + i, PLATE_ROW, "O")
			taken[Vector2i(burger.x + i, PLATE_ROW)] = "plate"
		if burger.parts.size() > INGREDIENT_ROWS.size():
			push_error("burger at col %d has %d parts but there are only %d ingredient storeys"
				% [burger.x, burger.parts.size(), INGREDIENT_ROWS.size()])
		for i in mini(burger.parts.size(), INGREDIENT_ROWS.size()):
			for k in burger.width:
				var at := Vector2i(burger.x + k, int(INGREDIENT_ROWS[i]))
				g.put(at.x, at.y, String(burger.parts[i]))
				taken[at] = "ingredient"

	g.put(chef_x, PLATE_ROW, "@")
	taken[Vector2i(chef_x, PLATE_ROW)] = "chef"

	# Nasties are spread over the storeys rather than lined up on the ground,
	# because walking the length of the bottom floor to find them is not a
	# decision, it is a chore. They also start as far from the chef as the maze
	# allows, so the first few seconds are spent working rather than dodging.
	for e: Array in enemies:
		var at := Vector2i(int(e[0]), int(e[1]))
		if taken.has(at):
			push_error("enemy at %s would overwrite the %s there" % [at, taken[at]])
			continue
		g.put(at.x, at.y, String(e[2]))
	return g.as_map()


func _initialize() -> void:
	var specs: Array = [
		{
			"name": "LUNCH RUSH",
			"burgers": [
				[1, 3, ["m", "l", "t"]],
				[6, 3, ["m", "r", "t"]],
				[11, 3, ["m", "l", "t"]],
			],
			"ladders": [[0, 10], [5, 12], [4, 14]],
			"chef": 0,
			"enemies": [[15, 0, "1"], [9, 3, "2"], [4, 6, "3"], [14, 13, "3"]],
		},
		{
			"name": "DOUBLE SHIFT",
			"burgers": [
				[0, 3, ["m", "t"]],
				[4, 3, ["m", "l", "t"]],
				[9, 3, ["m", "r", "t"]],
				[13, 3, ["m", "l", "t"]],
			],
			"ladders": [[3, 12], [7, 15], [5, 14]],
			"chef": 3,
			"enemies": [[12, 0, "1"], [8, 3, "2"], [7, 6, "3"], [12, 13, "1"]],
		},
		{
			"name": "DINNER RUSH",
			"burgers": [
				[1, 3, ["m", "l", "t"]],
				[6, 3, ["m", "r", "t"]],
				[11, 3, ["m", "t"]],
			],
			"ladders": [[5, 14], [0, 10], [9, 15]],
			"chef": 0,
			"enemies": [[15, 0, "3"], [14, 3, "1"], [4, 6, "2"], [10, 13, "3"]],
		},
	]

	var out: Array = []
	for spec: Dictionary in specs:
		var burgers: Array = []
		for b: Array in spec["burgers"]:
			burgers.append(Burger.new(int(b[0]), int(b[1]), b[2]))
		var map := build(spec["ladders"], burgers, int(spec["chef"]), spec["enemies"])
		out.append({"name": spec["name"], "map": map})

	for lv in out:
		print("\t{")
		print("\t\t\"name\": \"%s\"," % lv["name"])
		print("\t\t\"map\": [")
		for y in (lv["map"] as PackedStringArray).size():
			var row: String = (lv["map"] as PackedStringArray)[y]
			print("\t\t\t\"%s\"," % row)
		print("\t\t],")
		print("\t},")
	quit(0)
