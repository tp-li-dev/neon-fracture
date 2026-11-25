extends Control
## META tab: カード構文工房 (card syntax forge). Port of renderForge / updateForgePreview / createForgedCard.

const TAB_ID := "forge"
const TAB_LABEL := "工房"
const TAB_ORDER := 30

var _built := false
var _root: BoxContainer
var _scroll: ScrollContainer
var _pick_btns: Dictionary = {}     # type -> NeonButton
var _name_edit: LineEdit
var _owned_key := ""
# preview widgets
var _card_panel: Kit.GlassPanel
var _rarity_lbl: Label
var _cost_chip_box: HBoxContainer
var _name_lbl: Label
var _desc_lbl: Label
var _cost_bar: Kit.NeonBar
var _mech_lbl: Label
var _status: MetaUI.Notice
var _create_btn: Kit.NeonButton
var _dup_btn: Kit.NeonButton
var _open_btn: Kit.NeonButton
var _notice: MetaUI.Notice
var _got_notice := false
var _dup_id := ""
var _syntax_box: HFlowContainer

func build() -> void:
	if _built: return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	_root = BoxContainer.new()
	_root.add_theme_constant_override("separation", Kit.S4)
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_root)
	_root.custom_minimum_size.x = 300
	_build_parts_panel()
	_build_preview_panel()
	_scroll.resized.connect(_layout)
	_layout()

func _layout() -> void:
	if _root == null: return
	var narrow := _scroll.size.x < 860.0
	if _root.vertical != narrow: _root.vertical = narrow
	_root.custom_minimum_size.x = maxf(300.0, _scroll.size.x - 14.0)

# ------------------------------------------------------------------ left: parts
func _build_parts_panel() -> void:
	var p := Kit.panel(Kit.VIOLET, Kit.S4)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_root.add_child(p)
	p.body.add_theme_constant_override("separation", Kit.S3)
	p.body.add_child(Kit.heading("カード構文工房", Kit.VIOLET, Kit.FS_LG))
	p.body.add_child(Kit.label("解析済みの構文を組み合わせて、固有のカードを無料で作成します。", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	for type in Meta.CARD_FIELDS:
		var row := Kit.hbox(Kit.S3)
		var l := Kit.label(MetaUI.PART_LABELS[type], Kit.FS_MD, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, false, true)
		l.custom_minimum_size.x = 84 if not Kit.is_compact() else 96
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		var b := Kit.button("", "ghost")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t: String = type
		b.pressed.connect(func(): _open_picker(t))
		var arrow := Kit.label("▾", Kit.FS_MD, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
		arrow.offset_right = -12
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(arrow)
		row.add_child(b)
		p.body.add_child(row)
		_pick_btns[type] = b
	_name_edit = LineEdit.new()
	_name_edit.max_length = 64
	_name_edit.placeholder_text = "カード名（任意・64文字まで／空欄なら自動命名）"
	_name_edit.clear_button_enabled = true
	_name_edit.custom_minimum_size.y = Kit.btn_h()
	_name_edit.add_theme_font_size_override("font_size", Kit.fs(Kit.FS_MD))
	_name_edit.text_changed.connect(func(_t): _update_preview())
	p.body.add_child(Kit.spacer(Kit.S1))
	p.body.add_child(Kit.label("カード名", Kit.FS_SM, Kit.DIM))
	p.body.add_child(_name_edit)

func _open_picker(type: String) -> void:
	var items: Array = []
	for part in Meta.CARD_PARTS[type]:
		var owned: bool = bool(Meta._truthy(Meta.meta.syntax.get(part.id)))
		var lab: String = (part.get("icon", "") + " " if part.has("icon") else "") + (part.text if part.text != "" else "条件なし")
		items.append({"id": part.id, "label": ("未解析 · " if not owned else "") + lab,
			"tag": "%s%d" % ["+" if int(part.cost) >= 0 else "", int(part.cost)] + (" · " + Kit.rarity_label(part.rarity) if part.has("rarity") else ""),
			"color": Kit.rarity_color(part.get("rarity", "COMMON")), "disabled": not owned})
	MetaUI.pick(MetaUI.PART_LABELS[type], items, Cards.forgeSelection.get(type), func(id):
		Cards.forgeSelection[type] = id
		_notice.show_msg("")
		_update_preview(), Kit.VIOLET)

# ------------------------------------------------------------------ right: preview
func _build_preview_panel() -> void:
	var col := Kit.vbox(Kit.S3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_root.add_child(col)
	_card_panel = Kit.panel(Kit.CYAN, Kit.S4)
	col.add_child(_card_panel)
	var b := _card_panel.body
	b.add_theme_constant_override("separation", Kit.S2)
	var top := Kit.hbox(Kit.S3)
	_rarity_lbl = Kit.label("コモン", Kit.FS_SM, Kit.SLATE, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	top.add_child(_rarity_lbl)
	top.add_child(Kit.fill_spacer())
	_cost_chip_box = Kit.hbox(0)
	top.add_child(_cost_chip_box)
	b.add_child(top)
	_name_lbl = Kit.label("", Kit.FS_XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, true)
	b.add_child(_name_lbl)
	b.add_child(Kit.hsep())
	_desc_lbl = Kit.label("", Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	b.add_child(_desc_lbl)
	_cost_bar = Kit.bar(0.0, Kit.CYAN, "", 20)
	b.add_child(_cost_bar)
	_mech_lbl = Kit.label("", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	b.add_child(_mech_lbl)
	_status = MetaUI.Notice.new()
	col.add_child(_status)
	_create_btn = Kit.button("このカードを作成（無料）", "cta", _on_create)
	col.add_child(_create_btn)
	var links := Kit.hbox(Kit.S3)
	_dup_btn = Kit.button("保有カードを表示", "ghost", func(): _show_in_library(_dup_id))
	_dup_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_btn = Kit.button("作成カードを保管庫で開く", "ghost", func(): _show_in_library(String(Cards.forgeLastCreated)))
	_open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dup_btn.visible = false
	_open_btn.visible = false
	links.add_child(_dup_btn)
	links.add_child(_open_btn)
	col.add_child(links)
	_notice = MetaUI.Notice.new()
	col.add_child(_notice)
	var sp := Kit.panel(Kit.CYAN, Kit.S3)
	col.add_child(sp)
	sp.body.add_child(Kit.label("解析済み構文", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_syntax_box = HFlowContainer.new()
	_syntax_box.add_theme_constant_override("h_separation", Kit.S2)
	_syntax_box.add_theme_constant_override("v_separation", Kit.S2)
	sp.body.add_child(_syntax_box)

# ------------------------------------------------------------------ logic
func refresh() -> void:
	if not _built: return
	# renderForge: keep selections valid & parts that are unlocked
	var key := ""
	for type in Meta.CARD_FIELDS:
		var ids: Array = []
		for p in Meta.unlockedParts(type): ids.append(p.id)
		key += ",".join(ids) + "|"
		var sel = Cards.forgeSelection.get(type)
		if not (sel in ids):
			Cards.forgeSelection[type] = ids[0] if ids.size() > 0 else ""
	_owned_key = key
	MetaUI.clear_children(_syntax_box)
	for type in Meta.CARD_PARTS:
		var owned := Meta.unlockedParts(type).size()
		var total: int = Meta.CARD_PARTS[type].size()
		_syntax_box.add_child(Kit.chip(MetaUI.PART_LABELS.get(type, type), "%d / %d" % [owned, total], Kit.EMERALD if owned >= total else Kit.CYAN))
	Cards.forgeOwnedKey = key
	_update_preview()

func _candidate() -> Dictionary:
	var sel: Dictionary = {}
	for k in Meta.CARD_FIELDS: sel[k] = Cards.forgeSelection.get(k, "")
	return Meta.forgeCandidate(sel, _name_edit.text)

func _update_preview() -> void:
	var card := _candidate()
	var rar: String = card.rarity
	var col := Kit.rarity_color(rar)
	# part buttons
	for type in Meta.CARD_FIELDS:
		var b: Kit.NeonButton = _pick_btns[type]
		var part: Dictionary = Meta.PART_BY_ID.get(Cards.forgeSelection.get(type), {})
		var pc := Kit.rarity_color(part.get("rarity", "COMMON")) if not part.is_empty() else Kit.MUTE
		b.text = ("%s%s" % [(part.icon + " ") if part.has("icon") else "", MetaUI.part_label(part)]) if not part.is_empty() else "（未解析）"
		var nrm := Kit.box(Kit.with_a(pc, 0.07), Kit.with_a(pc, 0.5), 1)
		nrm.border_width_left = 4
		var hov := Kit.box(Kit.with_a(pc, 0.18), pc, 1)
		hov.border_width_left = 4
		for s in [nrm, hov]:
			s.content_margin_left = 14; s.content_margin_right = 34; s.content_margin_top = 8; s.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", nrm)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_color_override("font_color", Kit.TEXT)
	# card preview
	_card_panel.set_accent(col)
	_rarity_lbl.text = Kit.rarity_label(rar)
	_rarity_lbl.add_theme_color_override("font_color", col)
	MetaUI.clear_children(_cost_chip_box)
	_cost_chip_box.add_child(Kit.chip("COST", "%d / 15" % int(card.cost), Kit.ROSE if int(card.cost) > 15 else col))
	_name_lbl.text = card.name
	_name_lbl.add_theme_color_override("font_color", col.lightened(0.55))
	_desc_lbl.text = Cards.describeCard(card)
	_cost_bar.color = Kit.ROSE if int(card.cost) > 15 else col
	_cost_bar.set_value_instant(clampf(float(card.cost) / 15.0, 0.0, 1.0))
	var extra := ""
	if card.effect == "chargebeam": extra = "0.65秒チャージ後に発射 · "
	elif card.effect in ["meteor", "gravitywell"]: extra = "予告の後に発動 · "
	_mech_lbl.text = "再発動間隔 %.2f秒 · %s本体由来のトリガーのみ。ドローンからは発動しません。" % [Cards.cardCooldown(card), extra]
	# validation
	var err: String = Meta.forgeValidation(card)
	var dup = Cards.findDuplicateCard(card)
	_status.show_msg(err if err != "" else "作成できます。CR・DATAは消費しません。", "warn" if err != "" else "ok")
	_create_btn.disabled = err != ""
	_create_btn.text = "同一構成を保有済み" if dup != null else ("構文を調整してください" if err != "" else "このカードを作成（無料）")
	_dup_id = String(dup.id) if dup != null else ""
	_dup_btn.visible = dup != null
	_open_btn.visible = Cards.forgeLastCreated != null and Meta.meta.cards.any(func(c): return c.id == Cards.forgeLastCreated)

func _on_create() -> void:
	var card := _candidate()
	var err: String = Meta.forgeValidation(card)
	if err != "":
		_notice.show_msg(err, "warn")
		_update_preview()
		return
	_got_notice = false
	if Meta.createForgedCard(card):
		Cards.forgeLastCreated = card.id
		if not _got_notice:
			_notice.show_msg("「%s」を作成しました。保管庫から装備できます。" % card.name, "ok")
	elif not _got_notice:
		_notice.show_msg("カードを作成できませんでした。", "warn")
	_update_preview()

func _show_in_library(id: String) -> void:
	var lib := MetaUI.find_tab("library")
	if lib == null or id == "": return
	MetaUI.goto_tab("library")
	if lib.has_method("show_card"): lib.call("show_card", id)

## forgeNotice from Meta/Cards (kind: "ok" | "warn").
func notice(kind: String, msg: String) -> void:
	_got_notice = true
	_notice.show_msg(msg, kind)
