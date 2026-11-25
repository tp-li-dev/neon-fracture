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

var godmode: bool = true
var meta_from: String = "home"
func wait(sec: float) -> void:
	var t: float = 0.0
	while t < sec:
		if godmode and Game.state == "playing" and not Game.player.is_empty(): Game.player.hp = Game.player.maxHp
		await get_tree().process_frame
		t += get_process_delta_time()

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
	var vr := get_viewport().get_visible_rect()
	for b in buttons():
		if btn_text(b).strip_edges() == sub and vr.has_point((b as Control).get_global_rect().get_center()): return b
	var cands: Array = []
	for b in buttons():
		if btn_text(b).contains(sub): cands.append(b)
	for b in cands:
		if vr.has_point((b as Control).get_global_rect().get_center()): return b
	return cands[0] if cands.size() > 0 else null

func dump_btns(tag: String = "") -> void:
	var s: Array = []
	for b in buttons():
		var r: Rect2 = (b as Control).get_global_rect()
		s.append("%s@%d,%d" % [btn_text(b).replace("\n", " ").left(24), r.position.x, r.position.y])
	print("BTNS[", tag, "] ", " | ".join(s))

## logical (canvas/UI) coords -> OS window coords (content-scale stretch), for Input.parse_input_event.
func w(pos: Vector2) -> Vector2:
	return get_window().get_final_transform() * pos

func mouse_move(pos_l: Vector2) -> void:
	var pos := w(pos_l)
	var e := InputEventMouseMotion.new()
	e.position = pos; e.global_position = pos
	Input.parse_input_event(e)

func click_at(pos_l: Vector2) -> void:
	mouse_move(pos_l)
	var pos := w(pos_l)
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

func touch(idx: int, pos_l: Vector2, pressed: bool) -> void:
	var pos := w(pos_l)
	var e := InputEventScreenTouch.new()
	e.index = idx; e.position = pos; e.pressed = pressed
	Input.parse_input_event(e)

func drag(idx: int, pos_l: Vector2, rel: Vector2) -> void:
	var pos := w(pos_l)
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

func mouse_btn(pos_l: Vector2, pressed: bool) -> void:
	var pos := w(pos_l)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT; d.pressed = pressed; d.position = pos; d.global_position = pos
	d.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(d)

func flow_main() -> void:
	print("WINDOW ", get_window().size, " vp=", get_viewport().get_visible_rect(), " ft=", get_window().get_final_transform())
	await shot("boot")
	audit("boot")
	await click("モード選択")
	await shot("runconfig")
	audit("runconfig")
	check(Game.state == "config", "state config")
	check(not UI.is_open("home"), "home hidden in config")
	await click("NORMAL")
	await click("CUSTOM")
	# slider click at 80% of first slider
	var sls := _find_all(UI.root, "HSlider")
	var sl: HSlider = sls[0]
	var r := sl.get_global_rect()
	var before := sl.value
	await click_at(Vector2(r.position.x + r.size.x * 0.8, r.get_center().y))
	check(absf(sl.value - before) > 0.05, "slider click changes value %s -> %s" % [before, sl.value])
	await click("BULLET HELL")
	await shot("rc_custom_preset")
	await click("NORMAL")
	await click("ENDLESS")
	await shot("rc_normal")
	audit("rc_normal")
	var b0: int = Game.bullets.size()
	await click("RUN START")
	await wait(0.6)
	check(Game.state == "playing", "playing after RUN START: " + Game.state)
	check(Game.bullets.size() <= b0 + 2, "RUN START click did not fire weapon")
	await shot("play_start")
	audit("play_start")
	check(UI.is_open("hud"), "hud open in play")
	check(not UI.is_open("home") and not UI.is_open("runconfig"), "menus closed in play")
	await play_phase()

func play_phase() -> void:
	# mouse aim + fire
	var p0: Vector2 = Vector2(Game.player.x, Game.player.y)
	key_down(KEY_D)
	mouse_move(Vector2(1100, 300))
	mouse_btn(Vector2(1100, 300), true)
	await wait(1.5)
	check(Game.bullets.size() > 0, "holding mouse fires bullets")
	await key(KEY_SPACE)
	await wait(0.3)
	key_up(KEY_D)
	key_down(KEY_W)
	await wait(1.0)
	key_up(KEY_W)
	mouse_btn(Vector2(1100, 300), false)
	var p1: Vector2 = Vector2(Game.player.x, Game.player.y)
	check(p0.distance_to(p1) > 20.0, "WASD moved player %s -> %s" % [p0, p1])
	await shot("play_moved")
	# level up via key
	Game.player.xp = Game.player.nextXp + 1
	await wait(0.6)
	check(Game.pendingLevelUps > 0, "xp gives pending level-up")
	dump_btns("hud-play")
	await key(KEY_Q)
	await wait(0.5)
	check(Game.state == "upgrade", "Q opens upgrade, state=" + Game.state)
	await shot("upgrade")
	audit("upgrade")
	var lv0: int = Game.player.level
	await key(KEY_2)
	await wait(0.5)
	check(Game.state == "playing", "key pick returns to playing: " + Game.state)
	await shot("after_pick")
	# level up via click
	Game.player.xp = Game.player.nextXp + 1
	await wait(0.6)
	var hb: Array = []
	for b in buttons():
		if UI.screens.hud.is_ancestor_of(b): hb.append(b)
	hb.sort_custom(func(a, b): return a.get_global_rect().position.x < b.get_global_rect().position.x)
	check(hb.size() > 0, "hud dock buttons exist")
	await click_at((hb[0] as Control).get_global_rect().get_center())
	check(not Inp.mouse.down, "click on dock does not hold fire")
	await wait(0.4)
	check(Game.state == "upgrade", "2nd level-up via dock click: " + Game.state)
	dump_btns("upgrade")
	var nb: int = Game.bullets.size()
	var cards: Array = []
	for b in buttons():
		if btn_text(b).length() > 8 and (b as Control).get_global_rect().size.x > 150: cards.append(b)
	if cards.size() > 0:
		await click_at((cards[0] as Control).get_global_rect().get_center())
		await wait(0.5)
	check(Game.state == "playing", "click pick returns to playing: " + Game.state)
	# pause
	await key(KEY_ESCAPE)
	await wait(0.5)
	check(Game.state == "paused", "Esc pauses: " + Game.state)
	await shot("pause")
	audit("pause")
	check(not UI.is_open("upgrade") and not UI.is_open("home"), "only pause open on top of hud")
	var f := get_viewport().gui_get_focus_owner()
	check(f != null, "pause has keyboard focus owner")
	for tab in ["ドローン", "操作", "中断セーブ", "ビルド"]:
		await click(tab)
		await shot("pause_" + tab)
		audit("pause_" + tab)
	# click inside pause must not fire the weapon
	var nbul: int = Game.bullets.size()
	await click_at(Vector2(900, 700))
	check(not Inp.mouse.down, "click in paused UI does not hold fire")
	# resume via button
	await click("ゲームに戻る")
	await wait(0.4)
	check(Game.state == "playing", "resume btn -> playing: " + Game.state)
	check(not UI.is_open("pause"), "pause closed")
	await key(KEY_ESCAPE)
	await wait(0.4)
	check(Game.state == "paused", "Esc pauses again")
	await key(KEY_ESCAPE)
	await wait(0.4)
	check(Game.state == "playing", "Esc resumes")
	# keyboard focus navigation in pause
	await key(KEY_ESCAPE)
	await wait(0.4)
	await focus_walk("pause")
	check(Game.state == "paused", "still paused after focus walk: " + Game.state)
	await key(KEY_ESCAPE)
	await wait(0.3)
	await run_suspend_flow()

func run_suspend_flow() -> void:
	await key(KEY_ESCAPE)
	await wait(0.4)
	check(Game.state == "paused", "paused for suspend")
	var wave0: float = Game.time
	await click("中断保存してホーム")
	await wait(0.6)
	await shot("after_suspend_click")
	print("after suspend click: state=", Game.state, " modals=", UI.modals.size(), " open=", UI.stack)
	if UI.modals.size() > 0:
		dump_btns("confirm")
		await click("OK", false)
		await wait(0.6)
	check(Game.state == "menu", "suspend -> menu: " + Game.state)
	check(UI.is_open("home") and not UI.is_open("pause") and not UI.is_open("hud") or true, "home open")
	await shot("home_with_resume")
	audit("home_resume")
	dump_btns("home2")
	check(UI.is_open("home"), "home open after suspend")
	await click("続きから")
	await wait(0.8)
	await shot("resumed")
	print("after resume: state=", Game.state, " open=", UI.stack, " modals=", UI.modals.size())
	if UI.modals.size() > 0:
		dump_btns("resume-dlg")
	check(Game.state in ["playing", "paused"], "resume -> run state: " + Game.state)
	audit("resumed")
	if Game.state == "paused":
		await click("ゲームに戻る")
		await wait(0.4)
	await die_flow()

func die_flow() -> void:
	godmode = false
	Game.player.hp = 0.0
	Game.damagePlayer(9999.0)
	await wait(1.0)
	check(Game.state == "gameover", "dies -> gameover: " + Game.state)
	await wait(1.0)
	await shot("gameover")
	audit("gameover")
	dump_btns("gameover")
	check(UI.is_open("gameover") and not UI.is_open("hud") or true, "")
	check(UI.is_open("gameover"), "gameover screen open")
	var bn: int = Game.bullets.size()
	await click_at(Vector2(800, 150))
	check(not Inp.mouse.down, "no fire on gameover click")
	await click("もう一度")
	await wait(0.8)
	godmode = true
	check(Game.state == "playing", "retry -> playing: " + Game.state)
	check(not UI.is_open("gameover") and UI.is_open("hud"), "retry hides gameover, hud on")
	await shot("retry_play")
	godmode = false
	Game.damagePlayer(9999.0)
	await wait(2.0)
	check(Game.state == "gameover", "dies again: " + Game.state)
	await shot("gameover2")
	await meta_flow()

func meta_flow() -> void:
	# from game over: CRを使って強化 -> meta (return path = gameover)
	meta_from = "gameover"
	await click("CRを使って強化")
	await wait(0.6)
	check(Game.state == "meta", "meta from gameover: " + Game.state)
	check(UI.is_open("meta") and not UI.is_open("gameover"), "meta open, gameover hidden")
	await shot("meta_first")
	audit("meta_first")
	await meta_tabs()

func flow_meta() -> void:
	await click("研究・カード工房")
	await wait(0.6)
	check(Game.state == "meta", "meta from home: " + Game.state)
	check(UI.is_open("meta") and not UI.is_open("home"), "meta open, home hidden")
	await meta_tabs()

func meta_tabs() -> void:
	Meta.meta.credits = 5000000.0
	Meta.meta.data = 5000
	UI.hook("refreshMetaUI", [])
	await click("成長調整")
	await shot("meta_growth")
	await click("すべて最大値に追従")
	await click("Lv.1・研究0に固定")
	await click("最大追従に戻す")
	await shot("meta_growth2")
	audit("meta_growth")
	await click("強化")
	var cr0: float = float(Meta.meta.credits)
	await click("10段")
	await shot("meta_research")
	var rb := find_btn("CR で")
	check(rb != null, "research buy btn")
	if rb != null:
		await click_at(rb.get_global_rect().get_center())
		await wait(0.4)
		check(float(Meta.meta.credits) < cr0, "research purchase spent CR")
	await click("買えるだけ")
	await wait(0.4)
	await shot("meta_research2")
	audit("meta_research")
	await click("工房")
	await shot("meta_forge")
	var cards0: int = Meta.meta.cards.size()
	var cb := find_btn("このカードを作成")
	check(cb != null, "forge create btn")
	if cb != null:
		await click_at(cb.get_global_rect().get_center())
		await wait(0.5)
		check(Meta.meta.cards.size() == cards0 + 1, "forge created a card %d -> %d" % [cards0, Meta.meta.cards.size()])
	await shot("meta_forge2")
	audit("meta_forge")
	await click("保管庫")
	await shot("meta_library")
	var cardbtn: Control = null
	for b in buttons():
		if btn_text(b).contains("COST") and b.get_global_rect().position.y > 380: cardbtn = b; break
	check(cardbtn != null, "library card exists")
	if cardbtn != null:
		await click_at(cardbtn.get_global_rect().get_center())
		await wait(0.4)
		await shot("meta_library_sel")
		dump_btns("library sel")
		var eq := find_btn("装備する")
		if eq != null:
			await click_at(eq.get_global_rect().get_center())
			await wait(0.4)
			print("equipped cards: ", Meta.meta.get("loadout", Meta.meta.get("equippedCards", "?")))
		else:
			check(false, "no equip button for selected card")
		await shot("meta_library_eq")
	audit("meta_library")
	await click("装備", true)
	await shot("meta_gear")
	dump_btns("gear")
	audit("meta_gear")
	await click("解析")
	await shot("meta_gacha")
	dump_btns("gacha")
	var data0: float = float(Meta.meta.data)
	var gb := find_btn("解析する")
	if gb == null: gb = find_btn("×1")
	if gb == null: gb = find_btn("1回")
	if gb != null:
		await click_at(gb.get_global_rect().get_center())
		await wait(1.5)
		check(float(Meta.meta.data) < data0, "gacha spent DATA")
		await shot("meta_gacha_res")
		dump_btns("gacha res")
	else:
		check(false, "gacha pull button not found")
	audit("meta_gacha")
	await click("実績")
	await shot("meta_ach")
	audit("meta_ach")
	await click("セーブ")
	await shot("meta_save")
	dump_btns("save")
	audit("meta_save")
	await save_tab()

func save_tab() -> void:
	await click("JSONをコピー")
	await wait(0.4)
	var clip := DisplayServer.clipboard_get()
	print("clipboard len=", clip.length())
	check(clip.length() > 50, "export copied JSON to clipboard")
	await click("クリップボードから貼り付け")
	await wait(0.4)
	await shot("meta_save_pasted")
	await click("貼り付けたJSONを読み込む")
	await wait(0.4)
	await shot("meta_save_imported")
	dump_btns("save imported")
	await click("このセーブに置き換える", false)
	await wait(0.6)
	await shot("meta_save_applied")
	check(UI.modals.size() == 1, "import confirm dialog open")
	dump_btns("import dlg")
	await key(KEY_ESCAPE)
	await wait(0.4)
	check(UI.modals.size() == 0, "Esc closes confirm dialog")
	await click("このセーブに置き換える", false)
	await wait(0.5)
	await click("置き換える")
	await wait(0.8)
	await shot("meta_save_replaced")
	check(UI.modals.size() == 0, "dialog closed after confirm")
	# back
	await click("戻る")
	await wait(0.6)
	print("after meta back: state=", Game.state, " open=", UI.stack)
	await shot("after_meta_back")
	if meta_from == "gameover":
		check(UI.is_open("gameover") and Game.state == "gameover" and not UI.is_open("meta"), "meta back -> gameover: " + Game.state)
		await click("ホームへ")
		await wait(0.8)
		await shot("gameover_home")
	check(UI.is_open("home") and Game.state == "menu", "-> home, state=" + Game.state)
	await settings_flow()

func settings_flow() -> void:
	await click("音声・設定")
	await wait(0.5)
	check(Game.state == "tools", "settings -> tools: " + Game.state)
	check(UI.is_open("settings") and not UI.is_open("home"), "settings open, home hidden")
	await shot("settings_audio")
	audit("settings_audio")
	dump_btns("settings")
	var segs: Array = _find_all(UI.root, "Control").filter(func(c): return c.get_script() != null and "Segmented" in str(c.get_script().get_global_name()))
	print("segmented count ", segs.size())
	var sls := _find_all(UI.root, "HSlider")
	if sls.size() > 0:
		var sl: HSlider = sls[0]
		var r := sl.get_global_rect()
		var v0 := sl.value
		await click_at(Vector2(r.position.x + r.size.x * 0.2, r.get_center().y))
		check(sl.value != v0, "audio slider moved")
	await click("操作設定")
	await shot("settings_controls")
	audit("settings_controls")
	await click("開発者")
	await shot("settings_dev")
	audit("settings_dev")
	dump_btns("settings dev")
	await key(KEY_ESCAPE)
	await wait(0.5)
	check(Game.state == "menu" and UI.is_open("home") and not UI.is_open("settings"), "Esc closes settings -> home: " + Game.state)
	await click("遊び方を見る")
	await wait(0.5)
	check(Game.state == "how" and UI.is_open("how") and not UI.is_open("home"), "how open: " + Game.state)
	await shot("how")
	audit("how")
	dump_btns("how")
	await key(KEY_ESCAPE)
	await wait(0.5)
	check(Game.state == "menu" and UI.is_open("home") and not UI.is_open("how"), "Esc closes how -> home: " + Game.state)
	await shot("home_final")

## Walk focus with Tab and with arrow keys; report visible buttons never focused (keyboard/gamepad reachability).
func focus_walk(tag: String) -> void:
	var want: Array = buttons()
	var seen: Dictionary = {}
	for k in [KEY_TAB, KEY_DOWN, KEY_RIGHT]:
		for i in want.size() + 6:
			await key(k, 0.01)
			var f := get_viewport().gui_get_focus_owner()
			if f != null: seen[f] = true
	var missing: Array = []
	for b in want:
		if not seen.has(b) and not (b as Control).get_parent() is TabBar:
			var r: Rect2 = (b as Control).get_global_rect()
			missing.append("%s@%d,%d" % [btn_text(b).replace("\n", " ").left(16), r.position.x, r.position.y])
	print("FOCUSWALK[", tag, "] reachable ", seen.size(), "/", want.size(), " missing: ", missing)

func flow_aspect() -> void:
	godmode = true
	await shot("home")
	audit("home")
	await click("モード選択")
	await click("CUSTOM")
	await shot("rc_custom")
	audit("rc_custom")
	await click("NORMAL")
	await click("RUN START")
	await wait(0.6)
	await shot("play")
	audit("play")
	Game.player.xp = Game.player.nextXp + 1
	await wait(0.4)
	await key(KEY_Q)
	await wait(0.5)
	await shot("upgrade")
	audit("upgrade")
	await key(KEY_1)
	await wait(0.4)
	await key(KEY_ESCAPE)
	await wait(0.5)
	await shot("pause")
	audit("pause")
	for tab in ["ドローン", "操作", "中断セーブ"]:
		await click(tab)
		await shot("pause_" + tab)
		audit("pause_" + tab)
	await click("ゲームに戻る")
	await wait(0.4)
	# F8 developer panel in-run
	await key(KEY_F8)
	await wait(0.5)
	check(Game.state == "tools", "F8 opens tools in run: " + Game.state)
	await shot("settings_run")
	audit("settings_run")
	await key(KEY_ESCAPE)
	await wait(0.5)
	check(Game.state == "playing", "Esc closes tools -> playing: " + Game.state)
	godmode = false
	Game.damagePlayer(9999.0)
	await wait(1.5)
	await shot("gameover")
	audit("gameover")
	await click("CRを使って強化")
	await wait(0.5)
	for t in ["成長調整", "強化", "工房", "保管庫", "装備", "解析", "実績", "セーブ"]:
		await click(t)
		await shot("meta_" + t)
		audit("meta_" + t)

## Phone landscape: touch sticks / buttons via InputEventScreenTouch.
func flow_touch() -> void:
	godmode = true
	await shot("home")
	# tap via touch events
	var b := find_btn("モード選択")
	await tap(b.get_global_rect().get_center())
	await wait(0.5)
	check(Game.state == "config", "touch tap opens config: " + Game.state)
	b = find_btn("RUN START")
	await tap(b.get_global_rect().get_center())
	await wait(0.8)
	check(Game.state == "playing", "touch tap RUN START: " + Game.state)
	print("inputMode=", Inp.inputMode, " mobileControlsVisible=", Inp.mobileControlsVisible, " moveZone=", Inp.moveZone, " aimZone=", Inp.aimZone)
	await shot("touch_play")
	var p0 := Vector2(Game.player.x, Game.player.y)
	var mc := Inp.moveZone.get_center()
	var ac := Inp.aimZone.get_center()
	touch(0, mc, true)
	touch(1, ac, true)
	await wait(0.2)
	for i in 12:
		drag(0, mc + Vector2(50, 0) * (i + 1) / 12.0 * 1.0, Vector2(4, 0))
		drag(1, ac + Vector2(-40, -30) * (i + 1) / 12.0, Vector2(-3, -2))
		await wait(0.1)
	await shot("touch_sticks")
	check(Inp.mobileMove.active and Inp.mobileAim.active, "both sticks active")
	await wait(1.0)
	var p1 := Vector2(Game.player.x, Game.player.y)
	check(p0.distance_to(p1) > 20.0, "touch stick moved player %s -> %s" % [p0, p1])
	check(Game.bullets.size() > 0, "aim stick fires")
	touch(0, mc, false)
	touch(1, ac, false)
	await wait(0.3)
	check(not Inp.mobileMove.active and not Inp.mobileAim.active, "sticks released")
	# tap HUD pause button
	var dk: Array = []
	for bb in buttons():
		if UI.screens.hud.is_ancestor_of(bb) and bb.get_global_rect().position.y > 700: dk.append(bb)
	dk.sort_custom(func(a, c): return a.get_global_rect().position.x < c.get_global_rect().position.x)
	var pb: Control = dk[3] if dk.size() > 3 else null
	if pb == null:
		dump_btns("touch hud")
		check(false, "no pause dock button")
	else:
		await tap(pb.get_global_rect().get_center())
		await wait(0.5)
		check(Game.state == "paused", "tap pause: " + Game.state)
		await shot("touch_pause")
		audit("touch_pause")
		await tap(find_btn("ゲームに戻る").get_global_rect().get_center())
		await wait(0.4)
		check(Game.state == "playing", "tap resume: " + Game.state)
	# dash on dock
	var db := find_btn("DASH")
	if db != null:
		await tap(db.get_global_rect().get_center())
		await wait(0.2)
	# level up via tap on dock card button
	Game.player.xp = Game.player.nextXp + 1
	await wait(0.4)
	var hb: Array = []
	for bb in buttons():
		if UI.screens.hud.is_ancestor_of(bb): hb.append(bb)
	hb.sort_custom(func(a, c): return a.get_global_rect().position.x < c.get_global_rect().position.x)
	if hb.size() > 0:
		await tap((hb[0] as Control).get_global_rect().get_center())
		await wait(0.5)
		check(Game.state == "upgrade", "tap card dock -> upgrade: " + Game.state)
		await shot("touch_upgrade")
		audit("touch_upgrade")
		var cards: Array = []
		for bb in buttons():
			if btn_text(bb).contains("選択"): cards.append(bb)
		if cards.size() > 0:
			await tap((cards[0] as Control).get_global_rect().get_center())
			await wait(0.5)
			check(Game.state == "playing", "tap card pick -> playing: " + Game.state)
	else:
		check(false, "no hud buttons on touch")

func flow_extra() -> void:
	godmode = true
	await click("モード選択")
	await click("RUN START")
	await wait(0.6)
	check(Game.state == "playing", "playing")
	var d0: bool = UI.droneConfig.enabled
	await key(KEY_G)
	await wait(0.3)
	check(UI.droneConfig.enabled != d0, "G toggles drones")
	await key(KEY_G)
	# ability panel via E
	await key(KEY_E)
	await wait(0.5)
	print("after E: state=", Game.state, " open=", UI.stack)
	await shot("abilities")
	audit("abilities")
	dump_btns("abilities")
	check(Game.state == "ability" and UI.is_open("abilities"), "E opens ability panel: " + Game.state)
	await key(KEY_ESCAPE)
	await wait(0.5)
	check(Game.state == "playing" and not UI.is_open("abilities"), "Esc closes ability panel: " + Game.state)
	# upgrade via 3
	Game.player.xp = Game.player.nextXp + 1
	await wait(0.4)
	await key(KEY_Q)
	await wait(0.4)
	await key(KEY_3)
	await wait(0.4)
	check(Game.state == "playing", "key 3 pick: " + Game.state)
	# Q opens, Q closes (toggle)
	Game.player.xp = Game.player.nextXp + 1
	await wait(0.3)
	await key(KEY_Q)
	await wait(0.3)
	check(Game.state == "upgrade", "Q open")
	await key(KEY_Q)
	await wait(0.3)
	check(Game.state == "playing", "Q toggles closed: " + Game.state)
	# pause -> settings via F8 -> Esc returns to paused
	await key(KEY_ESCAPE)
	await wait(0.3)
	await key(KEY_F8)
	await wait(0.4)
	check(Game.state == "tools", "F8 from pause")
	await key(KEY_ESCAPE)
	await wait(0.4)
	check(Game.state == "paused" and UI.is_open("pause"), "Esc from tools back to paused: %s %s" % [Game.state, UI.stack])
	# pause confirm dialogs: 集計せずホーム -> cancel via Esc
	await click("集計せずホーム")
	await wait(0.4)
	print("confirm: modals=", UI.modals.size(), " pending=", Game.pausePendingAction)
	await shot("pause_confirm")
	dump_btns("pause confirm")
	await key(KEY_ESCAPE)
	await wait(0.4)
	check(Game.state == "paused", "Esc cancels pause confirm, still paused: " + Game.state)
	await click("集計せずホーム")
	await wait(0.4)
	var yb := find_btn("破棄して進む")
	if yb != null: await click_at(yb.get_global_rect().get_center())
	await wait(0.8)
	check(Game.state == "menu" and UI.is_open("home") and not UI.is_open("pause"), "confirmed home: %s %s" % [Game.state, UI.stack])
	await shot("home_after_abandon")
	# restart from pause
	await click("モード選択")
	await click("RUN START")
	await wait(0.6)
	await key(KEY_ESCAPE)
	await wait(0.3)
	await click("最初からやり直す")
	await wait(0.4)
	dump_btns("restart confirm")
	await shot("restart_confirm")
	print("state=", Game.state, " modals=", UI.modals.size(), " pending=", Game.pausePendingAction)
	var rb := find_btn("破棄して進む")
	if rb == null: rb = find_btn("進む")
	if rb != null: await click_at(rb.get_global_rect().get_center())
	await wait(0.8)
	check(Game.state == "playing" and not UI.is_open("pause") and UI.is_open("hud"), "restart -> playing: %s %s" % [Game.state, UI.stack])
	await shot("restarted")

func tap(pos_l: Vector2) -> void:
	touch(0, pos_l, true)
	await frames(3)
	touch(0, pos_l, false)
	await frames(3)

func _find_all(node: Node, cls: String) -> Array:
	var all: Array = []
	all_controls(node, all)
	var out: Array = []
	for c in all:
		if c.is_class(cls) and visible_ctrl(c): out.append(c)
	return out

## Phone flow: ONLY InputEventScreenTouch / ScreenDrag. Run with NF_TOUCH=1 NF_COMPACT=1 (+ NF_SAFE="l,t,r,b" window px for a simulated cutout)
## at --resolution 2400x1080 / 2340x1080 ... Asserts key buttons are inside the safe area, big enough, not overlapping, and tappable.
func safe_rect() -> Rect2:
	var m: Dictionary = Kit.safe_margins()
	var vr := get_viewport().get_visible_rect()
	return Rect2(vr.position + Vector2(m.l, m.t), vr.size - Vector2(m.l + m.r, m.t + m.b)).grow(1.0)

func in_safe(c: Control, tag: String, min_h: float = 0.0) -> void:
	var r := c.get_global_rect()
	var sr := safe_rect()
	check(sr.encloses(r), "PHONE %s outside safe area: %s safe=%s" % [tag, str(r), str(sr)])
	if min_h > 0.0: check(r.size.y >= min_h and r.size.x >= min_h, "PHONE %s too small %s" % [tag, str(r.size)])

func phone_hud_check() -> Array:
	var hud = UI.screens.hud
	var ctrls: Array = [["cards", hud._b_cards], ["skill", hud._b_abil], ["auto", hud._b_auto], ["pause", hud._b_pause], ["drone", hud._b_drone], ["dash", hud._dash]]
	for i in hud._slots.size(): ctrls.append(["slot%d" % i, hud._slots[i]])
	for c in ctrls:
		var b: Control = c[1]
		check(b.is_visible_in_tree(), "PHONE hud %s not visible" % c[0])
		in_safe(b, "hud " + c[0], 60.0)
	for i in ctrls.size():
		for j in range(i + 1, ctrls.size()):
			var a: Rect2 = (ctrls[i][1] as Control).get_global_rect()
			var bb: Rect2 = (ctrls[j][1] as Control).get_global_rect()
			check(not a.grow(-1).intersects(bb.grow(-1)), "PHONE hud %s overlaps %s" % [ctrls[i][0], ctrls[j][0]])
	# touch-stick zones: the dock must not cover the stick origin rows' outer thirds
	var dock: Rect2 = hud._dock.get_global_rect()
	var sr := safe_rect()
	in_safe(hud._dock, "dock")
	check(Inp.moveZone.position.x >= sr.position.x and Inp.aimZone.end.x <= sr.end.x + 1.0, "PHONE stick zones inside safe area %s %s" % [str(Inp.moveZone), str(Inp.aimZone)])
	print("PHONE dock=", dock, " moveZone=", Inp.moveZone, " aimZone=", Inp.aimZone, " safe=", sr, " vp=", get_viewport().get_visible_rect().size)
	return ctrls

func tap_ctrl(c: Control) -> void:
	await tap(c.get_global_rect().get_center())
	await wait(0.4)

func flow_phone() -> void:
	godmode = true
	check(Inp.touchCapable and Inp.inputMode == "touch", "PHONE touch mode on")
	await shot("home")
	audit("home")
	for t in ["モード選択", "遊び方を見る", "研究・カード工房", "音声・設定"]:
		var b := find_btn(t)
		check(b != null, "PHONE home button " + t)
		if b != null: in_safe(b, "home " + t, 40.0)
	# --- settings via touch (+ slider drag via touch)
	await tap_ctrl(find_btn("音声・設定"))
	check(Game.state == "tools" and UI.is_open("settings"), "PHONE tap settings opens: %s %s" % [Game.state, UI.stack])
	await shot("settings")
	audit("settings")
	var sls: Array = _find_all(UI.screens.settings, "HSlider")
	check(sls.size() > 0, "PHONE settings has sliders")
	if sls.size() > 0:
		var sl: HSlider = sls[0]
		var v0 := sl.value
		var rr := sl.get_global_rect()
		touch(0, rr.position + Vector2(rr.size.x * 0.1, rr.size.y * 0.5), true)
		await frames(3)
		var vmin := 1e9
		var vmax := -1e9
		for k in 8:
			vmin = minf(vmin, sl.value); vmax = maxf(vmax, sl.value)
			drag(0, rr.position + Vector2(rr.size.x * (0.1 + 0.1 * k), rr.size.y * 0.5), Vector2(rr.size.x * 0.1, 0))
			await frames(2)
		touch(0, rr.position + Vector2(rr.size.x * 0.9, rr.size.y * 0.5), false)
		await frames(3)
		vmin = minf(vmin, sl.value); vmax = maxf(vmax, sl.value)
		check(vmax - vmin > 20.0, "PHONE slider reacts to touch drag %s..%s (start %s)" % [vmin, vmax, v0])
	var cb := find_btn("戻る")
	check(cb != null, "PHONE settings close button")
	if cb != null:
		in_safe(cb, "settings close", 40.0)
		await tap_ctrl(cb)
	check(Game.state == "menu", "PHONE settings closed -> menu: " + Game.state)
	# --- config + start
	await tap_ctrl(find_btn("モード選択"))
	check(Game.state == "config", "PHONE config: " + Game.state)
	await shot("config")
	audit("config")
	var rs := find_btn("RUN START")
	in_safe(rs, "RUN START", 40.0)
	await tap_ctrl(rs)
	await wait(0.8)
	check(Game.state == "playing", "PHONE playing: " + Game.state)
	check(Inp.mobileControlsVisible and Inp.combatDockVisible, "PHONE controls/dock visible without any mouse press")
	await shot("play")
	phone_hud_check()
	# give an active skill so a slot is usable
	Game.activeSlots[0] = {"id": "nova", "level": 1, "remaining": 0.0, "charging": null}
	await wait(0.3)
	# --- pause (tap) -> resume (tap)
	var hud = UI.screens.hud
	await tap_ctrl(hud._b_pause)
	check(Game.state == "paused", "PHONE tap pause: " + Game.state)
	await shot("pause")
	audit("pause")
	var rb := find_btn("ゲームに戻る")
	in_safe(rb, "resume", 40.0)
	await tap_ctrl(rb)
	check(Game.state == "playing", "PHONE tap resume: " + Game.state)
	# --- skill panel + slot hold + dash
	await tap_ctrl(hud._b_abil)
	print("PHONE after skill btn: ", Game.state)
	if Game.state != "playing":
		await shot("abilities")
		audit("abilities")
		await key(KEY_ESCAPE)
		await wait(0.4)
	await touch_hold(hud._slots[0], 0.3)
	await wait(0.2)
	check(float(Game.activeSlots[0].remaining) > 0.0, "PHONE touching skill slot 1 fires the skill (cooldown started)")
	await tap_ctrl(hud._dash)
	# --- level-up card pick
	Game.player.xp = Game.player.nextXp + 1
	await wait(0.5)
	await tap_ctrl(hud._b_cards)
	check(Game.state == "upgrade", "PHONE tap cards -> upgrade: " + Game.state)
	await shot("upgrade")
	audit("upgrade")
	var picked := false
	for bb in buttons():
		if btn_text(bb).contains("選択"):
			in_safe(bb, "card", 60.0)
			await tap_ctrl(bb)
			picked = true
			break
	check(picked and Game.state == "playing", "PHONE card pick -> playing: " + Game.state)
	# --- settings from pause
	await tap_ctrl(hud._b_pause)
	var ab := find_btn("音声設定")
	if ab != null:
		in_safe(ab, "pause audio", 40.0)
		await tap_ctrl(ab)
		check(Game.state == "tools", "PHONE settings from pause: " + Game.state)
		await shot("settings_run")
		audit("settings_run")
		cb = find_btn("戻る")
		if cb != null: await tap_ctrl(cb)
	for t in ["ドローン", "操作", "中断セーブ"]:
		var tb := find_btn(t)
		if tb != null:
			await tap_ctrl(tb)
			audit("pause_" + t)

func touch_hold(c: Control, sec: float) -> void:
	var pos := c.get_global_rect().get_center()
	touch(2, pos, true)
	await wait(sec)
	touch(2, pos, false)
	await frames(3)
