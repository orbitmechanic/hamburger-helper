class_name LevelData
extends RefCounted
## Levels as ASCII maps, one string per row, one character per grid cell.
##
## Keeping levels as text in source means a level change shows up as a readable
## diff in `git log` instead of an opaque binary scene edit.
##
## Legend:
##   .  empty            #  platform (solid)     =  ladder
##   H  wall (solid)     T  table / plate        s  salt pile
##   b  bun dispenser    l  lettuce dispenser    t  tomato dispenser
##   c  cheese dispenser m  meat dispenser
##   P  player start     e  hot dog              p  pickle
##   o  onion
##
## Geometry rules (enforced by validate()):
##   * A platform row may contain ladder cells; ladders replace the platform at
##     their column so the player can climb through the notch.
##   * A ladder run spans from a lower floor's walkable row to the one above it.
##   * Ladder cells support the player, so stepping onto one never makes you fall.

const LEGAL_CHARS := ".#H=TsbltcmPepo"
const DISPENSER_CHARS := "bltcm"
const BLOCKING_CHARS := "#Hbltcmepo"


class Level:
	var name: String = ""
	var target: int = 3
	var seconds: float = 75.0
	var map: PackedStringArray = []


const LEVELS: Array = [
	{
		"name": "LUNCH RUSH",
		"target": 3,
		"seconds": 75.0,
		"map": [
			"################",
			"#b............l#",
			"#######=########",
			"#......=.......#",
			"#......=.......#",
			"#=..TT.=..TT...#",
			"#=#####=########",
			"#=.............#",
			"#=.............#",
			"#=.............#",
			"#=.............#",
			"#=.............#",
			"#=..TT..P.s....#",
			"################",
			"################",
		],
	},
	{
		"name": "DOUBLE SHIFT",
		"target": 5,
		"seconds": 95.0,
		"map": [
			"################",
			"#m....=.......b#",
			"######=#########",
			"#.....=........#",
			"#.=...=....TT=.#",
			"##=##########=##",
			"#.=..........=.#",
			"#.=......=.e.=.#",
			"#########=######",
			"#........=.....#",
			"#.=.TT...=..p=.#",
			"##=##########=##",
			"#.=.TT...s.P.=.#",
			"################",
			"################",
		],
	},
]


static func count() -> int:
	return LEVELS.size()


static func get_level(index: int) -> Level:
	var lv := Level.new()
	if index < 0 or index >= LEVELS.size():
		return lv
	var raw: Dictionary = LEVELS[index]
	lv.name = String(raw["name"])
	lv.target = int(raw["target"])
	lv.seconds = float(raw["seconds"])
	var rows: PackedStringArray = raw["map"]
	lv.map = rows.duplicate()
	return lv


## Returns an array of human-readable problems. Empty means the level is valid.
static func validate(lv: Level) -> PackedStringArray:
	var problems := PackedStringArray()
	if lv.map.is_empty():
		problems.append("level has no rows")
		return problems
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

	# The player must stand on something.
	var spawns := find_all(lv, "P")
	if spawns.is_empty():
		problems.append("no player start 'P'")
	for cell in spawns:
		if not _supported(lv, cell):
			problems.append("player start at %s has no floor beneath it" % cell)

	if lv.target < 1:
		problems.append("target must be at least 1")
	if lv.seconds <= 0.0:
		problems.append("seconds must be positive")

	# Everything the player must interact with has to be reachable on foot.
	var walkable := _reachable(lv)
	if not walkable.is_empty():
		for cell in find_all(lv, "T") + find_all(lv, "s"):
			if cell not in walkable:
				problems.append("cell %s is unreachable from the player start" % cell)
		for cell in find_all(lv, "b") + find_all(lv, "l") + find_all_lettuce(lv):
			if not _touching_walkable(lv, cell, walkable):
				problems.append("dispenser at %s cannot be reached from the player start" % cell)
	return problems


static func find_all_lettuce(lv: Level) -> Array[Vector2i]:
	return find_all(lv, "l") + find_all(lv, "t") + find_all(lv, "c") + find_all(lv, "m")


## Flood fill of the cells the player can walk to. Ladders are walkable,
## tables are walkable (they are counters), solid tiles and dispensers are not.
static func _reachable(lv: Level) -> Dictionary:
	var seen := {}
	var start := find_all(lv, "P")
	if start.is_empty():
		return seen
	var stack: Array[Vector2i] = [start[0]]
	seen[start[0]] = true
	var steps := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		for step in steps:
			var next: Vector2i = cell + step
			if seen.has(next):
				continue
			if next.x < 0 or next.y < 0 or next.x >= Cfg.GRID_W or next.y >= lv.map.size():
				continue
			var ch: String = lv.map[next.y][next.x]
			if BLOCKING_CHARS.contains(ch):
				continue
			seen[next] = true
			stack.append(next)
	return seen


static func _touching_walkable(lv: Level, cell: Vector2i, walkable: Dictionary) -> bool:
	for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if walkable.has(cell + step):
			return true
	return false


static func find_all(lv: Level, ch: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in lv.map.size():
		if y >= lv.map[y].length():
			continue
		var row: String = lv.map[y]
		for x in row.length():
			if row[x] == ch:
				out.append(Vector2i(x, y))
	return out


static func _supported(lv: Level, cell: Vector2i) -> bool:
	var below := cell + Vector2i.DOWN
	if below.y >= lv.map.size():
		return false
	return lv.map[below.y][below.x] in ["#", "H", "T", "="]
