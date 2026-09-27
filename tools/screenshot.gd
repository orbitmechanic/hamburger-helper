extends Node2D
## Renders a scene and writes a PNG, so the game can be looked at without a
## human at the keyboard.
##
## Needs a real (if virtual) display: Godot's headless mode uses a dummy
## renderer, so this cannot be run with --headless. See tools/shots.sh, which
## starts Xvfb and calls this.
##
##   DISPLAY=:99 SHOT_SCENE=scenes/game.tscn SHOT_OUT=/tmp/game.png \
##     godot --rendering-driver opengl3 --resolution 256x240 tools/screenshot.tscn
##
## Env: SHOT_SCENE (default scenes/game.tscn), SHOT_OUT (required),
## SHOT_FRAMES (frame cap, default 900), SHOT_TIME_SCALE (default 1; raising it
## gets past the level card in fewer frames, which matters a lot on software
## GL), SHOT_UNTIL_PHASE (optional: capture as soon as the scene's own `phase`
## reaches this, instead of after a guessed number of frames).
##
## The scene is instantiated straight into the root viewport and captured
## through get_viewport(). An earlier version put it in a SubViewport, and that
## rendered exactly one frame and then went stale: the game underneath was
## provably running (phase advanced, the clock counted down) while every
## capture from frame 10 to frame 500 came back byte-identical. So the scene is
## parented to the root viewport and the window is sized to the project base so
## the project settings do the scaling.

const BASE_SIZE := Vector2i(256, 240)

var _shot_scene := ""


func _ready() -> void:
	_shot_scene = OS.get_environment("SHOT_SCENE")
	if _shot_scene == "":
		_shot_scene = "res://scenes/game.tscn"
	var out_path := OS.get_environment("SHOT_OUT")
	if out_path == "":
		out_path = "/tmp/hamburger-helper.png"
	var frames := int(OS.get_environment("SHOT_FRAMES")) if OS.get_environment("SHOT_FRAMES") != "" else 900
	var env_scale := OS.get_environment("SHOT_TIME_SCALE")
	Engine.time_scale = float(env_scale) if env_scale != "" else 1.0
	var env_phase := OS.get_environment("SHOT_UNTIL_PHASE")
	var until_phase := int(env_phase) if env_phase != "" else -1
	var settle := int(OS.get_environment("SHOT_SETTLE_FRAMES")) \
		if OS.get_environment("SHOT_SETTLE_FRAMES") != "" else 0

	var packed: PackedScene = load(_shot_scene)
	if packed == null:
		push_error("could not load %s" % _shot_scene)
		get_tree().quit(1)
		return

	var inst := packed.instantiate()
	add_child(inst)

	var reached := until_phase < 0
	var waited := 0
	for i in frames:
		waited = i
		await get_tree().process_frame
		if not reached and "phase" in inst and int(inst.phase) >= until_phase:
			reached = true
			# Let the moment finish happening. Starting a level is not instant,
			# and a capture taken on the phase's very first frame catches a board
			# that is still arriving.
			for j in settle:
				await get_tree().process_frame
			await get_tree().process_frame
			break

	# Report what the scene thinks its own state is. Without this a stale frame
	# is indistinguishable from a scene that never started, which is exactly the
	# mistake worth catching here.
	if "phase" in inst:
		print("state: phase=%s chefs=%d burgers=%d/%d" % [
			str(inst.phase), GameState.chefs, GameState.burgers_done,
			GameState.burgers_target])

	# Waiting on the scene's own phase beats a tuned frame count, because a wrong
	# guess fails loudly here instead of quietly writing a picture of the wrong
	# moment - which is how a level-4 shot once came back showing the title.
	if not reached:
		push_error("SHOT_UNTIL_PHASE=%d not reached within %d frames (phase is %s)"
			% [until_phase, frames, str(inst.phase) if "phase" in inst else "n/a"])
		get_tree().quit(1)
		return

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("viewport produced no image")
		get_tree().quit(1)
		return
	var err := image.save_png(out_path)
	if err != OK:
		push_error("save_png(%s) failed with %d" % [out_path, err])
		get_tree().quit(1)
		return
	print("screenshot: wrote %s (%dx%d) from %s after %d of %d frames (+%d settle)" % [
		out_path, image.get_width(), image.get_height(), _shot_scene, waited, frames, settle])
	get_tree().quit(0)
