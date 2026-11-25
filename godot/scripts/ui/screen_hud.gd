extends NFScreen
## Gameplay HUD (persistent, non-modal, mouse-transparent except buttons).
## Original: index.html #hud (4546), #xpHud, #combatDock (5173), syncCombatHud 7862, updateUI 9122,
## setupSkillHoldButtons 10328, layoutTouchZones 5848, drone controls 10274-10312.
##
## Public helpers for other screens (get the instance via UI.screens["hud"]):
##   build_drone_panel() -> Control        drone ON/OFF/targets/priority/output settings (pause screen)
##   build_run_status_panel() -> Control   CURRENT BUILD panel (pause screen); refreshed by hook renderRunStatus
##   auto_cards_text(long: bool) -> String  "自動取得：ON" (long) / "自動 ON" (short)
## Dev: NF_HUD_MOCK=kb|touch with NF_SCREEN=hud starts a run with demo state for screenshots.

const ROSE_C := Color("#f43f5e")
const FUCH_C := Color("#d946ef")
const BLUE_C := Color("#3b82f6")
const VIO_C := Color("#8b5cf6")
const CYAN_L := Color("#67e8f9")

# ============================================================== widgets
class HudBar extends Control:
	var value := 0.0:
		set(v):
			value = clampf(v, 0.0, 1.0)
	var shown := 0.0
	var stops := PackedColorArray([Kit.ROSE, Kit.FUCHSIA, Kit.CYAN])
	var glow := false

	func _init(h: int = 10) -> void:
		custom_minimum_size.y = h
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		if absf(shown - value) > 0.0005:
			shown = lerpf(shown, value, minf(1.0, dt * 12.0))
			if absf(shown - value) < 0.0008: shown = value
			queue_redraw()

	func _sample(t: float) -> Color:
		var n := stops.size() - 1
		var x := clampf(t, 0.0, 1.0) * n
		var i := mini(int(x), n - 1)
		return stops[i].lerp(stops[i + 1], x - i)

	func _draw() -> void:
		var h := size.y
		var rad := int(h * 0.5)
		draw_style_box(Kit.box(Color(0.01, 0.03, 0.07, 0.85), Color(1, 1, 1, 0.07), 1, rad), Rect2(Vector2.ZERO, size))
		if shown < 0.002: return
		var fw := maxf(h, (size.x - 2.0) * shown)
		var x0 := 1.0
		var y0 := 1.0
		var hh := h - 2.0
		var seg := 28
		var wsh := minf(fw, size.x - 2.0)
		if glow:
			draw_style_box(Kit.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, rad, Kit.with_a(_sample(0.85), 0.35), 7), Rect2(x0, y0, wsh, hh))
		# rounded left cap + gradient body
		for i in seg:
			var a := float(i) / seg
			var b := float(i + 1) / seg
			var c0 := _sample(a)
			var c1 := _sample(b)
			var xa := x0 + wsh * a
			var xb := x0 + wsh * b
			draw_polygon(PackedVector2Array([Vector2(xa, y0), Vector2(xb, y0), Vector2(xb, y0 + hh), Vector2(xa, y0 + hh)]),
				PackedColorArray([c0, c1, c1, c0]))
		# round the ends by overdrawing track-coloured corners
		draw_rect(Rect2(x0 + 2, y0 + 1, maxf(0.0, wsh - 4), maxf(1.0, hh * 0.28)), Color(1, 1, 1, 0.20))
		draw_line(Vector2(x0 + wsh, y0), Vector2(x0 + wsh, y0 + hh), Color(1, 1, 1, 0.7), 1.5)


## Active-skill slot with press-and-hold (original setupSkillHoldButtons).
class SlotBtn extends Control:
	var idx := 0
	var title := "未取得"
	var sub := "ボス報酬"
	var rdy := 0.0          # 0..1 cooldown progress
	var has_slot := false
	var can_use := false
	var charging := false
	var held := false
	var key_text := "1"
	var touch_layout := false
	var _ptr := ""
	var _hover := false
	var _pulse := 0.0

	func _init(i: int) -> void:
		idx = i
		custom_minimum_size = Vector2(60, Kit.btn_h() + 12)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	func _process(dt: float) -> void:
		if charging:
			_pulse += dt * 7.0
			queue_redraw()

	func _release() -> void:
		if _ptr == "": return
		var t := _ptr
		_ptr = ""
		Inp.endSkillHold("ui:%d:%s" % [idx, t])
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if Game.state != "playing": return
		var down := false
		var up := false
		var tok := ""
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			tok = "mouse"; down = e.pressed; up = not e.pressed
		elif e is InputEventScreenTouch:
			tok = "t%d" % e.index; down = e.pressed; up = not e.pressed
		elif (e is InputEventMouseMotion or e is InputEventScreenDrag) and _ptr != "":
			var p: Vector2 = e.position
			if p.x < -18 or p.y < -18 or p.x > size.x + 18 or p.y > size.y + 18:
				_release()
			return
		else:
			return
		if down and _ptr == "":
			_ptr = tok
			Inp.beginSkillHold(idx, "ui:%d:%s" % [idx, tok])
			accept_event()
			queue_redraw()
		elif up and _ptr == tok:
			_release()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var accent: Color = Kit.CYAN
		if charging: accent = Kit.AMBER
		elif not has_slot: accent = Kit.SLATE
		elif not can_use: accent = Kit.MUTE
		var fill := Color(0.04, 0.07, 0.12, 0.88)
		var sb := Kit.box(fill, Kit.with_a(accent, 0.55 if has_slot else 0.20), 1, 8,
			Kit.with_a(accent, 0.22) if (can_use or charging) else Color(0, 0, 0, 0), 10 if (can_use or charging) else 0)
		draw_style_box(sb, r)
		if has_slot and not charging:
			var pw := (size.x - 2.0) * rdy
			if pw > 1.0:
				draw_rect(Rect2(1, size.y - 5, pw, 4), Kit.with_a(Kit.CYAN if can_use else Kit.SLATE, 0.85 if can_use else 0.5))
		if charging:
			var a := 0.12 + 0.12 * (0.5 + 0.5 * sin(_pulse))
			draw_style_box(Kit.box(Kit.with_a(Kit.AMBER, a), Kit.with_a(Kit.AMBER, 0.9), 2, 8), r)
		if held:
			var hb := Kit.box(Color(0, 0, 0, 0), CYAN_L, 2, 8, Kit.with_a(CYAN_L, 0.5), 8)
			hb.draw_center = false
			draw_style_box(hb, r.grow(-1))
		if has_focus():
			var fb := Kit.box(Color(0, 0, 0, 0), Color.WHITE, 2, 9)
			fb.draw_center = false
			draw_style_box(fb, r.grow(2))
		var f := Kit.font(true)
		var tc := Kit.TEXT if (has_slot and (can_use or charging)) else Kit.DIM
		var fs_t := Kit.fs(12)
		var fs_s := Kit.fs(11)
		var tx := 8.0
		if not touch_layout:
			var bs := float(Kit.fs(18))
			var br := Rect2(8, 8, bs, bs)
			draw_style_box(Kit.box(Kit.with_a(accent, 0.12), Kit.with_a(accent, 0.55), 1, 5), br)
			var ks := f.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.fs(11))
			draw_string(f, Vector2(br.position.x + (bs - ks.x) * 0.5, br.position.y + bs * 0.5 + ks.y * 0.33), key_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.fs(11), Kit.with_a(accent, 0.95))
			tx = 8.0 + bs + 6.0
		var avail := size.x - tx - 6.0
		if touch_layout:
			tx = 4.0
			avail = size.x - 8.0
		var ty := size.y * 0.42
		var ts := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, avail, fs_t)
		var ox := tx + (maxf(0.0, avail - ts.x) * 0.5 if touch_layout else 0.0)
		draw_string(f, Vector2(ox, ty), title, HORIZONTAL_ALIGNMENT_LEFT, avail, fs_t, tc)
		var ss := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, avail, fs_s)
		var ox2 := tx + (maxf(0.0, avail - ss.x) * 0.5 if touch_layout else 0.0)
		var sc := Kit.AMBER if charging else (Kit.EMERALD if (has_slot and can_use) else Kit.DIM)
		draw_string(f, Vector2(ox2, ty + fs_s + 4), sub, HORIZONTAL_ALIGNMENT_LEFT, avail, fs_s, sc)


## Dock command button with hotkey badge and optional count.
class DockBtn extends Kit.NeonButton:
	var label_text := ""
	var key_text := ""
	var count := -1
	var tone: Color = Kit.CYAN
	var lit := false
	var dim := false

	func _init(lbl: String, key: String = "") -> void:
		super._init("primary")
		label_text = lbl
		key_text = key
		text = ""
		custom_minimum_size.y = Kit.btn_h()
		focus_mode = Control.FOCUS_NONE
		set_tone(Kit.CYAN, false, false)

	func set_tone(c: Color, is_lit: bool, is_dim: bool) -> void:
		tone = c; lit = is_lit; dim = is_dim
		var fillc := Kit.with_a(c, 0.30 if lit else 0.07)
		var bd := Kit.with_a(c, 0.9 if lit else (0.22 if dim else 0.45))
		var n := Kit.box(fillc if not dim else Color(1, 1, 1, 0.03), bd, 1, 8)
		var h := Kit.box(Kit.with_a(c, 0.30), c, 1, 8)
		var p := Kit.box(Kit.with_a(c, 0.42), c.lightened(0.2), 1, 8)
		for s in [n, h, p]:
			s.content_margin_left = 8; s.content_margin_right = 8
		add_theme_stylebox_override("normal", n)
		add_theme_stylebox_override("hover", h)
		add_theme_stylebox_override("pressed", p)
		add_theme_stylebox_override("hover_pressed", p)
		queue_redraw()

	func _draw() -> void:
		super._draw()
		var f := Kit.font(true)
		var fsz := Kit.fs(12)
		var cc := Kit.TEXT if not dim else Kit.DIM
		if lit: cc = Color.WHITE
		var lw := f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		var bs := float(Kit.fs(18))
		var cs := ""
		var cw := 0.0
		if count >= 0:
			cs = str(count)
			cw = f.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.fs(13)).x
		var total := lw
		if key_text != "": total += bs + 6.0
		if cs != "": total += cw + 8.0
		var x := (size.x - total) * 0.5
		var cy := size.y * 0.5
		if key_text != "":
			var br := Rect2(x, cy - bs * 0.5, bs, bs)
			draw_style_box(Kit.box(Kit.with_a(tone, 0.12), Kit.with_a(tone, 0.55), 1, 5), br)
			var ks := f.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.fs(11))
			draw_string(f, Vector2(br.position.x + (bs - ks.x) * 0.5, cy + ks.y * 0.33), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.fs(11), Kit.with_a(tone, 0.95))
			x += bs + 6.0
		draw_string(f, Vector2(x, cy + fsz * 0.36), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, cc)
		x += lw + 8.0
		if cs != "":
			draw_string(f, Vector2(x, cy + Kit.fs(13) * 0.36), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.fs(13),
				Kit.EMERALD if lit else Kit.with_a(tone, 0.85))


class DashBtn extends Control:
	var pct := 1.0
	var status := "READY"
	signal pressed

	func _init() -> void:
		custom_minimum_size = Vector2(76, Kit.btn_h() + 12)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or e.is_action_pressed("ui_accept"):
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var rdy := pct >= 1.0
		var ac := Kit.FUCHSIA if rdy else Kit.VIOLET
		draw_style_box(Kit.box(Color(0.10, 0.07, 0.16, 0.9), Kit.with_a(ac, 0.7 if rdy else 0.35), 1, 8,
			Kit.with_a(ac, 0.25) if rdy else Color(0, 0, 0, 0), 10 if rdy else 0), r)
		if not rdy:
			draw_rect(Rect2(1, size.y - 5, (size.x - 2) * pct, 4), Kit.with_a(Kit.VIOLET, 0.8))
		if has_focus():
			var fb := Kit.box(Color(0, 0, 0, 0), Color.WHITE, 2, 9)
			fb.draw_center = false
			draw_style_box(fb, r.grow(2))
		var f := Kit.font(true)
		var a := f.get_string_size("DASH", HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.fs(13))
		draw_string(f, Vector2((size.x - a.x) * 0.5, size.y * 0.44), "DASH", HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.fs(13), Color("#f0d9ff") if rdy else Kit.DIM)
		var b := f.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.fs(11))
		draw_string(f, Vector2((size.x - b.x) * 0.5, size.y * 0.44 + Kit.fs(11) + 4), status, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.fs(11), Kit.EMERALD if rdy else Color("#c7b0de"))


## Virtual sticks + zone hints, drawn from Inp state (screen px == UI root px).
class StickLayer extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _dashed_rect(r: Rect2, col: Color) -> void:
		var d := 7.0
		var g := 6.0
		var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			var a: Vector2 = p[i]
			var b: Vector2 = p[(i + 1) % 4]
			var len := a.distance_to(b)
			var dir := (b - a) / maxf(len, 1.0)
			var t := 0.0
			while t < len:
				draw_line(a + dir * t, a + dir * minf(len, t + d), col, 1.0)
				t += d + g

	func _stick(o: Dictionary, col: Color, firing: bool) -> void:
		var base := Vector2(o.originX, o.originY)
		var knob := Vector2(o.knobX, o.knobY)
		var rr: float = Inp.stickSize * 0.5
		draw_circle(base, rr + 6, Kit.with_a(col, 0.05))
		draw_arc(base, rr, 0, TAU, 56, Kit.with_a(col, 0.55), 2.0, true)
		draw_arc(base, rr * 0.55, 0, TAU, 40, Kit.with_a(col, 0.16), 1.0, true)
		if knob.distance_to(base) > 2.0:
			draw_line(base, knob, Kit.with_a(col, 0.22), 3.0, true)
		draw_circle(knob, 26.0, Kit.with_a(col, 0.18 if not firing else 0.34))
		draw_circle(knob, 20.0, Kit.with_a(col.lightened(0.15), 0.55 if not firing else 0.85))
		draw_arc(knob, 20.0, 0, TAU, 32, Color(1, 1, 1, 0.7), 1.5, true)

	func _draw() -> void:
		if not Inp.mobileControlsVisible: return
		var f := Kit.font(false)
		var zs := [[Inp.moveZone, Inp.mobileMove, "移動", Kit.CYAN], [Inp.aimZone, Inp.mobileAim, "照準・射撃", Kit.FUCHSIA]]
		for z in zs:
			var r: Rect2 = z[0]
			var o: Dictionary = z[1]
			var col: Color = z[3]
			var held: bool = o.active
			if held:
				draw_style_box(Kit.box(Kit.with_a(col, 0.025), Color(0, 0, 0, 0), 0, 18), r)
			_dashed_rect(r, Kit.with_a(col, 0.40 if held else 0.26))
			var ts := f.get_string_size(z[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			if not held:
				draw_string(f, Vector2(r.position.x + (r.size.x - ts.x) * 0.5, r.end.y - 10), z[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Kit.with_a(col, 0.55))
		if Inp.mobileMove.active and Inp.mobileMove.revealed:
			_stick(Inp.mobileMove, Kit.CYAN, false)
		if Inp.mobileAim.active and Inp.mobileAim.revealed:
			_stick(Inp.mobileAim, Kit.FUCHSIA, float(Inp.mobileAim.mag) > 0.18)


## "CURRENT BUILD" panel (original #runStatusPanel + detail paragraphs).
class RunStatusPanel extends Kit.GlassPanel:
	static var instances: Array = []
	var mode_cp: Label
	var cells: Dictionary = {}
	var skills_lbl: Label
	var details: Dictionary = {}
	var grid: GridContainer

	func _init() -> void:
		super._init(Kit.CYAN, Kit.S3)
		brackets = false
		instances.append(self)
		var head := Kit.hbox(Kit.S3)
		var hv := Kit.vbox(2)
		hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hv.add_child(Kit.label("CURRENT BUILD", Kit.FS_XS, Kit.with_a(Kit.CYAN, 0.75), HORIZONTAL_ALIGNMENT_LEFT, false, true))
		hv.add_child(Kit.label("現在の最終ステータス / 強化状態", Kit.FS_XS, Kit.MUTE))
		head.add_child(hv)
		mode_cp = Kit.label("", Kit.FS_SM, Kit.AMBER, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
		head.add_child(mode_cp)
		body.add_child(head)
		grid = GridContainer.new()
		grid.columns = 2 if Kit.is_compact() else 4
		grid.add_theme_constant_override("h_separation", Kit.S2)
		grid.add_theme_constant_override("v_separation", Kit.S2)
		body.add_child(grid)
		for k in [["damage", "DAMAGE"], ["fireRate", "FIRE RATE"], ["projectiles", "PROJECTILES"], ["crit", "CRIT"],
				["pierce", "PIERCE / BOUNCE"], ["lifesteal", "LIFESTEAL"], ["pickup", "PICKUP"], ["drones", "DRONES"]]:
			var c := PanelContainer.new()
			c.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.08), 1, 8))
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var v := Kit.vbox(2)
			var m := Kit.margin(v, Kit.S2)
			v.add_child(Kit.label(k[1], Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, false, true))
			var val := Kit.label("0", Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, true)
			v.add_child(val)
			c.add_child(m)
			grid.add_child(c)
			cells[k[0]] = val
		body.add_child(Kit.hsep())
		skills_lbl = Kit.label("", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
		body.add_child(skills_lbl)
		for k in ["runGrowthSummary", "runDefenseDetail", "runDroneDetail", "runSkillDetail", "runCardHistory", "runAttackInfo", "runDamageBreakdown"]:
			var l := Kit.label("", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
			body.add_child(l)
			details[k] = l
		visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
		tree_exiting.connect(func(): instances.erase(self))

	func refresh() -> void:
		var p: Dictionary = Game.player
		if p.is_empty(): return
		var c: Dictionary = Meta.challenge()
		var gs := ""
		if Meta.runGrowth != null and not (Meta.runGrowth is Dictionary and (Meta.runGrowth as Dictionary).is_empty()):
			gs = "このランの成長適用：" + str(Meta.growthSummary(Meta.runGrowth)) + "（途中変更なし）"
		details.runGrowthSummary.text = gs
		details.runGrowthSummary.visible = gs != ""
		mode_cp.text = "%s / %s / CP %.2f" % [str(Meta.runConfig.mode).to_upper(), c.label, float(c.cp)]
		cells.damage.text = "%.1f" % float(p.damage)
		cells.fireRate.text = "%.1f/s" % float(p.fireRate)
		cells.projectiles.text = str(p.multishot)
		cells.crit.text = "%d%% ×%.2f" % [roundi(float(p.crit) * 100.0), float(p.critMult)]
		cells.pierce.text = "%s / %s" % [str(p.pierce), str(p.bulletBounces)]
		var heal := roundi(float(p.get("healEfficiency", 0.70)) * float(c.heal) * 100.0)
		cells.lifesteal.text = "%.1f%% / Heal %d%%" % [float(p.lifesteal) * 100.0, heal]
		var pk: String = "GLOBAL" if p.globalPickup else str(roundi(float(p.magnet)))
		if p.get("mapEspAdvanced", false): pk += " / ESP++"
		elif p.get("mapEsp", false): pk += " / ESP"
		cells.pickup.text = pk
		var ds: Dictionary = UI.droneStats()
		cells.drones.text = "%d機 / 単体 %.1f / %.2f発/秒" % [int(p.droneCount), float(ds.damage), float(ds.rate)]
		var names: Array = []
		var ranks: Dictionary = p.get("skillRanks", {})
		for id in ranks:
			var rk: int = int(ranks[id])
			if rk <= 0: continue
			names.append(_skill_name(str(id)))
		skills_lbl.text = " / ".join(names) if names.size() > 0 else "まだラン中強化を取得していません。"
		details.runDroneDetail.text = "ドローン継承：本体攻撃力の%d%%、連射値の18%%、弾速の15%%、クリ率の25%%、クリ追加倍率の30%%。本体の発射数・跳弾・吸血・処刑・状態異常・カード発動は継承しません。群体火力係数 %.2f（機数^0.60）。描画は最大8機に集約し、論理機数と威力は成長し続けます。" % [roundi(float(p.get("droneDamageTransfer", 0.18)) * 100.0), float(ds.fleetWeight)]
		details.runDefenseDetail.text = "敵 Lv.%d / シールド %d / バリア %.1f秒 / 付与封印 %.1f秒 / 回復阻害 %.1f秒。×印の紫弾・予告区域は全破壊＋封印、橙の菱形はバリア貫通。どちらもダッシュで回避できます。" % [
			int(Enemies.enemyLevelForWave()), int(p.shieldHits), float(p.barrierTime), float(p.barrierLock), float(p.wounded)]
		var sk: Array = []
		for i in Game.activeSlots.size():
			var s = Game.activeSlots[i]
			if s != null:
				sk.append("%d: %s Lv.%d / CD %.1f秒 / 残り %.1f秒" % [i + 1, Combat.ACTIVE_DEFS[s.id].name, int(s.level), Combat.activeCooldown(s), float(s.remaining)])
			else:
				sk.append("%d: 未取得" % (i + 1))
		details.runSkillDetail.text = " ｜ ".join(sk) + " / ボス報酬保留 %d回" % Game.abilityRewards.size()
		var hist: Array = []
		for h in Game.autoHistory: hist.append(str(h.name))
		details.runCardHistory.text = "カード保留 %d回 / 自動 %s / 最近の取得：%s" % [Game.pendingLevelUps, "ON" if Game.playPreferences.autoCards else "OFF", " → ".join(hist) if hist.size() > 0 else "なし"]
		var gear: int = (p.get("gearEffects", {}) as Dictionary).size()
		var chg := 0
		for s in Game.activeSlots:
			if s != null and s.get("charging") is Dictionary: chg += 1
		details.runAttackInfo.text = "チャージ効率 +%d%% / ビーム威力 ×%.2f / 装備パッシブ %d系統 / 充填中 %d枠" % [
			roundi(float(p.get("chargeEfficiency", 0)) * 100.0), float(p.get("beamPower", 1.0)), gear, chg]
		var t: Dictionary = Game.runDamageTotals
		details.runDamageBreakdown.text = "実ダメージ：本体 %s / ドローン %s / スキル %s / 装備 %s / 追加効果 %s" % [
			Kit.num(t.player), Kit.num(t.drone), Kit.num(t.active), Kit.num(t.gear), Kit.num(t.other)]

	static func _skill_name(id: String) -> String:
		for src in ["skills", "uniqueEpics", "legendarySkills"]:
			var arr = Cards.get(src)
			if arr is Array:
				for x in arr:
					if x is Dictionary and str(x.get("id", "")) == id: return str(x.get("name", id))
			elif arr is Dictionary and arr.has(id):
				var d = arr[id]
				if d is Dictionary: return str(d.get("name", id))
		return id


## Drone ON/OFF + target filter + priority + output (original #droneSettings).
class DronePanel extends VBoxContainer:
	static var instances: Array = []
	var summary: Label
	var t_enabled: Kit.NeonToggle
	var t_cat: Dictionary = {}
	var opt: OptionButton
	var sl: HSlider
	var out_lbl: Label
	var _busy := false
	const PRIOS := [["nearest", "近い敵"], ["boss", "ボス優先"], ["elite", "エリート優先"], ["weakest", "残りHPが少ない敵"], ["strongest", "残りHPが多い敵"], ["aim", "プレイヤーの照準付近"]]

	func _init() -> void:
		add_theme_constant_override("separation", Kit.S3)
		instances.append(self)
		summary = Kit.label("", Kit.FS_SM, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, true)
		add_child(summary)
		t_enabled = Kit.toggle(true, func(on: bool): _patch({"enabled": on}))
		add_child(Kit.setting_row("ドローン稼働", t_enabled, "OFFでも機数・強化は保持。飛行中のドローン弾は消去されます  [G]"))
		add_child(Kit.label("攻撃してよい敵", Kit.FS_SM, Kit.DIM))
		var row := Kit.hbox(Kit.S4)
		for k in [["normal", "通常"], ["elite", "エリート"], ["boss", "ボス"]]:
			var h := Kit.hbox(Kit.S2)
			h.add_child(Kit.label(k[1], Kit.FS_MD, Kit.TEXT))
			var tg := Kit.toggle(true, func(on: bool): _patch({k[0]: on}))
			tg.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			h.add_child(tg)
			t_cat[k[0]] = tg
			row.add_child(h)
		add_child(row)
		opt = OptionButton.new()
		opt.custom_minimum_size = Vector2(200, Kit.btn_h())
		opt.focus_mode = Control.FOCUS_ALL
		for p in PRIOS: opt.add_item(p[1])
		opt.item_selected.connect(func(i: int): _patch({"priority": PRIOS[i][0]}))
		add_child(Kit.setting_row("攻撃優先順位", opt))
		var srow := Kit.hbox(Kit.S3)
		sl = Kit.slider(0, 100, 1, 100, func(v: float): _patch({"output": v}))
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		out_lbl = Kit.label("100%", Kit.FS_MD, Kit.CYAN, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
		out_lbl.custom_minimum_size.x = 56
		srow.add_child(sl)
		srow.add_child(out_lbl)
		add_child(Kit.setting_row("出力", srow, "現在のドローン火力に対する割合（成長の上限ではありません）"))
		add_child(Kit.label("対象制限は誘導先と命中判定の両方へ適用します。", Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
		add_child(Kit.button("稼働100%・全敵に戻す", "ghost", func(): _reset()))
		visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
		tree_exiting.connect(func(): instances.erase(self))
		refresh()

	func _patch(d: Dictionary) -> void:
		if _busy: return
		UI.setDroneConfig(d)
		sync_all()

	func _reset() -> void:
		UI.setDroneConfig(UI.DRONE_DEFAULTS.duplicate())
		sync_all()

	static func sync_all() -> void:
		var keep: Array = []
		for p in instances:
			if is_instance_valid(p):
				keep.append(p)
				(p as DronePanel).refresh()
		instances = keep

	func refresh() -> void:
		_busy = true
		var c: Dictionary = UI.droneConfig
		t_enabled.set_value(bool(c.enabled))
		for k in t_cat: (t_cat[k] as Kit.NeonToggle).set_value(bool(c[k]))
		for i in PRIOS.size():
			if PRIOS[i][0] == c.priority: opt.select(i)
		sl.value = float(c.output)
		out_lbl.text = "%d%%" % int(round(float(c.output)))
		var p: Dictionary = Game.player
		var n := int(p.get("droneCount", 0)) if not p.is_empty() else 0
		var on: bool = c.enabled
		var tg := 0
		for k in ["normal", "elite", "boss"]:
			if c[k]: tg += 1
		var dps := 0.0
		if not p.is_empty():
			dps = float(UI.droneStats().dps) * (float(c.output) / 100.0 if on else 0.0)
		summary.text = "保有 %d機 / %s / 出力 %d%% / %s / 理論群体DPS %s" % [n, "稼働" if on else "停止", int(round(float(c.output))),
			("対象 %dカテゴリ" % tg) if tg > 0 else "対象なし（射撃しません）", Meta.researchNumber(dps)]
		_busy = false


# ============================================================== state
var _d: Dictionary = {}              # last updateUI payload
var _layer: Control
var _top_left: Control
var _top_right: Control
var _center: VBoxContainer
var _dock: VBoxContainer
var _stick: StickLayer
var _hp_bar: HudBar
var _hp_text: Label
var _lvl: Label
var _score: Label
var _defense: Label
var _combo: Label
var _combo_kills: Label
var _combo_bar: HudBar
var _wave: Label
var _obj: Label
var _boss_box: Control
var _boss_name: Label
var _boss_pct: Label
var _boss_bar: HudBar
var _xp_box: Control
var _xp_bar: HudBar
var _xp_text: Label
var _rarity: Label
var _legend: Control
var _enemy_lv: Label
var _effects: Label
var _b_cards: DockBtn
var _b_abil: DockBtn
var _b_auto: DockBtn
var _b_pause: DockBtn
var _b_drone: DockBtn
var _slots: Array = []
var _dash: DashBtn
var _warn: Control
var _warn_tw: Tween
var _touch := false
var _mock := ""
var _mock_t := 0.0
var _shown_alpha := 0.0
var _last_layout := Vector2.ZERO
var _boss_clock := 0.0

func _init() -> void:
	persistent = true
	layer_z = -5
	fade_time = 0.0

func setup(u: Node) -> void:
	super.setup(u)
	is_open = true
	visible = false
	set_process(true)

# ============================================================== build
func build() -> void:
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_layer)
	_stick = StickLayer.new()
	add_child(_stick)               # full-rect, below content (no safe-area offset)
	move_child(_stick, 1)
	_build_top_left()
	_build_top_right()
	_build_center()
	_build_dock()
	_build_boss_warning()
	_apply_layout()

func _glass(accent: Color, pad_x: int, pad_y: int) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := Kit.panel_style(accent, Color(0.035, 0.055, 0.105, 0.78), 0.10)
	sb.content_margin_left = pad_x; sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y; sb.content_margin_bottom = pad_y
	sb.set_corner_radius_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _lbl(t: String, sz: int, col: Color, al: int = HORIZONTAL_ALIGNMENT_LEFT, bold := true) -> Label:
	return Kit.label(t, sz, col, al, false, bold)

func _build_top_left() -> void:
	var p := _glass(Kit.CYAN, 16, 12)
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_layer.add_child(p)
	_top_left = p
	var v := Kit.vbox(8)
	p.add_child(v)
	var row := Kit.hbox(8)
	var l := _lbl("耐久値", Kit.FS_XS, Kit.with_a(Kit.CYAN, 0.85))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	_hp_text = _lbl("100 / 100", Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(_hp_text)
	v.add_child(row)
	_hp_bar = HudBar.new(12)
	_hp_bar.glow = true
	_hp_bar.value = 1.0; _hp_bar.shown = 1.0
	v.add_child(_hp_bar)
	var r2 := Kit.hbox(8)
	var a := Kit.vbox(0)
	a.add_child(_lbl("レベル", Kit.FS_XS, Kit.MUTE))
	_lvl = _lbl("01", Kit.FS_LG, Kit.TEXT)
	a.add_child(_lvl)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(a)
	var b := Kit.vbox(0)
	b.add_child(_lbl("スコア", Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_RIGHT))
	_score = _lbl("000000", Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	b.add_child(_score)
	r2.add_child(b)
	v.add_child(r2)
	_defense = _lbl("", Kit.FS_XS, Kit.AMBER)
	_defense.visible = false
	v.add_child(_defense)

func _build_top_right() -> void:
	var p := _glass(Kit.VIOLET, 16, 12)
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_layer.add_child(p)
	_top_right = p
	var v := Kit.vbox(6)
	p.add_child(v)
	v.add_child(_lbl("連続撃破", Kit.FS_XS, Kit.with_a(Kit.VIOLET, 0.9), HORIZONTAL_ALIGNMENT_RIGHT))
	var row := Kit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	_combo = _lbl("x1.00", Kit.FS_2XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(_combo)
	_combo_kills = _lbl("0 連鎖", Kit.FS_XS, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, false)
	_combo_kills.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_combo_kills)
	v.add_child(row)
	_combo_bar = HudBar.new(7)
	_combo_bar.stops = PackedColorArray([VIO_C, Kit.CYAN])
	v.add_child(_combo_bar)

func _build_center() -> void:
	_center = VBoxContainer.new()
	_center.add_theme_constant_override("separation", 4)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_layer.add_child(_center)
	_wave = _lbl("ウェーブ 01", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_center.add_child(_wave)
	_obj = _lbl("ネオン空間を生き残れ。", Kit.FS_MD, Color(0.89, 0.91, 0.94, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	_obj.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_obj.add_theme_constant_override("outline_size", 4)
	_center.add_child(_obj)
	# boss HP bar (appears while a boss is alive)
	_boss_box = VBoxContainer.new()
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	var bh := Kit.hbox(8)
	_boss_name = _lbl("防衛異常体", Kit.FS_XS, Kit.ROSE)
	_boss_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(_boss_name)
	_boss_pct = _lbl("100%", Kit.FS_XS, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	bh.add_child(_boss_pct)
	_boss_box.add_child(bh)
	_boss_bar = HudBar.new(10)
	_boss_bar.stops = PackedColorArray([Color("#be123c"), ROSE_C, Color("#fda4af")])
	_boss_bar.glow = true
	_boss_box.add_child(_boss_bar)
	_center.add_child(_boss_box)
	# XP
	_xp_box = VBoxContainer.new()
	_xp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var xh := Kit.hbox(8)
	var xl := _lbl("共鳴経験値", Kit.FS_XS, Kit.MUTE)
	xl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xh.add_child(xl)
	_rarity = _lbl("希少共鳴 0 / 3", Kit.FS_XS, Kit.VIOLET, HORIZONTAL_ALIGNMENT_RIGHT)
	xh.add_child(_rarity)
	_xp_text = _lbl("0 / 10", Kit.FS_XS, CYAN_L, HORIZONTAL_ALIGNMENT_RIGHT)
	xh.add_child(_xp_text)
	_xp_box.add_child(xh)
	_xp_bar = HudBar.new(10)
	_xp_bar.stops = PackedColorArray([BLUE_C, VIO_C, Color("#a5f3fc")])
	_xp_bar.glow = true
	_xp_box.add_child(_xp_bar)
	_legend = Kit.hbox(16)
	(_legend as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_legend.add_child(_lbl("□＋ 経験値", Kit.FS_XS, Kit.EMERALD))
	_legend.add_child(_lbl("● 敵弾", Kit.FS_XS, Color("#fb923c")))
	_legend.add_child(_lbl("◇× 破壊・貫通", Kit.FS_XS, Kit.FUCHSIA))
	_xp_box.add_child(_legend)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_child(gap)
	_center.add_child(_xp_box)

func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.add_theme_constant_override("separation", 6)
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_layer.add_child(_dock)
	var st := Kit.hbox(10)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_lv = _lbl("敵 Lv.1", Kit.FS_SM, Kit.AMBER)
	st.add_child(_enemy_lv)
	_effects = _lbl("", Kit.FS_SM, Kit.ROSE, HORIZONTAL_ALIGNMENT_LEFT, false)
	_effects.clip_text = true
	_effects.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.add_child(_effects)
	_dock.add_child(st)
	var cmd := HBoxContainer.new()
	cmd.add_theme_constant_override("separation", 6)
	cmd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_b_cards = DockBtn.new("カード", "Q")
	_b_cards.count = 0
	_b_cards.pressed.connect(func(): if Game.state == "playing" or Game.state == "upgrade": Inp.toggleRunPanel("cards"))
	_b_abil = DockBtn.new("スキル", "E")
	_b_abil.count = 0
	_b_abil.pressed.connect(func(): if Game.state == "playing" or Game.state == "ability": Inp.toggleRunPanel("abilities"))
	_b_auto = DockBtn.new("自動 OFF")
	_b_auto.pressed.connect(func(): Game.toggleAutoCards())
	_b_pause = DockBtn.new("Ⅱ  Esc 停止")
	_b_pause.pressed.connect(func(): Game.setPause(true))
	_b_drone = DockBtn.new("◎ DRN ON")
	_b_drone.pressed.connect(func(): UI.toggleDrones(); _sync_drone_btn())
	_b_auto.tooltip_text = "自動取得の切替 [F]"
	_b_drone.tooltip_text = "ドローンのON／OFF [G]。詳細は一時停止のドローン設定"
	_b_pause.tooltip_text = "一時停止・操作設定"
	for b in [_b_cards, _b_abil, _b_auto, _b_pause, _b_drone]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 1.15 if (b == _b_cards or b == _b_abil or b == _b_drone) else 0.9
		cmd.add_child(b)
	_dock.add_child(cmd)
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var s := SlotBtn.new(i)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		act.add_child(s)
		_slots.append(s)
	_dash = DashBtn.new()
	_dash.pressed.connect(_on_dash)
	act.add_child(_dash)
	_dock.add_child(act)

func _build_boss_warning() -> void:
	_warn = Control.new()
	_warn.set_anchors_preset(Control.PRESET_FULL_RECT)
	_warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warn.visible = false
	add_child(_warn)
	var tint := ColorRect.new()
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.5, 0.0, 0.08, 0.14)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warn.add_child(tint)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warn.add_child(cc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := Kit.label("巨大異常体を検出", Kit.FS_LG, Color("#fda4af"), HORIZONTAL_ALIGNMENT_CENTER, false, true)
	var b := Kit.label("ボスウェーブ", Kit.FS_3XL + 28, Color("#ffe4e6"), HORIZONTAL_ALIGNMENT_CENTER, false, true)
	b.add_theme_color_override("font_outline_color", Color(0.9, 0.1, 0.25, 0.8))
	b.add_theme_constant_override("outline_size", 10)
	v.add_child(a)
	v.add_child(b)
	cc.add_child(v)

# ============================================================== layout
func _apply_layout() -> void:
	if _layer == null: return
	var vs := get_viewport_rect().size
	var touch := Inp.inputMode == "touch"
	_touch = touch
	var avail := vs.x - content.get_theme_constant("margin_left") - content.get_theme_constant("margin_right")
	# dock width: min(560, avail) on keyboard; ~44% / min 310 on touch (original body.nf-touch #combatDock)
	var dw: float = minf(560.0, avail - 16.0)
	if touch: dw = maxf(310.0, avail * 0.44)
	_dock.custom_minimum_size.x = dw
	var xw: float = minf(440.0, avail * 0.30)
	if touch: xw = avail * 0.34
	_xp_box.custom_minimum_size.x = maxf(xw, 220.0)
	_legend.visible = not touch and vs.y >= 700
	_top_left.custom_minimum_size.x = 210.0 if touch else 300.0
	_top_right.custom_minimum_size.x = 150.0 if touch else 190.0
	_center.custom_minimum_size.x = maxf(xw, 220.0)
	for s in _slots:
		(s as SlotBtn).touch_layout = touch
		(s as SlotBtn).custom_minimum_size.y = (84 if touch else Kit.btn_h() + 12)   # touch: >= ~7 mm thumb target on a 1080p phone
	_b_pause.label_text = "Ⅱ" if touch else "Ⅱ  Esc 停止"
	for b in [_b_cards, _b_abil]:
		(b as DockBtn).key_text = "" if touch else ("Q" if b == _b_cards else "E")
	_refresh_keys()
	for b in [_b_cards, _b_abil, _b_auto, _b_pause, _b_drone]:
		(b as DockBtn).custom_minimum_size.y = 72 if touch else Kit.btn_h()
		(b as DockBtn).queue_redraw()
	_dash.custom_minimum_size.x = 96.0 if touch else 76.0
	_last_layout = vs

func _refresh_keys() -> void:
	var k: Dictionary = Inp.currentKeys()
	if not _touch:
		_b_cards.key_text = Inp.keyLabel(str(k.cards))
		_b_abil.key_text = Inp.keyLabel(str(k.rewards))
	for i in 3:
		(_slots[i] as SlotBtn).key_text = Inp.keyLabel(str((k.skills as Array)[i]))
	_b_cards.tooltip_text = "カード選択 [%s] / %d回保留" % [Inp.keyLabel(str(k.cards)), Game.pendingLevelUps]
	_b_abil.tooltip_text = "スキル獲得・強化 [%s] / %d回保留" % [Inp.keyLabel(str(k.rewards)), Game.abilityRewards.size()]

# ============================================================== lifecycle
## HUD never grabs focus (Space/Enter must stay gameplay keys, not ui_accept on a dock button).
func _grab_default_focus() -> void:
	pass

func on_open(_args: Dictionary = {}) -> void:
	visible = true
	_apply_layout()
	_mock = OS.get_environment("NF_HUD_MOCK")
	if _mock != "" and Game.state == "menu":
		_start_mock()

func _want_visible() -> bool:
	return ["playing", "paused", "upgrade", "ability"].has(Game.state)

func _process(dt: float) -> void:
	var want := _want_visible()
	# Full-screen run panels (pause / card choice / ability reward) cover the HUD: fade it out so the
	# panel headers don't overlap the HP/score plates.
	var target := 1.0 if Game.state == "playing" else 0.0
	if want and _mock != "": target = 1.0
	_shown_alpha = move_toward(_shown_alpha, target, dt * 5.0)
	modulate.a = _shown_alpha
	visible = _shown_alpha > 0.01
	if not visible: return
	if get_viewport_rect().size != _last_layout or _touch != (Inp.inputMode == "touch"):
		_apply_layout()
	if _mock != "": _mock_tick(dt)
	_dock.visible = Game.state == "playing" and Inp.combatDockVisible or (Game.state == "playing" and _mock != "")
	_refresh_dock()
	_boss_clock -= dt
	if _boss_clock <= 0.0:
		_boss_clock = 0.08
		_refresh_boss()
	if Inp.mobileControlsVisible or _stick.get_meta("had", false):
		_stick.set_meta("had", Inp.mobileControlsVisible)
		_stick.queue_redraw()

func _st(l: Label, t: String) -> void:
	if l.text != t: l.text = t

# ============================================================== hooks
func h_updateUI(d: Variant = null) -> void:
	if not (d is Dictionary): return
	_d = d
	_apply_ui()

func _apply_ui() -> void:
	var d := _d
	if d.is_empty(): return
	_hp_bar.value = float(d.hpPct) / 100.0
	_st(_hp_text, str(d.hpText))
	_st(_lvl, str(d.levelText))
	_st(_score, str(d.scoreText))
	_st(_combo, str(d.comboText))
	_st(_combo_kills, str(d.comboKillsText))
	_combo_bar.value = clampf(float(d.comboBarPct) / 100.0, 0.0, 1.0)
	_st(_wave, str(d.waveText))
	_st(_obj, str(d.objectiveText))
	_st(_xp_text, str(d.xpText))
	_xp_bar.value = clampf(float(d.xpPct) / 100.0, 0.0, 1.0)
	_st(_rarity, str(d.rarityBoostText))
	_rarity.add_theme_color_override("font_color", Kit.AMBER if d.epicGuarantee else Kit.VIOLET)
	var ds := str(d.defenseText)
	_st(_defense, ds)
	_defense.visible = ds != ""
	var low: float = float(d.hpPct)
	_hp_bar.stops = PackedColorArray([ROSE_C, FUCH_C, Kit.CYAN]) if low > 30.0 else PackedColorArray([Color("#be123c"), ROSE_C, Color("#fb7185")])

func h_syncCombatHud() -> void:
	_refresh_dock()

func b_syncCombatHud() -> void:
	pass

func h_syncInputPresentation(_state: Variant = null, _mode: Variant = null) -> void:
	_apply_layout()
	_refresh_dock()

func h_setMobileControls(_show: Variant = false, _mode: Variant = null) -> void:
	_stick.queue_redraw()
	_apply_layout()

func h_skillHoldVisual(v: Variant = null) -> void:
	if not (v is Array): return
	for i in mini(3, (v as Array).size()):
		(_slots[i] as SlotBtn).held = bool(v[i])
		(_slots[i] as SlotBtn).queue_redraw()

func h_updateSkillHolds() -> void:
	# Original UI block hook: repeat-use held skills when ready (logic lives in Inp).
	Inp.updateSkillHolds()

func h_resetGameUI(_touch_capable: Variant = null) -> void:
	h_hideBossWarning()
	h_skillHoldVisual([false, false, false])
	_d = {}
	_hp_bar.shown = 1.0; _hp_bar.value = 1.0
	_xp_bar.shown = 0.0; _xp_bar.value = 0.0
	_apply_layout()
	_refresh_dock()

func h_finishPresentation() -> void:
	h_hideBossWarning()
	h_skillHoldVisual([false, false, false])

func h_showBossWarning() -> void:
	_warn.visible = true
	_warn.modulate.a = 0.0
	if _warn_tw and _warn_tw.is_valid(): _warn_tw.kill()
	_warn_tw = create_tween().set_loops()
	_warn_tw.tween_property(_warn, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	_warn_tw.tween_property(_warn, "modulate:a", 0.55, 0.22).set_trans(Tween.TRANS_SINE)

func h_hideBossWarning() -> void:
	if not _warn.visible: return
	if _warn_tw and _warn_tw.is_valid(): _warn_tw.kill()
	var tw := create_tween()
	tw.tween_property(_warn, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func(): if Game.bossWarningTimer <= 0.0: _warn.visible = false)

func h_renderRunStatus() -> void:
	var keep: Array = []
	for p in RunStatusPanel.instances:
		if is_instance_valid(p):
			keep.append(p)
			(p as RunStatusPanel).refresh()
	RunStatusPanel.instances = keep

func h_syncDroneControls() -> void:
	_sync_drone_btn()
	DronePanel.sync_all()

func h_toggleDrones() -> void:
	UI.toggleDrones()
	_sync_drone_btn()
	DronePanel.sync_all()

# ============================================================== dock refresh
func auto_cards_text(long: bool = true) -> String:
	var on: bool = Game.playPreferences.get("autoCards", false)
	if long: return "自動取得：ON" if on else "自動取得：OFF"
	return "自動 ON" if on else "自動 OFF"

func _sync_drone_btn() -> void:
	var on: bool = UI.droneConfig.get("enabled", true)
	var t := "%s DRN %s" % ["◎" if on else "○", "ON" if on else "OFF"]
	if _b_drone.label_text != t:
		_b_drone.label_text = t
	_b_drone.set_tone(Kit.VIOLET if on else Kit.SLATE, false, not on)

func _on_dash() -> void:
	if Game.state != "playing": return
	if float(Game.player.dashReady) < 1.0:
		Inp.showInputNotice("ダッシュは再充填中です", 1000)
		return
	Game.dash()
	_refresh_dock()

func _refresh_dock() -> void:
	var p: Dictionary = Game.player
	if p.is_empty() or _slots.is_empty(): return
	var pend: int = Game.pendingLevelUps
	var ab: int = Game.abilityRewards.size()
	_b_cards.count = pend
	_b_cards.set_tone(Kit.EMERALD if pend > 0 else Kit.CYAN, pend > 0, false)
	_b_abil.count = ab
	_b_abil.set_tone(Kit.EMERALD if ab > 0 else Kit.CYAN, ab > 0, false)
	_b_cards.queue_redraw(); _b_abil.queue_redraw()
	var auto: bool = Game.playPreferences.get("autoCards", false)
	var at := auto_cards_text(false)
	if _b_auto.label_text != at or _b_auto.lit != auto:
		_b_auto.label_text = at
		_b_auto.set_tone(Kit.EMERALD if auto else Kit.SLATE, auto, false)
	_sync_drone_btn()
	_st(_enemy_lv, "敵 Lv.%d" % int(Enemies.enemyLevelForWave()))
	var deb: Array = []
	if float(p.get("barrierLock", 0)) > 0: deb.append("バリア付与不可 %.1f秒" % float(p.barrierLock))
	if float(p.get("wounded", 0)) > 0: deb.append("回復低下 %.1f秒" % float(p.wounded))
	if int(p.get("shieldHits", 0)) > 0: deb.append("シールド %d" % int(p.shieldHits))
	if float(p.get("barrierTime", 0)) > 0: deb.append("バリア %.1f秒" % float(p.barrierTime))
	_st(_effects, " / ".join(deb))
	var keys: Dictionary = Inp.currentKeys()
	for i in 3:
		var sb: SlotBtn = _slots[i]
		var slot = Game.activeSlots[i] if i < Game.activeSlots.size() else null
		if slot == null:
			sb.has_slot = false; sb.can_use = false; sb.charging = false
			sb.title = "未取得"; sb.sub = "ボス報酬"; sb.rdy = 0.0
			sb.tooltip_text = "ボスを倒すと取得できます"
		else:
			var def: Dictionary = Combat.ACTIVE_DEFS[slot.id]
			var ch = slot.get("charging")
			var is_ch: bool = ch is Dictionary
			sb.has_slot = true
			sb.charging = is_ch
			sb.can_use = float(slot.remaining) <= 0.0 and not is_ch
			sb.title = str(def.name)
			if is_ch:
				var warn: float = maxf(0.0001, float(ch.get("warn", 1.0)))
				sb.sub = "充填 %d%%" % roundi(clampf(float(ch.get("age", 0.0)) / warn, 0.0, 1.0) * 100.0)
			elif float(slot.remaining) > 0.0:
				sb.sub = "%.1fs" % float(slot.remaining)
			else:
				sb.sub = "Lv.%d" % int(slot.level)
			sb.rdy = 1.0 - clampf(float(slot.remaining) / maxf(0.001, Combat.activeCooldown(slot)), 0.0, 1.0)
			sb.tooltip_text = "%s [%s]%s" % [def.name, Inp.keyLabel(str((keys.skills as Array)[i])),
				(" / 再使用まで %.1f秒" % float(slot.remaining)) if float(slot.remaining) > 0.0 else ""]
		sb.queue_redraw()
	var dr: float = float(p.dashReady)
	_dash.pct = dr
	_dash.status = "READY" if dr >= 1.0 else "%.1fs" % ((1.0 - dr) * float(p.dashCooldown))
	_dash.queue_redraw()
	_refresh_keys()

func _refresh_boss() -> void:
	var boss = null
	if Game.bossAlive:
		for e in Game.enemies:
			if e.get("boss", false) and not e.get("_dead", false):
				boss = e
				break
	if boss == null:
		_boss_box.visible = false
		return
	_boss_box.visible = true
	var nm := "防衛異常体"
	if boss.get("bossKind", "") == "spinner": nm = "回転異常体"
	elif boss.get("bossKind", "") == "hunter": nm = "追跡異常体"
	var n: int = Enemies.activeBosses().size()
	_st(_boss_name, nm + ((" ほか %d体" % n) if n > 1 else ""))
	var pct: float = clampf(float(boss.hp) / maxf(1.0, float(boss.maxHp)), 0.0, 1.0)
	_boss_bar.value = pct
	_st(_boss_pct, "%d%%" % ceili(pct * 100.0))
	_boss_box.custom_minimum_size.x = _center.custom_minimum_size.x

# ============================================================== helpers for other screens
## True when screen position `pos` (UI root px) is over a clickable HUD control. main.gd/Inp should NOT
## start shooting / sticks for a press there (Godot runs _input before GUI, so handled events never reach buttons).
func pointer_over_hud(pos: Vector2) -> bool:
	if not visible or _dock == null or not _dock.is_visible_in_tree(): return false
	for c in [_b_cards, _b_abil, _b_auto, _b_pause, _b_drone, _dash] + _slots:
		if (c as Control).get_global_rect().grow(4.0).has_point(pos): return true
	return false

func build_drone_panel() -> Control:
	return DronePanel.new()

func build_run_status_panel() -> Control:
	var p := RunStatusPanel.new()
	p.refresh()
	return p

# ============================================================== dev mock (NF_HUD_MOCK=kb|touch)
func _start_mock() -> void:
	Game.resetGame()
	if _mock == "touch":
		Inp.setInputMode("touch")
	var p: Dictionary = Game.player
	p.hp = p.maxHp * 0.63
	p.xp = float(p.nextXp) * 0.45
	p.level = 7
	p.shieldHits = 2
	p.guardTimer = 1.6
	p.barrierLock = 3.2
	Game.score = 128430
	Game.combo = 3.4
	Game.comboKills = 42
	Game.comboTimer = Combat.comboWindow() * 0.6
	Game.wave = 9
	Game.pendingLevelUps = 2
	Game.abilityRewards = [{"offers": ["nova"], "boss": 1, "wave": 5}]
	Game.activeSlots[0] = {"id": "nova", "level": 2, "remaining": 6.2, "charging": null}
	Game.activeSlots[1] = {"id": "lance", "level": 1, "remaining": 0.0, "charging": null}
	Game.playPreferences.autoCards = true
	Game.bossAlive = true
	Enemies.spawnBoss()
	Inp.heldSkills.clear()
	Inp.heldSkills["mock"] = {"index": 1, "started": Game.time}
	h_skillHoldVisual([false, true, false])
	p.dashReady = 0.4
	h_showBossWarning()
	if OS.get_environment("NF_HUD_NOWARN") != "": h_hideBossWarning()

func _mock_tick(dt: float) -> void:
	_mock_t += dt
	Game.player.hp = maxf(float(Game.player.hp), 1.0)
	Game.bossWarningTimer = 0.0 if OS.get_environment("NF_HUD_NOWARN") != "" else 100.0
	if _mock == "touch":
		Inp.mobileControlsVisible = true
		Inp.mobileMove.active = true; Inp.mobileMove.revealed = true
		var vs := get_viewport_rect().size
		Inp.mobileMove.originX = Inp.moveZone.position.x + 140.0; Inp.mobileMove.originY = Inp.moveZone.end.y - 110.0
		Inp.mobileMove.knobX = Inp.mobileMove.originX + 18.0; Inp.mobileMove.knobY = Inp.mobileMove.originY - 14.0
		Inp.mobileAim.active = true; Inp.mobileAim.revealed = true; Inp.mobileAim.mag = 0.8
		Inp.mobileAim.originX = Inp.aimZone.end.x - 140.0; Inp.mobileAim.originY = Inp.aimZone.end.y - 110.0
		Inp.mobileAim.knobX = Inp.mobileAim.originX - 20.0; Inp.mobileAim.knobY = Inp.mobileAim.originY - 12.0
		if vs.x <= 0: return
