extends Node2D

const DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const DECIDE_EVERY: float = 0.05
const FLEE_CELLS: int = 3
const FLEE_RELEASE: int = 2

var game: Game
var alive: bool = true
var flee_cells: int = FLEE_CELLS
var work_s: float = 0.0
var flee_s: float = 0.0
var stuck_s: float = 0.0
var closest: int = 999

var _held: Array[String] = []
var _think_t: float = 0.0
var _route: Array[Vector2i] = []
var _route_at: int = 0
var _goal: Vector2i = Vector2i.ZERO
var _route_t: float = 0.0
var _crossing: Ingredient = null
var _covered: Dictionary = {}

var wants: Vector2i = Vector2i.ZERO
var fleeing: bool = false
var _fleeing: bool = false

func _ready() -> void:
	var env := OS.get_environment("SURVIVAL_FLEE")
	if env != "":
		flee_cells = int(env)

func setup(p_game: Game) -> void:
	game = p_game

func _exit_tree() -> void:
	_release_all()

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

func rest() -> void:
	_release_all()
	_route.clear()

func _choose(board: Board, player: Player) -> void:
	var threat: int = _nearest_nasty(player.cell)
	if threat >= 0 and threat <= flee_cells:
		var esc := _best_escape(board, player.cell, _nasty_cells())
		_hold(esc)
		return
	var cross := _crossing_step(board, player.cell)
	if cross != Vector2i.ZERO:
		_hold(cross)
		return
	if _goal == Vector2i.ZERO or not _still_there(board):
		_goal = _pick_part(board, player.cell)
		_route.clear()
	if _goal != Vector2i.ZERO:
		if _route.is_empty():
			_route = _route_to(board, player.cell, _goal, false)
			_route_at = 0
		var step := _next_step(player)
		if step != Vector2i.ZERO:
			_hold(step)
			return
	_hold(Vector2i.ZERO)

func _nearest_nasty(from: Vector2i) -> int:
	var best := 999
	for n in game.get_tree().get_nodes_in_group(&"enemies"):
		if is_instance_valid(n):
			var d: Vector2i = n.cell - from
			best = mini(best, absi(d.x) + absi(d.y))
	return best if best < 999 else -1

func _nasty_cells() -> Array[Vector2i]:
	var arr: Array[Vector2i] = []
	for n in game.get_tree().get_nodes_in_group(&"enemies"):
		if is_instance_valid(n): arr.append(n.cell)
	return arr

func _still_there(board: Board) -> bool:
	return board.ingredient_at(_goal) != null

func _pick_part(board: Board, from: Vector2i) -> Vector2i:
	var best := Vector2i.ZERO
	var bestd := 1000000000
	for ing in game.get_tree().get_nodes_in_group(&"ingredients"):
		if not is_instance_valid(ing) or ing.falling: continue
		var cells_arr = ing.cells
		if cells_arr.size() == 0: continue
		var c: Vector2i = cells_arr[cells_arr.size()/2]
		var route := _route_to(board, from, c, true)
		if route.is_empty(): continue
		if best == Vector2i.ZERO or route.size() < bestd:
			best = c
			bestd = route.size()
	return best

func _route_to(board: Board, from: Vector2i, to: Vector2i, allow_drops: bool) -> Array[Vector2i]:
	var came := {}
	var queue: Array[Vector2i] = [from]
	came[from] = from
	var qi := 0
	while qi < queue.size():
		var cur := queue[qi]
		qi += 1
		for dir in DIRS:
			var n := cur + dir
			if came.has(n): continue
			if not _can_go(board, cur, dir, allow_drops): continue
			came[n] = cur
			queue.append(n)
			if n == to: break
		if came.has(to): break
	if not came.has(to): return []
	var path: Array[Vector2i] = []
	var cur := to
	while cur != from:
		path.insert(0, cur)
		cur = came[cur]
	return path

func _next_step(player: Player) -> Vector2i:
	if _route.is_empty(): return Vector2i.ZERO
	if _route_at >= _route.size(): return Vector2i.ZERO
	var tgt := _route[_route_at]
	if tgt == player.cell:
		_route_at += 1
		if _route_at >= _route.size(): return Vector2i.ZERO
		tgt = _route[_route_at]
	return tgt - player.cell

func _crossing_step(board: Board, from: Vector2i) -> Vector2i:
	for ing in _standing_parts():
		var ing_inst = ing
		if ing_inst.cells.size() == 0: continue
		var first: Vector2i = ing_inst.cells[0]
		var last: Vector2i = ing_inst.cells[ing_inst.cells.size()-1]
		if first.y != from.y: continue
		if from.x < first.x - 1 or from.x > last.x + 1: continue
		if from.x < first.x or from.x > last.x:
			_crossing = null
			_covered.clear()
			return Vector2i.ZERO
		if board.ingredient_at(from) != _crossing:
			_crossing = ing_inst
			_covered.clear()
		_covered[from] = true
		var target := Vector2i.ZERO
		for ccell in ing_inst.cells:
			if _covered.has(ccell): continue
			if target == Vector2i.ZERO or absi(ccell.x - from.x) < absi(target.x - from.x):
				target = ccell
		if target == Vector2i.ZERO:
			if from.x >= last.x: return Vector2i.RIGHT
			return Vector2i.LEFT
		return Vector2i(signi(target.x - from.x), 0)
	return Vector2i.ZERO

func _standing_parts() -> Array:
	var arr: Array = []
	if game == null: return arr
	for ing in game.get_tree().get_nodes_in_group(&"ingredients"):
		if is_instance_valid(ing) and ing.falling == false:
			arr.append(ing)
	return arr

func _best_escape(board: Board, from: Vector2i, threats: Array[Vector2i]) -> Vector2i:
	var gap := _gap_to_nasties(board, threats)
	var best_cell := from
	var best_g := -1
	for cell in gap.keys():
		var gval = gap[cell]
		var g: int = int(gval)
		if g > best_g or (g == best_g and absi(cell.x - from.x) + absi(cell.y - from.y) < absi(best_cell.x - from.x) + absi(best_cell.y - from.y)):
			best_g = g
			best_cell = cell
	if best_cell == from: return Vector2i.ZERO
	var came := {}
	var queue: Array[Vector2i] = [from]
	came[from] = from
	var qi := 0
	while qi < queue.size():
		var cur := queue[qi]
		qi += 1
		for dir in DIRS:
			var n := cur + dir
			if came.has(n): continue
			if not _can_go(board, cur, dir, false): continue
			came[n] = cur
			queue.append(n)
			if n == best_cell: break
		if came.has(best_cell): break
	if not came.has(best_cell): return Vector2i.ZERO
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
	var i := 0
	while i < queue.size():
		var cell: Vector2i = queue[i]
		i += 1
		var dval = out[cell]
		var distd: int = int(dval)
		for dir in DIRS:
			var next := cell + dir
			if out.has(next): continue
			if not _can_go(board, cell, dir, false): continue
			out[next] = distd + 1
			queue.append(next)
	return out

func _can_go(board: Board, from: Vector2i, dir: Vector2i, allow_drops: bool = true) -> bool:
	var to := from + dir
	if not Cfg.in_grid(to): return false
	if dir == Vector2i.UP or dir == Vector2i.DOWN:
		if not (board.is_ladder(from) or board.is_ladder(to)): return false
		if board.blocks_player(to): return false
		return board.is_ladder(to) or board.floor_below(to)
	if board.blocks_player(to): return false
	return allow_drops or board.floor_below(to) or board.is_ladder(to)

func _hold(dir: Vector2i) -> void:
	wants = dir
	var want := ""
	if dir != Vector2i.ZERO:
		want = _action_for(dir)
	if want == "" and _held.is_empty(): return
	if not _held.is_empty() and _held[0] == want: return
	_release_all()
	if want == "": return
	_held = [want]
	if not Input.is_action_pressed(want):
		Input.action_press(want)

func _action_for(dir: Vector2i) -> String:
	if dir == Vector2i.LEFT: return "move_left"
	if dir == Vector2i.RIGHT: return "move_right"
	if dir == Vector2i.UP: return "move_up"
	return "move_down"

func _release_all() -> void:
	for action in _held:
		Input.action_release(action)
	_held.clear()
