class_name Game
extends Node2D
## Owns one level: builds the board, drops the ingredients in, spawns the
## nasties and the bonuses, and runs the win/lose flow.
##
## There is no countdown to run down. The only two ways a level ends are all the
## plates filled and every chef used up.

enum Phase { INTRO, PLAYING, LEVEL_CLEAR, GAME_OVER, ALL_CLEAR }

## How long a result banner stays up before moving on.
const PHASE_TIME := 2.6
## How long the chef's victory runs before he settles on the last frame. Shorter
## than the banner on purpose, so he holds the pose rather than restarting it.
const VICTORY_TIME := 1.2
## How long the chef spends coming down under his parachute at the start of a
## level. The level card holds for exactly this long, so the card and the descent
## are one beat: the card is up while he is in the air and comes down when he lands,
## rather than the two finishing at different times and leaving a banner over a
## board the chef is already playing on.
const DROP_TIME := 3.0
## How long the chef stays down after being caught, before he is put back. Long
## enough to read the surprised pose, short enough not to feel like a stall.
const DEATH_TIME := 0.7
## How long a popup stays on the board. Long enough to read and to find, short
## enough that the next one is not drawn on top of it and the board does not
## accumulate a wall of old scores.
const POPUP_TIME := 2.0
## A pepper dose the level starts with, as in the original.
const STARTING_PEPPER := 1
## Seconds between random bonuses appearing, and how many can be out at once.
const BONUS_EVERY := 11.0
const BONUS_MAX := 2

var board: Board
var player: Player
var hud: Control
## Container for the board, chef, ingredients and enemies. Level teardown
## clears this and nothing else.
var actors: Node2D
var phase: Phase = Phase.PLAYING
var level: LevelData.Level
var paused := false

var _phase_t := 0.0
var _popups: Array = []
var _bonus_t := 0.0
## Counts the chef down from `DEATH_TIME` while he is on the floor. Overlapping the
## phase timer rather than becoming a phase of its own: the board is still in play
## behind him, it is only waiting for the chef.
var _dying := 0.0
## Set while the chef is coming back down under his parachute after a death. He is
## out of play for it, and the level is still PLAYING, so this is a flag on the
## game rather than a phase of its own.
var _respawning := false
## How far through the respawn drop the chef is. Separate from DROP_TIME so a
## slow frame cannot land him early.
var _respawn_t := 0.0


func _ready() -> void:
	actors = get_node_or_null("Actors")
	hud = get_node_or_null("HudLayer/Hud")
	if hud != null:
		hud.game = self
	start_level(_requested_level())


## Development hook: `godot scenes/game.tscn -- --level=2` jumps straight to a
## level. There is no level select yet, so this is the only way to look at
## anything past the first one, which is what tools/shots.sh needs.
## Ignored unless the argument is given.
func _requested_level() -> int:
	for arg in OS.get_cmdline_user_args():
		var text := arg.trim_prefix("--level=")
		if text == arg or not text.is_valid_int():
			continue
		var wanted := text.to_int()
		if wanted >= 0 and wanted < LevelData.count():
			return wanted
	return GameState.level_index


func start_level(index: int) -> void:
	_clear_actors()
	level = LevelData.get_level(index)
	GameState.set_level(index, level.plates.size())

	board = Board.new()
	_actor_parent().add_child(board)
	board.setup(level)

	player = Player.new()
	_actor_parent().add_child(player)
	player.setup(board, board.chef_spawn)
	player.add_pepper(STARTING_PEPPER)
	player.crossed.connect(_on_crossed)

	# The ingredients are already placed in the map, so they are built here rather
	# than pushed in by the chef. Each one is a run of cells; the width is part of
	# the puzzle, since the chef has to cross all of it to move it.
	for span in level.ingredients:
		var ing := Ingredient.new()
		_actor_parent().add_child(ing)
		ing.setup(board, span)
		ing.add_to_group(&"ingredients")
		ing.dropped.connect(_on_ingredient_dropped)
		ing.carried_rider.connect(_on_rider)
		ing.boarded.connect(_on_ingredient_boarded)

	_spawn_enemies()

	_popups.clear()
	_bonus_t = BONUS_EVERY
	paused = false
	_dying = 0.0
	_respawning = false
	_respawn_t = 0.0
	_set_player_active(false)
	phase = Phase.INTRO
	# He comes in over the top of the screen under his parachute and lands on the
	# spawn as the card comes down, and the card is held for exactly as long as the
	# descent: see DROP_TIME.
	_phase_t = DROP_TIME
	# The centre of the bottom floor, which is where a respawn comes in - not the
	# level's authored start. Those are different cells, and the authored one is
	# wherever the map could spare a `@`, so the run used to open with the chef
	# parachuting into a corner and having to walk back out of it. He now lands where
	# he would land after being caught, which is the one cell in the level chosen for
	# being somewhere to stand rather than for being out of the way.
	player.begin_drop(board.respawn_spawn, DROP_TIME)
	if hud != null:
		hud.queue_redraw()


## Where actors go. A dedicated container rather than the Game node itself,
## because clearing "all children" also removed the scene's own HUD: the level
## card, the score and the clock were destroyed by the first start_level and
## have never been visible since. Falls back to self, since the tests build a
## bare Game.new() with no scene and no container.
func _actor_parent() -> Node:
	return actors if actors != null else self


func _clear_actors() -> void:
	# Null the references first: a node freed at the end of the frame can still
	# run one more _process, and the old actors must not touch the new level.
	board = null
	player = null
	_popups.clear()
	# Detach before queue_free, otherwise the outgoing level keeps processing
	# and drawing for another frame and appears as a ghost behind the new one.
	var parent := _actor_parent()
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _spawn_enemies() -> void:
	for cell in board.enemy_spawns:
		var kind: Enemy.Kind = board.enemy_kinds.get(cell, Enemy.Kind.HOTDOG)
		var enemy := Enemy.new()
		_actor_parent().add_child(enemy)
		enemy.setup(board, cell, kind, player)
		enemy.add_to_group(&"enemies")
		enemy.squashed.connect(_on_enemy_squashed)


# --- Crossing --------------------------------------------------------------


## The chef has walked the full width of a part, so it drops. A nasty standing on
## it at that moment goes down with it, and the part falls two levels rather than
## one - which is the whole reason to bait a nasty under a bun.
func _on_crossed(ing: Ingredient) -> void:
	var riders := 0
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Enemy
		if enemy != null and is_instance_valid(enemy) and enemy.riding(ing):
			riders += 1
			enemy.attach(ing)
	if riders > 0:
		Sfx.play("ride")
	ing.knock(1 if riders > 0 else 0)


func _on_rider() -> void:
	GameState.add_score(Food.POINTS_RIDER)
	_popup("RIDE!", Cfg.COL_BONUS)


func _on_ingredient_dropped(floors: int, at: Vector2i) -> void:
	GameState.add_score(floors * Food.POINTS_PER_FLOOR)
	Sfx.play("drop")


## A part has reached a plate. If that finishes the burger it is worth scoring
## and, if it was the last plate, the level.
func _on_ingredient_boarded(plate: LevelData.Span) -> void:
	GameState.add_score(Food.POINTS_PER_FLOOR)
	if not Food.stack_is_burger(board.stack(plate.x)):
		Sfx.play("stack")
		return
	# A finished burger is the moment worth hearing, so the part landing on the
	# plate answers itself rather than piling a second sound on top of the jingle.
	Sfx.play("burger")
	GameState.count_burger(Food.burger_points(board.stack(plate.x).size()))
	_popup("+%d" % Food.burger_points(board.stack(plate.x).size()), Cfg.COL_BONUS)
	_popup_tween(Cfg.cell_to_pixel(Vector2i(plate.x, plate.y)))
	if GameState.burgers_done >= GameState.burgers_target:
		_enter(Phase.LEVEL_CLEAR)


func _on_enemy_squashed(points: int) -> void:
	GameState.add_score(points)
	Sfx.play("squash")


# --- Bonuses ---------------------------------------------------------------


func _process_bonuses(delta: float) -> void:
	for b in get_tree().get_nodes_in_group(&"bonuses"):
		var bonus := b as Bonus
		if bonus == null or not is_instance_valid(bonus):
			continue
		if bonus.cell == player.cell:
			_collect(bonus)
	_bonus_t -= delta
	if _bonus_t > 0.0:
		return
	_bonus_t = BONUS_EVERY
	if get_tree().get_nodes_in_group(&"bonuses").size() >= BONUS_MAX:
		return
	var at := _random_walk_row_cell()
	if at == Vector2i(-1, -1):
		return
	var bonus := Bonus.new()
	_actor_parent().add_child(bonus)
	bonus.setup(at, _random_bonus_kind())
	bonus.add_to_group(&"bonuses")


func _collect(bonus: Bonus) -> void:
	Sfx.play("bonus")
	match bonus.kind:
		Bonus.Kind.PEPPER, Bonus.Kind.SALT:
			player.add_pepper(bonus.charges())
			GameState.add_score(Food.POINTS_PEPPER)
			_popup(bonus.label(), Cfg.COL_PEPPER)
		Bonus.Kind.LIFE:
			GameState.add_chef()
			_popup("1UP", Cfg.COL_BONUS)
	_popup_tween(Cfg.cell_to_pixel(bonus.cell))
	bonus.queue_free()


## Pepper is the one that has to appear where the chef can actually reach it, so
## the cell is drawn from the walk rows rather than the whole grid.
##
## The candidates are collected and sampled with pick_random() instead of rolling
## and rejecting: rejection sampling needed a retry cap that silently degraded to
## "no bonus appears" on a crowded board, and picked a uniform cell from a list
## is both exact and shorter.
func _random_walk_row_cell() -> Vector2i:
	var candidates: Array[Vector2i] = []
	for x in range(1, Cfg.GRID_W - 1):
		for y in Cfg.GRID_H:
			var at := Vector2i(x, y)
			if board.blocks_player(at) or not board.floor_below(at):
				continue
			candidates.append(at)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates.pick_random()


func _random_bonus_kind() -> Bonus.Kind:
	var roll := randf()
	if roll < 0.45:
		return Bonus.Kind.PEPPER
	if roll < 0.9:
		return Bonus.Kind.SALT
	return Bonus.Kind.LIFE


## How long a nasty stays frozen by a dose. Long enough to walk away from it
## and do something else, short enough that it is not gone for the rest of the
## level.
const SPRAY_STUN_TIME := 5.0


## Seasoning is a forward spray the chef throws himself.
##
## Two earlier shapes were wrong for a player. Making the jar freeze every nasty
## the moment it was picked up took the timing out of the player's hands - the
## board paused itself, and the jar decided the moment rather than the player. And
## spending a charge to shimmer until something walked into the chef wasted the
## dose on whichever nasty happened to be nearest, which is rarely the one the
## player was aiming at. So a dose is now aimed: the key throws it the way the
## chef is facing, and whatever the spray reaches is frozen for a count-down.
## One charge is one shot, and with an empty jar the key says so.
func _fire_pepper() -> void:
	if player == null or not is_instance_valid(player):
		return
	if not Input.is_action_just_pressed(&"pepper"):
		return
	if not player.spend_pepper():
		_popup("NO PEPPER", Cfg.COL_PLATE)
		Sfx.play("deny")
		return
	var spray := player.spray_rect()
	var hit := 0
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Enemy
		if enemy != null and is_instance_valid(enemy) and spray.intersects(enemy.hit_rect()):
			enemy.stun(SPRAY_STUN_TIME)
			hit += 1
	# The hiss is the throw and the zap is what it bought, so a dose that connects
	# makes both - and a dose that does not is quiet apart from the spray, which is
	# the sound of having missed.
	Sfx.play("spray")
	if hit > 0:
		Sfx.play("zap")
	_popup("SPRAY!" if hit == 0 else "ZAP x%d" % hit, Cfg.COL_PEPPER)


# --- Loss ------------------------------------------------------------------


## Runs the contact check. The seasoning spray freezes a nasty for five seconds
## rather than removing it, so a frozen nasty must not be able to catch the chef
## either.
func _check_catches() -> void:
	if phase != Phase.PLAYING or player == null or not is_instance_valid(player):
		return
	if player.state == Player.St.JUMP:
		return
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.state == Enemy.St.SQUASH or enemy.state == Enemy.St.STUN:
			continue
		if _touching(enemy):
			_on_player_died()
			return


## Whether the chef and a nasty are actually touching.
##
## Body boxes in world pixels, so this answers the question the player is asking -
## are these two things touching on the screen - and not the easier one the cell
## check answered, which was whether they were in the same cell or next to it. That
## is what let the chef die a cell and a half from the nasty that got him, with
## nothing on screen overlapping: an eight-pixel gap the player could see and the
## game ignored.
func _touching(enemy: Enemy) -> bool:
	return player.hit_rect().intersects(enemy.hit_rect())


func _on_player_died() -> void:
	GameState.lose_chef()
	Sfx.play("death")
	# Every nasty goes back to its own ledge, as in the original. Without this a
	# nasty sitting next to the chef's spawn eats the run chef after chef, because
	# each respawn puts the chef straight back into its arms.
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Enemy
		if enemy != null and is_instance_valid(enemy):
			enemy.reset_for_respawn()
	# The chef is surprised, and stays that way long enough to be seen, rather than
	# blinking out of one pose and into his spawn in the same frame. He is also out
	# of play for it, so he cannot walk off into a nasty that has just been sent
	# back to its ledge, nor be caught again before he is back.
	player.set_pose(Sheet.Anim.DEATH)
	if GameState.out_of_chefs():
		_enter(Phase.GAME_OVER)
		return
	_popup("OUCH!", Cfg.COL_PLATE)
	# Where he was caught, not where he is about to be put back. The two are the
	# same cell on the first death and a long way apart on every one after it, so
	# reading the spawn here pins the complaint to the respawn and tells the player
	# nothing about what actually got him.
	_popup_tween(Cfg.cell_to_pixel(player.cell))
	_dying = DEATH_TIME
	_set_player_active(false)


## Put the chef back in the middle of the bottom floor, under his parachute.
##
## He comes down rather than appearing, because appearing on a board he was just
## caught on is what made a death feel like a glitch: the same chef was in two
## places in the space of a frame. The drop is the one the level opens with, so a
## respawn reads as the level putting him back rather than as a new thing, and the
## canopy comes off on the landing the same way it does at the start.
func _revive() -> void:
	_dying = 0.0
	if player == null or not is_instance_valid(player):
		return
	# `begin_drop` hands the chef back to himself, so the surprised pose goes with
	# it, and it leaves him not processing until the drop finishes.
	player.begin_drop(board.respawn_spawn, DROP_TIME)
	Sfx.play("respawn")
	_respawn_t = 0.0
	_respawning = true


# --- Flow -------------------------------------------------------------------


func _process(delta: float) -> void:
	# Before the early returns below, so a popup still ages out while the chef is
	# down, paused off, or the level is clearing. A popup that froze during the
	# death beat would sit on the board for the rest of the level.
	_age_popups(delta)
	if Input.is_action_just_pressed(&"pause") and phase == Phase.PLAYING:
		paused = not paused
		if hud != null:
			hud.queue_redraw()
	if paused:
		return

	# The chef is down. The board waits on him: no input, no catches, and the
	# banner is not running, because none of that is the point of this beat.
	if _dying > 0.0:
		_dying -= delta
		if _dying <= 0.0:
			_revive()
		if hud != null:
			hud.queue_redraw()
		return

	# And coming back down. Like INTRO, the drop runs off the level's clock rather
	# than the chef's, because he is not processing, and like INTRO the board is
	# simply not in play until he lands.
	if _respawning:
		_respawn_t += delta
		player.drop_step(delta)
		if _respawn_t >= DROP_TIME:
			_respawning = false
			_respawn_t = 0.0
			# finish_drop is what hands him back to himself and takes the canopy off;
			# doing it here rather than in _revive is what makes the landing and the
			# chef becoming playable the same frame.
			player.finish_drop()
			_set_player_active(true)
		if hud != null:
			hud.queue_redraw()
		return

	match phase:
		Phase.PLAYING:
			_process_bonuses(delta)
			_fire_pepper()
			_check_catches()
		_:
			# Everything that is not PLAYING just runs its phase timer down, which
			# includes the level card, so INTRO deliberately falls through here.
			_phase_t -= delta
			_pose_the_chef(delta)
			if _phase_t <= 0.0:
				_advance()

	if hud != null:
		hud.queue_redraw()


## The chef while the level is in charge of him: coming down under his parachute
## for the card, and celebrating a cleared level.
##
## Both are on the phase's own clock rather than the chef's, because he is not
## processing during either, so a clock of his own would not be running.
func _pose_the_chef(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	match phase:
		Phase.INTRO:
			player.drop_step(delta)
		Phase.LEVEL_CLEAR, Phase.ALL_CLEAR:
			# The banner is longer than the flourish, so he settles on the last
			# frame and holds it for the rest rather than restarting.
			player.set_pose(Sheet.Anim.VICTORY,
					clampf((PHASE_TIME - _phase_t) / VICTORY_TIME, 0.0, 1.0))


## The chef only moves and is only hit while the level is actually running.
func _set_player_active(active: bool) -> void:
	if player != null and is_instance_valid(player):
		player.set_process(active)


func _enter(next: Phase) -> void:
	phase = next
	_phase_t = PHASE_TIME
	# The chef is only ever down during play. Anything that takes the board out of
	# play takes him off the floor with it, or the death beat would swallow the
	# banner it happens during.
	_dying = 0.0
	# And any respawn descent in flight. A level that ends while the chef is still
	# coming back down would otherwise leave the flag set, and the next level would
	# open with him dropping out of the sky for no reason. Landing him here is the
	# same contract as the PLAYING branch below: whatever the canopy was doing, it
	# is not doing it any more.
	_respawning = false
	_respawn_t = 0.0
	# Landing him here is the same contract as the PLAYING branch below: whatever
	# the canopy was doing, it is not doing it any more. finish_drop is what takes
	# it off, and calling it only when dropping is true is why a level that ended
	# mid-descent would otherwise leave a canopy hanging over a board the chef has
	# already been taken off.
	if player != null and is_instance_valid(player):
		player.finish_drop()
	match next:
		Phase.PLAYING:
			# The canopy is only for the descent, and the descent is only for the
			# card. Landing here rather than trusting the two clocks to finish
			# together: if they are a frame apart the chef is playing under a
			# parachute, or a parachute is left hanging over a board he has landed on.
			if player != null and is_instance_valid(player):
				player.finish_drop()
				player.clear_pose()
			_set_player_active(true)
		Phase.LEVEL_CLEAR:
			_set_player_active(false)
			# Set here as well as from `_celebrate` so the very first frame of the
			# banner is already the start of the flourish and not the last frame of
			# whatever he was doing when the last plate went down.
			if player != null and is_instance_valid(player):
				player.set_pose(Sheet.Anim.VICTORY, 0.0)
			_popup("LEVEL CLEAR!", Cfg.COL_BONUS)
			Sfx.play("level_clear")
			GameState.save_progress()
		Phase.GAME_OVER:
			_set_player_active(false)
			_popup("GAME OVER", Cfg.COL_PLATE)
			Sfx.play("game_over")
			GameState.save_progress()
		Phase.ALL_CLEAR:
			_set_player_active(false)
			_popup("YOU WIN!", Cfg.COL_PEPPER)
			Sfx.play("win")
			GameState.save_progress()


func _advance() -> void:
	match phase:
		Phase.INTRO:
			_enter(Phase.PLAYING)
		Phase.LEVEL_CLEAR:
			var next_index := GameState.level_index + 1
			if next_index < LevelData.count():
				start_level(next_index)
			else:
				_enter(Phase.ALL_CLEAR)
		Phase.GAME_OVER, Phase.ALL_CLEAR:
			get_tree().change_scene_to_file("res://scenes/main.tscn")


func _popup(text: String, color: Color) -> void:
	_popups.append({"text": text, "t": 0.0, "pos": Vector2.ZERO, "color": color})


func _popup_tween(at: Vector2) -> void:
	if _popups.is_empty():
		return
	_popups.back()["pos"] = at


## Ages the popups and drops the ones that have been up long enough.
##
## Without this they never went away at all, so the `OUCH!` from the first death
## was still on the board at the end of the level, sitting on top of whatever the
## chef was doing. Each popup keeps its own clock rather than the whole batch
## ageing together, so a score that comes up mid-death still gets its full two
## seconds instead of inheriting the age of the thing that was already there.
func _age_popups(delta: float) -> void:
	var live: Array = []
	for p in _popups:
		p["t"] = float(p["t"]) + delta
		if float(p["t"]) < POPUP_TIME:
			live.append(p)
	_popups = live


## For the Hud to draw. Popups live here because only the Game knows where things
## happened.
func popups() -> Array:
	return _popups
