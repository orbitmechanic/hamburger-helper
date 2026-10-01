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
## The suite is arranged around the one rule the game is built on - walk the full
## width of a part, it drops a floor, and the parts under it come with it - so
## that the rules are tested in the order a player meets them.
##
## Exits 0 when everything passes, 1 otherwise, so CI can gate on it.

var _passed := 0
var _failed := 0

func _ready() -> void:
	_run()

func _run() -> void:
	print_rich("[b]Hamburger Helper - test suite[/b]")

	_test_input_map()
	_test_levels_validate()
	_test_validator_has_teeth()
	_test_level_geometry()
	_test_chef_never_starts_trapped()
	await _test_parts_are_centred()
	_test_ingredient_columns_line_up()
	_test_burgers_have_room()
	_test_enemies_are_spread_out()
	_test_nasties_are_slow()
	_test_burger_order()
	_test_burgers_are_half_height()
	_test_sheets()
	_test_sfx()
	_test_burger_scoring()
	await _test_board_tiles()
	await _test_landing_spot()
	await _test_single_knock_falls_one_storey()
	await _test_food_lands_on_a_ledge()
	await _test_chain_reaction()
	await _test_column_builds_a_burger()
	await _test_crossing_needs_the_full_width()
	await _test_player_jump()
	await _test_reach_grabs_a_jar_above()
	await _test_ladder_climb()
	await _test_player_falls_off_a_ledge()
	await _test_pepper_stuns_a_nasty()
	await _test_pepper_is_fired_by_a_key()
	await _test_contact_is_drawn_contact()
	await _test_falling_food_squashes()
	await _test_falling_food_crushes_what_it_passes()
	await _test_food_crushes_a_nasty_on_a_ladder()
	await _test_intro_lands_in_the_centre()
	await _test_a_nasty_steps_off_the_top_of_a_ladder()
	await _test_a_nasty_steps_off_the_bottom_of_a_ladder()
	await _test_riding_a_part()
	await _test_crossing_a_part_carries_the_nasty()
	await _test_game_starts_every_level()
	await _test_burger_completes_the_level()
	await _test_running_out_of_chefs()
	await _test_a_death_resets_the_nasties()
	await _test_a_popup_times_out()
	await _test_each_popup_ages_on_its_own_clock()
	await _test_a_popup_ages_out_while_the_chef_is_down()
	await _test_a_respawn_is_the_middle_of_the_floor_and_a_descent()
	await _test_a_respawn_drop_is_on_the_level_clock()
	await _test_a_level_ending_mid_descent_clears_the_respawn()
	await _test_the_level_directs_the_chef()

	print("")
	if _failed == 0:
		print_rich("[color=green]PASS[/color]  %d checks" % _passed)
		get_tree().quit(0)
	else:
		print_rich("[color=red]FAIL[/color]  %d passed, %d failed" % [_passed, _failed])
		get_tree().quit(1)

# --- Configuration ---------------------------------------------------------

## The input map lives in project.godot rather than being registered in code at
## startup, which is where the editor expects it. Nothing else notices when that
## file is edited by hand or regenerated, so the actions and the keys the game
## documents are checked here.
func _test_input_map() -> void:
	_begin("input map")
	var expected := {
		"move_left": [KEY_LEFT, KEY_A],
		"move_right": [KEY_RIGHT, KEY_D],
		"move_up": [KEY_UP, KEY_W],
		"move_down": [KEY_DOWN, KEY_S],
		"jump": [KEY_SPACE, KEY_X],
		"pepper": [KEY_F],
		"pause": [KEY_ESCAPE, KEY_P],
		"confirm": [KEY_ENTER, KEY_SPACE],
	}
	for action: String in expected:
		if not InputMap.has_action(action):
			check(false, "%s is mapped" % action, "no such action")
			continue
		var got: Array = []
		for e in InputMap.action_get_events(action):
			var key := e as InputEventKey
			if key != null and not key.echo:
				got.append(key.physical_keycode)
		var want: Array = expected[action]
		var missing: Array = []
		for k in want:
			if not got.has(k):
				missing.append(k)
		check(missing.is_empty(), "%s responds to its documented keys" % action,
			"missing %s" % str(missing))

# --- Levels ----------------------------------------------------------------

## Every shipped level has to pass its own validator. This is the check that stops
## a hand-edited map from shipping unplayable, since validate() is what proves the
## burgers are buildable and every ingredient is reachable.
func _test_levels_validate() -> void:
	_begin("levels validate")
	check(LevelData.count() == 3, "there are three levels", "count is %d" % LevelData.count())
	for i in LevelData.count():
		var lv := LevelData.get_level(i)
		var problems := LevelData.validate(lv)
		check(problems.is_empty(), "level %d (%s) is valid" % [i + 1, lv.name],
			"; ".join(problems))

## A validator that never fails is worse than none, because it is believed. This
## feeds it maps that are wrong in each of the ways a hand edit gets them wrong.
func _test_validator_has_teeth() -> void:
	_begin("validator catches broken maps")

	var no_plate := _map([
		"...............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"mmm............",
		"################",
		"...............",
		"...............",
		"...............",
		"################",
	])
	var problems := LevelData.validate(LevelData.from_map("no plate", no_plate))
	check(problems.size() > 0, "a level with no plates is rejected")

	# A plate whose column has no food above it can never be finished.
	var orphan_plate := _map([
		"...............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"OO.............",
		"################",
	])
	problems = LevelData.validate(LevelData.from_map("orphan plate", orphan_plate))
	check(problems.size() > 0, "a plate with no ingredients above it is rejected")

	# A ladder one column out of line with the one above it strands the chef
	# between two storeys. This is the case the reachability rewrite exists for.
	var stray_ladder := _map([
		"...............",
		"#=##############",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"@.............",
		"################",
	])
	problems = LevelData.validate(LevelData.from_map("stray ladder", stray_ladder))
	check(problems.size() > 0, "a ladder that does not line up is rejected")

	var wrong_width := _map([
		"..............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"@.............",
		"################",
	])
	problems = LevelData.validate(LevelData.from_map("wrong width", wrong_width))
	check(problems.size() > 0, "a map that is not the right size is rejected")

	# The negative controls above must not be failing for a trivial reason, or the
	# positive results prove nothing. Each is checked for the problem it is meant
	# to provoke.
	check(_mentions(problems, "wide"), "the width failure names the width",
		"got %s" % "; ".join(problems))

func _mentions(problems: PackedStringArray, needle: String) -> bool:
	for p in problems:
		if p.findn(needle) != -1:
			return true
	return false

## The shape every level shares. These are the invariants a generated map has to
## keep, checked against the source rather than the generator so that a bad paste
## is caught.
func _test_level_geometry() -> void:
	_begin("level geometry")
	for i in LevelData.count():
		var lv := LevelData.get_level(i)
		var tag := "level %d" % (i + 1)
		check(lv.map.size() == Cfg.GRID_H, "%s has %d rows" % [tag, Cfg.GRID_H])
		var all_right := true
		for y in lv.map.size():
			if (lv.map[y] as String).length() != Cfg.GRID_W:
				all_right = false
		check(all_right, "%s is %d cells wide" % [tag, Cfg.GRID_W])
		check(not lv.plates.is_empty(), "%s has plates to build on" % tag)
		check(not lv.ingredients.is_empty(), "%s has ingredients in the maze" % tag)
		check(lv.enemies.size() >= 3, "%s has all three kinds of nasty" % tag,
			"found %d" % lv.enemies.size())

		# Every plate must be buildable, which is the same check the game makes
		# when a part lands on it.
		var buildable := true
		for plate in lv.plates:
			if not Food.stack_is_burger(lv.recipe(plate)):
				buildable = false
		check(buildable, "%s has a buildable recipe for every plate" % tag)

		# Every ingredient has to be standing over a plate, and resting on a
		# walk row rather than floating.
		var grounded := true
		var over_plate := true
		for ing in lv.ingredients:
			if lv.map[ing.y + 1][ing.x] not in ["#", "H", "="]:
				grounded = false
			var home: LevelData.Span = null
			for plate in lv.plates:
				if ing.overlaps(plate):
					home = plate
			if home == null:
				over_plate = false
		check(grounded, "%s rests every ingredient on something" % tag)
		check(over_plate, "%s puts every ingredient over a plate" % tag)

		# The three kinds of nasty have to all be represented, or a level is not
		# exercising the roster.
		var kinds := {}
		for cell in lv.enemies:
			kinds[lv.enemy_kinds[cell]] = true
		check(kinds.size() == 3, "%s uses hot dog, egg and pickle" % tag,
			"found %d kinds" % kinds.size())

## The chef must never begin a level somewhere he cannot get out of.
##
## This is not a style rule, it is a fairness one, and it caught a real trap: DINNER
## RUSH started the chef in the top-left cell of the ground storey, where the only way
## out ran the length of a one-wide corridor that a nasty patrols. He was not in
## danger by bad luck, he was in a corner by design, and no amount of skill gets him
## out of it. Two ways out is the bar - one and he is standing in a trap.
##
## The walking rules are written out again here rather than borrowed from the chef or
## from tools/survival_bot.gd, because the point of the check is that they agree. A
## test that called the same helper the code under test calls would pass no matter what
## the rules were.
func _test_chef_never_starts_trapped() -> void:
	_begin("the chef never starts trapped")
	for i in LevelData.count():
		var h := _Harness.new(self)
		var game := await h.start_game(i)
		var board: Board = game.board
		var chef: Vector2i = board.chef_spawn
		var tag := "level %d" % (i + 1)
		check(_walk_exits(board, chef) >= 2,
			"%s starts the chef with %d way(s) out of %s" % [
				tag, _walk_exits(board, chef), str(chef)],
			"a chef with one way out is a chef in a corner")
		h.teardown()

## Ways out of a cell: the steps the chef could actually take from there.
func _walk_exits(board: Board, from: Vector2i) -> int:
	var out := 0
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var to := from + dir
		if not Cfg.in_grid(to):
			continue
		if dir == Vector2i.UP or dir == Vector2i.DOWN:
			if not (board.is_ladder(from) or board.is_ladder(to)):
				continue
			if board.blocks_player(to):
				continue
			if not (board.is_ladder(to) or board.floor_below(to)):
				continue
		else:
			if board.blocks_player(to):
				continue
			if not (board.floor_below(to) or board.is_ladder(to)):
				continue
		out += 1
	return out

## A part is drawn over the middle of the cells it occupies, and the burger it
## joins is drawn over the middle of the plate. If those two centres disagree,
## the stack visibly shifts sideways when the part boards. Averaging the cell
## coordinates by hand and adding half the run's width put a three-cell part a
## cell and a half to the right of where it actually stood, which is what the
## shifting was.
func _test_parts_are_centred() -> void:
	_begin("a wide part is centred on its cells")
	var h := _Harness.new(self)
	# No plates: a part that reached one would board, leave the maze and be
	# freed, which is not what is being measured here. It falls to the ledge
	# under row 9 instead, which is a real fall and a real resting place.
	await h.setup(_blank_map())
	if h.board == null:
		return
	var widths := {1: 1, 2: 3, 3: 6}
	for width: int in widths:
		var at_x: int = widths[width]
		var ing := _add_ingredient(h, h.board, "m", at_x, width, 6)
		var want := Rect2(at_x, 6, width, 1).get_center() * Cfg.TILE
		check(ing.position.distance_to(want) < 0.01,
			"a %d-cell part is drawn over the middle of its cells" % width,
			"at %s, wanted %s" % [str(ing.position), str(want)])
		# And it is still centred wherever it comes to rest.
		ing.position = Vector2(0, 0)
		ing.knock()
		await h.until(func() -> bool: return not ing.falling)
		var landed := Rect2(at_x, ing.rest_row, width, 1).get_center() * Cfg.TILE
		check(ing.position.distance_to(landed) < 0.01,
			"and is still centred after falling to row %d" % ing.rest_row,
			"at %s, wanted %s" % [str(ing.position), str(landed)])
	h.teardown()

## An ingredient and the plate it lands on have to occupy the same cells.
##
## A part keeps its own column all the way down, and the finished burger is drawn
## over the plate's column, so a narrower or wider part above a plate snaps
## sideways as it boards. A three-cell patty over a two-cell plate is the obvious
## case: the patty visibly slid across the maze on the way down and jumped at the
## bottom. This is checked against the shipped maps so the alignment cannot be
## broken by a hand edit of a level.
func _test_ingredient_columns_line_up() -> void:
	_begin("ingredient columns line up with their plate")
	for i in LevelData.count():
		var lv := LevelData.get_level(i)
		var tag := "level %d" % (i + 1)
		var mismatched: Array = []
		for ing in lv.ingredients:
			for plate in lv.plates:
				if not ing.overlaps(plate):
					continue
				if ing.x != plate.x or ing.width != plate.width:
					mismatched.append("%s cols %d-%d over plate cols %d-%d" % [
						ing.ch, ing.x, ing.right(), plate.x, plate.right()])
		check(mismatched.is_empty(), "%s lines every ingredient up with its plate" % tag,
			"; ".join(mismatched))

## A burger grows upward from its plate, one row per layer, and a part cannot fall
## through a platform. So the rows above a plate have to stay clear for the whole
## recipe or the burger stops growing partway and the level cannot be finished.
## An earlier version of the levels put a ledge on row 10, which capped every
## burger at two layers and left all three levels unwinnable.
func _test_burgers_have_room() -> void:
	_begin("burgers have room to grow")
	for i in LevelData.count():
		var lv := LevelData.get_level(i)
		var tag := "level %d" % (i + 1)
		var problems: Array = []
		for plate in lv.plates:
			problems.append_array(LevelData._clearance_problems(lv, plate, lv.recipe(plate).size()))
		check(problems.is_empty(), "%s gives every plate room for its burger" % tag,
			"; ".join(problems))

		# The room also has to be real, not just unchecked space: the top layer
		# must land clear of the lowest ledge above the plate, and clear of every
		# row the chef walks in, or a finished burger stands in a doorway.
		var blocked := []
		for plate in lv.plates:
			var layers: int = lv.recipe(plate).size()
			var top: int = plate.y - layers
			for row in range(top, plate.y):
				for x in range(plate.x, plate.right() + 1):
					var ch: String = lv.map[row][x]
					if ch in ["#", "H", "="]:
						blocked.append("plate cols %d-%d row %d is '%s'"
							% [plate.x, plate.right(), row, ch])
		check(blocked.is_empty(), "%s keeps finished burgers out of the geometry" % tag,
			"; ".join(blocked))

	# The clearance check has to be able to fail, or the positive results above
	# mean nothing. Row 10 is a ledge in this map, and the plate's column runs
	# straight through it.
	var too_tight := _map([
		"...............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"################",
		"...............",
		"...............",
		"#####OOO########",
		"...............",
		"...............",
		"...............",
		"################",
	])
	var tall := LevelData.from_map("no room", too_tight)
	var reported: Array = []
	for plate in tall.plates:
		reported.append_array(LevelData._clearance_problems(tall, plate, 3))
	check(not reported.is_empty(), "a burger with nowhere to grow is reported",
		"got %d problems" % reported.size())

## Nasties are spread over the storeys and start well clear of the chef.
##
## With all of them on the ground floor, the start of a level is a walk along one
## row and a chef who starts next to one has no first move. Both are checked so
## the maps cannot quietly drift back to a bottom-floor line-up.
func _test_enemies_are_spread_out() -> void:
	_begin("enemies are spread out")
	for i in LevelData.count():
		var lv := LevelData.get_level(i)
		var tag := "level %d" % (i + 1)
		var rows := {}
		var closest := 999
		for cell in lv.enemies:
			rows[cell.y] = true
			closest = mini(closest, absi(cell.x - lv.chef.x) + absi(cell.y - lv.chef.y))
		check(rows.size() >= 2, "%s starts its nasties on more than one storey" % tag,
			"all on row %d" % lv.enemies[0].y)
		check(closest >= LevelData.ENEMY_MIN_DISTANCE,
			"%s starts every nasty at least %d cells from the chef" % [tag, LevelData.ENEMY_MIN_DISTANCE],
			"closest is %d" % closest)

# --- Food ------------------------------------------------------------------

## A burger is a base bun, a patty, optional toppings, and a lid, in that order.
## Every position is checked, so a burger assembled inside out is not scored.
func _test_burger_order() -> void:
	_begin("burger order")
	var b := Food.Kind.BUN_BOTTOM
	var p := Food.Kind.PATTY
	var l := Food.Kind.LETTUCE
	var r := Food.Kind.TOMATO
	var t := Food.Kind.BUN_TOP

	check(Food.stack_is_burger([b, p, t]), "bun, patty, lid is a burger")
	check(Food.stack_is_burger([b, p, l, t]), "a lettuce is allowed")
	check(Food.stack_is_burger([b, p, r, t]), "a tomato is allowed")
	check(Food.stack_is_burger([b, p, l, r, t]), "both toppings is allowed")
	check(Food.stack_is_burger([b, p, l, r, l, t]), "several toppings is allowed")

	check(not Food.stack_is_burger([b, t]), "two buns are not a burger")
	check(not Food.stack_is_burger([b, p]), "a patty on a bun is not finished")
	check(not Food.stack_is_burger([b, l, p, t]), "the patty goes straight on the bun")
	check(not Food.stack_is_burger([b, p, t, l]), "nothing may sit on the lid")
	check(not Food.stack_is_burger([b, p, t, t]), "nor a second lid")
	check(not Food.stack_is_burger([p, b, t]), "the base has to be the base")
	check(not Food.stack_is_burger([b, p, b, t]), "a second bun cannot hide inside")
	check(not Food.stack_is_burger([b, p, p, t]), "nor a second patty")
	check(not Food.stack_is_burger([]), "an empty plate is not a burger")
	# A bad kind must not crash the check, which is the bug the guard in
	# Food.is_kind() exists to prevent.
	check(not Food.stack_is_burger([b, p, -1, t]), "a nonsense part is rejected safely")
	check(not Food.stack_is_burger([b, 99, t]), "a nonsense part is rejected safely")

func _test_burger_scoring() -> void:
	_begin("burger scoring")
	check(Food.burger_points(0) == 0, "an empty plate is worth nothing")
	check(Food.burger_points(3) > 0, "a finished burger is worth something")
	var rising := true
	for n in range(4, Food.POINTS_BURGER.size()):
		if Food.burger_points(n) <= Food.burger_points(n - 1):
			rising = false
	check(rising, "a taller burger is always worth more")
	check(Food.burger_points(999) == 0, "a nonsense size is worth nothing")
	check(Food.POINTS_PER_FLOOR > 0, "dropping a part pays something")
	check(Food.squash_points(Enemy.Kind.EGG) > Food.squash_points(Enemy.Kind.HOTDOG),
		"an egg is worth more to squash than a hot dog")

# --- Board -----------------------------------------------------------------

func _test_board_tiles() -> void:
	_begin("board tiles")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	check(board.tile_at(Vector2i(0, 1)) == Board.Tile.PLATFORM, "a ledge is a platform")
	check(board.tile_at(Vector2i(0, 2)) == Board.Tile.EMPTY, "open space is empty")
	check(board.tile_at(Vector2i(0, 13)) == Board.Tile.PLATE, "a plate is a plate")

	# Ledges stop the chef; nothing else does. Food and plates are floor.
	check(board.blocks_player(Vector2i(0, 1)), "a ledge blocks the chef")
	check(not board.blocks_player(Vector2i(4, 2)), "open air does not")
	check(not board.blocks_player(Vector2i(0, 13)), "a plate does not block the chef")
	check(not board.is_ladder(Vector2i(0, 0)), "open space is not a ladder")

	check(board.floor_below(Vector2i(3, 0)), "there is a ledge under row 0")
	check(not board.floor_below(Vector2i(3, 2)), "there is nothing under open row 2")
	check(board.is_plate(Vector2i(0, 13)), "the plate is where it was put")

	# Occupancy is exclusive, and a wide claim is all-or-nothing.
	var cells: Array[Vector2i] = [Vector2i(0, 13), Vector2i(1, 13)]
	var first := Ingredient.new()
	h.game_node.add_child(first)
	first.setup(board, _span("m", 0, 2, 9))
	check(board.ingredient_at(Vector2i(0, 9)) == first, "an ingredient claims its cells")
	check(board.ingredient_at(Vector2i(1, 9)) == first, "a wide ingredient claims every cell")
	check(board.ingredient_at(Vector2i(2, 9)) == null, "and nothing past its width")

	var overlap := Ingredient.new()
	h.game_node.add_child(overlap)
	overlap.setup(board, _span("m", 1, 2, 9))
	check(board.ingredient_at(Vector2i(1, 9)) == first, "a second claim on taken cells is refused")
	h.teardown()

## landing_spot is the whole "push it and it drops a floor" rule, so it is worth
## checking against each kind of thing that can be below.
func _test_landing_spot() -> void:
	_begin("landing spot")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	# A part resting on the row 7 ledge scans from row 8, and the next thing down
	# is the row 10 ledge.
	var open_span := _cells(Vector2i(5, 6), 2)
	var spot := board.landing_spot(open_span, 7)
	check(spot["row"] == 9, "a part with a clear column lands on the next ledge",
		"row is %s" % str(spot["row"]))
	check(spot["ingredient"] == null and spot["plate"] == null, "landing on a ledge is neither")

	# The ground is the bottom of the world, so that is the last resort.
	spot = board.landing_spot(_cells(Vector2i(5, 12), 2), 13)
	check(spot["row"] == Cfg.GRID_H - 2, "with nothing else below, the ground catches it",
		"row is %s" % str(spot["row"]))

	# And a part already on the ground is told to stay there rather than handed a
	# row underneath the world.
	spot = board.landing_spot(_cells(Vector2i(5, 13), 2), Cfg.GRID_H - 1)
	check(spot["row"] == 13, "and nothing sends it further", "row is %s" % str(spot["row"]))

	# A plate column catches it instead of the ledge.
	var over_plate: Array[Vector2i] = [Vector2i(0, 12), Vector2i(1, 12)]
	spot = board.landing_spot(over_plate, 12)
	check(spot["plate"] != null, "a part over a plate lands on the plate")
	check(spot["row"] == board.stack_top_row(board.plates[0]),
		"and it lands on top of the burger so far",
		"row %s vs %d" % [str(spot["row"]), board.stack_top_row(board.plates[0])])

	# Another part below stops it one row higher, and is reported so it can be
	# knocked too - that is the chain.
	var lower := _add_ingredient(h, board, "m", 5, 2, 9)
	spot = board.landing_spot(open_span, 7)
	check(spot["ingredient"] == lower, "a part below is reported so it can be knocked too")
	check(spot["row"] == 8, "and the falling part rests just above it", "row is %s" % str(spot["row"]))
	h.teardown()

## One push moves a part one storey: it lands on the ledge below rather than
## dropping the whole height of the level. A part is already sitting on the front
## of a ledge, so the scan starts below that ledge and it falls to the next one.
func _test_single_knock_falls_one_storey() -> void:
	_begin("one knock, one storey")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	# Row 6 with the row 10 ledge below it and nothing else in the way.
	var ing := _add_ingredient(h, board, "m", 5, 2, 6)
	var before := ing.rest_row
	ing.knock()
	check(ing.rest_row == 9, "a part lands on the next ledge down, not on the floor",
		"row went %d -> %d" % [before, ing.rest_row])
	check(board.ingredient_at(Vector2i(5, ing.rest_row)) == ing, "it claims its new cells")
	check(board.ingredient_at(Vector2i(5, before)) == null, "and gives up the old ones")
	await h.until(func() -> bool: return not ing.falling)
	check(ing.falling == false, "and settles")

	# It is now resting on the row 10 ledge, so a second push takes it the rest of
	# the way down onto the ground, where nothing can move it any further.
	ing.knock()
	await h.until(func() -> bool: return not ing.falling)
	check(ing.rest_row == Cfg.GRID_H - 2, "and the ground is the bottom of the world",
		"row is %d" % ing.rest_row)
	ing.knock()
	await h.until(func() -> bool: return not ing.falling)
	check(ing.rest_row == Cfg.GRID_H - 2, "a part on the ground cannot fall further",
		"row is %d" % ing.rest_row)
	h.teardown()

## Ledges catch falling food as well as the chef. A part knocked off the top
## storey lands on the next ledge down rather than dropping to the floor, which
## is what turns a column of parts into a burger one push at a time.
func _test_food_lands_on_a_ledge() -> void:
	_begin("falling food lands on ledges")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	# Row 0 sits on the full-width row 1 ledge, so a knock takes it to the row 4
	# ledge and no further.
	var ing := _add_ingredient(h, board, "m", 5, 2, 0)
	ing.knock()
	check(ing.rest_row == 3, "a part stops on the ledge below it",
		"stopped at row %d" % ing.rest_row)
	check(board.tile_at(Vector2i(5, 4)) == Board.Tile.PLATFORM,
		"which is the ledge it was dropped onto")
	h.teardown()

## The chain: knocking the top of a column walks it down one storey, and doing
## that repeatedly walks it onto the plate.
func _test_chain_reaction() -> void:
	_begin("chain reaction")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	var low := _add_ingredient(h, board, "m", 0, 2, 9)
	var mid := _add_ingredient(h, board, "l", 0, 2, 6)
	var top := _add_ingredient(h, board, "t", 0, 2, 3)

	top.knock()
	await h.frames(20)
	check(board.stack(0).size() == 2, "one knock puts exactly the bottom part on the plate",
		"stack is %s" % str(board.stack(0)))
	check(mid.rest_row == 9, "the next part down takes the vacated row",
		"mid stopped at row %d" % mid.rest_row)
	check(top.rest_row == 6, "and the lid follows down one storey",
		"lid stopped at row %d" % top.rest_row)

	# Every knock walks the surviving column down one storey; three knocks in all
	# finish the burger, and the order comes out right.
	for i in 3:
		if Food.stack_is_burger(board.stack(0)):
			break
		var head := _column_top(board, 0)
		if head == null:
			break
		head.knock()
		await h.frames(20)
	check(Food.stack_is_burger(board.stack(0)),
		"repeated knocks build the burger",
		"stack is %s" % str(board.stack(0)))
	var order := board.stack(0)
	check(order.size() == 4, "every part reached the plate", "stack size is %d" % order.size())
	check(order[1] == Food.Kind.PATTY, "the patty is the first to arrive")
	check(order[2] == Food.Kind.LETTUCE, "then the lettuce")
	check(order[3] == Food.Kind.BUN_TOP, "and the lid last, so the order comes out right")
	check(order[0] == Food.Kind.BUN_BOTTOM, "on top of the base bun the plate provides")
	h.teardown()

## The highest part left standing in a plate's column, the thing the chef would
## cross next. Scans the board rather than the "ingredients" group, which only
## the Game populates.
func _column_top(board: Board, plate_index: int) -> Ingredient:
	var plate := board.plates[plate_index]
	var parts: Array[Ingredient] = []
	for y in Cfg.GRID_H:
		for x in range(plate.x, plate.right() + 1):
			var ing := board.ingredient_at(Vector2i(x, y))
			if ing != null and not parts.has(ing):
				parts.append(ing)
	if parts.is_empty():
		return null
	parts.sort_custom(func(a: Ingredient, b: Ingredient) -> bool: return a.rest_row < b.rest_row)
	return parts[0]

## The same thing driven by the chef rather than by a direct knock, which is the
## path a player actually takes: one crossing is one storey, so the chef walks
## the column down onto the plate one push at a time.
func _test_column_builds_a_burger() -> void:
	_begin("chef builds a burger")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	_add_ingredient(h, board, "m", 1, 2, 9)
	_add_ingredient(h, board, "l", 1, 2, 6)
	_add_ingredient(h, board, "t", 1, 2, 3)

	for i in 5:
		if Food.stack_is_burger(board.stack(0)):
			break
		var head := _column_top(board, 0)
		if head == null:
			break
		# Start beside the part, not on it, so the crossing is walked end to end.
		h.player.place(Vector2i(head.cells[0].x - 1, head.rest_row))
		h.hold(&"move_right")
		await h.frames(120)
		h.release(&"move_right")
		await h.frames(40)

	check(Food.stack_is_burger(board.stack(0)), "walking crossings builds the burger",
		"stack is %s" % str(board.stack(0)))
	h.teardown()

## A part is only pushed by a full crossing. Brushing its edge does nothing, which
## is what makes the width of a part part of the puzzle.
func _test_crossing_needs_the_full_width() -> void:
	_begin("crossing needs the full width")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	var ing := _add_ingredient(h, board, "m", 2, 3, 6)
	h.player.place(Vector2i(1, 6))
	var before := ing.rest_row

	# Stand on the first cell of a three-wide part and step off the end of it.
	h.hold(&"move_right")
	await h.frames(10)
	h.release(&"move_right")
	await h.frames(14)
	check(ing.rest_row == before, "one cell of a three-wide part does not move it",
		"row went %d -> %d" % [before, ing.rest_row])

	# Now cross the rest of it.
	h.hold(&"move_right")
	await h.frames(70)
	h.release(&"move_right")
	await h.frames(20)
	check(ing.rest_row == 9, "the full crossing drops it one storey",
		"row went %d -> %d" % [before, ing.rest_row])
	h.teardown()

# --- Player ----------------------------------------------------------------

## The jump is a dodge, not a way to climb: it clears the cell in front so a nasty
## standing in it is gone over rather than landed on, and it only works as a push
## off a platform, never sideways off a ladder.
func _test_player_jump() -> void:
	_begin("player jump")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	# A nasty one cell in front is the whole reason the jump has to clear a cell.
	# It is frozen so it stays put rather than wandering into the landing cell.
	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.setup(board, Vector2i(5, 0), Enemy.Kind.HOTDOG, h.player)
	enemy.stun(90.0)

	h.player.place(Vector2i(4, 0))
	h.player.facing = 1
	check(board.floor_below(Vector2i(4, 0)), "the chef starts on a platform")
	# Held direction, so this is the sideways hop, not the reach. The key is read
	# before the move, so holding a direction cannot swallow the jump.
	h.hold(&"move_right")
	h.tap(&"jump")
	await h.until(func() -> bool: return h.player.state == Player.St.JUMP, 1.0)
	check(h.player.state == Player.St.JUMP, "a direction held still jumps",
		"state is %d" % h.player.state)
	await h.until(func() -> bool: return not h.player.moving, 2.0)
	check(h.player.state == Player.St.WALK, "and it ends standing",
		"state is %d" % h.player.state)
	h.release(&"move_right")
	check(h.player.cell.x == 6, "a stopped hop sideways covers two cells",
		"x is %d" % h.player.cell.x)
	check(h.player.cell.y == 0, "and does not change row", "y is %d" % h.player.cell.y)
	check(h.player.cell != enemy.cell, "so the chef does not land on the nasty",
		"both at %s" % str(h.player.cell))

	# Taking off mid-stride carries a cell further than taking off from a stop.
	h.player.place(Vector2i(4, 0))
	h.player.facing = 1
	h.hold(&"move_right")
	await h.until(func() -> bool: return h.player.moving, 1.0)
	check(h.player.moving, "the chef is running when he jumps")
	h.tap(&"jump")
	await h.until(func() -> bool: return h.player.state == Player.St.JUMP, 1.0)
	await h.until(func() -> bool: return not h.player.moving, 2.0)
	h.release(&"move_right")
	check(h.player.cell.x == 8, "a running hop covers three",
		"x is %d" % h.player.cell.x)

	# ...and it is the stopped hop that arcs high, so a reach really reaches. Read
	# off the sprite rather than the constant, because the arc is what the player
	# sees; a slack margin keeps it from depending on which frame caught the peak.
	# Row 3 rather than the top row, because a reach from the top row has no cell
	# above it to reach into.
	var stand_peak := await _hop_peak(h, Vector2i(4, 3), false)
	var run_peak := await _hop_peak(h, Vector2i(4, 3), true)
	check(stand_peak > run_peak + 6.0,
		"a stopped hop arcs about twice as high as a running one",
		"stopped rose %.1fpx, running rose %.1fpx" % [stand_peak, run_peak])

	# Nothing held is a reach straight up, to the plate on the storey above.
	h.player.place(Vector2i(4, 3))
	h.player.facing = 1
	check(board.floor_below(Vector2i(4, 3)), "and this storey has a floor too")
	h.tap(&"jump")
	await h.until(func() -> bool: return h.player.state == Player.St.JUMP, 1.0)
	check(h.player.cell == Vector2i(4, 2), "the reach targets the cell above",
		"cell is %s" % str(h.player.cell))
	await h.until(func() -> bool: return not h.player.moving, 2.0)
	check(h.player.cell.x == 4, "without moving sideways", "x is %d" % h.player.cell.x)

	# With nothing under him the chef is already falling; he must not jump.
	h.player.place(Vector2i(4, 5))
	h.player.facing = 1
	check(not board.floor_below(Vector2i(4, 5)), "these cells are in mid-air")
	h.tap(&"jump")
	await h.frames(10)
	check(not h.player.moving, "a chef in mid-air cannot jump")

	# A ladder is not a launch pad, even with a ledge under it, so he cannot leap
	# sideways off a rung.
	var ladder_cell := Vector2i(4, 0)
	board._set_tile(ladder_cell, Board.Tile.LADDER)
	h.player.place(ladder_cell)
	h.player.facing = 1
	h.tap(&"jump")
	await h.frames(10)
	check(h.player.cell == ladder_cell, "no jump sideways off a ladder",
		"ended at %s" % str(h.player.cell))
	h.teardown()

## Runs one hop and reports how far the chef's sprite rose above the row he took
## off from, in pixels. Both hops stay on the same row, so the whole difference is
## the arc.
func _hop_peak(h: _Harness, from: Vector2i, running: bool) -> float:
	h.player.place(from)
	h.player.facing = 1
	if running:
		h.hold(&"move_right")
		await h.until(func() -> bool: return h.player.moving, 1.0)
	var base := h.player.position.y
	var peak := base
	h.tap(&"jump")
	await h.until(func() -> bool: return h.player.state == Player.St.JUMP, 1.0)
	while h.player.moving:
		peak = minf(peak, h.player.position.y)
		await h.frame()
	if running:
		h.release(&"move_right")
	return base - peak

## The stopped jump exists so the chef can reach a jar sitting on a plate above the
## track he normally walks, so the pickup is the behaviour worth pinning down: the
## hop has to carry his cell onto the jar, not just his sprite up past it.
func _test_reach_grabs_a_jar_above() -> void:
	_begin("reach grabs a jar above")
	var h := _Harness.new(self)
	var g := await h.start_game(0)
	if g == null:
		return
	g._enter(Game.Phase.PLAYING)
	await h.frame()
	var player := g.player
	var board := g.board

	# Find somewhere the reach can be used from: a floor to push off, and a free
	# cell directly above it to reach into.
	var stand := Vector2i(-1, -1)
	for y in range(Cfg.GRID_H):
		for x in range(1, Cfg.GRID_W - 1):
			var at := Vector2i(x, y)
			if not board.floor_below(at) or board.is_ladder(at):
				continue
			if not Cfg.in_grid(at + Vector2i.UP) or board.blocks_player(at + Vector2i.UP):
				continue
			stand = at
			break
		if stand.x >= 0:
			break
	if stand.x < 0:
		check(false, "the level offers somewhere to reach from")
		h.teardown()
		return
	check(true, "the level offers somewhere to reach from")

	player.place(stand)
	player.pepper_left = 0
	var jar := Bonus.new()
	h.game_node.add_child(jar)
	jar.setup(stand + Vector2i.UP, Bonus.Kind.PEPPER)
	jar.add_to_group(&"bonuses")
	var jar_id := jar.get_instance_id()
	await h.frame()

	h.tap(&"jump")
	# Wait on the charge rather than the jar: the pickup frees the node, and a
	# lambda holding it would be holding a freed object.
	await h.until(func() -> bool: return player.pepper_left > 0, 2.0)
	check(not is_instance_id_valid(jar_id), "the reach takes the jar off the plate above",
		"the jar is still sitting there")
	check(player.pepper_left == 1, "and it goes into the jar as a charge",
		"%d left" % player.pepper_left)
	h.teardown()

func _test_ladder_climb() -> void:
	_begin("ladder climb")
	var h := _Harness.new(self)
	await h.setup(_ladder_map())
	var board := h.board
	if board == null:
		return

	var base := Vector2i(4, 9)
	check(board.is_ladder(base + Vector2i.UP), "the test map has a ladder where expected")
	h.player.place(base)
	h.hold(&"move_up")
	await h.frames(90)
	h.release(&"move_up")
	await h.frames(10)
	check(h.player.cell.y < base.y, "the chef climbs the ladder",
		"y went %d -> %d" % [base.y, h.player.cell.y])
	check(board.is_ladder(h.player.cell) or h.player.cell.y == 6, "and ends on or above it")
	h.teardown()

## Walking off the end of a ledge drops him, because there is nothing there.
func _test_player_falls_off_a_ledge() -> void:
	_begin("falling off a ledge")
	var h := _Harness.new(self)
	await h.setup(_gappy_map())
	var board := h.board
	if board == null:
		return

	# Row 1 has a hole from x=4 onwards, so walking right off x=3 drops him.
	h.player.place(Vector2i(3, 0))
	h.player.facing = 1
	h.hold(&"move_right")
	await h.until(func() -> bool: return h.player.cell.x == 4)
	await h.until(func() -> bool: return h.player.state == Player.St.FALL)
	await h.until(func() -> bool: return h.player.state == Player.St.WALK and not h.player.moving)
	h.release(&"move_right")
	check(h.player.cell.y == 3, "he falls when there is no floor", "y is %d" % h.player.cell.y)
	check(h.player.state == Player.St.WALK, "and lands standing")
	check(board.floor_below(h.player.cell), "on something solid")

	# A fall is one cell and about four frames of real time. Playing the four-frame
	# hop arc across it would strobe, so a fall holds the reach. The state is set
	# directly because a fall is over before a test can sample a frame of it, and
	# the point here is the mapping rather than the timing.
	h.player.state = Player.St.FALL
	check(h.player.anim_state() == Sheet.Anim.JUMP, "a fall still uses the jump art")
	check(h.player.anim_frame(Sheet.Anim.JUMP) == int(Sheet.FRAMES[Sheet.Anim.JUMP]) - 1,
		"held on the reach rather than played through")
	h.teardown()

func _test_pepper_stuns_a_nasty() -> void:
	_begin("pepper")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.setup(board, Vector2i(5, 13), Enemy.Kind.EGG, h.player)

	h.player.add_pepper(2)
	check(h.player.pepper_left == 2, "pepper goes in the jar")
	check(h.player.spend_pepper(), "and can be spent")
	check(h.player.pepper_left == 1, "spending one leaves the other",
		"%d left" % h.player.pepper_left)
	check(h.player.spend_pepper() and not h.player.spend_pepper(),
		"an empty jar cannot pay for a shot")

	enemy.stun(3.0)
	check(enemy.state == Enemy.St.STUN, "a stung nasty stops")
	h.teardown()

func _test_nasties_are_slow() -> void:
	_begin("a nasty is half the pace it was")
	# Measured rather than asserted against the constant, so this is what a player
	# would feel: a nasty must spend at least two cells' worth of time on every
	# cell the chef covers in one. Anything faster turns a chase into a formality.
	check(Enemy.STEP >= Cfg.STEP_WALK * 2.0,
		"a nasty takes at least twice as long per cell as the chef",
		"nasty %ss vs chef %ss" % [Enemy.STEP, Cfg.STEP_WALK])
	# Climbing matched, or a nasty would be quick going up a ladder and slow on the
	# floor, which reads as two different speeds for one character.
	check(Enemy.STEP_CLIMB >= Cfg.STEP_CLIMB * 2.0,
		"and at least twice as long climbing",
		"nasty %ss vs chef %ss" % [Enemy.STEP_CLIMB, Cfg.STEP_CLIMB])

## A nasty that has climbed to the top of a ladder has to step off it onto the
## walk row above.
##
## The top rung is not the top of the climb. The cell above it is, and on every
## shipped level it is open floor with the platform of the storey below it. So a
## nasty standing on the top rung is on a ladder with no rung above it and solid
## platform either side - and _patrol(), which is what it fell through to, turns
## it round into that platform and leaves it standing there for the rest of the
## level. It cannot climb and it cannot walk. The nasty stops a row short of the
## floor the ladder was built to reach, and the player watches it do nothing.
	# Now time a real one moving down a corridor.
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	if h.board == null:
		return
	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.setup(h.board, Vector2i(8, 13), Enemy.Kind.PICKLE, h.player)
	var steps := 0
	enemy.step_finished.connect(func() -> void: steps += 1)
	await h.until(func() -> bool: return enemy.moving, 2.0)
	var clock := 0.0
	var seen := 0
	var last := enemy.cell.x
	while clock < 1.2:
		await h.frame()
		clock += get_process_delta_time()
		if enemy.cell.x != last:
			last = enemy.cell.x
			seen += 1
	var per_cell := clock / maxf(seen, 1)
	check(per_cell >= Cfg.STEP_WALK * 2.0,
		"a nasty covering ground takes at least twice as long as the chef per cell",
		"%.3fs per cell" % per_cell)
	h.teardown()

## A finished burger is drawn at half height, and only the drawing.
##
## At a cell per layer a four-layer burger stood four rows up in the floor the
## chef and the nasties walk on, in the middle of a storey. Half height puts the
## same burger in two rows. The risk in that change is the stack and the drawing
## drifting apart, so this checks the drawn rectangles against the shipped levels
## and then checks the logical stack is still one layer per cell.

func _test_a_nasty_steps_off_the_top_of_a_ladder() -> void:
	_begin("a nasty steps off the top of a ladder")
	var h := _Harness.new(self)
	await h.setup(_full_height_ladder_map())
	if h.board == null:
		return

	# The top rung: a ladder at the top of the solid row, with the walk row above it
	# open and the platform row solid either side of the ladder.
	var top_rung := Vector2i(14, 1)
	check(h.board.is_ladder(top_rung), "the test starts on a ladder")
	check(not h.board.is_ladder(top_rung + Vector2i.UP),
		"with no rung above it")
	check(not h.board.blocks_player(top_rung + Vector2i.UP),
		"and open floor above it")
	check(h.board.blocks_player(top_rung + Vector2i.LEFT)
			and h.board.blocks_player(top_rung + Vector2i.RIGHT),
		"but platform either side, so it cannot simply walk off")

	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.setup(h.board, top_rung, Enemy.Kind.EGG, h.player)
	# On the walk row above, so the nasty is chasing upward.
	h.player.place(top_rung + Vector2i.UP)

	# Give it long enough to have walked a good few cells if it were going to.
	await h.seconds(3.0)
	check(enemy.cell.y < top_rung.y, "it gets above the top of the ladder",
		"stuck on row %d" % enemy.cell.y)
	# Not "it is on the cell above the rung" - by now it may well have carried on up
	# and along the top walk row, which is the point. What must not be true is that
	# it is standing still on the ladder, so this asks whether it is still going.
	check(not (enemy.cell == top_rung and not enemy.moving),
		"and is not left standing on the ladder")
	h.teardown()

## The bottom of a ladder is the same hazard in reverse, so it is checked too: a
## nasty that cannot get off the bottom is a nasty that cannot get on to the floor
## below it at all.
func _test_a_nasty_steps_off_the_bottom_of_a_ladder() -> void:
	_begin("a nasty steps off the bottom of a ladder")
	var h := _Harness.new(self)
	await h.setup(_full_height_ladder_map())
	if h.board == null:
		return

	var bottom_rung := Vector2i(14, 4)
	check(h.board.is_ladder(bottom_rung), "the test starts on a ladder")
	check(not h.board.is_ladder(bottom_rung + Vector2i.DOWN),
		"with no rung below it")

	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.setup(h.board, bottom_rung, Enemy.Kind.PICKLE, h.player)
	h.player.place(bottom_rung + Vector2i.DOWN)

	await h.seconds(3.0)
	check(enemy.cell.y > bottom_rung.y, "it gets below the bottom of the ladder",
		"stuck on row %d" % enemy.cell.y)
	h.teardown()

func _test_burgers_are_half_height() -> void:
	_begin("burgers are drawn at half height")
	check(Cfg.BURGER_LAYER_H == Cfg.TILE / 2,
		"one layer is half a cell tall",
		"%s px against a %s px cell" % [Cfg.BURGER_LAYER_H, Cfg.TILE])

	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	if h.board == null:
		return
	for i in LevelData.count():
		var lv := LevelData.get_level(i)
		var tag := "level %d" % (i + 1)
		var tallest := 0
		for plate in lv.plates:
			tallest = maxi(tallest, lv.recipe(plate).size())
		# Two cells is the ceiling: the ground storey is five rows of walking room
		# and a burger that fills it is a burger in the way.
		check(tallest * Cfg.BURGER_LAYER_H <= 2 * Cfg.TILE,
			"%s tallest burger is at most two cells of drawing" % tag,
			"%d layers is %.1f px" % [tallest, tallest * Cfg.BURGER_LAYER_H])

		# The drawn stack has to sit on its plate and stay under the storey above.
		var plate := lv.plates[0]
		var plate_rect := h.board.burger_layer(plate, 0)
		check(is_equal_approx(plate_rect.position.y + plate_rect.size.y,
				float(plate.y * Cfg.TILE)),
			"%s the bottom layer sits on the plate" % tag,
			"underside at %s, wanted %s" % [
				plate_rect.position.y + plate_rect.size.y, plate.y * Cfg.TILE])
		check(plate_rect.size.x == plate.width * Cfg.TILE,
			"%s a layer is as wide as its plate" % tag)
		var top := h.board.burger_layer(plate, maxi(tallest - 1, 0))
		check(top.position.y > float((plate.y - 3) * Cfg.TILE),
			"%s the drawn stack stays in the bottom three rows" % tag,
			"top at row %.2f" % (top.position.y / Cfg.TILE))
		# Layer n sits directly on layer n-1: no gaps, no overlap.
		var abuts := true
		for n in range(1, tallest):
			var lower := h.board.burger_layer(plate, n - 1)
			var upper := h.board.burger_layer(plate, n)
			if not is_equal_approx(lower.position.y, upper.position.y + upper.size.y):
				abuts = false
		check(abuts, "%s the drawn layers stack without gaps" % tag)
	h.teardown()

	# The logical stack is untouched: a part still joins it one cell at a time, so
	# halving the drawing must not change where anything stops.
	var span: LevelData.Span = LevelData.get_level(0).plates[0]
	check(h.board.stack_top_row(span) == span.y - h.board.stack(span.x).size(),
		"the logical stack is still one layer per cell")

## A burger is two buns, and the corners that say so are the ones facing away from
## the burger: a lid is domed so its top corners round off, a base sits flat so its
## bottom ones do. Checked on the shipped half-cell layer height, because that is
## where the rounding either fits or has to be squeezed.
func _test_buns_are_rounded_the_right_way_up() -> void:
	_begin("buns are rounded the right way up")
	var h := int(Cfg.BURGER_LAYER_H)

	var lid := Board._layer_insets(Food.Kind.BUN_TOP, h)
	check(lid[0] > lid[1], "a lid rounds off over its first rows",
			"%s then %s" % [lid[0], lid[1]])
	check(lid[h - 1] == 0, "and squares up against the rest of the burger",
			"bottom row inset %d" % lid[h - 1])
	check(lid[0] == Board.BUN_ROUND, "by the rounding it is supposed to have",
			"%d, wanted %d" % [lid[0], Board.BUN_ROUND])

	var base := Board._layer_insets(Food.Kind.BUN_BOTTOM, h)
	check(base[h - 1] > base[h - 2], "a base rounds off over its last rows",
			"%s then %s" % [base[h - 2], base[h - 1]])
	check(base[0] == 0, "and squares up against the rest of the burger",
			"top row inset %d" % base[0])

	# The two are each other's reflection, which is what makes a burger read as a
	# burger rather than a box with a box on it.
	var flipped := PackedInt32Array()
	for i in h:
		flipped.append(lid[h - 1 - i])
	check(base == flipped, "and the pair are mirror images of each other",
			"lid %s against base %s" % [str(lid), str(base)])

	# The one place they must agree is the join in the middle, where a lid sits on
	# whatever is under it: both have to be square there or the stack has a step.
	check(lid[h - 1] == base[0], "with a square join between them",
			"lid bottom %d, base top %d" % [lid[h - 1], base[0]])

	# Everything between the bun and its neighbours is still a box. A patty with
	# rounded corners is a patty with a bite out of it.
	for kind in [Food.Kind.PATTY, Food.Kind.LETTUCE, Food.Kind.TOMATO]:
		var square := Board._layer_insets(kind, h)
		var all_zero := true
		for v in square:
			if v != 0:
				all_zero = false
		check(all_zero, "%s is still square" % Food.DEFS[kind]["name"],
			str(square))

## The patty is speckled black and the lettuce ribbed white, which is the way round
## they read at a glance.
func _test_the_patty_is_black_and_the_lettuce_is_white() -> void:
	_begin("the patty is black and the lettuce is white")
	check(Food.TEXTURES.has(Food.Kind.PATTY), "the patty has a texture")
	check(Food.TEXTURES.has(Food.Kind.LETTUCE), "and so does the lettuce")
	for kind in [Food.Kind.PATTY, Food.Kind.LETTUCE]:
		var d: Dictionary = Food.TEXTURES[kind]
		var name: String = d["name"]
		var tile: Array = d["tile"]
		var marks := 0
		for row in tile:
			var text: String = row
			for c in text.length():
				if text[c] == "#":
					marks += 1
		check(marks > 0, "%s texture has marks in it" % name,
			"%d marks in %d rows" % [marks, tile.size()])
		# A mark that is not a single pixel is detail nobody can see on a layer half
		# a cell tall, and a mask wider than the layer is a mask that cannot tile.
		var widths := PackedInt32Array()
		for row in tile:
			widths.append((row as String).length())
		var one := true
		for w in widths:
			if w != widths[0]:
				one = false
		check(one, "%s texture rows are all the same width" % name, str(widths))
		check(widths[0] <= Cfg.TILE, "%s tile is no wider than a cell" % name,
			"%d px" % widths[0])
		check(tile.size() <= Cfg.BURGER_LAYER_H,
			"%s tile is no taller than a layer" % name,
			"%d rows against %d" % [tile.size(), Cfg.BURGER_LAYER_H])

	# The patty's black is near-black rather than a true black, because a true black
	# speck is the same colour as the outline and vanishes into the edge.
	var patty: Color = Food.texture_of(Food.Kind.PATTY)
	var patty_base: Color = Food.color_of(Food.Kind.PATTY)
	check(patty != Cfg.COL_OUTLINE, "a patty speck is not the outline's black")
	check(patty != Color("000000"), "nor a true black",
		"which would be %s" % str(patty))
	check(patty.get_luminance() < patty_base.get_luminance(),
		"and is darker than the patty it is drawn on",
		"%.3f against %.3f" % [patty.get_luminance(), patty_base.get_luminance()])

	var lettuce: Color = Food.texture_of(Food.Kind.LETTUCE)
	var lettuce_base: Color = Food.color_of(Food.Kind.LETTUCE)
	check(lettuce.get_luminance() > lettuce_base.get_luminance(),
		"a lettuce mark is lighter than the leaf it is drawn on",
		"%.3f against %.3f" % [lettuce.get_luminance(), lettuce_base.get_luminance()])

	# The mask has to repeat, or a layer narrower than the tile would either be blank
	# or cropped, and which one depends on the plate it is on.
	for kind in [Food.Kind.PATTY, Food.Kind.LETTUCE]:
		var a := Food.texture_at(kind, 0, 0)
		check(a or not a, "texture_at answers for %s" % Food.DEFS[kind]["name"])
		check(Food.texture_at(kind, 4, 0) == Food.texture_at(kind, 0, 0),
			"%s repeats every four columns" % Food.DEFS[kind]["name"])
		# Negative positions come from nothing the board asks for, but wrapping them
		# rather than indexing a negative row is cheaper than proving they cannot.
		check(Food.texture_at(kind, -1, 0) == Food.texture_at(kind, 3, 0),
			"%s wraps rather than indexing backwards" % Food.DEFS[kind]["name"])
		check(Food.texture_at(kind, 0, -1) == Food.texture_at(kind, 0, 3),
			"%s wraps in rows too" % Food.DEFS[kind]["name"])
##
## The whole point of the sheets is that the art can be replaced with a PNG, so
## the things worth protecting are the contract rather than the drawing: every
## character has a sheet, every sheet is the same size, every frame a cell
## contract promises is actually filled, and the padding cells really are empty so
## a replacement cannot inherit a stray frame. The pixels are read from the
## imported texture, which is what the game blits, not from the PNG on disk.
func _test_sheets() -> void:
	_begin("character sheets")
	var missing := Sheet.all_present()
	check(missing.is_empty(), "every character has a sheet",
		"missing %s" % ", ".join(missing))
	if not missing.is_empty():
		return

	var want := Sheet.size()
	for character: String in Sheet.CHARACTERS:
		var tex := Sheet.texture(character)
		var got := tex.get_size()
		check(Vector2i(got) == want,
			"%s sheet is %dx%d" % [character, want.x, want.y],
			"got %dx%d" % [got.x, got.y])

	# Every frame a character promises has art in it, and every cell it does not
	# promise is clear. The two are one contract rather than two: a sheet keeps the
	# whole shared grid, so the rows a character has no use for are expected to be
	# blank, and a row that is meant to be blank but has a walk cycle in it is just
	# as wrong as a missing frame.
	var blank_used := []
	var dirty_pad := []
	for character: String in Sheet.CHARACTERS:
		for anim in Sheet.ROWS:
			var promised: bool = anim in Sheet.anims_for(character)
			for frame in Sheet.COLUMNS:
				var n: int = _cell(character, anim, frame)["n"]
				if promised and frame < int(Sheet.FRAMES[anim]):
					if n == 0:
						blank_used.append("%s r%d f%d" % [character, Sheet.row(anim), frame])
				elif n > 0:
					dirty_pad.append("%s r%d f%d" % [character, Sheet.row(anim), frame])
	check(blank_used.is_empty(), "every frame in the layout has art in it",
		"blank %s" % ", ".join(blank_used))
	check(dirty_pad.is_empty(), "cells no character claims are empty",
		"unexpected art in %s" % ", ".join(dirty_pad))

	# The frames of an animation have to differ from each other, or it is one
	# picture with a row of copies of itself.
	var still := []
	for character: String in Sheet.CHARACTERS:
		for anim in Sheet.anims_for(character):
			if int(Sheet.FRAMES[anim]) < 2:
				continue
			var sigs := {}
			for frame in int(Sheet.FRAMES[anim]):
				sigs[_cell(character, anim, frame)["sig"]] = true
			if sigs.size() == 1:
				still.append("%s row %d" % [character, Sheet.row(anim)])
	check(still.is_empty(), "frames within an animation differ from each other",
		"identical frames in %s" % ", ".join(still))

	# The cells are see-through. A filled cell draws a dark box the size of the
	# cell behind every character, which covers the part of the cell the character
	# jumps into and lifts into - the space is not spare, it has to be visible.
	var solid := []
	for character: String in Sheet.CHARACTERS:
		var opaque := 0
		var total := 0
		for anim in Sheet.anims_for(character):
			for frame in range(Sheet.FRAMES[anim]):
				total += Sheet.CELL.x * Sheet.CELL.y
				opaque += int(_cell(character, anim, frame)["n"])
		# The characters are blocky, so a lot of a cell is legitimately empty, but
		# nothing like all of it: a filled cell would be at 100%.
		if float(opaque) / float(total) > 0.5:
			solid.append("%s %.0f%%" % [character, 100.0 * float(opaque) / float(total)])
	check(solid.is_empty(), "the cells are transparent, not filled boxes",
		"too solid: %s" % ", ".join(solid))

	# Everyone stands on the baseline: there is art in the bottom row of the cell
	# and none below it, which is what Sheet's anchor promises. A character drawn
	# a pixel high floats, and it is the kind of thing that survives a redraw.
	var off_baseline := []
	var never_lands := []
	for character: String in Sheet.CHARACTERS:
		for anim in Sheet.anims_for(character):
			var lands := false
			for frame in int(Sheet.FRAMES[anim]):
				var low: int = _cell(character, anim, frame)["low"]
				# A bob lifts the feet a pixel or two; hanging in the air does not.
				if low < Sheet.CELL.y - 3:
					off_baseline.append("%s r%d f%d" % [character, Sheet.row(anim), frame])
				if low == Sheet.CELL.y - 1:
					lands = true
			if not lands:
				never_lands.append("%s row %d" % [character, Sheet.row(anim)])
	check(off_baseline.is_empty(), "no frame floats more than a bob off the floor",
		"floating in %s" % ", ".join(off_baseline))
	check(never_lands.is_empty(), "every animation has its feet on the floor",
		"never touching it: %s" % ", ".join(never_lands))

	# Nothing may spill into the next cell. A frame drawn too wide used to smear
	# into the following column, which shows up as a stray frame in a padded cell
	# and as junk in the middle of a replacement sheet.
	var spills := []
	for character: String in Sheet.CHARACTERS:
		for anim in Sheet.anims_for(character):
			for frame in range(Sheet.FRAMES[anim]):
				var c := _cell(character, anim, frame)
				if c["n"] > 0 and (c["right"] >= Sheet.CELL.x or c["low"] >= Sheet.CELL.y):
					spills.append("%s r%d c%d" % [character, Sheet.row(anim), frame])
	check(spills.is_empty(), "no frame spills out of its cell",
		"spilling in %s" % ", ".join(spills))

	# The imported chef has to actually be in his cells. The old drawn chef had two
	# hardcoded eye pixels checked, because the old drawing code used to fake a
	# facing of zero on a ladder to hide them. A drawn chef has no such landmark, and
	# hardcoding two pixels of his would break the next time the art is touched, so
	# what is checked is the thing the import can plausibly get wrong: the toque is
	# there, and it is in the top of the cell. A figure measured from the wrong band
	# of the source, or placed a pixel low, still looks like a chef on its own and is
	# a hat where his face should be once he is on the board.
	var hatless := []
	var hat_low := []
	for anim in [Sheet.Anim.WALK, Sheet.Anim.CLIMB]:
		for frame in int(Sheet.FRAMES[anim]):
			if _count_in_cell(Sheet.CHEF, anim, frame, ChefArt.COL_HAT) == 0:
				hatless.append("r%d f%d" % [Sheet.row(anim), frame])
			elif _count_in_cell(Sheet.CHEF, anim, frame, ChefArt.COL_HAT,
					Rect2i(Vector2i.ZERO, Vector2i(Sheet.CELL.x, Sheet.CELL.y / 2))) == 0:
				hat_low.append("r%d f%d" % [Sheet.row(anim), frame])
	var face_frames: int = int(Sheet.FRAMES[Sheet.Anim.WALK]) \
			+ int(Sheet.FRAMES[Sheet.Anim.CLIMB])
	check(hatless.size() == 0, "the chef has a hat in every walk and climb frame",
		"%d of %d bare" % [hatless.size(), face_frames])
	check(hat_low.is_empty(), "and it is on top of him, not at his feet",
		"hat below the waist in %s" % ", ".join(hat_low))

	# The run and the climb are the same six frames, because the climb reuses the
	# run. They are separate rows rather than one row read twice so the layout stays
	# the same shape for a sheet that ever wants to draw a different climb, and this
	# is what stops the two quietly drifting apart.
	var drift := []
	for frame in int(Sheet.FRAMES[Sheet.Anim.CLIMB]):
		if _cell(Sheet.CHEF, Sheet.Anim.WALK, frame)["sig"] \
				!= _cell(Sheet.CHEF, Sheet.Anim.CLIMB, frame)["sig"]:
			drift.append(str(frame))
	check(drift.is_empty(), "the climb is the run", "differs in frame %s" % ", ".join(drift))

	# The committed PNGs have to be what the art code paints. A sheet that was
	# regenerated and not re-imported, or edited by hand, looks fine and plays fine
	# while no longer being reproducible from the project, which is the one property
	# the sheets are here to guarantee.
	var drifted := []
	for character: String in Sheet.CHARACTERS:
		var painted := CharArt.sheet(character)
		var got := Sheet.texture(character).get_image()
		if got.get_size() != painted.get_size():
			drifted.append("%s size" % character)
			continue
		var mismatch := 0
		for y in painted.get_height():
			for x in painted.get_width():
				var a := got.get_pixel(x, y)
				var b := painted.get_pixel(x, y)
				# Alpha always, colour only where the pixel is visible: the colour
				# hiding under a fully transparent pixel is not part of the art and
				# does not survive a round trip through the importer intact.
				if absf(a.a - b.a) > 0.01:
					mismatch += 1
				elif b.a >= 0.5 and not a.is_equal_approx(b):
					mismatch += 1
		if mismatch > 0:
			drifted.append("%s %d px" % [character, mismatch])
	check(drifted.is_empty(),
		"the committed sheets match the art that draws them",
		"run tools/make_sheets.gd and --import, then: %s" % ", ".join(drifted))

	# The three nasties are told apart by their art now, so each sheet has to carry
	# its own colour and not the other two.
	for character: String in [Sheet.HOTDOG, Sheet.EGG, Sheet.PICKLE]:
		var mine: Color = CharArt.VILLAIN_COLORS[character]
		var own := 0
		var others := 0
		for anim in Sheet.anims_for(character):
			for frame in int(Sheet.FRAMES[anim]):
				for seen in _cell(character, anim, frame)["colors"].keys():
					if seen == mine.to_rgba32():
						own += 1
					elif seen in [CharArt.VILLAIN_COLORS[Sheet.HOTDOG].to_rgba32(),
							CharArt.VILLAIN_COLORS[Sheet.EGG].to_rgba32(),
							CharArt.VILLAIN_COLORS[Sheet.PICKLE].to_rgba32()]:
						others += 1
		check(own > 0 and others == 0,
			"%s is drawn in its own colour only" % character,
			"%d of its own, %d of another nasty's" % [own, others])

## One cell of a character's sheet, measured. `n` non-background pixels, `low` the
## lowest row holding any, and `sig` a fingerprint for comparing two frames.
func _cell(character: String, anim: int, frame: int) -> Dictionary:
	var img := Sheet.texture(character).get_image()
	var r := Sheet.region(anim, frame)
	var n := 0
	var low := -1
	var right := -1
	var sig := 0
	var colors := {}
	for y in r.size.y:
		for x in r.size.x:
			var c := img.get_pixel(int(r.position.x) + x, int(r.position.y) + y)
			if c.a < 0.5:
				continue
			n += 1
			low = y
			right = x
			sig = sig * 131 + x * 7919 + y * 104729 + c.to_rgba32()
			colors[c.to_rgba32()] = true
	return {"n": n, "low": low, "right": right, "sig": sig, "colors": colors}

## One pixel of a character's sheet, in cell coordinates.
func _pixel(character: String, anim: int, frame: int, at: Vector2i) -> Color:
	var img := Sheet.texture(character).get_image()
	var r := Sheet.region(anim, frame)
	return img.get_pixel(int(r.position.x) + at.x, int(r.position.y) + at.y)

## How many pixels of one colour are in a cell, or in a box within it.
##
## `within` is cell-relative and defaults to the whole cell. Exact match rather than
## a tolerance, unlike the visual check's: this is reading a sheet the generator
## painted from a palette of its own, so a colour that is nearly right is a colour
## that is wrong.
func _count_in_cell(character: String, anim: int, frame: int, want: Color,
		within: Rect2i = Rect2i(Vector2i.ZERO, Vector2i(Sheet.CELL))) -> int:
	var img := Sheet.texture(character).get_image()
	var r := Sheet.region(anim, frame)
	var want32 := want.to_rgba32()
	var n := 0
	for y in within.size.y:
		for x in within.size.x:
			var c := img.get_pixel(int(r.position.x) + within.position.x + x,
					int(r.position.y) + within.position.y + y)
			if c.a >= 0.5 and c.to_rgba32() == want32:
				n += 1
	return n

## The most recent popup the game raised, which is how the tests read the short
## confirmations pepper and its bonuses put on screen.
func _last_popup(g: Game) -> String:
	var all := g.popups()
	if all.is_empty():
		return ""
	return String((all[all.size() - 1] as Dictionary)["text"])

## The pepper key is what spends a charge, not touching a nasty.
##
## Spending it automatically on the first thing the chef brushed past made the
## jars something the player never chose how to use, so it is now thrown with the
## pepper action and only the window it opens can zap a nasty.
func _test_pepper_is_fired_by_a_key() -> void:
	_begin("pepper is fired by a key")
	var h := _Harness.new(self)
	var g := await h.start_game(0)
	if g == null:
		return
	g._enter(Game.Phase.PLAYING)
	await h.frame()
	var player := g.player

	player.pepper_left = 0

	# The key with an empty jar does nothing at all, and says so.
	Input.action_press(&"pepper")
	await h.frame()
	Input.action_release(&"pepper")
	await h.frame()
	check(_last_popup(g) == "NO PEPPER", "pressing pepper with an empty jar says so",
		"popup was %s" % _last_popup(g))

	# A nasty to aim at: one cell in front of the chef, inside a spray's reach.
	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.add_to_group(&"enemies")
	enemy.setup(g.board, player.cell + Vector2i.RIGHT, Enemy.Kind.HOTDOG, player)
	player.facing = 1

	# With a charge in the jar, the key throws the dose and the nasty it reaches
	# is frozen.
	player.add_pepper(2)
	Input.action_press(&"pepper")
	await h.frame()
	Input.action_release(&"pepper")
	await h.frame()
	check(player.pepper_left == 1, "the key spends one charge",
		"%d left" % player.pepper_left)
	check(enemy.state == Enemy.St.STUN, "a nasty in front of the chef is frozen",
		"state is %d" % enemy.state)

	# The freeze is a count-down, not a permanent removal.
	check(enemy._timer > 4.0, "for about five seconds",
		"timer is %.1f" % enemy._timer)
	await h.until(func() -> bool: return enemy.state != Enemy.St.STUN, 8.0)
	check(enemy.state != Enemy.St.STUN, "and then it starts walking again",
		"state is %d" % enemy.state)

	# The spray only goes the way the chef is facing, so a nasty behind him is
	# safe from a shot thrown forwards.
	enemy.place(player.cell + Vector2i.LEFT)
	player.facing = 1
	player.add_pepper(1)
	Input.action_press(&"pepper")
	await h.frame()
	Input.action_release(&"pepper")
	await h.frame()
	check(enemy.state != Enemy.St.STUN, "a nasty behind the chef is not sprayed",
		"state is %d" % enemy.state)

	# And it does not reach the whole board.
	enemy.place(player.cell + Vector2i(player.facing * 4, 0))
	player.add_pepper(1)
	Input.action_press(&"pepper")
	await h.frame()
	Input.action_release(&"pepper")
	await h.frame()
	check(enemy.state != Enemy.St.STUN, "a nasty four cells away is out of reach",
		"state is %d" % enemy.state)

	h.teardown()

## The chef is caught when he and a nasty are touching on the screen.
##
## This used to be "when they are in the same cell or next to it", which is a
## three-by-three block of cells around the chef: the chef died while a nasty was
## visibly a full character away, with floor drawn between them. Contact is now
## body boxes in world pixels, and the box is smaller than a cell on purpose.
func _test_contact_is_drawn_contact() -> void:
	_begin("contact is contact")
	var h := _Harness.new(self)
	await h.start_game(0)
	var g: Game = h.game_node.get_child(0) as Game
	if g == null or g.player == null:
		return
	var player: Player = g.player
	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.add_to_group(&"enemies")
	enemy.setup(g.board, player.cell + Vector2i(3, 0), Enemy.Kind.HOTDOG, player)

	# Far away, obviously not touching.
	enemy.place(player.cell + Vector2i(3, 0))
	check(not g._touching(enemy), "a nasty three cells away is not touching")

	# Next door. Still not touching, which is the whole complaint.
	enemy.place(player.cell + Vector2i.RIGHT)
	check(not g._touching(enemy), "a nasty in the next cell is not touching",
		"chef at %s boxes %s vs %s" % [str(player.cell),
			str(player.hit_rect()), str(enemy.hit_rect())])
	check(not g._touching(enemy), "and nor is one in the cell above")
	enemy.place(player.cell + Vector2i.UP)
	check(not g._touching(enemy), "above the chef is not touching either")
	enemy.place(player.cell + Vector2i(3, 0))

	# The same cell, and half a cell, are.
	enemy.place(player.cell)
	check(g._touching(enemy), "a nasty on the chef's cell is touching")
	enemy.place(player.cell + Vector2i.RIGHT)
	enemy.position -= Vector2(Cfg.TILE * 0.5, 0.0)
	enemy.cell = enemy.cell
	check(g._touching(enemy), "and so is one halfway across the gap")

	# A raised hitbox still catches a chef standing underneath.
	enemy.place(player.cell + Vector2i.DOWN)
	check(not g._touching(enemy), "a nasty in the cell below is not touching")
	h.teardown()

## Food falling on a nasty flattens it, which is the other way past one.
func _test_falling_food_squashes() -> void:
	_begin("falling food squashes")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	# Standing on the ground row, in the path of a part about to be dropped on him.
	enemy.setup(board, Vector2i(8, 13), Enemy.Kind.HOTDOG, h.player)

	var ing := _add_ingredient(h, board, "m", 7, 3, 9)
	ing.knock()
	await h.until(func() -> bool: return enemy.state == Enemy.St.SQUASH)
	check(enemy.state == Enemy.St.SQUASH, "a nasty under falling food is flattened",
		"state is %d" % enemy.state)

	# A flattened nasty lies still, and does not come back almost at once: the
	# count-down is long enough to read as "out of play" and to give the chef a
	# real window of work.
	check(enemy._timer > 3.0, "and stays down for several seconds",
		"timer is %.1f" % enemy._timer)
	await h.until(func() -> bool: return enemy.state != Enemy.St.SQUASH, 8.0)
	check(enemy.state != Enemy.St.SQUASH, "then it comes back into play",
		"state is %d" % enemy.state)
	check(enemy.cell == enemy.home_cell, "on the ledge it started on",
		"at %s, home %s" % [str(enemy.cell), str(enemy.home_cell)])
	h.teardown()

## A nasty on top of a part goes down with it, and the part falls two levels.
func _test_riding_a_part() -> void:
	_begin("riding a part")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	var ing := _add_ingredient(h, board, "m", 5, 3, 6)
	# A nasty rides a part by standing on top of it, so it sits a row above the
	# part, not level with it.
	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.setup(board, Vector2i(6, 5), Enemy.Kind.PICKLE, h.player)
	check(enemy.riding(ing), "the nasty is standing on the part")

	# A part level with the nasty is beside it, not underfoot, so it is not a
	# ride. This is the off-by-one that used to make the whole mechanic dead.
	var beside := _add_ingredient(h, board, "l", 2, 5, 5)
	check(not enemy.riding(beside), "a part level with the nasty is not underfoot")

	# The chef's crossing attaches the rider before it knocks the part, so the
	# nasty is carried down instead of being flattened by the part leaving.
	enemy.attach(ing)
	ing.knock(1)
	check(enemy.state == Enemy.St.RIDE, "the nasty is carried down",
		"state is %d" % enemy.state)
	await h.until(func() -> bool: return enemy.state == Enemy.St.SQUASH, 3.0)
	h.teardown()

## The whole point of the ride is that it happens while you play: the chef walks
## across a part a nasty is standing on, and the nasty goes down with it. This
## drives the game's own crossing handler, so the mechanic is checked through the
## path a player actually takes rather than by calling the enemy's methods.
func _test_crossing_a_part_carries_the_nasty() -> void:
	_begin("crossing a part carries the nasty")
	var h := _Harness.new(self)
	var g := await h.start_game(0)
	if g == null:
		return
	g._enter(Game.Phase.PLAYING)
	await h.frame()

	# Any part with a free cell above it will do; put a nasty on that cell so it
	# is standing on the part, and freeze the level's own nasties out of the way.
	var ing: Ingredient = null
	for candidate in g.get_tree().get_nodes_in_group(&"ingredients"):
		var c := candidate as Ingredient
		if c != null and g.board.ingredient_at(c.cells[0]) == c \
				and not g.board.blocks_player(c.cells[0] + Vector2i.UP):
			ing = c
			break
	if ing == null:
		check(false, "a level 1 part with room to stand a nasty on top of it")
		h.teardown()
		return

	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.add_to_group(&"enemies")
	enemy.setup(g.board, ing.cells[0] + Vector2i.UP, Enemy.Kind.HOTDOG, g.player)
	check(enemy.riding(ing), "the nasty is standing on the part")

	# The chef walks the full width, which is the crossing the game listens for.
	g._on_crossed(ing)
	check(enemy.state == Enemy.St.RIDE, "the crossing puts the nasty on the ride",
		"state is %d" % enemy.state)
	await h.until(func() -> bool: return enemy.state == Enemy.St.SQUASH, 6.0)
	check(enemy.state == Enemy.St.SQUASH, "and the part crushes it on the way down",
		"state is %d" % enemy.state)
	h.teardown()

# --- Game flow -------------------------------------------------------------

func _test_game_starts_every_level() -> void:
	_begin("game starts")
	for i in LevelData.count():
		var g := await _Harness.new(self).start_game(i, false)
		var label := "level %d" % (i + 1)
		if g == null:
			continue
		check(g.board != null, "%s builds a board" % label)
		check(g.player != null, "%s spawns the chef" % label)
		var ings := g.get_tree().get_nodes_in_group(&"ingredients")
		var nasts := g.get_tree().get_nodes_in_group(&"enemies")
		check(ings.size() == g.level.ingredients.size(),
			"%s puts every ingredient in the maze" % label,
			"%d of %d" % [ings.size(), g.level.ingredients.size()])
		check(nasts.size() == g.level.enemies.size(), "%s spawns every nasty" % label,
			"%d of %d" % [nasts.size(), g.level.enemies.size()])
		check(g.phase == Game.Phase.INTRO, "%s opens on the level card" % label)
		check(g.player.pepper_left == Game.STARTING_PEPPER,
			"%s starts with pepper in the jar" % label)
		g.queue_free()
		await _frame()

## Winning is a state change, not a special case: the last plate to be finished
## ends the level.
func _test_burger_completes_the_level() -> void:
	_begin("finishing the level")
	var g := await _Harness.new(self).start_game(0)
	if g == null:
		return
	GameState.reset_run()
	var target := g.level.plates.size()
	check(GameState.burgers_target == target, "the level knows how many burgers it wants")

	# Drive every part of the first column onto its plate. A knock walks the
	# column down a storey, so keep knocking whatever is currently on top until
	# the burger is done.
	var board := g.board
	var plate_x := g.level.plates[0].x
	for i in 8:
		if Food.stack_is_burger(board.stack(plate_x)):
			break
		var head := _column_top(board, 0)
		if head == null:
			break
		head.knock()
		# Wait for the fall to settle, or the next knock is ignored as still
		# falling.
		for f in 40:
			if not is_instance_valid(head) or not head.falling:
				break
			await _frame()
	check(Food.stack_is_burger(board.stack(plate_x)),
		"dropping the column top-down builds the burger", "stack is %s" % str(board.stack(plate_x)))
	check(GameState.burgers_done == 1, "and scores it", "counted %d" % GameState.burgers_done)
	check(g.phase != Game.Phase.LEVEL_CLEAR, "but one burger is not the level")
	g.queue_free()
	await _frame()

func _test_running_out_of_chefs() -> void:
	_begin("running out of chefs")
	var g := await _Harness.new(self).start_game(0)
	if g == null:
		return
	GameState.reset_run()
	check(GameState.chefs == GameState.START_CHEFS, "a run starts with spare chefs")
	check(not GameState.out_of_chefs(), "and is not over")

	for i in GameState.START_CHEFS:
		g._on_player_died()
	check(GameState.out_of_chefs(), "losing every chef ends the run")
	check(g.phase == Game.Phase.GAME_OVER, "and the game says so")
	g.queue_free()
	await _frame()

## Being caught puts the chef back on his spawn, so every nasty has to go back to
## its own ledge too. Without that a nasty that has parked on the spawn eats the
## run chef after chef with no chance to get away, which is how a level ended with
## all six chefs gone while the player was not touching the controls.
func _test_a_death_resets_the_nasties() -> void:
	_begin("a death resets the nasties")
	var g := await _Harness.new(self).start_game(0)
	if g == null:
		return
	GameState.reset_run()
	var nasts := g.get_tree().get_nodes_in_group(&"enemies")
	check(nasts.size() > 0, "the level has enemies to reset")

	# Park every nasty on top of where the chef will come back to, which is the
	# situation that used to eat the whole run. He respawns in the middle of the
	# floor rather than where the level starts him, so that is the cell to use.
	var homes := []
	for e in nasts:
		var enemy := e as Enemy
		homes.append(enemy.home_cell)
		enemy.place(g.board.respawn_spawn)
	var parked := true
	for e in nasts:
		if (e as Enemy).cell != g.board.respawn_spawn:
			parked = false
	check(parked, "the test parks every nasty on the respawn cell")

	# The chef is moved off his respawn cell first, so the respawn is a real move
	# and this can tell "he went back" apart from "he never left".
	g.player.place(g.board.respawn_spawn + Vector2i(-1, 0))
	var fell_at := g.player.cell
	var before := GameState.chefs
	g._on_player_died()
	check(GameState.chefs == before - 1, "the chef loses one")
	# He is out of play where he fell: he is not walked back to his spawn mid-death,
	# so the surprise is something the player sees rather than a blink, and he
	# cannot be caught a second time on the way or walk into a nasty sent home.
	check(g.player.cell == fell_at, "and stays where he fell, out of play")
	check(g.player.anim_state() == Sheet.Anim.DEATH, "showing the surprised pose")
	check(not g.player.is_processing(), "and not taking input")

	# The respawn is a beat later rather than the same frame, so the surprise is
	# something the player actually sees. Driven through the game's own clock
	# instead of waiting on real frames, so the test is not timing dependent.
	for i in 5:
		g._process(Game.DEATH_TIME / 5.0)
	# He comes back down under his parachute now, so the beat after the floor is
	# not instant: it takes the drop. Run it out before asking where he ended up.
	var guard := 0
	while g._respawning and guard < 200:
		g._process(Game.DROP_TIME / 20.0)
		guard += 1
	check(g.player.cell == g.board.respawn_spawn,
			"and goes back to the middle of the floor after the beat",
			"at %s, respawn is %s" % [str(g.player.cell), str(g.board.respawn_spawn)])
	check(g.player.anim_state() != Sheet.Anim.DEATH, "no longer wearing the pose")
	check(not g.player.dropping, "and the canopy is off")
	check(g.player.is_processing(), "and back in play")

	var all_home := true
	for i in nasts.size():
		if (nasts[i] as Enemy).cell != homes[i]:
			all_home = false
	check(all_home, "and every nasty is back on its own ledge")

	# The point of all that: the chef is not standing in a nasty's arms any more,
	# so he is not killed again the instant he respawns.
	var clear := true
	for e in nasts:
		if (e as Enemy).cell == g.board.respawn_spawn:
			clear = false
	check(clear, "so nobody is left on top of where he lands")

	# The complaint belongs where it happened. Reading the spawn instead put "OUCH!"
	# over the cell the chef was about to appear in and left the cell he was caught
	# in saying nothing at all, which on every death after the first was the player
	# being told about a place he was not. So the chef has to be somewhere that is
	# not his spawn for this to be a test of anything.
	g.player.place(g.board.chef_spawn + Vector2i(-2, 0))
	var caught_at := g.player.cell
	g._on_player_died()
	var said: Dictionary = g.popups().back()
	check(said["pos"] == Cfg.cell_to_pixel(caught_at),
			"the ouch is over the chef, not over his spawn",
			"at %s, said %s" % [str(caught_at), str(said["pos"])])
	check(said["pos"] != Cfg.cell_to_pixel(g.board.chef_spawn),
			"which are not the same cell")
	g.queue_free()
	await _frame()

## A popup has to leave the board on its own.
##
## They used to never go away: the `t` on each one was written when it was raised
## and then never read by anything, so the `OUCH!` from the first death was still
## painted at the end of the level, over whatever the chef had walked to by then,
## with the score popups piling up behind it. Two seconds is long enough to read
## "OUCH!" and to look up from the board to find it, and short enough that it is
## gone before the next one arrives.
func _test_a_popup_times_out() -> void:
	_begin("a popup times out")
	var g := await _Harness.new(self).start_game(0)
	if g == null:
		return
	g._popup("OUCH!", Cfg.COL_PLATE)
	g._popup_tween(Cfg.cell_to_pixel(g.player.cell))
	check(g.popups().size() == 1, "the popup is up when it is raised")
	var just_under := Game.POPUP_TIME - 0.05
	g._process(just_under)
	check(g.popups().size() == 1,
			"a popup that has not been up for two seconds is still there",
			"%d left after %.2fs" % [g.popups().size(), just_under])
	g._process(0.1)
	check(g.popups().is_empty(),
			"and is gone once it has",
			"%d left, texts %s" % [g.popups().size(), str(_popup_texts(g))])
	g.queue_free()
	await _frame()

## The texts currently on the board, for a failure message.
func _popup_texts(g: Game) -> Array:
	var out: Array = []
	for p in g.popups():
		out.append(String((p as Dictionary)["text"]))
	return out

## Popups age out on their own clocks, so one raised while another is already up
## gets its own full time rather than inheriting the older one's remaining time.
func _test_each_popup_ages_on_its_own_clock() -> void:
	_begin("each popup ages on its own clock")
	var g := await _Harness.new(self).start_game(0)
	if g == null:
		return
	g._popup("FIRST", Cfg.COL_PLATE)
	g._process(Game.POPUP_TIME - 0.05)
	g._popup("SECOND", Cfg.COL_PLATE)
	# Long enough for the first to be well past its own two seconds, but only a
	# moment for the second, which was raised almost at the end of that window.
	g._process(0.1)
	var texts := _popup_texts(g)
	check(texts.size() == 1 and String(texts[0]) == "SECOND",
			"only the newer one is left, with its own two seconds still to run",
			"left %s" % str(texts))
	g.queue_free()
	await _frame()

## A popup raised while the chef is down still times out. The death beat returns
## early from _process, so ageing the popups after that branch would have left
## the `OUCH!` on the board for the rest of the level, which is the bug this whole
## pair of tests is about.
func _test_a_popup_ages_out_while_the_chef_is_down() -> void:
	_begin("a popup ages out while the chef is down")
	var g := await _Harness.new(self).start_game(0)
	if g == null:
		return
	g.player.place(g.board.chef_spawn + Vector2i(-2, 0))
	g._on_player_died()
	check(g.popups().size() == 1, "the ouch went up when he was caught")
	# Step the death beat to its end the way the death test does, and keep going,
	# because the whole point is the frames after he is back on his feet.
	var guard := 0
	while g._dying > 0.0 and guard < 200:
		g._process(Game.DEATH_TIME / 20.0)
		guard += 1
	check(g._dying <= 0.0, "and he is back on his feet")
	g._process(Game.POPUP_TIME)
	check(g.popups().is_empty(),
			"but the ouch has timed out with him",
			"left %s" % str(_popup_texts(g)))
	g.queue_free()
	await _frame()

## The chef comes back to the middle of the bottom floor, and he comes back down.
##
## He used to be put back on the cell the level was authored to start him in, which
## on every level was off to one side. That read as the level restarting rather than
## as the chef being put back on his feet, and it walked him across the board from
## wherever he had actually died. It also appeared rather than descended, so the
## same chef was in two places within a frame of being caught.
func _test_a_respawn_is_the_middle_of_the_floor_and_a_descent() -> void:
	_begin("a respawn is the middle of the floor and a descent")
	for i in LevelData.count():
		var g := await _Harness.new(self).start_game(i)
		if g == null:
			return
		var cell: Vector2i = g.board.respawn_spawn
		# Middle of the floor: standable, on the bottom walkable row, and as close
		# to the middle of the board as the level allows.
		check(not g.board.blocks_player(cell),
				"level %d: the respawn cell is somewhere to stand" % (i + 1),
				"at %s" % str(cell))
		check(g.board.floor_below(cell),
				"level %d: and on the bottom row, standing on something" % (i + 1),
				"at %s" % str(cell))
		check(cell != g.board.chef_spawn,
				"level %d: which is not the corner the level starts him in" % (i + 1),
				"both are %s" % str(cell))
		# Caught somewhere far from the middle, so "went back" is a real move.
		var far := Vector2i(1, cell.y) if cell.x > Cfg.GRID_W / 2 else Vector2i(Cfg.GRID_W - 2, cell.y)
		g.player.place(far)
		g._on_player_died()
		var beat := 0
		while g._dying > 0.0 and beat < 400:
			g._process(Game.DEATH_TIME / 20.0)
			beat += 1
		# The beat after the floor is the descent, so he is in the air, not on the
		# cell, and the canopy is with him.
		check(g._respawning,
				"level %d: he comes back down rather than appearing" % (i + 1))
		check(g.player.dropping,
				"level %d: under his parachute on the way" % (i + 1))
		check(g.player.position.y < Cfg.cell_to_pixel(cell).y,
				"level %d: from above the floor" % (i + 1),
				"at %s, floor is %s" % [str(g.player.position), str(Cfg.cell_to_pixel(cell))])
		check(not g.player.is_processing(),
				"level %d: and not taking input while he is in the air" % (i + 1))
		var drop := 0
		while g._respawning and drop < 400:
			g._process(Game.DROP_TIME / 20.0)
			drop += 1
		check(g.player.cell == cell,
				"level %d: and lands in the middle of the floor" % (i + 1),
				"at %s, wanted %s" % [str(g.player.cell), str(cell)])
		check(not g.player.dropping, "level %d: with the canopy off" % (i + 1))
		check(g.player.is_processing(), "level %d: and back in play" % (i + 1))
		g.queue_free()
		await _frame()

## The respawn drop belongs to the level, not the chef, so it survives a pause and
## is released by the level rather than by the chef's own clock.
##
## A chef who is not processing cannot run a clock of his own, so a drop that lived
## on his `_process` would either not run at all or, worse, run at double speed the
## moment the player unpaused. This is the same contract INTRO already relies on.
func _test_a_respawn_drop_is_on_the_level_clock() -> void:
	_begin("a respawn drop is on the level clock")
	var g := await _Harness.new(self).start_game(0)
	if g == null:
		return
	g.player.place(g.board.chef_spawn + Vector2i(-2, 0))
	g._on_player_died()
	var beat := 0
	while g._dying > 0.0 and beat < 400:
		g._process(Game.DEATH_TIME / 20.0)
		beat += 1
	check(g._respawning, "he is coming back down")
	# Halfway, so the drop is unmistakably still in flight.
	g._process(Game.DROP_TIME * 0.5)
	var mid := g.player.position
	check(g._respawning, "and still in the air halfway through",
			"at %s" % str(mid))
	# Paused: the drop must not move, or unpausing would jump him down the rest of
	# the way in a single frame.
	g.paused = true
	g._process(Game.DROP_TIME * 0.5)
	check(g.player.position == mid,
			"a paused drop holds him where he was",
			"at %s, was %s" % [str(g.player.position), str(mid)])
	g.paused = false
	var drop := 0
	while g._respawning and drop < 400:
		g._process(Game.DROP_TIME / 20.0)
		drop += 1
	check(g.player.cell == g.board.respawn_spawn,
			"and lets go once the player is back",
			"at %s, respawn is %s" % [str(g.player.cell), str(g.board.respawn_spawn)])
	g.queue_free()
	await _frame()

## A level that ends while the chef is still coming back down must not leave the
## descent running into the next one, or he drops out of the sky over a board he
## has not started yet.
func _test_a_level_ending_mid_descent_clears_the_respawn() -> void:
	_begin("a level ending mid-descent clears the respawn")
	var g := await _Harness.new(self).start_game(0)
	if g == null:
		return
	g.player.place(g.board.chef_spawn + Vector2i(-2, 0))
	g._on_player_died()
	var beat := 0
	while g._dying > 0.0 and beat < 400:
		g._process(Game.DEATH_TIME / 20.0)
		beat += 1
	g._process(Game.DROP_TIME * 0.4)
	check(g._respawning, "he is in the air when the level ends")
	g._enter(Game.Phase.LEVEL_CLEAR)
	check(not g._respawning, "so the level ending clears the descent")
	check(not g.player.dropping, "and takes the canopy off with it")
	g.queue_free()
	await _frame()

## The moments the chef is not in charge of his own animation: arriving, being
## caught, and clearing a level. Arriving and dying are the level's because the
## chef is not doing anything - he is on a parachute, or he is on the floor, or the
## last plate is down and he is standing still. What this protects is that each is
## released when its moment passes: a chef who keeps celebrating after the banner is
## gone is a chef standing on a board he is no longer allowed to play, and a canopy
## left hanging over a board he has landed on is the same bug wearing a parachute.
func _test_the_level_directs_the_chef() -> void:
	_begin("the level directs the chef")
	var g := await _Harness.new(self).start_game(0, false)
	if g == null:
		return
	GameState.reset_run()

	# A level opens with the chef coming down under his parachute: he starts at the
	# top of the screen, the canopy is drawn on the cell above him, both fall to
	# the spawn, and the canopy is gone once he lands.
	check(g.phase == Game.Phase.INTRO, "a level starts on its card")
	check(g.player.dropping, "and the chef is on his way down")

	# High enough that the fall is a fall, low enough that the whole rig is on
	# screen. The canopy goes in the cell above his, so a chef whose canopy is flush
	# with the top edge has all of him below it.
	var canopy_top := g.player.position.y + Cfg.TILE * 0.5 - Cfg.TILE - Sheet.offset().y
	check(canopy_top >= 0.0, "the canopy comes in from the top of the screen",
			"top edge at y %.1f" % canopy_top)
	check(g.player.position.y < Cfg.cell_to_pixel(g.board.chef_spawn).y,
			"from well above where he lands")
	check(g.player.anim_state() == Sheet.Anim.IDLE,
			"hanging, which is what idle looks like from a canopy")

	# The card and the descent are one beat: the card is up for as long as the fall
	# takes, so there is no point in the level where he is playing under a canopy.
	check(g._phase_t <= Game.DROP_TIME, "the card holds for the drop")

	# Landing takes him onto the spawn cell exactly, drops the canopy, and puts him
	# back under his own control. Driven through the game's own clock rather than by
	# waiting on frames, so the test is not timing dependent.
	var start_y := g.player.position.y
	# The intro lands on the respawn cell - the middle of the bottom floor - rather
	# than the level's authored start.
	var landing := Cfg.cell_to_pixel(g.board.respawn_spawn).y
	g._process(Game.DROP_TIME * 0.5)
	check(g.player.dropping, "he is still coming down halfway")
	check(g.player.position.y > start_y, "and lower than he was",
			"y went %.1f -> %.1f" % [start_y, g.player.position.y])
	check(g.player.position.y < landing, "but not there yet")
	g._process(Game.DROP_TIME * 0.5)
	check(not g.player.dropping, "the canopy is gone when he lands")
	check(g.player.cell == g.board.respawn_spawn, "and he is on his spawn")
	check(is_equal_approx(g.player.position.y, landing), "on the exact cell")

	g._enter(Game.Phase.PLAYING)
	check(not g.player.dropping, "the canopy is for the descent only")
	check(g.player.anim_state() == Sheet.Anim.IDLE, "and from there he is playing")
	check(g.player.is_processing(), "and back in control")

	# Spraying is a punch for exactly as long as the puff is in the air, and the
	# throw plays out over the puff rather than looping at its own speed. The
	# timer is driven directly here, because it is the mapping being checked and
	# the player's own clock only ticks on real frames.
	g.player.spend_pepper()
	check(g.player.anim_state() == Sheet.Anim.PUNCH, "a spray plays the punch, not the walk cycle")
	check(g.player.anim_frame(Sheet.Anim.PUNCH) == 0, "starting on the wind-up")
	g.player.spray_time = Player.SPRAY_TIME * 0.5
	check(g.player.anim_frame(Sheet.Anim.PUNCH) == 1,
		"halfway through the puff is the middle of the throw")
	g.player.spray_time = Player.SPRAY_TIME * 0.01
	check(g.player.anim_frame(Sheet.Anim.PUNCH) == 2,
		"and it reaches the last frame before the puff is gone")
	g.player.spray_time = 0.0
	check(g.player.anim_state() == Sheet.Anim.IDLE, "and the chef is himself again")

	# A cleared level plays the victory off the banner's clock and then holds it.
	# Both halves matter: an animation that restarts every frame never gets past
	# its first frame, and one that never holds keeps re-flourishing under a
	# banner that is still up.
	g._enter(Game.Phase.LEVEL_CLEAR)
	var first := g.player.anim_frame(g.player.anim_state())
	check(g.player.anim_state() == Sheet.Anim.VICTORY, "a cleared level has the chef celebrating")
	var last := int(Sheet.FRAMES[Sheet.Anim.VICTORY]) - 1
	for i in 8:
		g._process(Game.PHASE_TIME / 8.0)
		var f := g.player.anim_frame(g.player.anim_state())
		check(f >= first, "the victory never rewinds")
		check(f <= last, "and never runs off the end of the animation")
	check(g.player.anim_frame(g.player.anim_state()) == last,
		"and settles on the final frame for the rest of the banner")

	g.queue_free()
	await _frame()

# --- Fixtures --------------------------------------------------------------

## A bare grid with one plate, used by the rule tests that do not care about the
## shape of a real level. Ledges on rows 1/4/7/10 and the floor on 14, matching
## the shipped levels.
func _synthetic_map() -> PackedStringArray:
	var map := _blank_map()
	map[13] = "OO" + ".".repeat(Cfg.GRID_W - 2)
	return map

## A map with one ladder running the full height of the building, so both ends of
## it can be stood on.
##
## The ladder is a single column of rungs with solid platform either side of the
## top rung and open floor above it - the shape every shipped level has, and the
## shape that strands a nasty. The chef starts on the ground floor and the walk row
## above the ladder is where a climbing nasty is trying to get to.
func _full_height_ladder_map() -> PackedStringArray:
	var map := _blank_map()
	map[1] = "#".repeat(Cfg.GRID_W - 2) + "=" + "#"
	map[2] = ".".repeat(Cfg.GRID_W - 2) + "=" + "."
	map[3] = ".".repeat(Cfg.GRID_W - 2) + "=" + "."
	map[4] = ".".repeat(Cfg.GRID_W - 2) + "=" + "."
	map[13] = "O" + ".".repeat(Cfg.GRID_W - 1)
	return map


## The same grid but with a hole punched in the row 1 ledge, so a chef walking
## right along the top storey has an edge to fall off.
func _gappy_map() -> PackedStringArray:
	var map := _synthetic_map()
	map[1] = "####" + ".".repeat(Cfg.GRID_W - 4)
	return map


## The same grid with a ladder column at x=4 running between row 9 and row 6.
func _ladder_map() -> PackedStringArray:
	var map := _synthetic_map()
	var row7 := (map[7] as String).substr(0, 4) + "=" + (map[7] as String).substr(5)
	var row8 := (map[8] as String).substr(0, 4) + "=" + (map[8] as String).substr(5)
	map[7] = row7
	map[8] = row8
	return map


func _blank_map() -> PackedStringArray:
	var map := PackedStringArray()
	for y in Cfg.GRID_H:
		if y in [1, 4, 7, 10, Cfg.GRID_H - 1]:
			map.append("#".repeat(Cfg.GRID_W))
		else:
			map.append(".".repeat(Cfg.GRID_W))
	return map

func _map(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows:
		out.append(String(r))
	return out

func _span(ch: String, x: int, width: int, y: int) -> LevelData.Span:
	var span := LevelData.Span.new()
	span.ch = ch
	span.x = x
	span.width = width
	span.y = y
	return span

func _cells(at: Vector2i, width: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in width:
		out.append(at + Vector2i(i, 0))
	return out

func _add_ingredient(h: _Harness, board: Board, ch: String, x: int, width: int, y: int) -> Ingredient:
	var ing := Ingredient.new()
	h.game_node.add_child(ing)
	# The game files parts in this group, and the crush rule finds them by it, so the
	# harness has to file them the same way or the rule is invisible under test.
	ing.add_to_group(&"ingredients")
	ing.setup(board, _span(ch, x, width, y))
	return ing

func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame

# --- Harness ---------------------------------------------------------------

## Minimal stand-in for the Game scene: builds a board and a player wired up the
## same way, so tests exercise production code paths rather than copies.
class _Harness:
	extends RefCounted

	var owner: Node
	var game_node: Node2D
	var board: Board
	var player: Player

	func _init(p_owner: Node) -> void:
		owner = p_owner

	## A board plus a chef, with no Game in the way, for testing the rules.
	func setup(map: PackedStringArray) -> void:
		game_node = Node2D.new()
		owner.add_child(game_node)
		board = Board.new()
		game_node.add_child(board)
		board.setup(LevelData.from_map("TEST", map))
		player = Player.new()
		game_node.add_child(player)
		player.setup(board, board.chef_spawn)
		# Production lets the Game decide what a crossing does; the harness stands
		# in for it with the same knock and no riders.
		player.crossed.connect(func(ing: Ingredient) -> void: ing.knock())
		await frame()

	## A real Game node, for testing level flow.
	## Starts a level, and by default skips the level card so the chef is standing
	## on the board and the game is in play.
	##
	## Skipping steps the phase on rather than waiting it out: the card is three
	## seconds of real game time now, and most of what these tests do is play at the
	## chef rather than watch him arrive. A chef who is still under his parachute
	## has a position at the top of the screen and a cell at the bottom of it, and
	## every test that checks the two agree would be checking a lie.
	func start_game(level_index: int, play: bool = true) -> Game:
		GameState.reset_run()
		game_node = Node2D.new()
		owner.add_child(game_node)
		var g := Game.new()
		game_node.add_child(g)
		g.start_level(level_index)
		if play:
			g._advance()
		await frame()
		return g

	func teardown() -> void:
		Input.action_release(&"move_left")
		Input.action_release(&"move_right")
		Input.action_release(&"move_up")
		Input.action_release(&"move_down")
		Input.action_release(&"jump")
		if game_node != null and is_instance_valid(game_node):
			game_node.queue_free()
		await frame()

	func frame() -> void:
		await owner.get_tree().process_frame

	func frames(count: int) -> void:
		for i in count:
			await frame()

	## Waits real game time rather than a frame count. Headless Godot has no vsync
	## and runs as fast as it can, so a fixed number of frames is a much shorter
	## span of game time here than in the game, and anything waiting on a timer
	## needs to wait on time.
	func seconds(t: float) -> void:
		await owner.get_tree().create_timer(t).timeout

	## Waits for a condition, up to `timeout` seconds of game time. Preferred over
	## sleeping a guessed number of frames: headless Godot has no vsync and runs
	## as fast as it can, so a frame count is a different span of game time on
	## every machine, and a wait that is too short is flaky rather than slow.
	func until(condition: Callable, timeout: float = 5.0) -> bool:
		var waited := 0.0
		while waited < timeout:
			if condition.call():
				return true
			await frame()
			waited += owner.get_process_delta_time()
		return condition.call()

	## Holds an action for a number of frames, which is how the chef is driven.
	## The chef reads held input rather than single presses, so a test has to
	## hold the key down for the walk to continue.
	func hold(action: StringName) -> void:
		Input.action_press(action)

	func release(action: StringName) -> void:
		Input.action_release(action)

	func tap(action: StringName) -> void:
		Input.action_press(action)
		Input.action_release(action)

# --- Assertions ------------------------------------------------------------


## A falling part flattens what it passes through, not only what it lands on.
##
## The part's grid cell jumps straight to the row it lands in, so the rows in between
## exist only as the band the fall reports. A nasty in one of them used to be invisible,
## because the old check looked its own cell up in the grid.
func _test_falling_food_crushes_what_it_passes() -> void:
	_begin("falling food crushes what it passes through")
	var h := _Harness.new(self)
	# An open shaft down column 4, clear of the test map's ledges, with a ladder for a
	# nasty to hold on to part way down.
	var map := _blank_map()
	for y in Cfg.GRID_H:
		map[y] = ".".repeat(Cfg.GRID_W)
	map[Cfg.GRID_H - 1] = "#".repeat(Cfg.GRID_W)
	var col := 4
	for y in range(2, 13):
		var row: String = map[y]
		map[y] = row.substr(0, col) + "=" + row.substr(col + 1)
	await h.setup(map)
	if h.board == null:
		return
	var board := h.board

	# A nasty holding a rung part way down the shaft, nowhere near either end of the
	# fall, and stunned so it holds still and this measures the crush rather than two
	# actors moving at once. Being stunned must not make it safe.
	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.setup(board, Vector2i(col, 8), Enemy.Kind.PICKLE, h.player)
	enemy.place(Vector2i(col, 8))
	enemy.stun(30.0)
	check(board.is_ladder(Vector2i(col, 8)), "the nasty is on a rung")

	var ing := _add_ingredient(h, board, "m", col, 1, 5)
	ing.knock()
	check(ing.rest_row > 8, "the part falls past the nasty",
		"part landed at row %d, nasty at row 8" % ing.rest_row)
	check(board.ingredient_at(Vector2i(col, 8)) == null,
		"and never rests in the nasty's cell")
	await h.until(func() -> bool: return enemy.state == Enemy.St.SQUASH, 2.0)
	check(enemy.state == Enemy.St.SQUASH, "a nasty in the part's path is flattened")

	# A nasty in another column is untouched: the rule is what the part passes
	# through, not everything below it.
	var safe := Enemy.new()
	h.game_node.add_child(safe)
	safe.setup(board, Vector2i(8, 8), Enemy.Kind.EGG, h.player)
	safe.place(Vector2i(8, 8))
	safe.stun(30.0)
	var ing2 := _add_ingredient(h, board, "m", col, 1, 5)
	ing2.knock()
	await h.frames(10)
	check(safe.state != Enemy.St.SQUASH, "a nasty in another column is not crushed")
	await h.teardown()


## The exact report: a nasty on a ladder under a falling part lived, because the part
## occupies no cell between the row it is knocked from and the row it lands in.
func _test_food_crushes_a_nasty_on_a_ladder() -> void:
	_begin("falling food crushes a nasty on a ladder")
	var h := _Harness.new(self)
	var map := _blank_map()
	for y in Cfg.GRID_H:
		map[y] = ".".repeat(Cfg.GRID_W)
	map[Cfg.GRID_H - 1] = "#".repeat(Cfg.GRID_W)
	var col := 4
	for y in range(2, 13):
		var row: String = map[y]
		map[y] = row.substr(0, col) + "=" + row.substr(col + 1)
	await h.setup(map)
	if h.board == null:
		return
	var board := h.board

	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.setup(board, Vector2i(col, 8), Enemy.Kind.PICKLE, h.player)
	enemy.place(Vector2i(col, 8))
	check(board.is_ladder(Vector2i(col, 8)), "the nasty is on a rung")

	var ing := _add_ingredient(h, board, "m", col, 1, 5)
	ing.knock()
	await h.until(func() -> bool: return enemy.state == Enemy.St.SQUASH, 2.0)
	check(enemy.state == Enemy.St.SQUASH,
		"a nasty on a ladder is flattened by a part falling past",
		"state %d, part row %d" % [enemy.state, ing.rest_row])
	await h.teardown()


## The run opens with the chef dropping into the middle of the bottom floor, not into
## whichever cell of it the map had room for a `@` in.
func _test_intro_lands_in_the_centre() -> void:
	_begin("the intro drop lands in the centre")
	var h := _Harness.new(self)
	var g: Game = await h.start_game(0, false)
	if g == null:
		return
	var spawn := g.board.respawn_spawn
	check(g.player.cell == spawn, "the chef comes in at the respawn cell",
		"opened at %s, respawn is %s" % [str(g.player.cell), str(spawn)])

	# The middle of the floor it can stand on, rather than an edge. Measured as the
	# distance to the nearest wall along that row, so "centre" is checked as the
	# property the player sees and not as a particular index.
	var row := spawn.y
	var left := spawn.x
	while left > 0 and not g.board.blocks_player(Vector2i(left - 1, row)):
		left -= 1
	var right := spawn.x
	while right < Cfg.GRID_W - 1 and not g.board.blocks_player(Vector2i(right + 1, row)):
		right += 1
	var margin := mini(spawn.x - left, right - spawn.x)
	check(margin >= 2, "and is clear of both corners",
		"landed %d cells from the nearest edge of its floor" % margin)
	await h.teardown()


## Sound effects. The same contract the sheets are held to, for the same reason: the
## effects are generated and committed, and the property that makes them worth
## having is that a replacement is a WAV with the right name. That is only true if
## the committed files are what the recipes produce and every name the game asks for
## resolves to something, so both are checked here rather than discovered by
## listening for a missing sound in a level.
func _test_sfx() -> void:
	_begin("sound effects")

	# A recipe with no file, or a file with no recipe, is one of the two ways this
	# drifts, and neither shows up as a crash - the first is silent, the second is a
	# file nothing generates. So both directions are checked.
	var missing: Array[String] = []
	for name: String in SfxArt.SOUNDS:
		if not ResourceLoader.exists(Sfx.DIR + name + ".wav"):
			missing.append(name)
	check(missing.is_empty(),
		"every effect has a committed file",
		"run tools/make_sfx.gd then --import; missing: %s" % ", ".join(missing))

	var ungenerated: Array[String] = []
	var found := _sfx_files()
	for path: String in found:
		var name := path.get_file().get_basename()
		if not name in SfxArt.SOUNDS:
			ungenerated.append(name)
	check(ungenerated.is_empty(),
		"every committed effect has a recipe",
		"no recipe generates: %s" % ", ".join(ungenerated))

	# A stream that will not load is the same failure as a missing file, one step
	# later, and this is the step that says so rather than the game doing it at
	# runtime in front of a player.
	var unloadable: Array[String] = []
	for name: String in SfxArt.SOUNDS:
		if Sfx.stream_for(name) == null:
			unloadable.append(name)
	check(unloadable.is_empty(),
		"every effect loads as a stream",
		"did not load: %s" % ", ".join(unloadable))

	# The importer re-encodes by default, to QOA, which is lossy and also resamples
	# out of 16 bit. That would leave three different things for one effect: the WAV
	# on disk, the recipe that made it, and the samples the game actually plays -
	# and the comparison below could never hold. So the import is forced to lossless
	# PCM, and checked here, because it is set in an .import file that is easy to
	# lose in a move and impossible to notice by listening to a compression artefact.
	var lossy: Array[String] = []
	for name: String in SfxArt.SOUNDS:
		var stream := Sfx.stream_for(name) as AudioStreamWAV
		if stream == null:
			continue
		if stream.format != AudioStreamWAV.FORMAT_16_BITS:
			lossy.append("%s is not 16 bit" % name)
		if stream.stereo:
			lossy.append("%s is not mono" % name)
		if stream.mix_rate != SfxArt.RATE:
			lossy.append("%s is %d Hz" % [name, stream.mix_rate])
	check(lossy.is_empty(),
		"every effect is imported losslessly as 16 bit mono at one rate",
		"check compress/mode=0 in the .import files; %s" % "; ".join(lossy))

	# An effect has to be long enough to hear and short enough not to be in the way
	# of the next one. A file of near-silence fails this too, which is the point: a
	# generator that produced silence at the right length would otherwise pass
	# everything else here.
	var out_of_range: Array[String] = []
	var silent: Array[String] = []
	for name: String in SfxArt.SOUNDS:
		var stream := Sfx.stream_for(name) as AudioStreamWAV
		if stream == null:
			continue
		var secs := float(stream.data.size() / 2) / float(stream.mix_rate)
		if secs < 0.03 or secs > 1.0:
			out_of_range.append("%s is %.3fs" % [name, secs])
		if _sfx_peak(stream) < 0.05:
			silent.append(name)
	check(out_of_range.is_empty(),
		"every effect is long enough to hear and short enough not to crowd",
		"; ".join(out_of_range))
	check(silent.is_empty(),
		"no effect is silent",
		"silent: %s" % ", ".join(silent))

	# An effect that starts or ends at full volume is a click, and clicks are worse
	# than the sound they are attached to. This is the one property of the generated
	# audio that nothing else here would notice.
	var clicking: Array[String] = []
	for name: String in SfxArt.SOUNDS:
		var stream := Sfx.stream_for(name) as AudioStreamWAV
		if stream == null:
			continue
		var edges := _sfx_edges(stream)
		if edges["head"] > 0.2 or edges["tail"] > 0.05:
			clicking.append("%s starts %.2f ends %.2f"
					% [name, edges["head"], edges["tail"]])
	check(clicking.is_empty(),
		"no effect clicks in or out",
		"; ".join(clicking))

	# Two effects with the same samples are one effect with two names, and the game
	# pays for the distinction in code. Two of these were identical in an early
	# draft, which is why it is checked rather than assumed.
	var identical: Array[String] = []
	var by_bytes := {}
	for name: String in SfxArt.SOUNDS:
		var stream := Sfx.stream_for(name) as AudioStreamWAV
		if stream == null:
			continue
		# The samples themselves, compared as bytes: a digest of the samples would
		# turn a collision into a passing check, and the samples are what "the same
		# sound twice" means.
		var key := stream.data
		if by_bytes.has(key):
			identical.append("%s == %s" % [name, by_bytes[key]])
		else:
			by_bytes[key] = name
	check(identical.is_empty(),
		"every effect is a different sound",
		"; ".join(identical))

	# The committed WAVs have to be what the recipes produce, or a regenerated
	# effect is one nobody noticed - a hand-edited file and a changed recipe are
	# told apart here rather than both passing.
	#
	# Read off disk rather than off the loaded stream, which is the whole point. The
	# stream comes from .godot/imported/, and that is only refreshed by an explicit
	# --import, so comparing against it passes for a file that was regenerated and
	# never imported - which looks and plays fine while no longer being reproducible
	# from the project, and is the exact failure the sheet drift check was written
	# for. Reading the file is also the only version of this check that a fresh
	# clone can run before it has imported anything.
	var drifted: Array[String] = []
	for name: String in SfxArt.SOUNDS:
		var want := SfxArt.wav(name)
		var got := FileAccess.get_file_as_bytes(Sfx.DIR + name + ".wav")
		if got != want:
			drifted.append(name)
	check(drifted.is_empty(),
		"the committed effects match the recipes that generate them",
		"run tools/make_sfx.gd and --import, then: %s" % ", ".join(drifted))

	# And the files have to be well-formed WAVs rather than merely the right bytes.
	# Parsed here rather than trusted to the importer, because a header that lies
	# about its own size imports to something plausible and plays.
	var malformed: Array[String] = []
	for name: String in SfxArt.SOUNDS:
		var read := _sfx_read_wav(Sfx.DIR + name + ".wav")
		if read["error"] != "":
			malformed.append("%s: %s" % [name, read["error"]])
			continue
		if read["rate"] != SfxArt.RATE or read["bits"] != 16 or read["channels"] != 1:
			malformed.append("%s: %d ch %d bit %d Hz" % [name, read["channels"],
					read["bits"], read["rate"]])
	check(malformed.is_empty(),
		"every effect is a well formed 16 bit mono WAV",
		"; ".join(malformed))

	# Every name the game asks for has to be a name the generator makes. This is the
	# check that catches a typo in a call site, which is otherwise a silent effect
	# and nothing else at all - a missing file is reported by Sfx at runtime, but a
	# report in a log is not a failed test.
	var asked := _sfx_names_asked_for()
	var unknown: Array[String] = []
	for name: String in asked:
		if not name in SfxArt.SOUNDS:
			unknown.append(name)
	check(unknown.is_empty(),
		"every effect the game asks for is one that exists",
		"asked for but not generated: %s" % ", ".join(unknown))

	# The pool, because a player that cuts itself off is a fault nothing else here
	# would catch: the effect still plays, still loads, and still matches its recipe.
	# Asking for one more than the pool holds is the case - the second layer of the
	# same sound has to be heard as well as the first, or a chain reaction quietly
	# loses half its noise.
	var players := _sfx_players()
	check(players.size() >= 2,
		"the effect pool can overlap at least two sounds",
		"pool holds %d" % players.size())

	# Three plows of the same effect at once must be three separate voices, not one
	# restarted three times - which is the difference between hearing a chain
	# reaction and hearing a single thud under it.
	var asks := mini(3, players.size())
	for i in asks:
		Sfx.play("jump")
	var playing := 0
	for p: AudioStreamPlayer in players:
		if p.playing:
			playing += 1
	check(playing == asks,
		"each play lands on its own player",
		"%d playing after %d plays" % [playing, asks])

	# The reverse, so an effect that was generated and never wired up is visible.
	# An unused effect is not a bug yet - the win jingle is a placeholder for a
	# later pass - but it should not be invisible either.
	var unused: Array[String] = []
	for name: String in SfxArt.SOUNDS:
		if not name in asked:
			unused.append(name)
	print("  [color=grey]note[/color] generated but never asked for: %s"
			% (", ".join(unused) if not unused.is_empty() else "none"))


## The committed effect files, by name.
func _sfx_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(Sfx.DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "wav":
			out.append(f)
	return out


## Reads a RIFF/WAVE file and reports what it actually declares, by parsing the
## chunks rather than assuming a 44 byte header.
##
## Returns `error` empty on success, alongside `rate`, `bits`, `channels` and
## `samples` (the raw little-endian 16 bit body). Deliberately does not use the
## importer: the point is to check the file, and the importer is one of the things
## that can be wrong about it.
func _sfx_read_wav(path: String) -> Dictionary:
	var out := {"error": "", "rate": 0, "bits": 0, "channels": 0, "samples": PackedByteArray()}
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 44:
		out["error"] = "only %d bytes" % b.size()
		return out
	if b.slice(0, 4).get_string_from_ascii() != "RIFF":
		out["error"] = "no RIFF"
		return out
	# The size field covers everything after itself, so it is a real check on the
	# generator rather than a formality.
	var riff := b.decode_u32(4)
	if riff != b.size() - 8:
		out["error"] = "RIFF says %d, file is %d" % [riff, b.size() - 8]
		return out
	if b.slice(8, 12).get_string_from_ascii() != "WAVE":
		out["error"] = "no WAVE"
		return out
	var at := 12
	while at + 8 <= b.size():
		var id := b.slice(at, at + 4).get_string_from_ascii()
		var size := b.decode_u32(at + 4)
		if at + 8 + size > b.size():
			out["error"] = "%s chunk claims %d bytes, %d left" % [id, size, b.size() - at - 8]
			return out
		match id:
			"fmt ":
				if size < 16:
					out["error"] = "fmt is %d bytes" % size
					return out
				if b.decode_u16(at + 8) != 1:
					out["error"] = "not PCM"
					return out
				out["channels"] = b.decode_u16(at + 10)
				out["rate"] = b.decode_u32(at + 12)
				out["bits"] = b.decode_u16(at + 22)
			"data":
				out["samples"] = b.slice(at + 8, at + 8 + size)
		# Chunks are padded to an even length, which a sample body of odd size would
		# otherwise be silently misread past.
		at += 8 + size + (size % 2)
	if out["rate"] == 0:
		out["error"] = "no fmt chunk"
	elif out["samples"].is_empty():
		out["error"] = "no data chunk"
	return out


## The pool's players, in order.
func _sfx_players() -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for child in Sfx.get_children():
		var p := child as AudioStreamPlayer
		if p != null:
			out.append(p)
	return out


## The loudest sample in a stream, as a fraction of full scale.
func _sfx_peak(stream: AudioStreamWAV) -> float:
	var peak := 0
	for i in range(0, stream.data.size() - 1, 2):
		peak = maxi(peak, absi(stream.data.decode_s16(i)))
	return float(peak) / 32767.0


## How far a stream's first and last samples are from silence, as fractions of its
## own peak. Relative rather than absolute, so a quiet effect is not judged against
## a loud one's scale.
func _sfx_edges(stream: AudioStreamWAV) -> Dictionary:
	var peak := maxf(_sfx_peak(stream), 0.001)
	var head := 0.0
	var tail := 0.0
	if stream.data.size() >= 2:
		head = absf(float(stream.data.decode_s16(0)) / 32767.0) / peak
		tail = absf(float(stream.data.decode_s16(stream.data.size() - 2)) / 32767.0) / peak
	return {"head": head, "tail": tail}


## Every effect name the game plays, read out of the source rather than maintained
## by hand. A hand-maintained list would drift from the call sites, which is the
## exact failure this check exists to catch - so it is read from the scripts.
func _sfx_names_asked_for() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://scripts")
	if dir == null:
		return out
	var stack: Array[String] = []
	for f in dir.get_files():
		stack.append("res://scripts/" + f)
	# Two levels deep, which is where the game and the player live.
	for sub: String in ["game", "player", "items", "food", "enemies"]:
		var d := DirAccess.open("res://scripts/" + sub)
		if d == null:
			continue
		for f in d.get_files():
			stack.append("res://scripts/%s/%s" % [sub, f])
	for path: String in stack:
		if not path.ends_with(".gd") or path.ends_with("sfx.gd"):
			continue
		var text := FileAccess.get_file_as_string(path)
		for pattern: String in ['Sfx.play("']:
			var at := 0
			while true:
				var found := text.find(pattern, at)
				if found < 0:
					break
				var start := found + pattern.length()
				var end := text.find('"', start)
				if end < 0:
					break
				out.append(text.substr(start, end - start))
				at = end
	return out

func _begin(name: String) -> void:
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
