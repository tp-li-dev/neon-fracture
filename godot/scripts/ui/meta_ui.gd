class_name MetaUI
extends RefCounted
## Shared widgets for the meta-screen tabs (forge / library / gear). Not a tab itself
## (file name does not start with meta_tab_). Use via the global class MetaUI.

const PART_LABELS := {"trigger": "トリガー", "condition": "条件", "chance": "確率", "effect": "効果", "power": "強度"}
const RARITIES := ["COMMON", "RARE", "EPIC", "LEGENDARY"]
const SLOT_COLOR := {"core": Color("#e879f9"), "armor": Color("#34d399"), "drive": Color("#22d3ee")}

static func rarity_value(r: String) -> int:
	return int(Cards.rarityRank.get(r, 1))

static func part_label(p: Dictionary) -> String:
	var t: String = p.get("text", "")
	var cost: int = int(p.get("cost", 0))
	return "%s [%s%d]" % [t if t != "" else "条件なし", "+" if cost >= 0 else "", cost]

# ------------------------------------------------------------------ modal picker
## items: [{id, label, tag, color, disabled}]. on_pick(id).
static func pick(title: String, items: Array, current: Variant, on_pick: Callable, accent: Color = Kit.CYAN) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	var p := Kit.panel(accent, Kit.S4)
	p.custom_minimum_size.x = clampf(UI.root.size.x * 0.5, 360.0, 620.0)
	cc.add_child(p)
	p.body.add_theme_constant_override("separation", Kit.S3)
	p.body.add_child(Kit.heading(title, accent, Kit.FS_LG))
	var rowh := Kit.btn_h() + 6
	var maxh := maxf(160.0, UI.root.size.y * 0.66)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = minf(maxh, rowh * items.size() + 4)
	sc.follow_focus = true
	var list := Kit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	p.body.add_child(sc)
	var close := func():
		UI.pop_modal(root)
	var focus_btn: Control = null
	for it in items:
		var col: Color = it.get("color", accent)
		var on: bool = it.id == current
		var b := Kit.button(String(it.label), "ghost")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nrm := Kit.box(Kit.with_a(col, 0.20) if on else Color(1, 1, 1, 0.03), Kit.with_a(col, 0.9) if on else Color(1, 1, 1, 0.14), 1)
		nrm.border_width_left = 4
		nrm.border_color = col if on else Kit.with_a(col, 0.6)
		var hov := Kit.box(Kit.with_a(col, 0.16), col, 1)
		hov.border_width_left = 4
		for s in [nrm, hov]:
			s.content_margin_left = 16; s.content_margin_right = 90; s.content_margin_top = 8; s.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", nrm)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_color_override("font_color", Color.WHITE if on else (Kit.TEXT if not it.get("disabled", false) else Kit.MUTE))
		b.add_theme_color_override("font_disabled_color", Kit.MUTE)
		if it.get("disabled", false):
			b.disabled = true
		var tg: String = String(it.get("tag", ""))
		if tg != "":
			var tl := Kit.label(tg, Kit.FS_SM, col if not it.get("disabled", false) else Kit.MUTE, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
			tl.set_anchors_preset(Control.PRESET_FULL_RECT)
			tl.offset_right = -14
			tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			b.add_child(tl)
		var id: Variant = it.id
		b.pressed.connect(func():
			close.call()
			on_pick.call(id))
		list.add_child(b)
		if on or (focus_btn == null and not b.disabled): focus_btn = b
	var cb := Kit.button("閉じる", "ghost", func(): close.call())
	p.body.add_child(cb)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed: close.call())
	root.set_meta("on_cancel", func(): close.call())
	root.set_meta("focus", focus_btn if focus_btn != null else cb)
	UI.push_modal(root)
	if focus_btn != null:
		sc.call_deferred("ensure_control_visible", focus_btn)

# ------------------------------------------------------------------ filter button
## Button showing "title: value"; opens a picker. items: [{id,label,color}]; value "all" = inactive.
class Filter extends Kit.NeonButton:
	signal changed
	var title := ""
	var items: Array = []
	var value: Variant = "all"
	func _init(t: String = "", its: Array = [], accent_col: Color = Kit.CYAN) -> void:
		super._init("ghost")
		title = t
		items = its
		clip_text = true
		accent = accent_col
		custom_minimum_size.x = 120
		pressed.connect(func():
			MetaUI.pick(title, items, value, func(id): set_value(id, true), accent))
		_sync()
	func set_value(v: Variant, emit: bool = false) -> void:
		value = v
		_sync()
		if emit: changed.emit()
	func _sync() -> void:
		var lab := String(value)
		var col := accent
		for it in items:
			if it.id == value:
				lab = String(it.label)
				col = it.get("color", accent)
		text = lab
		if value == "all":
			set_kind("ghost")
		else:
			set_kind("primary", col)

# ------------------------------------------------------------------ notice bar
class Notice extends PanelContainer:
	var _l: Label
	func _init() -> void:
		_l = Kit.label("", Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
		add_child(_l)
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func show_msg(msg: String, kind: String = "ok") -> void:
		if msg.strip_edges() == "":
			visible = false
			return
		var col := Kit.kind_color(kind)
		var sb := Kit.box(Kit.with_a(col, 0.10), Kit.with_a(col, 0.55), 1, 6)
		sb.border_width_left = 4
		sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 7; sb.content_margin_bottom = 7
		add_theme_stylebox_override("panel", sb)
		_l.add_theme_color_override("font_color", col.lightened(0.45))
		_l.text = msg
		visible = true

# ------------------------------------------------------------------ pager
class Pager extends HBoxContainer:
	signal go(delta: int)
	var prev: Kit.NeonButton
	var next: Kit.NeonButton
	var info: Label
	func _init() -> void:
		add_theme_constant_override("separation", Kit.S3)
		alignment = BoxContainer.ALIGNMENT_CENTER
		prev = Kit.button("‹ 前へ", "ghost", func(): go.emit(-1))
		next = Kit.button("次へ ›", "ghost", func(): go.emit(1))
		prev.custom_minimum_size.x = 110
		next.custom_minimum_size.x = 110
		info = Kit.label("1 / 1", Kit.FS_MD, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, false, true)
		info.custom_minimum_size.x = 80
		add_child(prev); add_child(info); add_child(next)
	func set_state(page: int, pages: int) -> void:
		info.text = "%d / %d" % [page + 1, pages]
		prev.disabled = page <= 0
		next.disabled = page >= pages - 1
		visible = pages > 1

# ------------------------------------------------------------------ tile
## Rarity-coloured tile used for library cards and gear modules.
class Tile extends PanelContainer:
	signal pressed
	var col := Kit.SLATE
	var rarity := "COMMON"
	var equipped := false
	var locked := false
	var selected := false:
		set(v):
			selected = v
			_style()
	var pips := -1          # 0..5 level pips (-1 = none)
	var pip_count := 0
	var _hover := false
	var _name: Label
	var _badge: Label
	func _init(r: String, icon: String, title: String, sub: String, desc: String, foot: String, badge: String = "") -> void:
		rarity = r if Kit.RARITY.has(r) else "COMMON"
		col = Kit.rarity_color(rarity)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(200, 168 if Kit.is_compact() else 148)
		var m := MarginContainer.new()
		for s in ["left", "top", "right", "bottom"]: m.add_theme_constant_override("margin_" + s, 12)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		var v := Kit.vbox(4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(v)
		var top := Kit.hbox(8)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := PanelContainer.new()
		ic.add_theme_stylebox_override("panel", Kit.box(Kit.with_a(col, 0.16), Kit.with_a(col, 0.6), 1, 18))
		ic.custom_minimum_size = Vector2(34, 34)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var il := Kit.label(icon, Kit.FS_LG, col, HORIZONTAL_ALIGNMENT_CENTER)
		il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ic.add_child(il)
		top.add_child(ic)
		var tv := Kit.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name = Kit.label(title, Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
		_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_name.clip_text = true
		tv.add_child(_name)
		var sl := Kit.label(sub, Kit.FS_XS, col)
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sl.clip_text = true
		tv.add_child(sl)
		top.add_child(tv)
		_badge = Kit.label(badge, Kit.FS_SM, Kit.AMBER, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
		top.add_child(_badge)
		v.add_child(top)
		var dl := Kit.label(desc, Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
		dl.max_lines_visible = 3
		dl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		dl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(dl)
		var fl := Kit.label(foot, Kit.FS_XS, Kit.MUTE)
		fl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		fl.clip_text = true
		v.add_child(fl)
		mouse_entered.connect(func(): _hover = true; _style())
		mouse_exited.connect(func(): _hover = false; _style())
		focus_entered.connect(_style)
		focus_exited.connect(_style)
		_style()

	func set_pips(level: int, count: int = 5) -> void:
		pips = level
		pip_count = count
		queue_redraw()

	func _style() -> void:
		var hot := _hover or has_focus() or selected
		var tint: Color = Kit.RARITY[rarity].tint
		var border := Kit.with_a(col, 0.95 if hot else 0.42)
		var bw := 2 if hot else 1
		if equipped:
			border = Kit.EMERALD
			bw = 2
		var sb := Kit.box(Kit.with_a(tint, 0.55 if locked else 0.92), border, bw, 8,
			Kit.with_a(Kit.EMERALD if equipped else col, 0.30 if hot else (0.22 if equipped else 0.08)), 12 if hot else 8)
		add_theme_stylebox_override("panel", sb)
		modulate = Color(1, 1, 1, 0.62) if locked and not hot else Color.WHITE
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or e.is_action_pressed("ui_accept"):
			accept_event()
			pressed.emit()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_polygon(PackedVector2Array([Vector2(2, 2), Vector2(w - 2, 2), Vector2(w - 2, h * 0.5), Vector2(2, h * 0.5)]),
			PackedColorArray([Kit.with_a(col, 0.14), Kit.with_a(col, 0.14), Kit.with_a(col, 0.0), Kit.with_a(col, 0.0)]))
		draw_line(Vector2(w - 14, 0), Vector2(w, 14), Kit.with_a(col, 0.9), 2.0)
		if pips >= 0:
			for i in pip_count:
				var cx := w - 18.0 - (pip_count - 1 - i) * 13.0
				var on := i < pips
				draw_rect(Rect2(cx - 4, h - 20, 8, 8), col if on else Color(1, 1, 1, 0.12))
		if equipped:
			draw_rect(Rect2(0, 0, 4, h), Kit.EMERALD)

# ------------------------------------------------------------------ misc
static func scroll_grid(cols_min_w: int = 220) -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.follow_focus = true
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", Kit.S3)
	g.add_theme_constant_override("v_separation", Kit.S3)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(g)
	sc.resized.connect(func():
		var w := sc.size.x - 14.0
		var mw := cols_min_w * (1.15 if Kit.is_compact() else 1.0)
		var n := maxi(1, int((w + Kit.S3) / (mw + Kit.S3)))
		if g.columns != n: g.columns = n)
	return [sc, g]

static func empty_label(text: String) -> Control:
	var l := Kit.label(text, Kit.FS_MD, Kit.MUTE, HORIZONTAL_ALIGNMENT_CENTER, true)
	l.custom_minimum_size.y = 120
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

static func clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

static func find_tab(tab_id: String) -> Control:
	var meta_scr: Control = UI.get_screen("meta")
	if meta_scr == null: return null
	return _find(meta_scr, tab_id)

static func _find(n: Node, tab_id: String) -> Control:
	if n is Control and "TAB_ID" in n and n.get("TAB_ID") == tab_id: return n
	for c in n.get_children():
		var r := _find(c, tab_id)
		if r != null: return r
	return null

## Ask the meta shell to switch to a tab (shell API, if present: set_tab / select_tab / show_tab).
static func goto_tab(tab_id: String) -> void:
	var meta_scr: Control = UI.get_screen("meta")
	if meta_scr == null: return
	for m in ["set_tab", "select_tab", "show_tab", "setMetaTab"]:
		if meta_scr.has_method(m):
			meta_scr.call(m, tab_id)
			return
