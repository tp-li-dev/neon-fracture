extends NFScreen
## #startScreen — title / mode select / how-to / meta / settings / CONTINUE (suspended run).
## Original: index.html 4598-4696 (HTML), 10396-10512 (suspend logic -> RunSave in run_save.gd).
## Hooks: showHome, syncResumeEntry, startRunSession, clearRunSession, markSessionSettled, sessionAlreadySettled,
##        refreshMetaUI (broadcast).  Shown automatically at boot while Game.state == "menu".

var _compact := false
var _wide := true
var _lv_lbl: Label
var _xp_bar: Kit.NeonBar
var _xp_lbl: Label
var _cr_lbl: Label
var _data_lbl: Label
var _high_lbl: Label
var _wave_lbl: Label
var _resume_info: Label
var _resume_btn: Kit.NeonButton
var _import_btn: Kit.NeonButton
var _discard_btn: Kit.NeonButton
var _import_box: Control
var _import_info: Label
var _fd: FileDialog
var _pending_import: Dictionary = {}
var _discard_armed := false
var _start_btn: Kit.NeonButton
var _ambient: Control

# ------------------------------------------------------------------ decorative
class Ambient extends Control:
	var t := 0.0
	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(dt: float) -> void:
		if not is_visible_in_tree(): return
		t += dt
		queue_redraw()
	func _glow(c: Vector2, r: float, col: Color) -> void:
		for i in 14:
			var k := float(i) / 13.0
			draw_circle(c, r * (1.0 - k * 0.92), Color(col.r, col.g, col.b, col.a * 0.07))
	func _draw() -> void:
		var s := size
		var p := 0.5 + 0.5 * sin(t * 0.8)
		_glow(Vector2(s.x * 0.08, s.y * 0.02), minf(s.x, s.y) * (0.62 + 0.05 * p), Color(0.13, 0.83, 0.93, 0.55))
		_glow(Vector2(s.x * 0.96, s.y * 0.98), minf(s.x, s.y) * (0.70 + 0.05 * (1.0 - p)), Color(0.65, 0.54, 0.98, 0.60))
		# faint grid
		var gc := Color(0.4, 0.8, 1.0, 0.035)
		var step := 64.0
		var off := fmod(t * 6.0, step)
		var x := -off
		while x < s.x:
			draw_line(Vector2(x, 0), Vector2(x, s.y), gc, 1.0)
			x += step
		var y := -off
		while y < s.y:
			draw_line(Vector2(0, y), Vector2(s.x, y), gc, 1.0)
			y += step
		# watermark N
		var f := Kit.font(true)
		draw_string(f, Vector2(s.x * 0.52, s.y * 0.92), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s.y * 0.95), Color(1, 1, 1, 0.014))

class TitleArt extends Control:
	var compact := false
	func _init(c: bool = false) -> void:
		compact = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fs := 56 if c else 104
		custom_minimum_size = Vector2(0, fs * (1.0 if c else 1.85))
		if c: custom_minimum_size.y = fs * 1.05
	func _draw() -> void:
		var f := Kit.font(true)
		var fs := 56 if compact else 104
		if compact:
			var x := _line("NEON", Vector2(0, fs * 0.86), f, fs, false)
			_line("FRACTURE", Vector2(x + 16, fs * 0.86), f, fs, true)
		else:
			_line("NEON", Vector2(0, fs * 0.82), f, fs, false)
			_line("FRACTURE", Vector2(0, fs * 1.72), f, fs, true)
	func _line(txt: String, pos: Vector2, f: Font, fs: int, grad: bool) -> float:
		var x := pos.x
		var n := txt.length()
		for i in n:
			var ch := txt[i]
			var k := float(i) / maxf(1.0, float(n - 1))
			var col := Color.WHITE
			if grad:
				col = Kit.CYAN.lerp(Color("#60a5fa"), clampf(k * 2.0, 0.0, 1.0)) if k < 0.5 else Color("#60a5fa").lerp(Kit.VIOLET, (k - 0.5) * 2.0)
			var adv := f.get_char_size(ch.unicode_at(0), fs).x * 0.96
			if grad:
				draw_char(f, Vector2(x, pos.y) + Vector2(0, 0), ch, fs, Color(col.r, col.g, col.b, 0.12))
				draw_char(f, Vector2(x + 3, pos.y + 3), ch, fs, Color(col.r, col.g, col.b, 0.10))
				draw_char(f, Vector2(x - 3, pos.y - 2), ch, fs, Color(col.r, col.g, col.b, 0.10))
			draw_char(f, Vector2(x, pos.y), ch, fs, col)
			x += adv
		return x

# ------------------------------------------------------------------ lifecycle
func build() -> void:
	modal = true
	dim_alpha = 0.0
	layer_z = 0
	_ambient = Ambient.new()
	add_child(_ambient)
	move_child(_ambient, 0)
	get_viewport().size_changed.connect(_on_resize)
	_fd = FileDialog.new()
	_fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_fd.access = FileDialog.ACCESS_FILESYSTEM
	_fd.use_native_dialog = true
	_fd.title = "中断JSONを選択"
	_fd.filters = PackedStringArray(["*.json ; 中断セーブ JSON"])
	_fd.file_selected.connect(_on_import_file)
	add_child(_fd)
	_rebuild()
	call_deferred("_auto_open")

func _auto_open() -> void:
	for i in 3: await get_tree().process_frame
	if OS.get_environment("NF_SCREEN") != "" or OS.get_environment("NF_SHOT") != "": return
	if Game.state == "menu" and UI.top_screen() == "" and not is_open:
		UI.show_screen("home")

func _on_resize() -> void:
	if is_open and (Kit.is_compact() != _compact or (get_viewport_rect().size.x >= 1000.0) != _wide):
		_rebuild()
		_refresh()

func on_open(_args: Dictionary = {}) -> void:
	if Kit.is_compact() != _compact or (get_viewport_rect().size.x >= 1000.0) != _wide:
		_rebuild()
	_pending_import = {}
	_import_box.visible = false
	_refresh()

func _rebuild() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	_compact = Kit.is_compact()
	_wide = get_viewport_rect().size.x >= 1000.0
	_build_ui()

# ------------------------------------------------------------------ hooks
func h_showHome() -> void:
	Game.state = "menu"
	UI.goto("home")

func h_syncResumeEntry() -> void:
	if _resume_btn != null: _refresh_resume()

func h_startRunSession() -> void:
	RunSave.start_session()

func h_clearRunSession() -> void:
	RunSave.clear_session()

func h_markSessionSettled() -> void:
	RunSave.mark_session_settled()

func h_sessionAlreadySettled() -> bool:
	return RunSave.session_already_settled()

func b_refreshMetaUI() -> void:
	if _lv_lbl != null: _refresh()

func b_resetGameUI(_touch = null) -> void:
	if is_open: UI.hide_screen("home")

func b_openMeta(_from = null) -> void:
	if is_open: UI.hide_screen("home")

func b_closeMeta() -> void:
	call_deferred("_after_meta")

func _after_meta() -> void:
	if Game.state == "menu" and not is_open:
		UI.goto("home")

# ------------------------------------------------------------------ UI
func _cap(t: String) -> Control:
	var p := PanelContainer.new()
	var sb := Kit.box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.20), 1, 5)
	sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 2; sb.content_margin_bottom = 3
	sb.border_width_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(Kit.label(t, Kit.FS_XS, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, false, true))
	return p

func _control_row(title: String, sub: String, keys: Array) -> Control:
	var h := Kit.hbox(Kit.S3)
	var v := Kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(Kit.label(title, Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	v.add_child(Kit.label(sub, Kit.FS_XS, Kit.MUTE))
	h.add_child(v)
	var kb := Kit.hbox(4)
	kb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for k in keys: kb.add_child(_cap(k))
	h.add_child(kb)
	return h

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	content.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size.y = 0
	scroll.add_child(center)
	var vp := get_viewport_rect().size
	var row: BoxContainer = HBoxContainer.new() if _wide else VBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.S5)
	row.custom_minimum_size.x = minf(1280.0, vp.x - 40.0)
	center.add_child(row)

	# ---------------- main card
	var main := Kit.panel(Kit.CYAN, Kit.S5 if _compact else Kit.S6)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_stretch_ratio = 1.3
	row.add_child(main)
	var b := main.body
	b.add_theme_constant_override("separation", Kit.S3 if _compact else Kit.S4)
	var eb := Kit.hbox(Kit.S3)
	var dot := ColorRect.new()
	dot.color = Kit.CYAN
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eb.add_child(dot)
	eb.add_child(Kit.label("ネオン・アリーナ・ローグライト", Kit.FS_XS, Kit.CYAN.lightened(0.4), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	b.add_child(eb)
	b.add_child(TitleArt.new(_compact))
	if not _compact:
		b.add_child(Kit.label("有限の巨大ネオンフィールドを駆け回り、押し寄せる敵を撃ち抜いて能力を組み替える。\n一瞬の判断とビルド構築を混ぜた、短時間で何度も遊べるアリーナ・ローグライト。", Kit.FS_MD, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))

	# action buttons
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", Kit.S3)
	acts.add_theme_constant_override("v_separation", Kit.S3)
	_start_btn = Kit.button("モード選択  →", "cta", func(): UI.hook("openRunConfig"))
	_start_btn.custom_minimum_size.x = 210 if not _compact else 190
	acts.add_child(_start_btn)
	var how := Kit.button("遊び方を見る", "ghost", func(): UI.hook("openHow"))
	acts.add_child(how)
	var meta := Kit.button("研究・カード工房", "primary", func(): Meta.openMeta("menu"))
	meta.set_kind("primary", Kit.AMBER)
	acts.add_child(meta)
	acts.add_child(Kit.button("音声・設定", "ghost", func(): UI.hook("openUtility", ["audio"])))
	b.add_child(acts)
	default_focus = _start_btn

	# continue box
	var cb := PanelContainer.new()
	cb.add_theme_stylebox_override("panel", Kit.box(Kit.with_a(Kit.CYAN, 0.04), Kit.with_a(Kit.CYAN, 0.22), 1, 10))
	var cv := Kit.vbox(Kit.S2)
	cb.add_child(Kit.margin(cv, Kit.S3))
	cv.add_child(Kit.label("CONTINUE / 中断再開", Kit.FS_XS, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_resume_info = Kit.label("", Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	cv.add_child(_resume_info)
	var cr := HFlowContainer.new()
	cr.add_theme_constant_override("h_separation", Kit.S2)
	cr.add_theme_constant_override("v_separation", Kit.S2)
	_resume_btn = Kit.button("続きから", "success", _on_resume)
	_import_btn = Kit.button("中断JSON読込", "ghost", func(): _fd.popup_centered_ratio(0.7))
	_discard_btn = Kit.button("破棄", "danger", _on_discard)
	cr.add_child(_resume_btn); cr.add_child(_import_btn); cr.add_child(_discard_btn)
	cv.add_child(cr)
	var ib := Kit.vbox(Kit.S2)
	_import_info = Kit.label("", Kit.FS_SM, Kit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, true)
	ib.add_child(_import_info)
	var ibr := Kit.hbox(Kit.S2)
	ibr.add_child(Kit.button("中断枠に読み込む", "primary", _on_apply_import))
	ibr.add_child(Kit.button("取消", "ghost", func(): _pending_import = {}; _import_box.visible = false))
	ib.add_child(ibr)
	_import_box = ib
	ib.visible = false
	cv.add_child(ib)
	b.add_child(cb)

	# player summary strip
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", Kit.box(Kit.with_a(Kit.AMBER, 0.035), Kit.with_a(Kit.AMBER, 0.12), 1, 12))
	var sg := Kit.hbox(Kit.S4)
	strip.add_child(Kit.margin(sg, Kit.S3 if _compact else Kit.S4))
	var c1 := Kit.vbox(3)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c1.add_child(Kit.label("PLAYER LEVEL", Kit.FS_XS, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_lv_lbl = Kit.label("Lv.1", Kit.FS_XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	c1.add_child(_lv_lbl)
	_xp_bar = Kit.bar(0.0, Kit.CYAN, "", 8)
	c1.add_child(_xp_bar)
	_xp_lbl = Kit.label("0 / 0 XP", Kit.FS_XS, Kit.MUTE)
	c1.add_child(_xp_lbl)
	sg.add_child(c1)
	sg.add_child(_vline())
	var c2 := Kit.vbox(3)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c2.add_child(Kit.label("所持クレジット", Kit.FS_XS, Kit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	var r2 := Kit.hbox(6)
	_cr_lbl = Kit.label("0", Kit.FS_XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	r2.add_child(_cr_lbl)
	r2.add_child(Kit.label("CR", Kit.FS_SM, Kit.AMBER))
	c2.add_child(r2)
	c2.add_child(Kit.label("研究専用", Kit.FS_XS, Kit.MUTE))
	sg.add_child(c2)
	sg.add_child(_vline())
	var c3 := Kit.vbox(3)
	c3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c3.add_child(Kit.label("解析データ", Kit.FS_XS, Kit.VIOLET, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	var r3 := Kit.hbox(6)
	_data_lbl = Kit.label("0", Kit.FS_XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	r3.add_child(_data_lbl)
	r3.add_child(Kit.label("DATA", Kit.FS_SM, Kit.VIOLET))
	c3.add_child(r3)
	c3.add_child(Kit.label("ガチャ専用", Kit.FS_XS, Kit.MUTE))
	sg.add_child(c3)
	b.add_child(strip)

	# stats
	b.add_child(Kit.hsep())
	var st := HFlowContainer.new()
	st.add_theme_constant_override("h_separation", Kit.S5)
	st.add_theme_constant_override("v_separation", Kit.S1)
	var h1 := Kit.hbox(8)
	h1.add_child(Kit.label("ハイスコア", Kit.FS_SM, Kit.MUTE))
	_high_lbl = Kit.label("0", Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	h1.add_child(_high_lbl)
	st.add_child(h1)
	var h2 := Kit.hbox(8)
	h2.add_child(Kit.label("最高ウェーブ", Kit.FS_SM, Kit.MUTE))
	_wave_lbl = Kit.label("0", Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	h2.add_child(_wave_lbl)
	st.add_child(h2)
	st.add_child(Kit.label("固定16:9仮想盤面 / 解像度による視界差なし", Kit.FS_SM, Kit.MUTE))
	st.add_child(Kit.label("%s · RESUME & DRONE CONTROL" % Meta.GAME_VERSION, Kit.FS_SM, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	b.add_child(st)

	# ---------------- help card
	var help := Kit.panel(Kit.VIOLET, Kit.S5 if _compact else Kit.S6)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help.size_flags_stretch_ratio = 0.7
	row.add_child(help)
	var hb := help.body
	hb.add_theme_constant_override("separation", Kit.S4 if not _compact else Kit.S3)
	hb.add_child(Kit.label("操作方法", Kit.FS_XS, Kit.VIOLET, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	hb.add_child(_control_row("移動", "止まると包囲される", ["W", "A", "S", "D"]))
	hb.add_child(_control_row("照準・射撃", "マウス方向へ自動照準", ["マウス", "左クリック"]))
	hb.add_child(_control_row("ダッシュ", "短時間だけ無敵", ["SPACE"]))
	hb.add_child(_control_row("ポーズ", "戦略を立て直す", ["ESC"]))
	hb.add_child(Kit.hsep())
	var mo := Kit.hbox(Kit.S3)
	var mv := Kit.vbox(0)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.add_child(Kit.label("モバイル操作", Kit.FS_MD, Kit.CYAN.lightened(0.5), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	mv.add_child(Kit.label("左操作エリアを長押し: 移動 / 右操作エリアを長押し: 照準＋射撃", Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
	mo.add_child(mv)
	mo.add_child(Kit.label("横画面", Kit.FS_XS, Kit.CYAN, HORIZONTAL_ALIGNMENT_RIGHT, false, true))
	hb.add_child(mo)
	if not _compact or not _wide:
		var fl := PanelContainer.new()
		fl.add_theme_stylebox_override("panel", Kit.box(Kit.with_a(Kit.CYAN, 0.06), Kit.with_a(Color.WHITE, 0.08), 1, 12))
		var fv := Kit.vbox(4)
		fl.add_child(Kit.margin(fv, Kit.S4))
		fv.add_child(Kit.label("ゲームの流れ", Kit.FS_XS, Kit.CYAN.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT, false, true))
		fv.add_child(Kit.label("探索する → フローフィールドを使って位置を変える → 敵を倒す → カードと能力を組む → ボスを撃破する。", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		hb.add_child(Kit.fill_spacer())
		hb.add_child(fl)

func _vline() -> Control:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.08)
	c.custom_minimum_size = Vector2(1, 0)
	return c

# ------------------------------------------------------------------ refresh
func _refresh() -> void:
	if _lv_lbl == null: return
	var m: Dictionary = Meta.meta
	var lv: int = int(m.get("playerLevel", 1))
	var need: int = max(1, int(Meta.playerXpNeeded(lv)))
	var xp: float = float(m.get("playerXp", 0.0))
	_lv_lbl.text = "Lv.%s" % Kit.num(lv)
	_xp_bar.set_value_instant(clampf(xp / float(need), 0.0, 1.0))
	_xp_lbl.text = "%s / %s XP" % [Kit.num(floorf(xp)), Kit.num(need)]
	_cr_lbl.text = Kit.num(m.get("credits", 0))
	_data_lbl.text = Kit.num(m.get("data", 0))
	_high_lbl.text = Kit.num(Game.save.high)
	_wave_lbl.text = Kit.num(Game.save.wave)
	_refresh_resume()

func _refresh_resume() -> void:
	var p := RunSave.read()
	_resume_info.text = RunSave.summary_text(p)
	_resume_btn.disabled = p.is_empty()
	_discard_btn.disabled = p.is_empty()
	_resume_btn.text = "続きから再開" if not p.is_empty() else "続きから"
	_discard_armed = false
	_discard_btn.text = "破棄"

# ------------------------------------------------------------------ actions
func _on_resume() -> void:
	var err := RunSave.restore()
	if err != "":
		Inp.showInputNotice("再開できません: " + err, 6500)
		return
	UI.toast("中断セーブを復元しました。「ゲームに戻る」で再開します。", "ok", 3200)

func _on_discard() -> void:
	if not _discard_armed:
		_discard_armed = true
		_discard_btn.text = "もう一度で破棄"
		get_tree().create_timer(4.0).timeout.connect(func():
			if _discard_armed and is_instance_valid(_discard_btn):
				_discard_armed = false
				_discard_btn.text = "破棄")
		return
	RunSave.clear()
	_discard_armed = false
	_discard_btn.text = "破棄"
	_refresh_resume()

func _on_import_file(path: String) -> void:
	var r := RunSave.read_file(path)
	if r.has("error"):
		Inp.showInputNotice("中断JSONを読み込めません: " + str(r.error), 6500)
		return
	_pending_import = r.payload
	var w: Variant = _pending_import.get("summary", {}).get("wave", "?")
	_import_info.text = "Wave %s の中断データを読み込みました。現在の中断枠を置き換えます。" % str(w)
	_import_box.visible = true

func _on_apply_import() -> void:
	if _pending_import.is_empty(): return
	var v := RunSave.validate(_pending_import)
	if v.has("error"):
		Inp.showInputNotice(str(v.error), 5000)
		return
	var err := RunSave.persist(_pending_import)
	if err != "":
		RunSave.memory = _pending_import
		Inp.showInputNotice("永続保存できません。この起動中のみ再開できます。元のJSONを保持してください", 5000)
	_pending_import = {}
	_import_box.visible = false
	_refresh_resume()
