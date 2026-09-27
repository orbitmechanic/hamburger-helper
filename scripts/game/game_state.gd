extends Node
## Autoload holding progress that survives scene changes.
## Deliberately not `class_name`-d: the autoload name is GameState already.
##
## There is no clock. The original has no countdown either - the pressure is the
## three nasties, and a chef who loses one waits for the next one rather than
## racing a number. Everything here is about how far through the order the player
## is and how many chefs are left to finish it.

signal score_changed(score: int)
signal level_changed(index: int)
signal chefs_changed(chefs: int)

const START_CHEFS := 6
const START_LEVEL := 0

var score: int = 0
var level_index: int = START_LEVEL
## Spare chefs. One is in the kitchen at all times, so the last one lost ends the
## run, which is why this is the count of spares rather than lives.
var chefs: int = START_CHEFS
## How many burgers are finished on the plates so far this level.
var burgers_done: int = 0
## How many plates the level has, and therefore how many to win.
var burgers_target: int = 0
var high_score: int = 0

const SAVE_PATH := "user://hamburger_helper.save"


func _ready() -> void:
	load_progress()


func add_score(amount: int) -> void:
	score += amount
	if score > high_score:
		high_score = score
	score_changed.emit(score)


func set_level(index: int, target: int) -> void:
	level_index = index
	burgers_target = target
	burgers_done = 0
	level_changed.emit(index)


func count_burger(points: int) -> void:
	burgers_done += 1
	add_score(points)


func add_chef() -> void:
	chefs += 1
	chefs_changed.emit(chefs)


func lose_chef() -> void:
	chefs -= 1
	chefs_changed.emit(chefs)


## Whether the run is over: no spares left to send another chef out with.
func out_of_chefs() -> bool:
	return chefs <= 0


func reset_run() -> void:
	score = 0
	level_index = START_LEVEL
	chefs = START_CHEFS
	burgers_done = 0
	score_changed.emit(score)
	level_changed.emit(level_index)
	chefs_changed.emit(chefs)


func save_progress() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save file: %s" % SAVE_PATH)
		return
	f.store_var({"high_score": high_score})
	f.close()


func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = f.get_var()
	f.close()
	if data is Dictionary:
		high_score = int((data as Dictionary).get("high_score", 0))
