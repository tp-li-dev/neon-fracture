class_name NFScreen
extends Control
## Base class for UI screens (optional but recommended). Files: res://scripts/ui/screen_<id>.gd
## Override build() to create widgets under `content` (safe-area MarginContainer).
## Hooks: define `func h_<hookName>(args...)`.  Broadcast listeners (every screen gets them): `b_<hookName>`.

var screen_id := ""
var ui: Node                      # the UI autoload
var content: MarginContainer      # safe-area aware container, add your layout here
var backdrop: ColorRect           # optional dim layer (see dim_alpha)
var modal := false                # true: swallows pointer input behind it & shows backdrop
var persistent := false           # true: not closed by UI.goto() (HUD-like layers)
var dim_alpha := 0.0              # backdrop alpha when modal (e.g. 0.6)
var layer_z := 0                  # z-order among screens (higher on top)
var is_open := false
var fade_time := 0.18
var default_focus: Control        # focused on open (gamepad / keyboard)
var _tw: Tween

func setup(u: Node) -> void:
	ui = u
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = layer_z
	u.root.add_child(self)
	backdrop = ColorRect.new()
	backdrop.color = Color(0.0, 0.01, 0.03, dim_alpha)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	content = MarginContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	get_viewport().size_changed.connect(_apply_safe)
	_apply_safe()
	build()

## Override: create your widgets (add to `content`).
func build() -> void:
	pass

## Override: called every time the screen is shown (refresh from Game/Meta state here).
func on_open(_args: Dictionary = {}) -> void:
	pass

func on_close() -> void:
	pass

## Esc / ui_cancel while this is the top screen. Return true if consumed.
## Default false: sim-owned Esc routing (Inp.handleEscape -> hooks like closeUtility) continues.
func on_cancel() -> bool:
	return false

func _apply_safe() -> void:
	if content == null: return
	var m := Kit.safe_margins()
	content.add_theme_constant_override("margin_left", int(m.l) + (Kit.S4 if Kit.is_compact() else Kit.S5))
	content.add_theme_constant_override("margin_right", int(m.r) + (Kit.S4 if Kit.is_compact() else Kit.S5))
	content.add_theme_constant_override("margin_top", int(m.t) + Kit.S3)
	content.add_theme_constant_override("margin_bottom", int(m.b) + Kit.S3)

func open(args: Dictionary = {}) -> void:
	if _tw and _tw.is_valid(): _tw.kill()
	is_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP if modal else Control.MOUSE_FILTER_IGNORE
	if modal:
		backdrop.color.a = dim_alpha
	on_open(args)
	modulate.a = 0.0
	_tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "modulate:a", 1.0, fade_time)
	_tw.tween_callback(func(): _grab_default_focus())

func close() -> void:
	if not is_open: return
	is_open = false
	if _tw and _tw.is_valid(): _tw.kill()
	on_close()
	_tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tw.tween_property(self, "modulate:a", 0.0, fade_time * 0.8)
	_tw.tween_callback(func(): if not is_open: visible = false)

func _grab_default_focus() -> void:
	if not is_open: return
	if default_focus != null and is_instance_valid(default_focus) and default_focus.is_visible_in_tree():
		default_focus.grab_focus()
	else:
		Kit.focus_first(self)
