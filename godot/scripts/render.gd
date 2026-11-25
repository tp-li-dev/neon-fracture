extends Node
## Render — canvas-2D draw port. main.gd calls Render.draw(ci) from its _draw().
## Draws in WORLD coordinates (Camera2D follows World.camera_position()).
## shadowBlur is emulated by a wider low-alpha stroke drawn behind the crisp one.

var font: Font = null          # main.gd may set this; falls back to ThemeDB.fallback_font
var _base: Transform2D = Transform2D.IDENTITY
var _glow: bool = true

const ACTIVE_DEFS := {
	"nova": {"name": "反転ノヴァ", "icon": "✹", "cd": 15, "desc": "周囲の敵を攻撃し、近くの敵弾を消去。", "base": 4.5},
	"lance": {"name": "貫通砲", "icon": "⇢", "cd": 10, "desc": "0.7秒チャージ後に貫通ビーム。充填中は移動・照準可能。発射からCD開始。装甲無視。", "base": 7.5},
	"cleanse": {"name": "再起動", "icon": "✚", "cd": 22, "desc": "封印・侵食を解除。HPを少量回復し、ダッシュを回復。", "base": 0},
	"stasis": {"name": "重力拘束", "icon": "◎", "cd": 19, "desc": "周囲の敵を足止めしながら継続ダメージ。ボスにも有効。", "base": 2.5},
	"missiles": {"name": "誘導斉射", "icon": "⌖", "cd": 13, "desc": "近い敵へ装備スキル専用の誘導弾を射出。", "base": 2.2},
	"overdrive": {"name": "本体オーバードライブ", "icon": "⚡", "cd": 24, "desc": "一定時間、本体の弾ダメージと連射速度を強化。", "base": 0},
	"prism": {"name": "プリズム・バースト", "icon": "✧", "cd": 17, "desc": "0.95秒チャージ後、3方向へ装甲無視ビーム。光線ごとに420%ダメージ。", "base": 4.2},
	"orbital": {"name": "星雨砲撃", "icon": "☄", "cd": 18, "desc": "照準地点と周囲へ6発の彗星。予告後にそれぞれ180%の範囲攻撃。", "base": 1.8},
	"blades": {"name": "ブレード・サテライト", "icon": "✥", "cd": 20, "desc": "5秒間、6枚の旋回刃を展開。接触ダメージは同じ敵へ0.3秒間隔。", "base": 1.2},
	"arclattice": {"name": "雷光連結", "icon": "ϟ", "cd": 14, "desc": "近い敵から5体へ連鎖雷を3回放つ。1回150%ダメージ。", "base": 1.5},
	"singularity": {"name": "重力崩壊", "icon": "◉", "cd": 24, "desc": "照準位置に重力井戸。0.9秒後から3秒の拘束・継続ダメージ、最後に爆発。", "base": 1.6}
}

func _ready() -> void:
	if font == null:
		font = ThemeDB.fallback_font
	_disc_tex = _make_disc(64)

# Cached textures: draw_circle costs ~5us and draw_arc ~3.6us per call, a textured rect ~0.2us
# (and batches), so small discs / rings are drawn as modulated texture rects.
var _disc_tex: Texture2D = null
var _ring_tex: Dictionary = {}

func _make_disc(sz: int) -> Texture2D:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var h: float = sz / 2.0
	for y in range(sz):
		for x in range(sz):
			var d: float = Vector2(x + .5 - h, y + .5 - h).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(h - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _get_ring(q: int) -> Texture2D:
	# q = inner/outer radius ratio in 1/64 steps
	if _ring_tex.has(q):
		return _ring_tex[q]
	var sz: int = 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var h: float = sz / 2.0
	var inner: float = h * float(q) / 64.0
	for y in range(sz):
		for x in range(sz):
			var d: float = Vector2(x + .5 - h, y + .5 - h).length()
			var a: float = clampf(h - d, 0.0, 1.0) * clampf(d - inner + 0.5, 0.0, 1.0) if inner > 0.0 else clampf(h - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	_ring_tex[q] = t
	return t

# ---------------------------------------------------------------- color helpers
func hsl(h: float, s: float, l: float, a: float = 1.0) -> Color:
	## s, l in 0..100 like CSS
	var sf: float = s / 100.0
	var lf: float = l / 100.0
	var v: float = lf + sf * minf(lf, 1.0 - lf)
	var sv: float = 0.0 if v <= 0.0 else 2.0 * (1.0 - lf / v)
	return Color.from_hsv(fposmod(h, 360.0) / 360.0, sv, v, a)

func hexToHSLA(h: float, a: float = .7, l: float = 60) -> Color:
	return hsl(h, 95.0, l, a)

func _ca(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)

func _rgba(r: int, g: int, b: int, a: float) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)

# ---------------------------------------------------------------- primitive helpers
func _xf(ci: CanvasItem, pos: Vector2 = Vector2.ZERO, rot: float = 0.0) -> void:
	ci.draw_set_transform_matrix(_base * Transform2D(rot, pos))

func _segs(r: float) -> int:
	return clampi(int(r * 0.8) + 12, 16, 56)

func _circ(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float) -> void:
	if r > 70.0 or r - w * 0.5 <= 0.0 or _disc_tex == null:
		ci.draw_arc(c, r, 0.0, TAU, _segs(r), col, w)
		return
	var outer: float = r + w * 0.5
	var q: int = clampi(roundi((r - w * 0.5) / outer * 64.0), 1, 63)
	ci.draw_texture_rect(_get_ring(q), Rect2(c.x - outer, c.y - outer, outer * 2.0, outer * 2.0), false, col)

func _fcirc(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r > 70.0 or _disc_tex == null:
		ci.draw_circle(c, r, col)
		return
	ci.draw_texture_rect(_disc_tex, Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), false, col)

func _dash_circle(ci: CanvasItem, c: Vector2, r: float, dash: float, gap: float, col: Color, w: float) -> void:
	if r <= 0.5: return
	var step: float = dash + gap
	var n: int = mini(80, maxi(1, int(TAU * r / step)))
	# One multiline command instead of one draw_arc per dash.
	var pts := PackedVector2Array()
	for i in range(n):
		var a0: float = float(i) * step / r
		var a1: float = a0 + dash / r
		var am: float = (a0 + a1) * 0.5
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var pm := c + Vector2(cos(am), sin(am)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		pts.append(p0); pts.append(pm); pts.append(pm); pts.append(p1)
	ci.draw_multiline(pts, col, w)

## Canvas setLineDash([dash, gap]) equivalent (draw_dashed_line uses equal gap).
func _dashed(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, dash: float, gap: float) -> void:
	var d: Vector2 = b - a
	var len: float = d.length()
	if len < 0.01:
		return
	var dir: Vector2 = d / len
	var step: float = dash + gap
	var n: int = mini(200, int(ceil(len / step)))
	var pts := PackedVector2Array()
	for i in range(n):
		var s0: float = float(i) * step
		pts.append(a + dir * s0)
		pts.append(a + dir * minf(len, s0 + dash))
	ci.draw_multiline(pts, col, w)

func _truthy(v) -> bool:
	match typeof(v):
		TYPE_NIL: return false
		TYPE_BOOL: return v
		TYPE_INT, TYPE_FLOAT: return v != 0
		TYPE_STRING: return v != ""
		_: return true

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var o := pts.duplicate()
	o.append(pts[0])
	return o

func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, stroke: Color, w: float, glow: Color = Color(0, 0, 0, 0)) -> void:
	if fill.a > 0.0:
		ci.draw_colored_polygon(pts, fill)
	var cl := _closed(pts)
	if _glow and glow.a > 0.0:
		ci.draw_polyline(cl, glow, w + 5.0)
	if stroke.a > 0.0:
		ci.draw_polyline(cl, stroke, w)

func _text(ci: CanvasItem, txt: String, x: float, y: float, size: int, col: Color, align: int = 1, mid: bool = false) -> void:
	var f: Font = font if font != null else ThemeDB.fallback_font
	var yy: float = y + (size * 0.35 if mid else 0.0)
	match align:
		1: ci.draw_string(f, Vector2(x - 400.0, yy), txt, HORIZONTAL_ALIGNMENT_CENTER, 800.0, size, col)
		2: ci.draw_string(f, Vector2(x - 800.0, yy), txt, HORIZONTAL_ALIGNMENT_RIGHT, 800.0, size, col)
		_: ci.draw_string(f, Vector2(x, yy), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, col)

# ---------------------------------------------------------------- input helpers (original dxMove/dyMove)
func dxMove() -> float:
	if Inp.inputMode == "touch" and Inp.mobileMove.active:
		return Inp.mobileMove.x
	return (1.0 if (Inp.keyboardMoveHeld("KeyD") or Inp.keyboardMoveHeld("ArrowRight")) else 0.0) \
		- (1.0 if (Inp.keyboardMoveHeld("KeyA") or Inp.keyboardMoveHeld("ArrowLeft")) else 0.0)

func dyMove() -> float:
	if Inp.inputMode == "touch" and Inp.mobileMove.active:
		return Inp.mobileMove.y
	return (1.0 if (Inp.keyboardMoveHeld("KeyS") or Inp.keyboardMoveHeld("ArrowDown")) else 0.0) \
		- (1.0 if (Inp.keyboardMoveHeld("KeyW") or Inp.keyboardMoveHeld("ArrowUp")) else 0.0)

# ---------------------------------------------------------------- background
func drawBackground(ci: CanvasItem) -> void:
	var cam: Dictionary = World.camera
	var cx: float = cam.x
	var cy: float = cam.y
	var p = Game.player
	_base = Transform2D.IDENTITY
	_xf(ci)
	ci.draw_rect(Rect2(cx - 4000, cy - 4000, World.CAMERA_W + 8000, World.CAMERA_H + 8000), Color("#020409"))
	ci.draw_rect(Rect2(cx, cy, World.CAMERA_W, World.CAMERA_H), _rgba(2, 4, 9, 1))
	# radial gradient approximated with concentric discs (back to front)
	var pc := Vector2(p.x, p.y)
	var steps := 7
	for i in range(steps):
		var t: float = 1.0 - float(i) / float(steps)   # 1.0 -> 0.14
		var col: Color
		if t > 0.58:
			col = _rgba(2, 4, 9, 1).lerp(_rgba(5, 8, 17, 1), (1.0 - t) / 0.42)
		else:
			col = _rgba(5, 8, 17, 1).lerp(_rgba(10, 15, 27, 1), 1.0 - t / 0.58)
		_fcirc(ci, pc, 1050.0 * t, col)
	# stars
	var pts: Array = Game.stars
	for st in pts:
		if not World.pointInCamera(st.x, st.y, 8):
			continue
		ci.draw_rect(Rect2(st.x, st.y, st.s, st.s), Color(0.875, 0.976, 1.0, st.a))
	# grid
	var spacing: float = 96.0 if Game.bossAlive else 72.0
	var sx: float = floorf(cx / spacing) * spacing
	var sy: float = floorf(cy / spacing) * spacing
	var lines := PackedVector2Array()
	var x: float = sx
	while x <= cx + World.CAMERA_W + spacing:
		lines.append(Vector2(x, cy)); lines.append(Vector2(x, cy + World.CAMERA_H))
		x += spacing
	var y: float = sy
	while y <= cy + World.CAMERA_H + spacing:
		lines.append(Vector2(cx, y)); lines.append(Vector2(cx + World.CAMERA_W, y))
		y += spacing
	ci.draw_multiline(lines, _rgba(68, 127, 160, .055), 1.0)
	# map border
	ci.draw_rect(Rect2(8, 8, World.W - 16, World.H - 16), _rgba(34, 211, 238, .28), false, 5.0)
	# field zones
	var time: float = Game.time
	for z in Game.fieldZones:
		if not World.pointInCamera(z.x, z.y, z.r + 45):
			continue
		var ready: bool = z.cooldown <= 0.0
		var pulse: float = .5 + sin(time * 2.2 + z.phase) * .5
		var ga: float = .88 if ready else .28
		_xf(ci, Vector2(z.x, z.y), time * .12 + z.phase)
		var fc: Color = _ca(hexToHSLA(z.hue, .055 if ready else .025, 48), ga)
		var sc: Color = _ca(hexToHSLA(z.hue, (.38 + .18 * pulse) if ready else .12, 64), ga)
		_fcirc(ci, Vector2.ZERO, z.r, fc)
		_circ(ci, Vector2.ZERO, z.r, sc, 1.5)
		_xf(ci, Vector2(z.x, z.y), time * .12 + z.phase - time * .30)
		_dash_circle(ci, Vector2.ZERO, z.r * .72, 9.0, 13.0, sc, 1.5)
		_xf(ci, Vector2(z.x, z.y), time * .12 + z.phase - time * .30)
		var icon: String = "»" if z.type == "flow" else ("◫" if z.type == "charge" else "∞")
		var nm: String = "FLOW" if z.type == "flow" else ("CHARGE" if z.type == "charge" else "LINK")
		_text(ci, icon, 0, -6, 22, _ca(hexToHSLA(z.hue, .9, 72), .55 if ready else .16), 1, true)
		_text(ci, nm, 0, 16, 9, _ca(hexToHSLA(z.hue, .9, 72), .72 if ready else .22), 1, true)
	_xf(ci)

# ---------------------------------------------------------------- friendly effects / blades
func drawBladeSet(ci: CanvasItem, points: Array, hue: float) -> void:
	var time: float = Game.time
	var stroke: Color = hsl(hue, 95, 76)
	var fill: Color = hsl(hue, 90, 65, .18)
	var shape := PackedVector2Array([Vector2(-15, 0), Vector2(0, -7), Vector2(15, 0), Vector2(0, 7)])
	for b in points:
		_xf(ci, Vector2(b.x, b.y), time * 3.0)
		_poly(ci, shape, fill, stroke, 2.0)
	_xf(ci)

func drawFriendlyEffects(ci: CanvasItem) -> void:
	var time: float = Game.time
	var player = Game.player
	for h in Game.friendlyEffects:
		if h.get("dead", false): continue
		var ready: bool = h.age >= h.warn
		var p: float = U.clamp(h.age / maxf(.001, h.warn), 0, 1)
		var fade: float = U.clamp(1.0 - (h.age - h.warn) / h.duration, 0, 1) if ready else 1.0
		var stroke: Color = hsl(h.hue, 92, 72, (.85 * fade) if ready else .65)
		var fill: Color = hsl(h.hue, 90, 65, (.08 * fade) if ready else .035)
		var kind: String = h.kind
		var hp := Vector2(h.x, h.y)
		if kind == "beam":
			var angles: Array = []
			if h.has("angles") and h.angles != null:
				angles = h.angles
			else:
				angles.append(h.a)
				for i in range(mini(3, int(h.get("branches", 0)))):
					angles.append(h.a + (i + 1) * .18)
					angles.append(h.a - (i + 1) * .18)
			for a in angles:
				var p2 := Vector2(h.x + cos(a) * h.length, h.y + sin(a) * h.length)
				if ready:
					var w: float = h.width * fade
					ci.draw_line(hp, p2, stroke, maxf(1.0, w))
					ci.draw_line(hp, p2, Color(245 / 255.0, 1, 1, fade), maxf(2.0, h.width * .22 * fade))
				else:
					_dashed(ci, hp, p2, stroke, 2.0, 4.0, 12.0)
			if not ready:
				if p > 0.0:
					ci.draw_arc(hp, 24, 0, TAU * p, 24, stroke, 3.0)
				_fcirc(ci, hp, 5 + 10 * p, fill)
				if _truthy(h.get("slot", null)):
					_text(ci, "充填 %d%%" % roundi(p * 100.0), h.x, h.y - 36, 12, Color("#c7fbff"))
		elif kind == "meteor" or kind == "well":
			_fcirc(ci, hp, h.radius, fill)
			if ready:
				_circ(ci, hp, h.radius, stroke, 2.0)
			else:
				_dash_circle(ci, hp, h.radius, 4.0, 10.0, stroke, 2.0)
				_circ(ci, hp, maxf(2.0, h.radius * (1.0 - p)), stroke, 3.0)
				_text(ci, "味方砲撃" if kind == "meteor" else "重力収束", h.x, h.y - 14, 12, Color("#b5edff"))
			if ready:
				if kind == "meteor":
					ci.draw_line(Vector2(h.x - 70 * fade, h.y - 230 * fade), hp, _ca(stroke, fade), maxf(1.0, 8 * fade))
				else:
					for i in range(3):
						var rx: float = h.radius * (.25 + i * .22)
						var ry: float = h.radius * .24
						var rot: float = time * 2.0 + i
						var pts := PackedVector2Array()
						for k in range(25):
							var ang: float = TAU * k / 24.0
							var ex: float = cos(ang) * rx
							var ey: float = sin(ang) * ry
							pts.append(Vector2(h.x + ex * cos(rot) - ey * sin(rot), h.y + ex * sin(rot) + ey * cos(rot)))
						ci.draw_polyline(pts, stroke, 2.0)
		elif kind == "orbit" and ready:
			drawBladeSet(ci, Combat.bladePositions(player.x, player.y, h.radius, h.count, time * 2.5), h.hue)
	var ge = player.get("gearEffects", null)
	if ge != null and ge.get("orbit", false):
		drawBladeSet(ci, Combat.bladePositions(player.x, player.y, 150, 4, time * 2.4), 205)
	if float(player.get("bladePower", 0)) > 0.0:
		drawBladeSet(ci, Combat.bladePositions(player.x, player.y, 180, mini(8, int(player.bladeCount)), time * 2.4 + .5), 185)

# ---------------------------------------------------------------- hazards / loot / projectiles / enemy info
func drawHazards(ci: CanvasItem) -> void:
	for h in Game.hazards:
		var ready: bool = h.age >= h.warn
		var f: float = U.clamp(h.age / h.warn, 0, 1)
		var lw: float = 4.0 if ready else 2.0
		var sc: Color
		if h.kind == "break": sc = Color("#ef76d9")
		elif h.kind == "pierce": sc = Color("#ffb572")
		else: sc = Color("#ff6e66")
		var fc: Color = _rgba(225, 65, 189, .13) if h.kind == "break" else _rgba(255, 85, 65, .11)
		var rad: float = float(h.get("radius", 0.0))
		if h.shape == "circle":
			var c := Vector2(h.x, h.y)
			_fcirc(ci, c, h.radius, fc)
			if ready:
				_circ(ci, c, h.radius, sc, lw)
			else:
				_dash_circle(ci, c, h.radius, 8.0, 7.0, sc, lw)
			_circ(ci, c, maxf(0.5, h.radius * f), sc, 2.0 if not ready else lw)
		else:
			var x2: float = h.x + cos(h.a) * h.length if h.shape == "shot" else h.x2
			var y2: float = h.y + sin(h.a) * h.length if h.shape == "shot" else h.y2
			var w: float = float(h.get("width", 5)) if ready else 2.0
			if ready:
				ci.draw_line(Vector2(h.x, h.y), Vector2(x2, y2), sc, w)
			else:
				_dashed(ci, Vector2(h.x, h.y), Vector2(x2, y2), sc, w, 8.0, 7.0)
		var lab: String = str(h.get("label", ""))
		_text(ci, lab, h.x, h.y - (rad if rad != 0.0 else 30.0) - 14.0, 14, Color("#ffe2dc"))

func drawReadableLoot(ci: CanvasItem) -> void:
	for g in Game.gems:
		if g.get("collected", false) or not World.pointInCamera(g.x, g.y, 25):
			continue
		var kind: String = str(g.get("kind", ""))
		var s: float = 11.0 if kind == "boss" else (8.0 if kind == "rare" else 6.0)
		var sc: Color = Color("#ffe39b") if kind == "boss" else (Color("#bff7ce") if kind == "rare" else Color("#57e2b5"))
		var r := Rect2(g.x - s, g.y - s, s * 2, s * 2)
		ci.draw_rect(r, Color("#09261f"))
		ci.draw_rect(r, sc, false, 1.8)
		var c2: Color = Color("#ffe39b") if kind == "boss" else Color("#b2f9d9")
		ci.draw_line(Vector2(g.x - s * .45, g.y), Vector2(g.x + s * .45, g.y), c2, 1.3)
		ci.draw_line(Vector2(g.x, g.y - s * .45), Vector2(g.x, g.y + s * .45), c2, 1.3)

func drawReadableProjectiles(ci: CanvasItem) -> void:
	# Perf: opaque strokes are drawn as stacked discs (stroke disc under fill disc == fill + centred stroke),
	# and player-bullet trails are batched per (colour,width) into single multiline commands.
	var cam: Dictionary = World.camera
	var x0: float = cam.x - 35.0
	var x1: float = cam.x + World.CAMERA_W + 35.0
	var y0: float = cam.y - 35.0
	var y1: float = cam.y + World.CAMERA_H + 35.0
	var trails: Dictionary = {}
	var dots: Array = []
	var xc := Color("#5b0039")
	for b in Game.bullets:
		if b == null or b.get("_dead", false):
			continue
		var bx: float = b.x
		var by: float = b.y
		if bx < x0 or bx > x1 or by < y0 or by > y1:
			continue
		var bp := Vector2(bx, by)
		var br: float = b.r
		if b.get("enemy", false):
			var ak: String = str(b.get("attackKind", ""))
			var fill: Color = Color("#f65bc7") if ak == "break" else (Color("#ff986c") if ak == "wound" else Color("#ff6853"))
			if ak == "break" or ak == "pierce":
				var ang: float = atan2(b.vy, b.vx)
				var cs: float = cos(ang)
				var sn: float = sin(ang)
				var pts := PackedVector2Array([
					bp + Vector2(cs, sn) * (br + 3.0), bp + Vector2(sn, -cs) * br,
					bp - Vector2(cs, sn) * br, bp + Vector2(-sn, cs) * br])
				ci.draw_colored_polygon(pts, fill)
				ci.draw_polyline(_closed(pts), Color("#fff1e5"), 1.5)
				var ux := Vector2(cs, sn)
				var uy := Vector2(-sn, cs)
				ci.draw_multiline(PackedVector2Array([bp + ux * -3.0 + uy * -3.0, bp + ux * 3.0 + uy * 3.0,
					bp + ux * -3.0 + uy * 3.0, bp + ux * 3.0 + uy * -3.0]), xc, 1.5)
			else:
				_fcirc(ci, bp, br + 1.75, Color("#fff1e5"))
				_fcirc(ci, bp, br + 0.25, fill)
				_fcirc(ci, bp, 2.0, Color("#511814"))
		else:
			var from_drone: bool = b.get("fromDrone", false)
			var ci_idx: int = 0 if from_drone else (1 if b.get("source", "") is String and b.get("source", "") == "active" else 2)
			var lw: float = 2.0 if from_drone else maxf(2.0, br * .85)
			var sp: float = sqrt(b.vx * b.vx + b.vy * b.vy)
			if sp == 0.0: sp = 1.0
			var key: int = ci_idx * 1000 + int(lw * 10.0)
			if not trails.has(key):
				trails[key] = PackedVector2Array()
			var arr: PackedVector2Array = trails[key]
			arr.append(Vector2(bx - b.vx / sp * 12.0, by - b.vy / sp * 12.0))
			arr.append(bp)
			trails[key] = arr
			dots.append([bp, br, ci_idx])
	var cols: Array = [Color("#bca8fd"), Color("#fff2b0"), Color("#8deafa")]
	for key in trails:
		var idx: int = int(key) / 1000
		var w: float = float(int(key) % 1000) / 10.0
		ci.draw_multiline(trails[key], cols[idx], w)
	for d in dots:
		_fcirc(ci, d[0], d[1], cols[d[2]])

func drawEnemyInfo(ci: CanvasItem, e: Dictionary) -> void:
	if float(e.get("spawnDelay", 0)) > 0.0 or e.get("_dead", false):
		return
	var time: float = Game.time
	var t: String = str(e.type)
	var special: bool = t in ["disruptor", "lancer", "medic", "bulwark", "bombardier", "suppressor"]
	var boss: bool = e.get("boss", false)
	var elite: bool = e.get("elite", false)
	if special:
		var sym := {"disruptor": "×", "lancer": "⇢", "medic": "+", "bulwark": "▣", "bombardier": "!", "suppressor": "↓"}
		_text(ci, sym[t], e.x, e.y + 5, 16, Color("#fff1e6"))
	if boss or elite or special:
		_text(ci, "%s Lv.%s" % [Enemies.enemyName(e), str(e.level)], e.x, e.y - e.r - (25 if boss else 12), 16 if boss else 12, Color("#ffd49c") if boss else Color("#cfdae6"))
	var ep := Vector2(e.x, e.y)
	if float(e.get("burnTime", 0)) > 0.0:
		_circ(ci, ep, e.r + 4, Color("#ff944d"), 2.0)
	if e.get("armored", false) or float(e.get("protectedUntil", 0)) > time:
		_dash_circle(ci, ep, e.r + 7, 4.0, 4.0, Color("#7aaaff"), 1.5)
	if float(e.get("windup", 0)) > 0.0:
		var ca: float = e.chargeAngle
		_dashed(ci, ep, Vector2(e.x + cos(ca) * 165, e.y + sin(ca) * 165), Color("#ff9f6f"), 2.0, 7.0, 7.0)

# ---------------------------------------------------------------- main render
func draw(ci: CanvasItem) -> void:
	var G = Game
	var player = G.player
	if player == null or player.is_empty():
		return
	var time: float = G.time
	var cam: Dictionary = World.camera
	var heavy: bool = G.bossAlive or G.bullets.size() > 120 or G.enemies.size() > 25 or G.particles.size() > 140
	_glow = not heavy
	drawBackground(ci)
	var shake := Vector2.ZERO
	if G.state == "playing" and G.screenShake:
		shake = Vector2(U.rand(-G.screenShake, G.screenShake), U.rand(-G.screenShake, G.screenShake))
	_base = Transform2D(0.0, shake)
	_xf(ci)

	drawReadableLoot(ci)
	drawFriendlyEffects(ci)
	drawHazards(ci)

	# Rings / lightning
	for r in G.rings:
		var q: float = 1.0 - r.life / r.max
		var al: float = 1.0 - q
		var col: Color = _ca(hexToHSLA(r.hue, 1.0 - q, 68), al)
		if r.get("line", false):
			var mx: float = (r.x + r.x2) / 2.0 + sin(time * 67.0 + r.x) * 12.0
			var my: float = (r.y + r.y2) / 2.0 + cos(time * 73.0 + r.y) * 12.0
			var pts := PackedVector2Array([Vector2(r.x, r.y), Vector2(mx, my), Vector2(r.x2, r.y2)])
			if _glow: ci.draw_polyline(pts, _ca(hexToHSLA(r.hue, .8, 60), .25 * al), 8.0)
			ci.draw_polyline(pts, col, 2.5)
		else:
			var rr: float = r.r + q * float(r.get("extent", 90))
			if _glow: _circ(ci, Vector2(r.x, r.y), rr, _ca(hexToHSLA(r.hue, .8, 60), .22 * al), 7.0)
			_circ(ci, Vector2(r.x, r.y), rr, col, 2.0)

	drawReadableProjectiles(ci)

	# Enemies
	var tele: float = Enemies.SPAWN_TELEGRAPH
	for e in G.enemies:
		if e.get("_dead", false) or not World.pointInCamera(e.x, e.y, e.r + 85):
			continue
		var eboss: bool = e.get("boss", false)
		var sd: float = float(e.get("spawnDelay", 0))
		if sd > 0.0:
			var p: float = 1.0 - sd / maxf(.001, float(e.get("spawnTotal", tele)))
			var tx: float = U.clamp(e.x, 12, World.W - 12)
			var ty: float = U.clamp(e.y, 12, World.H - 12)
			var sc: Color = _rgba(251, 113, 133, .95) if eboss else hexToHSLA(e.hue, .9, 66)
			sc = _ca(sc, .35 + p * .55)
			var lw: float = 3.0 if eboss else 2.0
			_dash_circle(ci, Vector2(tx, ty), 12 + p * 18, 5.0, 6.0, sc, lw)
			ci.draw_line(Vector2(tx - 7, ty), Vector2(tx + 7, ty), sc, lw)
			ci.draw_line(Vector2(tx, ty - 7), Vector2(tx, ty + 7), sc, lw)
			continue
		var hit: bool = float(e.get("hitFlash", 0)) > 0.0
		var fillc: Color = Color(1, 1, 1, .95) if hit else hexToHSLA(e.hue, .24, 52)
		var strokec: Color = Color.WHITE if hit else hexToHSLA(e.hue, .92, 66)
		var glowc: Color = hexToHSLA(e.hue, .65, 55)
		glowc.a = .2
		var lwid: float = 3.0 if eboss else 1.8
		var er: float = e.r
		var rot: float = time * (.25 if eboss else .55) + float(e.get("phase", 0)) * .15
		var ep := Vector2(e.x, e.y)
		_xf(ci, ep, rot)
		var et: String = str(e.type)
		var o := Vector2.ZERO
		if eboss:
			var pts := PackedVector2Array()
			for i in range(8):
				var a: float = float(i) / 8.0 * TAU
				var rr: float = er * (1.0 if (i % 2) == 1 else .74)
				pts.append(Vector2(cos(a) * rr, sin(a) * rr))
			_poly(ci, pts, fillc, strokec, lwid, glowc)
			_xf(ci, ep, rot - time * .6)
			_circ(ci, o, er * .48, strokec, lwid)
			_fcirc(ci, o, er * .18, fillc)
		elif et == "tank":
			var pts := PackedVector2Array()
			for i in range(6):
				var a: float = float(i) / 6.0 * TAU
				pts.append(Vector2(cos(a) * er, sin(a) * er))
			_poly(ci, pts, fillc, strokec, lwid, glowc)
		elif et == "shooter":
			_xf(ci, ep, rot + PI / 4.0)
			var s: float = er * .72
			_poly(ci, PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)]), fillc, strokec, lwid, glowc)
		elif et == "splitter":
			_poly(ci, PackedVector2Array([Vector2(0, -er), Vector2(er, 0), Vector2(0, er), Vector2(-er, 0)]), fillc, strokec, lwid, glowc)
		elif et == "charger":
			_poly(ci, PackedVector2Array([Vector2(er, 0), Vector2(-er * .8, -er * .7), Vector2(-er * .45, 0), Vector2(-er * .8, er * .7)]), fillc, strokec, lwid, glowc)
		elif et == "orbiter":
			if _glow: _circ(ci, o, er, glowc, lwid + 5.0)
			_circ(ci, o, er, strokec, lwid)
			_fcirc(ci, o, er * .42, fillc)
			ci.draw_line(Vector2(-er - 4, 0), Vector2(er + 4, 0), strokec, lwid)
		else:
			_fcirc(ci, o, er, fillc)
			if _glow: _circ(ci, o, er, glowc, lwid + 5.0)
			_circ(ci, o, er, strokec, lwid)
			if et == "swift":
				ci.draw_line(Vector2(-er * .6, 0), Vector2(er * .65, 0), strokec, lwid)
		if e.get("elite", false):
			_xf(ci, ep, rot - time * .9)
			_dash_circle(ci, o, er + 5, 3.0, 5.0, _rgba(251, 191, 36, .8), 1.2)
		_xf(ci)
		drawEnemyInfo(ci, e)
		if eboss or et == "tank":
			var w: float = 110.0 if eboss else 36.0
			var pct: float = U.clamp(e.hp / e.maxHp, 0, 1)
			ci.draw_rect(Rect2(e.x - w / 2.0, e.y - er - 15, w, 4), _rgba(2, 6, 23, .65))
			ci.draw_rect(Rect2(e.x - w / 2.0, e.y - er - 15, w * pct, 4), hexToHSLA(e.hue, .95, 62))

	# Drones
	var dcfg = UI.get("droneConfig")
	var dena: bool = true if dcfg == null else bool(dcfg.get("enabled", true))
	var dmul: float = 1.0 if dena else .28
	var di := 0
	for d in G.drones:
		if not (is_finite(d.x) and is_finite(d.y)):
			di += 1
			continue
		_xf(ci, Vector2(d.x, d.y), time * 2.0 + di)
		_poly(ci, PackedVector2Array([Vector2(0, -7), Vector2(7, 5), Vector2(-7, 5)]),
			_rgba(168, 85, 247, .18 * dmul), _rgba(216, 180, 254, .9 * dmul), 1.5, _rgba(168, 85, 247, .2 * dmul))
		_xf(ci)
		ci.draw_line(Vector2(player.x, player.y), Vector2(d.x, d.y), _rgba(168, 85, 247, .08), 1.0)
		di += 1

	# Player
	var st: String = G.state
	if (st != "menu" and st != "gameover") or player.hp > 0:
		var mouse = Inp.mouse
		var pp := Vector2(player.x, player.y)
		var ang: float = atan2(mouse.y - player.y, mouse.x - player.x)
		var ga: float = 1.0
		if player.invuln > 0 and sin(time * 40.0) > 0.0:
			ga = .45
		_xf(ci, pp, ang)
		var glow_saved: bool = _glow
		_glow = true
		var pts := PackedVector2Array([Vector2(19, 0), Vector2(-9, -10), Vector2(-5, 0), Vector2(-9, 10)])
		_poly(ci, pts, _rgba(34, 211, 238, .16 * ga), _rgba(165, 243, 252, .98 * ga), 2.0, _rgba(34, 211, 238, .22 * ga))
		_glow = glow_saved
		_fcirc(ci, Vector2(2, 0), 3.1, Color(1, 1, 1, .92 * ga))
		if st == "playing" and (dxMove() != 0.0 or dyMove() != 0.0):
			var tc := _rgba(34, 211, 238, .38 * ga)
			ci.draw_line(Vector2(-9, -4), Vector2(-17 - U.rand(0, 10), -2), tc, 3.0)
			ci.draw_line(Vector2(-9, 4), Vector2(-17 - U.rand(0, 10), 2), tc, 3.0)
		_xf(ci)
		var aimD: float = sqrt((mouse.x - player.x) * (mouse.x - player.x) + (mouse.y - player.y) * (mouse.y - player.y))
		if aimD > 30.0:
			_dashed(ci, Vector2(player.x + cos(ang) * 24, player.y + sin(ang) * 24), Vector2(mouse.x, mouse.y),
				_rgba(165, 243, 252, .75 * .22), 1.0, 3.0, 8.0)
			_xf(ci, Vector2(mouse.x, mouse.y), time * .7)
			var rc := _rgba(165, 243, 252, .8 * .78)
			_circ(ci, Vector2.ZERO, 10, rc, 1.0)
			var rl := PackedVector2Array([Vector2(-15, 0), Vector2(-6, 0), Vector2(15, 0), Vector2(6, 0),
				Vector2(0, -15), Vector2(0, -6), Vector2(0, 15), Vector2(0, 6)])
			ci.draw_multiline(rl, rc, 1.0)
			_xf(ci)

	# Particles
	for p in G.particles:
		var a: float = U.clamp(p.life / p.max, 0, 1)
		ci.draw_rect(Rect2(p.x, p.y, p.size, p.size), _ca(hexToHSLA(p.hue, a, 68), a))

	# Floating texts
	for t in G.texts:
		var a: float = U.clamp(t.life / t.max, 0, 1)
		var col: Color = _ca(hexToHSLA(t.hue, a, 72), minf(1.0, a * 1.8))
		var sz: int = int(t.get("size", 14))
		if sz == 0: sz = 14
		if _glow:
			_text(ci, str(t.text), t.x + 1, t.y + 1, sz, Color(0, 0, 0, .35 * col.a), 1, true)
		_text(ci, str(t.text), t.x, t.y, sz, col, 1, true)

	# ---- screen-space (camera-fixed) layer: offscreen warnings, minimap
	_base = Transform2D(0.0, Vector2(cam.x, cam.y))
	_xf(ci)
	var cw: float = World.CAMERA_W
	var ch: float = World.CAMERA_H
	var mapEsp: bool = bool(player.get("mapEsp", false))
	var mapAdv: bool = bool(player.get("mapEspAdvanced", false))
	for e in G.enemies:
		if e.get("_dead", false) or World.pointInCamera(e.x, e.y, 0):
			continue
		var dx: float = e.x - player.x
		var dy: float = e.y - player.y
		var d: float = sqrt(dx * dx + dy * dy)
		if d > 1250.0 and not mapAdv and not (mapEsp and (e.get("boss", false) or e.get("elite", false))):
			continue
		var a: float = atan2(dy, dx)
		var rx: float = cw / 2.0 - 34.0
		var ry: float = ch / 2.0 - 34.0
		var tt: float = 1.0 / maxf(absf(cos(a)) / rx, absf(sin(a)) / ry)
		var ix: float = cw / 2.0 + cos(a) * tt
		var iy: float = ch / 2.0 + sin(a) * tt
		var ac: Color = _rgba(251, 113, 133, .95) if e.get("boss", false) else _rgba(103, 232, 249, .9)
		ac.a *= .85 if float(e.get("spawnDelay", 0)) > 0.0 else .32
		_xf(ci, Vector2(ix, iy), a)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(10, 0), Vector2(-7, -6), Vector2(-7, 6)]), ac)
	_xf(ci)
	# minimap
	var mw := 174.0
	var mh := 98.0
	var mx := 22.0
	var my: float = ch - mh - 22.0
	ci.draw_rect(Rect2(mx, my, mw, mh), _rgba(2, 6, 23, .72))
	ci.draw_rect(Rect2(mx, my, mw, mh), _rgba(148, 163, 184, .25), false, 1.0)
	var sx: float = mw / World.W
	var sy: float = mh / World.H
	ci.draw_rect(Rect2(mx + cam.x * sx, my + cam.y * sy, cw * sx, ch * sy), _rgba(34, 211, 238, .22), false, 1.0)
	for e in G.enemies:
		if e.get("_dead", false) or float(e.get("spawnDelay", 0)) > 0.0:
			continue
		var eb: bool = e.get("boss", false)
		if not mapEsp and not eb:
			continue
		var mc: Color
		if eb: mc = _rgba(251, 113, 133, .98)
		elif e.get("elite", false): mc = _rgba(216, 180, 254, .95)
		else: mc = _rgba(103, 232, 249, .68)
		var rr: float = 3.4 if eb else (2.2 if e.get("elite", false) else 1.25)
		_fcirc(ci, Vector2(mx + e.x * sx, my + e.y * sy), rr, mc)
	if mapAdv:
		var gc := _rgba(74, 222, 128, .62)
		for g in G.gems:
			_fcirc(ci, Vector2(mx + g.x * sx, my + g.y * sy), 2.1 if g.get("kind", "") == "boss" else .85, gc)
	_fcirc(ci, Vector2(mx + player.x * sx, my + player.y * sy), 2.8, _rgba(165, 243, 252, 1))
	_text(ci, "» FLOW: 移動加速", mx, my - 17, 8, _rgba(103, 232, 249, .72), 0)
	_text(ci, "◫ CHARGE: ダッシュ回復", mx + 72, my - 17, 8, _rgba(216, 180, 254, .72), 0)
	_text(ci, "∞ LINK: コンボ延長", mx, my - 7, 8, _rgba(253, 230, 138, .72), 0)
	if mapEsp:
		_text(ci, "ESP: OMNISCIENCE" if mapAdv else "ESP: ACTIVE", mx + mw, my - 7, 8,
			_rgba(253, 230, 138, .95) if mapAdv else _rgba(216, 180, 254, .88), 2)

	# damage flash (world space fill == camera rect)
	if G.flash > 0.0:
		ci.draw_rect(Rect2(-8, -8, cw + 16, ch + 16), _rgba(244, 63, 94, G.flash * .7))

	# vignette (camera fixed): radial 220 -> 900, alpha 0 -> .42
	var vc := Vector2(cw / 2.0, ch / 2.0)
	var r0 := 220.0
	var bandw := 62.0
	var rr2: float = r0
	while rr2 < 940.0:
		var tv: float = U.clamp((rr2 + bandw / 2.0 - 220.0) / 680.0, 0, 1)
		ci.draw_arc(vc, rr2 + bandw / 2.0, 0.0, TAU, 64, Color(0, 0, 0, .42 * tv), bandw + 1.0)
		rr2 += bandw
	_base = Transform2D.IDENTITY
	_xf(ci)
