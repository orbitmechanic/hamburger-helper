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
	await _test_parts_are_centred()
	_test_ingredient_columns_line_up()
	_test_burgers_have_room()
	_test_enemies_are_spread_out()
	_test_nasties_are_slow()
	_test_burger_order()
	_test_burgers_are_half_height()
	_test_sheets()
	_test_burger_scoring()
	await _test_board_tiles()
	await _test_landing_spot()
	await _test_single_knock_falls_one_storey()
	await _test_food_lands_on_a_ledge()
	await _test_chain_reaction()
	await _test_column_builds_a_burger()
	await _test_crossing_needs_the_full_width()
	await _test_player_jump()
	await _test_ladder_climb()
	await _test_player_falls_off_a_ledge()
	await _test_pepper_stuns_a_nasty()
	await _test_pepper_is_fired_by_a_key()
	await _test_falling_food_squashes()
	await _test_riding_a_part()
	await _test_game_starts_every_level()
	await _test_burger_completes_the_level()
	await _test_running_out_of_chefs()
	await _test_a_death_resets_the_nasties()

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


## The chain: knocking the top of a column moves the lot.
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
	check(not is_instance_valid(top) or top.falling, "the top part is on its way down")
	check(Food.stack_is_burger(board.stack(0)),
		"the whole column lands and builds a burger",
		"stack is %s" % str(board.stack(0)))
	var order := board.stack(0)
	check(order.size() == 4, "every part reached the plate", "stack size is %d" % order.size())
	check(order[1] == Food.Kind.PATTY, "the patty is the first to arrive")
	check(order[2] == Food.Kind.LETTUCE, "then the lettuce")
	check(order[3] == Food.Kind.BUN_TOP, "and the lid last, so the order comes out right")
	check(order[0] == Food.Kind.BUN_BOTTOM, "on top of the base bun the plate provides")
	h.teardown()


## The same thing driven by the chef rather than by a direct knock, which is the
## path a player actually takes.
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
	# Start beside the lid, not on it, so the crossing is walked end to end.
	h.player.place(Vector2i(0, 3))

	# Walk right across both of the lid's cells and off the end of it.
	h.hold(&"move_right")
	await h.frames(120)
	h.release(&"move_right")
	await h.frames(30)

	check(Food.stack_is_burger(board.stack(0)), "walking across the lid builds the burger",
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


## The jump is a dodge, not a way to climb: one cell in the facing direction.
func _test_player_jump() -> void:
	_begin("player jump")
	var h := _Harness.new(self)
	await h.setup(_synthetic_map())
	var board := h.board
	if board == null:
		return

	h.player.place(Vector2i(4, 0))
	h.player.facing = 1
	h.tap(&"jump")
	await h.frames(4)
	check(h.player.state == Player.St.JUMP or h.player.cell.x == 5,
		"the jump starts")
	await h.frames(30)
	check(h.player.cell.x == 5, "the jump covers one cell", "x is %d" % h.player.cell.x)
	check(h.player.cell.y == 0, "and does not change row", "y is %d" % h.player.cell.y)
	check(h.player.state == Player.St.WALK, "and it ends standing")
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

	check(not h.player.ghost(), "the chef starts solid")
	h.player.add_pepper(2)
	check(h.player.pepper_left == 2, "pepper goes in the jar")
	check(h.player.use_pepper(), "and can be spent")
	check(h.player.ghost(), "spending it makes the chef pass through")
	check(not h.player.use_pepper() or h.player.pepper_left == 0, "each charge is one use")

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
	h.teardown()


## The character sheets, checked as images rather than trusted.
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

	# Every promised frame has art in it and every padding cell is clear.
	var blank_used := []
	var dirty_pad := []
	for character: String in Sheet.CHARACTERS:
		for anim in Sheet.ROWS:
			for frame in int(Sheet.FRAMES[anim]):
				if _cell(character, anim, frame)["n"] == 0:
					blank_used.append("%s r%d f%d" % [character, Sheet.row(anim), frame])
			for frame in range(int(Sheet.FRAMES[anim]), Sheet.COLUMNS):
				if _cell(character, anim, frame)["n"] > 0:
					dirty_pad.append("%s r%d f%d" % [character, Sheet.row(anim), frame])
	check(blank_used.is_empty(), "every frame in the layout has art in it",
		"blank %s" % ", ".join(blank_used))
	check(dirty_pad.is_empty(), "padding cells are empty",
		"unexpected art in %s" % ", ".join(dirty_pad))

	# The frames of an animation have to differ from each other, or it is one
	# picture with a row of copies of itself.
	var still := []
	for character: String in Sheet.CHARACTERS:
		for anim in Sheet.ROWS:
			if int(Sheet.FRAMES[anim]) < 2:
				continue
			var sigs := {}
			for frame in int(Sheet.FRAMES[anim]):
				sigs[_cell(character, anim, frame)["sig"]] = true
			if sigs.size() == 1:
				still.append("%s row %d" % [character, Sheet.row(anim)])
	check(still.is_empty(), "frames within an animation differ from each other",
		"identical frames in %s" % ", ".join(still))

	# Everyone stands on the baseline: there is art in the bottom row of the cell
	# and none below it, which is what Sheet's anchor promises. A character drawn
	# a pixel high floats, and it is the kind of thing that survives a redraw.
	var off_baseline := []
	var never_lands := []
	for character: String in Sheet.CHARACTERS:
		for anim in Sheet.ROWS:
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
		for anim in Sheet.ROWS:
			for frame in range(Sheet.COLUMNS):
				var c := _cell(character, anim, frame)
				if c["n"] > 0 and (c["right"] >= Sheet.CELL.x or c["low"] >= Sheet.CELL.y):
					spills.append("%s r%d c%d" % [character, Sheet.row(anim), frame])
	check(spills.is_empty(), "no frame spills out of its cell",
		"spilling in %s" % ", ".join(spills))

	# The chef's eyes only show when he is facing somewhere, which the old drawing
	# code did by faking a facing of zero on a ladder. The climb frames have to
	# carry that themselves now.
	var eyes := [Vector2i(9, 11), Vector2i(11, 11)]
	var climb_eyes := 0
	for frame in int(Sheet.FRAMES[Sheet.Anim.CLIMB]):
		for at in eyes:
			if _pixel(Sheet.CHEF, Sheet.Anim.CLIMB, frame, at) == Cfg.COL_OUTLINE:
				climb_eyes += 1
	var walk_eyes := 0
	for at in eyes:
		if _pixel(Sheet.CHEF, Sheet.Anim.WALK, 0, at) == Cfg.COL_OUTLINE:
			walk_eyes += 1
	check(walk_eyes == eyes.size(), "the chef has eyes when he is walking",
		"%d of %d" % [walk_eyes, eyes.size()])
	check(climb_eyes == 0, "and none while he is on a ladder",
		"%d stray eye pixels" % climb_eyes)

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
				if not got.get_pixel(x, y).is_equal_approx(painted.get_pixel(x, y)):
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
		for anim in Sheet.ROWS:
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
			if c.is_equal_approx(Cfg.COL_BG):
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
	player.pepper_time = 0.0
	check(not player.ghost(), "the chef starts solid")

	# The key with an empty jar does nothing at all, and says so.
	Input.action_press(&"pepper")
	await h.frame()
	Input.action_release(&"pepper")
	await h.frame()
	check(not player.ghost(), "pressing pepper with an empty jar does nothing")
	check(_last_popup(g) == "NO PEPPER", "and the chef is told why",
		"popup was %s" % _last_popup(g))

	# With a charge in the jar, the key opens the window.
	player.add_pepper(1)
	Input.action_press(&"pepper")
	await h.frame()
	Input.action_release(&"pepper")
	await h.frame()
	check(player.ghost(), "the pepper key makes the chef shimmer")
	check(player.pepper_left == 0, "and spends a charge",
		"%d left" % player.pepper_left)
	check(_last_popup(g) == "PEPPER!", "with a confirmation")

	# A nasty that walks into the shimmer is stunned, and the dose already paid
	# for is not charged twice. The check is driven directly rather than left to
	# a frame of game time, so it cannot lose a race with the nasty's own
	# movement or with the five second dose running out.
	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.add_to_group(&"enemies")
	enemy.setup(g.board, player.cell + Vector2i.RIGHT, Enemy.Kind.HOTDOG, player)
	enemy.place(player.cell + Vector2i.RIGHT)
	player.pepper_time = Player.PEPPER_TIME
	g._check_catches()
	check(enemy.state == Enemy.St.STUN, "a nasty touching the shimmer is stunned",
		"state is %d" % enemy.state)
	check(player.pepper_left == 0, "zapping does not spend a second charge",
		"%d left" % player.pepper_left)

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
	var enemy := Enemy.new()
	h.game_node.add_child(enemy)
	enemy.setup(board, Vector2i(6, 6), Enemy.Kind.PICKLE, h.player)
	check(enemy.riding(ing), "the nasty is standing on the part")

	# One knock would take this part from row 6 to the row 9 ledge. A nasty riding
	# it buys a second drop, so it goes all the way to the ground instead.
	ing.knock()
	await h.until(func() -> bool: return not ing.falling)
	check(ing.rest_row == 9, "a part on its own falls one storey",
		"row is %d" % ing.rest_row)

	ing.knock(1)
	await h.until(func() -> bool: return not ing.falling)
	check(ing.rest_row == Cfg.GRID_H - 2, "and with a rider it falls two",
		"row is %d" % ing.rest_row)
	h.teardown()


# --- Game flow -------------------------------------------------------------


func _test_game_starts_every_level() -> void:
	_begin("game starts")
	for i in LevelData.count():
		var g := await _Harness.new(self).start_game(i)
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

	# Drive every part of the first column onto its plate, from the top down.
	var board := g.board
	var plate_x := g.level.plates[0].x
	var column: Array = []
	for ing in g.level.ingredients:
		if ing.overlaps(g.level.plates[0]):
			column.append(ing)
	column.sort_custom(func(a: LevelData.Span, b: LevelData.Span) -> bool: return a.y < b.y)
	check(not column.is_empty(), "the first plate has a column of parts to drop")

	for span in column:
		var live := board.ingredient_at(Vector2i(span.x, span.y))
		if live != null:
			live.knock()
		await _frame()
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

	# Park every nasty on top of the chef's spawn, which is the situation that
	# used to eat the whole run.
	var homes := []
	for e in nasts:
		var enemy := e as Enemy
		homes.append(enemy.home_cell)
		enemy.place(g.board.chef_spawn)
	var parked := true
	for e in nasts:
		if (e as Enemy).cell != g.board.chef_spawn:
			parked = false
	check(parked, "the test parks every nasty on the spawn")

	var before := GameState.chefs
	g._on_player_died()
	check(GameState.chefs == before - 1, "the chef loses one")
	check(g.player.cell == g.board.chef_spawn, "and goes back to his spawn")

	var all_home := true
	for i in nasts.size():
		if (nasts[i] as Enemy).cell != homes[i]:
			all_home = false
	check(all_home, "and every nasty is back on its own ledge")

	# The point of all that: the chef is not standing in a nasty's arms any more,
	# so he is not killed again the instant he respawns.
	var clear := true
	for e in nasts:
		if (e as Enemy).cell == g.board.chef_spawn:
			clear = false
	check(clear, "so nobody is left on top of him")
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
		await frame()

	## A real Game node, for testing level flow.
	func start_game(level_index: int) -> Game:
		GameState.reset_run()
		game_node = Node2D.new()
		owner.add_child(game_node)
		var g := Game.new()
		game_node.add_child(g)
		g.start_level(level_index)
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
