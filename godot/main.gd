extends Node2D
## Integration root: forwards input, drives the fixed-step sim, draws the world.
## All game logic lives in the autoload modules (see CONTRACT.md).

@onready var cam: Camera2D = $Camera

# Optional low-resolution world pass (mobile perf tier): the world is drawn into a SubViewport at
# Game.PERF.worldScale x the window's pixel size and shown through a TextureRect on a CanvasLayer BEHIND the UI
# layer (10), so the UI stays crisp at native resolution. At scale 1.0 the world is drawn directly (original path).
var _wv: SubViewport = null
var _wv_layer: CanvasLayer = null
var _wv_rect: TextureRect = null
var _wv_cam: Camera2D = null
var _wv_node: Node2D = null
var _wv_scale: float = 1.0
var _direct: bool = true

func _setup_world_view() -> void:
	_wv_layer = CanvasLayer.new()
	_wv_layer.layer = -5
	_wv_layer.name = "WorldLayer"
	add_child(_wv_layer)
	_wv = SubViewport.new()
	_wv.name = "WorldViewport"
	_wv.disable_3d = true
	_wv.gui_disable_input = true
	_wv.handle_input_locally = false
	_wv.transparent_bg = false
	_wv.size_2d_override_stretch = true
	_wv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_wv.size = Vector2i(16, 16)
	_wv_layer.add_child(_wv)
	_wv_node = Node2D.new()
	_wv_node.set_script(load("res://scripts/world_view.gd"))
	_wv.add_child(_wv_node)
	_wv_cam = Camera2D.new()
	_wv.add_child(_wv_cam)
	_wv_rect = TextureRect.new()
	_wv_rect.name = "WorldTexture"
	_wv_rect.texture = _wv.get_texture()
	_wv_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wv_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wv_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_wv_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_wv_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wv_layer.add_child(_wv_rect)
	Game.perf_tier_changed.connect(_update_world_view)
	_update_world_view()

func _update_world_view() -> void:
	var sc: float = clampf(float(Game.PERF.get("worldScale", 1.0)), 0.4, 1.0)
	var direct: bool = sc >= 0.99
	if direct != _direct or absf(sc - _wv_scale) > 0.001 or _wv_rect.visible == direct:
		_direct = direct
		_wv_scale = sc
		_wv_rect.visible = not direct
		_wv.render_target_update_mode = SubViewport.UPDATE_DISABLED if direct else SubViewport.UPDATE_ALWAYS
		queue_redraw()  # clears (or restores) the root-canvas world drawing
	if direct:
		return
	var logical: Vector2 = get_viewport_rect().size
	var px: Vector2 = Vector2(get_window().size)
	var want := Vector2i(maxi(16, roundi(px.x * sc)), maxi(16, roundi(px.y * sc)))
	if _wv.size != want:
		_wv.size = want
	var ov := Vector2i(roundi(logical.x), roundi(logical.y))
	if _wv.size_2d_override != ov:
		_wv.size_2d_override = ov

func _ready() -> void:
	_setup_world_view()
	Render.font = NFFonts.regular()
	UI.load_drone_config()
	World.generateWorld()
	if OS.get_environment("NF_E2E") != "":
		var drv: Script = load("res://tests/e2e.gd")
		var d: Node = drv.new()
		d.set("main", self)
		add_child(d)
	elif OS.get_environment("NF_SCREEN") != "":
		_screen_shot()
	elif OS.get_environment("NF_SHOT") != "":
		_demo()

func _input(e: InputEvent) -> void:
	# Pointer/touch presses over a UI panel or the HUD dock must not fire the weapon / move sticks.
	if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
		var pos: Vector2 = e.position
		var hud = UI.screens.get("hud")
		if UI.blocks_game_input() or UI.pointer_over_ui() or (hud != null and hud.pointer_over_hud(pos)):
			return
	if Inp.handle_event(e):
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	var vs := get_viewport_rect().size
	World.resize(vs.x, vs.y)
	Inp.set_view(vs, World.camera_center())
	Game.step_frame(dt)
	cam.position = World.camera_center()
	if _direct:
		queue_redraw()
	else:
		_update_world_view()
		_wv_cam.position = cam.position
		_wv_node.queue_redraw()

func _draw() -> void:
	if _direct:
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

# Dev-only: NF_SCREEN=<id> [NF_SHOT=<dir>] [NF_COMPACT=1] opens UI screen <id>, saves <dir>/screen_<id>.png, quits.
func _screen_shot() -> void:
	var id := OS.get_environment("NF_SCREEN")
	var dir := OS.get_environment("NF_SHOT") if OS.get_environment("NF_SHOT") != "" else "/tmp"
	await get_tree().create_timer(0.8).timeout
	UI.show_screen(id)
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/screen_" + id + ".png")
	print("NF_SCREEN ", id, " open=", UI.is_open(id))
	get_tree().quit()
