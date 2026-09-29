extends Node
## Plays each level with a bot and reports how long the chef lasts.
##
##   godot --headless res://tools/survival.tscn
##   godot --headless res://tools/survival.tscn -- --level=1 --runs=8
##
## A level nobody can last ten seconds on is not a level, it is a wall. The three
## maps were tuned by feel, and feel cannot tell you a placement is unfair - it
## only tells you that it is. So this plays them.
##
## The bot is not a good player and is not trying to be one. It does the two things
## a player has to do to stay alive: go where the work is, and get out of the way of
## a nasty. That makes the number it reports a floor rather than a ceiling, which is
## the useful direction. If a level cannot be survived by something that works and
## runs, skill will not save it.
##
## What it is for is comparison. Run it, move a nasty's spawn one cell, run it again,
## and the effect of a change is a number rather than an opinion.

const Bot := preload("res://tools/survival_bot.gd")

## Seconds a single attempt may run before it is called a pass, so that surviving it
## means surviving and not nearly running out of clock.
const CAP := 60.0
## Attempts per level by default.
const RUNS := 5
## Seconds an attempt may run, set from --cap=. Cut down while working on a placement,
## so the answer arrives before patience does.
var _cap := CAP


func _ready() -> void:
	var only := -1
	var runs := RUNS
	var cap := CAP
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			only = int(arg.split("=")[1])
		elif arg.begins_with("--runs="):
			runs = maxi(1, int(arg.split("=")[1]))
		elif arg.begins_with("--cap="):
			_cap = maxf(1.0, float(arg.split("=")[1]))
	print_rich("[b]survival[/b]  %d attempt(s) per level, up to %.0fs each"
		% [runs, _cap])
	# --level=N means just that level, not every level up to it.
	var wanted: Array[int] = []
	if only < 0:
		for i in range(LevelData.count()):
			wanted.append(i)
	else:
		wanted.append(only)
	var worst := 999.0
	for i in wanted:
		var rows: Array = []
		for run in range(runs):
			rows.append(await _attempt(i, run))
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.survived < b.survived)
		var times: Array = []
		var parts := 0
		var deaths := 0
		var opening := 999.0
		for r: Dictionary in rows:
			times.append(r.survived)
			parts += r.parts
			deaths += r.deaths
			opening = minf(opening, r.survived if r.first_death < 0.0 else r.first_death)
		var low: float = times[0]
		var median: float = times[times.size() / 2]
		var high: float = times[times.size() - 1]
		worst = minf(worst, median)
		print("  level %d  survive %5.1f-%5.1fs (median %5.1f)  first catch %5.1fs  %d part(s)/run  %s"
			% [i + 1, low, high, median, opening, parts / runs, _verdict(median)])
	print("")
	if worst >= 10.0:
		print_rich("[color=green]survival: all levels clear 10s[/color]  (worst %.1fs)" % worst)
		get_tree().quit(0)
	else:
		print_rich("[color=red]survival: a level is not survivable[/color]  (worst %.1fs)" % worst)
		get_tree().quit(1)


## Say what got the chef, and where, when a catch happens. A death with no explanation
## is the one number in this tool that cannot be acted on.
func _who_caught_me(run: int, elapsed: float, chef: Vector2i,
		nasties: Array[Vector2i]) -> void:
	# Where the chef was on the last frame he was alive, not where he has just been put
	# back. The game respawns him on the spot, so reading his cell after the catch
	# reports "died at his own spawn" for every death in the game.
	var near := ""
	var best := 999
	for n in nasties:
		var d := absi(n.x - chef.x) + absi(n.y - chef.y)
		if d < best:
			best = d
			near = str(n)
	print("      caught at %.1fs on level %d run %d: chef %s, nearest live nasty %s, all %s"
		% [elapsed, GameState.level_index + 1, run + 1, str(chef), near, str(nasties)])


## Where the live nasties are, for a death report. Squashed and peppered ones are not
## catching anybody, so they are left out.
func _nasty_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e == null or not is_instance_valid(e):
			continue
		if e.state == Enemy.St.SQUASH or e.state == Enemy.St.STUN:
			continue
		out.append(e.cell)
	return out


## One attempt at one level. Returns what happened, for _ready to summarise.
func _attempt(level: int, run: int) -> Dictionary:
	GameState.reset_run()
	seed(1000 + level * 97 + run * 13)
	var host := Node2D.new()
	add_child(host)
	var game := Game.new()
	host.add_child(game)
	game.start_level(level)
	var bot := Bot.new()
	bot.setup(game)
	host.add_child(bot)

	var elapsed := 0.0
	# Counted in a one-element array rather than a plain int: a lambda captures a local
	# by value, so a bare counter would be incremented in a copy and always read back
	# as zero.
	var parts := [0]
	var deaths := 0
	var last_chefs := GameState.chefs
	var first_death := -1.0
	# The last frame the chef was alive and the last frame the nasties were where they
	# were. Game.check_catches runs before this script's loop body on any given frame, so
	# by the time chefs drops the chef has already been moved back to his spawn and the
	# catch itself is gone. These keep the frame before it.
	var prev_chef := Vector2i.ZERO
	var prev_nasties: Array[Vector2i] = []
	var trace := OS.get_environment("SURVIVAL_TRACE") != "" and run == 0
	var trace_t := 0.0
	game.player.crossed.connect(func(_ing: Ingredient) -> void: parts[0] += 1)

	# The clock starts when the level does. The card before it is a grace period,
	# not something the player had to survive, and the results after it are not
	# play at all.
	while elapsed < _cap:
		var dt := get_process_delta_time()
		if game.phase == Game.Phase.PLAYING:
			bot.think(dt)
			elapsed += dt
		elif game.phase == Game.Phase.INTRO:
			bot.rest()
		else:
			break
		if trace and run == 0 and game.phase == Game.Phase.PLAYING:
			trace_t += dt
			if trace_t > 0.4:
				trace_t = 0.0
				var p2: Player = game.player
				var part := bot._pick_part(game.board, p2.cell)
				print("      %5.1f cell=%-9s st=%d wants=%-6s flee=%s part=%-7s d=%d" % [
					elapsed, str(p2.cell), p2.state, str(bot.wants),
					str(bot.fleeing), str(part),
					absi(part.x - p2.cell.x) + absi(part.y - p2.cell.y) if part != Vector2i.ZERO else -1])
		if GameState.chefs < last_chefs:
			deaths += 1
			last_chefs = GameState.chefs
			if first_death < 0.0:
				first_death = elapsed
				_who_caught_me(run, elapsed, prev_chef, prev_nasties)
		if game.phase == Game.Phase.PLAYING:
			prev_chef = game.player.cell
			prev_nasties = _nasty_cells()
		await get_tree().process_frame

	var why := "%d part(s) down, %d caught" % [parts[0], deaths]
	why += " [work %.0fs flee %.0fs stuck %.0fs closest %d]" % [
		bot.work_s, bot.flee_s, bot.stuck_s, bot.closest]
	if game.phase == Game.Phase.LEVEL_CLEAR:
		why = "level cleared, " + why
	elif game.phase == Game.Phase.GAME_OVER:
		why = "out of chefs, " + why
	host.queue_free()
	await get_tree().process_frame
	if run == 0:
		print("    level %d attempt 1: %5.1fs  (%s)" % [level + 1, elapsed, why])
	return {"survived": elapsed, "parts": parts[0], "deaths": deaths,
		"first_death": first_death, "why": why}


func _verdict(median: float) -> String:
	if median >= 20.0:
		return "[color=green]roomy[/color]"
	if median >= 10.0:
		return "[color=yellow]survivable, tight[/color]"
	return "[color=red]not survivable[/color]"
