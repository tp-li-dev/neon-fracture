extends Node2D
## NEON FRACTURE - Godot prototype (core combat loop).
## All entities are plain data drawn in one _draw() call: no per-entity nodes,
## so it stays light on mobile. Stats are taken from the original HTML game.

const WORLD := Vector2(4800, 2700)
const VIEW := Vector2(1600, 900)

enum State { TITLE, PLAY, LEVELUP, DEAD }

# name, radius, hp, speed, damage, xp, hue
const ENEMY := {
	"chaser":   {"n": "追跡機", "r": 13.0, "hp": 34.0,  "spd": 82.0,  "dmg": 15.0, "xp": 9,  "hue": 350.0},
	"swift":    {"n": "軽量機", "r": 9.0,  "hp": 22.0,  "spd": 132.0, "dmg": 11.0, "xp": 11, "hue": 185.0},
	"tank":     {"n": "重装機", "r": 20.0, "hp": 112.0, "spd": 48.0,  "dmg": 24.0, "xp": 20, "hue": 280.0},
	"shooter":  {"n": "射撃機", "r": 14.0, "hp": 55.0,  "spd": 62.0,  "dmg": 15.0, "xp": 18, "hue": 42.0},
	"splitter": {"n": "分裂機", "r": 16.0, "hp": 72.0,  "spd": 68.0,  "dmg": 16.0, "xp": 22, "hue": 135.0},
	"charger":  {"n": "突進機", "r": 12.0, "hp": 52.0,  "spd": 70.0,  "dmg": 23.0, "xp": 20, "hue": 12.0},
}

const UPGRADES := [
	{"id": "dmg",   "icon": "◆", "name": "火力増幅",     "desc": "ダメージ +25%"},
	{"id": "rate",  "icon": "≫", "name": "高速連射",     "desc": "連射速度 +20%"},
	{"id": "multi", "icon": "⋔", "name": "マルチショット", "desc": "弾数 +1"},
	{"id": "pierce","icon": "⟫", "name": "貫通弾",       "desc": "貫通 +1"},
	{"id": "speed", "icon": "➤", "name": "加速機構",     "desc": "移動速度 +10%"},
	{"id": "hp",    "icon": "✚", "name": "装甲強化",     "desc": "最大HP +25 / 全回復"},
	{"id": "dash",  "icon": "◫", "name": "クロノス",     "desc": "ダッシュCD -20%"},
	{"id": "magnet","icon": "◎", "name": "マグネット",   "desc": "回収範囲 +40%"},
]

var state := State.TITLE
var t := 0.0
var wave := 1
var wave_t := 0.0
var spawn_t := 0.0
var kills := 0
var score := 0
var shake := 0.0
var best_wave := 0
var touch_mode := false

# player
var p := {}
var enemies: Array = []
var bullets: Array = []
var ebullets: Array = []
var orbs: Array = []
var parts: Array = []
var rings: Array = []
var choices: Array = []

# input
var move_in := Vector2.ZERO
var aim_in := Vector2.ZERO      # touch right stick (0 = none)
var aim_dir := Vector2.RIGHT
var firing := false
var dash_req := false

@onready var cam: Camera2D = $Camera
@onready var hud: Control = $UI/Hud

func _ready() -> void:
	touch_mode = DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")
	reset_run()
	state = State.TITLE
	if OS.get_environment("NF_SHOT") != "":
		_demo()

# Dev-only: NF_SHOT=<dir> auto-plays and saves screenshots (used for CI/preview).
func _demo() -> void:
	var dir := OS.get_environment("NF_SHOT")
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/1_title.png")
	start_game()
	p.dmg = 40.0; p.rate = 7.0; p.multi = 3
	for k in 4:
		await get_tree().create_timer(5.0).timeout
		wave += 2
		hud.move_vec = Vector2.from_angle(k * 1.7)
		await get_tree().create_timer(2.5).timeout
		get_viewport().get_texture().get_image().save_png(dir + "/2_play%d.png" % k)
	open_levelup()
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/3_levelup.png")
	get_tree().quit()

func reset_run() -> void:
	p = {"pos": WORLD / 2, "vel": Vector2.ZERO, "hp": 100.0, "max_hp": 100.0, "speed": 275.0,
		"dmg": 14.0, "rate": 4.0, "multi": 1, "pierce": 0, "dash_cd": 2.1, "dash_t": 0.0, "dash_left": 0.0,
		"dash_dir": Vector2.RIGHT, "inv": 0.0, "shoot_t": 0.0, "magnet": 140.0, "xp": 0, "lvl": 1, "xp_need": 30}
	enemies.clear(); bullets.clear(); ebullets.clear(); orbs.clear(); parts.clear(); rings.clear()
	wave = 1; wave_t = 0.0; spawn_t = 0.0; kills = 0; score = 0; t = 0.0
	cam.position = p.pos

func start_game() -> void:
	reset_run()
	state = State.PLAY

# ------------------------------------------------------------------ input
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		touch_mode = true
	if state == State.TITLE or state == State.DEAD:
		if (e is InputEventKey and e.pressed and not e.echo and (e.keycode == KEY_SPACE or e.keycode == KEY_ENTER)) \
		or (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			start_game()
		return
	if state == State.LEVELUP:
		if e is InputEventKey and e.pressed and e.keycode >= KEY_1 and e.keycode <= KEY_3:
			pick(e.keycode - KEY_1)
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE:
		dash_req = true

func read_input() -> void:
	var v := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if hud.move_vec != Vector2.ZERO:
		v = hud.move_vec
	move_in = v.limit_length(1.0)
	if hud.aim_vec != Vector2.ZERO:
		aim_dir = hud.aim_vec.normalized(); firing = true
	elif touch_mode:
		var n = nearest_enemy()
		firing = n != null
		if n != null:
			aim_dir = (n.pos - p.pos).normalized()
	else:
		var m := get_global_mouse_position()
		aim_dir = (m - p.pos).normalized() if m.distance_to(p.pos) > 1.0 else aim_dir
		firing = true  # auto-fire keeps the PC and touch feel identical
	if hud.dash_pressed:
		dash_req = true; hud.dash_pressed = false

func nearest_enemy():
	var best = null; var bd := 1e12
	for e in enemies:
		var d: float = e.pos.distance_squared_to(p.pos)
		if d < bd and d < 900.0 * 900.0:
			bd = d; best = e
	return best

# ------------------------------------------------------------------ sim
func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	t += dt
	if state == State.PLAY:
		read_input()
		sim(dt)
	shake = maxf(0.0, shake - dt * 30.0)
	update_camera(dt)
	queue_redraw()
	hud.queue_redraw()

func update_camera(dt: float) -> void:
	var target: Vector2 = p.pos
	var half := VIEW / 2.0
	cam.position = cam.position.lerp(target, 1.0 - exp(-dt * 8.0))
	cam.position = cam.position.clamp(half, WORLD - half)
	cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake

func sim(dt: float) -> void:
	# --- player
	var pp: Vector2 = p.pos
	if dash_req and p.dash_t <= 0.0:
		p.dash_t = p.dash_cd; p.dash_left = 0.18; p.inv = 0.3
		p.dash_dir = move_in.normalized() if move_in.length() > 0.1 else aim_dir
		burst(pp, 14, 185.0, 220.0)
	dash_req = false
	p.dash_t = maxf(0.0, p.dash_t - dt)
	p.inv = maxf(0.0, p.inv - dt)
	if p.dash_left > 0.0:
		p.dash_left -= dt
		p.vel = p.dash_dir * 950.0
		if parts.size() < 500:
			parts.append({"pos": pp, "vel": Vector2.ZERO, "life": 0.25, "max": 0.25, "h": 185.0, "s": 9.0})
	else:
		p.vel = p.vel.lerp(move_in * p.speed, 1.0 - exp(-dt * 14.0))
	pp += p.vel * dt
	pp = pp.clamp(Vector2(30, 30), WORLD - Vector2(30, 30))
	p.pos = pp
	# --- fire
	p.shoot_t -= dt
	if firing and p.shoot_t <= 0.0:
		p.shoot_t += 1.0 / p.rate
		fire()
	# --- waves
	wave_t += dt
	if wave_t >= 20.0:
		wave_t = 0.0; wave += 1
		rings.append({"pos": pp, "r": 10.0, "life": 0.8, "max": 0.8, "h": 50.0, "grow": 1800.0})
	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t = maxf(0.18, 0.9 - wave * 0.04)
		var n := 1 + int(wave / 3)
		for i in n:
			spawn_enemy(pick_type())
	# --- bullets
	var i := bullets.size() - 1
	while i >= 0:
		var b = bullets[i]
		b.pos += b.vel * dt; b.life -= dt
		var dead: bool = b.life <= 0.0 or b.pos.x < 0 or b.pos.y < 0 or b.pos.x > WORLD.x or b.pos.y > WORLD.y
		if not dead:
			for e in enemies:
				if e.hp <= 0.0 or b.hit.has(e.id):
					continue
				var rr: float = e.r + 5.0
				if e.pos.distance_squared_to(b.pos) < rr * rr:
					hit_enemy(e, b.dmg)
					b.hit.append(e.id)
					if b.pierce <= 0:
						dead = true; break
					b.pierce -= 1
		if dead:
			bullets.remove_at(i)
		i -= 1
	# --- enemies
	var hp_scale := 1.0 + (wave - 1) * 0.14
	i = enemies.size() - 1
	while i >= 0:
		var e = enemies[i]
		if e.hp <= 0.0:
			enemies.remove_at(i); i -= 1; continue
		e.flash = maxf(0.0, e.flash - dt)
		var to: Vector2 = pp - e.pos
		var d := to.length()
		var dir := to / maxf(d, 0.001)
		var spd: float = e.spd
		match e.type:
			"shooter":
				if d < 380.0: spd = -e.spd * 0.6
				elif d < 560.0: spd = 0.0
				e.cd -= dt
				if e.cd <= 0.0 and d < 900.0:
					e.cd = 2.2
					ebullets.append({"pos": e.pos, "vel": dir * 320.0, "life": 4.0, "dmg": e.dmg})
			"charger":
				e.cd -= dt
				if e.state == 0 and e.cd <= 0.0 and d < 600.0:
					e.state = 1; e.cd = 0.55; e.cdir = dir        # wind-up
				elif e.state == 1:
					spd = 0.0
					if e.cd <= 0.0:
						e.state = 2; e.cd = 0.5
				elif e.state == 2:
					spd = 640.0; dir = e.cdir
					if e.cd <= 0.0:
						e.state = 0; e.cd = 2.5
		e.pos += dir * spd * dt
		# separation (cheap)
		for k in range(maxi(0, i - 6), i):
			var o = enemies[k]
			var dd: Vector2 = e.pos - o.pos
			var m: float = e.r + o.r
			var l2 := dd.length_squared()
			if l2 < m * m and l2 > 0.01:
				var push: Vector2 = dd / sqrt(l2) * (m - sqrt(l2)) * 0.5
				e.pos += push; o.pos -= push
		# contact
		var cr: float = e.r + 14.0
		if d < cr and p.inv <= 0.0:
			damage_player(e.dmg * (1.0 + (wave - 1) * 0.05))
		i -= 1
	# enemy bullets
	i = ebullets.size() - 1
	while i >= 0:
		var b = ebullets[i]
		b.pos += b.vel * dt; b.life -= dt
		if b.life <= 0.0:
			ebullets.remove_at(i)
		elif b.pos.distance_squared_to(pp) < 22.0 * 22.0 and p.inv <= 0.0:
			damage_player(b.dmg); ebullets.remove_at(i)
		i -= 1
	# orbs
	i = orbs.size() - 1
	while i >= 0:
		var o = orbs[i]
		var d: float = o.pos.distance_to(pp)
		if d < p.magnet or o.pull:
			o.pull = true
			o.pos = o.pos.move_toward(pp, (400.0 + 900.0 * (1.0 - clampf(d / 600.0, 0, 1))) * dt)
		if d < 20.0:
			p.xp += o.v; score += o.v
			orbs.remove_at(i)
			if p.xp >= p.xp_need:
				p.xp -= p.xp_need; p.lvl += 1
				p.xp_need = int(30 + p.lvl * 14)
				open_levelup()
		i -= 1
	# particles / rings
	i = parts.size() - 1
	while i >= 0:
		var q = parts[i]
		q.life -= dt; q.pos += q.vel * dt; q.vel *= 0.96
		if q.life <= 0.0: parts.remove_at(i)
		i -= 1
	i = rings.size() - 1
	while i >= 0:
		var r = rings[i]
		r.life -= dt; r.r += r.grow * dt
		if r.life <= 0.0: rings.remove_at(i)
		i -= 1

var _eid := 0
func pick_type() -> String:
	var pool: Array = ["chaser"]
	if wave >= 2: pool += ["swift", "chaser"]
	if wave >= 3: pool.append("tank")
	if wave >= 4: pool.append("shooter")
	if wave >= 5: pool.append("charger")
	if wave >= 6: pool.append("splitter")
	return pool[randi() % pool.size()]

func spawn_enemy(type: String, at := Vector2(-1, -1)) -> void:
	if enemies.size() > 220: return
	var d: Dictionary = ENEMY[type]
	var pos := at
	if at.x < 0:
		var a := randf() * TAU
		pos = p.pos + Vector2.from_angle(a) * randf_range(950.0, 1150.0)
		pos = pos.clamp(Vector2(40, 40), WORLD - Vector2(40, 40))
	_eid += 1
	var hp: float = d.hp * (1.0 + (wave - 1) * 0.14)
	enemies.append({"id": _eid, "type": type, "pos": pos, "r": d.r, "hp": hp, "max": hp, "spd": d.spd,
		"dmg": d.dmg, "xp": d.xp, "hue": d.hue, "flash": 0.0, "cd": randf_range(0.5, 2.0), "state": 0, "cdir": Vector2.ZERO})

func fire() -> void:
	var n: int = p.multi
	var step := 0.11
	for k in n:
		var a := aim_dir.angle() + (k - (n - 1) / 2.0) * step
		bullets.append({"pos": p.pos + Vector2.from_angle(a) * 20.0, "vel": Vector2.from_angle(a) * 1000.0,
			"life": 0.9, "dmg": p.dmg, "pierce": p.pierce, "hit": []})
	if parts.size() < 500:
		parts.append({"pos": p.pos + aim_dir * 22.0, "vel": aim_dir * 90.0, "life": 0.1, "max": 0.1, "h": 185.0, "s": 5.0})

func hit_enemy(e: Dictionary, dmg: float) -> void:
	e.hp -= dmg; e.flash = 0.07
	burst(e.pos, 3, e.hue, 140.0)
	if e.hp <= 0.0:
		kills += 1; score += e.xp * 3
		burst(e.pos, 14, e.hue, 260.0)
		rings.append({"pos": e.pos, "r": e.r, "life": 0.3, "max": 0.3, "h": e.hue, "grow": 260.0})
		orbs.append({"pos": e.pos, "v": e.xp, "pull": false})
		shake = minf(shake + 2.0, 8.0)
		if e.type == "splitter":
			for s in 2:
				spawn_enemy("swift", e.pos + Vector2.from_angle(randf() * TAU) * 24.0)

func damage_player(d: float) -> void:
	p.hp -= d; p.inv = 0.5; shake = 12.0
	burst(p.pos, 18, 350.0, 300.0)
	if p.hp <= 0.0:
		p.hp = 0.0; state = State.DEAD
		best_wave = maxi(best_wave, wave)
		burst(p.pos, 60, 350.0, 500.0)

func burst(pos: Vector2, n: int, hue: float, spd: float) -> void:
	for k in n:
		if parts.size() > 600: return
		var a := randf() * TAU
		var l := randf_range(0.2, 0.5)
		parts.append({"pos": pos, "vel": Vector2.from_angle(a) * randf_range(0.3, 1.0) * spd, "life": l, "max": l, "h": hue, "s": randf_range(2.0, 4.0)})

# ------------------------------------------------------------------ level up
func open_levelup() -> void:
	var pool := UPGRADES.duplicate()
	pool.shuffle()
	choices = pool.slice(0, 3)
	state = State.LEVELUP

func pick(i: int) -> void:
	if state != State.LEVELUP or i < 0 or i >= choices.size(): return
	match choices[i].id:
		"dmg": p.dmg *= 1.25
		"rate": p.rate *= 1.2
		"multi": p.multi += 1
		"pierce": p.pierce += 1
		"speed": p.speed *= 1.1
		"hp": p.max_hp += 25.0; p.hp = p.max_hp
		"dash": p.dash_cd *= 0.8
		"magnet": p.magnet *= 1.4
	rings.append({"pos": p.pos, "r": 10.0, "life": 0.5, "max": 0.5, "h": 280.0, "grow": 900.0})
	state = State.PLAY

# ------------------------------------------------------------------ drawing
func neon(h: float, v := 1.0, a := 1.0) -> Color:
	return Color.from_hsv(fposmod(h, 360.0) / 360.0, 0.62, v, a)

func gline(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, Color(col.r, col.g, col.b, col.a * 0.16), w * 3.2)
	draw_line(a, b, col, w)

func gpoly(pts: PackedVector2Array, col: Color, w: float) -> void:
	draw_polyline(pts, Color(col.r, col.g, col.b, col.a * 0.16), w * 3.2)
	draw_polyline(pts, col, w)

func gdot(pos: Vector2, r: float, col: Color) -> void:
	draw_circle(pos, r * 2.4, Color(col.r, col.g, col.b, col.a * 0.14))
	draw_circle(pos, r, col)

func _draw() -> void:
	var c := cam.position
	var tl := c - VIEW / 2.0 - Vector2(40, 40)
	var br := c + VIEW / 2.0 + Vector2(40, 40)
	# grid
	var gs := 100.0
	var gx := floorf(tl.x / gs) * gs
	while gx < br.x:
		var edge := gx <= 0.0 or gx >= WORLD.x
		draw_line(Vector2(gx, tl.y), Vector2(gx, br.y), Color(0.16, 0.4, 0.65, 0.22 if not edge else 0.0), 1.0)
		gx += gs
	var gy := floorf(tl.y / gs) * gs
	while gy < br.y:
		draw_line(Vector2(tl.x, gy), Vector2(br.x, gy), Color(0.16, 0.4, 0.65, 0.22), 1.0)
		gy += gs
	# arena border
	gpoly(PackedVector2Array([Vector2.ZERO, Vector2(WORLD.x, 0), WORLD, Vector2(0, WORLD.y), Vector2.ZERO]), neon(185, 1.6), 4.0)
	draw_rect(Rect2(Vector2(-60, -60), WORLD + Vector2(120, 120)), Color(0, 0, 0, 0.0), false, 1.0)
	# orbs
	for o in orbs:
		var s := 5.0 + sin(t * 8.0 + o.pos.x) * 1.2
		gdot(o.pos, s, neon(160, 1.5))
	# enemies
	for e in enemies:
		if e.pos.x < tl.x - 60 or e.pos.x > br.x + 60 or e.pos.y < tl.y - 60 or e.pos.y > br.y + 60:
			continue
		draw_enemy(e)
	# bullets
	for b in bullets:
		gline(b.pos, b.pos - b.vel.normalized() * 24.0, neon(185, 1.8), 4.0)
	for b in ebullets:
		gdot(b.pos, 7.0, neon(42, 1.8))
	# player
	if state != State.DEAD:
		draw_player()
	# fx
	for q in parts:
		var a: float = clampf(q.life / q.get("max", 0.4), 0, 1)
		gdot(q.pos, q.s * a + 0.5, neon(q.h, 1.7, a))
	for r in rings:
		var a: float = clampf(r.life / r.max, 0, 1)
		draw_arc(r.pos, r.r, 0, TAU, 40, neon(r.h, 1.6, a), 3.0)

func draw_enemy(e: Dictionary) -> void:
	var col := neon(e.hue, 1.5)
	if e.flash > 0.0: col = Color(2, 2, 2)
	var pos: Vector2 = e.pos
	var r: float = e.r
	var ang: float = (p.pos - pos).angle()
	var sides := 3
	match e.type:
		"chaser": sides = 3
		"swift": sides = 3
		"tank": sides = 6
		"shooter": sides = 4
		"splitter": sides = 5
		"charger": sides = 4
	var pts := PackedVector2Array()
	for k in sides + 1:
		var a: float = ang + TAU * k / sides + (PI / sides if e.type == "shooter" else 0.0)
		pts.append(pos + Vector2.from_angle(a) * r * (1.25 if e.type == "swift" and k % sides == 0 else 1.0))
	draw_colored_polygon(pts.slice(0, sides), Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.9))
	gpoly(pts, col, 3.0)
	if e.type == "charger" and e.state == 1:
		draw_line(pos, pos + e.cdir * 500.0, Color(2, 0.6, 0.3, 0.5), 2.0)
	if e.hp < e.max:
		var w := r * 2.0
		draw_rect(Rect2(pos + Vector2(-r, -r - 9), Vector2(w, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(pos + Vector2(-r, -r - 9), Vector2(w * e.hp / e.max, 3)), col)

func draw_player() -> void:
	var pos: Vector2 = p.pos
	var a := aim_dir.angle()
	var blink: bool = p.inv > 0.0 and int(t * 30.0) % 2 == 0
	var col := neon(185, 1.9) if not blink else Color(2, 2, 2)
	var pts := PackedVector2Array([pos + Vector2.from_angle(a) * 26.0, pos + Vector2.from_angle(a + 2.5) * 20.0,
		pos + Vector2.from_angle(a + PI) * 8.0, pos + Vector2.from_angle(a - 2.5) * 20.0, pos + Vector2.from_angle(a) * 26.0])
	draw_colored_polygon(pts.slice(0, 4), Color(0.05, 0.2, 0.3, 0.9))
	gpoly(pts, col, 3.0)
	draw_arc(pos, 26.0, a - 0.5, a + 0.5, 8, neon(185, 1.0, 0.5), 2.0)
