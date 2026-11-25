extends NFScreen
## 保留カード取得 (原作 #upgradeScreen 4837 / showUpgrade 8625 / renderCardChoices 7854 / selectUpgrade 8631)
## Hooks: showUpgrade hideUpgrade renderCardChoices(info{pending,auto,choices})
## Broadcasts: hidePanel("upgrade"|"upgradeScreen") showHome resetGameUI finishPresentation showGameOver openMeta
## Selection: click / Enter on a card, or keys 1-3 (handled by Inp -> Cards.selectUpgrade). Apply = Cards.selectUpgrade(u).
## Mock data: NF_SCREEN=upgrade (only when no run is active).

var _info: Dictionary = {}
var _root: Control
var _cards: Array = []
var _auto_btn: Button
var _mock := false

func _init() -> void:
	modal = true
	dim_alpha = 0.80
	layer_z = 42

func build() -> void:
	pass

# ------------------------------------------------------------------ hooks
func h_showUpgrade() -> void:
	UI.hide_screen("pause")
	UI.show_screen("upgrade")

func h_hideUpgrade() -> void:
	UI.hide_screen("upgrade")

func h_renderCardChoices(info: Variant = null) -> void:
	_info = info if info is Dictionary else {}
	if is_open: _render()

func b_hidePanel(id: Variant = "") -> void:
	if str(id) in ["upgrade", "upgradeScreen"]: UI.hide_screen("upgrade")

func b_showHome() -> void: UI.hide_screen("upgrade")
func b_resetGameUI(_t: Variant = null) -> void: UI.hide_screen("upgrade")
func b_finishPresentation() -> void: UI.hide_screen("upgrade")
func b_showGameOver(_i: Variant = null) -> void: UI.hide_screen("upgrade")
func b_openMeta(_f: Variant = null) -> void: UI.hide_screen("upgrade")

func b_syncCombatHud() -> void:
	if is_open and _auto_btn != null and is_instance_valid(_auto_btn):
		_auto_btn.text = "自動取得：ON" if Game.playPreferences.get("autoCards", false) else "自動取得：OFF"

func on_open(_args: Dictionary = {}) -> void:
	_mock = OS.get_environment("NF_SCREEN") == "upgrade" and (Game.player.is_empty() or Game.pendingLevelUps <= 0)
	if _mock:
		_info = _mock_info()
	elif _info.is_empty():
		_info = {"pending": Game.pendingLevelUps, "auto": Game.playPreferences.get("autoCards", false),
			"choices": Game.currentCardChoices if Game.pendingLevelUps > 0 and Game.currentCardChoices != null else []}
	_render()

# ------------------------------------------------------------------ render
func _mock_info() -> Dictionary:
	return {"pending": 3, "auto": false, "choices": [
		{"id": "damage", "icon": "✦", "name": "オーバーチャージ", "rarity": "RARE", "desc": "弾ダメージ +38%、弾速 +8%"},
		{"id": "pierce", "icon": "⇶", "name": "スペクトラル・ランス", "rarity": "EPIC", "desc": "弾ダメージ +80%、弾サイズ +1。火力特化の最終形。"},
		{"id": "regen", "icon": "✚", "name": "ナノリペア", "rarity": "COMMON", "desc": "毎秒HPを少量回復する。"}]}

func _render() -> void:
	if _root != null and is_instance_valid(_root):
		content.remove_child(_root)
		_root.queue_free()
	_cards.clear()
	var compact := Kit.is_compact()
	_root = Kit.vbox(Kit.S3 if compact else Kit.S4)
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_root)
	var pending := int(_info.get("pending", 0))
	var choices: Array = _info.get("choices", []) if pending > 0 else []

	var head := Kit.hbox(Kit.S4)
	var v := Kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(Kit.label("RUN UPGRADE", Kit.FS_XS, Kit.CYAN))
	v.add_child(Kit.label("保留カードを取得", Kit.FS_2XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	v.add_child(Kit.label("保留 %d回。閉じても候補と残り回数は保持されます。" % pending, Kit.FS_SM, Kit.DIM))
	head.add_child(v)
	if pending > 0: head.add_child(_pending_badge(pending))
	var close := Kit.button("あとで・戻る", "ghost", func(): Game.closeCardChoices())
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size.x = 170
	head.add_child(close)
	_root.add_child(head)

	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(mid)
	if choices.is_empty():
		var p := Kit.panel(Kit.SLATE, Kit.S5)
		p.body.add_child(Kit.label("保留中のカードはありません。", Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, false, true))
		p.body.add_child(Kit.label("レベルアップするとここへ追加されます。", Kit.FS_MD, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
		p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mid.add_child(p)
		default_focus = close
	else:
		var row := Kit.hbox(Kit.S4 if not compact else Kit.S3)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for i in choices.size():
			row.add_child(_card_column(choices[i], i, compact))
		mid.add_child(row)
		default_focus = _cards[0] if not _cards.is_empty() else close

	var foot := Kit.hbox(Kit.S4)
	var hint := Kit.label("この画面を開いている間だけ一時停止 / 数字 1〜3 で選択", Kit.FS_SM, Kit.DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(hint)
	_auto_btn = Kit.button("自動取得：ON" if bool(_info.get("auto", false)) else "自動取得：OFF", "ghost", _toggle_auto)
	_auto_btn.custom_minimum_size.x = 200
	foot.add_child(_auto_btn)
	_root.add_child(foot)

func _pending_badge(n: int) -> Control:
	var p := PanelContainer.new()
	var sb := Kit.box(Kit.with_a(Kit.AMBER, 0.12), Kit.with_a(Kit.AMBER, 0.6), 1, 20)
	sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 4; sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := Kit.hbox(8)
	h.add_child(Kit.label("PENDING", Kit.FS_XS, Kit.AMBER))
	h.add_child(Kit.label("×%d" % n, Kit.FS_XL, Kit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	p.add_child(h)
	return p

func _card_column(u: Variant, i: int, compact: bool) -> Control:
	var rar := str(u.get("rarity", "COMMON"))
	var card := Kit.rarity_card(rar, str(u.get("name", "")), str(u.get("desc", "")), str(u.get("icon", "✦")), "選択 %d" % (i + 1))
	card.custom_minimum_size = Vector2(250 if compact else 320, 190 if compact else 240)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.pressed.connect(func(): _pick(u))
	_cards.append(card)
	return card

func _pick(u: Variant) -> void:
	if _mock: return
	Cards.selectUpgrade(u)

func _toggle_auto() -> void:
	if _mock:
		_info.auto = not bool(_info.get("auto", false)); _render(); return
	Game.toggleAutoCards()
	_info.auto = Game.playPreferences.get("autoCards", false)
	_auto_btn.text = "自動取得：ON" if _info.auto else "自動取得：OFF"
