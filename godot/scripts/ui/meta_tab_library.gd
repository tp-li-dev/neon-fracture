extends Control
## META tab: カード保管庫 (card library). Port of renderCards / renderSyntaxSummary / showOwnedCard + rename/favorite/delete/equip.

const TAB_ID := "library"
const TAB_LABEL := "保管庫"
const TAB_ORDER := 40

const SORTS := [{"id": "default", "label": "標準（装備→★→レア）"}, {"id": "cost", "label": "コスト高い順"}, {"id": "name", "label": "名前順"}]

var _built := false
var _root: HBoxContainer
var _left: VBoxContainer
var _search: LineEdit
var _f_rarity: MetaUI.Filter
var _f_trigger: MetaUI.Filter
var _f_effect: MetaUI.Filter
var _f_state: MetaUI.Filter
var _f_sort: MetaUI.Filter
var _count_lbl: Label
var _equip_lbl: Label
var _slots_box: HBoxContainer
var _syntax_box: HFlowContainer
var _notice: MetaUI.Notice
var _scroll: ScrollContainer
var _grid: GridContainer
var _pager: MetaUI.Pager
var _detail_panel: Kit.GlassPanel
var _detail_body: VBoxContainer
var _modal: Control = null
var _modal_body: VBoxContainer = null
var _sel := ""
var _renaming := false
var _wide := true
var _got_notice := false

func build() -> void:
	if _built: return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_root = Kit.hbox(Kit.S4)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_left = Kit.vbox(Kit.S2)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(_left)
	_build_header()
	var sg := MetaUI.scroll_grid(230)
	_scroll = sg[0]
	_grid = sg[1]
	_left.add_child(_scroll)
	_pager = MetaUI.Pager.new()
	_pager.go.connect(func(d): Cards.libraryPage += d; _render_grid())
	_left.add_child(_pager)
	_detail_panel = Kit.panel(Kit.CYAN, Kit.S4)
	_detail_panel.custom_minimum_size.x = 340
	_detail_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_root.add_child(_detail_panel)
	var dsc := ScrollContainer.new()
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.body.add_child(dsc)
	_detail_panel.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_body = Kit.vbox(Kit.S2)
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dsc.add_child(_detail_body)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var w := size.x
	var wide := w >= 980.0
	if wide != _wide or not _detail_panel.visible == wide:
		_wide = wide
		_detail_panel.visible = wide
		if _built and _modal == null: _fill_detail(_detail_body)
	_detail_panel.custom_minimum_size.x = clampf(w * 0.30, 300.0, 400.0)

func _build_header() -> void:
	var top := Kit.hbox(Kit.S3)
	top.add_child(Kit.heading("カード保管庫", Kit.CYAN, Kit.FS_LG))
	top.add_child(Kit.fill_spacer())
	_equip_lbl = Kit.label("0 / 3 装備", Kit.FS_MD, Kit.EMERALD, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
	top.add_child(_equip_lbl)
	_left.add_child(top)
	_slots_box = Kit.hbox(Kit.S2)
	_left.add_child(_slots_box)
	# search row
	var sr := Kit.hbox(Kit.S2)
	_search = LineEdit.new()
	_search.placeholder_text = "カード名検索（名前の一部）"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.y = Kit.btn_h()
	_search.add_theme_font_size_override("font_size", Kit.fs(Kit.FS_MD))
	_search.text_changed.connect(func(_t): Cards.libraryPage = 0; _render_grid())
	sr.add_child(_search)
	sr.add_child(Kit.button("検索をクリア", "ghost", _clear_search))
	_count_lbl = Kit.label("", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_count_lbl.custom_minimum_size.x = 90
	_count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sr.add_child(_count_lbl)
	_left.add_child(sr)
	# filter row
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", Kit.S2)
	fr.add_theme_constant_override("v_separation", Kit.S2)
	var ritems: Array = [{"id": "all", "label": "全レアリティ"}]
	for r in MetaUI.RARITIES: ritems.append({"id": r, "label": Kit.rarity_label(r), "color": Kit.rarity_color(r)})
	_f_rarity = MetaUI.Filter.new("レアリティ", ritems)
	var titems: Array = [{"id": "all", "label": "全トリガー"}]
	for p in Meta.CARD_PARTS.get("trigger", []): titems.append({"id": p.id, "label": p.text, "color": Kit.rarity_color(p.get("rarity", "COMMON"))})
	_f_trigger = MetaUI.Filter.new("トリガー", titems)
	var eitems: Array = [{"id": "all", "label": "全効果"}]
	for p in Meta.CARD_PARTS.get("effect", []): eitems.append({"id": p.id, "label": p.text, "color": Kit.rarity_color(p.get("rarity", "COMMON"))})
	_f_effect = MetaUI.Filter.new("効果", eitems)
	_f_state = MetaUI.Filter.new("状態", [{"id": "all", "label": "すべて"}, {"id": "equipped", "label": "装備中", "color": Kit.EMERALD},
		{"id": "unequipped", "label": "未装備"}, {"id": "favorite", "label": "お気に入り", "color": Kit.AMBER}])
	_f_sort = MetaUI.Filter.new("並び替え", SORTS)
	_f_sort.set_value("default")
	for f in [_f_rarity, _f_trigger, _f_effect, _f_state, _f_sort]:
		f.custom_minimum_size.x = 150 if f != _f_trigger and f != _f_effect else 190
		f.changed.connect(func(): Cards.libraryPage = 0; _render_grid())
		fr.add_child(f)
	_left.add_child(fr)
	_syntax_box = HFlowContainer.new()
	_syntax_box.add_theme_constant_override("h_separation", Kit.S2)
	_syntax_box.add_theme_constant_override("v_separation", Kit.S1)
	_left.add_child(_syntax_box)
	_notice = MetaUI.Notice.new()
	_left.add_child(_notice)

# ------------------------------------------------------------------ public
func refresh() -> void:
	if not _built: return
	if Cards.libraryFocusId != null and not Meta.meta.cards.any(func(c): return c.id == Cards.libraryFocusId):
		Cards.libraryFocusId = null
	if _sel != "" and _card(_sel).is_empty(): _sel = ""
	_render_syntax()
	_render_slots()
	_render_grid()
	_refresh_detail()

## showOwnedCard(): show only this card (called from the forge tab).
func show_card(id: String) -> void:
	var c := _card(id)
	if c.is_empty():
		_notice.show_msg("そのカードは既に削除されています。判定を更新しました。", "warn")
		refresh()
		return
	for f in [_f_rarity, _f_trigger, _f_effect, _f_state]: f.set_value("all")
	_search.text = ""
	Cards.libraryPage = 0
	Cards.libraryFocusId = id
	_sel = id
	refresh()
	_notice.show_msg("工房で一致した所持カード「%s」だけを表示中。「検索をクリア」で全件に戻せます。" % c.name, "ok")

## libraryNotice from Meta/Cards.
func notice(kind: String, msg: String) -> void:
	_got_notice = true
	if _notice != null: _notice.show_msg(msg, kind)

# ------------------------------------------------------------------ data
func _card(id: String) -> Dictionary:
	for c in Meta.meta.get("cards", []):
		if c.id == id: return c
	return {}

func _is_eq(id: String) -> bool:
	return id in Meta.meta.equippedCards

func _filtered() -> Array:
	var q := _search.text
	var out: Array = []
	for c in Meta.meta.get("cards", []):
		var eq := _is_eq(c.id)
		if Cards.libraryFocusId != null and c.id != Cards.libraryFocusId: continue
		if not Cards.nameMatches(c.name, q): continue
		if _f_rarity.value != "all" and c.rarity != _f_rarity.value: continue
		if _f_trigger.value != "all" and c.get("trigger") != _f_trigger.value: continue
		if _f_effect.value != "all" and c.get("effect") != _f_effect.value: continue
		var st: String = _f_state.value
		if st == "equipped" and not eq: continue
		if st == "unequipped" and eq: continue
		if st == "favorite" and not Meta._truthy(c.get("favorite")): continue
		out.append(c)
	var sort_id: String = _f_sort.value
	out.sort_custom(func(a, b):
		var ea := int(_is_eq(a.id)); var eb := int(_is_eq(b.id))
		var fa := int(Meta._truthy(a.get("favorite"))); var fb := int(Meta._truthy(b.get("favorite")))
		if sort_id == "cost":
			if int(a.cost) != int(b.cost): return int(a.cost) > int(b.cost)
		elif sort_id == "name":
			var n := String(a.name).nocasecmp_to(String(b.name))
			if n != 0: return n < 0
		if ea != eb: return ea > eb
		if fa != fb: return fa > fb
		var ra := MetaUI.rarity_value(a.rarity); var rb := MetaUI.rarity_value(b.rarity)
		if ra != rb: return ra > rb
		return String(a.name).nocasecmp_to(String(b.name)) < 0)
	return out

# ------------------------------------------------------------------ render
func _clear_search() -> void:
	_search.text = ""
	Cards.libraryFocusId = null
	Cards.libraryPage = 0
	for f in [_f_rarity, _f_trigger, _f_effect, _f_state]: f.set_value("all")
	_notice.show_msg("")
	refresh()

func _render_syntax() -> void:
	MetaUI.clear_children(_syntax_box)
	_syntax_box.add_child(Kit.label("解析済み構文", Kit.FS_SM, Kit.MUTE))
	for type in Meta.CARD_PARTS:
		var list: Array = Meta.CARD_PARTS[type]
		var owned := 0
		for p in list:
			if Meta._truthy(Meta.meta.syntax.get(p.id)): owned += 1
		_syntax_box.add_child(Kit.chip(MetaUI.PART_LABELS.get(type, type), "%d / %d" % [owned, list.size()], Kit.CYAN if owned < list.size() else Kit.EMERALD))

func _render_slots() -> void:
	MetaUI.clear_children(_slots_box)
	_equip_lbl.text = "%d / 3 装備" % Meta.meta.equippedCards.size()
	for i in 3:
		var id := ""
		if i < Meta.meta.equippedCards.size(): id = String(Meta.meta.equippedCards[i])
		var c := _card(id) if id != "" else {}
		var col := Kit.rarity_color(c.rarity) if not c.is_empty() else Kit.MUTE
		var b := Kit.button(("%d  %s" % [i + 1, c.name]) if not c.is_empty() else "%d  空きスロット" % (i + 1), "ghost")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var nrm := Kit.box(Kit.with_a(col, 0.12) if not c.is_empty() else Color(1, 1, 1, 0.02), Kit.with_a(col, 0.7 if not c.is_empty() else 0.3), 1)
		nrm.border_width_left = 4
		nrm.content_margin_left = 12; nrm.content_margin_right = 8; nrm.content_margin_top = 6; nrm.content_margin_bottom = 6
		b.add_theme_stylebox_override("normal", nrm)
		b.add_theme_color_override("font_color", Kit.TEXT if not c.is_empty() else Kit.MUTE)
		b.disabled = c.is_empty()
		var cid := id
		b.pressed.connect(func(): _select(cid))
		_slots_box.add_child(b)

func _render_grid() -> void:
	var cards := _filtered()
	var total: int = Meta.meta.cards.size()
	var pages := maxi(1, ceili(cards.size() / float(Cards.LIBRARY_PAGE_SIZE)))
	Cards.libraryPage = clampi(Cards.libraryPage, 0, pages - 1)
	_count_lbl.text = "%d / %d枚" % [cards.size(), total]
	_pager.set_state(Cards.libraryPage, pages)
	MetaUI.clear_children(_grid)
	if cards.is_empty():
		_grid.add_child(MetaUI.empty_label("所持カードがありません。工房で作成するか、ガチャで入手しましょう。" if total == 0 else "一致するカードがありません。「検索をクリア」で全件に戻せます。"))
		return
	var from := Cards.libraryPage * Cards.LIBRARY_PAGE_SIZE
	for i in range(from, mini(cards.size(), from + Cards.LIBRARY_PAGE_SIZE)):
		var c: Dictionary = cards[i]
		var eq := _is_eq(c.id)
		var fav := Meta._truthy(c.get("favorite"))
		var t := MetaUI.Tile.new(c.rarity, _effect_icon(c), String(c.name), "%s · COST %d" % [Kit.rarity_label(c.rarity), int(c.cost)],
			Cards.describeCard(c), "再発動 %s秒%s" % [str(Cards.cardCooldown(c)), "  ·  装備中" if eq else ""], "★" if fav else "")
		t.equipped = eq
		t.selected = c.id == _sel and _wide
		t.tooltip_text = String(c.name)
		var cid: String = c.id
		t.pressed.connect(func(): _select(cid, true))
		_grid.add_child(t)

func _effect_icon(c: Dictionary) -> String:
	var p: Dictionary = Meta.PART_BY_ID.get(c.get("effect"), {})
	return String(p.get("icon", "✦"))

func _select(id: String, open_modal: bool = false) -> void:
	_sel = id
	_renaming = false
	if id == "": return
	if _wide:
		_render_grid()
		_refresh_detail()
	elif open_modal or true:
		_open_modal(id)

# ------------------------------------------------------------------ detail
func _refresh_detail() -> void:
	if _modal != null and is_instance_valid(_modal):
		if _sel == "" or _card(_sel).is_empty():
			UI.pop_modal(_modal)
			_modal = null
		else:
			_fill_detail(_modal_body)
	_fill_detail(_detail_body)

func _open_modal(id: String) -> void:
	if _modal != null and is_instance_valid(_modal): UI.pop_modal(_modal)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	var p := Kit.panel(Kit.rarity_color(_card(id).rarity), Kit.S4)
	p.custom_minimum_size.x = clampf(UI.root.size.x * 0.7, 340.0, 560.0)
	cc.add_child(p)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = minf(UI.root.size.y * 0.8, 560.0)
	p.body.add_child(sc)
	var vb := Kit.vbox(Kit.S2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	_modal = root
	_modal_body = vb
	var close := func():
		UI.pop_modal(root)
		_modal = null
	root.set_meta("on_cancel", close)
	_fill_detail(vb, close)
	UI.push_modal(root)

func _fill_detail(box: VBoxContainer, close: Callable = Callable()) -> void:
	MetaUI.clear_children(box)
	var c := _card(_sel)
	if c.is_empty():
		box.add_child(Kit.label("カードを選択すると詳細が表示されます。", Kit.FS_MD, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
		box.add_child(Kit.spacer(Kit.S2))
		box.add_child(Kit.label("装備できるカードは最大3枚。装備したカードは次のランから有効です。", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	var col := Kit.rarity_color(c.rarity)
	var eq := _is_eq(c.id)
	var fav := Meta._truthy(c.get("favorite"))
	var top := Kit.hbox(Kit.S2)
	top.add_child(Kit.label(Kit.rarity_label(c.rarity), Kit.FS_SM, col, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	top.add_child(Kit.fill_spacer())
	if eq: top.add_child(Kit.chip("装備中", null, Kit.EMERALD))
	top.add_child(Kit.chip("COST", int(c.cost), col))
	box.add_child(top)
	if _renaming:
		var le := LineEdit.new()
		le.max_length = 64
		le.text = c.name
		le.custom_minimum_size.y = Kit.btn_h()
		le.add_theme_font_size_override("font_size", Kit.fs(Kit.FS_MD))
		box.add_child(le)
		var rr := Kit.hbox(Kit.S2)
		var save := func():
			var nm := le.text.strip_edges()
			if nm == "": return
			Meta.renameCard(c.id, nm)
			_renaming = false
			_notice.show_msg("カード名を保存しました。", "ok")
			refresh()
		var sb := Kit.button("保存", "cta", save)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cb := Kit.button("取消", "ghost", func(): _renaming = false; _refresh_detail())
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(sb); rr.add_child(cb)
		box.add_child(rr)
		le.text_submitted.connect(func(_t): save.call())
		le.call_deferred("grab_focus")
	else:
		box.add_child(Kit.label(c.name, Kit.FS_XL, col.lightened(0.5), HORIZONTAL_ALIGNMENT_LEFT, true, true))
	box.add_child(Kit.hsep(Kit.with_a(col, 0.4)))
	box.add_child(Kit.label(Cards.describeCard(c), Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(Kit.label("再発動間隔 %s秒 · 本体由来のトリガーのみ。" % str(Cards.cardCooldown(c)), Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(Kit.spacer(Kit.S1))
	# parts breakdown
	for type in Meta.CARD_FIELDS:
		var part: Dictionary = Meta.PART_BY_ID.get(c.get(type), {})
		var row := Kit.hbox(Kit.S2)
		var l := Kit.label(MetaUI.PART_LABELS[type], Kit.FS_SM, Kit.MUTE)
		l.custom_minimum_size.x = 64
		row.add_child(l)
		var pt := Kit.label(MetaUI.part_label(part) if not part.is_empty() else "—", Kit.FS_SM, Kit.rarity_color(part.get("rarity", "COMMON")), HORIZONTAL_ALIGNMENT_LEFT, true)
		pt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pt)
		box.add_child(row)
	box.add_child(Kit.spacer(Kit.S2))
	# actions
	var eqb := Kit.button("装備解除" if eq else "装備する", "ghost" if eq else "cta", func(): _do_equip(c.id, close))
	box.add_child(eqb)
	var r2 := Kit.hbox(Kit.S2)
	var fb := Kit.button("★ お気に入り解除" if fav else "☆ お気に入り", "primary", func():
		Meta.toggleFavoriteCard(c.id)
		refresh())
	fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rb := Kit.button("改名", "ghost", func(): _renaming = true; _refresh_detail())
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var db := Kit.button("削除", "danger", func(): _do_delete(c.id, close))
	db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(fb); r2.add_child(rb); r2.add_child(db)
	box.add_child(r2)
	if close.is_valid():
		box.add_child(Kit.button("閉じる", "ghost", close))

func _do_equip(id: String, _close: Callable) -> void:
	var was := _is_eq(id)
	_got_notice = false
	if Meta.toggleEquipCard(id):
		_notice.show_msg("装備を解除しました。" if was else "装備しました。次のランから有効です。", "ok")
	elif not _got_notice:
		_notice.show_msg("装備枠は3枚です。別のカードを外してから装備してください。", "warn")
	refresh()

func _do_delete(id: String, close: Callable) -> void:
	var c := _card(id)
	if c.is_empty(): return
	if Meta._truthy(c.get("favorite")):
		_notice.show_msg("お気に入りを解除してから削除してください。", "warn")
		UI.toast("お気に入りを解除してから削除してください。", "warn")
		return
	var nm: String = c.name
	Kit.confirm("カードを削除", "「%s」を削除します。この操作は元に戻せません。" % nm, func():
		if Meta.deleteCard(id):
			_notice.show_msg("「%s」を削除しました。" % nm, "ok")
		if _sel == id: _sel = ""
		if _modal != null and is_instance_valid(_modal):
			UI.pop_modal(_modal)
			_modal = null
		refresh(), Callable(), "削除する", "キャンセル", true)
