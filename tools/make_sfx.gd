extends SceneTree
## Sound effect generator, not part of the game.
##
##   godot --headless --script res://tools/make_sfx.gd
##
## Every effect is one 16 bit mono WAV written straight to disk, the same deal the
## character sheets get in tools/make_sheets.gd: the game holds no synthesis code,
## and replacing an effect is dropping in a file with the same name. The generated
## WAVs are committed, because they are inputs to the game rather than build
## scratch, and checking out the repo has to give a game that runs.
##
## The recipes live in tools/sfx_art.gd, so the game has no idea how a sound is
## made, and the test suite can regenerate every effect and compare it against what
## is committed.

const OUT_DIR := "res://assets/sfx/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for name: String in SfxArt.SOUNDS:
		var path: String = OUT_DIR + name + ".wav"
		var bytes := SfxArt.wav(name)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			push_error("could not write %s" % path)
			quit(1)
			return
		f.store_buffer(bytes)
		f.close()
		var secs := SfxArt.wave(name).size() / float(SfxArt.RATE)
		print("%7.3fs  %6d B  %s" % [secs, bytes.size(), path])
	print("sfx: %d" % SfxArt.SOUNDS.size())
	# The committed WAVs have to match what this just synthesised, or a regenerated
	# effect is one nobody noticed.
	#
	# The import is not a formality. Godot's WAV importer defaults to QOA, which is
	# lossy and resamples out of 16 bit, so a freshly generated file imported at the
	# default no longer matches its own recipe and the suite says so. The committed
	# .import files pin compress/mode=0 to lossless PCM; if these files are new and
	# have no .import beside them yet, that is what the first import has to produce.
	print("now run: godot --headless --import")
	print("  and check compress/mode=0 in assets/sfx/*.wav.import (lossless PCM)")
	quit(0)
