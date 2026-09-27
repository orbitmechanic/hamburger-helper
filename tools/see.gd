extends Node
## Prints a capture as ASCII art so its layout can be inspected without
## eyeballing it.
##
##   godot --headless tools/see.tscn -- /tmp/hamburger-helper/03-level1-play.png [cols]
##
## Decoding and resampling are Image.load_from_file() and get_pixel(), which is
## what the ImageMagick `convert ... -resize ... gray:-` pipeline this replaces
## was doing. Godot's Image.resize() does the downsampling; the greyscale step is
## the luma of the pixel.

const RAMP := " .:-=+*#%@"  # darkest to lightest
## Terminal characters are about twice as tall as they are wide, so a square
## image needs its rows cut roughly in half to keep the aspect looking right.
const ASPECT := 0.42


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: godot --headless tools/see.tscn -- <file.png> [cols]")
		get_tree().quit(1)
		return
	var path := args[0]
	var cols := int(args[1]) if args.size() > 1 else 100
	var image := Image.load_from_file(path)
	if image == null:
		push_error("could not load %s" % path)
		get_tree().quit(1)
		return
	var rows := maxi(1, roundi(cols * float(image.get_height()) / float(image.get_width()) * ASPECT))
	# INTERPOLATE_BILINEAR, not nearest: averaging a block of pixels into one
	# character is the point, and picking one of them throws the detail away.
	image.resize(cols, rows, Image.INTERPOLATE_BILINEAR)
	print("%s  (%d rows x %d cols)" % [path, rows, cols])
	for y in rows:
		var line := ""
		for x in cols:
			var c := image.get_pixel(x, y)
			# Rec. 601 luma, the usual weighting for perceived brightness.
			var luma := int(clampf(c.r * 0.299 + c.g * 0.587 + c.b * 0.114, 0.0, 1.0) * 256.0)
			line += RAMP[mini(RAMP.length() - 1, luma * RAMP.length() / 256)]
		print(line)
	get_tree().quit(0)
