extends NFScreen
## #howScreen — 攻略ガイド「生き残るコツ」. Original: index.html 4780-4845 (HTML), 9843-9850 (JS).
## Hooks: openHow (from home), closeHow (Esc / ✕ / backdrop click). Game.state == "how" while open.

var _return_state := "menu"
var _shell: Control
var _close_btn: Control
var _compact := false

func build() -> void:
	modal = true
	dim_alpha = 0.78
	layer_z = 10
	z_index = layer_z
	get_viewport().size_changed.connect(_on_resize)
	_rebuild()

func _on_resize() -> void:
	if is_open and (Kit.is_compact() != _compact): _rebuild()

func on_open(_args: Dictionary = {}) -> void:
	if Kit.is_compact() != _compact: _rebuild()

func on_cancel() -> bool:
	h_closeHow()
	return true

func h_openHow() -> void:
	_return_state = Game.state
	Game.state = "how"
	Game.cancelCombatInput()
	if _return_state == "menu":
		UI.hide_screen("home")
	UI.show_screen("how")

func h_closeHow() -> void:
	if not is_open: return
	UI.hide_screen("how")
	Game.state = _return_state
	if _return_state == "menu":
		UI.show_screen("home")
	if Inp.has_method("syncInputPresentation"): Inp.syncInputPresentation()
	if Game.state == "playing": UI.hook("focusCombat")
	Game.last = U.now_ms()

func b_resetGameUI(_touch = null) -> void:
	if is_open: UI.hide_screen("how")

func _gui_input(e: InputEvent) -> void:
	# click outside the card closes (original: click on the dim backdrop)
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _shell != null:
		if not _shell.get_global_rect().has_point(e.global_position):
			accept_event()
			h_closeHow()

func _rebuild() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	_compact = Kit.is_compact()
	_build_ui()

func _tip(n: String, title: String, body: String, col: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.035), Kit.with_a(col, 0.28), 1, 12))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := Kit.vbox(Kit.S2)
	var h := Kit.hbox(Kit.S2)
	h.add_child(Kit.label(n, Kit.FS_XL, Kit.with_a(col, 0.55), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	h.add_child(Kit.label(title, Kit.FS_LG, col, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	v.add_child(h)
	v.add_child(Kit.label(body, Kit.FS_MD, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	p.add_child(Kit.margin(v, Kit.S4))
	return p

func _sub(title: String, body: String, col: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(Color(0, 0.02, 0.05, 0.28), Kit.with_a(col, 0.25), 1, 10))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Kit.vbox(2)
	v.add_child(Kit.label(title, Kit.FS_MD, col, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	v.add_child(Kit.label(body, Kit.FS_MD, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
	p.add_child(Kit.margin(v, Kit.S3))
	return p

func _build_ui() -> void:
	var vp := get_viewport_rect().size
	var wide := vp.x >= 1000.0
	var shell := Kit.panel(Kit.CYAN, Kit.S5)
	shell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.custom_minimum_size.x = minf(1380.0 if wide else 760.0, vp.x - 24.0)
	content.add_child(shell)
	_shell = shell
	var root := shell.body
	root.add_theme_constant_override("separation", Kit.S3)

	var head := Kit.hbox(Kit.S4)
	var hv := Kit.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(Kit.label("攻略ガイド", Kit.FS_XS, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	hv.add_child(Kit.label("生き残るコツ", Kit.FS_2XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	head.add_child(hv)
	var close := Kit.button("✕", "ghost", h_closeHow)
	close.custom_minimum_size = Vector2(Kit.btn_h(), Kit.btn_h())
	head.add_child(close)
	_close_btn = close
	default_focus = close
	root.add_child(head)
	root.add_child(Kit.hsep(Kit.with_a(Kit.CYAN, 0.3)))

	var sc := Kit.scroll_list(Kit.S3)
	root.add_child(sc)
	var col := Kit.list_of(sc)

	# left: tips + flow field   /   right: controls
	var grid: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	grid.add_theme_constant_override("separation", Kit.S4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(grid)
	var left := Kit.vbox(Kit.S3)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	grid.add_child(left)
	var tg := GridContainer.new()
	tg.columns = 2
	tg.add_theme_constant_override("h_separation", Kit.S3)
	tg.add_theme_constant_override("v_separation", Kit.S3)
	tg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(tg)
	tg.add_child(_tip("01", "常に動く", "敵はあなたの現在位置へ集まる。円を描くように動けば密度をコントロールできる。", Kit.CYAN))
	tg.add_child(_tip("02", "ダッシュを温存", "SPACEは移動技ではなく緊急回避。敵をすり抜ける瞬間に使うと強い。", Kit.VIOLET))
	tg.add_child(_tip("03", "ビルドを寄せる", "ラン中スキルに加え、恒久カードを最大3枚装備できる。トリガー・条件・確率・効果・強度を組み合わせて戦闘ロジックそのものを作れる。", Kit.EMERALD))
	tg.add_child(_tip("04", "コンボを切らさない", "経験値には5種類ある。生命経験値は回復、希少経験値はアップグレードのレア度を高め、ボスコアはエピックを保証する。", Kit.AMBER))

	var ff := Kit.panel(Kit.CYAN, Kit.S4)
	ff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(ff)
	var fh := Kit.hbox(Kit.S3)
	var fv := Kit.vbox(0)
	fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fv.add_child(Kit.label("FLOW FIELD", Kit.FS_XS, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	fv.add_child(Kit.label("フローフィールドとは？", Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	fh.add_child(fv)
	fh.add_child(Kit.label("すべて通過可能 / 壁判定なし", Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_RIGHT))
	ff.body.add_child(fh)
	ff.body.add_child(Kit.label("マップ上の大きな円形領域。敵もプレイヤーも引っ掛からず、そのまま通り抜けられる。円へ入った瞬間だけ効果が発動し、同じフィールドは8秒間再使用できない。", Kit.FS_MD, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var sub := Kit.hbox(Kit.S2)
	sub.add_child(_sub("» FLOW", "1.65秒間、移動速度 +25%", Kit.CYAN))
	sub.add_child(_sub("◫ CHARGE", "ダッシュゲージを38%回復", Kit.VIOLET))
	sub.add_child(_sub("∞ LINK", "コンボ猶予を1.25秒延長", Kit.AMBER))
	ff.body.add_child(sub)

	var right := Kit.vbox(Kit.S3)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.85
	grid.add_child(right)
	var op := Kit.panel(Kit.VIOLET, Kit.S4)
	op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(op)
	op.body.add_child(Kit.heading("操作：戦闘を止めずに育成", Kit.VIOLET, Kit.FS_LG))
	op.body.add_child(Kit.label("レベルアップでカードの選択権が貯まります。「カード」またはQで好きな時に開き、その間だけ一時停止。自動取得ONでは高レア優先で取得します。候補は閉じても変わりません。", Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	op.body.add_child(Kit.label("ボス撃破ごとに「スキル」またはEから取得・強化・上書きできます。最大3枠、数字1〜3またはタップで発動。強化レベルに上限はありません。", Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	op.body.add_child(Kit.label("□＋の緑タイル＝経験値 / 赤橙の●＝敵弾 / ×付き紫の菱形＝バリア破壊・付与封印 / 橙の菱形＝バリア貫通。予告線・予告円を見て回避してください。バリアとダッシュ回避は別扱いです。", Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	right.add_child(Kit.label("一時停止の「キー配置」で、Q/E/Rをスキル発動に切り替えられます。カード画面は同じキーかEscで戻れます。画面を開いている間、戦闘は停止します。", Kit.FS_MD, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))

	var foot := Kit.button("閉じる", "ghost", h_closeHow)
	root.add_child(foot)
