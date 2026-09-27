extends Node2D
## Renders a scene offscreen and writes a PNG, so the game can be looked at
## without a human at the keyboard.
##
## Needs a real (if virtual) display: Godot's headless mode uses a dummy
## renderer that produces no pixels, so this cannot be run with --headless.
##
##   Xvfb :99 -screen 0 1152x960x24 &
##   DISPLAY=:99 SHOT_SCENE=scenes/game.tscn SHOT_OUT=/tmp/game.png \
##     godot --rendering-driver opengl3 tools/screenshot.tscn
##
## Env: SHOT_SCENE (default scenes/game.tscn), SHOT_OUT (required),
## SHOT_FRAMES (default 90), SHOT_WIDTH / SHOT_HEIGHT (default 3x the 256x240
## base viewport, which is small enough that layout bugs hide in it).

const BASE_SIZE := Vector2i(256, 240)


func _ready() -> void:
	var scene_path := OS.get_environment("SHOT_SCENE")
	if scene_path == "":
		scene_path = "res://scenes/game.tscn"
	var out_path := OS.get_environment("SHOT_OUT")
	if out_path == "":
		out_path = "/tmp/hamburger-helper.png"
	var frames := int(OS.get_environment("SHOT_FRAMES")) if OS.get_environment("SHOT_FRAMES") != "" else 90
	var width := int(OS.get_environment("SHOT_WIDTH")) if OS.get_environment("SHOT_WIDTH") != "" else BASE_SIZE.x * 3
	var height := int(OS.get_environment("SHOT_HEIGHT")) if OS.get_environment("SHOT_HEIGHT") != "" else BASE_SIZE.y * 3

	# The capture is done through a SubViewport so the window size cannot change
	# how the game lays itself out; scaling stays owned by the project settings.
	var sub := SubViewport.new()
	sub.size = Vector2i(width, height)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	add_child(sub)

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("could not load %s" % scene_path)
		get_tree().quit(1)
		return
	var inst := packed.instantiate()
	sub.add_child(inst)

	# Let the scene build itself, run some frames of real gameplay, then draw.
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := sub.get_texture().get_image()
	if image == null:
		push_error("viewport produced no image")
		get_tree().quit(1)
		return
	var err := image.save_png(out_path)
	if err != OK:
		push_error("save_png(%s) failed with %d" % [out_path, err])
		get_tree().quit(1)
		return
	print("screenshot: wrote %s (%dx%d) from %s" % [out_path, width, height, scene_path])
	get_tree().quit(0)
