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
## SHOT_FRAMES (default 90), SHOT_TIME_SCALE (default 1; raising it gets past
## the level card in fewer frames, which matters a lot on software GL).
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
	var frames := int(OS.get_environment("SHOT_FRAMES")) if OS.get_environment("SHOT_FRAMES") != "" else 90
	var env_scale := OS.get_environment("SHOT_TIME_SCALE")
	Engine.time_scale = float(env_scale) if env_scale != "" else 1.0

	var packed: PackedScene = load(_shot_scene)
	if packed == null:
		push_error("could not load %s" % _shot_scene)
		get_tree().quit(1)
		return

	var inst := packed.instantiate()
	add_child(inst)

	for i in frames:
		await get_tree().process_frame

	# Report what the scene thinks its own state is. Without this a stale frame
	# is indistinguishable from a scene that never started, which is exactly the
	# mistake worth catching here.
	if "phase" in inst:
		print("state: phase=%s time_left=%.2f" % [
			str(inst.phase), float(GameState.time_left)])

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
	print("screenshot: wrote %s (%dx%d) from %s after %d frames" % [
		out_path, image.get_width(), image.get_height(), _shot_scene, frames])
	get_tree().quit(0)
