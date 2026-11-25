extends NFScreen
## Showcase of every Kit widget. NF_SCREEN=kitgallery for screenshots.

func build() -> void:
	modal = true
	dim_alpha = 0.55
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var col := Kit.vbox(Kit.S3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	var head := Kit.hbox(Kit.S4)
	head.add_child(Kit.heading("NEON FRACTURE  //  UI KIT", Kit.CYAN, Kit.FS_XL))
	head.add_child(Kit.fill_spacer())
	head.add_child(Kit.chip("CR", Kit.num(1234567), Kit.AMBER, "◆"))
	head.add_child(Kit.chip("RANK", "Lv 24", Kit.VIOLET))
	head.add_child(Kit.chip("BEST", Kit.short(48250000), Kit.EMERALD))
	var close_btn := Kit.button("閉じる", "ghost", func(): UI.hide_screen("kitgallery"))
	head.add_child(close_btn)
	col.add_child(head)

	var grid := GridContainer.new()
	grid.columns = 2 if Kit.is_compact() else 3
	grid.add_theme_constant_override("h_separation", Kit.S3)
	grid.add_theme_constant_override("v_separation", Kit.S3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(grid)

	# --- buttons
	var p1 := _card(grid, "BUTTONS", Kit.CYAN)
	p1.body.add_child(Kit.button("CTA  出撃", "cta"))
	p1.body.add_child(Kit.button("Primary  強化", "primary"))
	var r := Kit.hbox(Kit.S2)
	var g := Kit.button("Ghost", "ghost"); g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var d := Kit.button("Danger", "danger"); d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(g); r.add_child(d)
	p1.body.add_child(r)
	var dis := Kit.button("Disabled", "primary"); dis.disabled = true
	p1.body.add_child(dis)

	# --- controls
	var p2 := _card(grid, "CONTROLS", Kit.VIOLET)
	p2.body.add_child(Kit.setting_row("ドローン稼働", Kit.toggle(true), "機数・強化は保持されます"))
	p2.body.add_child(Kit.setting_row("オートファイア", Kit.toggle(false)))
	var sl := Kit.slider(0, 100, 1, 70)
	sl.custom_minimum_size.x = 180
	p2.body.add_child(Kit.setting_row("マスター音量", sl))
	p2.body.add_child(Kit.segmented(["全て", "攻撃", "防御", "補助"], 1, Callable(), Kit.VIOLET))
	p2.body.add_child(Kit.label("ツールチップ: ボタンにホバー", Kit.FS_SM, Kit.DIM))
	Kit.tooltip(p2.body.get_child(p2.body.get_child_count() - 1), "tip")

	# --- bars / chips
	var p3 := _card(grid, "STATUS", Kit.EMERALD)
	p3.body.add_child(Kit.bar(0.72, Kit.ROSE, "HP 144 / 200", 22))
	p3.body.add_child(Kit.bar(0.45, Kit.CYAN, "XP", 18))
	p3.body.add_child(Kit.bar(0.9, Kit.AMBER, "", 10))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", Kit.S2)
	chips.add_theme_constant_override("v_separation", Kit.S2)
	chips.add_child(Kit.chip("DMG", "x2.4", Kit.CYAN))
	chips.add_child(Kit.chip("CRIT", Kit.pct(0.18), Kit.FUCHSIA))
	chips.add_child(Kit.chip("TIME", Kit.mmss(754), Kit.EMERALD))
	chips.add_child(Kit.chip("WAVE", 12, Kit.AMBER))
	p3.body.add_child(chips)
	var act := Kit.hbox(Kit.S2)
	act.add_child(Kit.button("確認ダイアログ", "ghost", func():
		Kit.confirm("リセット確認", "進行中のランを破棄してホームへ戻ります。よろしいですか？",
			func(): UI.toast("OK", "ok"), func(): UI.toast("キャンセル", "warn"), "破棄する", "戻る", true)))
	act.add_child(Kit.button("Toast", "ghost", func(): UI.toast("武装を強化しました  +12%", "ok")))
	p3.body.add_child(act)

	# --- rarity cards
	var rc := Kit.hbox(Kit.S3)
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var data := [["COMMON", "パルス増幅器", "弾ダメージ +12%", "✦", "Lv3"], ["RARE", "レールコア", "貫通 +1 / ダメージ +9%", "⇢", "Lv2"],
		["EPIC", "ドローン母核", "ドローン1機 / 威力 +36%", "◎", "Lv1"], ["LEGENDARY", "ソヴリン・コア", "ダメージ +21% / クリ率 +15%", "♛", "Lv5"]]
	for it in data:
		var c := Kit.rarity_card(it[0], it[1], it[2], it[3], it[4])
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.pressed.connect(func(): UI.toast("%s を選択" % it[1], "info"))
		rc.add_child(c)
	col.add_child(rc)

	# --- palette + type
	var p4 := Kit.panel(Kit.SLATE, Kit.S3)
	p4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(p4)
	var sw := Kit.hbox(Kit.S2)
	for pair in [["CYAN", Kit.CYAN], ["VIOLET", Kit.VIOLET], ["FUCHSIA", Kit.FUCHSIA], ["AMBER", Kit.AMBER], ["EMERALD", Kit.EMERALD], ["ROSE", Kit.ROSE], ["SLATE", Kit.SLATE]]:
		var v := Kit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cr := ColorRect.new(); cr.color = pair[1]; cr.custom_minimum_size.y = 14
		v.add_child(cr); v.add_child(Kit.label(pair[0], Kit.FS_XS, Kit.DIM))
		sw.add_child(v)
	p4.body.add_child(sw)
	p4.body.add_child(Kit.label("ネオンフラクチャー 日本語表示  ABC 0123 / 12,345,678 CR", Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	default_focus = close_btn

func _card(parent: Node, title: String, accent: Color) -> Kit.GlassPanel:
	var p := Kit.panel(accent, Kit.S4)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.body.add_child(Kit.label(title, Kit.FS_SM, accent, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	p.body.add_child(Kit.hsep(Kit.with_a(accent, 0.3)))
	parent.add_child(p)
	return p
