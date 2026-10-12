extends Node
## Standalone attract-mode entry: `godot scenes/demo.tscn`.
##
## Attaches the demo cycle straight to the root, deferred, because the root is
## busy setting up this scene's children while our _ready runs and a nested
## add_child onto it fails. The cycle then survives the scene change that
## frees this holder, because it was never a child of it.

func _ready() -> void:
	var demo := Node.new()
	demo.name = "Demo"
	demo.set_script(preload("res://scripts/game/demo.gd"))
	get_tree().root.add_child.call_deferred(demo)
