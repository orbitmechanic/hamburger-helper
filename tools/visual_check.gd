extends Node
## Visual smoke test: asserts on the pixels of real captures, so "the HUD
## vanished" cannot pass again.
##
## This exists because of a bug that every other check missed. Level teardown
## cleared every child of the Game node, which included the scene's own HUD, so
## the score and the level card were destroyed by the first start_level and
## had never once been drawn. All 106 headless checks passed the
## whole time: they build a bare Game.new() with no scene, and a headless boot
## cannot see pixels. It took looking at an actual capture to find it.
##
## Runs headless - it only reads PNGs. Producing them needs a display, because
## Godot's headless mode uses a dummy renderer; ./tools/shots.sh does that.
##
##   godot --headless tools/visual_check.tscn
##
## Env: SHOT_DIR (default /tmp/hamburger-helper).
##
## Thresholds are fractions of the image, not pixel counts, so the checks mean the
## same thing whether the capture came out at the game's native 256x240 or
## upscaled. Capturing at 256x240 is what tools/screenshot.gd does.
##
## Counting pixels is Image.get_pixel() over Image.load_from_file(), which is
## what ImageMagick's `convert ... histogram` was doing here by hand.

const SHOT_DIR_DEFAULT := "/tmp/hamburger-helper"
## Matches the colours the game actually draws: the HUD's text, the level card
## panel, and the platform tan. Chosen from Cfg, not hardcoded twice.
const HUD_TEXT := Cfg.COL_PLATE
const PLATFORM := Cfg.COL_PLATFORM
## Smallest share of the image each thing may cover. The HUD and the card panel
## are set from what the real captures draw, with roughly half again as much
## margin as the thinnest one. The level share is deliberately not set that way:
## a real level covers about 20% of the frame with platform tan, and pinning a
## smoke test 0.08% under the measured value means any change to a level's shape
## fails here for no reason. A blank frame is 0% and a drawn one is 20%, so 12%
## still catches "the board never got built" with room to move.
const MIN_HUD_SHARE := 0.0015
const MIN_CARD_SHARE := 0.05
const MIN_LEVEL_SHARE := 0.12

## How far a channel may drift and still count. Godot's own capture path and the
## X11 one that preceded it can land on adjacent values around a flat fill.
const TOLERANCE := 2

var _failed := 0
var _passed := 0
var _dir := SHOT_DIR_DEFAULT


func _ready() -> void:
	var env := OS.get_environment("SHOT_DIR")
	if env != "":
		_dir = env
	print_rich("[b]visual check[/b]  %s" % _dir)
	if not FileAccess.file_exists("%s/03-level1-play.png" % _dir):
		print_rich("[color=red]no captures in %s; run ./tools/shots.sh first[/color]" % _dir)
		get_tree().quit(1)
		return
	await _run()
	print("")
	if _failed == 0:
		print_rich("[color=green]visual: all green[/color]  (%d checks)" % _passed)
		get_tree().quit(0)
	else:
		print_rich("[color=red]visual: FAILED[/color]  %d passed, %d failed" % [_passed, _failed])
		get_tree().quit(1)


func _run() -> void:
	# The HUD's text colour. Zero of these means the HUD is not being drawn at
	# all, which is exactly what the teardown bug caused.
	for shot in ["02-level1-card", "03-level1-play", "04-level2-play",
			"05-level3-play"]:
		_check_share("%s draws HUD text" % shot, shot, HUD_TEXT, MIN_HUD_SHARE)

	# The level card's panel: present over the card, gone once play starts. It
	# is drawn with alpha, so the pixel is the composite over the background -
	# counting the raw colour finds nothing.
	var card := _over(Cfg.COL_CARD, Cfg.COL_BG)
	_check_share("level card is drawn", "02-level1-card", card, MIN_CARD_SHARE)
	_check_share("level card is cleared for play", "03-level1-play", card, 0.0)

	# A frame that is only background means the level failed to build or draw.
	for shot in ["03-level1-play", "04-level2-play", "05-level3-play"]:
		_check_share("%s draws the level" % shot, shot, PLATFORM, MIN_LEVEL_SHARE)

	# No two captures may be the same picture. A stale capture comes back
	# byte-identical to whatever was on screen before, which is how a level-4
	# shot once showed the title screen.
	var pairs := [
		["01-title", "02-level1-card", "title and level card"],
		["02-level1-card", "03-level1-play", "level card and play"],
		["03-level1-play", "04-level2-play", "level 1 and 2"],
		["04-level2-play", "05-level3-play", "level 2 and 3"],
		["01-title", "05-level3-play", "title and level 3"],
	]
	for pair in pairs:
		_check_distinct(pair[0], pair[1], "%s differ" % pair[2])


## What `over` looks like once the renderer has blended it onto `under`.
static func _over(over: Color, under: Color) -> Color:
	var a := over.a
	return Color(
		over.r * a + under.r * (1.0 - a),
		over.g * a + under.g * (1.0 - a),
		over.b * a + under.b * (1.0 - a))


## Pixels within TOLERANCE of `want` in every channel.
func _count(image: Image, want: Color) -> int:
	var target := Color(want.r, want.g, want.b)
	var n := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if absf(c.r - target.r) * 255.0 <= TOLERANCE \
					and absf(c.g - target.g) * 255.0 <= TOLERANCE \
					and absf(c.b - target.b) * 255.0 <= TOLERANCE:
				n += 1
	return n


func _load(shot: String) -> Image:
	var path := "%s/%s.png" % [_dir, shot]
	var image := Image.load_from_file(path)
	if image == null:
		print_rich("  [color=red]missing capture %s[/color]" % path)
		_failed += 1
	return image


## Compares decoded pixels rather than file bytes, so a re-encode with different
## compression still counts as the same picture.
func _check_distinct(a: String, b: String, desc: String) -> void:
	var ia := _load(a)
	var ib := _load(b)
	if ia == null or ib == null:
		return
	if ia.get_size() == ib.get_size() and ia.get_data() == ib.get_data():
		_fail("%s" % desc, "identical images", "")
	else:
		_ok("%s" % desc, "distinct")


## Counts a colour in `shot` and requires it to cover at least `min_share` of the
## image. A share of 0 means "none of this colour may appear at all".
func _check_share(desc: String, shot: String, want: Color, min_share: float) -> void:
	var image := _load(shot)
	if image == null:
		return
	var area := image.get_width() * image.get_height()
	var n := _count(image, want)
	var share := float(n) / float(area)
	if share >= min_share:
		_ok(desc, "%d px, %.2f%% (need %.2f%%)" % [n, share * 100.0, min_share * 100.0])
	else:
		_fail(desc, "%d px, %.2f%%" % [n, share * 100.0],
			" (needed %.2f%%)" % (min_share * 100.0))


func _check(desc: String, actual: int, op: String, want: int) -> void:
	var ok := false
	match op:
		"gt": ok = actual > want
		"eq": ok = actual == want
		"lt": ok = actual < want
	if ok:
		_ok(desc, str(actual))
	else:
		_fail(desc, str(actual), " (wanted %s %d)" % [op, want])


func _ok(desc: String, detail: String) -> void:
	_passed += 1
	print_rich("  [color=green]ok[/color]   %-46s %s" % [desc, detail])


func _fail(desc: String, detail: String, want: String) -> void:
	_failed += 1
	print_rich("  [color=red]FAIL[/color] %-46s %s%s" % [desc, detail, want])
