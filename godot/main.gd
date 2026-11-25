extends Node2D
## Integration root: forwards input, drives the fixed-step sim, draws the world.
## All game logic lives in the autoload modules (see CONTRACT.md).

@onready var cam: Camera2D = $Camera

func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Noto Sans CJK JP", "Noto Sans JP", "Hiragino Sans", "Yu Gothic UI", "Meiryo", "WenQuanYi Zen Hei", "sans-serif"])
	Render.font = sf
	UI.load_drone_config()
	World.generateWorld()
	if OS.get_environment("NF_SHOT") != "":
		_demo()

func _input(e: InputEvent) -> void:
	if Inp.handle_event(e):
		get_viewport().set_input_as_handled()
	elif Game.state == "menu" and ((e is InputEventKey and e.pressed and e.keycode == KEY_SPACE) or (e is InputEventMouseButton and e.pressed)):
		Game.resetGame()   # temporary start trigger until the menu UI (milestone 3)

func _process(dt: float) -> void:
	var vs := get_viewport_rect().size
	World.resize(vs.x, vs.y)
	Inp.set_view(vs, World.camera_center())
	Game.step_frame(dt)
	cam.position = World.camera_center()
	queue_redraw()

func _draw() -> void:
	Render.draw(self)

# Dev-only: NF_SHOT=<dir> auto-plays and saves screenshots.
func _demo() -> void:
	var dir := OS.get_environment("NF_SHOT")
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/a_menu.png")
	print("resetGame -> ", Game.resetGame(), " state=", Game.state)
	Inp.mouse.down = true
	for k in 6:
		Game.player.hp = Game.player.maxHp
		await get_tree().create_timer(4.0).timeout
		Game.player.hp = Game.player.maxHp
		Game.wave += 1
		get_viewport().get_texture().get_image().save_png(dir + "/b_play%d.png" % k)
		print("t=", Game.time, " wave=", Game.wave, " enemies=", Game.enemies.size(), " bullets=", Game.bullets.size(), " state=", Game.state)
	get_tree().quit()
