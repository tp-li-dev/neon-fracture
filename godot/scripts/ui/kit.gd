class_name Kit
extends RefCounted
## NEON FRACTURE UI design system. All procedural (StyleBoxFlat + _draw), no image assets.
## Static helpers + a shared Theme (installed on UI.root, so every screen inherits it).
## See UI_GUIDE.md.

# ------------------------------------------------------------------ palette
const BG := Color("#05070d")
const BG2 := Color("#0a1020")
const PANEL := Color(0.040, 0.063, 0.118, 0.88)
const PANEL_HI := Color(0.075, 0.110, 0.190, 0.92)
const CYAN := Color("#22d3ee")
const VIOLET := Color("#a78bfa")
const FUCHSIA := Color("#e879f9")
const AMBER := Color("#fbbf24")      # CR / currency
const EMERALD := Color("#34d399")
const ROSE := Color("#fb7185")
const SLATE := Color("#94a3b8")
const TEXT := Color("#e2e8f0")
const DIM := Color("#94a3b8")
const MUTE := Color("#64748b")
const LINE := Color(1, 1, 1, 0.10)

## Rarity colours from the original (COMMON slate / RARE cyan / EPIC violet / LEGENDARY amber).
const RARITY := {
	"COMMON": {"color": Color("#94a3b8"), "label": "コモン", "tint": Color("#1c2535")},
	"RARE": {"color": Color("#22d3ee"), "label": "レア", "tint": Color("#0e2a3a")},
	"EPIC": {"color": Color("#a78bfa"), "label": "エピック", "tint": Color("#26253c")},
	"LEGENDARY": {"color": Color("#fbbf24"), "label": "レジェンダリー", "tint": Color("#342e23")},
}

# spacing scale (8px grid) and type scale
const S1 := 4
const S2 := 8
const S3 := 12
const S4 := 16
const S5 := 24
const S6 := 32
const S7 := 48
const FS_XS := 11
const FS_SM := 13
const FS_MD := 15
const FS_LG := 18
const FS_XL := 24
const FS_2XL := 34
const FS_3XL := 48

const FONT_NAMES := ["Noto Sans CJK JP", "Noto Sans JP", "Hiragino Sans", "Yu Gothic UI", "Meiryo", "WenQuanYi Zen Hei", "sans-serif"]

static var _theme: Theme
static var _font: SystemFont
static var _font_bold: SystemFont
static var _tex_cache: Dictionary = {}

# ------------------------------------------------------------------ responsive
## Compact (mobile) layout: touch device, short window, or NF_COMPACT=1 env override.
## NB: stretch mode canvas_items keeps the canvas ~900 tall, so the *window* height is tested.
static func is_compact() -> bool:
	if OS.get_environment("NF_COMPACT") == "1": return true
	if OS.get_environment("NF_COMPACT") == "0": return false
	if Inp.touchCapable and Inp.inputMode == "touch": return true
	if DisplayServer.window_get_size().y < 700: return true
	return false

static func ui_scale() -> float:
	return 1.2 if is_compact() else 1.0

## Font size for a base size (scaled up on compact).
static func fs(base: int) -> int:
	return int(round(base * ui_scale()))

## Spacing: n * 8px (n may be fractional).
static func sp(n: float) -> int:
	return int(round(n * 8.0))

static func btn_h() -> int:
	return 56 if is_compact() else 44

## Safe-area margins in canvas units: {"l","t","r","b"} (always >= 8).
static func safe_margins() -> Dictionary:
	var m := {"l": 8.0, "t": 8.0, "r": 8.0, "b": 8.0}
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree): return m
	var vp: Viewport = (loop as SceneTree).root
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0 or win.y <= 0: return m
	var vis := vp.get_visible_rect().size
	var k := Vector2(vis.x / win.x, vis.y / win.y)
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var wpos := Vector2(DisplayServer.window_get_position())
	if safe.size.x <= 0 or safe.size.y <= 0: return m
	var l := maxf(0.0, safe.position.x - wpos.x)
	var t := maxf(0.0, safe.position.y - wpos.y)
	var r := maxf(0.0, (wpos.x + win.x) - safe.end.x)
	var b := maxf(0.0, (wpos.y + win.y) - safe.end.y)
	# desktop windows sit inside a larger screen: ignore absurd values (> 20% of the window)
	if l > win.x * 0.2: l = 0
	if r > win.x * 0.2: r = 0
	if t > win.y * 0.2: t = 0
	if b > win.y * 0.2: b = 0
	m.l = maxf(8.0, l * k.x); m.r = maxf(8.0, r * k.x)
	m.t = maxf(8.0, t * k.y); m.b = maxf(8.0, b * k.y)
	return m

# ------------------------------------------------------------------ formatting (ja-JP)
## 12345678 -> "12,345,678"; floats are rounded.
static func num(n: Variant) -> String:
	var v: int = int(round(float(n)))
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0: out = "," + out
	return ("-" if neg else "") + out

## Compact JP magnitude: 12345 -> "1.2万", 230000000 -> "2.3億".
static func short(n: Variant) -> String:
	var v := absf(float(n))
	var sign := "-" if float(n) < 0 else ""
	if v < 10000.0: return sign + num(v)
	if v < 1.0e8: return sign + _trim(v / 1.0e4) + "万"
	return sign + _trim(v / 1.0e8) + "億"

static func _trim(x: float) -> String:
	var s := "%.1f" % x
	return s.trim_suffix(".0")

static func pct(x: float, digits: int = 0) -> String:
	return ("%." + str(digits) + "f%%") % (x * 100.0)

static func mmss(sec: float) -> String:
	var s := int(maxf(0.0, sec))
	return "%d:%02d" % [s / 60, s % 60]

static func rarity_color(r: String) -> Color:
	return RARITY.get(r, RARITY.COMMON).color

static func rarity_label(r: String) -> String:
	return RARITY.get(r, RARITY.COMMON).label

static func with_a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

# ------------------------------------------------------------------ fonts / theme
static func font(bold: bool = false) -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(FONT_NAMES)
		_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font_bold = SystemFont.new()
		_font_bold.font_names = PackedStringArray(FONT_NAMES)
		_font_bold.font_weight = 700
		_font_bold.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _font_bold if bold else _font

static func box(fill: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 6,
		shadow: Color = Color(0, 0, 0, 0), shadow_size: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.corner_detail = 5
	s.anti_aliasing = true
	s.shadow_color = shadow
	s.shadow_size = shadow_size
	return s

static func panel_style(accent: Color = CYAN, fill: Color = PANEL, glow: float = 0.14) -> StyleBoxFlat:
	return box(fill, with_a(accent, 0.38), 1, 6, with_a(accent, glow), 10)

## Procedural soft circle (slider grabbers etc.), cached.
static func circle_tex(diam: int, col: Color, ring: Color = Color(0, 0, 0, 0), glow: int = 4) -> ImageTexture:
	var key := "%d_%s_%s_%d" % [diam, col.to_html(), ring.to_html(), glow]
	if _tex_cache.has(key): return _tex_cache[key]
	var size := diam + glow * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var r := diam * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var col_out := Color(0, 0, 0, 0)
			if d <= r + glow:
				var g := clampf(1.0 - (d - r) / glow, 0.0, 1.0)
				col_out = with_a(col, 0.28 * g * g)
			if d <= r + 0.5:
				var a := clampf(r + 0.5 - d, 0.0, 1.0)
				var base := col
				if ring.a > 0.0 and d > r - 2.5: base = ring
				col_out = col_out.blend(with_a(base, a))
			img.set_pixel(x, y, col_out)
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t

static func theme() -> Theme:
	if _theme != null: return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = FS_MD
	# Label
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.0))
	# Tooltip
	var tp := box(Color(0.03, 0.05, 0.10, 0.96), with_a(CYAN, 0.5), 1, 4, with_a(CYAN, 0.18), 8)
	tp.content_margin_left = 12; tp.content_margin_right = 12; tp.content_margin_top = 8; tp.content_margin_bottom = 8
	t.set_stylebox("panel", "TooltipPanel", tp)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", FS_SM)
	# Scrollbars (thin, glowing grabber)
	for kind in ["VScrollBar", "HScrollBar"]:
		var track := box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 4)
		var gr := box(with_a(CYAN, 0.45), Color(0, 0, 0, 0), 0, 4)
		var grh := box(with_a(CYAN, 0.75), Color(0, 0, 0, 0), 0, 4)
		for s in [track, gr, grh]:
			s.content_margin_left = 3; s.content_margin_right = 3; s.content_margin_top = 3; s.content_margin_bottom = 3
		t.set_stylebox("scroll", kind, track)
		t.set_stylebox("scroll_focus", kind, track)
		t.set_stylebox("grabber", kind, gr)
		t.set_stylebox("grabber_highlight", kind, grh)
		t.set_stylebox("grabber_pressed", kind, grh)
	# HSlider
	var strack := box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.06), 1, 3)
	strack.content_margin_top = 3; strack.content_margin_bottom = 3
	var sfill := box(with_a(CYAN, 0.85), Color(0, 0, 0, 0), 0, 3, with_a(CYAN, 0.35), 6)
	sfill.content_margin_top = 3; sfill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", strack)
	t.set_stylebox("grabber_area", "HSlider", sfill)
	t.set_stylebox("grabber_area_highlight", "HSlider", sfill)
	var gt := circle_tex(18, Color("#e6fbff"), CYAN, 5)
	var gth := circle_tex(22, Color("#ffffff"), CYAN, 6)
	t.set_icon("grabber", "HSlider", gt)
	t.set_icon("grabber_highlight", "HSlider", gth)
	t.set_icon("grabber_disabled", "HSlider", circle_tex(16, MUTE, Color(0, 0, 0, 0), 2))
	t.set_constant("center_grabber", "HSlider", 0)
	# LineEdit
	var le := box(Color(0.02, 0.04, 0.09, 0.9), LINE, 1, 6)
	le.content_margin_left = 12; le.content_margin_right = 12; le.content_margin_top = 8; le.content_margin_bottom = 8
	var lef := box(Color(0.02, 0.04, 0.09, 0.95), with_a(CYAN, 0.9), 1, 6, with_a(CYAN, 0.25), 8)
	lef.content_margin_left = 12; lef.content_margin_right = 12; lef.content_margin_top = 8; lef.content_margin_bottom = 8
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", CYAN)
	t.set_color("font_placeholder_color", "LineEdit", MUTE)
	_theme = t
	return t

# ------------------------------------------------------------------ small widgets
static func label(text: String, size: int = FS_MD, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT,
		wrap: bool = false, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	if bold: l.add_theme_font_override("font", font(true))
	l.horizontal_alignment = align as HorizontalAlignment
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 40
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func heading(text: String, accent: Color = CYAN, size: int = FS_XL) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", S3)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(4, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	h.add_child(label(text, size, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

static func hsep(accent: Color = Color(1, 1, 1, 0.10)) -> Control:
	var c := ColorRect.new()
	c.color = accent
	c.custom_minimum_size = Vector2(0, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func spacer(h: int = S2, w: int = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func fill_spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func hbox(sep: int = S2) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b

static func vbox(sep: int = S2) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b

static func margin(child: Control, all: int = S4) -> MarginContainer:
	var m := MarginContainer.new()
	for s in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + s, all)
	m.add_child(child)
	return m

## Glass panel with glowing border + corner brackets. Add children to `.body`.
static func panel(accent: Color = CYAN, pad: int = S4) -> GlassPanel:
	return GlassPanel.new(accent, pad)

## kind: "primary" | "cta" (solid accent) | "ghost" | "danger" | "tab" | "success"
static func button(text: String, kind: String = "primary", cb: Callable = Callable()) -> NeonButton:
	var b := NeonButton.new(kind)
	b.text = text
	if cb.is_valid(): b.pressed.connect(cb)
	return b

static func toggle(value: bool = false, cb: Callable = Callable(), accent: Color = CYAN) -> NeonToggle:
	var t := NeonToggle.new(value, accent)
	if cb.is_valid(): t.toggled.connect(cb)
	return t

static func slider(min_v: float, max_v: float, step: float, value: float, cb: Callable = Callable()) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v; s.max_value = max_v; s.step = step; s.value = value
	s.custom_minimum_size = Vector2(200, 36 if is_compact() else 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	if cb.is_valid(): s.value_changed.connect(cb)
	return s

static func segmented(items: Array, index: int = 0, cb: Callable = Callable(), accent: Color = CYAN) -> Segmented:
	var s := Segmented.new(items, index, accent)
	if cb.is_valid(): s.selected.connect(cb)
	return s

## "LABEL  value" stat chip. value may be any string/number.
static func chip(text: String, value: Variant = null, color: Color = CYAN, icon: String = "") -> Control:
	var p := PanelContainer.new()
	var sb := box(with_a(color, 0.10), with_a(color, 0.40), 1, 14)
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := hbox(6)
	if icon != "": h.add_child(label(icon, FS_SM, color))
	h.add_child(label(text, FS_SM, DIM))
	if value != null: h.add_child(label(str(value), FS_SM, color, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	p.add_child(h)
	return p

static func bar(value: float = 0.0, color: Color = CYAN, text: String = "", height: int = 14) -> NeonBar:
	var b := NeonBar.new()
	b.color = color
	b.text = text
	b.custom_minimum_size.y = height
	b.set_value_instant(value)
	return b

static func rarity_card(rarity: String, title: String, desc: String, icon: String = "✦", level_text: String = "") -> RarityCard:
	return RarityCard.new(rarity, title, desc, icon, level_text)

## ScrollContainer (vertical) with an inner VBox: add rows to `.get_meta("list")` or use Kit.scroll_list.
static func scroll_list(sep: int = S2) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.follow_focus = true
	var v := vbox(sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	sc.set_meta("list", v)
	return sc

static func list_of(sc: ScrollContainer) -> VBoxContainer:
	return sc.get_meta("list")

## Settings row: title (+ optional description) left, control right.
static func setting_row(title: String, ctl: Control, desc: String = "") -> Control:
	var h := hbox(S4)
	var v := vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(label(title, FS_MD, TEXT))
	if desc != "": v.add_child(label(desc, FS_SM, DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	h.add_child(v)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ctl)
	return h

static func tooltip(ctl: Control, text: String) -> void:
	ctl.tooltip_text = text

## Modal confirm dialog (via UI modal stack). Esc / ui_cancel = no.
static func confirm(title: String, message: String, on_yes: Callable, on_no: Callable = Callable(),
		yes_text: String = "OK", no_text: String = "キャンセル", danger: bool = false) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	var accent := ROSE if danger else CYAN
	var p := panel(accent, S5)
	p.custom_minimum_size.x = 560 if is_compact() else 460
	cc.add_child(p)
	p.body.add_theme_constant_override("separation", S3)
	p.body.add_child(heading(title, accent, FS_LG))
	p.body.add_child(label(message, FS_MD, TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	p.body.add_child(spacer(S2))
	var row := hbox(S3)
	var no := button(no_text, "ghost")
	var yes := button(yes_text, "danger" if danger else "cta")
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no); row.add_child(yes)
	p.body.add_child(row)
	var finish := func(cb: Callable) -> void:
		UI.pop_modal(root)
		if cb.is_valid(): cb.call()
	yes.pressed.connect(func(): finish.call(on_yes))
	no.pressed.connect(func(): finish.call(on_no))
	root.set_meta("on_cancel", func(): finish.call(on_no))
	root.set_meta("focus", no if danger else yes)
	UI.push_modal(root)
	return root

static func focus_first(node: Node) -> bool:
	if node is Control and (node as Control).focus_mode == Control.FOCUS_ALL and (node as Control).is_visible_in_tree():
		if node is BaseButton and (node as BaseButton).disabled: pass
		else:
			(node as Control).grab_focus()
			return true
	for c in node.get_children():
		if focus_first(c): return true
	return false

static func kind_color(kind: String) -> Color:
	match kind:
		"ok", "success": return EMERALD
		"warn", "warning": return AMBER
		"err", "error", "danger": return ROSE
		"violet": return VIOLET
		_: return CYAN

# ================================================================== widget classes
class GlassPanel extends PanelContainer:
	var accent: Color = Kit.CYAN
	var body: VBoxContainer
	var brackets := true
	var _m: MarginContainer

	func _init(ac: Color = Kit.CYAN, pad: int = 16) -> void:
		accent = ac
		add_theme_stylebox_override("panel", Kit.panel_style(ac))
		_m = MarginContainer.new()
		for s in ["left", "top", "right", "bottom"]:
			_m.add_theme_constant_override("margin_" + s, pad)
		add_child(_m)
		body = VBoxContainer.new()
		body.add_theme_constant_override("separation", 8)
		_m.add_child(body)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_accent(ac: Color) -> void:
		accent = ac
		add_theme_stylebox_override("panel", Kit.panel_style(ac))
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# soft vertical sheen
		var pts := PackedVector2Array([Vector2(1, 1), Vector2(w - 1, 1), Vector2(w - 1, h * 0.55), Vector2(1, h * 0.55)])
		var cols := PackedColorArray([Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.045), Color(1, 1, 1, 0), Color(1, 1, 1, 0)])
		draw_polygon(pts, cols)
		# top accent hairline
		var c0 := Kit.with_a(accent, 0.0)
		var c1 := Kit.with_a(accent, 0.55)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, 1.5), Vector2(0, 1.5)]),
			PackedColorArray([c0, c1, c1, c0]))
		draw_polygon(PackedVector2Array([Vector2(w * 0.5, 0), Vector2(w, 0), Vector2(w, 1.5), Vector2(w * 0.5, 1.5)]),
			PackedColorArray([c1, c0, c0, c1]))
		if brackets:
			var bl := 16.0
			var bc := Kit.with_a(accent, 0.95)
			var o := -1.0
			draw_line(Vector2(o, o + bl), Vector2(o, o), bc, 2.0); draw_line(Vector2(o, o), Vector2(o + bl, o), bc, 2.0)
			draw_line(Vector2(w - o - bl, o), Vector2(w - o, o), bc, 2.0); draw_line(Vector2(w - o, o), Vector2(w - o, o + bl), bc, 2.0)
			draw_line(Vector2(o, h - o - bl), Vector2(o, h - o), bc, 2.0); draw_line(Vector2(o, h - o), Vector2(o + bl, h - o), bc, 2.0)
			draw_line(Vector2(w - o - bl, h - o), Vector2(w - o, h - o), bc, 2.0); draw_line(Vector2(w - o, h - o), Vector2(w - o, h - o - bl), bc, 2.0)

class NeonButton extends Button:
	var kind := "primary"
	var accent: Color = Kit.CYAN
	var glow := 0.0:
		set(v):
			glow = v
			queue_redraw()
	var _glow_sb: StyleBoxFlat
	var _tw: Tween
	var _hover := false
	var _down := false

	func _init(k: String = "primary") -> void:
		kind = k
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		alignment = HORIZONTAL_ALIGNMENT_CENTER
		custom_minimum_size.y = Kit.btn_h() if k != "tab" else Kit.btn_h() - 4
		add_theme_font_size_override("font_size", Kit.fs(Kit.FS_MD))
		add_theme_font_override("font", Kit.font(true))
		_apply_style()
		_glow_sb = Kit.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, Kit.with_a(accent, 0.0), 14)
		_glow_sb.draw_center = false
		mouse_entered.connect(func(): _hover = true; _retarget())
		mouse_exited.connect(func(): _hover = false; _retarget())
		focus_entered.connect(_retarget)
		focus_exited.connect(_retarget)
		button_down.connect(func(): _down = true; _retarget())
		button_up.connect(func(): _down = false; _retarget())
		resized.connect(func(): pivot_offset = size * 0.5)

	func set_kind(k: String, ac: Color = Color(0, 0, 0, 0)) -> void:
		kind = k
		if ac.a > 0: accent = ac
		_apply_style()

	func _apply_style() -> void:
		var ac := accent
		match kind:
			"danger": ac = Kit.ROSE
			"success": ac = Kit.EMERALD
			"ghost": ac = Kit.SLATE
			"cta": ac = Kit.CYAN
		accent = ac
		var px := 20 if kind != "tab" else 14
		var py := 10
		var normal: StyleBoxFlat
		var hover: StyleBoxFlat
		var pressed: StyleBoxFlat
		var disabled: StyleBoxFlat
		var fc := Kit.TEXT
		match kind:
			"cta":
				normal = Kit.box(Kit.with_a(ac, 0.92), Kit.with_a(Color.WHITE, 0.55), 1)
				hover = Kit.box(ac.lightened(0.18), Color.WHITE, 1)
				pressed = Kit.box(ac.darkened(0.15), Color.WHITE, 1)
				fc = Color("#03111a")
			"ghost":
				normal = Kit.box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.16), 1)
				hover = Kit.box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.42), 1)
				pressed = Kit.box(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.55), 1)
			"tab":
				normal = Kit.box(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.10), 1)
				hover = Kit.box(Color(1, 1, 1, 0.07), Kit.with_a(ac, 0.5), 1)
				pressed = Kit.box(Kit.with_a(ac, 0.22), ac, 1)
				fc = Kit.DIM
			_:
				normal = Kit.box(Kit.with_a(ac, 0.10), Kit.with_a(ac, 0.55), 1)
				hover = Kit.box(Kit.with_a(ac, 0.22), ac, 1)
				pressed = Kit.box(Kit.with_a(ac, 0.36), ac.lightened(0.2), 1)
		disabled = Kit.box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.07), 1)
		var focus := Kit.box(Color(0, 0, 0, 0), Color.WHITE, 2, 7, Kit.with_a(ac, 0.5), 10)
		focus.draw_center = false
		for s in [normal, hover, pressed, disabled]:
			s.content_margin_left = px; s.content_margin_right = px
			s.content_margin_top = py; s.content_margin_bottom = py
		add_theme_stylebox_override("normal", normal)
		add_theme_stylebox_override("hover", hover)
		add_theme_stylebox_override("pressed", pressed)
		add_theme_stylebox_override("hover_pressed", pressed)
		add_theme_stylebox_override("disabled", disabled)
		add_theme_stylebox_override("focus", focus)
		add_theme_color_override("font_color", fc)
		add_theme_color_override("font_hover_color", Color.WHITE if kind != "cta" else fc)
		add_theme_color_override("font_pressed_color", Color.WHITE if kind != "cta" else fc)
		add_theme_color_override("font_hover_pressed_color", Color.WHITE if kind != "cta" else fc)
		add_theme_color_override("font_focus_color", Color.WHITE if kind != "cta" else fc)
		add_theme_color_override("font_disabled_color", Kit.MUTE)
		if _glow_sb: _glow_sb.shadow_color = Kit.with_a(ac, glow * 0.6)
		queue_redraw()

	func _retarget() -> void:
		if not is_inside_tree(): return
		var tgt := 0.0
		if not disabled:
			if _hover or has_focus(): tgt = 1.0
			if _down: tgt = 1.4
		var sc := 0.97 if (_down and not disabled) else 1.0
		if _tw and _tw.is_valid(): _tw.kill()
		_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tw.tween_property(self, "glow", tgt, 0.14)
		_tw.tween_property(self, "scale", Vector2(sc, sc), 0.10)

	func _draw() -> void:
		if glow > 0.01 and _glow_sb:
			_glow_sb.shadow_color = Kit.with_a(accent, clampf(glow, 0.0, 1.4) * 0.45)
			draw_style_box(_glow_sb, Rect2(Vector2.ZERO, size))

class NeonToggle extends Control:
	signal toggled(on: bool)
	var value := false
	var accent: Color = Kit.CYAN
	var t := 0.0
	var _tw: Tween
	var _track: StyleBoxFlat

	func _init(v: bool = false, ac: Color = Kit.CYAN) -> void:
		value = v; t = 1.0 if v else 0.0; accent = ac
		focus_mode = Control.FOCUS_ALL
		var k := 1.2 if Kit.is_compact() else 1.0
		custom_minimum_size = Vector2(56, 30) * k
		size_flags_horizontal = Control.SIZE_SHRINK_END
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_track = StyleBoxFlat.new()
		_track.set_corner_radius_all(20)
		_track.anti_aliasing = true
		_track.border_width_left = 1; _track.border_width_right = 1; _track.border_width_top = 1; _track.border_width_bottom = 1
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func set_value(v: bool, emit: bool = false) -> void:
		if v == value: return
		value = v
		_anim()
		if emit: toggled.emit(value)

	func _anim() -> void:
		if not is_inside_tree():
			t = 1.0 if value else 0.0; queue_redraw(); return
		if _tw and _tw.is_valid(): _tw.kill()
		_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw.tween_method(func(x: float): t = x; queue_redraw(), t, 1.0 if value else 0.0, 0.16)

	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
				or (e is InputEventScreenTouch and e.pressed) \
				or e.is_action_pressed("ui_accept"):
			value = not value
			_anim()
			toggled.emit(value)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		_track.set_corner_radius_all(int(size.y * 0.5))
		_track.bg_color = Color(1, 1, 1, 0.07).lerp(Kit.with_a(accent, 0.35), t)
		_track.border_color = Color(1, 1, 1, 0.20).lerp(accent, t)
		_track.shadow_color = Kit.with_a(accent, 0.30 * t)
		_track.shadow_size = 8 if t > 0.05 else 0
		draw_style_box(_track, r)
		var pad := 4.0
		var d := size.y - pad * 2.0
		var x := lerpf(pad + d * 0.5, size.x - pad - d * 0.5, t)
		var c := Kit.SLATE.lerp(Color.WHITE, t)
		draw_circle(Vector2(x, size.y * 0.5), d * 0.5 + 3.0, Kit.with_a(accent, 0.18 * t))
		draw_circle(Vector2(x, size.y * 0.5), d * 0.5, c)
		if has_focus():
			var f := Kit.box(Color(0, 0, 0, 0), Color.WHITE, 2, int(size.y * 0.5))
			f.draw_center = false
			draw_style_box(f, r.grow(2))

class Segmented extends HBoxContainer:
	signal selected(index: int)
	var index := 0
	var accent: Color = Kit.CYAN
	var _btns: Array = []

	func _init(items: Array = [], idx: int = 0, ac: Color = Kit.CYAN) -> void:
		accent = ac
		index = idx
		add_theme_constant_override("separation", 4)
		for i in items.size():
			var b := Kit.NeonButton.new("tab")
			b.accent = ac
			b.set_kind("tab", ac)
			b.text = str(items[i])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func(): set_index(i, true))
			add_child(b)
			_btns.append(b)
		_refresh()

	func set_index(i: int, emit: bool = false) -> void:
		index = i
		_refresh()
		if emit: selected.emit(i)

	func _refresh() -> void:
		for i in _btns.size():
			var b: Kit.NeonButton = _btns[i]
			var on := i == index
			var sb := Kit.box(Kit.with_a(accent, 0.24) if on else Color(1, 1, 1, 0.02),
				accent if on else Color(1, 1, 1, 0.10), 1, 6, Kit.with_a(accent, 0.25) if on else Color(0, 0, 0, 0), 8 if on else 0)
			sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 8; sb.content_margin_bottom = 8
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_color_override("font_color", Color.WHITE if on else Kit.DIM)

class NeonBar extends Control:
	var color: Color = Kit.CYAN
	var value := 0.0
	var text := "":
		set(v):
			text = v
			queue_redraw()
	var _tw: Tween

	func set_value_instant(v: float) -> void:
		value = clampf(v, 0.0, 1.0); queue_redraw()

	func set_value_smooth(v: float, dur: float = 0.25) -> void:
		if not is_inside_tree(): set_value_instant(v); return
		if _tw and _tw.is_valid(): _tw.kill()
		_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw.tween_method(func(x: float): value = x; queue_redraw(), value, clampf(v, 0.0, 1.0), dur)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size.y = 14

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var rad := int(size.y * 0.5)
		draw_style_box(Kit.box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.10), 1, rad), r)
		if value > 0.001:
			var fw := maxf(size.y, size.x * value)
			var fr := Rect2(Vector2.ZERO, Vector2(fw, size.y)).grow(-1)
			draw_style_box(Kit.box(Kit.with_a(color, 0.85), Color(0, 0, 0, 0), 0, rad, Kit.with_a(color, 0.35), 6), fr)
			# highlight strip
			draw_rect(Rect2(fr.position + Vector2(rad * 0.6, 1), Vector2(maxf(0.0, fr.size.x - rad * 1.2), maxf(1.0, fr.size.y * 0.30))),
				Color(1, 1, 1, 0.22))
		if text != "":
			var f := Kit.font(true)
			var fsz := maxi(10, int(size.y * 0.72))
			var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz)
			if size.y >= 16:
				draw_string(f, Vector2((size.x - ts.x) * 0.5, (size.y + ts.y * 0.62) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(1, 1, 1, 0.95))

class RarityCard extends PanelContainer:
	signal pressed
	var rarity := "COMMON"
	var selected := false:
		set(v):
			selected = v
			_style()
	var _hover := false
	var _title: Label
	var _desc: Label
	var _icon: Label
	var _lv: Label
	func _init(r: String = "COMMON", title: String = "", desc: String = "", icon: String = "✦", level_text: String = "") -> void:
		rarity = r if Kit.RARITY.has(r) else "COMMON"
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(200, 132 if not Kit.is_compact() else 150)
		var col := Kit.rarity_color(rarity)
		var m := MarginContainer.new()
		for s in ["left", "top", "right", "bottom"]: m.add_theme_constant_override("margin_" + s, 14)
		add_child(m)
		var v := Kit.vbox(6)
		m.add_child(v)
		var top := Kit.hbox(10)
		var ic := PanelContainer.new()
		ic.add_theme_stylebox_override("panel", Kit.box(Kit.with_a(col, 0.16), Kit.with_a(col, 0.6), 1, 20))
		ic.custom_minimum_size = Vector2(36, 36)
		_icon = Kit.label(icon, Kit.FS_LG, col, HORIZONTAL_ALIGNMENT_CENTER)
		_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ic.add_child(_icon)
		top.add_child(ic)
		var tv := Kit.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(Kit.label(Kit.rarity_label(rarity), Kit.FS_XS, col))
		_title = Kit.label(title, Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
		tv.add_child(_title)
		top.add_child(tv)
		_lv = Kit.label(level_text, Kit.FS_SM, col, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
		top.add_child(_lv)
		v.add_child(top)
		_desc = Kit.label(desc, Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
		v.add_child(_desc)
		mouse_entered.connect(func(): _hover = true; _style())
		mouse_exited.connect(func(): _hover = false; _style())
		focus_entered.connect(func(): _style())
		focus_exited.connect(func(): _style())
		_style()

	func set_texts(title: String, desc: String, level_text: String = "") -> void:
		_title.text = title; _desc.text = desc; _lv.text = level_text

	func _style() -> void:
		var col := Kit.rarity_color(rarity)
		var tint: Color = Kit.RARITY[rarity].tint
		var hot := _hover or has_focus() or selected
		var sb := Kit.box(Kit.with_a(tint, 0.92), Kit.with_a(col, 0.95 if hot else 0.45), 2 if hot else 1, 8,
			Kit.with_a(col, 0.34 if hot else (0.16 if rarity != "COMMON" else 0.05)), 14 if hot else 8)
		add_theme_stylebox_override("panel", sb)
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
				or (e is InputEventScreenTouch and e.pressed) or e.is_action_pressed("ui_accept"):
			accept_event()
			pressed.emit()

	func _draw() -> void:
		var col := Kit.rarity_color(rarity)
		var w := size.x
		var h := size.y
		draw_polygon(PackedVector2Array([Vector2(2, 2), Vector2(w - 2, 2), Vector2(w - 2, h * 0.6), Vector2(2, h * 0.6)]),
			PackedColorArray([Kit.with_a(col, 0.16), Kit.with_a(col, 0.16), Kit.with_a(col, 0.0), Kit.with_a(col, 0.0)]))
		# corner notch
		var n := 14.0
		draw_line(Vector2(w - n, 0), Vector2(w, n), Kit.with_a(col, 0.9), 2.0)
