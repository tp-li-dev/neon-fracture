extends Control
## Meta tab: growth tuning (原作 9637-9720): apply-level sliders for Player Lv + each research, with starting-status preview.

const TAB_ID := "growth"
const TAB_LABEL := "成長調整"
const TAB_ORDER := 10

const PREVIEW_FIELDS := [
	["damage", "本体ダメージ"], ["maxHp", "最大HP"], ["speed", "移動速度"], ["bulletSpeed", "弾速"],
	["fireRate", "連射 / 秒"], ["crit", "会心率"], ["critMult", "会心威力"], ["lifesteal", "HP吸収（効率補正前）"],
	["magnet", "回収範囲"], ["xpMultiplier", "ランXP"], ["activePower", "スキル出力"], ["activeHaste", "スキル再使用効率"]]

var _root: VBoxContainer
var _notice: Label
var _summary: Label
var _lock: Label
var _preview_lv: Label
var _rows: Dictionary = {}       # key -> widgets dict
var _preview_cells: Array = []   # [{key, applied, full, label}]
var _econ_cells: Dictionary = {}
var _grid: GridContainer
var _guard := false

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var comp := Kit.is_compact()
	_root = Kit.vbox(Kit.S2)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var head := Kit.hbox(Kit.S3)
	_root.add_child(head)
	var tl := Kit.vbox(0)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tl.add_child(Kit.label("GROWTH TUNING", Kit.FS_XS, Kit.with_a(Kit.CYAN, 0.85), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	tl.add_child(Kit.label("成長を残して、強さを選ぶ", Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	if not comp:
		tl.add_child(Kit.label("ユーザーLvとCR研究を個別に調整。獲得済みLv・XP・CRは減りません。", Kit.FS_XS, Kit.DIM))
	head.add_child(tl)
	var b1 := Kit.button("すべて最大値に追従", "primary", func(): _all(true))
	var b2 := Kit.button("Lv.1・研究0に固定", "ghost", func(): _all(false))
	b1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(b1)
	head.add_child(b2)

	var rule := PanelContainer.new()
	var sb := Kit.box(Color("#10252c"), Color("#2a4249"), 1, 10)
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	rule.add_theme_stylebox_override("panel", sb)
	var rh := Kit.hbox(Kit.S3)
	rh.add_child(Kit.label("次のランから適用・自動保存。", Kit.FS_SM, Color("#a5f3fc"), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	var rl := Kit.label("数値指定＝固定 ／ 最大追従＝今後の成長も自動適用。", Kit.FS_SM, Kit.DIM)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rl.clip_text = true
	rh.add_child(rl)
	_summary = Kit.label("", Kit.FS_SM, Color("#99e4d5"), HORIZONTAL_ALIGNMENT_RIGHT)
	rh.add_child(_summary)
	rule.add_child(rh)
	_root.add_child(rule)

	var split := Kit.hbox(Kit.S3)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(split)

	# --- left: controls
	var lp := Kit.vbox(Kit.S1)
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lp.size_flags_stretch_ratio = 1.7
	split.add_child(lp)
	var cap := Kit.hbox(Kit.S2)
	cap.add_child(Kit.label("適用するLv・研究段数", Kit.FS_XS, Kit.DIM))
	cap.add_child(Kit.fill_spacer())
	cap.add_child(Kit.label("獲得済みの範囲内", Kit.FS_XS, Kit.DIM))
	lp.add_child(cap)
	var sc := Kit.scroll_list(0)
	lp.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", Kit.S2)
	_grid.add_theme_constant_override("v_separation", Kit.S2)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.list_of(sc).add_child(_grid)
	_make_row("playerLevel", "ユーザーレベル", "◇")
	for key in Meta.META_STATS:
		_make_row(key, Meta.META_STATS[key].name, Meta.META_STATS[key].icon)
	_lock = Kit.label("", Kit.FS_SM, Kit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, true)
	_lock.visible = false
	lp.add_child(_lock)
	_notice = Kit.label("", Kit.FS_SM, Color("#81d6ca"), HORIZONTAL_ALIGNMENT_LEFT, true)
	lp.add_child(_notice)

	# --- right: preview
	var pv := Kit.panel(Kit.EMERALD, Kit.S3)
	pv.brackets = false
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.size_flags_stretch_ratio = 1.0
	split.add_child(pv)
	pv.body.add_child(Kit.label("STARTING STATUS", Kit.FS_XS, Kit.with_a(Kit.EMERALD, 0.9), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	pv.body.add_child(Kit.label("適用値と最大値", Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_preview_lv = Kit.label("", Kit.FS_SM, Color("#99e4d5"), HORIZONTAL_ALIGNMENT_LEFT, true)
	pv.body.add_child(_preview_lv)
	if not comp:
		pv.body.add_child(Kit.label("現在の装備込み／難易度の制限・ラン中強化を除く。変更するのはユーザーLvと研究だけです。", Kit.FS_XS, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var psc := ScrollContainer.new()
	psc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	psc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.body.add_child(psc)
	var tbl := GridContainer.new()
	tbl.columns = 3
	tbl.add_theme_constant_override("h_separation", Kit.S3)
	tbl.add_theme_constant_override("v_separation", Kit.S1)
	tbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	psc.add_child(tbl)
	tbl.add_child(Kit.label("項目", Kit.FS_XS, Color("#88b9c3")))
	tbl.add_child(Kit.label("適用", Kit.FS_XS, Color("#88b9c3"), HORIZONTAL_ALIGNMENT_RIGHT))
	tbl.add_child(Kit.label("最大", Kit.FS_XS, Color("#88b9c3"), HORIZONTAL_ALIGNMENT_RIGHT))
	for f in PREVIEW_FIELDS:
		_preview_cells.append(_table_row(tbl, f[1], f[0]))
	_econ_cells = _table_row(tbl, "CR研究倍率", "")
	pv.body.add_child(Kit.label("獲得XPは本来のユーザーLvに加算。調整によるCP・報酬ボーナスはありません。換金研究は適用段数の倍率になります。", Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
	resized.connect(func():
		var cols := 2 if size.x > 1000 else 1
		if _grid.columns != cols: _grid.columns = cols)

func _table_row(tbl: GridContainer, label: String, key: String) -> Dictionary:
	var l := Kit.label(label, Kit.FS_SM, Color("#a9bfca"), HORIZONTAL_ALIGNMENT_LEFT, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var a := Kit.label("", Kit.FS_SM, Color("#b0f1e8"), HORIZONTAL_ALIGNMENT_RIGHT, false, true)
	var f := Kit.label("", Kit.FS_SM, Color("#879fae"), HORIZONTAL_ALIGNMENT_RIGHT)
	tbl.add_child(l); tbl.add_child(a); tbl.add_child(f)
	return {"key": key, "applied": a, "full": f}

func _make_row(key: String, title: String, icon: String) -> void:
	var p := Kit.panel(Kit.CYAN, Kit.S3)
	p.brackets = false
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := Kit.hbox(Kit.S2)
	h.add_child(Kit.label("%s %s" % [icon, title], Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	h.add_child(Kit.fill_spacer())
	var follow := Kit.button("最大追従", "ghost", func(): _commit(key, null, true))
	follow.custom_minimum_size.y = 34 if not Kit.is_compact() else 44
	h.add_child(follow)
	p.body.add_child(h)
	var st := Kit.hbox(Kit.S2)
	var val := Kit.label("", Kit.FS_SM, Color("#b7d1e3"))
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mode := Kit.label("", Kit.FS_XS, Color("#b9b38b"), HORIZONTAL_ALIGNMENT_RIGHT)
	st.add_child(val); st.add_child(mode)
	p.body.add_child(st)
	var inp := Kit.hbox(Kit.S3)
	var sl := Kit.slider(0, 1, 1, 0)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size.x = 100
	var sp := SpinBox.new()
	sp.step = 1
	sp.rounded = true
	sp.custom_minimum_size = Vector2(110, 40)
	sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inp.add_child(sl); inp.add_child(sp)
	p.body.add_child(inp)
	var desc := Kit.label("", Kit.FS_XS, Color("#9cafc2"), HORIZONTAL_ALIGNMENT_LEFT, true)
	p.body.add_child(desc)
	_grid.add_child(p)
	sl.value_changed.connect(func(v: float): if not _guard: _commit(key, int(v), false))
	sl.drag_ended.connect(func(_c): Meta.growthSavedNotice("次のランから適用します。獲得済みの成長は保持しています。"))
	sp.value_changed.connect(func(v: float): if not _guard: _commit(key, int(v), false))
	sp.get_line_edit().text_submitted.connect(func(_t): Meta.growthSavedNotice("次のランから適用します。"))
	_rows[key] = {"panel": p, "follow": follow, "val": val, "mode": mode, "slider": sl, "spin": sp, "desc": desc}

func _commit(key: String, value, follow_btn: bool) -> void:
	if not Meta.setGrowthChoice(key, value):
		_lock.text = "成長調整は、ホーム・リザルト・ラン設定から開いた研究所でのみ変更できます。"
		_lock.visible = true
		_sync_row(key)
		return
	_lock.visible = false
	_sync_row(key)
	_update_preview()
	if follow_btn: Meta.growthSavedNotice("この項目は今後の獲得済み最大値にも追従します。")

func _all(follow: bool) -> void:
	if not Meta.setAllGrowthChoices(follow):
		_lock.text = "成長調整は、ホーム・リザルト・ラン設定から開いた研究所でのみ変更できます。"
		_lock.visible = true

func _row_info(key: String) -> Dictionary:
	var prefs: Dictionary = Meta.sanitizeGrowthLimits(Meta.meta.growthLimits, Meta.meta.playerLevel, Meta.meta.stats)
	var g: Dictionary = Meta.resolveGrowthLimits()
	var is_player := key == "playerLevel"
	var mx: int = g.ownedPlayerLevel if is_player else g.ownedStats[key]
	var value: int = g.playerLevel if is_player else g.stats[key]
	var follow: bool = (prefs.playerLevel if is_player else prefs.research[key]) == null
	var desc: String
	if is_player:
		var b: Dictionary = Meta.playerLevelBase(value)
		desc = "基礎攻撃 %s / HP %s / 回収範囲 %s" % [Meta.researchNumber(18.0 + b.damage), Meta.researchNumber(100.0 + b.maxHp), Meta.researchNumber(115.0 + b.magnet)]
	else:
		desc = Meta.research_desc(key, value)
	return {"min": 1 if is_player else 0, "max": mx, "value": value, "follow": follow, "desc": desc}

func _sync_row(key: String) -> void:
	var info := _row_info(key)
	var r: Dictionary = _rows[key]
	_guard = true
	var sl: HSlider = r.slider
	var sp: SpinBox = r.spin
	for rg in [sl, sp]:
		rg.min_value = info.min
		rg.max_value = maxi(info.max, info.min)
	sl.editable = info.max > info.min
	sp.editable = info.max > info.min
	sl.set_value_no_signal(info.value)
	sp.set_value_no_signal(info.value)
	_guard = false
	r.val.text = "適用 %s / 獲得 %s" % [Meta.researchNumber(info.value), Meta.researchNumber(info.max)]
	r.desc.text = info.desc
	r.mode.text = "最大値に追従中" if info.follow else "この値に固定中"
	var reduced: bool = info.value < info.max
	(r.panel as Kit.GlassPanel).set_accent(Kit.AMBER if reduced else Kit.CYAN)
	var fb: Kit.NeonButton = r.follow
	fb.text = "✓ 最大追従" if info.follow else "最大追従に戻す"
	fb.set_kind("success" if info.follow else "ghost")

func _preview_player(g: Dictionary) -> Dictionary:
	var p: Dictionary = Game.playerBase()
	Meta.applyMetaBonuses(p, g)
	return p

func _fmt(key: String, p: Dictionary) -> String:
	var n: Callable = Meta.researchNumber
	match key:
		"crit": return n.call(p.crit * 100.0) + "%"
		"critMult": return "×" + n.call(p.critMult)
		"lifesteal": return n.call(p.lifesteal * 100.0) + "%"
		"xpMultiplier", "activePower": return "×" + n.call(p[key])
		"activeHaste": return "+" + n.call(p.activeHaste * 100.0) + "%"
	return n.call(p[key])

func _update_preview() -> void:
	var g: Dictionary = Meta.resolveGrowthLimits()
	var mx := {"playerLevel": g.ownedPlayerLevel, "stats": g.ownedStats}
	var ap := _preview_player(g)
	var fu := _preview_player(mx)
	_preview_lv.text = "ユーザーLv.%s / 最大 Lv.%s" % [Meta.researchNumber(g.playerLevel), Meta.researchNumber(g.ownedPlayerLevel)]
	for c in _preview_cells:
		var k: String = c.key
		c.applied.text = _fmt(k, ap)
		c.full.text = _fmt(k, fu)
		c.applied.add_theme_color_override("font_color", Color("#f1dc98") if float(ap[k]) < float(fu[k]) else Color("#b0f1e8"))
	_econ_cells.applied.text = "×" + Meta.researchNumber(1.0 + g.stats.economy * .03)
	_econ_cells.full.text = "×" + Meta.researchNumber(1.0 + g.ownedStats.economy * .03)
	_econ_cells.applied.add_theme_color_override("font_color", Color("#f1dc98") if g.stats.economy < g.ownedStats.economy else Color("#b0f1e8"))
	update_summaries()

# ---------------------------------------------------------------- shell API
func render_controls() -> void:
	if _root == null: return
	for k in _rows: _sync_row(k)
	_update_preview()

func update_summaries() -> void:
	if _summary == null: return
	_summary.text = Meta.growthSummary()

func notice(kind: String, msg: String) -> void:
	if kind != "growth" or _notice == null: return
	_notice.text = msg

func refresh() -> void:
	if _root == null: return
	_lock.visible = not Meta.growthEditAllowed()
	if _lock.visible: _lock.text = "成長調整は、ホーム・リザルト・ラン設定から開いた研究所でのみ変更できます。"
	render_controls()
