extends Node
## Autoload holding progress that survives scene changes.
## Deliberately not `class_name`-d: the autoload name is GameState already.

signal score_changed(score: int)
signal level_changed(index: int)
signal lives_changed(lives: int)

const START_LIVES := 3
const START_LEVEL := 0

var score: int = 0
var level_index: int = START_LEVEL
var lives: int = START_LIVES
var burgers_served: int = 0
var burgers_target: int = 0
var time_left: float = 0.0
var high_score: int = 0

const SAVE_PATH := "user://hamburger_helper.save"


func _ready() -> void:
	load_progress()


func add_score(amount: int) -> void:
	score += amount
	if score > high_score:
		high_score = score
	score_changed.emit(score)


func set_level(index: int, target: int, seconds: float) -> void:
	level_index = index
	burgers_target = target
	burgers_served = 0
	time_left = seconds
	level_changed.emit(index)


func set_time(seconds: float) -> void:
	time_left = seconds


func tick(delta: float) -> void:
	if time_left > 0.0:
		time_left = maxf(0.0, time_left - delta)


func add_life() -> void:
	lives += 1
	lives_changed.emit(lives)


func lose_life() -> void:
	lives -= 1
	lives_changed.emit(lives)


func reset_run() -> void:
	score = 0
	level_index = START_LEVEL
	lives = START_LIVES
	burgers_served = 0
	score_changed.emit(score)
	level_changed.emit(level_index)
	lives_changed.emit(lives)


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
