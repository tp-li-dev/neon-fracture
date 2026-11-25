extends Node
## Inp — port of index.html 5681-6077 (keyboard / mouse / floating touch sticks / skill holds / escape).
## Autoload name is `Inp` (Input is built in). PM's main.gd should:
##   - call  Inp.set_view(viewport_size, camera_pos[, scale, offset])  every frame (before Game.update)
##   - forward _input / _unhandled_input events to  Inp.handle_event(e)  (returns true if consumed)
## Names mirror the original JS (camelCase) so other modules can call Inp.<name>.

const CAM_W := 1600.0
const CAM_H := 900.0

# ---- original top-level state ----
var keys: Dictionary = {}                 # Set mirror (UI/debug only): code -> true
var physicalMoveKeys: Dictionary = {}     # Set (v28.4: single source of truth for keyboard movement): code -> true
var MOVE_CODES: Array = ["KeyW", "KeyA", "KeyS", "KeyD", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"]
var movementResetSerial: int = 0
var mouse: Dictionary = {"x": 2400.0, "y": 1350.0, "down": false}   # WORLD coordinates
var heldSkills: Dictionary = {}           # Map token -> {index, started}
var touchCapable: bool = false
var KEY_LAYOUTS: Dictionary = {
	"menus": {"cards": "KeyQ", "rewards": "KeyE", "skills": ["Digit1", "Digit2", "Digit3"], "name": "Q / Eで育成画面"},
	"abilities": {"cards": "KeyC", "rewards": "KeyV", "skills": ["KeyQ", "KeyE", "KeyR"], "name": "Q / E / Rでスキル発動"},
}
var inputPreferences: Dictionary = {"scheme": "menus", "device": "auto"}
var inputMode: String = "keyboard"
var mousePointerId = null                 # null or 0 (the mouse)
var pointerClient: Dictionary = {"x": 640.0, "y": 360.0, "valid": false}   # screen px
# Stick state. UI can draw from: active, x, y, mag (normalized), originX/originY (screen px, press origin),
# knobX/knobY (screen px of current touch), revealed (draw the stick), radius (px), pointerId.
var mobileMove: Dictionary = {"x": 0.0, "y": 0.0, "mag": 0.0, "active": false, "pointerId": null,
	"originX": 0.0, "originY": 0.0, "knobX": 0.0, "knobY": 0.0, "revealed": false, "radius": 36.0}
var mobileAim: Dictionary = {"x": 0.0, "y": 0.0, "mag": 0.0, "active": false, "pointerId": null,
	"originX": 0.0, "originY": 0.0, "knobX": 0.0, "knobY": 0.0, "revealed": false, "radius": 36.0}
var stickControllers: Array = []          # [{reset: Callable, active: Callable}]
var inputNoticeTimer: float = 0.0
var controlsLayoutFrame: int = 0
var inputPresentationState: String = ""
var MOVE_KEY_FALLBACK: Dictionary = {"w": "KeyW", "a": "KeyA", "s": "KeyS", "d": "KeyD",
	"arrowup": "ArrowUp", "arrowdown": "ArrowDown", "arrowleft": "ArrowLeft", "arrowright": "ArrowRight"}
var endMouse = null                       # (JS arrow fn) -> see _end_mouse()
var touchButtonPresses: Dictionary = {}   # DOM click-dedupe: not needed in Godot (kept for index parity)
var handledTouchUps: Array = []           # idem

# ---- Godot-side additions ----
var viewSize: Vector2 = Vector2(1280, 720)
var cameraPos: Vector2 = Vector2(1600, 900)
var viewScale: float = 1.0
var viewOffset: Vector2 = Vector2.ZERO
# Touch zone layout (screen px), computed by layoutTouchZones(). UI may draw these.
var moveZone: Rect2 = Rect2()
var aimZone: Rect2 = Rect2()
var stickSize: float = 112.0
# Presentation flags UI can read (replace body classes / hidden toggles of the original).
var mobileControlsVisible: bool = false
var combatDockVisible: bool = false
var dashHudVisible: bool = false

var _stick_press_ms := {"move": 0, "aim": 0}
var _touch_down_ids: Dictionary = {}      # pointer index -> true (touch down events seen)

const _SPECIAL_CODES := {
	KEY_SPACE: "Space", KEY_ESCAPE: "Escape", KEY_TAB: "Tab", KEY_F8: "F8",
	KEY_UP: "ArrowUp", KEY_DOWN: "ArrowDown", KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight",
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	touchCapable = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	stickControllers = [
		{"reset": Callable(self, "_reset_move"), "active": Callable(self, "_move_active")},
		{"reset": Callable(self, "_reset_aim"), "active": Callable(self, "_aim_active")},
	]
	_load_preferences.call_deferred()

func _load_preferences() -> void:
	var p: Dictionary = {}
	var raw = Meta.storage_get("nf_input_v1")
	if raw != null and str(raw) != "":
		var parsed = JSON.parse_string(str(raw))
		if parsed is Dictionary:
			p = parsed
	inputPreferences = {
		"scheme": p.get("scheme") if KEY_LAYOUTS.has(p.get("scheme", "")) else "menus",
		"device": p.get("device") if ["auto", "keyboard", "touch"].has(p.get("device", "")) else "auto",
	}
	var coarse: bool = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	inputMode = "touch" if inputPreferences.device == "touch" else ("keyboard" if inputPreferences.device == "keyboard" else ("touch" if coarse else "keyboard"))
	inputPresentationState = ""

func _process(_dt: float) -> void:
	# 70ms reveal timer of bindFloatingStick (setTimeout(reveal,70)).
	var now := Time.get_ticks_msec()
	for k in ["move", "aim"]:
		var obj: Dictionary = mobileMove if k == "move" else mobileAim
		var t: int = _stick_press_ms[k]
		if t > 0 and obj.active and not obj.revealed and now - t >= 70:
			_stick_press_ms[k] = 0
			_reveal(obj)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# OS focus loss: never restore keyboard movement afterwards.
		clearPhysicalMovement(); cancelPointerInput(); stopPlayerMotion()
		if Game.state == "playing":
			Game.setPause(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		clearKeyboardMovement(); syncKeyboardMirror()

# ------------------------------------------------------------------ view / coordinates
## Called by main.gd every frame. scale/offset optional: default = fit CAM_W x CAM_H centered in size.
func set_view(size: Vector2, cam_pos: Vector2, scale: float = -1.0, offset = null) -> void:
	var changed := size != viewSize
	viewSize = size
	cameraPos = cam_pos
	if scale > 0.0:
		viewScale = scale
	else:
		viewScale = minf(size.x / CAM_W, size.y / CAM_H)
	if offset is Vector2:
		viewOffset = offset
	else:
		viewOffset = (size - Vector2(CAM_W, CAM_H) * viewScale) * 0.5
	if changed:
		cancelPointerInput()
		layoutTouchZones()
	elif moveZone.size == Vector2.ZERO:
		layoutTouchZones()
	if not pointerClient.valid:
		pointerClient = {"x": size.x / 2.0, "y": size.y / 2.0, "valid": false}
	if Game.state == "playing" and inputMode == "keyboard" and pointerClient.valid:
		updateMousePosition(pointerClient.x, pointerClient.y)

func updateMousePosition(clientX: float, clientY: float) -> void:
	var x: float = (clientX - viewOffset.x) / viewScale
	var y: float = (clientY - viewOffset.y) / viewScale
	mouse.x = cameraPos.x + U.clamp(x, 0.0, CAM_W)
	mouse.y = cameraPos.y + U.clamp(y, 0.0, CAM_H)

# ------------------------------------------------------------------ movement / aim helpers
func keyLabel(code: String) -> String:
	if code.begins_with("Key"): return code.substr(3)
	if code.begins_with("Digit"): return code.substr(5)
	return code

func currentKeys() -> Dictionary:
	return KEY_LAYOUTS[inputPreferences.scheme]

func moveCodeFromEvent(e: InputEventKey) -> String:
	var code := _code_from_event(e)
	if MOVE_CODES.has(code): return code
	var k := OS.get_keycode_string(e.keycode).to_lower()
	return MOVE_KEY_FALLBACK.get(k, "")

func keyboardMoveHeld(code: String) -> bool:
	return inputMode == "keyboard" and physicalMoveKeys.has(code)

func syncKeyboardMirror() -> void:
	keys.clear()
	if Game.state != "playing" or inputMode != "keyboard": return
	for code in physicalMoveKeys:
		keys[code] = true

## Movement axes (original dxMove/dyMove). Touch stick gives analog values.
func dxMove() -> float:
	if inputMode == "touch" and mobileMove.active: return mobileMove.x
	return (1.0 if (keyboardMoveHeld("KeyD") or keyboardMoveHeld("ArrowRight")) else 0.0) - (1.0 if (keyboardMoveHeld("KeyA") or keyboardMoveHeld("ArrowLeft")) else 0.0)

func dyMove() -> float:
	if inputMode == "touch" and mobileMove.active: return mobileMove.y
	return (1.0 if (keyboardMoveHeld("KeyS") or keyboardMoveHeld("ArrowDown")) else 0.0) - (1.0 if (keyboardMoveHeld("KeyW") or keyboardMoveHeld("ArrowUp")) else 0.0)

func movement_vector() -> Vector2:
	return Vector2(dxMove(), dyMove())

## Aim helpers (Combat owns aimAngle/aimPoint; these are the raw-input equivalents).
func aim_point() -> Vector2:
	return Vector2(mouse.x, mouse.y)

func aim_angle() -> float:
	var p: Dictionary = Game.player
	return atan2(mouse.y - p.y, mouse.x - p.x)

func fire_held() -> bool:
	return mouse.down

# ------------------------------------------------------------------ misc original functions
func showInputNotice(message: String, ms: int = 2200) -> void:
	UI.hook("showInputNotice", [message, ms])

func clearKeyboardMovement() -> void:
	for code in MOVE_CODES:
		keys.erase(code)
	movementResetSerial += 1

func clearPhysicalMovement() -> void:
	physicalMoveKeys.clear()
	clearKeyboardMovement()

func restoreHeldKeyboardMovement() -> void:
	syncKeyboardMirror()

func stopPlayerMotion() -> void:
	var p = Game.player
	if p == null or not (p is Dictionary): return
	p.vx = 0.0; p.vy = 0.0; p.dashTime = 0.0

func releaseMovementInput(stopMotion: bool = false) -> void:
	clearKeyboardMovement()
	for c in stickControllers:
		if c.active.call(): c.reset.call()
	if stopMotion: stopPlayerMotion()

func setInputMode(mode: String) -> void:
	if inputMode == mode: return
	clearKeyboardMovement()
	if mode == "touch": physicalMoveKeys.clear()
	cancelPointerInput(); stopPlayerMotion()
	inputMode = mode; syncKeyboardMirror(); inputPresentationState = ""; syncInputPresentation()

func detectInput(mode: String) -> void:
	if inputPreferences.device != "auto": return
	if mode == "keyboard" and (mobileMove.active or mobileAim.active): return
	setInputMode(mode)

func saveInputPreferences() -> void:
	Meta.storage_set("nf_input_v1", JSON.stringify(inputPreferences))

func setKeyLayout(layout: String) -> void:
	if not KEY_LAYOUTS.has(layout): return
	inputPreferences.scheme = layout; saveInputPreferences(); syncInputSettings()
	UI.hook("syncCombatHud", [])

## Settings UI: Inp.setInputDevice("auto"|"keyboard"|"touch")
func setInputDevice(device: String) -> void:
	if not ["auto", "keyboard", "touch"].has(device): return
	inputPreferences.device = device; saveInputPreferences()
	if device == "touch": setInputMode("touch")
	elif device == "keyboard": setInputMode("keyboard")
	syncInputSettings()

func syncInputSettings() -> void:
	UI.hook("syncInputSettings", [inputPreferences, currentKeys()])

func focusCombat(reconcileMovement: bool = true) -> void:
	if reconcileMovement: restoreHeldKeyboardMovement()
	mouse.down = false; mousePointerId = null
	if pointerClient.valid: updateMousePosition(pointerClient.x, pointerClient.y)
	inputPresentationState = ""; syncInputPresentation()

func focusPanel(id: String, preferred: String = "") -> void:
	UI.hook("focusPanel", [id, preferred])
	inputPresentationState = ""; syncInputPresentation()

func cancelPointerInput() -> void:
	clearSkillHolds()
	mouse.down = false
	mousePointerId = null
	for c in stickControllers:
		c.reset.call()

func setMobileControls(visible: bool) -> void:
	var show: bool = visible and inputMode == "touch" and Game.state == "playing"
	if not show:
		for c in stickControllers:
			if c.active.call(): c.reset.call()
	mobileControlsVisible = show
	UI.hook("setMobileControls", [show, inputMode])
	if show: scheduleControlsLayout()

func syncInputPresentation() -> void:
	var stamp: String = "%s/%s" % [Game.state, inputMode]
	if inputPresentationState == stamp: return
	inputPresentationState = stamp
	setMobileControls(Game.state == "playing")
	combatDockVisible = Game.state == "playing"
	dashHudVisible = false if inputMode == "touch" else Game.state == "playing"
	UI.hook("syncInputPresentation", [Game.state, inputMode])
	if Game.state != "playing": cancelPointerInput()
	scheduleControlsLayout()

func scheduleControlsLayout() -> void:
	layoutTouchZones()

## Same geometry as the original (safe-area insets and the portrait combat-dock clamp are not available; = 0).
func layoutTouchZones() -> void:
	var w: float = viewSize.x
	var h: float = viewSize.y
	var size: float = minf(112.0, maxf(84.0, h * 0.28))
	stickSize = size
	var radius: float = size / 2.0
	var portrait: bool = w < h
	var top: float = maxf(radius + 100.0, h * (0.47 if portrait else 0.49))
	var bottom: float = h - radius - 10.0
	var left_end: float = w / 2.0 - 8.0
	var right_start: float = w / 2.0 + 8.0
	var mx: float = radius + 10.0
	var mr: float = left_end - 14.0
	var ax: float = right_start + 14.0
	var ar: float = w - radius - 10.0
	moveZone = Rect2(mx, top, maxf(12.0, mr - mx), maxf(12.0, bottom - top))
	aimZone = Rect2(ax, top, maxf(12.0, ar - ax), maxf(12.0, bottom - top))

# ------------------------------------------------------------------ floating sticks
func _reset_move() -> void: _stick_reset(mobileMove, "move")
func _reset_aim() -> void: _stick_reset(mobileAim, "aim")
func _move_active() -> bool: return mobileMove.active
func _aim_active() -> bool: return mobileAim.active

func _reveal(obj: Dictionary) -> void:
	if not obj.active or Game.state != "playing" or inputMode != "touch": return
	obj.revealed = true

func _stick_reset(obj: Dictionary, which: String) -> void:
	_stick_press_ms[which] = 0
	var had: bool = obj.active
	obj.active = false; obj.pointerId = null; obj.x = 0.0; obj.y = 0.0; obj.mag = 0.0; obj.revealed = false
	obj.knobX = obj.originX; obj.knobY = obj.originY
	if had or which == "aim":
		_on_vector(which, 0.0, 0.0, 0.0)

func _on_vector(which: String, x: float, y: float, mag: float) -> void:
	if which != "aim": return   # move stick: onVector is a no-op
	if Game.state != "playing":
		mouse.down = false
		return
	if mag > 0.10:
		var l: float = sqrt(x * x + y * y)
		if l == 0.0: l = 1.0
		var nx: float = x / l
		var ny: float = y / l
		mouse.x = Game.player.x + nx * 720.0
		mouse.y = Game.player.y + ny * 720.0
		mouse.down = mag > 0.18
	else:
		mouse.down = false

func _stick_begin(obj: Dictionary, which: String, index: int, pos: Vector2) -> void:
	obj.active = true; obj.pointerId = index; obj.x = 0.0; obj.y = 0.0; obj.mag = 0.0; obj.revealed = false
	obj.originX = pos.x; obj.originY = pos.y; obj.knobX = pos.x; obj.knobY = pos.y
	obj.radius = stickSize * 0.32
	_stick_press_ms[which] = Time.get_ticks_msec()

func _stick_update(obj: Dictionary, which: String, pos: Vector2) -> void:
	var dx: float = pos.x - obj.originX
	var dy: float = pos.y - obj.originY
	var length: float = sqrt(dx * dx + dy * dy)
	var radius: float = obj.radius
	var raw: float = minf(1.0, length / radius)
	var mag: float = 0.0 if raw <= 0.12 else (raw - 0.12) / 0.88
	if not obj.revealed and length > 5.0:
		_stick_press_ms[which] = 0
		_reveal(obj)
	obj.x = dx / length * mag if length > 0.0 else 0.0
	obj.y = dy / length * mag if length > 0.0 else 0.0
	obj.mag = mag
	var travel: float = minf(length, radius)
	obj.knobX = obj.originX + (dx / length * travel if length > 0.0 else 0.0)
	obj.knobY = obj.originY + (dy / length * travel if length > 0.0 else 0.0)
	_on_vector(which, obj.x, obj.y, mag)

func _stick_for_pointer(index: int) -> Variant:
	if mobileMove.active and mobileMove.pointerId == index: return ["move", mobileMove]
	if mobileAim.active and mobileAim.pointerId == index: return ["aim", mobileAim]
	return null

# ------------------------------------------------------------------ skills / panels
func skillFromInput(index: int) -> void:
	if Game.state != "playing": return
	var slots: Array = Game.activeSlots
	var s = slots[index] if index < slots.size() else null
	if s == null:
		if Game.abilityRewards.size() > 0: Combat.openAbilityRewards()
		else: showInputNotice("ボスを倒すとスキルを獲得できます")
		return
	if s.get("charging", false):
		showInputNotice("チャージ中：照準を合わせると自動で発射します", 1100); return
	if float(s.get("remaining", 0.0)) > 0.0:
		showInputNotice("再使用まで %.1f秒" % float(s.remaining), 1000); return
	Combat.useActive(index)

func toggleRunPanel(kind: String) -> void:
	var target: String = "upgrade" if kind == "cards" else "ability"
	if Game.state == target:
		if kind == "cards": Game.closeCardChoices()
		else: Combat.closeAbilityRewards()
		return
	if not ["playing", "paused", "upgrade", "ability"].has(Game.state): return
	if Game.state == "upgrade":
		UI.hook("hidePanel", ["upgrade"]); Game.state = Game.cardPanelOrigin
	elif Game.state == "ability":
		UI.hook("hidePanel", ["activeRewardScreen"]); Game.state = Game.panelReturnState
	if kind == "cards": Cards.showUpgrade()
	else: Combat.openAbilityRewards()

func handleEscape() -> void:
	var st: String = Game.state
	if st == "tools": UI.hook("closeUtility", []); return
	if st == "paused" and Game.pausePendingAction != null:
		Game.pausePendingAction = null; UI.hook("hidePauseConfirm", []); focusPanel("pauseScreen", "pauseResumeBtn"); return
	if st == "meta": Meta.closeMeta(); return
	if st == "how": UI.hook("closeHow", []); return
	if st == "config": UI.hook("closeRunConfig", []); return
	Game.togglePause()

# Long press = re-use when ready (original lives in the UI block 10313-10327; implemented here).
func clearSkillHolds() -> void:
	heldSkills.clear()
	UI.hook("skillHoldVisual", [[false, false, false]])

func beginSkillHold(index: int, token: String) -> void:
	if Game.state != "playing" or index < 0 or index > 2: return
	heldSkills[token] = {"index": index, "started": Game.time}
	skillFromInput(index)
	if Game.state == "playing": _skill_visual()

func endSkillHold(token: String) -> void:
	heldSkills.erase(token)
	_skill_visual()

func _skill_visual() -> void:
	var v := [false, false, false]
	for h in heldSkills.values():
		v[h.index] = true
	UI.hook("skillHoldVisual", [v])

func updateSkillHolds() -> void:
	if Game.state != "playing" or not Game.playPreferences.get("holdSkills", false): return
	var used := {}
	for h in heldSkills.values():
		if used.has(h.index) or float(Game.time) - float(h.started) < 0.30: continue
		used[h.index] = true
		var slots: Array = Game.activeSlots
		var slot = slots[h.index] if h.index < slots.size() else null
		if slot != null and float(slot.get("remaining", 0.0)) <= 0.0 and not slot.get("charging", false):
			Combat.useActive(h.index)
		if Game.state != "playing": break

# ------------------------------------------------------------------ event handling
func _code_from_event(e: InputEventKey) -> String:
	var kc: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
	if _SPECIAL_CODES.has(kc): return _SPECIAL_CODES[kc]
	if kc >= KEY_A and kc <= KEY_Z: return "Key" + char(kc)
	if kc >= KEY_0 and kc <= KEY_9: return "Digit" + char(kc)
	if kc >= KEY_KP_0 and kc <= KEY_KP_9: return "Numpad" + str(kc - KEY_KP_0)
	return ""

func handle_event(e: InputEvent) -> bool:
	if e is InputEventKey:
		return _handle_key(e)
	if e is InputEventMouseButton:
		return _handle_mouse_button(e)
	if e is InputEventMouseMotion:
		return _handle_mouse_motion(e)
	if e is InputEventScreenTouch:
		return _handle_touch(e)
	if e is InputEventScreenDrag:
		return _handle_drag(e)
	return false

func _handle_key(e: InputEventKey) -> bool:
	if not e.pressed:
		var up_code := moveCodeFromEvent(e)
		if up_code != "":
			physicalMoveKeys.erase(up_code); keys.erase(up_code)
		endSkillHold("key:" + _code_from_event(e))
		return false
	var st: String = Game.state
	var code := _code_from_event(e)
	var repeat: bool = e.echo
	if code == "F8" and not e.ctrl_pressed and not e.alt_pressed and not e.meta_pressed:
		if not repeat:
			if st == "tools": UI.hook("closeUtility", [])
			else: UI.hook("openUtility", ["developer"])
		return true
	var move_code := moveCodeFromEvent(e)
	if move_code != "":
		if e.ctrl_pressed or e.meta_pressed or e.alt_pressed: return false
		if ["playing", "paused", "upgrade", "ability", "tools"].has(st):
			physicalMoveKeys[move_code] = true
			if st == "playing":
				detectInput("keyboard")
				syncKeyboardMirror()
			return true
		return false
	if e.ctrl_pressed or e.meta_pressed or e.alt_pressed: return false
	if code == "Escape":
		if not repeat: handleEscape()
		return true
	var layout: Dictionary = currentKeys()
	if code == layout.cards or code == "KeyU":
		if ["playing", "paused", "upgrade", "ability"].has(st):
			if not repeat: toggleRunPanel("cards")
			return true
		return false
	if code == layout.rewards or code == "KeyK":
		if ["playing", "paused", "upgrade", "ability"].has(st):
			if not repeat: toggleRunPanel("abilities")
			return true
		return false
	var n: int = -1
	if code.begins_with("Digit") or code.begins_with("Numpad"):
		var d: int = int(code.substr(code.length() - 1))
		if d >= 1 and d <= 3: n = d - 1
	if st == "upgrade" and n >= 0:
		if not repeat and Game.currentCardChoices != null and n < Game.currentCardChoices.size():
			Cards.selectUpgrade(Game.currentCardChoices[n])
		return true
	if st == "ability" and n >= 0:
		if repeat: return true
		if Game.selectedAbilityId == null or str(Game.selectedAbilityId) == "":
			var offer = null
			if Game.abilityRewards.size() > 0:
				var offers: Array = Game.abilityRewards[0].offers
				if n < offers.size(): offer = offers[n]
			Game.selectedAbilityId = offer if offer else null
			Combat.renderAbilityRewards()
		else:
			Combat.assignAbility(Game.selectedAbilityId, n)
		return true
	if st != "playing": return false
	if code == "KeyG":
		if not repeat: UI.hook("toggleDrones", [])
		return true
	if code == "Space":
		if not repeat: Game.dash()
		return true
	var skill: int = (layout.skills as Array).find(code)
	if skill >= 0 or n >= 0:
		if not repeat: beginSkillHold(skill if skill >= 0 else n, "key:" + code)
		return true
	if code == "KeyF":
		if not repeat: Game.toggleAutoCards()
		return true
	return false

func _handle_mouse_button(e: InputEventMouseButton) -> bool:
	if e.device == InputEvent.DEVICE_ID_EMULATION: return false   # emulated from touch
	if e.button_index != MOUSE_BUTTON_LEFT: return false
	if e.pressed:
		if Game.state != "playing": return false
		detectInput("keyboard")
		pointerClient = {"x": e.position.x, "y": e.position.y, "valid": true}
		updateMousePosition(e.position.x, e.position.y)
		focusCombat(false)
		mouse.down = true; mousePointerId = 0
		return true
	# release (endMouse)
	if mousePointerId != null:
		mousePointerId = null; mouse.down = false
	return false

func _handle_mouse_motion(e: InputEventMouseMotion) -> bool:
	if e.device == InputEvent.DEVICE_ID_EMULATION: return false
	pointerClient = {"x": e.position.x, "y": e.position.y, "valid": true}
	if Game.state == "playing" and inputMode == "keyboard":
		updateMousePosition(e.position.x, e.position.y)
	if mousePointerId != null and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		mousePointerId = null; mouse.down = false
	return false

func _handle_touch(e: InputEventScreenTouch) -> bool:
	var idx: int = e.index
	if e.pressed:
		_touch_down_ids[idx] = true
		if Game.state != "playing": return false
		detectInput("touch")
		if inputPreferences.device == "keyboard" or inputMode != "touch": return false
		var obj: Dictionary
		var which := ""
		if moveZone.has_point(e.position) and not mobileMove.active:
			obj = mobileMove; which = "move"
		elif aimZone.has_point(e.position) and not mobileAim.active:
			obj = mobileAim; which = "aim"
		else:
			return false
		_stick_begin(obj, which, idx, e.position)
		return true
	_touch_down_ids.erase(idx)
	var s = _stick_for_pointer(idx)
	if s != null:
		_stick_reset(s[1], s[0])
		return true
	return false

func _handle_drag(e: InputEventScreenDrag) -> bool:
	var s = _stick_for_pointer(e.index)
	if s != null and Game.state == "playing":
		_stick_update(s[1], s[0], e.position)
		return true
	return false
