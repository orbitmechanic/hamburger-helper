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
##   crossing    as play, then walk the chef onto the near cell of a patty and back
##                off it again, so one cell is left pressed down with the chef
##                standing clear of it - the shape the stomp mechanic has
##   crossing_unmarked
##                as play, then stand the chef in the same cell beside the same
##                patty with nothing pressed down: the control capture that
##                "crossing" is measured against
##
## screenshot.gd reports the scene's own state, so the action is printed too:
## a capture of the wrong moment should be obvious from the log rather than
## something to be noticed later.

const ACTIONS := ["play", "pepper", "respawn", "popup_gone", "stunned", "ground",
		"crossing", "crossing_unmarked"]

var game: Game

## Set once the action above has run to completion.
##
## Read by tools/screenshot.gd, which otherwise captures whenever its frame cap
## arrives - so an action that needs more real game time than the cap allows is
## photographed part way through, with nothing in the log to say so. That is how
## the control capture came to show the chef still standing on the patty the
## comparison needs him clear of, which made a pixel check measure where he was
## rather than how the patty was drawn.
var shot_done := false


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
	shot_done = true
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


## Walks the chef onto the near end of a part, then back off it, so the capture
## shows one cell pressed down with its neighbours at full height - the shape the
## whole mechanic is about. A capture of a part part way *thinned* is a different
## picture again, and there is no such state any more.
##
## Driven through held input and stopped by letting go, because place() does not
## stomp by design - repositioning the chef is not the same as walking him, and a
## capture set up with place() would show a part untouched and look exactly like the
## stomps not working.
##
## Only the first cell is stomped rather than as many as will fit, because the part
## drops when the last cell goes and a capture of a part dropping is a different
## picture again. Stopping at the near end also leaves two cells of run-out, so a
## chef still carrying a step of momentum cannot tip the capture into the drop.
##
## Then he is walked back off the part. The stomps stay put until the part lands, so
## he can step off and leave the pressed cell showing - which is also the only way
## to capture the offset, because a chef standing in the cell covers the very row
## that moved.
func _run_part_way_across_a_part() -> void:
	var ing := _patty()
	if ing == null:
		return
	var near := ing.cells[0]
	# Off the near end, so the first step lands on the part and counts.
	game.player.place(near + Vector2i.LEFT)
	await _at_frame(1)
	var reached := await _walk_until(func() -> bool: return ing.is_stomped(near))
	await _stand_clear_of(ing)
	# Reported either way, because the walk is real game time and the capture is a
	# frame budget: if the budget ran out first the capture is a part at rest and
	# looks exactly like the stomps not working, so the log has to say they did not
	# arrive rather than leave it to be noticed.
	print("shot_scripted: %d of %d cells stomped (%s), each down %.1fpx, part %s%s" % [
			ing.stomped_count(), ing.cells.size(), str(near), ing.stomp_drop(),
			"at rest" if not ing.falling else "FALLING",
			"" if reached else " (WALK DID NOT FINISH)"])


## Walks the chef back off the part and leaves him standing still in the cell
## before it.
##
## Both stomp captures end here, and the reason they share it is that the two
## pictures are compared pixel by pixel: the chef has to be in the same cell,
## standing still on the same animation frame, in both or he covers a different
## amount of the part and the comparison measures him rather than the stomp. He
## also has to be *off* the part, because a chef in the stomped cell covers the
## only rows that moved.
func _stand_clear_of(ing: Ingredient) -> void:
	var clear_of := ing.cells[0] + Vector2i.LEFT
	Input.action_press(&"move_left")
	var off := 0.0
	while (game.player.cell != clear_of or game.player.moving) and off < 3.0:
		await get_tree().process_frame
		off += get_process_delta_time()
	Input.action_release(&"move_left")
	# A fixed settle, not a frame budget: the pose is a function of how long the
	# chef has been still, and both captures have to land on the same one.
	await _at_frame(8)


## Holds right until a condition holds or the budget runs out, so a scripted walk
## cannot hang the capture on a condition the game never reaches.
##
## Presses and releases around the wait itself rather than leaving the caller to do
## it, so there is one place that owns the key and a run cannot end with it stuck
## down and the next action walking off under a held arrow.
func _walk_until(done: Callable) -> bool:
	Input.action_press(&"move_right")
	var waited := 0.0
	while not done.call() and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	Input.action_release(&"move_right")
	# Let the step that got him there finish arriving, or the stomp is a cell behind
	# where the picture says he is.
	await _at_frame(6)
	return done.call()


## Puts the chef beside the same part with nothing stomped, for the control capture.
##
## Walks him off the near end exactly as the stomping capture does, because the two
## captures are only comparable if the chef is in the same place in both: he is
## standing clear of the part in 13, and a control with him still on it would be
## measuring where the chef is rather than how the patty is drawn.
##
## place() rather than a walk to get him onto the part in the first place, because
## place() does not stomp by design - repositioning the chef is not the same as
## walking him over, and a part he is merely standing on is exactly the unstomped
## state the control needs.
func _park_on_a_part() -> void:
	var ing := _patty()
	if ing == null:
		return
	var spot := ing.cells[0]
	game.player.place(spot)
	await _at_frame(6)
	await _stand_clear_of(ing)
	print("shot_scripted: parked on an unstomped part at %s, %d of %d cells down" % [
			str(spot), ing.stomped_count(), ing.cells.size()])


## The first patty at least three cells wide.
##
## A patty specifically, and not just any wide part, because the capture check
## measures pixels of a colour it can name: Food.color_of(PATTY) is something
## visual_check.gd can derive from the game's own palette, whereas which part the
## scene happened to build first is not something it could know. Every shipped level
## has three-cell patties.
##
## Quits rather than returning null to be captured anyway. shots.sh fails a run on a
## script or a parse error and push_error alone is neither, so without this a level
## with no usable patty would produce a capture of an unmarked patty - which reads as
## the marker not working, and would be found much later as a confusing pixel diff
## rather than as the level that caused it.
func _patty() -> Ingredient:
	for n in get_tree().get_nodes_in_group(&"ingredients"):
		var ing := n as Ingredient
		if ing != null and ing.kind == Food.Kind.PATTY and ing.cells.size() >= 3:
			return ing
	push_error("no patty three cells or wider on this level to run across")
	get_tree().quit(1)
	return null


func _ground_every_plate() -> void:
	for plate in game.board.plates:
		var recipe: Array = game.level.recipe(plate)
		# Through the board's own push, not by appending to its stack: push_to_stack
		# seeds the pile with the bottom bun and redraws, which is both why the
		# recipe's first entry is skipped and why there is no queue_redraw() here.
		for i in range(1, recipe.size()):
			game.board.push_to_stack(plate, recipe[i])
