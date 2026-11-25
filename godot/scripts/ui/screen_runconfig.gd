extends NFScreen
## #runConfigScreen — mode / difficulty / custom parameters / CP preview / RUN START.
## Original: index.html 4698-4778 (HTML), 9760-9815 (JS). State: Game.state == "config" while open.
## Hooks: openRunConfig, closeRunConfig. Broadcast: resetGameUI / openMeta (hide), closeMeta (return from growth editor).

const DIFFS := [
	["easy", "EASY", "v26基準。育成・爽快感向け。", Kit.TEXT],
	["normal", "NORMAL", "物量・HP・火力が明確に上昇。", Kit.TEXT],
	["hard", "HARD", "高密度＋高火力。強ビルド前提。", Kit.TEXT],
	["hardcore", "HARDCORE", "Shield/Barrierなし、回復半減。", Kit.ROSE],
	["fracture", "FRACTURE", "ONE HIT = RUN END。", Kit.AMBER],
	["custom", "CUSTOM", "条件からCPと報酬倍率を自動計算。", Kit.VIOLET],
]
const SLIDERS := [
	["density", "敵密度", 0.5, 3.5, 0.1], ["hpGrowth", "HP成長", 0.5, 8.0, 0.1], ["damageGrowth", "火力成長", 0.5, 8.0, 0.1],
	["elite", "Elite率", 0.5, 4.0, 0.1], ["attack", "攻撃密度", 0.7, 3.0, 0.1], ["levelRate", "敵Lv成長", 0.5, 12.0, 0.5],
]
const PRESETS := [["swarm", "SWARM"], ["bullet", "BULLET HELL"], ["boss", "BOSS RUSH"], ["onehit", "ONE HIT"], ["allboss", "ALL BOSS"], ["maximum", "最高成長"]]
const BOSS_NAMES := {"warden": "防衛異常体", "spinner": "回転異常体", "hunter": "追跡異常体"}
const INTERVALS := [10, 5, 4, 3]
const HEALS := [1.0, 0.5, 0.0]
const ROSTERS := ["auto", "selected", "bossOnly"]
const CLEAR_WAVES := [20, 30, 50]

var _syncing := false
var _narrow := false
var _compact := false
# widgets
var _mode_cards: Dictionary = {}
var _diff_cards: Dictionary = {}
var _clear_row: Control
var _clear_seg: Kit.Segmented
var _custom_panel: Control
var _sliders: Dictionary = {}
var _slider_vals: Dictionary = {}
var _interval_seg: Kit.Segmented
var _heal_seg: Kit.Segmented
var _shield_tg: Kit.NeonToggle
var _onehit_tg: Kit.NeonToggle
var _start_spin: SpinBox
var _roster_seg: Kit.Segmented
var _enemy_panel: Control
var _enemy_chips: Dictionary = {}
var _boss_chips: Dictionary = {}
var _boss_en_tg: Kit.NeonToggle
var _boss_limit_row: Control
var _boss_limit_seg: Kit.Segmented
var _boss_note: Label
# summary
var _cp_lbl: Label
var _diff_lbl: Label
var _stat_vals: Dictionary = {}
var _rules_box: VBoxContainer
var _growth_grid: GridContainer
var _growth_title: Label
var _err_lbl: Label
var _grow_lbl: Label
var _start_btn: Kit.NeonButton
var _first_focus: Control

# ------------------------------------------------------------------ small widget
class OptCard extends PanelContainer:
	signal pressed
	var accent: Color = Kit.CYAN
	var selected := false:
		set(v):
			selected = v
			_style()
	var _hover := false
	var _down := false
	var title_lbl: Label
	var desc_lbl: Label
	var tag_lbl: Label

	func _init(title: String, desc: String, ac: Color, title_col: Color = Kit.TEXT, tag: String = "") -> void:
		accent = ac
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var m := MarginContainer.new()
		for s in ["left", "top", "right", "bottom"]: m.add_theme_constant_override("margin_" + s, 12)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		var v := Kit.vbox(4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(v)
		var top := Kit.hbox(6)
		title_lbl = Kit.label(title, Kit.FS_MD, title_col, HORIZONTAL_ALIGNMENT_LEFT, false, true)
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(title_lbl)
		tag_lbl = Kit.label(tag, Kit.FS_XS, ac, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
		top.add_child(tag_lbl)
		v.add_child(top)
		desc_lbl = Kit.label(desc, Kit.FS_XS, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
		v.add_child(desc_lbl)
		mouse_entered.connect(func(): _hover = true; _style())
		mouse_exited.connect(func(): _hover = false; _style())
		focus_entered.connect(func(): _style())
		focus_exited.connect(func(): _style())
		_style()

	func _style() -> void:
		var hot := _hover or has_focus()
		var fill := Kit.with_a(accent, 0.20 if selected else (0.09 if hot else 0.035))
		var border := Kit.with_a(accent, 0.95 if selected else (0.7 if hot else 0.25))
		var sb := Kit.box(fill, border, 2 if (selected or has_focus()) else 1, 8,
			Kit.with_a(accent, 0.32 if selected else (0.15 if hot else 0.0)), 12 if selected else (6 if hot else 0))
		if has_focus(): sb.border_color = Color.WHITE
		add_theme_stylebox_override("panel", sb)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed: _down = true
			elif _down:
				_down = false
				if Rect2(Vector2.ZERO, size).has_point(e.position):
					accept_event()
					pressed.emit()
		elif e.is_action_pressed("ui_accept"):
			accept_event()
			pressed.emit()

class Chip extends Button:
	## toggle chip (enemy / boss checkbox)
	func _init(text_: String, ac: Color = Kit.CYAN) -> void:
		toggle_mode = true
		text = text_
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_theme_font_size_override("font_size", Kit.fs(Kit.FS_SM))
		custom_minimum_size.y = Kit.btn_h() - 6
		var on := Kit.box(Kit.with_a(ac, 0.26), ac, 1, 6, Kit.with_a(ac, 0.3), 8)
		var off := Kit.box(Color(1, 1, 1, 0.025), Color(1, 1, 1, 0.14), 1, 6)
		var hv := Kit.box(Color(1, 1, 1, 0.07), Kit.with_a(ac, 0.6), 1, 6)
		for s in [on, off, hv]:
			s.content_margin_left = 12; s.content_margin_right = 12; s.content_margin_top = 6; s.content_margin_bottom = 6
		add_theme_stylebox_override("normal", off)
		add_theme_stylebox_override("hover", hv)
		add_theme_stylebox_override("pressed", on)
		add_theme_stylebox_override("hover_pressed", on)
		var fcs := Kit.box(Color(0, 0, 0, 0), Color.WHITE, 2, 7)
		fcs.draw_center = false
		add_theme_stylebox_override("focus", fcs)
		add_theme_color_override("font_color", Kit.DIM)
		add_theme_color_override("font_pressed_color", Color.WHITE)
		add_theme_color_override("font_hover_color", Color.WHITE)
		add_theme_color_override("font_hover_pressed_color", Color.WHITE)

# ------------------------------------------------------------------ lifecycle
func build() -> void:
	modal = true
	dim_alpha = 0.80
	layer_z = 10
	z_index = layer_z
	get_viewport().size_changed.connect(_on_resize)
	_rebuild()

func _on_resize() -> void:
	if not is_open: return
	var n := get_viewport_rect().size.x < 960.0
	if n != _narrow or Kit.is_compact() != _compact:
		_rebuild()
		_sync_inputs()

func on_open(_args: Dictionary = {}) -> void:
	_rebuild()
	_sync_inputs()

func on_cancel() -> bool:
	h_closeRunConfig()
	return true

func _rebuild() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	_narrow = get_viewport_rect().size.x < 960.0
	_compact = Kit.is_compact()
	_build_ui()

# ------------------------------------------------------------------ hooks
func h_openRunConfig() -> void:
	Game.state = "config"
	Game.cancelCombatInput()
	UI.goto("runconfig")

func h_closeRunConfig() -> void:
	if not is_open: return
	UI.hide_screen("runconfig")
	Game.state = "menu"
	UI.show_screen("home")
	if Inp.has_method("syncInputPresentation"): Inp.syncInputPresentation()

func b_resetGameUI(_touch = null) -> void:
	if is_open: UI.hide_screen("runconfig")

func b_openMeta(_from = null) -> void:
	if is_open: UI.hide_screen("runconfig")

## Returning from the meta (growth editor) opened with openMeta("config").
func b_closeMeta() -> void:
	call_deferred("_after_meta")

func _after_meta() -> void:
	if Game.state == "config" and not is_open:
		UI.goto("runconfig")

# ------------------------------------------------------------------ UI construction
func _build_ui() -> void:
	_mode_cards.clear(); _diff_cards.clear(); _sliders.clear(); _slider_vals.clear()
	_enemy_chips.clear(); _boss_chips.clear(); _stat_vals.clear()
	var vp := get_viewport_rect().size
	var shell := Kit.panel(Kit.CYAN, Kit.S4 if _compact else Kit.S5)
	shell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.custom_minimum_size.x = minf(1380.0, vp.x - 24.0)
	content.add_child(shell)
	var root := shell.body
	root.add_theme_constant_override("separation", Kit.S3)

	# header
	var head := Kit.hbox(Kit.S4)
	var hv := Kit.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(Kit.label("RUN CONFIGURATION", Kit.FS_XS, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	hv.add_child(Kit.label("遊び方を選択", Kit.FS_2XL if not _compact else Kit.FS_XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	if not _compact:
		hv.add_child(Kit.label("敵速度は全難易度で固定。物量・HP・火力・攻撃構成で難しくなる。", Kit.FS_SM, Kit.MUTE))
	head.add_child(hv)
	var close := Kit.button("✕", "ghost", h_closeRunConfig)
	close.custom_minimum_size = Vector2(Kit.btn_h(), Kit.btn_h())
	head.add_child(close)
	root.add_child(head)
	root.add_child(Kit.hsep(Kit.with_a(Kit.CYAN, 0.3)))

	# body: left config scroll + right summary scroll
	var left_sc := Kit.scroll_list(Kit.S3)
	var right_sc := Kit.scroll_list(Kit.S3)
	_build_left(Kit.list_of(left_sc))
	_build_summary(Kit.list_of(right_sc))
	if _narrow:
		var one := Kit.scroll_list(Kit.S3)
		var col := Kit.list_of(one)
		# reuse the already built content inside a single column
		var lv := Kit.list_of(left_sc)
		var rv := Kit.list_of(right_sc)
		left_sc.remove_child(lv); right_sc.remove_child(rv)
		col.add_child(lv); col.add_child(rv)
		root.add_child(one)
	else:
		var row := Kit.hbox(Kit.S4)
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left_sc.size_flags_stretch_ratio = 1.35
		right_sc.size_flags_stretch_ratio = 0.65
		row.add_child(left_sc)
		row.add_child(right_sc)
		root.add_child(row)

	# footer
	var foot := Kit.hbox(Kit.S3)
	var back := Kit.button("戻る", "ghost", h_closeRunConfig)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.size_flags_stretch_ratio = 0.4
	_start_btn = Kit.button("RUN START →", "cta", _on_start)
	_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(back)
	foot.add_child(_start_btn)
	root.add_child(foot)
	default_focus = _start_btn

func _sec_label(t: String) -> Label:
	return Kit.label(t, Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, false, true)

func _build_left(col: VBoxContainer) -> void:
	col.add_child(_sec_label("GAME MODE"))
	var mg := GridContainer.new()
	mg.columns = 2
	mg.add_theme_constant_override("h_separation", Kit.S2)
	mg.add_theme_constant_override("v_separation", Kit.S2)
	mg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(mg)
	for m in [["endless", "∞ ENDLESS", "無限Wave。最高Wave・Score・CP記録を更新。", Kit.CYAN], ["clear", "✓ CLEAR RUN", "最終WaveのBoss撃破でクリア。タイムも記録。", Kit.EMERALD]]:
		var c := OptCard.new(m[1], m[2], m[3], m[3].lightened(0.5))
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = m[0]
		c.pressed.connect(func(): _set_mode(id))
		mg.add_child(c)
		_mode_cards[id] = c

	# clear target
	var crow := PanelContainer.new()
	crow.add_theme_stylebox_override("panel", Kit.box(Kit.with_a(Kit.EMERALD, 0.04), Kit.with_a(Kit.EMERALD, 0.18), 1, 8))
	var ch := Kit.hbox(Kit.S3)
	ch.add_child(Kit.label("FINAL WAVE", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	ch.add_child(Kit.fill_spacer())
	_clear_seg = Kit.segmented(["Wave 20", "Wave 30", "Wave 50"], 1, func(i): _set_clear_wave(CLEAR_WAVES[i]), Kit.EMERALD)
	_clear_seg.custom_minimum_size.x = 330 if not _compact else 380
	ch.add_child(_clear_seg)
	crow.add_child(Kit.margin(ch, Kit.S2))
	_clear_row = crow
	col.add_child(crow)

	col.add_child(_sec_label("DIFFICULTY"))
	var dg := GridContainer.new()
	dg.columns = 2 if _narrow else 3
	dg.add_theme_constant_override("h_separation", Kit.S2)
	dg.add_theme_constant_override("v_separation", Kit.S2)
	dg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(dg)
	for d in DIFFS:
		var tag := ""
		if Meta.DIFFICULTIES.has(d[0]):
			tag = "CP %.1f" % float(Meta.DIFFICULTIES[d[0]].cp)
		var acc: Color = Kit.CYAN if d[3] == Kit.TEXT else d[3]
		var c := OptCard.new(d[1], d[2], acc, d[3], tag)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var did: String = d[0]
		c.pressed.connect(func(): _set_difficulty(did))
		dg.add_child(c)
		_diff_cards[did] = c
		if d[0] == "easy": _first_focus = c

	_build_custom(col)

func _build_custom(col: VBoxContainer) -> void:
	var pnl := Kit.panel(Kit.VIOLET, Kit.S4)
	pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_panel = pnl
	col.add_child(pnl)
	var b := pnl.body
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", Kit.S2)
	head.add_theme_constant_override("v_separation", Kit.S2)
	head.add_child(Kit.label("CUSTOM PARAMETERS", Kit.FS_MD, Kit.VIOLET.lightened(0.4), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	head.add_child(Kit.spacer(0, Kit.S4))
	for p in PRESETS:
		var pid: String = p[0]
		var pb := Kit.button(p[1], "ghost", func(): _apply_preset(pid))
		pb.custom_minimum_size.y = Kit.btn_h() - 8
		head.add_child(pb)
	b.add_child(head)
	b.add_child(Kit.hsep(Kit.with_a(Kit.VIOLET, 0.3)))

	var grid := GridContainer.new()
	grid.columns = 1 if _narrow else 2
	grid.add_theme_constant_override("h_separation", Kit.S5)
	grid.add_theme_constant_override("v_separation", Kit.S3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_child(grid)
	for s in SLIDERS:
		if s[0] == "levelRate": continue
		grid.add_child(_slider_row(s))
	# boss interval
	var iv := Kit.vbox(4)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iv.add_child(Kit.label("Boss間隔", Kit.FS_SM, Kit.DIM))
	_interval_seg = Kit.segmented(["10 Wave", "5 Wave", "4 Wave", "3 Wave"], 1, func(i): _set_custom("bossInterval", INTERVALS[i]), Kit.VIOLET)
	iv.add_child(_interval_seg)
	grid.add_child(iv)
	# heal
	var hv := Kit.vbox(4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(Kit.label("回復", Kit.FS_SM, Kit.DIM))
	_heal_seg = Kit.segmented(["100%", "50%", "OFF"], 0, func(i): _set_custom("heal", HEALS[i]), Kit.VIOLET)
	hv.add_child(_heal_seg)
	grid.add_child(hv)
	# toggles
	_shield_tg = Kit.toggle(true, func(v): _set_custom("shield", v), Kit.CYAN)
	grid.add_child(Kit.setting_row("Shield/Barrier有効", _shield_tg))
	_onehit_tg = Kit.toggle(false, func(v): _set_custom("oneHit", v), Kit.AMBER)
	grid.add_child(Kit.setting_row("ONE HIT", _onehit_tg))

	b.add_child(Kit.spacer(Kit.S1))
	b.add_child(Kit.label("敵のレベル・編成", Kit.FS_MD, Kit.VIOLET.lightened(0.4), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	b.add_child(Kit.hsep(Kit.with_a(Kit.VIOLET, 0.2)))
	var g2 := GridContainer.new()
	g2.columns = 1 if _narrow else 2
	g2.add_theme_constant_override("h_separation", Kit.S5)
	g2.add_theme_constant_override("v_separation", Kit.S3)
	g2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_child(g2)
	# start level
	var sl := Kit.hbox(Kit.S2)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.add_child(Kit.label("開始敵Lv", Kit.FS_SM, Kit.DIM))
	sl.add_child(Kit.fill_spacer())
	var minus := Kit.button("−", "ghost", func(): _set_custom("startLevel", maxi(1, int(_start_spin.value) - 1)))
	var plus := Kit.button("+", "ghost", func(): _set_custom("startLevel", int(_start_spin.value) + 1))
	minus.custom_minimum_size.x = Kit.btn_h(); plus.custom_minimum_size.x = Kit.btn_h()
	_start_spin = SpinBox.new()
	_start_spin.min_value = 1; _start_spin.max_value = 10000; _start_spin.step = 1; _start_spin.rounded = true
	_start_spin.custom_minimum_size = Vector2(110, Kit.btn_h())
	_start_spin.value_changed.connect(func(v): if not _syncing: _set_custom("startLevel", int(v)))
	sl.add_child(minus); sl.add_child(_start_spin); sl.add_child(plus)
	g2.add_child(sl)
	g2.add_child(_slider_row(SLIDERS[5]))
	# roster
	var rv := Kit.vbox(4)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(Kit.label("敵の編成", Kit.FS_SM, Kit.DIM))
	_roster_seg = Kit.segmented(["通常編成（Lvで種類解放）", "選んだ通常敵のみ", "全敵ボス / ALL BOSS"], 0, func(i): _set_custom("rosterMode", ROSTERS[i]), Kit.VIOLET)
	rv.add_child(_roster_seg)
	b.add_child(rv)
	b.add_child(Kit.label("開始するのはWave 1のままです。敵Lvだけを上げます。成長値が2を超えるとWave経過で加速。移動速度は変わりません。", Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))

	# enemy picker
	var ep := Kit.vbox(Kit.S2)
	_enemy_panel = ep
	var eh := Kit.hbox(Kit.S2)
	eh.add_child(Kit.label("出現する通常敵", Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	eh.add_child(Kit.fill_spacer())
	var a := Kit.button("全選択", "ghost", func(): _set_custom("enemyTypes", Meta.CUSTOM_ENEMY_IDS.duplicate()); _sync_inputs())
	var n := Kit.button("全解除", "ghost", func(): _set_custom("enemyTypes", []); _sync_inputs())
	a.custom_minimum_size.y = Kit.btn_h() - 8; n.custom_minimum_size.y = Kit.btn_h() - 8
	eh.add_child(a); eh.add_child(n)
	ep.add_child(eh)
	var ef := HFlowContainer.new()
	ef.add_theme_constant_override("h_separation", Kit.S2)
	ef.add_theme_constant_override("v_separation", Kit.S2)
	for id in Meta.CUSTOM_ENEMY_IDS:
		var ch := Chip.new(str(Enemies.ENEMY_TYPES[id].get("name", id)), Kit.CYAN)
		var eid: String = id
		ch.toggled.connect(func(_on): if not _syncing: _read_chips())
		ef.add_child(ch)
		_enemy_chips[eid] = ch
	ep.add_child(ef)
	ep.add_child(Kit.label("選択した種類を最初から出します。ボス召喚・分裂も選択外の敵は生成しません。", Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
	b.add_child(ep)

	# boss
	var bh := Kit.hbox(Kit.S3)
	_boss_en_tg = Kit.toggle(true, func(v): _set_custom("bossEnabled", v), Kit.VIOLET)
	bh.add_child(Kit.label("定期ボスを出現させる", Kit.FS_MD, Kit.TEXT))
	bh.add_child(Kit.fill_spacer())
	_boss_en_tg.size_flags_horizontal = Control.SIZE_SHRINK_END
	bh.add_child(_boss_en_tg)
	b.add_child(bh)
	var bl := Kit.hbox(Kit.S3)
	bl.add_child(Kit.label("同時ボス", Kit.FS_SM, Kit.DIM))
	_boss_limit_seg = Kit.segmented(["1体", "2体", "3体"], 1, func(i): _set_custom("bossLimit", i + 1), Kit.VIOLET)
	_boss_limit_seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bl.add_child(_boss_limit_seg)
	_boss_limit_row = bl
	b.add_child(bl)
	var bf := HFlowContainer.new()
	bf.add_theme_constant_override("h_separation", Kit.S2)
	bf.add_theme_constant_override("v_separation", Kit.S2)
	for id in Meta.CUSTOM_BOSS_IDS:
		var bc := Chip.new(str(BOSS_NAMES.get(id, id)), Kit.ROSE)
		bc.toggled.connect(func(_on): if not _syncing: _read_chips())
		bf.add_child(bc)
		_boss_chips[id] = bc
	b.add_child(bf)
	_boss_note = Kit.label("", Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true)
	b.add_child(_boss_note)

func _slider_row(s: Array) -> Control:
	var key: String = s[0]
	var v := Kit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := Kit.hbox(Kit.S2)
	h.add_child(Kit.label(s[1], Kit.FS_SM, Kit.DIM))
	h.add_child(Kit.fill_spacer())
	var val := Kit.label("", Kit.FS_SM, Kit.CYAN.lightened(0.3), HORIZONTAL_ALIGNMENT_RIGHT, false, true)
	h.add_child(val)
	v.add_child(h)
	var sl := Kit.slider(s[2], s[3], s[4], float(Meta.runConfig.custom.get(key, 1.0)), func(x): if not _syncing: _set_custom(key, x))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size.x = 120
	v.add_child(sl)
	_sliders[key] = sl
	_slider_vals[key] = val
	return v

func _stat_cell(title: String, key: String, col: Color = Kit.TEXT) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.06), 1, 8))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Kit.vbox(0)
	v.add_child(Kit.label(title, Kit.FS_XS, Kit.DIM))
	var val := Kit.label("×1.00", Kit.FS_MD, col, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	v.add_child(val)
	p.add_child(Kit.margin(v, Kit.S2))
	_stat_vals[key] = val
	return p

func _build_summary(col: VBoxContainer) -> void:
	var pnl := Kit.panel(Kit.CYAN, Kit.S4)
	pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(pnl)
	var b := pnl.body
	b.add_child(Kit.label("CHALLENGE POWER", Kit.FS_XS, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	var cprow := Kit.hbox(Kit.S2)
	_cp_lbl = Kit.label("1.00", Kit.FS_3XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	cprow.add_child(_cp_lbl)
	var unit := Kit.label("CP", Kit.FS_SM, Kit.MUTE)
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	cprow.add_child(unit)
	b.add_child(cprow)
	_diff_lbl = Kit.label("EASY", Kit.FS_MD, Kit.CYAN.lightened(0.5), HORIZONTAL_ALIGNMENT_LEFT, false, true)
	b.add_child(_diff_lbl)
	var sg := GridContainer.new()
	sg.columns = 2
	sg.add_theme_constant_override("h_separation", Kit.S2)
	sg.add_theme_constant_override("v_separation", Kit.S2)
	sg.add_child(_stat_cell("Reward", "reward", Kit.AMBER))
	var spd := _stat_cell("敵速度", "speed", Kit.EMERALD)
	sg.add_child(spd)
	sg.add_child(_stat_cell("敵密度", "density"))
	sg.add_child(_stat_cell("HP成長", "hpGrowth"))
	sg.add_child(_stat_cell("火力成長", "damageGrowth"))
	sg.add_child(_stat_cell("攻撃密度", "attack"))
	b.add_child(sg)
	_rules_box = Kit.vbox(2)
	b.add_child(_rules_box)
	b.add_child(Kit.hsep())
	_growth_title = Kit.label("", Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, true)
	b.add_child(_growth_title)
	_growth_grid = GridContainer.new()
	_growth_grid.columns = 4
	_growth_grid.add_theme_constant_override("h_separation", Kit.S3)
	_growth_grid.add_theme_constant_override("v_separation", 3)
	_growth_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_child(_growth_grid)
	_err_lbl = Kit.label("", Kit.FS_SM, Kit.ROSE, HORIZONTAL_ALIGNMENT_LEFT, true, true)
	b.add_child(_err_lbl)

	var gp := Kit.panel(Kit.EMERALD, Kit.S3)
	gp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(gp)
	gp.body.add_child(Kit.label("PLAYER GROWTH", Kit.FS_XS, Kit.EMERALD, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_grow_lbl = Kit.label("", Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	gp.body.add_child(_grow_lbl)
	gp.body.add_child(Kit.button("成長の適用Lvを調整 →", "success", _on_growth_edit))

# ------------------------------------------------------------------ state <-> widgets
func _cfg() -> Dictionary:
	return Meta.runConfig

func _set_mode(m: String) -> void:
	_cfg().mode = m
	_sync_inputs()

func _set_difficulty(d: String) -> void:
	_cfg().difficulty = d
	_sync_inputs()

func _set_clear_wave(w: int) -> void:
	_cfg().clearWave = w
	_update_preview()

func _set_custom(key: String, v: Variant) -> void:
	_cfg().custom[key] = v
	_cfg().custom = Meta.cleanCustomConfig(_cfg().custom)
	_sync_inputs()

func _read_chips() -> void:
	var et: Array = []
	for id in Meta.CUSTOM_ENEMY_IDS:
		if _enemy_chips.has(id) and (_enemy_chips[id] as Button).button_pressed: et.append(id)
	var bt: Array = []
	for id in Meta.CUSTOM_BOSS_IDS:
		if _boss_chips.has(id) and (_boss_chips[id] as Button).button_pressed: bt.append(id)
	_cfg().custom.enemyTypes = et
	_cfg().custom.bossTypes = bt
	_cfg().custom = Meta.cleanCustomConfig(_cfg().custom)
	_update_preview()

func _apply_preset(name: String) -> void:
	var d: Dictionary = Meta.defaultRunConfig().custom
	var presets := {
		"swarm": {"density": 3.2, "hpGrowth": 1.5, "damageGrowth": 1.3, "elite": 1.8, "attack": 1.2},
		"bullet": {"density": 1.8, "hpGrowth": 1.8, "damageGrowth": 2.2, "elite": 2.4, "attack": 3.0, "bossInterval": 4, "heal": 0.5},
		"boss": {"density": 1.3, "hpGrowth": 3.4, "damageGrowth": 2.3, "elite": 1.8, "attack": 2.1, "bossInterval": 3, "heal": 0.5},
		"onehit": {"density": 2.3, "hpGrowth": 2.5, "damageGrowth": 2.5, "elite": 2.8, "attack": 2.2, "bossInterval": 4, "shield": false, "heal": 0.0, "oneHit": true, "levelRate": 6.0},
		"allboss": {"rosterMode": "bossOnly", "bossLimit": 2, "density": 1.5, "hpGrowth": 2.0, "damageGrowth": 2.0, "levelRate": 3.0},
		"maximum": {"density": 3.5, "hpGrowth": 8.0, "damageGrowth": 8.0, "elite": 4.0, "attack": 3.0, "bossInterval": 3, "levelRate": 12.0, "shield": false, "heal": 0.0, "startLevel": 100},
	}
	if not presets.has(name): return
	_cfg().difficulty = "custom"
	var c: Dictionary = d.duplicate(true)
	for k in presets[name]: c[k] = presets[name][k]
	_cfg().custom = Meta.cleanCustomConfig(c)
	_sync_inputs()

## Push Meta.runConfig into every widget (no signals), then refresh preview.
func _sync_inputs() -> void:
	if _start_btn == null: return
	_syncing = true
	Meta.runConfig = Meta.cleanRunConfig(Meta.runConfig)
	var rc: Dictionary = Meta.runConfig
	for id in _mode_cards: (_mode_cards[id] as OptCard).selected = (rc.mode == id)
	for id in _diff_cards: (_diff_cards[id] as OptCard).selected = (rc.difficulty == id)
	_clear_row.visible = rc.mode == "clear"
	_clear_seg.set_index(CLEAR_WAVES.find(int(rc.clearWave)))
	_custom_panel.visible = rc.difficulty == "custom"
	var c: Dictionary = rc.custom
	for k in _sliders:
		(_sliders[k] as HSlider).set_value_no_signal(float(c[k]))
	_interval_seg.set_index(INTERVALS.find(int(c.bossInterval)))
	_heal_seg.set_index(_heal_index(float(c.heal)))
	_shield_tg.set_value(bool(c.shield))
	_onehit_tg.set_value(bool(c.oneHit))
	_start_spin.set_value_no_signal(float(c.startLevel))
	_roster_seg.set_index(ROSTERS.find(str(c.rosterMode)))
	_boss_en_tg.set_value(bool(c.bossEnabled))
	_boss_limit_seg.set_index(int(c.bossLimit) - 1)
	for id in _enemy_chips: (_enemy_chips[id] as Button).set_pressed_no_signal(c.enemyTypes.has(id))
	for id in _boss_chips: (_boss_chips[id] as Button).set_pressed_no_signal(c.bossTypes.has(id))
	_syncing = false
	_update_preview()

func _heal_index(h: float) -> int:
	for i in HEALS.size():
		if is_equal_approx(HEALS[i], h): return i
	return -1

func _dis(ctrl: Control, off: bool) -> void:
	ctrl.modulate.a = 0.35 if off else 1.0
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE if off else Control.MOUSE_FILTER_STOP if ctrl is Kit.NeonToggle else Control.MOUSE_FILTER_PASS
	if ctrl is Kit.NeonToggle: ctrl.focus_mode = Control.FOCUS_NONE if off else Control.FOCUS_ALL
	for ch in ctrl.get_children():
		if ch is BaseButton: (ch as BaseButton).disabled = off

func _fmt_slider(key: String, v: float) -> String:
	return "%.1f%s" % [v, " / Wave" if key == "levelRate" else "x"]

func _update_preview() -> void:
	if _cp_lbl == null: return
	var rc: Dictionary = Meta.runConfig
	var cus: Dictionary = rc.custom
	var c: Dictionary = Meta.challenge()
	for k in _slider_vals:
		(_slider_vals[k] as Label).text = _fmt_slider(k, float(cus[k]))
	var boss_only: bool = cus.rosterMode == "bossOnly"
	_enemy_panel.visible = cus.rosterMode == "selected"
	_boss_limit_row.visible = boss_only
	_dis(_boss_en_tg, boss_only)
	_dis(_interval_seg, boss_only)
	_boss_note.text = "通常敵・支援召喚・分裂は出ません。撃破後に補充、最終Waveは残存ボス全滅でクリア。" if boss_only \
		else "選んだボスが交代で出現。同時1体。定期ボスOFFでもCLEAR最終戦には出現。"
	_cp_lbl.text = "%.2f" % float(c.cp)
	_stat_vals.reward.text = "×%.2f" % Meta.challengeReward()
	_stat_vals.speed.text = "×1.00"
	_diff_lbl.text = str(c.label)
	for k in ["density", "hpGrowth", "damageGrowth", "attack"]:
		(_stat_vals[k] as Label).text = "×%.2f" % float(c[k])
	# rules
	for ch in _rules_box.get_children(): ch.queue_free()
	var boss_line: String = ("全敵ボス / 同時 %d体" % Enemies.maxConcurrentBosses()) if boss_only \
		else ("定期ボス %s" % ("OFF" if c.get("bossEnabled", true) == false else "%d Waveごと" % int(c.bossInterval)))
	var lines := [
		"移動速度 変化なし",
		"開始敵Lv %s / 成長 %s" % [str(int(c.get("startLevel", 1))), _num_s(float(c.get("levelRate", 2)))],
		boss_line,
		"Shield %s / Heal %d%%%s" % ["ON" if c.shield else "OFF", roundi(float(c.heal) * 100.0), " / ONE HIT" if c.oneHit else ""],
		("Final Wave %s" % str(Meta.finalWaveTarget())) if rc.mode == "clear" else "ENDLESS",
		"CP・報酬には既存の上限あり。敵種の選別だけでは報酬倍率を加算しません。",
	]
	for i in lines.size():
		_rules_box.add_child(Kit.label(lines[i], Kit.FS_XS, Kit.EMERALD.lightened(0.3) if i == 0 else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	# growth preview
	_growth_title.text = "敵の成長予測（%s基準）" % ("ボス" if boss_only else "通常敵")
	for ch in _growth_grid.get_children(): ch.queue_free()
	for h in ["Wave", "敵Lv", "HP", "火力"]:
		_growth_grid.add_child(Kit.label(h, Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_RIGHT if h != "Wave" else HORIZONTAL_ALIGNMENT_LEFT, false, true))
	for w in [1, 10, 20, 50]:
		var lv: int = Enemies.enemyLevelForWave(w, c)
		var v: Dictionary = Enemies.enemyScaling(lv, boss_only, c)
		_growth_grid.add_child(Kit.label(str(w), Kit.FS_SM, Kit.DIM))
		_growth_grid.add_child(Kit.label(Meta.researchNumber(lv), Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, false, true))
		_growth_grid.add_child(Kit.label("×" + Meta.researchNumber(v.hp), Kit.FS_SM, Kit.ROSE.lightened(0.2), HORIZONTAL_ALIGNMENT_RIGHT, false, true))
		_growth_grid.add_child(Kit.label("即死" if c.oneHit else "×" + Meta.researchNumber(v.damage), Kit.FS_SM, Kit.AMBER, HORIZONTAL_ALIGNMENT_RIGHT, false, true))
	var err: String = Enemies.validateRunSetup()
	_err_lbl.text = err
	_start_btn.disabled = err != ""
	_grow_lbl.text = Meta.growthSummary()
	Meta.saveRunConfig()

func _num_s(f: float) -> String:
	return str(int(f)) if is_equal_approx(f, floorf(f)) else str(snappedf(f, 0.01))

# ------------------------------------------------------------------ actions
func _on_growth_edit() -> void:
	Meta.saveRunConfig()
	Meta.openMeta("config")
	UI.hook("openGrowthTab", ["config"])

func _on_start() -> void:
	Meta.runConfig = Meta.cleanRunConfig(Meta.runConfig)
	if Enemies.validateRunSetup() != "":
		_update_preview()
		return
	Meta.saveRunConfig()
	if Game.resetGame():
		UI.hide_screen("runconfig")
	else:
		_update_preview()
