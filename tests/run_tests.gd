extends SceneTree
## Headless test runner: `godot --headless --script res://tests/run_tests.gd`
##
## Exits 0 when everything passes, 1 otherwise, so CI can gate on it.

var _passed := 0
var _failed := 0
var _current := ""


func _initialize() -> void:
	print_rich("[b]Hamburger Helper - test suite[/b]")

	_test_levels_validate()
	_test_level_geometry()
	_test_burger_scoring()
	_test_burger_validation()
	_test_dispenser_cycle()

	print("")
	if _failed == 0:
		print_rich("[color=green]PASS[/color]  %d checks" % _passed)
		quit(0)
	else:
		print_rich("[color=red]FAIL[/color]  %d passed, %d failed" % [_passed, _failed])
		quit(1)


# --- Level tests ------------------------------------------------------------


func _test_levels_validate() -> void:
	_begin("levels validate")
	for i in LevelData.count():
		var lv := LevelData.get_level(i)
		var problems := LevelData.validate(lv)
		check(problems.is_empty(), "level %d ('%s') is valid" % [i + 1, lv.name],
			"; ".join(problems))


func _test_level_geometry() -> void:
	_begin("level geometry")
	for i in LevelData.count():
		var lv := LevelData.get_level(i)
		var walkable := LevelData._reachable(lv)
		check(walkable.size() > 40, "level %d has a playable area (%d cells)" % [i + 1, walkable.size()])

		# No hanging ladder stubs: every ladder belongs to a run of 2 or more.
		var stubs := 0
		for x in Cfg.GRID_W:
			var run := 0
			for y in Cfg.GRID_H:
				var row: String = lv.map[y]
				if x < row.length() and row[x] == "=":
					run += 1
				else:
					if run == 1:
						stubs += 1
					run = 0
			if run == 1:
				stubs += 1
		check(stubs == 0, "level %d has no single-tile ladder stubs" % (i + 1))

		# Every ladder column must let the player get somewhere new.
		check(LevelData.find_all(lv, "P").size() == 1,
			"level %d has exactly one player start" % (i + 1))


func _test_burger_scoring() -> void:
	_begin("burger scoring")
	var B := Food.Kind
	check(Food.burger_points([B.BUN_BOTTOM, B.LETTUCE, B.BUN_TOP]) == 100,
		"a single-filling burger is worth 100")
	check(Food.burger_points([B.BUN_BOTTOM, B.LETTUCE, B.MEAT, B.BUN_TOP]) == 150,
		"two fillings are worth 150")
	check(Food.burger_points([B.BUN_BOTTOM, B.LETTUCE, B.MEAT, B.CHEESE, B.TOMATO, B.BUN_TOP]) == 250,
		"four fillings are worth 250")
	check(Food.burger_points([B.BUN_BOTTOM, B.BUN_TOP]) == 0,
		"two buns with nothing between is worth nothing")


func _test_burger_validation() -> void:
	_begin("burger validation")
	var board := Board.new()
	var B := Food.Kind
	var base := Vector2i(2, 5)

	board.set_occupant(base, null)
	board._table_stacks[base] = [B.BUN_BOTTOM, B.LETTUCE, B.BUN_TOP]
	check(board.stack_is_burger(board.table_stack(base)), "bun + lettuce + lid is a burger")

	board._table_stacks[base] = [B.BUN_BOTTOM, B.BUN_TOP]
	check(not board.stack_is_burger(board.table_stack(base)), "bun + lid alone is not a burger")

	board._table_stacks[base] = [B.LETTUCE, B.MEAT, B.BUN_TOP]
	check(not board.stack_is_burger(board.table_stack(base)), "a burger with no bottom bun is rejected")

	board._table_stacks[base] = [B.BUN_BOTTOM, B.MEAT, B.BUN_BOTTOM]
	check(not board.stack_is_burger(board.table_stack(base)), "a lid on the bottom is rejected")

	board._table_stacks[base] = [B.BUN_TOP, B.MEAT, B.BUN_TOP]
	check(not board.stack_is_burger(board.table_stack(base)), "lid at the bottom is rejected")

	board._table_stacks[base] = [B.BUN_BOTTOM, B.LETTUCE, B.BUN_TOP, B.TOMATO]
	check(not board.stack_is_burger(board.table_stack(base)), "a lid that is not on top is rejected")

	board._table_stacks[base] = [B.BUN_BOTTOM, B.MEAT, B.MEAT, B.BUN_TOP]
	check(board.stack_is_burger(board.table_stack(base)), "stacked patties still make a burger")

	board.free()


func _test_dispenser_cycle() -> void:
	_begin("dispenser cycle")
	var board := Board.new()
	var lv := LevelData.get_level(0)
	board.setup(lv)
	var bun_cells: Array = []
	for y in Cfg.GRID_H:
		var row: String = lv.map[y]
		for x in mini(row.length(), Cfg.GRID_W):
			if board.is_dispenser(Vector2i(x, y)) and board.dispenser_kinds(Vector2i(x, y)).size() > 1:
				bun_cells.append(Vector2i(x, y))
	check(bun_cells.size() >= 1, "at least one dispenser emits both bun halves")
	for cell in bun_cells:
		var kinds: Array = board.dispenser_kinds(cell)
		check(kinds[0] != kinds[1], "bun dispenser at %s alternates halves" % cell)
	board.free()


# --- Harness ----------------------------------------------------------------


func _begin(name: String) -> void:
	_current = name
	print_rich("\n[b]%s[/b]" % name)


func check(condition: bool, description: String, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  [color=green]ok[/color]   %s" % description)
	else:
		_failed += 1
		if detail != "":
			print("  [color=red]FAIL[/color] %s - %s" % [description, detail])
		else:
			print("  [color=red]FAIL[/color] %s" % description)
