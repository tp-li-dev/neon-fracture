extends Node
## World — world/camera constants and transforms, field zones. See ../CONTRACT.md.
## Camera: the Godot Camera2D (owned by main.gd) should be positioned at camera_center()
## (or its top-left at camera_position()). Render draws in world coordinates.

const WORLD_W: float = 4800.0
const WORLD_H: float = 2700.0
const CAMERA_W: float = 1600.0
const CAMERA_H: float = 900.0
var W: float = WORLD_W
var H: float = WORLD_H
var VIEW_W: float = 1600.0
var VIEW_H: float = 900.0
var DPR: float = 1.0
var gameScale: float = 1.0
var gameOffsetX: float = 0.0
var gameOffsetY: float = 0.0
var lastCanvasPW: int = 0
var lastCanvasPH: int = 0
var camera: Dictionary = {"x": (WORLD_W - CAMERA_W) / 2.0, "y": (WORLD_H - CAMERA_H) / 2.0}

func camera_position() -> Vector2:
	return Vector2(camera.x, camera.y)

func camera_center() -> Vector2:
	return Vector2(camera.x + CAMERA_W / 2.0, camera.y + CAMERA_H / 2.0)

func clampCamera() -> void:
	camera.x = U.clamp(camera.x, 0, WORLD_W - CAMERA_W)
	camera.y = U.clamp(camera.y, 0, WORLD_H - CAMERA_H)

func snapCameraToPlayer() -> void:
	var p = Game.player
	if p != null and not p.is_empty():
		camera.x = p.x - CAMERA_W / 2.0
		camera.y = p.y - CAMERA_H / 2.0
	else:
		camera.x = (WORLD_W - CAMERA_W) / 2.0
		camera.y = (WORLD_H - CAMERA_H) / 2.0
	clampCamera()

## Replacement for the DOM resize(): call with the viewport size in pixels.
func resize(vw: float = -1.0, vh: float = -1.0) -> void:
	if vw > 0: VIEW_W = vw
	if vh > 0: VIEW_H = vh
	gameScale = minf(VIEW_W / CAMERA_W, VIEW_H / CAMERA_H)
	gameOffsetX = (VIEW_W - CAMERA_W * gameScale) * 0.5
	gameOffsetY = (VIEW_H - CAMERA_H * gameScale) * 0.5
	clampCamera()

func generateWorld() -> void:
	# No physical obstacles; passable "field zones" only.
	var zones: Array = []
	Game.fieldZones = zones
	var safeX: float = W / 2.0
	var safeY: float = H / 2.0
	var types := ["flow", "charge", "resonance"]
	var wanted := 14
	for i in range(wanted):
		for attempt in range(50):
			var r: float = U.rand(82, 128)
			var x: float = U.rand(r + 130, W - r - 130)
			var y: float = U.rand(r + 130, H - r - 130)
			if sqrt((x - safeX) * (x - safeX) + (y - safeY) * (y - safeY)) < 320: continue
			var bad := false
			for o in zones:
				if sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y)) < r + o.r + 190:
					bad = true
					break
			if bad: continue
			var type: String = types[i % types.size()]
			var hue: float = 185.0 if type == "flow" else (275.0 if type == "charge" else 42.0)
			zones.append({
				"x": x, "y": y, "r": r, "type": type, "hue": hue,
				"phase": U.rand(0, TAU),
				"cooldown": 0.0,
				"inside": false
			})
			break

func _zone_text(txt: String, hue: float) -> void:
	var p = Game.player
	if Game.texts.size() < Game.PERF.maxTexts:
		Game.texts.append({"x": p.x, "y": p.y - 30, "text": txt, "life": .75, "max": .75, "hue": hue, "size": 12})

func updateFieldZones(dt: float) -> void:
	var p = Game.player
	p.phaseSpeedTimer = maxf(0.0, float(p.get("phaseSpeedTimer", 0.0)) - dt)
	for z in Game.fieldZones:
		z.cooldown = maxf(0.0, float(z.get("cooldown", 0.0)) - dt)
		var dx: float = p.x - z.x
		var dy: float = p.y - z.y
		var inside: bool = sqrt(dx * dx + dy * dy) <= z.r
		if inside and not z.inside and z.cooldown <= 0.0:
			z.cooldown = 8.0
			if z.type == "flow":
				p.phaseSpeedTimer = maxf(float(p.get("phaseSpeedTimer", 0.0)), 1.65)
				_zone_text("FLOW +25% SPEED", 185)
				Audio.Sound.play("skill", {"gain": .045})
			elif z.type == "charge":
				p.dashReady = minf(1.0, p.dashReady + .38)
				_zone_text("PHASE CHARGE", 275)
				Audio.Sound.play("skill", {"gain": .045})
			else:
				Game.comboTimer = maxf(Game.comboTimer, Combat.comboWindow() + 1.25)
				_zone_text("RESONANCE LINK", 42)
				Audio.Sound.play("skill", {"gain": .045})
		z.inside = inside

func pointInCamera(x: float, y: float, pad: float = 0.0) -> bool:
	return x >= camera.x - pad and x <= camera.x + CAMERA_W + pad \
		and y >= camera.y - pad and y <= camera.y + CAMERA_H + pad

func updateCamera(dt: float, instant: bool = false) -> void:
	var p = Game.player
	var tx: float = U.clamp(p.x - CAMERA_W / 2.0, 0, W - CAMERA_W)
	var ty: float = U.clamp(p.y - CAMERA_H / 2.0, 0, H - CAMERA_H)
	if instant:
		camera.x = tx
		camera.y = ty
	else:
		var follow: float = 1.0 - exp(-dt * 8.5)
		camera.x += (tx - camera.x) * follow
		camera.y += (ty - camera.y) * follow
		clampCamera()

func runXpNeeded(level: float) -> int:
	return int(maxf(12.0, roundf(8.0 + 5.0 * level + 2.0 * pow(level, 1.25))))
