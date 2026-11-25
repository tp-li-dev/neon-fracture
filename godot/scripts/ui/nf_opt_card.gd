class_name NfOptCard
extends PanelContainer
## Selectable option card (title + description + optional tag). Emits `pressed`; `.selected` shows the active state.

signal pressed
var accent: Color = Kit.CYAN
var selected := false:
	set(v):
		selected = v
		_style()
var _hover := false
var _down := false
var title_lbl: Label
var desc_lbl: Label
var tag_lbl: Label

func _init(title: String, desc: String, ac: Color, title_col: Color = Kit.TEXT, tag: String = "") -> void:
	accent = ac
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var m := MarginContainer.new()
	for s in ["left", "top", "right", "bottom"]: m.add_theme_constant_override("margin_" + s, 12)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var v := Kit.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var top := Kit.hbox(6)
	title_lbl = Kit.label(title, Kit.FS_MD, title_col, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_lbl)
	tag_lbl = Kit.label(tag, Kit.FS_XS, ac, HORIZONTAL_ALIGNMENT_RIGHT, false, true)
	top.add_child(tag_lbl)
	v.add_child(top)
	desc_lbl = Kit.label(desc, Kit.FS_XS, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(desc_lbl)
	mouse_entered.connect(func(): _hover = true; _style())
	mouse_exited.connect(func(): _hover = false; _style())
	focus_entered.connect(func(): _style())
	focus_exited.connect(func(): _style())
	_style()

func _style() -> void:
	var hot := _hover or has_focus()
	var fill := Kit.with_a(accent, 0.20 if selected else (0.09 if hot else 0.035))
	var border := Kit.with_a(accent, 0.95 if selected else (0.7 if hot else 0.25))
	var sb := Kit.box(fill, border, 2 if (selected or has_focus()) else 1, 8,
		Kit.with_a(accent, 0.32 if selected else (0.15 if hot else 0.0)), 12 if selected else (6 if hot else 0))
	if has_focus(): sb.border_color = Color.WHITE
	add_theme_stylebox_override("panel", sb)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed: _down = true
		elif _down:
			_down = false
			if Rect2(Vector2.ZERO, size).has_point(e.position):
				accept_event()
				pressed.emit()
	elif e.is_action_pressed("ui_accept"):
		accept_event()
		pressed.emit()
