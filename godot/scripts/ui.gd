extends Node
## UI foundation: CanvasLayer root, screen router, hook bus, modal stack, toasts.
## Sim code calls UI.hook("name", [args]). Routing:
##   1. UI itself  `h_<name>`            (showInputNotice, utilityMessage, ...)
##   2. first registered screen having `h_<name>`  (gets the args; arg count is adapted)
##   3. EVERY screen having `b_<name>`   (broadcast listeners, called in addition)
## Screens are auto-discovered: res://scripts/ui/screen_<id>.gd  (see UI_GUIDE.md).

signal screen_opened(id: String)
signal screen_closed(id: String)

var layer_node: CanvasLayer
var root: Control                 # full-rect, mouse_filter ignore; add screens under it
var screens: Dictionary = {}      # id -> Control
var stack: Array = []             # ids of open screens, bottom -> top
var modals: Array = []            # open modal Controls (Kit.confirm etc.), bottom -> top
var unhandled: Dictionary = {}    # hook name -> count (diagnostics)
var _toast_box: VBoxContainer
var _mcache: Dictionary = {}
var _log_hooks := OS.get_environment("NF_HOOKLOG") != ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer_node = CanvasLayer.new()
	layer_node.layer = 10
	layer_node.name = "UILayer"
	add_child(layer_node)
	root = Control.new()
	root.name = "UIRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Kit.theme()
	layer_node.add_child(root)
	_build_toasts()
	_discover()
	# Become the LAST child of the tree root so our _input runs before Main's (modal Esc handling).
	call_deferred("_to_front_of_input")

func _to_front_of_input() -> void:
	var r := get_tree().root
	r.move_child(self, r.get_child_count() - 1)

func _discover() -> void:
	var dir := DirAccess.open("res://scripts/ui")
	if dir == null: return
	var files: Array = []
	for f in dir.get_files():
		var fn := f.trim_suffix(".remap")
		if fn.begins_with("screen_") and fn.ends_with(".gd"): files.append(fn)
	files.sort()
	for fn in files:
		var id: String = fn.trim_prefix("screen_").trim_suffix(".gd")
		var scr: Variant = load("res://scripts/ui/" + fn)
		if scr == null or not (scr is Script) or not (scr as Script).can_instantiate():
			push_warning("UI: screen script failed to load: " + fn)
			continue
		var inst: Variant = (scr as Script).new()
		if not (inst is Control):
			push_warning("UI: screen is not a Control: " + fn)
			if inst is Object and not (inst is RefCounted): (inst as Object).free()
			continue
		var c := inst as Control
		c.name = "Screen_" + id
		if "screen_id" in c: c.set("screen_id", id)
		screens[id] = c
		if c.has_method("setup"):
			c.call("setup", self)
		else:
			root.add_child(c)
			c.visible = false

# ---------------------------------------------------------------- hook router
func hook(name: String, args: Array = []) -> Variant:
	var m := "h_" + name
	var result: Variant = null
	var handled := false
	if has_method(m):
		result = _call(self, m, args)
		handled = true
	else:
		for id in screens:
			var s: Object = screens[id]
			if is_instance_valid(s) and s.has_method(m):
				result = _call(s, m, args)
				handled = true
				break
	var bm := "b_" + name
	for id in screens:
		var s2: Object = screens[id]
		if is_instance_valid(s2) and s2.has_method(bm):
			_call(s2, bm, args)
			handled = true
	if not handled:
		unhandled[name] = int(unhandled.get(name, 0)) + 1
		if _log_hooks and unhandled[name] == 1: print("UI.hook unhandled: ", name, " ", args)
	return result

## Call obj.m with args padded/truncated to the method's signature (tolerates sim/handler arity drift).
func _call(obj: Object, m: String, args: Array) -> Variant:
	var key := str(obj.get_script().get_instance_id() if obj.get_script() else obj.get_class()) + "/" + m
	var info: Array = _mcache.get(key, [])
	if info.is_empty():
		for md in obj.get_method_list():
			if md.name == m:
				info = [md.args.size(), (int(md.flags) & 32) != 0]
				break
		if info.is_empty(): info = [args.size(), true]
		_mcache[key] = info
	var n: int = info[0]
	var a := args.duplicate()
	while a.size() < n: a.append(null)
	if a.size() > n and not info[1]: a.resize(n)
	return obj.callv(m, a)

# ---------------------------------------------------------------- screens
func get_screen(id: String) -> Control:
	return screens.get(id, null)

func is_open(id: String) -> bool:
	var s: Control = screens.get(id, null)
	if s == null: return false
	if "is_open" in s: return s.get("is_open")
	return s.visible

func show_screen(id: String, args: Dictionary = {}) -> void:
	var s: Control = screens.get(id, null)
	if s == null:
		push_warning("UI.show_screen: unknown screen '%s'" % id)
		return
	stack.erase(id)
	stack.append(id)
	if s.has_method("open"): s.call("open", args)
	else: s.visible = true
	s.move_to_front()
	screen_opened.emit(id)

func hide_screen(id: String) -> void:
	var s: Control = screens.get(id, null)
	if s == null: return
	stack.erase(id)
	if s.has_method("close"): s.call("close")
	else: s.visible = false
	screen_closed.emit(id)

func toggle_screen(id: String, args: Dictionary = {}) -> void:
	if is_open(id): hide_screen(id)
	else: show_screen(id, args)

## Fade out all non-persistent screens and show `id`.
func goto(id: String, args: Dictionary = {}) -> void:
	for sid in stack.duplicate():
		if sid == id: continue
		var s: Control = screens.get(sid, null)
		if s != null and s.get("persistent") == true: continue
		hide_screen(sid)
	show_screen(id, args)

func hide_all(keep_persistent: bool = true) -> void:
	for sid in stack.duplicate():
		var s: Control = screens.get(sid, null)
		if keep_persistent and s != null and s.get("persistent") == true: continue
		hide_screen(sid)

func top_screen() -> String:
	return "" if stack.is_empty() else stack.back()

## True while any modal screen/dialog should swallow gameplay input.
func blocks_game_input() -> bool:
	if not modals.is_empty(): return true
	for id in stack:
		var s: Control = screens.get(id, null)
		if s != null and s.get("modal") == true and is_open(id): return true
	return false

## True if the pointer at `pos` (viewport coords) is over an interactive UI control.
func pointer_over_ui() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE

# ---------------------------------------------------------------- modal stack (Kit.confirm)
func push_modal(ctrl: Control, focus: Control = null) -> void:
	modals.append(ctrl)
	root.add_child(ctrl)
	ctrl.z_index = 200 + modals.size()
	ctrl.modulate.a = 0.0
	create_tween().tween_property(ctrl, "modulate:a", 1.0, 0.14)
	var f: Control = focus
	if f == null and ctrl.has_meta("focus"): f = ctrl.get_meta("focus")
	if f != null: f.call_deferred("grab_focus")
	else: Kit.focus_first(ctrl)

func pop_modal(ctrl: Control) -> void:
	modals.erase(ctrl)
	if not is_instance_valid(ctrl): return
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(ctrl, "modulate:a", 0.0, 0.10)
	tw.tween_callback(ctrl.queue_free)
	var top := top_screen()
	if modals.is_empty() and top != "" and screens.has(top):
		Kit.focus_first(screens[top])

# ---------------------------------------------------------------- input (Esc / gamepad cancel)
func _input(e: InputEvent) -> void:
	if not (e.is_action_pressed("ui_cancel") or (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE)):
		return
	if not modals.is_empty():
		var m: Control = modals.back()
		if m.has_meta("on_cancel"): (m.get_meta("on_cancel") as Callable).call()
		else: pop_modal(m)
		get_viewport().set_input_as_handled()
		return
	var top := top_screen()
	if top != "" and screens.has(top) and is_open(top):
		var s: Control = screens[top]
		if s.has_method("on_cancel") and s.call("on_cancel") == true:
			get_viewport().set_input_as_handled()
			return
	# Joypad B has no Inp binding: route to the same escape logic as the Esc key.
	if e is InputEventJoypadButton:
		Inp.handleEscape()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- toasts
func _build_toasts() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.add_theme_constant_override("separation", 8)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.z_index = 100
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_toast_box)

## kind: info | ok | warn | err | violet.  ms: lifetime.
func toast(text: String, kind: String = "info", ms: int = 2200) -> void:
	if _toast_box == null: return
	var col := Kit.kind_color(kind)
	var p := PanelContainer.new()
	var sb := Kit.box(Color(0.03, 0.05, 0.10, 0.94), Kit.with_a(col, 0.7), 1, 6, Kit.with_a(col, 0.25), 10)
	sb.content_margin_left = 16; sb.content_margin_right = 20; sb.content_margin_top = 10; sb.content_margin_bottom = 10
	sb.border_width_left = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Kit.label(text, Kit.FS_MD, Kit.TEXT)
	p.add_child(l)
	_toast_box.add_child(p)
	while _toast_box.get_child_count() > 4:
		var old := _toast_box.get_child(0)
		_toast_box.remove_child(old)
		old.queue_free()
	var m := Kit.safe_margins()
	_toast_box.position.y = float(m.t) + 8.0
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.16)
	tw.tween_interval(maxf(0.2, ms / 1000.0))
	tw.tween_property(p, "modulate:a", 0.0, 0.30)
	tw.tween_callback(p.queue_free)

# ---------------------------------------------------------------- built-in hooks
func h_showInputNotice(message: Variant = "", ms: Variant = 2200) -> void:
	toast(str(message), "info", int(ms) if ms != null else 2200)

func h_utilityMessage(message: Variant = "", kind: Variant = "info") -> void:
	toast(str(message), str(kind) if kind != null else "info", 2600)

# ---------------------------------------------------------------- drone control (原作 7889-10312)
const DRONE_DEFAULTS := {"enabled": true, "normal": true, "elite": true, "boss": true, "priority": "nearest", "output": 100}
var droneConfig: Dictionary = DRONE_DEFAULTS.duplicate()

func cleanDroneConfig(raw: Variant = {}) -> Dictionary:
	var r: Dictionary = raw if raw is Dictionary else {}
	var pr: String = str(r.get("priority", "nearest"))
	var out: float = 100.0
	if r.has("output") and (r["output"] is float or r["output"] is int):
		out = clampf(float(r["output"]), 0.0, 100.0)
	return {"enabled": r.get("enabled", true) != false, "normal": r.get("normal", true) != false,
		"elite": r.get("elite", true) != false, "boss": r.get("boss", true) != false,
		"priority": pr if pr in ["nearest", "boss", "elite", "weakest", "strongest", "aim"] else "nearest", "output": out}

func droneStats() -> Dictionary:
	var p: Dictionary = Game.player
	var n: float = maxf(0.0, float(p.droneCount))
	var damage: float = (6.0 + p.damage * float(p.get("droneDamageTransfer", 0.18))) * (p.droneDamage / 10.0)
	var rate: float = (1.1 + p.fireRate * 0.18) * (p.droneRate / 1.25)
	var fleet: float = pow(n, 0.60)
	return {"damage": damage, "rate": rate, "fleetWeight": fleet,
		"dps": damage * rate * fleet * (1.0 + p.crit * 0.25 * (p.critMult - 1.0) * 0.30)}

func droneTargetAllowed(e) -> bool:
	if e == null or e.get("_dead", false) or float(e.get("spawnDelay", 0.0)) > 0.0:
		return false
	if e.get("boss", false): return droneConfig.boss
	if e.get("elite", false): return droneConfig.elite
	return droneConfig.normal

func selectDroneTarget():
	var best = null
	var rank := INF
	var distance := INF
	var p: Dictionary = Game.player
	for e in Game.enemies:
		var d: float = U.dist2(e, p)
		if not droneTargetAllowed(e) or d > p.droneRange * p.droneRange:
			continue
		var r: float
		match droneConfig.priority:
			"boss": r = 0.0 if e.get("boss", false) else 1.0
			"elite": r = 0.0 if e.get("elite", false) else 1.0
			"weakest": r = e.hp
			"strongest": r = -e.hp
			"aim": r = U.dist2(e, Inp.mouse)
			_: r = d
		if r < rank or (r == rank and d < distance):
			best = e; rank = r; distance = d
	return best

func setDroneConfig(patch: Dictionary) -> void:
	var merged := droneConfig.duplicate()
	merged.merge(patch, true)
	droneConfig = cleanDroneConfig(merged)
	Meta.storage_set("nf_drone_control_v1", JSON.stringify(droneConfig))
	for d in Game.drones:
		d.target = null; d.targetClock = 0; d.shotCredit = 0
	if not droneConfig.enabled or droneConfig.output == 0:
		for b in Game.bullets:
			if b.get("fromDrone", false): b._dead = true
	Game.sceneDirty = true

func toggleDrones() -> void:
	setDroneConfig({"enabled": not droneConfig.enabled})
	hook("showInputNotice", ["ドローン " + ("稼働" if droneConfig.enabled else "停止") + "（機数・強化は保持）", 1600])

func load_drone_config() -> void:
	var raw = Meta.storage_get("nf_drone_control_v1")
	if raw != null and str(raw) != "":
		var j = JSON.parse_string(str(raw))
		droneConfig = cleanDroneConfig(j if j is Dictionary else {})
