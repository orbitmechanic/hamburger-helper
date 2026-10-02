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
## The captures that show a level being played, with the level each one is of.
## One table rather than three lists of the same three names, so a new level's
## capture cannot be added to the chef check and forgotten in the level check.
const PLAY_SHOTS := [
	["03-level1-play", 0],
	["04-level2-play", 1],
	["05-level3-play", 2],
]
## The captures tools/shot_scripted.gd drives the game into, each against the
## scripted baseline it was taken beside. "play" with the same level and the same
## number of frames is what that action was supposed to change, so an action that
## quietly did nothing - a keypress that did not register, a call that was gated
## shut - comes back as a picture of the level looking exactly as it always does.
## That is the failure this file was built for, in a place where nothing else looks:
## the capture exists, it is the right size, and it is wrong.
const SCRIPTED_SHOTS := [
	["07-pepper", "the spray"],
	["08-respawn", "the parachute"],
	["09-popup-gone", "the popup clearing"],
	["10-stunned", "the frozen nasties"],
	["11-ground", "the finished burgers"],
	["12-ground-l3", "level 3's own tiles"],
]
## Matches the colours the game actually draws: the HUD's little chef hats, its
## text, and the level card panel. Chosen from Cfg, not hardcoded twice.
##
## The hats are the load-bearing one. The chef sprite's own hat is ChefArt.COL_HAT
## (ffffeb) and not this white, so every ffffff pixel on screen belongs to the
## HUD's row of six spare-chef hats, and the count is 222 in all three play
## captures whether the level is one burger wider or not. That is what makes it a
## clean answer to "is the HUD being drawn at all", which is the question the
## teardown bug turned this file into.
const HUD_HATS := Cfg.PLAYER_COOK_HAT
## The HUD's two labels - "LEVEL n" and "BURGERS x/y" - are the only white text.
const HUD_TEXT := Cfg.COL_PLATE
## The chef's hat and apron, and his inked outline, read off his own sheet. The
## characters are the only things on screen drawn out of a texture rather than a
## flat rect, so they are the only thing that can go missing without a colour count
## noticing: a sheet that failed to load would leave an empty cell and the level
## would still be "drawn". Two colours rather than one, because they fail
## differently - the hat is the largest shape on him and catches a sheet that is
## missing or the wrong size, and the ink catches one that imported without its
## outline, which still draws a recognisable chef in the wrong place.
const CHEF_HAT := ChefArt.COL_HAT
const CHEF_INK := ChefArt.COL_LINE
## Smallest share of the image each thing may cover. The HUD and the card panel
## are set from what the real captures draw, with roughly half again as much
## margin as the thinnest one. The level share is deliberately not set that way:
## a real level covers about 20% of the frame with its ledges, and pinning a
## smoke test 0.08% under the measured value means any change to a level's shape
## fails here for no reason. A blank frame is 0% and a drawn one is 20%, so 12%
## still catches "the board never got built" with room to move.
##
## The two HUD floors come off measured captures, and the hats are the one that
## carries the check: 222 px of pure white, which is six 8x8 hats less their
## outlines and the aprons over them. The 92 px floor is less than half of that
## and still well clear of the 45 px the chef's own hat would leave behind if the
## HUD were torn down, which is the failure this file exists to catch.
const MIN_HUD_SHARE := 0.0015
const MIN_CARD_SHARE := 0.05
const MIN_LEVEL_SHARE := 0.12
## Deliberately thin, and worth saying why rather than quietly rounding it up.
## Two 8px labels sit behind a 2px outline, and the outline eats the interior of
## every thin stroke, so all that survives is the few pixels where a stem is wide
## enough: 9 px in play and 12 px on the card, out of 61440. A floor of 6 px is
## the most this can honestly assert. It is here to catch the HUD losing its
## labels, not to stand in for the HUD existing - the hats do that. This was
## previously 0.0015 against the white *plates*, which is where its 585 px came
## from; branding the plates took those pixels away and left the real number.
const MIN_HUD_TEXT_SHARE := 0.0001
## The chef is 16 by 24 pixels in a 256x240 frame, so about 0.6% of it, and his
## hat and apron are most of that. The floor is set from the thinnest frame he owns
## rather than from whichever one a capture happened to catch: across his whole
## sheet the thinnest is 38 pixels of hat, and these sit at about half that, so any
## frame passes and a chef who is missing, blank or a third drawn still fails. The
## three play captures all catch the same frame, which is why reading the threshold
## off one of them alone would pin it to a stride that is not the worst case.
const MIN_CHEF_SHARE := 0.0003
## The outline is a couple of rows of pixels around the whole figure, thinnest at
## 18 pixels, so the floor is low on purpose: the check is there to catch an import
## that lost the ink, which is a real way for a sheet to be wrong, and not to pin
## down how much of him is edge.
const MIN_CHEF_INK_SHARE := 0.00015

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
	# The HUD's row of spare-chef hats. Zero of these means the HUD is not being
	# drawn at all, which is exactly what the teardown bug caused.
	for shot in ["02-level1-card", "03-level1-play", "04-level2-play",
			"05-level3-play"]:
		_check_share("%s draws the HUD" % shot, shot, HUD_HATS, MIN_HUD_SHARE)

	# The HUD's two labels, which are a separate thing from the hats being there.
	for shot in ["02-level1-card", "03-level1-play", "04-level2-play",
			"05-level3-play"]:
		_check_share("%s draws HUD text" % shot, shot, HUD_TEXT, MIN_HUD_TEXT_SHARE)

	# The level card's panel: present over the card, gone once play starts. It
	# is drawn with alpha, so the pixel is the composite over the background -
	# counting the raw colour finds nothing.
	var card := _over(Cfg.COL_CARD, Cfg.COL_BG)
	_check_share("level card is drawn", "02-level1-card", card, MIN_CARD_SHARE)
	_check_share("level card is cleared for play", "03-level1-play", card, 0.0)

	# The chef is on the board in every play capture, and is drawn out of his sheet
	# rather than with flat rects. A sheet that is missing, mislaid or the wrong
	# size leaves him invisible, which no other check here would see.
	for entry in PLAY_SHOTS:
		_check_share("%s draws the chef" % entry[0], entry[0], CHEF_HAT, MIN_CHEF_SHARE)
		_check_share("%s draws him inked" % entry[0], entry[0], CHEF_INK, MIN_CHEF_INK_SHARE)

	# A frame that is only background means the level failed to build or draw.
	# Counted over the colours of the level's own brand, so a level rendered in
	# the wrong palette fails here too: the three play captures are one per level
	# and each is the only place its brand is checked.
	for entry in PLAY_SHOTS:
		_check_brand("%s draws the level" % entry[0], entry[0], int(entry[1]),
				MIN_LEVEL_SHARE)

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

	# Each driven capture against the driven baseline. 11 is against 06 rather
	# than against 12, because 12 is the same action on a different level: what
	# makes it different is the brand, which is checked as a level below.
	for entry in SCRIPTED_SHOTS:
		_check_distinct("06-play", entry[0],
			"%s shows %s" % [entry[0], entry[1]])

	# The last one is the only capture of level 3 taken through the scripted tool,
	# and it is the only place SHOT_LEVEL is checked end to end: a level index the
	# tool ignored would land on level 1 and fail here, in level 3's own colours.
	_check_brand("12-ground-l3 draws its level", "12-ground-l3", 2, MIN_LEVEL_SHARE)


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


## Every colour one brand's board is drawn in, taken from the level's own brand
## rather than from a list kept here, so a level restyled in Cfg.BRANDS is
## checked against the new colours without touching this file. Cfg.brand_colors()
## holds the key list and the deduplication, because the keys are the palette's
## contract rather than this check's.
static func _brand_colors(index: int) -> Array[Color]:
	return Cfg.brand_colors(Cfg.brand_index(LevelData.get_level(index).brand))


## Counts a colour in `shot` and requires it to cover at least `min_share` of the
## image. A share of 0 means "none of this colour may appear at all".
func _check_share(desc: String, shot: String, want: Color, min_share: float) -> void:
	_check_any(desc, shot, [want], min_share)


## As _check_share, but over a set of colours. They are counted together rather
## than each against the threshold, because the point is how much of the frame
## the set covers in total - a brand's four platform bands between them are one
## surface, and asking each of them to clear the bar on its own would be
## measuring the layout rather than the drawing.
func _check_any(desc: String, shot: String, wants: Array, min_share: float) -> void:
	var image := _load(shot)
	if image == null:
		return
	var area := image.get_width() * image.get_height()
	var n := 0
	for want in wants:
		n += _count(image, want)
	var share := float(n) / float(area)
	if share >= min_share:
		_ok(desc, "%d px, %.2f%% (need %.2f%%)" % [n, share * 100.0, min_share * 100.0])
	else:
		_fail(desc, "%d px, %.2f%%" % [n, share * 100.0],
			" (needed %.2f%%)" % (min_share * 100.0))


## The level-share check, named for what it is asserting: that this level's board
## drew, in this level's colours. The name in the failure is the brand's, so a
## level built in the wrong palette says which one was expected.
##
## Counted over the whole brand rather than one colour because a platform tile is
## body + band + edge + dark in four bands covering the cell: counting the body
## alone would measure about a third of the drawn area, and the threshold would be
## pinning a layout detail rather than a blank frame. Counting the set makes the
## check "this level's board drew its ledges, in this level's colours", which
## catches a level built in the wrong brand as well as one that never built.
func _check_brand(desc: String, shot: String, level_index: int, min_share: float) -> void:
	var level := LevelData.get_level(level_index)
	var brand_name: String = Cfg.BRANDS[Cfg.brand_index(level.brand)]["name"]
	_check_any("%s in '%s'" % [desc, brand_name], shot, _brand_colors(level_index),
		min_share)


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
