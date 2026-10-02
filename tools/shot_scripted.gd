extends Node2D
## Captures the game in a state that needs driving rather than waiting for.
##
## tools/screenshot.gd can start a scene and wait N frames, which is enough for a
## board that builds itself but not for a moment the player has to cause: a pepper
## spray, a chef under a parachute, a nasty frozen by seasoning. Those all need an
## input or a call, and a capture taken at an arbitrary frame count is a guess.
##
## So this wraps a real Game, gets it into play, performs a named action on a
## chosen frame, and then lets screenshot.gd do what it does.
##
##   SHOT_SCENE=res://tools/shot_scripted.tscn \
##   SHOT_OUT=/tmp/pepper.png SHOT_FRAMES=12 \
##   godot --rendering-driver opengl3 --resolution 256x240 tools/screenshot.tscn
##
## Env:
##   SHOT_ACTION  one of the actions below; defaults to "play" (no action, just
##                the level in play, for a baseline capture)
##   SHOT_LEVEL   level index, 0-based (default 0)
##
## Actions:
##   play        start the level and skip the level card
##   pepper      as play, then throw one dose to the right
##   respawn     as play, then kill the chef and hold the frame just after the
##                parachute has started, so a respawn descent can be seen
##   popup_gone  as play, then kill the chef and run the clock past the popup's
##                two seconds, so the "caught" popup is seen to have taken itself
##                off the board rather than left lying on it
##   stunned     as play, then freeze every nasty on the board
##   ground      as play, then complete one burger on every plate, so the drawn
##                stacks can be seen
##   crossing    as play, then walk the chef all but one cell across a patty and
##                stop, so the part's run-over marker - a fifth of its thickness
##                off per cell - is on screen
##   crossing_unmarked
##                as play, then stand the chef on the same cell of the same patty
##                with no crossing under way: the control capture that
##                "crossing" is measured against
##
## screenshot.gd reports the scene's own state, so the action is printed too:
## a capture of the wrong moment should be obvious from the log rather than
## something to be noticed later.

const ACTIONS := ["play", "pepper", "respawn", "popup_gone", "stunned", "ground",
		"crossing", "crossing_unmarked"]

var game: Game


func _ready() -> void:
	var level := int(OS.get_environment("SHOT_LEVEL")) \
		if OS.get_environment("SHOT_LEVEL") != "" else 0
	var action := OS.get_environment("SHOT_ACTION")
	if action == "":
		action = "play"
	if not ACTIONS.has(action):
		push_error("SHOT_ACTION %s is not one of %s" % [action, str(ACTIONS)])
		get_tree().quit(1)
		return

	GameState.reset_run()
	# reset_run puts the run back to the first level, and the scene's own _ready
	# starts whichever level GameState points at. So the level has to be chosen
	# before the scene is built, not after: setting it once the game is running
	# would be overwritten by start_level, and SHOT_LEVEL would end up naming a
	# level in the log while the capture held a different one - which is the one
	# outcome this whole tool exists to rule out.
	if level > 0:
		if level >= LevelData.count():
			push_error("SHOT_LEVEL %d is past the last level (%d)" % [
				level, LevelData.count() - 1])
			get_tree().quit(1)
			return
		GameState.level_index = level
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	# Straight into play: the level card is a three second wait and nothing here is
	# about the card.
	game._advance()
	# Park the nasties. They patrol on a coin flip, so two captures of the same
	# moment differ by several hundred pixels of them walking about - more than the
	# thing being looked at. Frozen, the only difference between two captures is
	# the thing the action actually did, which is the point of taking them.
	_park_nasties()
	# The level reported is the one the game is actually on, read back off the
	# state rather than echoed from the request, so a level that did not take
	# shows up here as the level it really is.
	print("shot_scripted: action=%s level=%d (%s)" % [
			action, GameState.level_index, game.level.name])

	# Applied on a later frame so the level has finished building first.
	var at := 2
	match action:
		"pepper":
			await _at_frame(at)
			# Through the real input path rather than by calling _fire_pepper(), which
			# is gated on is_action_just_pressed and would quietly do nothing here -
			# a capture that looks identical to the baseline is worse than no capture.
			game.player.facing = 1
			Input.action_press(&"pepper")
			await get_tree().process_frame
			Input.action_release(&"pepper")
			print("shot_scripted: pepper thrown, %d charge(s) left, spray_time=%.4f"
				% [game.player.pepper_left, game.player.spray_time])
			# Diagnostic: hold the puff open so the capture cannot miss it. SPRAY_TIME
			# is 0.18s, which is a couple of frames in a container, so a capture taken
			# after it has expired shows nothing and looks like "the spray does not
			# render" when it may only mean "the spray is too brief to see".
			# Freeze the clock rather than extending the timer. The punch frame is
			# chosen from spray_time, so writing a longer time into it selects a
			# frame index past the end of the row and the chef draws nothing at all -
			# which looks exactly like "the effect is broken" and is not.
			if OS.get_environment("SHOT_HOLD_SPRAY") != "":
				Engine.time_scale = 0.0
			print("shot_scripted: at fire -> pos=%s facing=%d spray_time=%.4f" % [
				str(game.player.position), game.player.facing, game.player.spray_time])
		"respawn":
			# Caught, then the game's own clock run through the death beat and into
			# the middle of the respawn descent. Nothing is set up by hand here: the
			# point is to photograph the real flow, so if the canopy is missing from
			# the capture the game really is not drawing it.
			await _at_frame(at)
			game._on_player_died()
			game._process(Game.DEATH_TIME + 0.05)
			game._process(Game.DROP_TIME * 0.45)
			print("shot_scripted: respawning=%s dropping=%s cell=%s" % [
					game._respawning, game.player.dropping, str(game.player.cell)])
		"popup_gone":
			# Caught, then the clock run on well past the popup's two seconds. The
			# ouch has to have taken itself off the board by then.
			await _at_frame(at)
			game._on_player_died()
			game._process(Game.DEATH_TIME + 0.05)
			game._process(Game.POPUP_TIME + 0.1)
			print("shot_scripted: popups left after the timeout: %d" % game.popups().size())
		"stunned":
			await _at_frame(at)
			for e in get_tree().get_nodes_in_group(&"enemies"):
				(e as Enemy).stun(30.0)
				(e as Enemy).set_process(false)
		"ground":
			await _at_frame(at)
			_ground_every_plate()
		"crossing":
			await _at_frame(at)
			await _run_part_way_across_a_part()
		"crossing_unmarked":
			# The control for "crossing": the chef in exactly the same cell, on the same
			# part, with no crossing under way. Comparing the two isolates the squash,
			# because the chef occludes the part in both and only the mark differs. A
			# comparison against 06-play would not: the chef is somewhere else in that
			# one, so it covers part of the same pixels and the two effects cannot be
			# told apart.
			await _at_frame(at)
			_park_on_a_part()
	await get_tree().process_frame
	_report()


func _at_frame(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Stops every nasty where it stands, so a capture is repeatable.
##
## The facing is pinned as well as the position, and that is not fussiness. Enemy
## setup seeds facing from randf(), and the sprite is mirrored by it, so two runs
## of the same action came back differing by a dozen pixels - one nasty's lit foot
## highlight on the left in one and on the right in the other. Twelve pixels is
## enough for a "these two captures differ" check to pass, which is precisely the
## check meant to catch an action that did nothing, so it has to be made true
## rather than argued with.
func _park_nasties() -> void:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Enemy
		enemy.set_process(false)
		enemy.place(enemy.home_cell)
		enemy.facing = 1


## Completes every plate's burger by dropping each recipe's parts straight onto the
## stack, so a capture can show finished burgers rather than empty plates.
## Prints the chef's state on the last frame, so a capture that missed its moment
## says so in the log rather than being discovered later as "the effect is broken".
func _report() -> void:
	if game == null or game.player == null:
		return
	var pl := game.player
	var an := pl.anim_state()
	print("shot_scripted: at capture -> pos=%s cell=%s spray_time=%.4f visible=%s" % [
		str(pl.position), str(pl.cell), pl.spray_time, pl.visible])
	print("shot_scripted: anim=%d frame=%d pose_anim=%d _anim=%d processing=%s" % [
		an, pl.anim_frame(an), pl.pose_anim, pl._anim, pl.is_processing()])


## Walks the chef over all but the last cell of a part and stops there, so the
## capture shows a part part way run over rather than one either untouched or
## already dropping.
##
## Driven through held input and stopped by letting go, because place() throws the
## crossing away by design - repositioning the chef is not the same as walking him,
## and a capture set up with place() would show a part at full thickness and look
## exactly like the marker not working.
##
## One cell short of the end, so the capture is of a crossing still in progress: the
## last cell completes it, and a part mid-drop is a different picture again.
func _run_part_way_across_a_part() -> void:
	var ing := _patty()
	if ing == null:
		return
	var stop_at := ing.cells.size() - 1
	# Off the near end, so the first step lands on the part and counts.
	game.player.place(ing.cells[0] + Vector2i.LEFT)
	await _at_frame(1)
	Input.action_press(&"move_right")
	var waited := 0.0
	while ing.cross_cells < stop_at and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	Input.action_release(&"move_right")
	# Let the step that took him onto the last cell finish arriving, or the mark is a
	# cell behind where the picture says he is.
	await _at_frame(6)
	# Reported either way, because the walk is real game time and the capture is a
	# frame budget: if the budget ran out first the capture is a part at rest and
	# looks exactly like the marker not working, so the log has to say the mark did
	# not arrive rather than leave it to be noticed.
	print("shot_scripted: run over %d of %d cells, drawn at %.0f%%%s" % [
			ing.cross_cells, ing.cells.size(), ing.cross_thickness() * 100.0,
			"" if ing.cross_cells >= stop_at else " (WALK DID NOT FINISH)"])


## Stands the chef on the middle of a part with no crossing started, for the control
## capture. place() rather than a walk, because place() throws the crossing away by
## design - repositioning the chef is not the same as walking him over, and a part
## he is merely standing on is exactly the unmarked state the control needs.
func _park_on_a_part() -> void:
	var ing := _patty()
	if ing == null:
		return
	game.player.place(ing.cells[ing.cells.size() / 2])
	await _at_frame(6)
	print("shot_scripted: parked on an unmarked part at %s, drawn at %.0f%%" % [
			str(ing.cells[ing.cells.size() / 2]), ing.cross_thickness() * 100.0])


## The first patty at least three cells wide.
##
## A patty specifically, and not just any wide part, because the capture check
## measures pixels of a colour it can name: Food.color_of(PATTY) is something
## visual_check.gd can derive from the game's own palette, whereas which part the
## scene happened to build first is not something it could know. Every shipped level
## has three-cell patties, and failing loudly beats quietly capturing the wrong one.
func _patty() -> Ingredient:
	for n in get_tree().get_nodes_in_group(&"ingredients"):
		var ing := n as Ingredient
		if ing != null and ing.kind == Food.Kind.PATTY and ing.cells.size() >= 3:
			return ing
	push_error("no patty three cells or wider on this level to run across")
	return null


func _ground_every_plate() -> void:
	for plate in game.board.plates:
		var recipe: Array = game.level.recipe(plate)
		# Through the board's own push, not by appending to its stack: push_to_stack
		# seeds the pile with the bottom bun and redraws, which is both why the
		# recipe's first entry is skipped and why there is no queue_redraw() here.
		for i in range(1, recipe.size()):
			game.board.push_to_stack(plate, recipe[i])
