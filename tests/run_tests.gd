extends Node
## Headless test runner.
##
## Run with:
##   godot --headless res://tests/test_scene.tscn
##
## This is a scene rather than a `--script` entry point on purpose: a --script
## entry is compiled before autoloads are registered, so autoload identifiers
## are invisible to it. Running as a scene loads autoloads normally and keeps
## the tests exercising the same code paths the game does.
##
## Exits 0 when everything passes, 1 otherwise, so CI can gate on it.

var _passed := 0
var _failed := 0
var _current := ""


func _ready() -> void:
	_run()


func _run() -> void:
	print_rich("[b]Hamburger Helper - test suite[/b]")

	_test_levels_validate()
	_test_level_geometry()
	_test_burger_scoring()
	_test_burger_validation()
	_test_dispenser_cycle()
	await _test_assemble_burger()
	await _test_ingredient_falls_and_is_picked_up()
	await _test_take_from_table()
	await _test_walking()
	await _test_climbing()
	await _test_tray_capacity()

	print("")
	if _failed == 0:
		print_rich("[color=green]PASS[/color]  %d checks" % _passed)
		get_tree().quit(0)
	else:
		print_rich("[color=red]FAIL[/color]  %d passed, %d failed" % [_passed, _failed])
		get_tree().quit(1)


# --- Integration tests ------------------------------------------------------


## Builds a whole burger through the same calls the player makes, and checks
## the score and the burger counter.
func _test_assemble_burger() -> void:
	_begin("assembling a burger")
	var harness := _Harness.new(self)
	await harness.setup(0)
	var state = harness.state
	var B := Food.Kind
	var table_cell := harness.first_table()

	var before: int = state.score
	# Assemble standing on the counter, which is how a player delivers.
	harness.player.place(table_cell)
	harness.player.tray = [B.BUN_BOTTOM, B.LETTUCE, B.BUN_TOP]
	harness.player.tray_changed.emit()
	# Place from the top of the tray down: lid, lettuce, then the bottom bun.
	harness.player._place_one()
	harness.player._place_one()
	harness.player._place_one()

	check(harness.board.table_stack(table_cell) == [B.BUN_BOTTOM, B.LETTUCE, B.BUN_TOP],
		"the table holds bun, lettuce, lid in order",
		str(harness.board.table_stack(table_cell)))
	check(state.score == before + 100, "a finished burger scores 100",
		"score went %d -> %d" % [before, state.score])
	check(state.burgers_served == 1, "one burger counted")

	# Dropping another bun on top must not pay out twice.
	var after: int = state.score
	harness.player.tray = [B.BUN_BOTTOM]
	harness.player._place_one()
	check(state.score == after, "an already-scored table does not pay twice")
	check(not harness.board.stack_is_burger(harness.board.table_stack(table_cell)),
		"a lid under a new bun is no longer a valid burger")
	harness.teardown()


## A dropped ingredient should fall, come to rest, and be collectable.
func _test_ingredient_falls_and_is_picked_up() -> void:
	_begin("ingredients fall and are collectable")
	var harness := _Harness.new(self)
	await harness.setup(0)

	# Start in mid-air well above the floor so there is somewhere to fall.
	var floor_cell := harness.ground_cell() - Vector2i(0, 3)
	var ing := Ingredient.new()
	harness.game_node.add_child(ing)
	ing.setup(harness.board, floor_cell, Food.Kind.MEAT)

	var guard := 0
	while not ing.resting and guard < 120:
		await harness.frame()
		guard += 1
	check(ing.resting, "a dropped patty comes to rest")
	check(harness.board.occupant_at(ing.cell) == ing, "a resting ingredient occupies its cell")
	check(ing.cell.y > floor_cell.y, "it fell at least one cell")

	harness.player.place(ing.cell)
	harness.player._take_one()
	check(harness.player.tray == [Food.Kind.MEAT], "walking over it picks it up",
		str(harness.player.tray))
	check(harness.board.occupant_at(ing.cell) == null, "the cell is freed once collected")
	harness.teardown()


## Items can be taken back off a table.
func _test_take_from_table() -> void:
	_begin("taking items back off a table")
	var harness := _Harness.new(self)
	await harness.setup(0)
	var B := Food.Kind
	var cell := harness.first_table()
	harness.board.push_to_table(cell, B.BUN_BOTTOM)
	harness.board.push_to_table(cell, B.MEAT)

	harness.player.place(cell)
	harness.player._take_one()
	check(harness.player.tray == [B.MEAT], "the top item comes off the stack first", str(harness.player.tray))
	check(harness.board.table_stack(cell) == [B.BUN_BOTTOM], "the rest of the stack stays put")
	harness.teardown()


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


## Holding a direction walks the chef along the floor.
func _test_walking() -> void:
	_begin("walking")
	var harness := _Harness.new(self)
	await harness.setup(0)
	var start_x := harness.player.cell.x
	Input.action_press(&"move_right")
	await harness.frames(30)
	Input.action_release(&"move_right")
	check(harness.player.cell.x > start_x, "holding right walks the chef right",
		"x stayed at %d" % start_x)
	check(harness.player.state == Player.St.NORMAL, "he ends up standing, not mid-air")
	harness.teardown()


## The chef climbs a ladder when up is held on it.
func _test_climbing() -> void:
	_begin("climbing")
	var harness := _Harness.new(self)
	await harness.setup(0)
	var base := harness.ladder_base()
	harness.player.place(base)
	var start_y := harness.player.cell.y
	Input.action_press(&"move_up")
	await harness.frames(40)
	Input.action_release(&"move_up")
	check(harness.player.cell.y < start_y, "holding up climbs the ladder",
		"y went %d -> %d" % [start_y, harness.player.cell.y])
	harness.teardown()


## The tray holds three items and no more.
func _test_tray_capacity() -> void:
	_begin("tray capacity")
	var harness := _Harness.new(self)
	await harness.setup(0)
	var B := Food.Kind
	harness.player.tray = [B.BUN_BOTTOM, B.LETTUCE, B.MEAT]

	var cell := harness.first_table()
	harness.board.push_to_table(cell, B.CHEESE)
	harness.player.place(cell)
	harness.player._take_one()
	check(harness.player.tray.size() == Player.TRAY_MAX, "a full tray takes on nothing more",
		"tray is %s" % str(harness.player.tray))
	check(harness.board.table_stack(cell) == [B.CHEESE], "the rejected item stays on the table")
	harness.teardown()


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


## Minimal stand-in for the Game scene: builds a board and a player wired up the
## same way, so tests exercise production code paths rather than copies.
class _Harness:
	extends RefCounted

	var owner: Node
	var game_node: Node
	var board: Board
	var player: Player
	## The GameState autoload. Left untyped because the autoload cannot also
	## declare a class_name without colliding with itself.
	var state

	func _init(p_owner: Node) -> void:
		owner = p_owner

	func setup(level_index: int) -> void:
		game_node = Node2D.new()
		owner.add_child(game_node)

		state = GameState
		state.reset_run()

		var lv := LevelData.get_level(level_index)
		board = Board.new()
		game_node.add_child(board)
		board.setup(lv)

		player = Player.new()
		player.board = board
		game_node.add_child(player)
		player.place(board.player_spawn)

		player.want_ingredient.connect(func(cell: Vector2i, kind: Food.Kind) -> void:
			var ing := Ingredient.new()
			game_node.add_child(ing)
			ing.setup(board, cell, kind))
		player.served.connect(func(_points: int, _cell: Vector2i) -> void: pass)

		# One frame so _ready and any pending work settles.
		await frame()

	func teardown() -> void:
		game_node.queue_free()
		await frame()

	func frame() -> void:
		await owner.get_tree().process_frame

	func frames(count: int) -> void:
		for i in count:
			await frame()

	## The lowest cell of the first ladder column that reaches the ground.
	func ladder_base() -> Vector2i:
		var lv := board.level
		for y in range(Cfg.GRID_H - 1, -1, -1):
			var row: String = lv.map[y]
			for x in mini(row.length(), Cfg.GRID_W):
				if row[x] != "=":
					continue
				# Walk down to the bottom of this run.
				var yy := y
				while yy + 1 < Cfg.GRID_H and lv.map[yy + 1][x] == "=":
					yy += 1
				if yy == y:
					continue
				return Vector2i(x, yy)
		return board.player_spawn

	func first_table() -> Vector2i:
		for y in Cfg.GRID_H:
			var row: String = board.level.map[y]
			for x in mini(row.length(), Cfg.GRID_W):
				if row[x] == "T":
					return Vector2i(x, y)
		return Vector2i.ZERO

	## A walkable cell on the ground floor, used as a drop point.
	func ground_cell() -> Vector2i:
		var lv := board.level
		for y in range(Cfg.GRID_H - 1, -1, -1):
			var row: String = lv.map[y]
			for x in mini(row.length(), Cfg.GRID_W):
				if row[x] == "." and board.supports_actor(Vector2i(x, y)):
					return Vector2i(x, y)
		return board.player_spawn
