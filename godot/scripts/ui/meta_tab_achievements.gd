extends Control
## Meta tab: achievements + personal records (原作 renderAchievements 6901).

const TAB_ID := "achievements"
const TAB_LABEL := "実績"
const TAB_ORDER := 70

var _root: VBoxContainer
var _count: Label
var _bar: Kit.NeonBar
var _tiles: GridContainer
var _tile_vals: Array = []
var _grid: GridContainer
var _scroll: ScrollContainer
var _cards: Dictionary = {}   # id -> {panel,title,reward,desc,check}

const TILE_NAMES := ["BEST SCORE", "BEST WAVE", "MAX CP", "MAX COMBO", "TOTAL KILLS", "CLEARS", "MAX HIT", "FRACTURE", "FAST CLEAR"]

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root = Kit.vbox(Kit.S2)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var top := Kit.panel(Kit.EMERALD, Kit.S3)
	top.brackets = false
	_root.add_child(top)
	var h := Kit.hbox(Kit.S4)
	top.body.add_child(h)
	var tl := Kit.vbox(0)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_child(Kit.label("ACHIEVEMENTS & RECORDS", Kit.FS_XS, Kit.with_a(Kit.EMERALD, 0.9), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	tl.add_child(Kit.label("実績・自己ベスト", Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	h.add_child(tl)
	var cv := Kit.vbox(4)
	cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count = Kit.label("0 / 0", Kit.FS_XL, Kit.EMERALD, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
	cv.add_child(_count)
	_bar = Kit.bar(0.0, Kit.EMERALD, "", 6)
	_bar.custom_minimum_size.x = 160
	cv.add_child(_bar)
	h.add_child(cv)
	_tiles = GridContainer.new()
	_tiles.columns = 9
	_tiles.add_theme_constant_override("h_separation", Kit.S2)
	_tiles.add_theme_constant_override("v_separation", Kit.S2)
	top.body.add_child(_tiles)
	for n in TILE_NAMES:
		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := Kit.box(Color(0.01, 0.03, 0.07, 0.55), Color(1, 1, 1, 0.07), 1, 8)
		sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 6; sb.content_margin_bottom = 6
		pc.add_theme_stylebox_override("panel", sb)
		var v := Kit.vbox(0)
		v.add_child(Kit.label(n, Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, false, true))
		var val := Kit.label("0", Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
		val.clip_text = true
		v.add_child(val)
		pc.add_child(v)
		_tile_vals.append(val)
		_tiles.add_child(pc)

	_scroll = Kit.scroll_list(0)
	_root.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", Kit.S2)
	_grid.add_theme_constant_override("v_separation", Kit.S2)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.list_of(_scroll).add_child(_grid)
	for a in Meta.ACHIEVEMENTS:
		_grid.add_child(_make_card(a))
	resized.connect(_relayout)
	_relayout()

func _relayout() -> void:
	if _grid == null: return
	_tiles.columns = clampi(int(size.x / 150.0), 2, 9)
	var cols := clampi(int(size.x / 420.0), 1, 3)
	if cols != _grid.columns: _grid.columns = cols

func _make_card(a: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size.y = 64
	var v := Kit.vbox(2)
	p.add_child(v)
	var h := Kit.hbox(Kit.S2)
	var title := Kit.label("◇ %s" % a.name, Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	h.add_child(title)
	var rw := Kit.label("+%d DATA" % int(a.reward), Kit.FS_XS, Kit.VIOLET, HORIZONTAL_ALIGNMENT_RIGHT)
	h.add_child(rw)
	v.add_child(h)
	var d := Kit.label(str(a.desc), Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(d)
	_cards[a.id] = {"panel": p, "title": title, "reward": rw, "desc": d}
	return p

func _style(p: PanelContainer, ok: bool) -> void:
	var sb := Kit.box(Color(0.06, 0.2, 0.16, 0.45) if ok else Color(0.01, 0.03, 0.07, 0.5),
		Kit.with_a(Kit.EMERALD, 0.55) if ok else Color(1, 1, 1, 0.07), 1, 10,
		Kit.with_a(Kit.EMERALD, 0.18) if ok else Color(0, 0, 0, 0), 8 if ok else 0)
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)

func refresh() -> void:
	if _root == null: return
	var s: Dictionary = Meta.achievementSummary()
	_count.text = "%d / %d" % [s.unlocked, s.total]
	_bar.set_value_smooth(float(s.unlocked) / maxf(1.0, float(s.total)))
	var fast = "—" if s.fastClear == null else "%.1fs" % float(s.fastClear)
	var vals := [Kit.num(s.bestScore), str(int(s.bestWave)), "%.2f" % s.maxCP, "x%.2f" % s.maxCombo, Kit.num(s.totalKills),
		str(int(s.clears)), Kit.num(floorf(s.maxHit)), "Wave %d" % int(s.fractureWave), fast]
	for i in vals.size(): _tile_vals[i].text = vals[i]
	for a in Meta.ACHIEVEMENTS:
		var ok: bool = Meta._truthy(Meta.meta.achievements.get(a.id))
		var c: Dictionary = _cards[a.id]
		_style(c.panel, ok)
		var t: Label = c.title
		t.text = "%s %s" % ["✓" if ok else "◇", a.name]
		t.add_theme_color_override("font_color", Color("#a7f3d0") if ok else Kit.DIM)
