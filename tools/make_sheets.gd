extends SceneTree
## Character sheet generator, not part of the game.
##
##   godot --headless --script res://tools/make_sheets.gd
##
## Every character gets one PNG on one fixed grid, and the game blits frames out
## of it instead of drawing itself. That buys the thing that actually matters for
## this project: swapping a character for real art later is dropping in a PNG
## with the same name, laid out the way Sheet describes, and touching no code. So
## the layout is a contract rather than a habit, and it is written down in one
## place (Sheet) that both this tool and the game read.
##
## The art itself lives in tools/char_art.gd, because the point of the sheets is
## that the game has no art code at all. This tool paints those operations into an
## Image directly - fill_rect per rect, no viewport, no framebuffer, no display -
## so it runs headless and its output is reproducible.
##
## The generated PNGs are committed. They are inputs to the game, not build
## scratch, and checking out the repo has to give a game that runs.

const OUT_DIR := "res://assets/sheets/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for character: String in Sheet.CHARACTERS:
		var path: String = OUT_DIR + character + ".png"
		CharArt.sheet(character).save_png(path)
		print("%dx%d  %s" % [Sheet.size().x, Sheet.size().y, path])
	print("sheets: %d" % Sheet.CHARACTERS.size())
	# The committed sheets have to match what this just painted, or a regenerated
	# sheet is one that nobody noticed. Re-import and let the suite compare.
	print("now run: godot --headless --import")
	quit(0)
