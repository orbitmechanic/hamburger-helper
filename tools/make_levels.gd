extends SceneTree
## Level map authoring aid, not part of the game.
##
##   godot --headless --script res://tools/make_levels.gd
##
## BurgerTime levels are not really free-form: the walk rows have to line up
## with the platform rows, a ladder has to be a contiguous vertical run that
## joins two walk rows, and every ingredient has to stand in a plate's column or
## that burger can never be finished. Those are three easy things to get wrong
## by hand and impossible to eyeball on a 16x15 grid.
##
## So the shape of a level is described here as intent - which burgers exist,
## what is in each, and where the ladders go - and this prints the ASCII map.
## The output is pasted into LevelData.LEVELS, which stays the source of truth:
## a finished level should be readable in a diff, not generated at runtime.

const W := 16
const H := 15
## Solid ledges. The chef stands on the row above each of these.
const PLATFORM_ROWS := [1, 4, 7, 10, 14]
## Rows he can stand in, and the only rows ingredients may occupy.
const WALK_ROWS := [0, 3, 6, 9, 13]
## Ladder bands, as [column, lower walk row]. A run is punched through every
## row between the two walk rows it joins.
const BAND := 1


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


## `ladder_bands` is one list of columns per gap between walk rows, bottom first:
## [columns joining the ground to row 9, 9 to 6, 6 to 3, 3 to 0].
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
	for burger: Burger in burgers:
		for i in burger.width:
			g.put(burger.x + i, 13, "O")
		for i in burger.parts.size():
			# Part 0 is lowest, so it takes the deepest walk row above the plate.
			var y: int = 9 - i * 3
			for k in burger.width:
				g.put(burger.x + k, y, String(burger.parts[i]))

	for e: Array in enemies:
		g.put(int(e[0]), 13, String(e[1]))
	g.put(chef_x, 13, "@")
	return g.as_map()


func _initialize() -> void:
	var specs: Array = [
		{
			"name": "LUNCH RUSH",
			"burgers": [
				[1, 3, ["m", "t"]],
				[6, 3, ["m", "l", "t"]],
				[11, 3, ["m", "r", "l", "t"]],
			],
			"ladders": [[0, 14], [4, 10], [5, 14], [4, 9]],
			"chef": 0,
			"enemies": [[5, "1"], [9, "2"], [14, "3"]],
		},
		{
			"name": "DOUBLE SHIFT",
			"burgers": [
				[0, 2, ["m", "t"]],
				[3, 3, ["m", "l", "t"]],
				[7, 3, ["m", "l", "t"]],
				[12, 3, ["m", "r", "l", "t"]],
			],
			"ladders": [[6, 15], [5, 11], [2, 10], [4, 14]],
			"chef": 6,
			"enemies": [[2, "3"], [9, "1"], [15, "2"]],
		},
		{
			"name": "DINNER RUSH",
			"burgers": [
				[2, 3, ["m", "t"]],
				[6, 3, ["m", "l", "t"]],
				[11, 3, ["m", "r", "l", "t"]],
			],
			"ladders": [[0, 9], [5, 14], [1, 10], [0, 9]],
			"chef": 0,
			"enemies": [[4, "1"], [9, "2"], [14, "3"]],
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
			print("\t\t\t\"%s\",%s" % [row, "" if y == H - 1 else ""])
		print("\t\t],")
		print("\t},")
	quit(0)
