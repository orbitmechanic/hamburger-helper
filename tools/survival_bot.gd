extends Node2D
## A bot that plays the game, for tools/survival.gd to time.
##
## Not a good player, and deliberately not trying to be one. It does the two things a
## player has to do to stay alive: go where the work is, and get out of the way of a
## nasty. That makes the number it reports a floor rather than a ceiling, which is the
## useful direction - if a level cannot be survived by something that works and runs,
## no amount of skill will save it.
##
## The movement rules are copied from Player._drive and Player._climb rather than shared
## with them, because a bot that shares the player's own helpers cannot discover that a
## level is unreachable. Written out separately, a route the bot finds is one the player
## can walk.

## The four ways to step, in the order they are tried. Order matters: it is the tie-break
## when two routes are the same length, and a bot that changes its mind every tick
## because the search happened to return a different equal-length answer spends the level
## pacing on the spot.
const DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

## How close a nasty has to get before the bot stops working and runs. Far enough to have
## time to get away, close enough not to spend the level flinching. The chef walks a cell
## in about an eighth of a second and a nasty in nearly half of one, so even a step is a
## comfortable lead; the trigger is where it is so a bot that is mid-work still breaks away
## with room to spare rather than trying to squeeze one more cell out of a part the moment
## a nasty lands on it. One cell of lead is one nasty step of time, which is four chefl steps.
const FLEE_CELLS := 3
## Seconds between reconsiderations. The chef takes about a fifth of a second to walk a
## cell, so thinking faster than this cannot produce a different step anyway.
const DECIDE_EVERY := 0.18
## Extra cells of daylight the bot wants before it settles down and goes back to
## work. Without it the bot stops running the instant the gap is one cell wider than
## it was when it started, turns round, meets the nasty again, and runs back - which
## on a ladder is a loop that never gets anywhere and never gets caught either.
const FLEE_RELEASE := 2
## How far ahead the bot looks for somewhere better to be.
const ESCAPE_LOOK := 6
## Seconds a route is followed before it is looked at again. Long enough to get
## somewhere, short enough to notice the world changing underneath.
const ROUTE_TTL := 1.5

var game: Game
var alive := true

## Cells at which the bot gives up working and runs, overridable so it can be swept.
var flee_cells := FLEE_CELLS

## Counters, for tools/survival.gd to print so a bad number can be explained.
var work_s := 0.0
var flee_s := 0.0
var stuck_s := 0.0
var closest := 999

var _held: Array[String] = []
var _think_t := 0.0
## The route being walked, as the cells to reach in order.
var _route: Array[Vector2i] = []
## How far along the route the chef is.
var _route_at := 0
## The part being worked on, held until it drops or turns out to be out of reach.
var _goal := Vector2i.ZERO
var _route_t := 0.0
## The part being walked across, and which of its cells the chef has stood in.
var _crossing: Ingredient = null
var _covered := {}
## What it is currently pressing, for tracing.
var wants := Vector2i.ZERO
var fleeing := false
var _fleeing := false


func _ready() -> void:
	var env := OS.get_environment("SURVIVAL_FLEE")
	if env != "":
		flee_cells = int(env)


func setup(p_game: Game) -> void:
	game = p_game


## Let go of everything and stop working, for the level card and the results.
func rest() -> void:
	_release_all()
	_route.clear()
	_goal = Vector2i.ZERO
	_crossing = null
	_covered.clear()
	wants = Vector2i.ZERO
	fleeing = false


## One tick. Drives the same input actions a player would press.
func think(delta: float) -> void:
	if game == null or game.player == null or not is_instance_valid(game.player):
		return
	var board := game.board
	var player: Player = game.player
	if board == null or game.phase != Game.Phase.PLAYING or player.state == Player.St.FALL:
		rest()
		return

	_think_t -= delta
	if _think_t > 0.0:
		return
	_think_t = DECIDE_EVERY
	_choose(board, player)
	if fleeing:
		flee_s += DECIDE_EVERY
	elif wants == Vector2i.ZERO:
		stuck_s += DECIDE_EVERY
	else:
		work_s += DECIDE_EVERY


# --- Deciding ---------------------------------------------------------------


func _choose(board: Board, player: Player) -> void:
	# A nasty this close outranks any amount of work.
	var threat := _nearest_nasty(player.cell)
	if _fleeing:
		fleeing = threat >= 0 and threat <= flee_cells + FLEE_RELEASE
		_fleeing = fleeing
	else:
		fleeing = threat >= 0 and threat <= flee_cells
		_fleeing = fleeing
	if fleeing:
		# There is deliberately no fall-through to the work branch from here. A chef
		# who knows a nasty is close but has no better cell to stand in still must not
		# start on a part: the part is usually in the same corridor as the nasty, and
		# the "no better cell" answer means the search can see no cell nearby that the
		# nasty cannot reach, so the best use of the half second he has is to hold his
		# ground and buy the searcher another decision, not to invite the nasty over.
		_hold(_best_escape(board, player.cell, _nasty_cells()))
		return

	# On the same storey as a part, and able to reach it by walking: cross it. A part
	# only drops once every one of its cells has been stood in, so this walks him along
	# the whole width rather than stepping onto the middle of one and stopping.
	var cross := _crossing_step(board, player.cell)
	if cross != Vector2i.ZERO:
		_route.clear()
		_hold(cross)
		return

	# Work towards a part. The goal is held rather than re-picked every tick, because
	# two parts on the same storey swap places as the chef walks past the midpoint
	# between them, and a bot that re-picks on every tick walks between the two of them
	# forever. It is also only ever a part he can actually walk to: a route that needs
	# stepping off a ledge ends with him on the ground storey looking up at the part he
	# was on his way to, and the whole level becomes that.
	if _goal == Vector2i.ZERO or not _still_there(board) \
			or _route_to(board, player.cell, _goal, true).is_empty():
		_goal = _pick_part(board, player.cell)
		_route.clear()
		_route_t = 0.0
	if _goal == Vector2i.ZERO:
		_hold(Vector2i.ZERO)
		return

	_route_t -= DECIDE_EVERY
	if _route.is_empty() or _route_t <= 0.0:
		_route = _route_to(board, player.cell, _goal, false)
		_route_at = 0
		_route_t = ROUTE_TTL
	_hold(_next_step(player.cell))


## Whether the part being worked on is still standing in the level.
func _still_there(board: Board) -> bool:
	return board.ingredient_at(_goal) != null


## The direction that walks the chef across a part standing on his own storey.
##
## A part only drops once every one of its cells has been stood in, so this tracks
## which cells have been covered and walks him to the nearest one that has not - the
## same rule the chef follows, rather than an approximation of it. "Carry on in the
## direction you were already going" is not good enough: a chef who steps onto the
## left-hand cell of a three-wide part while heading left is asked to keep heading left,
## which is the edge of the map, and the level stops with a part one cell from done.
## Once every cell is covered it walks him off the far end, because that is what tips
## the part over.
func _crossing_step(board: Board, from: Vector2i) -> Vector2i:
	for ing in _standing_parts():
		var first := ing.cells[0]
		var last := ing.cells[ing.cells.size() - 1]
		if first.y != from.y:
			continue
		if from.x < first.x - 1 or from.x > last.x + 1:
			continue
		# Moving off the edge of a part, so the part he was crossing is done with.
		if from.x < first.x or from.x > last.x:
			_crossing = null
			_covered.clear()
			return Vector2i.ZERO
		if board.ingredient_at(from) != _crossing:
			_crossing = ing
			_covered.clear()
		_covered[from] = true
		var target := Vector2i.ZERO
		for cell in ing.cells:
			if _covered.has(cell):
				continue
			if target == Vector2i.ZERO \
					or absi(cell.x - from.x) < absi(target.x - from.x):
				target = cell
		if target == Vector2i.ZERO:
			# All of it is covered. Step off the far end to drop it.
			return Vector2i.RIGHT if from.x >= last.x else Vector2i.LEFT
		return Vector2i(signi(target.x - from.x), 0)
	return Vector2i.ZERO


## The nearest part the chef can walk to without stepping off anything.
##
## Distance is the length of the walk, not how near it looks: two parts on the same
## storey are one row away from the ledge the chef is standing on, and only one of
## them is on the ladder he is standing next to.
func _pick_part(board: Board, from: Vector2i) -> Vector2i:
	var best := Vector2i.ZERO
	var best_len := 9999
	for ing in _standing_parts():
		var at := ing.cells[0]
		closest = mini(closest, absi(at.x - from.x) + absi(at.y - from.y))
		var route := _route_to(board, from, at, true)
		if route.is_empty():
			continue
		if route.size() < best_len:
			best_len = route.size()
			best = at
	return best


## Every part still standing, as the game itself knows them.
func _standing_parts() -> Array[Ingredient]:
	var out: Array[Ingredient] = []
	for node in get_tree().get_nodes_in_group(&"ingredients"):
		var ing := node as Ingredient
		if ing != null and is_instance_valid(ing) and not ing.falling and not ing.cells.is_empty():
			out.append(ing)
	return out


## The cells to walk to get from `from` to `to`, or nothing if there is no way.
##
## Breadth first, so the cost is cells walked rather than a guess. Routes that keep to
## the chef's feet are preferred: dropping off a ledge is a move he can make, but a route
## that leans on it drops him off the same ledge over and over. `safe_only` is for asking
## whether a part is worth walking to, where falling off would not get him closer.
func _route_to(board: Board, from: Vector2i, to: Vector2i, safe_only: bool = false) -> Array[Vector2i]:
	if from == to:
		return []
	var out := _search(board, from, to, false)
	if out.is_empty() and not safe_only:
		out = _search(board, from, to, true)
	return out


func _search(board: Board, from: Vector2i, to: Vector2i, allow_drops: bool) -> Array[Vector2i]:
	if from == to:
		return []
	var queue: Array[Vector2i] = [from]
	var came := {from: Vector2i.ZERO}
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		for dir in DIRS:
			var next := at + dir
			if came.has(next) or not _can_go(board, at, dir, allow_drops):
				continue
			came[next] = at
			if next == to:
				return _unwind(came, to)
			queue.append(next)
	return []


func _unwind(came: Dictionary, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var at := to
	while came[at] != Vector2i.ZERO:
		out.push_front(at)
		at = came[at]
	return out


## The direction of the next cell on the route.
##
## Returns ZERO rather than a step that goes nowhere if the chef is not standing where
## the route thinks he is. He falls, he is put back after being caught, and a nasty can
## knock him about; the difference between the route's next cell and where he actually
## is is then a vector across the map, and holding it as a direction is how a bot ends
## up asking to walk four rows north in one step. Losing the route and looking again is
## always better than that.
func _next_step(at: Vector2i) -> Vector2i:
	while _route_at < _route.size() and _route[_route_at] == at:
		_route_at += 1
	if _route_at >= _route.size():
		_route.clear()
		return Vector2i.ZERO
	var step: Vector2i = _route[_route_at] - at
	if not DIRS.has(step):
		_route.clear()
		return Vector2i.ZERO
	return step


## Cells of every nasty that can still catch the chef.
func _nasty_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e != null and is_instance_valid(e) \
				and e.state != Enemy.St.SQUASH and e.state != Enemy.St.STUN:
			out.append(e.cell)
	return out


## Manhattan distance to the nearest live nasty, or -1 if there are none.
func _nearest_nasty(from: Vector2i) -> int:
	var best := -1
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var e := node as Enemy
		if e == null or not is_instance_valid(e):
			continue
		if e.state == Enemy.St.SQUASH or e.state == Enemy.St.STUN:
			continue
		var d := absi(e.cell.x - from.x) + absi(e.cell.y - from.y)
		if best < 0 or d < best:
			best = d
	return best


## The first step towards the safest cell within reach.
##
## Scored on where the chef would *end up*, not on which way is nearest, and measured
## in walked steps rather than straight lines, so a wall between him and a nasty counts
## for something. Only the best cell is chosen and only its first step is taken: taking
## the locally best step every tick is what makes a bot walk into a nasty in a corridor
## it cannot turn around in. Stepping off a ledge is not counted as an escape, because
## it buys a frame and costs a storey.
func _best_escape(board: Board, from: Vector2i, threats: Array[Vector2i]) -> Vector2i:
	if threats.is_empty():
		return Vector2i.ZERO
	var gap := _gap_to_nasties(board, threats)
	var best_cell := from
	var best_score: int = gap.get(from, 0)
	var best_depth := 0
	var came := {from: Vector2i.ZERO}
	var depth := {from: 0}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		if depth[at] >= ESCAPE_LOOK:
			continue
		for dir in DIRS:
			var next := at + dir
			if came.has(next) or not _can_go(board, at, dir, false):
				continue
			came[next] = at
			depth[next] = depth[at] + 1
			queue.append(next)
			var score: int = gap.get(next, 0)
			# Level with the best so far but further away wins: same safety, and the
			# head start is worth having in a corridor.
			if score > best_score or (score == best_score and depth[next] > best_depth):
				best_score = score
				best_cell = next
				best_depth = depth[next]
	if best_cell == from:
		return Vector2i.ZERO
	var step := best_cell
	while came[step] != from:
		step = came[step]
	return step - from


func _gap_to_nasties(board: Board, threats: Array[Vector2i]) -> Dictionary:
	var out := {}
	var queue: Array[Vector2i] = []
	for t in threats:
		if not out.has(t):
			out[t] = 0
			queue.append(t)
	var at := 0
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		at += 1
		for dir in DIRS:
			var next := cell + dir
			if out.has(next) or not _can_go(board, cell, dir, false):
				continue
			out[next] = at
			queue.append(next)
	return out


## Whether the chef could step this way, using the same rules he does.
func _can_go(board: Board, from: Vector2i, dir: Vector2i, allow_drops: bool = true) -> bool:
	var to := from + dir
	if not Cfg.in_grid(to):
		return false
	if dir == Vector2i.UP or dir == Vector2i.DOWN:
		if not (board.is_ladder(from) or board.is_ladder(to)):
			return false
		if board.blocks_player(to):
			return false
		return board.is_ladder(to) or board.floor_below(to)
	if board.blocks_player(to):
		return false
	return allow_drops or board.floor_below(to) or board.is_ladder(to)


# --- Pressing keys ----------------------------------------------------------


func _hold(dir: Vector2i) -> void:
	wants = dir
	var want := _action_for(dir) if dir != Vector2i.ZERO else ""
	if want == "" and _held.is_empty():
		return
	if not _held.is_empty() and _held[0] == want:
		return
	_release_all()
	if want == "":
		return
	_held = [want]
	if not Input.is_action_pressed(want):
		Input.action_press(want)


func _action_for(dir: Vector2i) -> String:
	if dir == Vector2i.LEFT:
		return "move_left"
	if dir == Vector2i.RIGHT:
		return "move_right"
	if dir == Vector2i.UP:
		return "move_up"
	return "move_down"


func _release_all() -> void:
	for action in _held:
		Input.action_release(action)
	_held.clear()


func _exit_tree() -> void:
	_release_all()
