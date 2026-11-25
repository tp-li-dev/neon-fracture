extends Control
## META tab: 装備 (gear modules). Port of renderGear: 3 slots (core / armor / drive), module levels 1-5.

const TAB_ID := "gear"
const TAB_LABEL := "装備"
const TAB_ORDER := 50

var _built := false
var _root: VBoxContainer
var _slots_row: BoxContainer
var _search: LineEdit
var _f_slot: MetaUI.Filter
var _f_rarity: MetaUI.Filter
var _f_state: MetaUI.Filter
var _count_lbl: Label
var _notice: MetaUI.Notice
var _scroll: ScrollContainer
var _grid: GridContainer
var _pager: MetaUI.Pager

func build() -> void:
	if _built: return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_root = Kit.vbox(Kit.S2)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var top := Kit.hbox(Kit.S3)
	top.add_child(Kit.heading("装備モジュール", Kit.FUCHSIA, Kit.FS_LG))
	top.add_child(Kit.fill_spacer())
	top.add_child(Kit.label("装備は次のランから有効 · Lv.1〜5", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	_root.add_child(top)
	_slots_row = BoxContainer.new()
	_slots_row.add_theme_constant_override("separation", Kit.S3)
	_root.add_child(_slots_row)
	# search + filters
	var sr := Kit.hbox(Kit.S2)
	_search = LineEdit.new()
	_search.placeholder_text = "装備名検索（未解析の装備も検索可）"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.y = Kit.btn_h()
	_search.add_theme_font_size_override("font_size", Kit.fs(Kit.FS_MD))
	_search.text_changed.connect(func(_t): Cards.gearPage = 0; _render_grid())
	sr.add_child(_search)
	sr.add_child(Kit.button("検索をクリア", "ghost", func():
		_search.text = ""
		Cards.gearPage = 0
		_f_slot.set_value("all"); _f_rarity.set_value("all"); _f_state.set_value("all")
		_render_grid()))
	_count_lbl = Kit.label("", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_count_lbl.custom_minimum_size.x = 80
	_count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sr.add_child(_count_lbl)
	_root.add_child(sr)
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", Kit.S2)
	fr.add_theme_constant_override("v_separation", Kit.S2)
	_f_slot = MetaUI.Filter.new("装備部位", [{"id": "all", "label": "全部位"}, {"id": "core", "label": "CORE", "color": MetaUI.SLOT_COLOR.core},
		{"id": "armor", "label": "ARMOR", "color": MetaUI.SLOT_COLOR.armor}, {"id": "drive", "label": "DRIVE", "color": MetaUI.SLOT_COLOR.drive}])
	var ritems: Array = [{"id": "all", "label": "全レアリティ"}]
	for r in MetaUI.RARITIES: ritems.append({"id": r, "label": Kit.rarity_label(r), "color": Kit.rarity_color(r)})
	_f_rarity = MetaUI.Filter.new("レアリティ", ritems)
	_f_state = MetaUI.Filter.new("所持状態", [{"id": "all", "label": "すべて"}, {"id": "owned", "label": "所持", "color": Kit.CYAN},
		{"id": "equipped", "label": "装備中", "color": Kit.EMERALD}])
	for f in [_f_slot, _f_rarity, _f_state]:
		f.custom_minimum_size.x = 150
		f.changed.connect(func(): Cards.gearPage = 0; _render_grid())
		fr.add_child(f)
	_root.add_child(fr)
	_notice = MetaUI.Notice.new()
	_root.add_child(_notice)
	var sg := MetaUI.scroll_grid(240)
	_scroll = sg[0]
	_grid = sg[1]
	_root.add_child(_scroll)
	_pager = MetaUI.Pager.new()
	_pager.go.connect(func(d): Cards.gearPage += d; _render_grid())
	_root.add_child(_pager)
	resized.connect(func(): _slots_row.vertical = size.x < 640.0)

func refresh() -> void:
	if not _built: return
	_render_slots()
	_render_grid()

func notice(kind: String, msg: String) -> void:
	if _notice != null: _notice.show_msg(msg, kind)

# ------------------------------------------------------------------ slots
func _lv(id: String) -> int:
	return int(Meta.meta.modules.get(id, 0))

func _equipped(slot: String) -> String:
	var v = Meta.meta.equippedGear.get(slot)
	return String(v) if v != null else ""

func _render_slots() -> void:
	MetaUI.clear_children(_slots_row)
	for slot in Meta.GEAR_SLOTS:
		var scol: Color = MetaUI.SLOT_COLOR[slot]
		var id := _equipped(slot)
		var m: Dictionary = Meta.MODULE_BY_ID.get(id, {})
		var rcol := Kit.rarity_color(m.rarity) if not m.is_empty() else scol
		var p := Kit.panel(rcol if not m.is_empty() else scol, Kit.S3)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slots_row.add_child(p)
		p.body.add_theme_constant_override("separation", Kit.S1)
		var head := Kit.hbox(Kit.S2)
		head.add_child(Kit.label(Cards.GEAR_SLOT_LABEL[slot], Kit.FS_SM, scol, HORIZONTAL_ALIGNMENT_LEFT, false, true))
		head.add_child(Kit.fill_spacer())
		if m.is_empty():
			head.add_child(Kit.label("未装備", Kit.FS_SM, Kit.MUTE))
			p.body.add_child(head)
			p.body.add_child(Kit.label("下のリストから装備を選択", Kit.FS_SM, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
			continue
		var lv := _lv(id)
		head.add_child(Kit.label("Lv.%d/5" % lv, Kit.FS_SM, rcol, HORIZONTAL_ALIGNMENT_RIGHT, false, true))
		p.body.add_child(head)
		p.body.add_child(Kit.label("%s %s" % [m.icon, m.name], Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, true))
		p.body.add_child(Kit.label(Cards.module_desc(id, maxi(1, lv)), Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		var mid: String = id
		var nm: String = m.name
		var ub := Kit.button("解除", "ghost", func(): _toggle(mid, nm))
		p.body.add_child(ub)

# ------------------------------------------------------------------ grid
func _filtered() -> Array:
	var out: Array = []
	var q := _search.text
	for m in Meta.MODULES:
		var lv: int = _lv(m.id)
		var slot := Meta.moduleSlot(m.id)
		var eq: bool = _equipped(slot) == m.id
		if not Cards.nameMatches(m.name, q): continue
		if _f_slot.value != "all" and slot != _f_slot.value: continue
		if _f_rarity.value != "all" and m.rarity != _f_rarity.value: continue
		if _f_state.value == "owned" and lv <= 0: continue
		if _f_state.value == "equipped" and not eq: continue
		out.append(m)
	out.sort_custom(func(a, b):
		var ea := int(_equipped(Meta.moduleSlot(a.id)) == a.id); var eb := int(_equipped(Meta.moduleSlot(b.id)) == b.id)
		if ea != eb: return ea > eb
		var oa := int(_lv(a.id) > 0); var ob := int(_lv(b.id) > 0)
		if oa != ob: return oa > ob
		return MetaUI.rarity_value(a.rarity) > MetaUI.rarity_value(b.rarity))
	return out

func _render_grid() -> void:
	var list := _filtered()
	var pages := maxi(1, ceili(list.size() / float(Cards.LIBRARY_PAGE_SIZE)))
	Cards.gearPage = clampi(Cards.gearPage, 0, pages - 1)
	_count_lbl.text = "%d / %d種" % [list.size(), Meta.MODULES.size()]
	_pager.set_state(Cards.gearPage, pages)
	MetaUI.clear_children(_grid)
	if list.is_empty():
		_grid.add_child(MetaUI.empty_label("条件に一致する装備がありません。"))
		return
	var from := Cards.gearPage * Cards.LIBRARY_PAGE_SIZE
	for i in range(from, mini(list.size(), from + Cards.LIBRARY_PAGE_SIZE)):
		var m: Dictionary = list[i]
		var lv: int = _lv(m.id)
		var slot := Meta.moduleSlot(m.id)
		var eq: bool = _equipped(slot) == m.id
		var foot := "タップで装備解除" if eq else ("タップで装備" if lv > 0 else "ガチャ・ラン報酬で入手")
		var t := MetaUI.Tile.new(m.rarity, String(m.icon), String(m.name),
			"%s · %s" % [Cards.GEAR_SLOT_LABEL[slot], ("Lv.%d/5" % lv) if lv > 0 else "未解析 / Lv.1性能"],
			Cards.module_desc(m.id, maxi(1, lv)), foot, "装備中" if eq else "")
		t.equipped = eq
		t.locked = lv <= 0
		t.set_pips(lv, 5)
		var mid: String = m.id
		var nm: String = m.name
		t.pressed.connect(func(): _toggle(mid, nm))
		_grid.add_child(t)

func _toggle(id: String, nm: String) -> void:
	var lv := _lv(id)
	var slot := Meta.moduleSlot(id)
	var eq: bool = _equipped(slot) == id
	if lv <= 0 and not eq:
		_notice.show_msg("%s：未解析です。ガチャ・ラン報酬で入手できます。" % nm, "warn")
		return
	Meta.toggleEquipGear(id)
	_notice.show_msg("%s：%s" % [nm, "解除しました" if eq else "次のランから有効"], "ok")
	refresh()
