extends NFScreen
## #utilityScreen — 音声 / 操作 / 開発者 (診断 + 実験ラン).
## Original: index.html 5175-5250 (HTML), 9928-10272 (JS: openUtility/closeUtility/setUtilityTab/renderTools/developer*).
## Hooks: openUtility(tab), closeUtility, setUtilityTab(tab); broadcast: syncInputSettings, utilityMessage (footer text),
## resetGameUI. Game.state == "tools" while open; the previous state is restored on close.
## Browser-only parts (Web Audio engine details, DOM diagnostics, UA / storage probe) are replaced by Godot equivalents.

const VOLUMES := [["master", "全体"], ["shots", "本体の射撃"], ["drones", "ドローン"], ["skills", "スキル・ビーム・爆発"], ["feedback", "被弾・敵・警告"], ["ui", "UI・カード・XP取得"]]
const DEV_STAT_FIELDS := [
	{"key": "damage", "label": "本体ダメージ", "min": 0.1, "max": 1e12, "int": false},
	{"key": "maxHp", "label": "最大HP", "min": 1.0, "max": 1e12, "int": false},
	{"key": "fireRate", "label": "発射回数 / 秒", "min": 0.1, "max": 1e6, "int": false},
	{"key": "multishot", "label": "一度の弾数", "min": 1.0, "max": 1e6, "int": true},
	{"key": "pierce", "label": "貫通回数", "min": 0.0, "max": 10000.0, "int": true},
	{"key": "bulletBounces", "label": "反射回数", "min": 0.0, "max": 10000.0, "int": true},
	{"key": "droneCount", "label": "ドローン論理機数", "min": 0.0, "max": 10000.0, "int": true},
	{"key": "droneDamage", "label": "ドローン専用火力", "min": 0.1, "max": 1e12, "int": false},
	{"key": "activePower", "label": "スキル出力倍率", "min": 0.05, "max": 1e6, "int": false},
	{"key": "activeHaste", "label": "スキル再使用効率", "min": 0.0, "max": 10000.0, "int": false},
	{"key": "beamPower", "label": "ビーム威力倍率", "min": 0.05, "max": 1e6, "int": false},
	{"key": "chargeEfficiency", "label": "チャージ効率", "min": 0.0, "max": 10000.0, "int": false},
]
const ENEMY_NAMES_BOSS := {"warden": "防衛", "spinner": "回転", "hunter": "追跡"}
const TAB_KEYS := ["audio", "input", "developer"]

var _tab := 0
var _return_state := "menu"
var _wide := true
var _compact := false
var _tick_acc := 0.0
var _status_msg := ""
var _msg_lbl: Label
var _tab_seg: Kit.Segmented
var _panes: Array = []
var _sync := false
var _first_btn: Control

# audio
var _vol_sliders: Dictionary = {}
var _vol_labels: Dictionary = {}
var _mute_btn: Kit.NeonButton
var _a_state: Label
var _a_detail: Label
var _a_meter: Kit.NeonBar
var _a_info: Label
# input
var _layout_cards: Dictionary = {}
var _device_seg: Kit.Segmented
var _quality_seg: Kit.Segmented
var _key_summary: Label
var _hold_tg: Kit.NeonToggle
# developer
var _dev_state_lbl: Label
var _dev_consent_row: Control
var _dev_consent: Kit.NeonToggle
var _dev_enable: Kit.NeonButton
var _dev_info: Label
var _dev_controls: Control
var _f_cp: LineEdit
var _f_level: LineEdit
var _f_hp: LineEdit
var _f_dmg: LineEdit
var _f_stats: Dictionary = {}
var _f_card_search: LineEdit
var _f_card_count: LineEdit
var _card_opt: OptionButton
var _card_desc: Label
var _give_card_btn: Kit.NeonButton
var _skill_slot: OptionButton
var _skill_opt: OptionButton
var _f_skill_lv: LineEdit
var _god_tg: Kit.NeonToggle
var _enemy_opt: OptionButton
var _f_spawn: LineEdit
var _metrics_box: GridContainer
var _log_view: RichTextLabel
var _log_count: Label
var _overlay_tg: Kit.NeonToggle
var _inputlog_tg: Kit.NeonToggle
var _catalogue: Array = []
var _catalogue_shown: Array = []
var _log: Array = []
var _log_sig := ""
var _dev_overlay := false
var _input_log := true
var _monitor: Label

# ------------------------------------------------------------------ lifecycle
func build() -> void:
	modal = true
	dim_alpha = 0.84
	layer_z = 30
	z_index = layer_z
	get_viewport().size_changed.connect(_on_resize)
	_monitor = Label.new()
	_monitor.visible = false
	_monitor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_monitor.position = Vector2(10, 96)
	_monitor.add_theme_font_size_override("font_size", 12)
	_monitor.add_theme_color_override("font_color", Kit.EMERALD)
	_monitor.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_monitor.add_theme_constant_override("outline_size", 4)
	_monitor.z_index = 120
	UI.root.add_child.call_deferred(_monitor)
	_rebuild()
	_log_add("boot", "settings ready")

func _on_resize() -> void:
	if is_open and ((get_viewport_rect().size.x >= 1000.0) != _wide or Kit.is_compact() != _compact):
		_rebuild()
		_sync_all()

func on_open(args: Dictionary = {}) -> void:
	if (get_viewport_rect().size.x >= 1000.0) != _wide or Kit.is_compact() != _compact:
		_rebuild()
	if args.has("tab"): _tab = maxi(0, TAB_KEYS.find(str(args.tab)))
	elif OS.get_environment("NF_TAB") != "" and Game.state != "tools": _tab = maxi(0, TAB_KEYS.find(OS.get_environment("NF_TAB")))   # screenshot harness
	_sync_all()
	_select_tab(_tab)

func on_cancel() -> bool:
	h_closeUtility()
	return true

func _rebuild() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	_wide = get_viewport_rect().size.x >= 1000.0
	_compact = Kit.is_compact()
	_vol_sliders.clear(); _vol_labels.clear(); _layout_cards.clear(); _f_stats.clear(); _panes.clear()
	_build_ui()

# ------------------------------------------------------------------ hooks (原作 9930-9960)
func h_openUtility(tab: Variant = "audio") -> void:
	var t: String = str(tab) if tab != null else "audio"
	if Game.state == "tools":
		h_setUtilityTab(t)
		return
	_return_state = Game.state
	Game.cancelCombatInput()
	Game.state = "tools"
	Game.screenShake = 0.0
	Game.flash = 0.0
	Game.sceneDirty = true
	_tab = maxi(0, TAB_KEYS.find(t if t != "controls" else "input"))
	if _return_state == "menu": UI.hide_screen("home")   # never leave the home panel (focusable) behind the settings panel
	UI.show_screen("settings")
	_set_message("設定はこの端末に保存。閉じると元の画面に戻ります。")
	Game.syncCombatHud()
	Inp.focusPanel("utilityScreen", "utilityClose")

func h_closeUtility() -> void:
	if Game.state != "tools" or not is_open: return
	UI.hide_screen("settings")
	Game.state = _return_state
	if Game.state == "menu": UI.show_screen("home")
	Game.sceneDirty = true
	Game.last = U.now_ms()
	Game.syncCombatHud()
	if Game.state == "paused":
		Game.renderRunStatus()
	elif Game.state == "upgrade":
		Game.renderCardChoices()
	elif Game.state == "ability":
		Combat.renderAbilityRewards()
	elif Game.state == "playing":
		UI.hook("focusCombat")
	if Inp.has_method("syncInputPresentation"): Inp.syncInputPresentation()
	_log_sig = ""

func h_setUtilityTab(tab: Variant = "audio") -> void:
	_select_tab(maxi(0, TAB_KEYS.find(str(tab))))

func b_utilityMessage(message: Variant = "", _kind = null) -> void:
	_set_message(str(message))

func b_syncInputSettings(_prefs = null, _keys = null) -> void:
	if _device_seg != null: _sync_input()

func b_resetGameUI(_touch = null) -> void:
	# a new run starts: the panel never stays open over it (enableDeveloperRun re-opens it itself afterwards)
	if is_open and Game.state != "tools":
		UI.hide_screen("settings")

# ------------------------------------------------------------------ helpers
func _set_message(m: String) -> void:
	_status_msg = m
	if _msg_lbl != null: _msg_lbl.text = m

func _log_add(type: String, msg: String) -> void:
	_log.append({"ms": Time.get_ticks_msec(), "type": type, "message": msg})
	if _log.size() > 240: _log.pop_front()

func _panel(title: String, accent: Color = Kit.CYAN) -> Kit.GlassPanel:
	var p := Kit.panel(accent, Kit.S4)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if title != "":
		p.body.add_child(Kit.label(title, Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	return p

func _help(t: String) -> Label:
	return Kit.label(t, Kit.FS_SM, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true)

func _wrap_btns() -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", Kit.S2)
	h.add_theme_constant_override("v_separation", Kit.S2)
	return h

func _field(placeholder: String, value: String = "", numeric: bool = true) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.text = value
	le.custom_minimum_size = Vector2(120, Kit.btn_h())
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.select_all_on_focus = true
	if numeric: le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	return le

func _labeled(title: String, ctl: Control) -> Control:
	var v := Kit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(Kit.label(title, Kit.FS_SM, Kit.DIM))
	v.add_child(ctl)
	return v

func _grid2() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2 if _wide else 1
	g.add_theme_constant_override("h_separation", Kit.S4)
	g.add_theme_constant_override("v_separation", Kit.S3)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g

func _section(parent: Control, title: String, open: bool) -> VBoxContainer:
	var holder := Kit.vbox(Kit.S2)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := Kit.vbox(Kit.S3)
	body.visible = open
	var hb := Kit.button(("▾  " if open else "▸  ") + title, "ghost")
	hb.set_meta("keep", true)
	hb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hb.pressed.connect(func():
		body.visible = not body.visible
		hb.text = ("▾  " if body.visible else "▸  ") + title)
	holder.add_child(hb)
	holder.add_child(body)
	parent.add_child(holder)
	return body

# ------------------------------------------------------------------ UI
func _build_ui() -> void:
	var vp := get_viewport_rect().size
	var shell := Kit.panel(Kit.CYAN, Kit.S5 if not _compact else Kit.S4)
	shell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.custom_minimum_size.x = minf(1380.0, vp.x - 24.0)
	content.add_child(shell)
	var root := shell.body
	root.add_theme_constant_override("separation", Kit.S3)

	var head := Kit.hbox(Kit.S4)
	var hv := Kit.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(Kit.label("NEON / CONTROL ROOM", Kit.FS_XS, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	hv.add_child(Kit.label("音声・操作・開発者パネル", Kit.FS_2XL if not _compact else Kit.FS_XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	hv.add_child(Kit.label("設定中は戦闘が一時停止します", Kit.FS_SM, Kit.MUTE))
	head.add_child(hv)
	var back := Kit.button("戻る  Esc", "ghost", h_closeUtility)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(back)
	_first_btn = back
	default_focus = back
	root.add_child(head)

	_tab_seg = Kit.segmented(["音声設定", "操作設定", "開発者  F8"], _tab, func(i): _select_tab(i, true), Kit.CYAN)
	root.add_child(_tab_seg)
	root.add_child(Kit.hsep(Kit.with_a(Kit.CYAN, 0.3)))

	var sc := Kit.scroll_list(Kit.S3)
	root.add_child(sc)
	var col := Kit.list_of(sc)
	var pa := Kit.vbox(Kit.S3); pa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pi := Kit.vbox(Kit.S3); pi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pd := Kit.vbox(Kit.S3); pd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(pa); col.add_child(pi); col.add_child(pd)
	_panes = [pa, pi, pd]
	_build_audio(pa)
	_build_input(pi)
	_build_dev(pd)

	var foot := Kit.hbox(Kit.S3)
	_msg_lbl = Kit.label(_status_msg, Kit.FS_SM, Kit.EMERALD.lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT, true)
	_msg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_msg_lbl)
	foot.add_child(Kit.label("%s · AUDIO & SANDBOX" % Meta.GAME_VERSION, Kit.FS_XS, Kit.MUTE))
	root.add_child(foot)
	_select_tab(_tab)

func _select_tab(i: int, from_ui: bool = false) -> void:
	_tab = clampi(i, 0, 2)
	if _tab_seg != null and not from_ui: _tab_seg.set_index(_tab)
	for k in _panes.size():
		(_panes[k] as Control).visible = (k == _tab)
	_sync_all()
	_tick(true)

# ---------------- audio pane
func _build_audio(pa: VBoxContainer) -> void:
	var lay: BoxContainer = HBoxContainer.new() if _wide else VBoxContainer.new()
	lay.add_theme_constant_override("separation", Kit.S4)
	lay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pa.add_child(lay)
	# mixer
	var mix := _panel("音量ミキサー", Kit.CYAN)
	mix.size_flags_stretch_ratio = 1.1
	lay.add_child(mix)
	_mute_btn = Kit.button("ミュート OFF", "ghost", _on_mute)
	mix.body.add_child(_mute_btn)
	for v in VOLUMES:
		var key: String = v[0]
		var row := Kit.vbox(2)
		var h := Kit.hbox(Kit.S2)
		h.add_child(Kit.label(v[1], Kit.FS_MD, Kit.TEXT))
		h.add_child(Kit.fill_spacer())
		var val := Kit.label("0%", Kit.FS_MD, Kit.CYAN.lightened(0.3), HORIZONTAL_ALIGNMENT_RIGHT, false, true)
		h.add_child(val)
		row.add_child(h)
		var sl := Kit.slider(0, 100, 1, float(Audio.Sound.prefs.get(key, 50)), func(x): _on_volume(key, x))
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.drag_ended.connect(func(_c): Audio.Sound.gesture("volume-change"))
		row.add_child(sl)
		mix.body.add_child(row)
		_vol_sliders[key] = sl
		_vol_labels[key] = val
	mix.body.add_child(_help("0%でその種類を消音。設定はこの端末に保存し、ゲームのセーブ移行では上書きしません。現在は効果音のみで、BGMはありません。"))
	# engine
	var side := Kit.vbox(Kit.S3)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(side)
	var eng := _panel("", Kit.VIOLET)
	side.add_child(eng)
	eng.body.add_child(Kit.label("AUDIO ENGINE", Kit.FS_XS, Kit.VIOLET, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_a_state = Kit.label("操作待ち", Kit.FS_XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	eng.body.add_child(_a_state)
	_a_detail = _help("")
	eng.body.add_child(_a_detail)
	_a_meter = Kit.bar(0.0, Kit.EMERALD, "", 10)
	eng.body.add_child(_a_meter)
	eng.body.add_child(_help("出力メーターは同時発音数（最大%d音）です。端末から実際に聞こえることを保証する表示ではありません。" % int(Audio.Sound.MAX_VOICES)))
	var r1 := _wrap_btns()
	r1.add_child(Kit.button("音声を再開", "ghost", func(): Audio.Sound.recover(); _set_message("音声の再開を要求しました。状態とテスト音を確認してください。"); _tick(true)))
	r1.add_child(Kit.button("UI音を試す", "primary", func(): _test("test", "現在の音量でテスト音を再生しました。聞こえるか確認してください。", "まだ音を出せません。ミュート・全体音量・UI音量と音声状態を確認してください。")))
	eng.body.add_child(r1)
	var r2 := _wrap_btns()
	r2.add_child(Kit.button("射撃音を試す", "ghost", func(): _test("shot", "本体の射撃の実際の効果音を、現在の専用音量で試聴しました。", "本体の射撃の音量・ミュート・音声状態を確認してください。")))
	r2.add_child(Kit.button("ドローン音を試す", "ghost", func(): _test("drone", "ドローンの実際の効果音を、現在の専用音量で試聴しました。", "ドローンの音量・ミュート・音声状態を確認してください。")))
	eng.body.add_child(r2)
	_a_info = _help("")
	eng.body.add_child(_a_info)
	eng.body.add_child(Kit.button("直らない場合：音声を再初期化", "ghost", func(): Audio.Sound.rebuild(); _set_message("音声エンジンだけ再初期化しました。音をテストしてください。"); _tick(true)))
	var tip := _panel("無音になったとき", Kit.AMBER)
	side.add_child(tip)
	tip.body.add_child(_help("まずミュート・音量・端末の出力先を確認し、「音声を再開」を押してください。再初期化は音声エンジンだけを作り直します。スコアやセーブは変更しません。"))
	tip.body.add_child(_help("アプリ切替後などで音声が止まった場合も、同じ手順で再開できます。"))

func _on_mute() -> void:
	Audio.Sound.setPreference("muted", not bool(Audio.Sound.prefs.muted))
	if not Audio.Sound.prefs.muted: Audio.Sound.gesture("unmute")
	_sync_audio()
	_tick(true)

func _on_volume(key: String, v: float) -> void:
	if _sync: return
	Audio.Sound.setPreference(key, v)
	(_vol_labels[key] as Label).text = "%d%%" % int(round(v))
	_set_message("音量を保存しました。")

func _test(kind: String, ok_msg: String, ng_msg: String) -> void:
	var ok: bool = await Audio.Sound.test(kind)
	_set_message(ok_msg if ok else ng_msg)
	_tick(true)

func _sync_audio() -> void:
	if _mute_btn == null: return
	_sync = true
	var p: Dictionary = Audio.Sound.preferences()
	for k in _vol_sliders:
		(_vol_sliders[k] as HSlider).set_value_no_signal(float(p[k]))
		(_vol_labels[k] as Label).text = "%d%%" % int(round(float(p[k])))
	var m: bool = bool(p.muted)
	_mute_btn.text = "ミュート ON" if m else "ミュート OFF"
	_mute_btn.set_kind("danger" if m else "ghost")
	_sync = false

# ---------------- input pane
func _build_input(pi: VBoxContainer) -> void:
	var p := _panel("操作設定：キー配置・入力方式", Kit.EMERALD)
	pi.add_child(p)
	p.body.add_child(Kit.label("キー配置", Kit.FS_SM, Kit.DIM))
	var lay: BoxContainer = HBoxContainer.new() if _wide else VBoxContainer.new()
	lay.add_theme_constant_override("separation", Kit.S3)
	for l in [["menus", "Q / E：カード・スキル画面", "発動は数字1・2・3（標準）"], ["abilities", "Q / E / R：スキル発動", "C：カード / V：スキル獲得・強化"]]:
		var id: String = l[0]
		var c := NfOptCard.new(l[1], l[2], Kit.EMERALD, Kit.TEXT)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.pressed.connect(func(): Inp.setKeyLayout(id); _sync_input())
		lay.add_child(c)
		_layout_cards[id] = c
	p.body.add_child(lay)
	p.body.add_child(Kit.spacer(Kit.S1))
	p.body.add_child(Kit.label("入力方式", Kit.FS_SM, Kit.DIM))
	_device_seg = Kit.segmented(["自動切替（マウス／タッチ）", "キーボード・マウス固定", "タッチ固定"], 0,
		func(i): Inp.setInputDevice(["auto", "keyboard", "touch"][i]), Kit.EMERALD)
	p.body.add_child(_device_seg)
	p.body.add_child(_help("設定はこの端末に保存"))
	p.body.add_child(Kit.spacer(Kit.S1))
	p.body.add_child(Kit.label("描画品質", Kit.FS_SM, Kit.DIM))
	_quality_seg = Kit.segmented(["自動（端末に合わせる）", "高品質", "軽量（モバイル向け）"], 0,
		func(i):
			if _sync: return
			Game.set_perf_tier(["auto", "high", "mobile"][i]), Kit.EMERALD)
	p.body.add_child(_quality_seg)
	p.body.add_child(_help("軽量：ワールドを低解像度で描画し、発光・ラベル・粒子を減らします。UIは高解像度のまま。保存されます。"))
	_key_summary = Kit.label("", Kit.FS_SM, Kit.CYAN.lightened(0.5), HORIZONTAL_ALIGNMENT_LEFT, true)
	p.body.add_child(_key_summary)
	var h := _panel("スキル長押し", Kit.CYAN)
	pi.add_child(h)
	_hold_tg = Kit.toggle(true, func(v):
		if _sync: return
		Game.playPreferences.holdSkills = v
		Game.savePlayPreferences()
		Inp.clearSkillHolds())
	h.body.add_child(Kit.setting_row("スキル長押し中は、CD終了ごとに再使用", _hold_tg,
		"タップ／キー短押しは1回。長押しは押している間だけ繰り返し。離した後も、開始済みのチャージは発射されます。画面を開くと長押し入力は解除。"))
	var rel := _panel("入力の復旧", Kit.AMBER)
	pi.add_child(rel)
	rel.body.add_child(_help("移動や射撃が押しっぱなしのように動くときは、入力をすべて解除してください。"))
	rel.body.add_child(Kit.button("入力をすべて解除", "ghost", _release_inputs))

func _sync_input() -> void:
	if _device_seg == null: return
	_sync = true
	for id in _layout_cards: (_layout_cards[id] as NfOptCard).selected = (Inp.inputPreferences.scheme == id)
	_device_seg.set_index(["auto", "keyboard", "touch"].find(str(Inp.inputPreferences.device)))
	if _quality_seg != null: _quality_seg.set_index(["auto", "high", "mobile"].find(Game.perfPref))
	var k: Dictionary = Inp.currentKeys()
	var skills: Array = []
	for s in k.skills: skills.append(Inp.keyLabel(s))
	_key_summary.text = "%s：カード / %s：スキル獲得・強化 / %s：発動 / Space：ダッシュ / Esc：戻る・一時停止" % [Inp.keyLabel(k.cards), Inp.keyLabel(k.rewards), "・".join(skills)]
	_hold_tg.set_value(bool(Game.playPreferences.get("holdSkills", true)))
	_sync = false

func _release_inputs() -> void:
	Inp.clearPhysicalMovement()
	Inp.cancelPointerInput()
	Inp.stopPlayerMotion()
	_log_add("input-reset", "manual release")
	_set_message("移動・射撃・タッチ入力を解除しました。戻った後に押し直してください。")

# ---------------- developer pane
func _build_dev(pd: VBoxContainer) -> void:
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", Kit.box(Kit.with_a(Kit.AMBER, 0.08), Kit.with_a(Kit.AMBER, 0.35), 1, 10))
	var bv := Kit.vbox(2)
	banner.add_child(Kit.margin(bv, Kit.S3))
	bv.add_child(Kit.label("診断 ＋ ラン実験", Kit.FS_MD, Kit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	bv.add_child(Kit.label("見るだけなら通常ランのまま。自由操作を有効にしたランだけ、報酬・記録の対象外になります。", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	pd.add_child(banner)

	var sb := _panel("", Kit.AMBER)
	pd.add_child(sb)
	var hh := Kit.hbox(Kit.S3)
	hh.add_child(Kit.label("ランを自由に調整", Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	hh.add_child(Kit.fill_spacer())
	_dev_state_lbl = Kit.label("診断のみ", Kit.FS_SM, Kit.AMBER, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
	hh.add_child(_dev_state_lbl)
	sb.body.add_child(hh)
	sb.body.add_child(_help("保存済みのユーザーLv・研究・CR・DATAは書き換えません。下の自由操作は、このラン中だけ有効です。通常報酬へは途中で戻せません。"))
	_dev_consent = Kit.toggle(false, func(_v): if not _sync: _render_dev_state(), Kit.AMBER)
	_dev_consent_row = Kit.setting_row("このランを報酬・実績・記録の対象外にする", _dev_consent)
	sb.body.add_child(_dev_consent_row)
	_dev_enable = Kit.button("実験ランを有効化", "primary", _enable_dev)
	_dev_enable.set_kind("primary", Kit.AMBER)
	sb.body.add_child(_dev_enable)
	_dev_info = _help("")
	sb.body.add_child(_dev_info)

	var ctl := Kit.vbox(Kit.S3)
	_dev_controls = ctl
	sb.body.add_child(ctl)
	ctl.add_child(Kit.label("自由操作（次の通常ランには引き継がれません）", Kit.FS_SM, Kit.AMBER.lightened(0.3)))

	# --- world
	var w := _section(ctl, "CP・敵の強さ", true)
	w.add_child(_help("CPは報酬評価値です。CPだけ変えても敵は強くなりません。敵Lv・HP・火力は別々に指定できます。空欄は元の設定へ戻します。"))
	var g := _grid2()
	_f_cp = _field("自動計算")
	_f_level = _field("Waveに応じて成長")
	_f_hp = _field("1", "1")
	_f_dmg = _field("1", "1")
	g.add_child(_labeled("CP上書き", _f_cp))
	g.add_child(_labeled("敵Lv固定", _f_level))
	g.add_child(_labeled("敵HP ×", _f_hp))
	g.add_child(_labeled("敵火力 ×", _f_dmg))
	w.add_child(g)
	var wb := _wrap_btns()
	wb.add_child(Kit.button("CP・敵設定を適用", "primary", func(): _dev("world-settings", _apply_world)))
	wb.add_child(Kit.button("元の難易度設定へ", "ghost", func(): _dev("reset-world", _reset_world)))
	w.add_child(wb)
	w.add_child(_help("元へ戻しても、このランの報酬対象外は継続。敵速度は変更しません。存命敵のHP割合を維持して反映します。"))

	# --- stats
	var s := _section(ctl, "本体・ドローン・スキルの数値", false)
	var sg := _grid2()
	for d in DEV_STAT_FIELDS:
		var le := _field(str(d.min))
		_f_stats[d.key] = le
		sg.add_child(_labeled(d.label, le))
	s.add_child(sg)
	var sbtn := _wrap_btns()
	sbtn.add_child(Kit.button("数値を適用", "primary", func(): _dev("player-stats", _apply_stats)))
	sbtn.add_child(Kit.button("本体火力 ×2", "ghost", func(): _dev("double-damage", _double_damage)))
	sbtn.add_child(Kit.button("現在値を読み直す", "ghost", _read_stats))
	s.add_child(sbtn)
	s.add_child(_help("最大HP変更は現在のHP割合を維持します。通常の成長データは変わりません。入力範囲は検証のための制限です。"))

	# --- cards
	var c := _section(ctl, "好きなプレイ中カードを取得", false)
	var cg := _grid2()
	_f_card_search = _field("ドローン / ビーム / LEGENDARY", "", false)
	_f_card_search.text_changed.connect(func(_t): _render_card_list())
	_f_card_count = _field("1", "1")
	cg.add_child(_labeled("カード名で絞る", _f_card_search))
	cg.add_child(_labeled("追加回数", _f_card_count))
	c.add_child(cg)
	_card_opt = OptionButton.new()
	_card_opt.custom_minimum_size.y = Kit.btn_h()
	_card_opt.fit_to_longest_item = false
	_card_opt.item_selected.connect(func(_i): _render_card_desc())
	c.add_child(_labeled("カード・レアリティ", _card_opt))
	_card_desc = _help("")
	c.add_child(_card_desc)
	var cb := _wrap_btns()
	_give_card_btn = Kit.button("条件・費用なしで追加", "primary", func(): _dev("temporary-card", _give_card))
	cb.add_child(_give_card_btn)
	cb.add_child(Kit.button("カード選択権 ＋10", "ghost", func(): _dev("card-choices", func(): Game.pendingLevelUps += 10; return {"msg": "カード選択権を10回追加しました。Qから取得できます。"})))
	c.add_child(cb)
	c.add_child(_help("レジェンドも前提条件なしで取得可能。重ねて適用できますが、ON/OFF型の能力は同じ効果のままです。現在の難易度の禁止効果は維持します。"))

	# --- skills
	var k := _section(ctl, "アクティブスキルを指定", false)
	var kg := _grid2()
	_skill_slot = OptionButton.new()
	_skill_slot.custom_minimum_size.y = Kit.btn_h()
	for i in 3: _skill_slot.add_item("枠%d" % (i + 1), i)
	_f_skill_lv = _field("1", "1")
	kg.add_child(_labeled("装備枠", _skill_slot))
	kg.add_child(_labeled("Lv", _f_skill_lv))
	k.add_child(kg)
	_skill_opt = OptionButton.new()
	_skill_opt.custom_minimum_size.y = Kit.btn_h()
	for id in Combat.ACTIVE_DEFS:
		_skill_opt.add_item(str(Combat.ACTIVE_DEFS[id].name))
		_skill_opt.set_item_metadata(_skill_opt.item_count - 1, id)
	k.add_child(_labeled("スキル", _skill_opt))
	var kb := _wrap_btns()
	kb.add_child(Kit.button("スキルを装備・上書き", "primary", func(): _dev("active-skill", _equip_skill)))
	kb.add_child(Kit.button("ボスのスキル選択権 ＋3", "ghost", func(): _dev("ability-choices", func():
		for i in 3: Combat.queueAbilityReward()
		return {"msg": "ボスのスキル選択権を3回追加しました。Eから取得できます。"})))
	k.add_child(kb)

	# --- combat
	var b := _section(ctl, "戦闘の検証操作", false)
	_god_tg = Kit.toggle(false, func(v):
		if _sync: return
		_dev("invincibility", func():
			Meta.developerRun.god = v
			return {"msg": "検証用無敵 %s。報酬対象外は継続します。" % ("ON" if v else "OFF")}), Kit.AMBER)
	b.add_child(Kit.setting_row("検証用無敵", _god_tg))
	var bb := _wrap_btns()
	bb.add_child(Kit.button("全回復・デバフ解除", "ghost", func(): _dev("heal-cleanse", func():
		Game.player.hp = Game.player.maxHp
		Game.player.barrierLock = 0.0
		Game.player.wounded = 0.0
		return {"msg": "全回復・デバフ解除しました。"})))
	bb.add_child(Kit.button("全スキルCD・ダッシュ回復", "ghost", func(): _dev("reset-cooldowns", _reset_cd)))
	b.add_child(bb)
	var eg := _grid2()
	_enemy_opt = OptionButton.new()
	_enemy_opt.custom_minimum_size.y = Kit.btn_h()
	for id in Meta.CUSTOM_ENEMY_IDS:
		_enemy_opt.add_item(str(Enemies.ENEMY_TYPES[id].get("name", id)))
		_enemy_opt.set_item_metadata(_enemy_opt.item_count - 1, str(id))
	for id in Meta.CUSTOM_BOSS_IDS:
		_enemy_opt.add_item("ボス / " + str(ENEMY_NAMES_BOSS.get(id, id)))
		_enemy_opt.set_item_metadata(_enemy_opt.item_count - 1, "boss:" + str(id))
	_f_spawn = _field("1", "1")
	eg.add_child(_labeled("敵の種類", _enemy_opt))
	eg.add_child(_labeled("出現数", _f_spawn))
	b.add_child(eg)
	var eb := _wrap_btns()
	eb.add_child(Kit.button("選んだ敵を出現", "primary", func(): _dev("spawn-enemies", _spawn)))
	eb.add_child(Kit.button("敵・弾・予告を消去", "danger", func(): _dev("clear-field", _clear_field)))
	b.add_child(eb)
	b.add_child(_help("ボスは検証時のみ同時3体まで。消去操作では撃破数・XP・ボス報酬を増やしません。"))

	# --- metrics / log
	_metrics_box = GridContainer.new()
	_metrics_box.columns = 3 if _wide else 1
	_metrics_box.add_theme_constant_override("h_separation", Kit.S2)
	_metrics_box.add_theme_constant_override("v_separation", Kit.S2)
	_metrics_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pd.add_child(_metrics_box)
	var tools := _wrap_btns()
	_overlay_tg = Kit.toggle(false, func(v): _dev_overlay = v; _tick(true))
	_inputlog_tg = Kit.toggle(true, func(v): _input_log = v)
	var o1 := Kit.hbox(Kit.S2); o1.add_child(Kit.label("戦闘中に小型モニター", Kit.FS_SM, Kit.TEXT)); o1.add_child(_overlay_tg)
	var o2 := Kit.hbox(Kit.S2); o2.add_child(Kit.label("ゲームキーの記録", Kit.FS_SM, Kit.TEXT)); o2.add_child(_inputlog_tg)
	tools.add_child(o1); tools.add_child(o2)
	tools.add_child(Kit.button("入力をすべて解除", "ghost", _release_inputs))
	tools.add_child(Kit.button("診断JSONを保存", "ghost", _export_diag))
	tools.add_child(Kit.button("ログを消去", "ghost", func(): _log.clear(); _log_sig = ""; _set_message("診断ログを消去しました。"); _tick(true)))
	pd.add_child(tools)
	var lp := _panel("", Kit.SLATE)
	pd.add_child(lp)
	var lh := Kit.hbox(Kit.S2)
	lh.add_child(Kit.label("イベント・ログ", Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	lh.add_child(Kit.fill_spacer())
	_log_count = Kit.label("", Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_RIGHT)
	lh.add_child(_log_count)
	lp.body.add_child(lh)
	_log_view = RichTextLabel.new()
	_log_view.custom_minimum_size.y = 190
	_log_view.scroll_following = true
	_log_view.selection_enabled = true
	_log_view.add_theme_font_size_override("normal_font_size", Kit.fs(Kit.FS_SM))
	_log_view.add_theme_color_override("default_color", Kit.DIM)
	lp.body.add_child(_log_view)
	pd.add_child(_help("ログは直近240件のみ、このセッション内に保持。送信はしません。JSONには画面サイズ・ゲーム状態・入力・音声状態・ログを含みます。カード名や自由入力文、セーブ本体は含めません。"))
	_build_catalogue()
	_render_card_list()

# ------------------------------------------------------------------ developer logic (原作 10054-10232)
func _viewed_state() -> String:
	return _return_state if Game.state == "tools" else Game.state

func _live() -> bool:
	return not Game.runSettled and ["playing", "paused", "upgrade", "ability"].has(_viewed_state())

func _dev_active() -> bool:
	return bool(Meta.developerRun.get("active", false))

func _render_dev_state() -> void:
	if _dev_controls == null: return
	var live := _live()
	var enabled := _dev_active() and live
	_set_enabled(_dev_controls, enabled)
	_dev_controls.modulate.a = 1.0 if enabled else 0.45
	_dev_consent_row.visible = not enabled
	_dev_enable.disabled = enabled or not _dev_consent.value
	_dev_enable.text = "実験ラン：有効（このランは報酬なし）" if enabled else ("このランを報酬なしの実験用に切替" if live else "現在のモードで実験ランを開始")
	_dev_state_lbl.text = "SANDBOX / 報酬なし" if enabled else "診断のみ"
	if enabled:
		_dev_info.text = "CP %.2f / 敵 Lv.%d / 自由操作 %d回。下の数値変更はこのランだけ。" % [float(Meta.challenge().cp), Enemies.enemyLevelForWave(), int(Meta.developerRun.actions)]
	elif live:
		_dev_info.text = "現在のスコア・取得予定報酬も、切り替えると正式集計されません。"
	else:
		_dev_info.text = "開始済みのランがないため、現在の難易度・成長設定で新しい実験ランを開始します。"

func _set_enabled(n: Node, on: bool) -> void:
	for ch in n.get_children():
		if ch.has_meta("keep"): continue
		if ch is BaseButton: (ch as BaseButton).disabled = not on
		elif ch is LineEdit: (ch as LineEdit).editable = on
		elif ch is Range: (ch as Range).editable = on
		elif ch is Kit.NeonToggle:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
			(ch as Control).focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		_set_enabled(ch, on)

func _sync_dev_inputs() -> void:
	if _dev_controls == null: return
	_sync = true
	var dr: Dictionary = Meta.developerRun
	_f_cp.text = "" if dr.cp == null else str(snappedf(float(dr.cp), 0.0001))
	_f_level.text = "" if dr.enemyLevel == null else str(int(dr.enemyLevel))
	_f_hp.text = str(dr.enemyHp)
	_f_dmg.text = str(dr.enemyDamage)
	_god_tg.set_value(bool(dr.god))
	_read_stats()
	_render_card_desc()
	_sync = false

func _read_stats() -> void:
	var p: Dictionary = Game.player
	for d in DEV_STAT_FIELDS:
		var v: Variant = p.get(d.key)
		var n: float = float(v) if (v is float or v is int) else float(d.min)
		(_f_stats[d.key] as LineEdit).text = str(snappedf(n, 0.0001))

## fn returns {"msg": String} or {"err": String}.
func _dev(label: String, fn: Callable) -> void:
	if Game.state != "tools" or not _live() or not _dev_active():
		_set_message("先に「実験ランを有効化」を押してください。")
		return
	var r: Variant = fn.call()
	if r is Dictionary and r.has("err"):
		_set_message(str(r.err))
		return
	Meta.developerRun.actions = int(Meta.developerRun.actions) + 1
	_log_add("dev-action", label)
	Game.sceneDirty = true
	Game.updateUI()
	Game.syncCombatHud()
	Game.renderRunStatus()
	_sync_dev_inputs()
	_render_dev_state()
	_set_message(str(r.get("msg", "")) if r is Dictionary and str(r.get("msg", "")) != "" else label + "を適用しました。このラン は報酬・記録対象外です。")

## Validated numeric read -> {"v": float} / {"err": msg}
func _num(le: LineEdit, label: String, mn: float, mx: float, integer: bool = false, nullable: bool = false) -> Dictionary:
	var t := le.text.strip_edges()
	if nullable and t == "": return {"v": null}
	var ok := t.is_valid_float()
	var n := t.to_float() if ok else 0.0
	if not ok or n < mn or n > mx or (integer and not is_equal_approx(n, roundf(n))):
		return {"err": "%sは%s〜%s%sで指定してください。" % [label, Kit.num(mn) if mn >= 1.0 else str(mn), Kit.num(mx) if mx >= 1.0 else str(mx), "の整数" if integer else ""]}
	return {"v": n}

func _refresh_enemies() -> void:
	for e in Game.enemies:
		if not e.get("_dead", false):
			e.level = -1
			Enemies.refreshEnemyLevel(e)

func _apply_world() -> Dictionary:
	var cp := _num(_f_cp, "CP上書き", 0.1, 1000.0, false, true)
	if cp.has("err"): return cp
	var lv := _num(_f_level, "敵Lv固定", 1.0, 100000.0, true, true)
	if lv.has("err"): return lv
	var hp := _num(_f_hp, "敵HP ×", 0.05, 1000.0)
	if hp.has("err"): return hp
	var dm := _num(_f_dmg, "敵火力 ×", 0.05, 1000.0)
	if dm.has("err"): return dm
	var dr: Dictionary = Meta.developerRun
	dr.cp = cp.v
	dr.enemyLevel = null if lv.v == null else int(lv.v)
	dr.enemyHp = hp.v
	dr.enemyDamage = dm.v
	_refresh_enemies()
	return {"msg": "検証CP %.2f / 敵Lv %d。敵HP・火力を反映しました。CPは報酬評価の試算値です。" % [float(Meta.challenge().cp), Enemies.enemyLevelForWave()]}

func _reset_world() -> Dictionary:
	var dr: Dictionary = Meta.developerRun
	dr.cp = null; dr.enemyLevel = null; dr.enemyHp = 1; dr.enemyDamage = 1
	_refresh_enemies()
	return {"msg": "CP・敵の倍率を元の難易度設定に戻しました。このランの報酬対象外は継続します。"}

func _apply_stats() -> Dictionary:
	var vals := {}
	for d in DEV_STAT_FIELDS:
		var r := _num(_f_stats[d.key], str(d.label), float(d.min), float(d.max), bool(d.int))
		if r.has("err"): return r
		vals[d.key] = r.v
	var p: Dictionary = Game.player
	var ratio: float = U.clamp(float(p.hp) / float(p.maxHp), 0.0, 1.0)
	for k in vals:
		p[k] = int(vals[k]) if bool(DEV_STAT_FIELDS.filter(func(x): return x.key == k)[0].int) else float(vals[k])
	p.hp = p.maxHp * ratio
	Meta.applyModeRestrictions()
	Enemies.syncDrones()
	return {"msg": "本体・ドローン・スキルの数値を適用しました。最大HPは現在のHP割合を維持しています。"}

func _double_damage() -> Dictionary:
	if float(Game.player.damage) > 5e11:
		return {"err": "入力・表示用の検証範囲を超えます。数値を指定してください。"}
	Game.player.damage = float(Game.player.damage) * 2.0
	return {"msg": "本体ダメージを2倍にしました。"}

func _build_catalogue() -> void:
	_catalogue.clear()
	for f in Cards.skills:
		for rarity in ["COMMON", "RARE", "EPIC"]:
			if f.tiers.has(rarity):
				_catalogue.append({"id": f.id, "key": "%s:%s" % [f.id, rarity], "name": f.name, "icon": f.icon, "rarity": rarity,
					"desc": f.tiers[rarity].desc, "apply": Cards._apply_skill.bind(f.id, Cards.rarityRank[rarity])})
	for u in Cards.uniqueEpics:
		_catalogue.append({"id": u.id, "key": "%s:EPIC" % u.id, "name": u.name, "icon": u.icon, "rarity": "EPIC", "desc": u.desc, "apply": Cards._apply_unique.bind(u.id)})
	for l in Cards.legendarySkills:
		_catalogue.append({"id": l.id, "key": "%s:LEGENDARY" % l.id, "name": l.name, "icon": l.icon, "rarity": "LEGENDARY", "desc": l.desc, "apply": Cards._apply_legend.bind(l.id)})

func _norm(v: String) -> String:
	return v.to_lower().replace(" ", "").replace("　", "")

func _render_card_list() -> void:
	if _card_opt == null: return
	var prev := ""
	if _card_opt.selected >= 0 and _card_opt.selected < _catalogue_shown.size():
		prev = str(_catalogue_shown[_card_opt.selected].key)
	var q := _norm(_f_card_search.text)
	_catalogue_shown = _catalogue.filter(func(c): return _norm("%s %s %s" % [c.name, c.rarity, c.id]).contains(q))
	_card_opt.clear()
	var sel := 0
	for i in _catalogue_shown.size():
		var c: Dictionary = _catalogue_shown[i]
		_card_opt.add_item("[%s] %s" % [c.rarity, c.name])
		if c.key == prev: sel = i
	if not _catalogue_shown.is_empty(): _card_opt.select(sel)
	_give_card_btn.disabled = _catalogue_shown.is_empty() or not (_dev_active() and _live())
	_render_card_desc()

func _render_card_desc() -> void:
	if _card_desc == null: return
	if _card_opt.selected >= 0 and _card_opt.selected < _catalogue_shown.size():
		_card_desc.text = str(_catalogue_shown[_card_opt.selected].desc)
	else:
		_card_desc.text = "一致するカードがありません。"

func _give_card() -> Dictionary:
	if _card_opt.selected < 0 or _card_opt.selected >= _catalogue_shown.size():
		return {"err": "カードを選んでください。"}
	var c: Dictionary = _catalogue_shown[_card_opt.selected]
	var n := _num(_f_card_count, "追加回数", 1.0, 20.0, true)
	if n.has("err"): return n
	var actual := {"id": c.id, "name": c.name, "icon": c.icon, "rarity": c.rarity, "desc": c.desc, "apply": c.apply}
	for i in int(n.v):
		Game.pendingLevelUps += 1
		Game.applyRunChoice(actual, false)
	Game.currentCardChoices = null   # no obsolete offers after forcing an evolution
	return {"msg": "%s [%s] を%d回適用。保留の通常選択権は消費していません。" % [c.name, c.rarity, int(n.v)]}

func _equip_skill() -> Dictionary:
	var id: String = str(_skill_opt.get_item_metadata(_skill_opt.selected))
	var idx: int = _skill_slot.selected
	var lv := _num(_f_skill_lv, "Lv", 1.0, 10000.0, true)
	if lv.has("err"): return lv
	if not Combat.ACTIVE_DEFS.has(id) or idx < 0 or idx > 2:
		return {"err": "スキルと枠を選択してください。"}
	for i in 3:
		var s: Variant = Game.activeSlots[i]
		if i != idx and s != null and s.get("id") == id:
			return {"err": "そのスキルは別の枠に装備中です。同じ枠を選んで強化してください。"}
	var old: Variant = Game.activeSlots[idx]
	if old != null and old.get("charging") is Dictionary: old.charging.dead = true
	Game.activeSlots[idx] = {"id": id, "level": int(lv.v), "remaining": 0.0, "charging": null}
	return {"msg": "枠%d：%s Lv.%d。準備完了です。" % [idx + 1, Combat.ACTIVE_DEFS[id].name, int(lv.v)]}

func _reset_cd() -> Dictionary:
	for s in Game.activeSlots:
		if s != null:
			s.remaining = 0.0
			if s.get("charging") is Dictionary: s.charging.dead = true
			s.charging = null
	Game.player.dashReady = 1.0
	return {"msg": "スキルCDとダッシュを回復しました。充填中の発射予約は取消しました。"}

func _spawn() -> Dictionary:
	var id: String = str(_enemy_opt.get_item_metadata(_enemy_opt.selected))
	var n := _num(_f_spawn, "出現数", 1.0, 10.0, true)
	if n.has("err"): return n
	var boss := id.begins_with("boss:")
	var type := id.substr(5) if boss else id
	if not (Meta.CUSTOM_BOSS_IDS if boss else Meta.CUSTOM_ENEMY_IDS).has(type):
		return {"err": "敵の種類が不正です。"}
	var made := 0
	var cnt: int = int(n.v)
	for i in cnt:
		var e: Variant = Enemies.spawnEnemy("boss" if boss else type, boss, type if boss else null)
		if e == null: break
		var a: float = float(i) / maxf(1.0, float(cnt)) * TAU
		e.x = U.clamp(Game.player.x + cos(a) * 420.0, 70.0, World.W - 70.0)
		e.y = U.clamp(Game.player.y + sin(a) * 260.0, 70.0, World.H - 70.0)
		made += 1
	return {"msg": "%d体を予告付きで出現させました。%s" % [made, "同時出現の安全上限に達しました。" if made < cnt else ""]}

func _clear_field() -> Dictionary:
	for e in Game.enemies: e._dead = true
	for b in Game.bullets:
		if b != null: b._dead = true
	Game.enemies = []; Game.bullets = []; Game.hazards = []; Game.particles = []; Game.rings = []
	Game.bossAlive = false; Game.bossWarningTimer = 0.0; Game.clearPending = false
	UI.hook("hideBossWarning")
	return {"msg": "敵・弾・予告を消去しました。撃破数・XPは増えません。自動スポーンは再開します。"}

## enableDeveloperRun (原作 10105)
func _enable_dev() -> void:
	if Game.state != "tools" or not _dev_consent.value: return
	if _dev_active() and _live(): return
	if not _live():
		var err: String = Enemies.validateRunSetup()
		if err != "":
			_set_message(err)
			return
		h_closeUtility()
		UI.hide_screen("home")
		Game.resetGame()
		if Game.state != "playing": return
		Meta.developerRun.active = true
		h_openUtility("developer")
	else:
		Meta.developerRun.active = true
	Meta.developerRun.actions = int(Meta.developerRun.actions) + 1
	_dev_consent.set_value(false)
	_log_add("sandbox", "enabled; permanent rewards and records excluded")
	_sync_dev_inputs()
	_render_dev_state()
	Game.updateUI()
	_set_message("実験ランを有効化しました。CP・カード・数値を自由に試せます。保存済みの成長データは変更していません。")

# ------------------------------------------------------------------ diagnostics
func _sync_all() -> void:
	_sync_audio()
	_sync_input()
	_sync_dev_inputs()
	_render_dev_state()
	_render_card_list()

func _process(dt: float) -> void:
	_tick_acc += dt
	if _tick_acc >= 0.25:
		_tick_acc = 0.0
		_tick(false)

func _input(e: InputEvent) -> void:
	if _input_log and e is InputEventKey and e.pressed and not e.echo and (Game.state == "playing" or is_open):
		_log_add("key", OS.get_keycode_string(e.physical_keycode if e.physical_keycode != 0 else e.keycode))
		if _log.size() > 240: _log.pop_front()

func _snapshot() -> Dictionary:
	var p: Dictionary = Game.player
	var alive := Game.enemies.filter(func(x): return not x.get("_dead", false))
	var pb := Game.bullets.filter(func(b): return b != null and not b.get("_dead", false) and not b.get("enemy", false))
	var eb := Game.bullets.filter(func(b): return b != null and not b.get("_dead", false) and b.get("enemy", false))
	return {"app": "NEON_FRACTURE_DIAGNOSTIC", "version": Meta.GAME_VERSION, "createdAt": Time.get_datetime_string_from_system(true) + "Z",
		"environment": {"width": World.VIEW_W, "height": World.VIEW_H, "os": OS.get_name(), "godot": Engine.get_version_info().string,
			"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "fps": Engine.get_frames_per_second()},
		"game": {"developer": Meta.developerRun.duplicate(), "state": Game.state, "inspectedState": _viewed_state(), "wave": Game.wave,
			"enemyLevel": Enemies.enemyLevelForWave(), "runSeconds": Game.time, "settled": Game.runSettled, "difficulty": Meta.runConfig.difficulty,
			"player": {"x": p.get("x"), "y": p.get("y"), "vx": p.get("vx"), "vy": p.get("vy"), "hp": p.get("hp"), "maxHp": p.get("maxHp"), "level": p.get("level")},
			"counts": {"enemies": alive.size(), "bosses": Enemies.activeBosses().size(), "bullets": pb.size() + eb.size(), "playerBullets": pb.size(),
				"enemyBullets": eb.size(), "particles": Game.particles.size(), "gems": Game.gems.size(), "friendlyEffects": Game.friendlyEffects.size(),
				"hazards": Game.hazards.size(), "cards": Game.pendingLevelUps, "skills": Game.abilityRewards.size()}},
		"input": {"mode": Inp.inputMode, "physicalKeys": Inp.physicalMoveKeys.keys(), "preferences": Inp.inputPreferences.duplicate()},
		"audio": Audio.Sound.sample(), "unhandledHooks": UI.unhandled.duplicate(), "logs": _log.slice(maxi(0, _log.size() - 240))}

func _export_diag() -> void:
	var fname := "neon-fracture-diagnostic-%d.json" % int(Time.get_unix_time_from_system() * 1000.0)
	for d in [OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), ProjectSettings.globalize_path("user://")]:
		if str(d) == "": continue
		var path: String = str(d).path_join(fname)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null: continue
		f.store_string(JSON.stringify(_snapshot(), "  "))
		f.close()
		_set_message("診断JSONを保存しました（%s）。ゲームのセーブデータは含めていません。" % path)
		return
	_log_add("export-error", "cannot write")
	_set_message("診断の保存に失敗しました。")

func _tick(force: bool) -> void:
	var active := is_open
	if active and _tab == 0:
		_tick_audio()
	if active and _tab == 2:
		_tick_dev(force)
	# small in-battle monitor
	if _monitor != null:
		var show := _dev_overlay and Game.state == "playing"
		_monitor.visible = show
		if show:
			var n := Game.enemies.size()
			_monitor.text = "%s  %d FPS\n敵 %d / 弾 %d\n入力 %s\n音声 %s / %d音" % [Meta.GAME_VERSION, Engine.get_frames_per_second(), n, Game.bullets.size(),
				"+".join(Inp.physicalMoveKeys.keys()) if not Inp.physicalMoveKeys.is_empty() else "—", str(Audio.Sound.sample().state), int(Audio.Sound.sample().voices)]

func _tick_audio() -> void:
	var a: Dictionary = Audio.Sound.sample()
	var labels := {"suspended": "一時停止", "running": "再生エンジン動作中"}
	var label: String = "ミュート中" if (a.muted or float(a.master) == 0.0) else str(labels.get(a.state, a.state))
	_a_state.text = label
	_a_detail.text = "%s / 再生中 %d音 / %d Hz" % [a.state, int(a.voices), int(Audio.Sound.SAMPLE_RATE)]
	_a_meter.set_value_instant(float(a.voices) / float(maxi(1, int(a.maxVoices))))
	var c: Dictionary = a.counts
	_a_info.text = "発音 %d / 連射の音のみ集約 %d / 音数制限 %d / ミュート %d / 音声待機 %d（試聴を含む）" % [int(c.played), int(c.rateLimited), int(c.limited), int(c.muted), int(c.blocked)]
	_sync_audio_light(a)

func _sync_audio_light(a: Dictionary) -> void:
	var m: bool = bool(a.muted)
	var want := "ミュート ON" if m else "ミュート OFF"
	if _mute_btn.text != want: _sync_audio()

func _tick_dev(force: bool) -> void:
	_render_dev_state()
	var t := Engine.get_frames_per_second()
	var a: Dictionary = Audio.Sound.sample()
	var p: Dictionary = Game.player
	var alive := 0
	for e in Game.enemies:
		if not e.get("_dead", false): alive += 1
	var mv := Inp.physicalMoveKeys.keys()
	var px: String = "%.1f, %.1f" % [float(p.get("x", 0)), float(p.get("y", 0))]
	var pv: String = "%.1f, %.1f" % [float(p.get("vx", 0)), float(p.get("vy", 0))]
	var unh := 0
	for k in UI.unhandled: unh += int(UI.unhandled[k])
	var metrics := [
		["シーン / ビルド", "%s / %s" % [_viewed_state(), Meta.GAME_VERSION], "パネル表示中は時間停止"],
		["FPS / 処理時間", "%d / %.2f ms" % [t, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0], "物理 %.2f ms / 描画コール %d" % [Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]],
		["Wave / 敵Lv", "%d / %d" % [Game.wave, Enemies.enemyLevelForWave()], "%s / %.1f秒" % [Meta.runConfig.difficulty, Game.time]],
		["敵 / 弾", "%d / %d" % [alive, Game.bullets.size()], "ボス %d" % Enemies.activeBosses().size()],
		["エフェクト / 保留カード", "%d / %d" % [Game.particles.size() + Game.friendlyEffects.size(), Game.pendingLevelUps], "XP %d / 予告 %d / スキル報酬 %d" % [Game.gems.size(), Game.hazards.size(), Game.abilityRewards.size()]],
		["入力状態", " ".join(mv) if not mv.is_empty() else "キーなし", "%s / 移動 %.2f, %.2f" % [Inp.inputMode, Inp.dxMove(), Inp.dyMove()]],
		["座標 / 速度", px, pv],
		["音声状態", "%s / %d音" % [a.state, int(a.voices)], "発音 %d / ミュート除外 %d" % [int(a.counts.played), int(a.counts.muted)]],
		["メモリ / オブジェクト", "%.1f MB / %d" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_COUNT))], "未処理フック %d件" % unh],
	]
	var sig := str(metrics)
	if force or sig != str(_metrics_box.get_meta("sig", "")):
		_metrics_box.set_meta("sig", sig)
		for ch in _metrics_box.get_children(): ch.queue_free()
		for m in metrics:
			var cell := PanelContainer.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.08), 1, 8))
			var v := Kit.vbox(0)
			v.add_child(Kit.label(m[0], Kit.FS_XS, Kit.DIM))
			v.add_child(Kit.label(m[1], Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
			v.add_child(Kit.label(m[2], Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
			cell.add_child(Kit.margin(v, Kit.S2))
			_metrics_box.add_child(cell)
	var logsig := "%d:%d" % [_log.size(), int(_log.back().ms) if not _log.is_empty() else 0]
	if logsig != _log_sig:
		_log_sig = logsig
		var lines: PackedStringArray = []
		for x in _log.slice(maxi(0, _log.size() - 80)):
			lines.append("%8.2fs  %-14s %s" % [float(x.ms) / 1000.0, str(x.type), str(x.message)])
		_log_view.text = "\n".join(lines) if not lines.is_empty() else "記録はありません"
		_log_count.text = "直近80件表示 / 保持 %d / 240件" % _log.size()
