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
	await _test_respawn_grace()
	await _test_every_level_starts()
	await _test_level_intro()
	await _test_full_run_reaches_the_win_screen()

	print("")
	if _failed == 0:
		print_rich("[color=green]PASS[/color]  %d checks" % _passed)
		get_tree().quit(0)
	else:
		print_rich("[color=red]FAIL[/color]  %d passed, %d failed" % [_passed, _failed])
		get_tree().quit(1)


## A chef that respawns onto the pad where it just died must get a moment of
## invulnerability, otherwise an idle chef loses the whole run in a few seconds.
## Uses the harness, which has no enemies, so nothing else can land a hit.
func _test_respawn_grace() -> void:
	_begin("respawn grace")
	var harness := _Harness.new(self)
	await harness.setup(0)
	var player := harness.player
	var lives := GameState.lives

	check(player.hit(), "the first hit lands")
	check(GameState.lives == lives - 1, "the first hit cost a life")

	player._dead_t = 0.0
	await harness.frame()
	check(player.cell == player.board.player_spawn,
		"the chef is back on the spawn pad")
	check(player.state == Player.St.NORMAL, "the chef is not left dead")

	check(not player.hit(), "a hit is refused during the grace window")
	check(GameState.lives == lives - 1,
		"the refused hit cost no life",
		"lives %d, expected %d" % [GameState.lives, lives - 1])

	# Let the grace run out, then the same hit should connect again.
	player._grace_t = 0.0
	check(player.hit(), "a hit lands once the grace window is over")
	check(GameState.lives == lives - 2, "the later hit costs a life")

	# The window must actually close on its own, not just when forced shut.
	player._dead_t = 0.0
	await harness.frame()
	check(player._grace_t > 0.0, "respawning arms the grace window again")
	var guard := 0
	while player._grace_t > 0.0 and guard < 600:
		await harness.frame()
		guard += 1
	check(player._grace_t == 0.0, "the grace window closes on its own",
		"still %f after %d frames" % [player._grace_t, guard])
	harness.teardown()


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


## Every level can be built, spawned into and torn down. Teardown is the part
## that bit: queue_free is deferred, so a level that was only freed rather than
## detached kept running against the next one.
func _test_every_level_starts() -> void:
	_begin("level progression")
	# The real scene, not Game.new(). The bug this covers only exists when the
	# scene's own children are present, so a bare Game.new() can never see it.
	var game := _instantiate_game()
	add_child(game)
	var total := LevelData.count()
	for i in total:
		game.start_level(i)
		await harness_frames(3)
		var lv := LevelData.get_level(i)
		check(game.board != null, "level %d builds a board" % (i + 1))
		check(game.player != null, "level %d spawns the chef" % (i + 1))
		check(game.player.cell == game.board.player_spawn,
			"level %d starts the chef on its pad" % (i + 1),
			"chef at %s, pad at %s" % [game.player.cell, game.board.player_spawn])
		check(game.board.dispenser_cells().size() > 0,
			"level %d has somewhere to get ingredients" % (i + 1),
			"no dispensers on %s" % lv.name)
		check(game.board.table_cells().size() > 0,
			"level %d has somewhere to serve them" % (i + 1),
			"no counters on %s" % lv.name)
		check(not game.board.blocks_player(game.board.player_spawn),
			"level %d starts the chef on clear floor" % (i + 1))
		# Teardown must not take the scene's own nodes with it. It did: clearing
		# every child of Game also destroyed the HUD, so the score, the clock and
		# the level card have never been drawn at all.
		# Deliberately unguarded. The guard that used to be here was
		# "if game.actors != null", and a freed Object compares equal to null in
		# GDScript, so the check was skipped in precisely the case it existed to
		# catch: teardown that frees the actor container takes the HUD with it.
		var scene_hud = game.get_node_or_null("HudLayer/Hud")
		check(scene_hud != null and is_instance_valid(scene_hud),
			"level %d leaves the HUD alone" % (i + 1),
			"the HUD was destroyed by the previous start_level")
		check(game.get_node_or_null("Actors") != null and is_instance_valid(game.get_node_or_null("Actors")),
			"level %d leaves the actor container alone" % (i + 1),
			"the container was destroyed by the previous start_level")
		check(game.hud == scene_hud, "level %d still has its HUD wired up" % (i + 1))
		check(game.get_child_count() == 2,
			"level %d keeps the scene's own two children" % (i + 1),
			"%d children: %s" % [game.get_child_count(), str(game.get_children())])
		# The previous level's nodes must be gone, not merely pending deletion.
		var live := 0
		for child in game._actor_parent().get_children():
			if child is Board or child is Player or child is Enemy:
				live += 1
		var expected := 1 + 1 + game.board.enemy_kinds.size()
		check(live == expected, "level %d has no leftover actors" % (i + 1),
			"%d actor nodes, expected %d" % [live, expected])
		check(lv.name != "", "level %d has a name" % (i + 1))
	game.queue_free()
	await get_tree().process_frame


## The level card holds the chef still and stops the clock, then hands over.
func _test_level_intro() -> void:
	_begin("level intro")
	var game := Game.new()
	add_child(game)
	GameState.reset_run()
	game.start_level(0)
	check(game.phase == Game.Phase.INTRO, "a level opens on its card", "phase is %d" % game.phase)

	var clock := GameState.time_left
	var spawn := game.player.cell
	Input.action_press(&"move_right")
	await harness_frames(20)
	Input.action_release(&"move_right")
	check(game.player.cell == spawn, "the chef cannot walk during the card",
		"moved to %s" % game.player.cell)
	check(is_equal_approx(GameState.time_left, clock), "the clock does not run during the card",
		"clock went %.2f -> %.2f" % [clock, GameState.time_left])

	# Run out the card.
	var guard := 0
	while game.phase == Game.Phase.INTRO and guard < 600:
		await get_tree().process_frame
		guard += 1
	check(game.phase == Game.Phase.PLAYING, "the card hands over to play",
		"phase is %d after %d frames" % [game.phase, guard])

	# And the chef is live again.
	var after := game.player.cell
	Input.action_press(&"move_right")
	await harness_frames(20)
	Input.action_release(&"move_right")
	check(game.player.cell != after, "the chef moves once play starts",
		"still at %s" % game.player.cell)
	game.queue_free()
	await get_tree().process_frame


## Serve the required burgers on every level in turn and confirm the run walks
## itself to the win screen rather than stalling in a phase.
func _test_full_run_reaches_the_win_screen() -> void:
	_begin("full run")
	var game := _instantiate_game()
	add_child(game)
	GameState.reset_run()

	# The win screen calls back into the title scene, which does not exist
	# under a bare Game, so stop the run just short of that.
	var reached_all_clear := false
	var levels_seen := 0

	for level_i in LevelData.count():
		game.start_level(level_i)
		check(game.phase == Game.Phase.INTRO,
			"level %d opens on its card" % (level_i + 1))
		# Skip the card and the clear banner.
		await _run_phase_out(game, Game.Phase.PLAYING)
		check(game.phase == Game.Phase.PLAYING, "level %d is playable" % (level_i + 1),
			"phase is %d" % game.phase)

		# Serve the target through the real scoring path.
		var table := game.board.table_cells()[0]
		game.player.place(table)
		var guard := 0
		while GameState.burgers_served < GameState.burgers_target and guard < 20:
			_assemble(game)
			guard += 1
		check(GameState.burgers_served >= GameState.burgers_target,
			"level %d can actually reach its target" % (level_i + 1),
			"stalled at %d/%d" % [GameState.burgers_served, GameState.burgers_target])
		check(game.phase == Game.Phase.LEVEL_CLEAR,
			"level %d clears on its target" % (level_i + 1),
			"phase is %d at %d/%d" % [game.phase, GameState.burgers_served, GameState.burgers_target])
		levels_seen += 1

		if level_i + 1 < LevelData.count():
			await _run_phase_out(game, Game.Phase.INTRO)
			check(game.phase == Game.Phase.INTRO,
				"level %d hands over to the next card" % (level_i + 2),
				"phase is %d" % game.phase)
		else:
			await _run_phase_out(game, Game.Phase.ALL_CLEAR)
			reached_all_clear = game.phase == Game.Phase.ALL_CLEAR
			check(reached_all_clear, "the last level ends in a win",
				"phase is %d" % game.phase)

	check(levels_seen == LevelData.count(), "every level was played",
		"%d of %d" % [levels_seen, LevelData.count()])
	check(reached_all_clear, "the run reaches the win screen")
	check(GameState.level_index == LevelData.count() - 1, "the run ends on the last level",
		"stopped at level index %d" % GameState.level_index)
	game.queue_free()
	await get_tree().process_frame


## Waits for a phase timer to run down, without spinning forever if it will not.
func _run_phase_out(game: Game, until: int) -> void:
	var guard := 0
	while game.phase != until and guard < 900:
		await get_tree().process_frame
		guard += 1


## Builds and serves one perfect burger the way the player would. Clears the
## counter first: a level's target outnumbers its counters, so the same surface
## has to be reused, and a stack left complete never reads as a burger again.
func _assemble(game: Game) -> void:
	var table := game.board.table_cells()[0]
	game.board.clear_table(table)
	game.player.place(table)
	var need: Array = [Food.Kind.BUN_BOTTOM, Food.Kind.LETTUCE, Food.Kind.BUN_TOP]
	for kind in need:
		game.player.tray.append(kind)
		game.player._place_one()
		game.player.tray.clear()


## The real game scene, loaded from disk. Anything checking the scene's own
## node structure has to go through this: Game.new() has no Hud, no Actors and
## no HudLayer, and will happily pass a test the shipped scene fails.
func _instantiate_game() -> Game:
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		push_error("could not load res://scenes/game.tscn")
		return Game.new()
	var inst := packed.instantiate()
	# The win screen changes scene to the title, which is not present under a
	# bare test, so stop short of it.
	return inst


func harness_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


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
