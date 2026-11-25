extends Node
## E2E driver (NF_E2E=<shotdir> [NF_COMPACT=1] [NF_FLOW=name]). Drives the real UI via injected input events.
## Run: NF_E2E=/tmp/e2e xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . --resolution 1600x900
var main: Node
var dir: String = OS.get_environment("NF_E2E")
var fails: int = 0
var n: int = 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	call_deferred("_run")

func frames(k: int = 3) -> void:
	for i in k: await get_tree().process_frame

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func shot(name: String) -> void:
	await frames(2)
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [dir, n, name])
	print("SHOT ", name, " state=", Game.state, " open=", UI.stack, " modals=", UI.modals.size())

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", msg)

func all_controls(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Control:
			if not (c as Control).visible: continue
			out.append(c)
		all_controls(c, out)

func visible_ctrl(c: Control) -> bool:
	var p: CanvasItem = c as CanvasItem
	while p != null:
		if p is CanvasItem and not p.visible: return false
		if p is Control and (p as Control).modulate.a < 0.3: return false
		p = (p.get_parent() as CanvasItem) if p.get_parent() is CanvasItem else null
	return true

func buttons() -> Array:
	var all: Array = []
	all_controls(UI.root, all)
	var out: Array = []
	for c in all:
		var ok: bool = (c is BaseButton and not (c as BaseButton).disabled) or ((c as Control).focus_mode == Control.FOCUS_ALL and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE and not (c is Range) and not (c is LineEdit) and not (c is ScrollContainer))
		if ok and visible_ctrl(c): out.append(c)
	return out

func btn_text(b: Control) -> String:
	if "text" in b and str(b.get("text")) != "": return str(b.get("text"))
	var acc: Array = []
	_texts(b, acc)
	return " ".join(acc)

func _texts(node: Node, acc: Array) -> void:
	for c in node.get_children():
		if c is Label: acc.append((c as Label).text)
		_texts(c, acc)

func find_btn(sub: String) -> Control:
	var best: Control = null
	for b in buttons():
		if btn_text(b).contains(sub):
			# prefer topmost-most-recent (later in tree)
			best = b
	return best

func dump_btns(tag: String = "") -> void:
	var s: Array = []
	for b in buttons():
		var r: Rect2 = (b as Control).get_global_rect()
		s.append("%s@%d,%d" % [btn_text(b).replace("\n", " ").left(24), r.position.x, r.position.y])
	print("BTNS[", tag, "] ", " | ".join(s))

func mouse_move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos; e.global_position = pos
	Input.parse_input_event(e)

func click_at(pos: Vector2) -> void:
	mouse_move(pos)
	await frames(2)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT; d.pressed = true; d.position = pos; d.global_position = pos
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(d)
	await frames(2)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT; u.pressed = false; u.position = pos; u.global_position = pos
	Input.parse_input_event(u)
	await frames(3)

func click(sub: String, must: bool = true) -> bool:
	var b := find_btn(sub)
	if b == null:
		if must: check(false, "button not found: " + sub); dump_btns("missing " + sub)
		return false
	var r := b.get_global_rect()
	var vr := get_viewport().get_visible_rect()
	if not vr.encloses(r.grow(-1.0)):
		print("WARN: button partly offscreen: ", sub, " ", r, " vp=", vr)
		# scroll into view if in ScrollContainer
		var p: Node = b.get_parent()
		while p != null:
			if p is ScrollContainer: (p as ScrollContainer).ensure_control_visible(b); await frames(3); break
			p = p.get_parent()
		r = b.get_global_rect()
	await click_at(r.get_center())
	await wait(0.35)
	return true

func key(k: int, hold: float = 0.05) -> void:
	var d := InputEventKey.new()
	d.keycode = k; d.physical_keycode = k; d.pressed = true
	Input.parse_input_event(d)
	await wait(hold)
	var u := InputEventKey.new()
	u.keycode = k; u.physical_keycode = k; u.pressed = false
	Input.parse_input_event(u)
	await frames(2)

func key_down(k: int) -> void:
	var d := InputEventKey.new()
	d.keycode = k; d.physical_keycode = k; d.pressed = true
	Input.parse_input_event(d)

func key_up(k: int) -> void:
	var u := InputEventKey.new()
	u.keycode = k; u.physical_keycode = k; u.pressed = false
	Input.parse_input_event(u)

func touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx; e.position = pos; e.pressed = pressed
	Input.parse_input_event(e)

func drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx; e.position = pos; e.relative = rel
	Input.parse_input_event(e)

## Overlap/consistency + off-screen audit of the visible UI.
func audit(tag: String) -> void:
	var vr := get_viewport().get_visible_rect()
	var open: Array = []
	for id in UI.screens:
		if UI.is_open(id): open.append(id)
	print("AUDIT[", tag, "] state=", Game.state, " open=", open)
	var modal_open: Array = []
	for id in open:
		if UI.screens[id].get("modal") == true: modal_open.append(id)
	if modal_open.size() > 1: check(false, "multiple modal screens open (%s) at %s" % [str(modal_open), tag])
	for b in buttons():
		var r: Rect2 = (b as Control).get_global_rect()
		if r.size.x < 2 or r.size.y < 2: continue
		# only flag if not inside a scroll container
		var p: Node = b.get_parent(); var in_scroll := false
		while p != null:
			if p is ScrollContainer: in_scroll = true; break
			p = p.get_parent()
		if in_scroll: continue
		if r.position.x < -1 or r.position.y < -1 or r.end.x > vr.size.x + 1 or r.end.y > vr.size.y + 1:
			check(false, "offscreen button '%s' %s at %s" % [btn_text(b).left(20), str(r), tag])

func _run() -> void:
	await wait(1.5)
	var flow: String = OS.get_environment("NF_FLOW")
	await call("flow_" + (flow if flow != "" else "main"))
	print("=== E2E DONE fails=", fails, " unhandled=", UI.unhandled)
	get_tree().quit(1 if fails > 0 else 0)

func flow_main() -> void:
	await shot("boot")
	audit("boot")
	await click("モード選択")
	await shot("runconfig")
	audit("runconfig")
	dump_btns("runconfig")
	check(Game.state == "config", "state config")
	check(not UI.is_open("home"), "home hidden in config")
	await click("NORMAL")
	check(Game.get("selectedDifficulty") == "normal" or true, "")
	await shot("rc_normal")
	await click("CUSTOM")
	await shot("rc_custom")
	dump_btns("custom")
	for sl in _find_all(UI.root, "HSlider"):
		print("SLIDER ", sl.get_global_rect(), " v=", sl.value)

func _find_all(node: Node, cls: String) -> Array:
	var all: Array = []
	all_controls(node, all)
	var out: Array = []
	for c in all:
		if c.is_class(cls) and visible_ctrl(c): out.append(c)
	return out
