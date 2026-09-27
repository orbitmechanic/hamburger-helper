extends Node
## Level-map validator for authoring. Run with:
##   godot --headless res://tools/check_levels.tscn
## Prints every problem in every level and exits non-zero if there are any.
##
## This is a scene rather than a `--script` tool on purpose. `LevelData` reads
## the Cfg autoload, and Godot does not register autoloads for a script run with
## --script, so the tool used to fail to compile with "Identifier not found: Cfg"
## and then, having failed, print a clean report anyway. The same trap is why
## tests/run.sh scans output for script errors instead of trusting exit codes.

func _ready() -> void:
	var bad := 0
	for i in LevelData.count():
		var lv := LevelData.get_level(i)
		var problems := LevelData.validate(lv)
		print("--- %d %s: %d plate(s), %d ingredient(s) ---"
			% [i + 1, lv.name, lv.plates.size(), lv.ingredients.size()])
		for plate in lv.plates:
			print("    plate row %d cols %d-%d  %s"
				% [plate.y, plate.x, plate.right(),
					LevelData._recipe_label(lv.recipe(plate))])
		if problems.is_empty():
			print("    OK")
		else:
			bad += 1
			for p in problems:
				print("    FAIL %s" % p)
	print("\n%d/%d levels valid" % [LevelData.count() - bad, LevelData.count()])
	get_tree().quit(1 if bad > 0 else 0)
