extends NFScreen
## META shell (研究所): header (LV / XP / CR / DATA / LOADOUT / back) + tab bar.
## Tabs are auto-discovered: res://scripts/ui/meta_tab_<id>.gd
##   extends Control; const TAB_ID/TAB_LABEL/TAB_ORDER; func build(); func refresh(); optional func notice(kind, msg)
## Optional tab methods used by hooks: render_controls() / update_summaries() (growth), show_results(results) (gacha).

const TAB_DIR := "res://scripts/ui/"
const TAB_PREFIX := "meta_tab_"
const DEFAULT_TAB := "research"

var tabs: Array = []                 # [{id,label,order,node,btn,built}]
var current_id := ""
var _stack: Control
var _tabbar: HBoxContainer
var _title_box: VBoxContainer
var _sub: Label
var _lv_lbl: Label
var _xp_lbl: Label
var _xp_bar: Kit.NeonBar
var _cr_lbl: Label
var _data_lbl: Label
var _load_lbl: Label
var _back: Kit.NeonButton
var _tab_tw: Tween
var _pending_notice: Dictionary = {}   # kind -> msg (for tabs not built yet)

func build() -> void:
	modal = true
	dim_alpha = 0.9
	backdrop.color = Color(0.012, 0.02, 0.045, 0.94)
	layer_z = 40
	z_index = layer_z
	var root := Kit.vbox(Kit.S2)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(root)
	root.add_child(_build_header())
	root.add_child(_build_tabbar())
	_stack = Control.new()
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.clip_contents = true
	root.add_child(_stack)
	_discover_tabs()
	default_focus = _back

# ------------------------------------------------------------------ header
func _stat_block(eyebrow: String, color: Color) -> Array:
	var v := Kit.vbox(0)
	var e := Kit.label(eyebrow, Kit.FS_XS, Kit.with_a(color, 0.8), HORIZONTAL_ALIGNMENT_LEFT, false, true)
	v.add_child(e)
	return [v, e]

func _build_header() -> Control:
	var comp := Kit.is_compact()
	var row := Kit.hbox(Kit.S4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# title
	_title_box = Kit.vbox(0)
	_title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_box.add_child(Kit.label("NEON LABORATORY", Kit.FS_XS, Kit.with_a(Kit.AMBER, 0.85), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_title_box.add_child(Kit.label("恒久強化 & カード構文研究", Kit.FS_XL if not comp else Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_sub = Kit.label("強化・カード構築・解析・セーブをタブで管理。必要な研究だけ開き、自分の戦闘ロジックを組み上げる。", Kit.FS_XS, Kit.MUTE)
	_sub.clip_text = true
	_sub.visible = not comp
	_title_box.add_child(_sub)
	row.add_child(_title_box)

	var panel := Kit.panel(Kit.CYAN, Kit.S3 if not comp else Kit.S2)
	panel.brackets = false
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var stats := Kit.hbox(Kit.S5 if not comp else Kit.S4)
	panel.body.add_child(stats)
	# level
	var lv := _stat_block("PLAYER LEVEL", Kit.CYAN)
	var lvb: VBoxContainer = lv[0]
	_lv_lbl = Kit.label("Lv.1", Kit.FS_XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	lvb.add_child(_lv_lbl)
	_xp_bar = Kit.bar(0.0, Kit.CYAN, "", 6)
	_xp_bar.custom_minimum_size.x = 110
	lvb.add_child(_xp_bar)
	_xp_lbl = Kit.label("0 / 0 XP", Kit.FS_XS, Kit.MUTE)
	lvb.add_child(_xp_lbl)
	stats.add_child(lvb)
	# credits
	var cr := _stat_block("所持クレジット", Kit.AMBER)
	_cr_lbl = Kit.label("0 CR", Kit.FS_XL, Kit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	cr[0].add_child(_cr_lbl)
	stats.add_child(cr[0])
	# data
	var dt := _stat_block("解析データ", Kit.VIOLET)
	_data_lbl = Kit.label("0 DATA", Kit.FS_XL, Kit.VIOLET, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	dt[0].add_child(_data_lbl)
	stats.add_child(dt[0])
	# loadout
	if not comp:
		var ld := _stat_block("LOADOUT", Kit.VIOLET)
		_load_lbl = Kit.label("装備 0/3 / カード 0/3", Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
		ld[0].add_child(_load_lbl)
		stats.add_child(ld[0])
	row.add_child(panel)

	_back = Kit.button("✕  戻る", "ghost", func(): Meta.closeMeta())
	_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_back)
	return row

func refresh_header() -> void:
	if _lv_lbl == null: return
	var m: Dictionary = Meta.meta
	var need: int = Meta.playerXpNeeded(m.playerLevel)
	var xp: float = float(m.get("playerXp", 0.0))
	_lv_lbl.text = "Lv.%s" % Kit.num(m.playerLevel)
	_xp_lbl.text = "%s / %s XP" % [Kit.num(floorf(xp)), Kit.num(need)]
	_xp_bar.set_value_smooth(minf(1.0, xp / maxf(1.0, float(need))))
	_cr_lbl.text = "%s CR" % Kit.num(m.credits)
	_data_lbl.text = "%s DATA" % Kit.num(m.get("data", 0))
	if _load_lbl:
		var g := 0
		for v in Meta._dictv(m.get("equippedGear")).values():
			if v != null: g += 1
		_load_lbl.text = "装備 %d/3 / カード %d/3" % [g, (m.get("equippedCards", []) as Array).size()]

# ------------------------------------------------------------------ tabs
func _build_tabbar() -> Control:
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.custom_minimum_size.y = Kit.btn_h() + 6
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabbar = Kit.hbox(Kit.S2)
	_tabbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_tabbar)
	return sc

func _discover_tabs() -> void:
	var seen := {}
	for f in DirAccess.get_files_at(TAB_DIR):
		var name: String = f
		for suf in [".remap", ".gdc"]:
			if name.ends_with(suf): name = name.trim_suffix(suf)
		if not (name.begins_with(TAB_PREFIX) and name.ends_with(".gd")) or seen.has(name): continue
		seen[name] = true
		var scr = load(TAB_DIR + name)
		if scr == null or not (scr is GDScript): continue
		var consts: Dictionary = (scr as GDScript).get_script_constant_map()
		var tid: String = str(consts.get("TAB_ID", name.trim_prefix(TAB_PREFIX).trim_suffix(".gd")))
		tabs.append({"id": tid, "label": str(consts.get("TAB_LABEL", tid)), "order": int(consts.get("TAB_ORDER", 100)),
			"script": scr, "node": null, "btn": null, "built": false})
	tabs.sort_custom(func(a, b): return a.order < b.order)
	for t in tabs:
		var b := Kit.button(t.label, "tab")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 104 if not Kit.is_compact() else 96
		var tid: String = t.id
		b.pressed.connect(func(): set_tab(tid))
		_tabbar.add_child(b)
		t.btn = b

func _tab(id: String) -> Dictionary:
	for t in tabs: if t.id == id: return t
	return {}

func _ensure_built(t: Dictionary) -> void:
	if t.built: return
	t.built = true
	var n: Control = (t.script as GDScript).new()
	n.name = "Tab_" + str(t.id)
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_EXPAND_FILL
	n.visible = false
	_stack.add_child(n)
	n.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.node = n
	if n.has_method("build"): n.call("build")
	for k in _pending_notice.keys():
		if n.has_method("notice"): n.call("notice", k, _pending_notice[k])

func set_tab(id: String, instant := false) -> void:
	var t := _tab(id)
	if t.is_empty(): return
	_ensure_built(t)
	var changed := id != current_id
	current_id = id
	for o in tabs:
		var on: bool = o.id == id
		var b: Kit.NeonButton = o.btn
		b.set_kind("primary" if on else "tab", Kit.CYAN)
		if o.node != null and not on: o.node.visible = false
	var n: Control = t.node
	n.visible = true
	if n.has_method("refresh"): n.call("refresh")
	if _tab_tw and _tab_tw.is_valid(): _tab_tw.kill()
	if changed and not instant:
		n.modulate.a = 0.0
		_tab_tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tab_tw.tween_property(n, "modulate:a", 1.0, 0.16)
	else:
		n.modulate.a = 1.0

func _tab_node(id: String) -> Control:
	var t := _tab(id)
	if t.is_empty() or not t.built: return null
	return t.node

func _send_notice(kind: String, msg: String) -> void:
	_pending_notice[kind] = msg
	for t in tabs:
		if t.built and t.node != null and t.node.has_method("notice"):
			t.node.call("notice", kind, msg)

# ------------------------------------------------------------------ lifecycle
func on_open(args: Dictionary = {}) -> void:
	refresh_header()
	_pending_notice.clear()
	if tabs.is_empty(): return
	var id := current_id
	if _tab(id).is_empty():
		id = DEFAULT_TAB if not _tab(DEFAULT_TAB).is_empty() else str(tabs[0].id)
	if args.has("tab") and not _tab(str(args.tab)).is_empty(): id = str(args.tab)
	var env_tab := OS.get_environment("NF_META_TAB")
	if env_tab != "" and not _tab(env_tab).is_empty(): id = env_tab   # screenshot harness
	set_tab(id, true)

func on_cancel() -> bool:
	return false

func refresh_all() -> void:
	refresh_header()
	if current_id != "":
		var t := _tab(current_id)
		if not t.is_empty() and t.node != null and t.node.has_method("refresh"): t.node.call("refresh")

# ------------------------------------------------------------------ hooks
func h_openMeta(_from: Variant = "menu") -> void:
	UI.show_screen("meta")

func h_closeMeta() -> void:
	UI.hide_screen("meta")

func h_refreshMetaUI() -> void:
	if is_open: refresh_all()

func h_researchNotice(msg: Variant = "") -> void:
	_send_notice("research", str(msg))

func h_growthSavedNotice(msg: Variant = "") -> void:
	_send_notice("growth", str(msg))

func h_renderGrowthControls() -> void:
	var n := _tab_node("growth")
	if n != null and n.has_method("render_controls"): n.call("render_controls")

func h_updateGrowthSummaries() -> void:
	var n := _tab_node("growth")
	if n != null and n.has_method("update_summaries"): n.call("update_summaries")

func h_renderGachaResults(results: Variant = []) -> void:
	var t := _tab("gacha")
	if t.is_empty(): return
	_ensure_built(t)
	if t.node.has_method("show_results"): t.node.call("show_results", results)

func h_libraryNotice(msg: Variant = "", _kind: Variant = "") -> void:
	_send_notice("library", str(msg))

func h_forgeNotice(msg: Variant = "", _kind: Variant = "") -> void:
	_send_notice("forge", str(msg))
