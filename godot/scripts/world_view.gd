extends Node2D
## Draws the game world (Render.draw) inside the low-resolution world SubViewport owned by main.gd.
## The UI (CanvasLayer 10) stays in the main viewport at native resolution on top of the upscaled world texture.

func _draw() -> void:
	Render.draw(self)
