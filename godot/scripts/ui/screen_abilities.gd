extends NFScreen
## ボススキル報酬 (原作 #activeRewardScreen 5173 / openAbilityRewards 7740 / renderAbilityRewards 7748 / assignAbility 7765)
## Hooks: openAbilityRewards closeAbilityRewards renderAbilityRewards hideActiveRewardScreen
## Broadcasts: hidePanel("activeRewardScreen") showHome resetGameUI finishPresentation showGameOver openMeta
## Flow: pick an offer (click / key 1-3 via Inp) -> pick a slot (click / key 1-3) -> Combat.assignAbility(id, slot).
## Mock data: NF_SCREEN=abilities (only when no run is active).

var _root: Control
var _mock := false
var _mock_sel := "lance"

func _init() -> void:
	modal = true
	dim_alpha = 0.80
	layer_z = 42

func build() -> void:
	pass

func h_openAbilityRewards() -> void:
	UI.hide_screen("pause")
	UI.show_screen("abilities")

func h_closeAbilityRewards() -> void:
	UI.hide_screen("abilities")

func h_hideActiveRewardScreen() -> void:
	UI.hide_screen("abilities")

func h_renderAbilityRewards() -> void:
	if is_open: _render()

func b_hidePanel(id: Variant = "") -> void:
	if str(id) in ["activeRewardScreen", "abilities"]: UI.hide_screen("abilities")

func b_showHome() -> void: UI.hide_screen("abilities")
func b_resetGameUI(_t: Variant = null) -> void: UI.hide_screen("abilities")
func b_finishPresentation() -> void: UI.hide_screen("abilities")
func b_showGameOver(_i: Variant = null) -> void: UI.hide_screen("abilities")
func b_openMeta(_f: Variant = null) -> void: UI.hide_screen("abilities")
func b_syncInputSettings(_p: Variant = null, _k: Variant = null) -> void:
	if is_open: _render()

func on_open(_args: Dictionary = {}) -> void:
	_mock = OS.get_environment("NF_SCREEN") == "abilities" and (Game.player.is_empty() or Game.abilityRewards.is_empty())
	_render()

# ------------------------------------------------------------------ data access (mock aware)
func _defs() -> Dictionary:
	return Combat.ACTIVE_DEFS

func _offers() -> Array:
	if _mock: return ["lance", "orbital", "stasis"]
	if Game.abilityRewards.is_empty(): return []
	return Game.abilityRewards[0].offers

func _slots() -> Array:
	if _mock: return [{"id": "stasis", "level": 2, "remaining": 0.0}, null, null]
	return Game.activeSlots

func _selected() -> String:
	if _mock: return _mock_sel
	return str(Game.selectedAbilityId) if Game.selectedAbilityId != null else ""

func _pending() -> int:
	return 2 if _mock else Game.abilityRewards.size()

func _skill_keys() -> Array:
	return Inp.currentKeys().skills

# ------------------------------------------------------------------ render
func _render() -> void:
	if _root != null and is_instance_valid(_root):
		content.remove_child(_root)
		_root.queue_free()
	var compact := Kit.is_compact()
	_root = Kit.vbox(Kit.S3 if compact else Kit.S4)
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_root)

	var head := Kit.hbox(Kit.S4)
	var v := Kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(Kit.label("BOSS ABILITY", Kit.FS_XS, Kit.AMBER))
	v.add_child(Kit.label("スキルを取得・強化", Kit.FS_2XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	v.add_child(Kit.label("保留 %d回 / このランのみ" % _pending(), Kit.FS_SM, Kit.DIM))
	head.add_child(v)
	var close := Kit.button("あとで・戻る", "ghost", func(): Combat.closeAbilityRewards())
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size.x = 170
	head.add_child(close)
	_root.add_child(head)

	var sel := _selected()
	var offers := _offers()
	var body := Kit.vbox(Kit.S3)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(body)
	var first_card: Control = null
	if offers.is_empty():
		var p := Kit.panel(Kit.SLATE, Kit.S5)
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		p.body.add_child(Kit.fill_spacer())
		p.body.add_child(Kit.label("ボスを倒すごとに、スキルの取得・強化権が1回増えます。", Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, true))
		p.body.add_child(Kit.label("戦闘中に自動で開くことはありません。", Kit.FS_MD, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
		p.body.add_child(Kit.fill_spacer())
		body.add_child(p)
	else:
		var row := Kit.hbox(Kit.S3)
		body.add_child(row)
		for i in offers.size():
			var c := _offer_card(str(offers[i]), i, sel == str(offers[i]))
			if first_card == null or sel == str(offers[i]): first_card = c
			row.add_child(c)
		body.add_child(Kit.label(_slot_section_title(sel), Kit.FS_XS, Kit.CYAN))
		var srow := Kit.hbox(Kit.S3)
		body.add_child(srow)
		var slots := _slots()
		var already := -1
		for i in slots.size():
			if slots[i] != null and str(slots[i].id) == sel and sel != "": already = i
		for i in slots.size():
			srow.add_child(_slot_button(i, slots[i], sel, already))
		body.add_child(Kit.label(
			"上書きすると旧スキルはこのランから外れます。残りクールダウンを維持するため、付け替えで連発はできません。" if sel != ""
			else "同じスキルはレベルアップ。レベルに固定上限はありません。", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	default_focus = first_card if first_card != null else close

	var k: Array = []
	for c in _skill_keys(): k.append(Inp.keyLabel(str(c)))
	var hint := Kit.label("戦闘中：%s で発動（数字1〜3も使用可）。CDは戦闘中だけ進みます。 / この画面では 1〜3 で候補→枠を選択" % " / ".join(k), Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	_root.add_child(hint)

func _slot_section_title(sel: String) -> String:
	return "装備スロット  ―  取得先を選択" if sel != "" else "装備スロット  ―  上の候補を選択"

func _offer_card(id: String, i: int, selected: bool) -> Control:
	var d: Dictionary = _defs()[id]
	var owned = null
	for s in _slots():
		if s != null and str(s.id) == id: owned = s
	var rarity := "LEGENDARY" if owned != null else "EPIC"
	var lv_text := ("Lv.%d → %d" % [int(owned.level), int(owned.level) + 1]) if owned != null else "新規スキル"
	var desc := "%s\n\n基礎CD %s秒 / %s" % [str(d.desc), str(d.cd), lv_text]
	var card := Kit.rarity_card(rarity, str(d.name), desc, str(d.icon), "選択 %d" % (i + 1))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(240, 170 if Kit.is_compact() else 220)
	card.selected = selected
	card.pressed.connect(func(): _choose(id))
	return card

func _choose(id: String) -> void:
	if _mock:
		_mock_sel = id; _render(); return
	Game.selectedAbilityId = id
	Combat.renderAbilityRewards()

func _slot_button(i: int, slot: Variant, sel: String, already: int) -> Control:
	var label := "空きスロット"
	if slot != null: label = "%s Lv.%d" % [str(_defs()[slot.id].name), int(slot.level)]
	var nxt := "上の候補を選択"
	if sel != "":
		if already >= 0: nxt = "同じスキルを強化" if already == i else "別枠へ重複装備できません"
		else: nxt = "この枠を上書き" if slot != null else "この枠へ取得"
	var enabled := sel != "" and not (already >= 0 and already != i)
	var b := Kit.button("", "primary" if enabled else "ghost", func(): _assign(i))
	b.disabled = not enabled
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 84 if Kit.is_compact() else 76
	var inner := Kit.vbox(0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	var keys: Array = _skill_keys()
	inner.add_child(Kit.label("発動キー %s" % Inp.keyLabel(str(keys[i])), Kit.FS_XS, Kit.DIM if enabled else Kit.MUTE, HORIZONTAL_ALIGNMENT_CENTER))
	inner.add_child(Kit.label(label, Kit.FS_MD, Kit.TEXT if enabled else Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, false, true))
	inner.add_child(Kit.label(nxt, Kit.FS_SM, Kit.CYAN if enabled else Kit.MUTE, HORIZONTAL_ALIGNMENT_CENTER))
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["top", "bottom"]: m.add_theme_constant_override("margin_" + s, 8)
	m.add_child(inner)
	b.add_child(m)
	return b

func _assign(i: int) -> void:
	if _mock:
		_mock_sel = ""; _render(); return
	Combat.assignAbility(Game.selectedAbilityId, i)
