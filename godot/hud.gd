extends Control
## HUD, menus and touch controls. Drawn directly (no Control node tree).

@onready var g: Node2D = get_parent().get_parent()

var move_vec := Vector2.ZERO
var aim_vec := Vector2.ZERO
var dash_pressed := false

var _move_id := -1
var _aim_id := -1
var _move_origin := Vector2.ZERO
var _aim_origin := Vector2.ZERO
var _move_pos := Vector2.ZERO
var _aim_pos := Vector2.ZERO
const STICK_R := 90.0

var font: Font

func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Noto Sans CJK JP", "Noto Sans JP", "Hiragino Sans", "Yu Gothic UI", "Meiryo", "WenQuanYi Zen Hei", "sans-serif"])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font = sf

func dash_rect() -> Rect2:
	return Rect2(size.x - 190, size.y - 200, 130, 130)

func card_rect(i: int) -> Rect2:
	var w := minf(360.0, (size.x - 120.0) / 3.0)
	var h := 300.0
	var gap := 28.0
	var x0 := (size.x - (w * 3 + gap * 2)) / 2.0
	return Rect2(x0 + i * (w + gap), size.y / 2.0 - h / 2.0 + 20, w, h)

func _input(e: InputEvent) -> void:
	if g.state == g.State.LEVELUP:
		var pos := Vector2.ZERO
		var tap := false
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pos = e.position; tap = true
		elif e is InputEventScreenTouch and e.pressed:
			pos = e.position; tap = true
		if tap:
			for i in g.choices.size():
				if card_rect(i).has_point(pos):
					g.pick(i); get_viewport().set_input_as_handled(); return
		return
	if g.state != g.State.PLAY:
		move_vec = Vector2.ZERO; aim_vec = Vector2.ZERO; _move_id = -1; _aim_id = -1
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			if dash_rect().grow(20).has_point(e.position):
				dash_pressed = true
			elif e.position.x < size.x * 0.5 and _move_id == -1:
				_move_id = e.index; _move_origin = e.position; _move_pos = e.position
			elif e.position.x >= size.x * 0.5 and _aim_id == -1:
				_aim_id = e.index; _aim_origin = e.position; _aim_pos = e.position
		else:
			if e.index == _move_id:
				_move_id = -1; move_vec = Vector2.ZERO
			elif e.index == _aim_id:
				_aim_id = -1; aim_vec = Vector2.ZERO
	elif e is InputEventScreenDrag:
		if e.index == _move_id:
			_move_pos = e.position
			move_vec = ((_move_pos - _move_origin) / STICK_R).limit_length(1.0)
			if move_vec.length() < 0.12: move_vec = Vector2.ZERO
		elif e.index == _aim_id:
			_aim_pos = e.position
			aim_vec = ((_aim_pos - _aim_origin) / STICK_R).limit_length(1.0)
			if aim_vec.length() < 0.2: aim_vec = Vector2.ZERO

# ------------------------------------------------------------------ draw
const CYAN := Color(0.35, 1.6, 1.9)
const MAG := Color(1.8, 0.4, 1.4)
const INK := Color(0.02, 0.03, 0.06, 0.82)

func txt(s: String, pos: Vector2, sz: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	if align == HORIZONTAL_ALIGNMENT_CENTER and w > 0.0:
		pos.x -= w / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT and w > 0.0:
		pos.x -= w
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT if w < 0.0 else align, w, sz, col)

func panel(r: Rect2, border: Color, fill := INK) -> void:
	draw_rect(r, fill)
	draw_rect(r, border, false, 2.0)
	# corner notch accents
	var n := 14.0
	draw_line(r.position, r.position + Vector2(n, 0), border * 1.4, 4.0)
	draw_line(r.end, r.end - Vector2(n, 0), border * 1.4, 4.0)

func _draw() -> void:
	match g.state:
		g.State.TITLE: draw_title()
		g.State.PLAY: draw_hud()
		g.State.LEVELUP:
			draw_hud(); draw_levelup()
		g.State.DEAD:
			draw_hud(); draw_dead()

func draw_hud() -> void:
	var p: Dictionary = g.p
	var m := 28.0
	# HP
	var hw := 340.0
	panel(Rect2(m, m, hw, 54), CYAN * 0.6)
	txt("HP", Vector2(m + 14, m + 22), 14, Color(0.6, 0.85, 1.0))
	txt("%d / %d" % [ceili(p.hp), int(p.max_hp)], Vector2(m + hw - 14, m + 22), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 120)
	var f: float = p.hp / p.max_hp
	draw_rect(Rect2(m + 14, m + 32, hw - 28, 10), Color(0.1, 0.15, 0.25))
	draw_rect(Rect2(m + 14, m + 32, (hw - 28) * f, 10), Color(0.3, 1.8, 0.9) if f > 0.35 else Color(2.0, 0.3, 0.4))
	# wave + score (top right)
	var rw := 260.0
	panel(Rect2(size.x - rw - m, m, rw, 74), MAG * 0.6)
	txt("WAVE %02d" % g.wave, Vector2(size.x - m - 16, m + 30), 26, Color(1.0, 0.8, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, rw - 32)
	txt("SCORE %d   KILL %d" % [g.score, g.kills], Vector2(size.x - m - 16, m + 56), 14, Color(0.7, 0.75, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, rw - 32)
	# XP (top center)
	var xw := minf(460.0, size.x - 760.0)
	var xx := (size.x - xw) / 2.0
	draw_rect(Rect2(xx, m + 4, xw, 8), Color(0.08, 0.1, 0.2, 0.9))
	draw_rect(Rect2(xx, m + 4, xw * float(p.xp) / float(p.xp_need), 8), Color(1.2, 0.6, 2.0))
	txt("Lv.%d" % p.lvl, Vector2(xx + xw / 2.0, m + 36), 16, Color(0.85, 0.75, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 100)
	# dash button
	var dr := dash_rect()
	var c := dr.get_center()
	var ready: bool = p.dash_t <= 0.0
	draw_circle(c, 62.0, Color(0.02, 0.05, 0.1, 0.7))
	draw_arc(c, 62.0, 0, TAU, 48, CYAN * (1.0 if ready else 0.35), 3.0)
	if not ready:
		draw_arc(c, 54.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - p.dash_t / p.dash_cd), 48, MAG, 5.0)
	txt("DASH", c + Vector2(0, 8), 20, Color.WHITE if ready else Color(0.5, 0.55, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 80)
	if not g.touch_mode:
		txt("SPACE", c + Vector2(0, 30), 11, Color(0.6, 0.7, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 80)
	# touch sticks
	if _move_id != -1:
		draw_stick(_move_origin, _move_pos, CYAN)
	if _aim_id != -1:
		draw_stick(_aim_origin, _aim_pos, MAG)
	if g.touch_mode and _move_id == -1 and _aim_id == -1:
		txt("左: 移動  /  右: 照準(自動照準あり)", Vector2(size.x / 2.0, size.y - 34), 15, Color(0.55, 0.65, 0.85, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 440)

func draw_stick(o: Vector2, pos: Vector2, col: Color) -> void:
	draw_arc(o, STICK_R, 0, TAU, 40, col * Color(1, 1, 1, 0.5), 3.0)
	var k := o + (pos - o).limit_length(STICK_R)
	draw_circle(k, 34.0, col * Color(1, 1, 1, 0.55))

func draw_title() -> void:
	var cx := size.x / 2.0
	var cy := size.y / 2.0
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.03, 0.55))
	var pulse := 0.7 + 0.3 * sin(g.t * 2.5)
	txt("NEON", Vector2(cx, cy - 90), 104, Color(1.6, 1.7, 2.0), HORIZONTAL_ALIGNMENT_CENTER, 900)
	txt("FRACTURE", Vector2(cx, cy + 20), 104, Color(0.3, 1.4, 2.0), HORIZONTAL_ALIGNMENT_CENTER, 900)
	txt("有限ネオンフィールドを生き残れ — Godot prototype", Vector2(cx, cy + 72), 20, Color(0.65, 0.72, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 900)
	var lbl := "TAP TO START" if g.touch_mode else "PRESS SPACE / CLICK"
	txt(lbl, Vector2(cx, cy + 150), 28, Color(1.6, 1.2, 0.5) * pulse, HORIZONTAL_ALIGNMENT_CENTER, 900)
	if g.best_wave > 0:
		txt("BEST WAVE %d" % g.best_wave, Vector2(cx, cy + 190), 16, Color(0.7, 0.8, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 900)
	txt("WASD 移動 / マウス照準(自動連射) / SPACE ダッシュ", Vector2(cx, size.y - 40), 15, Color(0.5, 0.6, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 900)

func draw_levelup() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.03, 0.72))
	txt("LEVEL UP", Vector2(size.x / 2.0, size.y / 2.0 - 190), 48, Color(1.4, 0.8, 2.0), HORIZONTAL_ALIGNMENT_CENTER, 600)
	txt("強化を1つ選択", Vector2(size.x / 2.0, size.y / 2.0 - 152), 18, Color(0.7, 0.75, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 600)
	var mp := get_viewport().get_mouse_position()
	for i in g.choices.size():
		var r := card_rect(i)
		var u: Dictionary = g.choices[i]
		var hot: bool = r.has_point(mp) and not g.touch_mode
		panel(r, (MAG if hot else CYAN) * 0.9, Color(0.05, 0.06, 0.14, 0.95) if not hot else Color(0.12, 0.08, 0.2, 0.95))
		txt(u.icon, Vector2(r.position.x + r.size.x / 2.0, r.position.y + 100), 72, MAG if hot else CYAN, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		txt(u.name, Vector2(r.position.x + r.size.x / 2.0, r.position.y + 170), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		txt(u.desc, Vector2(r.position.x + r.size.x / 2.0, r.position.y + 210), 18, Color(0.7, 0.8, 1.0), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		if not g.touch_mode:
			txt("[%d]" % (i + 1), Vector2(r.position.x + r.size.x / 2.0, r.position.y + 270), 16, Color(0.5, 0.6, 0.8), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func draw_dead() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.0, 0.02, 0.7))
	var cx := size.x / 2.0
	var cy := size.y / 2.0
	txt("SIGNAL LOST", Vector2(cx, cy - 60), 72, Color(2.0, 0.35, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 900)
	txt("WAVE %d   /   SCORE %d   /   KILL %d" % [g.wave, g.score, g.kills], Vector2(cx, cy), 24, Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 900)
	var pulse := 0.7 + 0.3 * sin(g.t * 2.5)
	txt("TAP TO RETRY" if g.touch_mode else "PRESS SPACE / CLICK", Vector2(cx, cy + 80), 26, Color(1.6, 1.2, 0.5) * pulse, HORIZONTAL_ALIGNMENT_CENTER, 900)
