extends Control
## Meta tab: analysis gacha (原作 7100-7140). Meta.doGacha(1|10) -> hook renderGachaResults -> show_results().

const TAB_ID := "gacha"
const TAB_LABEL := "解析"
const TAB_ORDER := 60
const TYPE_ORDER := ["beginner", "syntax", "card", "gear", "prism"]
const IDLE_MSG := "構文を集めるほど、作れるカードの文章とロジックが増える。"

var _root: HBoxContainer
var _type_btns: Dictionary = {}
var _desc: Label
var _odds: Label
var _pity_bar: Kit.NeonBar
var _pity_lbl: Label
var _data_lbl: Label
var _b1: Kit.NeonButton
var _b10: Kit.NeonButton
var _msg: RichTextLabel
var _grid: GridContainer
var _scroll: ScrollContainer
var _res_wrap: Control
var _tw: Tween
var _busy := false

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root = Kit.hbox(Kit.S3)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# ---- left: controls
	var lp := Kit.panel(Kit.AMBER, Kit.S4)
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lp.size_flags_stretch_ratio = 0.9
	_root.add_child(lp)
	var b := lp.body
	b.add_theme_constant_override("separation", Kit.S2)
	b.add_child(Kit.label("ANALYSIS GACHA", Kit.FS_XS, Kit.with_a(Kit.AMBER, 0.85), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	b.add_child(Kit.label("解析タイプを選択", Kit.FS_XL if not Kit.is_compact() else Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	if not Kit.is_compact():
		b.add_child(Kit.label("CRは確実な研究、DATAはランダム解析に分離。重複もDATAや装備Lvへ変換される。", Kit.FS_XS, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var tr := HFlowContainer.new()
	tr.add_theme_constant_override("h_separation", Kit.S2)
	tr.add_theme_constant_override("v_separation", Kit.S2)
	b.add_child(tr)
	for t in TYPE_ORDER:
		var tid: String = t
		var btn := Kit.button(Meta.GACHA_TYPES[tid].name, "tab", func(): _select(tid))
		btn.custom_minimum_size.x = 92
		tr.add_child(btn)
		_type_btns[tid] = btn
	_desc = Kit.label("", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	b.add_child(_desc)
	var br := Kit.hbox(Kit.S3)
	b.add_child(br)
	_b1 = Kit.button("", "primary", func(): _pull(1))
	_b10 = Kit.button("", "cta", func(): _pull(10))
	for x in [_b1, _b10]:
		x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		x.custom_minimum_size.y = 72 if not Kit.is_compact() else 76
		br.add_child(x)
	# odds + pity
	_odds = _info_row(b, "現在の内訳")
	var prow := PanelContainer.new()
	prow.add_theme_stylebox_override("panel", _info_box())
	var pv := Kit.vbox(4)
	var ph := Kit.hbox(Kit.S2)
	ph.add_child(Kit.label("高レア保証 (EPIC以上)", Kit.FS_XS, Kit.DIM))
	ph.add_child(Kit.fill_spacer())
	_pity_lbl = Kit.label("0 / 25", Kit.FS_SM, Kit.VIOLET, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
	ph.add_child(_pity_lbl)
	pv.add_child(ph)
	_pity_bar = Kit.bar(0.0, Kit.VIOLET, "", 8)
	pv.add_child(_pity_bar)
	prow.add_child(pv)
	b.add_child(prow)
	var dr := Kit.hbox(Kit.S2)
	dr.add_child(Kit.label("所持 解析データ", Kit.FS_SM, Kit.DIM))
	dr.add_child(Kit.fill_spacer())
	_data_lbl = Kit.label("0 DATA", Kit.FS_LG, Kit.VIOLET, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
	dr.add_child(_data_lbl)
	b.add_child(dr)
	b.add_child(Kit.fill_spacer())
	_msg = RichTextLabel.new()
	_msg.bbcode_enabled = true
	_msg.fit_content = true
	_msg.scroll_active = false
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.add_theme_font_size_override("normal_font_size", Kit.fs(Kit.FS_SM))
	_msg.add_theme_color_override("default_color", Kit.DIM)
	_msg.custom_minimum_size.y = 44
	b.add_child(_msg)

	# ---- right: results
	var rp := Kit.panel(Kit.VIOLET, Kit.S3)
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rp.size_flags_stretch_ratio = 1.5
	_root.add_child(rp)
	rp.body.add_child(Kit.label("RESULTS  ·  解析結果", Kit.FS_XS, Kit.with_a(Kit.VIOLET, 0.9), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_scroll = Kit.scroll_list(0)
	rp.body.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", Kit.S2)
	_grid.add_theme_constant_override("v_separation", Kit.S2)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.list_of(_scroll).add_child(_grid)
	_scroll.resized.connect(func():
		var cols := clampi(int(_scroll.size.x / 230.0), 1, 5)
		if cols != _grid.columns: _grid.columns = cols)
	_set_msg(IDLE_MSG)
	_show_empty()

func _info_box() -> StyleBoxFlat:
	var sb := Kit.box(Color(0.01, 0.03, 0.07, 0.55), Color(1, 1, 1, 0.07), 1, 8)
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	return sb

func _info_row(parent: Control, title: String) -> Label:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _info_box())
	var h := Kit.hbox(Kit.S2)
	h.add_child(Kit.label(title, Kit.FS_XS, Kit.DIM))
	var v := Kit.label("", Kit.FS_XS, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	pc.add_child(h)
	parent.add_child(pc)
	return v

func _set_msg(bb: String) -> void:
	_msg.text = bb

func _show_empty() -> void:
	for c in _grid.get_children(): c.queue_free()

func _select(tid: String) -> void:
	Meta.selectedGachaType = tid
	_update_type_ui()

func _update_type_ui() -> void:
	var sel: String = Meta.selectedGachaType
	if not Meta.GACHA_TYPES.has(sel): sel = "beginner"
	var g: Dictionary = Meta.GACHA_TYPES[sel]
	for tid in _type_btns:
		var btn: Kit.NeonButton = _type_btns[tid]
		var ac: Color = Kit.AMBER if tid == "prism" else Kit.CYAN
		btn.set_kind("primary" if tid == sel else "tab", ac)
		if tid != sel and tid == "prism": btn.add_theme_color_override("font_color", Kit.AMBER)
	_b1.text = "1回解析\n%s DATA" % Kit.num(g.cost)
	_b10.text = "10回解析\n%s DATA" % Kit.num(int(g.cost) * 9)
	_desc.text = g.desc
	_odds.text = "構文 %d%% / 完成カード %d%% / 装備 %d%%" % [roundi(g.weights[0] * 100.0), roundi(g.weights[1] * 100.0), roundi(g.weights[2] * 100.0)]

func _update_wallet() -> void:
	var pity: int = int(Meta.meta.get("pity", 0))
	_pity_lbl.text = "%d / 25" % pity
	_pity_bar.set_value_smooth(minf(1.0, pity / 25.0))
	_data_lbl.text = "%s DATA" % Kit.num(Meta.meta.get("data", 0))
	var g: Dictionary = Meta.GACHA_TYPES[Meta.selectedGachaType if Meta.GACHA_TYPES.has(Meta.selectedGachaType) else "beginner"]
	_b1.disabled = int(Meta.meta.get("data", 0)) < int(g.cost)
	_b10.disabled = int(Meta.meta.get("data", 0)) < int(g.cost) * 9

func _pull(n: int) -> void:
	var r: Dictionary = Meta.doGacha(n)
	if not r.ok:
		_set_msg("[color=#fb7185]%s[/color]" % r.error)
		UI.toast(r.error, "warn")
	# results are delivered through hook renderGachaResults -> show_results()

func refresh() -> void:
	if _root == null: return
	_update_type_ui()
	_update_wallet()

# ---------------------------------------------------------------- results
func show_results(results: Array) -> void:
	if _root == null: return
	_show_empty()
	_update_wallet()
	if _tw and _tw.is_valid(): _tw.kill()
	var refunds := 0
	var best := 1
	_tw = create_tween()
	var i := 0
	for x in results:
		refunds += int(x.get("refund", 0))
		best = maxi(best, Meta.rarityValue(x.rarity))
		var card := _result_card(x)
		_grid.add_child(card)
		card.modulate.a = 0.0
		card.pivot_offset = Vector2(60, 40)
		card.scale = Vector2(0.85, 0.85)
		var d := i * 0.07
		_tw.parallel().tween_property(card, "modulate:a", 1.0, 0.22).set_delay(d)
		_tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.26).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1
	_scroll.scroll_vertical = 0
	var msg := "解析完了。"
	if refunds > 0: msg += "重複分 [color=#a78bfa][b]%s DATA[/b][/color] を還元。" % Kit.num(refunds)
	if best >= 3: msg += "  [color=%s][b]%s 獲得![/b][/color]" % [Kit.rarity_color("LEGENDARY" if best >= 4 else "EPIC").to_html(false), "LEGENDARY" if best >= 4 else "EPIC"]
	_set_msg(msg)

func _result_card(x: Dictionary) -> Control:
	var rar: String = x.rarity
	var col := Kit.rarity_color(rar)
	var pc := PanelContainer.new()
	var hot := Meta.rarityValue(rar) >= 3
	var sb := Kit.box(Kit.with_a(Kit.RARITY[rar].tint, 0.9), Kit.with_a(col, 0.9 if hot else 0.45), 2 if hot else 1, 10,
		Kit.with_a(col, 0.4 if rar == "LEGENDARY" else (0.28 if hot else 0.0)), 14 if hot else 0)
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 10; sb.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.custom_minimum_size.y = 92
	var v := Kit.vbox(2)
	pc.add_child(v)
	var kind_txt := ""
	var title := ""
	var sub := ""
	match x.kind:
		"syntax":
			kind_txt = "構文"
			title = str(x.part.get("text", "")) if str(x.part.get("text", "")) != "" else "条件なし"
			var cost: int = int(x.part.cost)
			sub = "COST %s%d%s" % ["+" if cost >= 0 else "", cost, (" / 重複 +%dDATA" % x.refund) if x.refund else ""]
		"card":
			kind_txt = "完成カード"
			title = str(x.card.get("name", ""))
			sub = Cards.describeCard(x.card)
			if x.get("duplicate", false): sub += "  / 重複 +%dDATA" % x.refund
		_:
			kind_txt = "装備"
			title = str(x.m.name)
			sub = "Lv.%d%s" % [int(x.lv), (" / +%dDATA" % x.refund) if x.refund else ""]
	v.add_child(Kit.label("%s / %s" % [kind_txt, Kit.rarity_label(rar)], Kit.FS_XS, col, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	v.add_child(Kit.label(title, Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, true))
	v.add_child(Kit.label(sub, Kit.FS_XS, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	return pc
