extends Control
## Meta tab: CR research (原作 renderResearch 6823 / 研究カード). Batch x1/x10/x100/max.

const TAB_ID := "research"
const TAB_LABEL := "強化"
const TAB_ORDER := 20

var _root: VBoxContainer
var _base_grid: GridContainer
var _base_vals: Array = []
var _lv_title: Label
var _lv_xp: Label
var _hint: Label
var _notice: Label
var _batch: Kit.Segmented
var _grid: GridContainer
var _scroll: ScrollContainer
var _cards: Dictionary = {}   # key -> {lv,value,desc,applied,next,btn}
const BATCHES := [1, 10, 100, "max"]

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root = Kit.vbox(Kit.S2)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var comp := Kit.is_compact()

	# --- top panel: level base + batch tools
	var top := Kit.panel(Kit.CYAN, Kit.S3)
	top.brackets = false
	_root.add_child(top)
	var r1 := Kit.hbox(Kit.S4)
	top.body.add_child(r1)
	var left := Kit.vbox(2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(Kit.label("PERMANENT STATS  ·  ステータス研究", Kit.FS_XS, Kit.with_a(Kit.CYAN, 0.85), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_lv_title = Kit.label("Player Lv.1 による基礎数値", Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	left.add_child(_lv_title)
	_lv_xp = Kit.label("0 / 0 XP", Kit.FS_XS, Kit.MUTE)
	left.add_child(_lv_xp)
	r1.add_child(left)
	_base_grid = GridContainer.new()
	_base_grid.columns = 4
	_base_grid.add_theme_constant_override("h_separation", Kit.S2)
	_base_grid.add_theme_constant_override("v_separation", Kit.S2)
	for n in ["基礎攻撃", "基礎HP", "回収範囲", "弾速"]:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", _mini_box())
		var v := Kit.vbox(0)
		v.add_child(Kit.label(n, Kit.FS_XS, Kit.MUTE))
		var val := Kit.label("0", Kit.FS_MD, Color("#cffafe"), HORIZONTAL_ALIGNMENT_LEFT, false, true)
		v.add_child(val)
		pc.add_child(v)
		_base_vals.append(val)
		_base_grid.add_child(pc)
	r1.add_child(_base_grid)
	var go := Kit.button("適用Lvを調整 →", "ghost", _goto_growth)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(go)

	var r2 := Kit.hbox(Kit.S3)
	top.body.add_child(r2)
	var cap := Kit.vbox(0)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_child(Kit.label("継続研究 · 上限なし", Kit.FS_MD, Color("#a5f3fc"), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_hint = Kit.label("", Kit.FS_XS, Kit.DIM)
	_hint.clip_text = true
	cap.add_child(_hint)
	r2.add_child(cap)
	var bi := 0
	for i in BATCHES.size():
		if str(BATCHES[i]) == str(Meta.researchBatch): bi = i
	_batch = Kit.segmented(["1段", "10段", "100段", "買えるだけ"], bi, func(i: int):
		Meta.researchBatch = BATCHES[i]
		refresh(), Kit.CYAN)
	_batch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r2.add_child(_batch)
	_notice = Kit.label("", Kit.FS_SM, Kit.EMERALD)
	_notice.clip_text = true
	_notice.visible = false
	top.body.add_child(_notice)
	if not comp:
		top.body.add_child(Kit.label("数値成長はユーザーLv、割合強化はCR研究。購入済みの段数はそのまま引き継ぎます。", Kit.FS_XS, Kit.MUTE))

	# --- cards
	_scroll = Kit.scroll_list(0)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", Kit.S3)
	_grid.add_theme_constant_override("v_separation", Kit.S3)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.list_of(_scroll).add_child(_grid)
	for key in Meta.META_STATS:
		_grid.add_child(_make_card(key))
	resized.connect(_relayout)
	_relayout()

func _mini_box() -> StyleBoxFlat:
	var sb := Kit.box(Color(0.01, 0.03, 0.07, 0.55), Color(1, 1, 1, 0.07), 1, 8)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 4; sb.content_margin_bottom = 4
	return sb

func _relayout() -> void:
	if _grid == null: return
	var w := size.x
	var cols := clampi(int(w / 330.0), 1, 5)
	if cols != _grid.columns: _grid.columns = cols
	_base_grid.columns = 4 if w > 640 else 2

func _make_card(key: String) -> Control:
	var d: Dictionary = Meta.META_STATS[key]
	var p := Kit.panel(Kit.CYAN, Kit.S3)
	p.brackets = false
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := Kit.hbox(Kit.S2)
	head.add_child(Kit.label("%s %s" % [d.icon, d.name], Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	head.add_child(Kit.fill_spacer())
	var lv := Kit.label("0 段", Kit.FS_SM, Kit.DIM)
	head.add_child(lv)
	p.body.add_child(head)
	var val := Kit.label("+0%", Kit.FS_2XL, Color("#a5f3fc"), HORIZONTAL_ALIGNMENT_LEFT, false, true)
	p.body.add_child(val)
	var desc := Kit.label("", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	p.body.add_child(desc)
	p.body.add_child(Kit.hsep())
	var applied := Kit.label("", Kit.FS_XS, Color("#9bcbc8"), HORIZONTAL_ALIGNMENT_LEFT, true)
	p.body.add_child(applied)
	var nxt := Kit.label("", Kit.FS_SM, Kit.VIOLET, HORIZONTAL_ALIGNMENT_LEFT, true)
	p.body.add_child(nxt)
	p.body.add_child(Kit.fill_spacer())
	var btn := Kit.button("", "primary", func(): _buy(key))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.body.add_child(btn)
	_cards[key] = {"panel": p, "lv": lv, "value": val, "desc": desc, "applied": applied, "next": nxt, "btn": btn}
	return p

func _buy(key: String) -> void:
	if not Meta.buyStat(key):
		if Game.state != "meta": UI.toast("研究所を開いてから購入してください", "warn")
	refresh()

func _goto_growth() -> void:
	var s := UI.get_screen("meta")
	if s != null and s.has_method("set_tab"): s.call("set_tab", "growth")

func notice(kind: String, msg: String) -> void:
	if kind != "research" or _notice == null: return
	_notice.text = msg
	_notice.visible = msg != ""

func refresh() -> void:
	if _root == null: return
	var m: Dictionary = Meta.meta
	var need: int = Meta.playerXpNeeded(m.playerLevel)
	_lv_title.text = "Player Lv.%s による基礎数値" % Kit.num(m.playerLevel)
	_lv_xp.text = "%s / %s XP" % [Kit.num(floorf(float(m.get("playerXp", 0.0)))), Kit.num(need)]
	var b: Dictionary = Meta.playerLevelBase()
	_base_vals[0].text = "%.1f" % (18.0 + b.damage)
	_base_vals[1].text = str(roundi(100.0 + b.maxHp))
	_base_vals[2].text = str(roundi(115.0 + b.magnet))
	_base_vals[3].text = str(roundi(760.0 + b.bulletSpeed))
	_hint.text = Meta.growthSummary() + "。研究の購入は獲得済み段数を増やします。"
	for i in BATCHES.size():
		if str(BATCHES[i]) == str(Meta.researchBatch): _batch.set_index(i)
	var res: Dictionary = Meta.resolveGrowthLimits()
	for key in Meta.META_STATS:
		var c: Dictionary = _cards[key]
		var q: Dictionary = Meta.researchQuote(key)
		c.lv.text = "%s 段" % Meta.researchNumber(q.lv)
		c.value.text = "+%s%%" % Meta.researchNumber(Meta.research_value(key, q.lv))
		c.desc.text = Meta.research_desc(key, q.lv)
		var ap = res.stats[key]
		c.applied.text = "適用：%s段 · %s" % [Meta.researchNumber(ap), Meta.research_desc(key, ap)]
		var btn: Kit.NeonButton = c.btn
		if q.count > 0:
			c.next.text = "次：+%s%% / %s段" % [Meta.researchNumber(Meta.research_value(key, q.next)), Meta.researchNumber(q.count)]
			btn.text = "%s CR で %s段研究" % [Meta.researchNumber(q.cost), Meta.researchNumber(q.count)]
		else:
			c.next.text = "購入できるCRがありません"
			btn.text = "CR不足"
		btn.disabled = not q.valid
		btn.set_kind("primary" if q.valid else "ghost", Kit.CYAN)
