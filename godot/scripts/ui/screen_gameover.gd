extends NFScreen
## リザルト (原作 #gameOverScreen 4869 / gameOver 8157-8245)
## Hook: showGameOver(info) -- info shape: see game.gd gameOver(). Broadcasts: showHome resetGameUI openMeta closeMeta showPause.
## Buttons: もう一度挑戦 -> Game.resetGame(), CRを使って強化 -> Meta.openMeta("gameover"), ホームへ -> Game.returnHome(), 音声設定.
## Mock data: NF_SCREEN=gameover (only when no result was received).

var _info: Dictionary = {}
var _root: Control
var _tween: Tween

func _init() -> void:
	modal = true
	dim_alpha = 0.86
	layer_z = 45

func build() -> void:
	pass

func h_showGameOver(info: Variant = null) -> void:
	_info = info if info is Dictionary else {}
	UI.hide_screen("pause")
	UI.show_screen("gameover")

func b_showHome() -> void: UI.hide_screen("gameover"); _info = {}
func b_resetGameUI(_t: Variant = null) -> void: UI.hide_screen("gameover"); _info = {}
func b_openMeta(_f: Variant = null) -> void: UI.hide_screen("gameover")
func b_closeMeta() -> void:
	# Meta opened from the result returns to it (Meta.closeMeta sets state back to "gameover")
	if Game.state == "gameover" and not _info.is_empty(): UI.show_screen("gameover")
func b_hidePanel(id: Variant = "") -> void:
	if str(id) == "gameOverScreen": UI.hide_screen("gameover")

func on_open(_args: Dictionary = {}) -> void:
	if _info.is_empty() and OS.get_environment("NF_SCREEN") == "gameover":
		_info = _mock()
	_render()

func _mock() -> Dictionary:
	return {"reason": "death", "eligible": true, "wasHigh": true, "score": 1284650, "wave": 17, "kills": 842,
		"earnedCredits": 18420, "earnedData": 214, "playerXpGain": 6210, "levelBefore": 14, "levelsGained": 2, "playerLevel": 16,
		"newAchievements": [{"id": "a1", "name": "撃破の洗礼", "desc": "500体撃破", "reward": 20}, {"id": "a2", "name": "ボスハンター", "desc": "ボスを3体撃破", "reward": 30}],
		"runLoot": {"count": 5, "newSyntax": 2, "cards": 1, "gear": 1, "profile": {"rank": "A", "gear": 0.182, "card": 0.094, "rarePlus": 0.41, "epicPlus": 0.16, "legendary": 0.021}},
		"cp": 2.35, "cpLabel": "HARD", "rewardMultiplier": 1.82, "mode": "endless", "finalWaveTarget": 30,
		"growthSummary": "火力 Lv.4 / 連射 Lv.3 / 経済 Lv.2", "devActions": 0, "highScore": 1284650, "bestWave": 17}

# ------------------------------------------------------------------ text by reason (原作 8210-8243)
func _tag_title_msg() -> Array:   # [tag, title, message, color]
	var reason := str(_info.get("reason", "death"))
	var eligible: bool = bool(_info.get("eligible", true))
	var cpl := str(_info.get("cpLabel", ""))
	var cp := float(_info.get("cp", 1.0))
	var wave := int(_info.get("wave", 0))
	if not eligible:
		return ["DEVELOPER RUN", "DEV CLEAR" if reason == "clear" else "実験終了",
			"CP変更・自由強化を使用した実験ランです。報酬・実績・ハイスコアには反映しません。", Kit.VIOLET]
	if reason == "clear":
		return ["MISSION COMPLETE", "CLEAR", "Wave %s 最終Boss撃破 / %s / CP %.2f" % [str(_info.get("finalWaveTarget", wave)), cpl, cp], Kit.EMERALD]
	if reason == "settle":
		return ["自主帰還・集計完了", "ランを確定", "現在までのスコア・CR・構文資産を正式に持ち帰った。", Kit.AMBER]
	var msg := "シグナルが途絶えた。能力の組み合わせを変えて再挑戦しよう。"
	if wave >= 10: msg = "高Wave到達。ビルドを調整すればさらに伸ばせる。"
	elif wave >= 5: msg = "報酬を持ち帰った。装備と研究を更新して次のランへ。"
	return ["シグナル消失", "撃破された", msg, Kit.ROSE]

# ------------------------------------------------------------------ build
func _render() -> void:
	if _root != null and is_instance_valid(_root):
		content.remove_child(_root)
		_root.queue_free()
	if _tween and _tween.is_valid(): _tween.kill()
	var compact := Kit.is_compact()
	var eligible: bool = bool(_info.get("eligible", true))
	var tt := _tag_title_msg()
	var accent: Color = tt[3]
	_root = Kit.vbox(Kit.S3 if compact else Kit.S4)
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_root)

	var body := Kit.hbox(Kit.S5 if not compact else Kit.S4)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(body)

	# ---------------- left: headline + core stats
	var left := Kit.vbox(Kit.S3)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(left)
	left.add_child(Kit.label(tt[0], Kit.FS_SM, accent))
	left.add_child(Kit.label(tt[1], Kit.FS_3XL if not compact else Kit.FS_2XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	left.add_child(Kit.label(tt[2], Kit.FS_MD, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var gs := str(_info.get("growthSummary", ""))
	if gs != "": left.add_child(Kit.label("開始時の成長適用：" + gs, Kit.FS_SM, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
	if bool(_info.get("wasHigh", false)):
		left.add_child(_banner("★ ハイスコア更新！", Kit.CYAN))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Kit.S2)
	grid.add_theme_constant_override("v_separation", Kit.S2)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(grid)
	var score_lbl := Kit.label("0", Kit.FS_2XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	var final_target = _info.get("finalWaveTarget", null)
	var wave_sub := ""
	if str(_info.get("mode", "")) == "clear" and final_target != null: wave_sub = "/ %s" % str(final_target)
	var cr_text := "+" + Kit.num(_info.get("earnedCredits", 0))
	grid.add_child(_stat_tile("スコア", score_lbl, Kit.TEXT, "BEST " + Kit.num(_info.get("highScore", 0)) if eligible else ""))
	grid.add_child(_stat_tile("ウェーブ", Kit.label("%s %s" % [str(_info.get("wave", 0)), wave_sub], Kit.FS_2XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true), Kit.TEXT, "BEST %s" % str(_info.get("bestWave", 0)) if eligible else ""))
	grid.add_child(_stat_tile("撃破数", Kit.label(Kit.num(_info.get("kills", 0)), Kit.FS_2XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true), Kit.TEXT, ""))
	grid.add_child(_stat_tile("獲得CR", Kit.label(cr_text, Kit.FS_2XL, Kit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, false, true), Kit.AMBER, "スコア中心 + Wave / 撃破 / ボス補正 × 換金研究"))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", Kit.S2)
	chips.add_theme_constant_override("v_separation", Kit.S2)
	chips.add_child(Kit.chip("DATA", "+" + Kit.num(_info.get("earnedData", 0)), Kit.VIOLET))
	chips.add_child(Kit.chip("CP", "%.2f" % float(_info.get("cp", 1.0)), Kit.AMBER))
	chips.add_child(Kit.chip("Reward", ("×%.2f" % float(_info.get("rewardMultiplier", 1.0))) if eligible else "対象外", Kit.CYAN))
	var mode_txt := "%s / %s" % ["CLEAR" if str(_info.get("mode", "endless")) == "clear" else "ENDLESS", str(_info.get("cpLabel", ""))]
	chips.add_child(Kit.chip(mode_txt, null, Kit.SLATE))
	left.add_child(chips)

	# ---------------- right: run analysis
	var right := Kit.panel(Kit.VIOLET, Kit.S4 if not compact else Kit.S3)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var sc := Kit.scroll_list(Kit.S3)
	right.body.add_child(sc)
	_analysis(Kit.list_of(sc), eligible)

	# ---------------- actions
	var acts := Kit.hbox(Kit.S3)
	_root.add_child(acts)
	var retry := Kit.button("もう一度挑戦  ↻", "cta", _retry)
	var meta := Kit.button("CRを使って強化", "primary", func(): Meta.openMeta("gameover"))
	var home := Kit.button("ホームへ", "ghost", func(): Game.returnHome())
	var audio := Kit.button("音声設定", "ghost", func(): UI.hook("openUtility", ["audio"]))
	for b in [retry, meta, home]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acts.add_child(b)
	acts.add_child(audio)
	default_focus = retry

	# count-up of the score
	var target := int(_info.get("score", 0))
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(v: float): score_lbl.text = Kit.num(roundi(v)), 0.0, float(target), 0.9)

func _retry() -> void:
	if Game.resetGame(): UI.hide_screen("gameover")

func _banner(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var sb := Kit.box(Kit.with_a(col, 0.12), Kit.with_a(col, 0.55), 1, 8, Kit.with_a(col, 0.25), 10)
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(Kit.label(text, Kit.FS_LG, col, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p

func _stat_tile(title: String, value: Control, color: Color, sub: String) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := Kit.box(Kit.with_a(color, 0.06 if color != Kit.TEXT else 0.035), Kit.with_a(color, 0.28 if color != Kit.TEXT else 0.10), 1, 10)
	sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 10; sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var v := Kit.vbox(0)
	v.add_child(Kit.label(title, Kit.FS_XS, Kit.DIM))
	v.add_child(value)
	if sub != "": v.add_child(Kit.label(sub, Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
	p.add_child(v)
	return p

func _analysis(l: VBoxContainer, eligible: bool) -> void:
	var loot: Dictionary = _info.get("runLoot", {})
	var prof: Dictionary = loot.get("profile", {})
	var head := Kit.hbox(Kit.S3)
	var hv := Kit.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(Kit.label("RUN ANALYSIS", Kit.FS_XS, Kit.VIOLET))
	hv.add_child(Kit.label("報酬評価", Kit.FS_SM, Kit.DIM))
	head.add_child(hv)
	var rank := str(prof.get("rank", "C"))
	head.add_child(Kit.label(rank if eligible else "—", Kit.FS_3XL, Kit.CYAN if eligible else Kit.MUTE, HORIZONTAL_ALIGNMENT_RIGHT, false, true))
	l.add_child(head)
	l.add_child(Kit.hsep())

	if not eligible:
		l.add_child(Kit.label("報酬対象外", Kit.FS_LG, Kit.AMBER, HORIZONTAL_ALIGNMENT_LEFT, false, true))
		l.add_child(Kit.label("恒久Lv・CR・DATA・構文・カード・装備・実績は変更していません。次の通常ランはモード選択から始められます。", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		l.add_child(Kit.label("検証CP %.2f / 自由操作 %s回。報酬倍率の試算は表示のみです。" % [float(_info.get("cp", 1.0)), str(_info.get("devActions", 0))], Kit.FS_SM, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
		return

	# loot + xp
	var lv_before := int(_info.get("levelBefore", 1))
	var gained := int(_info.get("levelsGained", 0))
	var row := Kit.hbox(Kit.S2)
	row.add_child(Kit.chip("解析", "%d枠" % int(loot.get("count", 0)), Kit.CYAN))
	row.add_child(Kit.chip("新規構文", str(int(loot.get("newSyntax", 0))), Kit.VIOLET))
	row.add_child(Kit.chip("完成カード", str(int(loot.get("cards", 0))), Kit.AMBER))
	row.add_child(Kit.chip("装備", str(int(loot.get("gear", 0))), Kit.EMERALD))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", Kit.S2)
	flow.add_theme_constant_override("v_separation", Kit.S2)
	for c in row.get_children():
		row.remove_child(c); flow.add_child(c)
	row.queue_free()
	l.add_child(flow)
	l.add_child(Kit.label("最低保証込みで構文・カード・装備を獲得しました。", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))

	var xp_box := Kit.vbox(4)
	var xp_row := Kit.hbox(Kit.S3)
	xp_row.add_child(Kit.label("Player XP +%s" % Kit.num(_info.get("playerXpGain", 0)), Kit.FS_MD, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	xp_row.add_child(Kit.fill_spacer())
	var lvtxt := "Player Lv.%d" % lv_before
	if gained > 0: lvtxt += "  →  Lv.%d  (+%d)" % [int(_info.get("playerLevel", lv_before + gained)), gained]
	else: lvtxt += "  (変化なし)"
	xp_row.add_child(Kit.label(lvtxt, Kit.FS_MD, Kit.EMERALD if gained > 0 else Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, false, true))
	xp_box.add_child(xp_row)
	if Meta.meta.has("playerXp") and Meta.meta.has("playerLevel"):
		var need: float = maxf(1.0, float(Meta.playerXpNeeded(Meta.meta.playerLevel)))
		xp_box.add_child(Kit.bar(clampf(float(Meta.meta.playerXp) / need, 0.0, 1.0), Kit.CYAN, "", 10))
	l.add_child(xp_box)

	var ach: Array = _info.get("newAchievements", [])
	if not ach.is_empty():
		l.add_child(Kit.hsep())
		var total := 0
		for a in ach: total += int(a.get("reward", 0))
		l.add_child(Kit.label("実績解除 %d件  /  +%d DATA" % [ach.size(), total], Kit.FS_MD, Kit.EMERALD, HORIZONTAL_ALIGNMENT_LEFT, false, true))
		for a in ach:
			var r := Kit.hbox(Kit.S2)
			r.add_child(Kit.label("◆", Kit.FS_SM, Kit.EMERALD))
			var t := Kit.label("%s  %s" % [str(a.get("name", "")), str(a.get("desc", ""))], Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(t)
			r.add_child(Kit.label("+%s" % str(a.get("reward", 0)), Kit.FS_SM, Kit.VIOLET))
			l.add_child(r)
	l.add_child(Kit.hsep())
	if not prof.is_empty():
		l.add_child(Kit.label("スコア補正: 装備 %.1f%% / 完成カード %.1f%% / RARE+ %.1f%% / EPIC+ %.1f%% / LEGENDARY %.2f%%（各確率には上限あり）" % [
			float(prof.get("gear", 0)) * 100.0, float(prof.get("card", 0)) * 100.0, float(prof.get("rarePlus", 0)) * 100.0,
			float(prof.get("epicPlus", 0)) * 100.0, float(prof.get("legendary", 0)) * 100.0], Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_LEFT, true))
