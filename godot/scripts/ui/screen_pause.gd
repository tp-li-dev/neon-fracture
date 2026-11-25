extends NFScreen
## 一時停止 (原作 #pauseScreen 4846 / setPause 8294 / showPauseConfirm 8269 / renderRunStatus 8279 / 中断セーブ 10396-10512)
## Hooks: showPause(info) hidePause showPauseConfirm(action) hidePauseConfirm; broadcasts: renderRunStatus syncDroneControls
## syncInputSettings showHome resetGameUI hidePanel showGameOver showUpgrade openAbilityRewards.
## Layout: left "action dashboard" (summary tiles + 4 actions), right tabbed panel (ビルド/ドローン/操作/中断セーブ).
## Mock data for screenshots: NF_SCREEN=pause (used only when no run exists).

const TABS := ["ビルド", "ドローン", "操作", "中断セーブ"]
const PRIORITIES := [["nearest", "近い敵"], ["boss", "ボス優先"], ["elite", "エリート優先"],
	["weakest", "残りHPが少ない敵"], ["strongest", "残りHPが多い敵"], ["aim", "照準付近"]]

var _info: Dictionary = {}
var _tab := 0
var _root: Control
var _tab_stack: Control
var _confirm: Control = null
var _suspend_msg := "中断保存は1枠。再開時は一時停止画面で待機します。報酬はラン終了まで未確定。"
var _suspend_label: Label
var _key_summary: Label
var _layout_seg: Kit.Segmented
var _device_seg: Kit.Segmented
var _drone_refs: Dictionary = {}
var _mock := false

func _init() -> void:
	modal = true
	dim_alpha = 0.78
	layer_z = 40

func build() -> void:
	pass

# ------------------------------------------------------------------ hooks
func h_showPause(info: Variant = null) -> void:
	_info = info if info is Dictionary else {}
	_suspend_msg = "中断保存は1枠。再開時は一時停止画面で待機します。報酬はラン終了まで未確定。"
	UI.show_screen("pause")

func h_hidePause() -> void:
	_close_confirm()
	UI.hide_screen("pause")

func h_showPauseConfirm(action: Variant = "home") -> void:
	_close_confirm()
	var restart := str(action) == "restart"
	var title := "最初からやり直す" if restart else "集計せずホームへ"
	var msg := "最初からやり直します。\n現在のスコア・CR・構文報酬はすべて破棄されます。" if restart \
		else "集計せずホームへ戻ります。\nこのランで得た成果は保存されません。"
	_confirm = Kit.confirm(title, msg, func():
			_confirm = null
			Game.pausePendingAction = null
			if restart: Game.resetGame()
			else: Game.returnHome(),
		func():
			_confirm = null
			Game.pausePendingAction = null,
		"破棄して進む", "キャンセル", true)

func h_hidePauseConfirm() -> void:
	_close_confirm()

func b_syncDroneControls() -> void:
	if is_open: _refresh_drone()

func b_syncInputSettings(_prefs: Variant = null, _keys: Variant = null) -> void:
	if is_open: _refresh_input()

func b_renderRunStatus() -> void:
	pass  # contents are rebuilt in on_open (hook order: renderRunStatus -> showPause)

func b_showHome() -> void:
	_close_confirm(); UI.hide_screen("pause")

func b_resetGameUI(_touch: Variant = null) -> void:
	_close_confirm(); UI.hide_screen("pause")

func b_showGameOver(_info: Variant = null) -> void:
	_close_confirm(); UI.hide_screen("pause")

func b_showUpgrade() -> void:
	UI.hide_screen("pause")

func b_openAbilityRewards() -> void:
	UI.hide_screen("pause")

func b_hidePanel(id: Variant = "") -> void:
	if str(id) == "pauseScreen": UI.hide_screen("pause")

func _close_confirm() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		UI.pop_modal(_confirm)
	_confirm = null

func on_cancel() -> bool:
	return false  # Esc -> Inp.handleEscape -> Game.togglePause

func on_close() -> void:
	_close_confirm()

# ------------------------------------------------------------------ build
func on_open(_args: Dictionary = {}) -> void:
	_mock = OS.get_environment("NF_SCREEN") == "pause" and Game.player.is_empty()
	_rebuild()

func _rebuild() -> void:
	if _root != null and is_instance_valid(_root):
		content.remove_child(_root)
		_root.queue_free()
	_drone_refs.clear()
	_root = Kit.vbox(Kit.S3 if Kit.is_compact() else Kit.S4)
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_root)
	_root.add_child(_header())
	var body := Kit.hbox(Kit.S4)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(body)
	var left := _left_column()
	left.custom_minimum_size.x = 330 if Kit.is_compact() else 380
	body.add_child(left)
	body.add_child(_right_panel())
	default_focus = _resume_btn

var _resume_btn: Button

func _header() -> Control:
	var h := Kit.hbox(Kit.S4)
	var v := Kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(Kit.label("RUN CONTROL", Kit.FS_XS, Kit.CYAN))
	v.add_child(Kit.label("一時停止", Kit.FS_2XL, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	v.add_child(Kit.label("スキルCD・敵・弾・デバフは停止中", Kit.FS_SM, Kit.DIM))
	h.add_child(v)
	_resume_btn = Kit.button("ゲームに戻る  ▶", "cta", func(): Game.setPause(false))
	_resume_btn.custom_minimum_size = Vector2(240, Kit.btn_h() + 8)
	_resume_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_resume_btn)
	return h

func _tile(title: String, value: String, color: Color) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := Kit.box(Kit.with_a(color, 0.07), Kit.with_a(color, 0.32), 1, 8)
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var v := Kit.vbox(0)
	v.add_child(Kit.label(title, Kit.FS_XS, Kit.DIM))
	v.add_child(Kit.label(value, Kit.FS_XL, color, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	p.add_child(v)
	return p

func _left_column() -> Control:
	var col := Kit.vbox(Kit.S3)
	var lvl: int; var score: int; var cr: int; var loot: int
	if _mock:
		lvl = 18; score = 482350; cr = 3920; loot = 4
	else:
		lvl = int(_info.get("level", Game.player.get("level", 1)))
		score = int(_info.get("score", floorf(Game.score)))
		cr = int(_info.get("credits", Meta.earnedCreditAmount()))
		loot = int(_info.get("loot", Meta.runRewardCount()))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", Kit.S2)
	g.add_theme_constant_override("v_separation", Kit.S2)
	g.add_child(_tile("レベル", "Lv.%d" % lvl, Kit.CYAN))
	g.add_child(_tile("スコア", Kit.num(score), Kit.TEXT))
	g.add_child(_tile("集計時のCR", "+" + Kit.num(cr), Kit.AMBER))
	g.add_child(_tile("報酬", "%d枠" % loot, Kit.VIOLET))
	col.add_child(g)
	col.add_child(Kit.label(_mode_text(), Kit.FS_SM, Kit.AMBER))
	var hp: float = 0.72; var xp: float = 0.4
	var hp_t := "HP 144 / 200"; var xp_t := "XP 40%"
	if not _mock and not Game.player.is_empty():
		var pl: Dictionary = Game.player
		hp = float(pl.hp) / maxf(1.0, float(pl.maxHp)); xp = float(pl.xp) / maxf(1.0, float(pl.nextXp))
		hp_t = "HP %d / %d" % [ceili(float(pl.hp)), ceili(float(pl.maxHp))]
		xp_t = "XP %d%%  (保留 %d)" % [roundi(xp * 100.0), Game.pendingLevelUps]
	col.add_child(Kit.bar(hp, Kit.ROSE, hp_t, 20))
	col.add_child(Kit.bar(xp, Kit.CYAN, xp_t, 20))
	col.add_child(Kit.fill_spacer())
	var actions := GridContainer.new()
	actions.columns = 2 if Kit.is_compact() else 1
	actions.add_theme_constant_override("h_separation", Kit.S2)
	actions.add_theme_constant_override("v_separation", Kit.S2)
	var defs := [
		["中断保存してホーム", "primary", _on_suspend],
		["ここで集計して終了", "success", func(): Game.gameOver("settle")],
		["最初からやり直す", "ghost", func(): Game.showPauseConfirm("restart")],
		["集計せずホーム", "danger", func(): Game.showPauseConfirm("home")],
	]
	for d in defs:
		var b := Kit.button(d[0], d[1], d[2])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)
	col.add_child(actions)
	return col

func _mode_text() -> String:
	if _mock: return "ENDLESS / NORMAL / CP 1.00"
	var c: Dictionary = Meta.challenge()
	return "%s / %s / CP %.2f" % [str(Meta.runConfig.get("mode", "endless")).to_upper(), str(c.get("label", "")), float(c.get("cp", 1.0))]

func _right_panel() -> Control:
	var p := Kit.panel(Kit.CYAN, Kit.S3 if Kit.is_compact() else Kit.S4)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var seg := Kit.segmented(TABS, _tab, func(i): _set_tab(i))
	p.body.add_child(seg)
	_tab_stack = Control.new()
	_tab_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.body.add_child(_tab_stack)
	var pages := [_page_build(), _page_drone(), _page_input(), _page_suspend()]
	for pg in pages:
		(pg as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
		_tab_stack.add_child(pg)
	_set_tab(_tab)
	return p

func _set_tab(i: int) -> void:
	_tab = i
	var n := 0
	for c in _tab_stack.get_children():
		c.visible = n == i
		n += 1

func _page() -> Array:
	var sc := Kit.scroll_list(Kit.S3)
	return [sc, Kit.list_of(sc)]

func _section(title: String, color: Color = Kit.CYAN) -> Label:
	return Kit.label(title, Kit.FS_XS, color)

# ------------------------------------------------------------------ tab: build
func _stat_cell(title: String, value: String) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := Kit.box(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.08), 1, 6)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var v := Kit.vbox(0)
	v.add_child(Kit.label(title, Kit.FS_XS, Kit.MUTE))
	v.add_child(Kit.label(value, Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, true))
	p.add_child(v)
	return p

func _skill_name(id: String) -> String:
	for arr in [Cards.skills, Cards.uniqueEpics, Cards.legendarySkills]:
		for s in arr:
			if str(s.get("id", "")) == id: return str(s.get("name", id))
	return id

func _page_build() -> Control:
	var pg := _page()
	var l: VBoxContainer = pg[1]
	var p: Dictionary = Game.player
	var stats: Array
	var skills_rich: Array = []   # [name, rank]
	var details: Array = []
	if _mock:
		stats = [["DAMAGE", "86.4"], ["FIRE RATE", "7.2/s"], ["PROJECTILES", "3"], ["CRIT", "28% ×2.10"],
			["PIERCE / BOUNCE", "2 / 1"], ["LIFESTEAL", "2.5% / Heal 70%"], ["PICKUP", "230 / ESP"], ["DRONES", "4機 / 単体 11.2 / 1.62発/秒"]]
		skills_rich = [["オーバーチャージ", 3], ["ハイパーフィード", 2], ["マルチスプレッド", 2], ["クリティカルコア", 1]]
		details = ["このランの成長適用：火力 Lv.4 / 連射 Lv.3 / 経済 Lv.2（途中変更なし）",
			"敵 Lv.24 / シールド 1 / バリア 0.0秒 / 付与封印 0.0秒 / 回復阻害 0.0秒。",
			"1: 貫通砲 Lv.2 / CD 9.0秒 / 残り 0.0秒 ｜ 2: 未取得 ｜ 3: 未取得 / ボス報酬保留 1回",
			"カード保留 2回 / 自動 OFF / 最近の取得：ハイパーフィード → オーバーチャージ",
			"実ダメージ：本体 182,400 / ドローン 41,250 / スキル 22,900 / 装備 8,120 / 追加効果 3,400"]
	else:
		stats = _real_stats(p)
		var ranks: Dictionary = p.get("skillRanks", {})
		for id in ranks:
			if int(ranks[id]) > 0: skills_rich.append([_skill_name(str(id)), int(ranks[id])])
		details = _real_details(p)
	l.add_child(_section("CURRENT BUILD  現在の最終ステータス"))
	var g := GridContainer.new()
	g.columns = 2 if Kit.is_compact() else 4
	g.add_theme_constant_override("h_separation", Kit.S2)
	g.add_theme_constant_override("v_separation", Kit.S2)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in stats: g.add_child(_stat_cell(s[0], s[1]))
	l.add_child(g)
	l.add_child(_section("ラン中強化", Kit.VIOLET))
	if skills_rich.is_empty():
		l.add_child(Kit.label("まだラン中強化を取得していません。", Kit.FS_SM, Kit.DIM))
	else:
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", Kit.S2)
		fl.add_theme_constant_override("v_separation", Kit.S2)
		for s in skills_rich:
			var rk: int = s[1]
			fl.add_child(Kit.chip(s[0], "★" if rk >= 4 else ("R%d" % rk), Kit.AMBER if rk >= 4 else (Kit.VIOLET if rk >= 3 else Kit.SLATE)))
		l.add_child(fl)
	l.add_child(Kit.hsep())
	for d in details:
		if str(d) != "": l.add_child(Kit.label(str(d), Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var row := Kit.hbox(Kit.S2)
	var keys: Dictionary = Inp.currentKeys()
	var b1 := Kit.button("カードを開く [%s]" % Inp.keyLabel(str(keys.cards)), "primary", func(): Cards.showUpgrade())
	var b2 := Kit.button("スキル獲得・強化 [%s]" % Inp.keyLabel(str(keys.rewards)), "primary", func(): Combat.openAbilityRewards())
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(b1); row.add_child(b2)
	l.add_child(row)
	return pg[0]

func _real_stats(p: Dictionary) -> Array:
	if p.is_empty(): return []
	var c: Dictionary = Meta.challenge()
	var pickup: String = "GLOBAL" if p.get("globalPickup", false) else str(roundi(float(p.get("magnet", 0))))
	pickup += " / ESP++" if p.get("mapEspAdvanced", false) else (" / ESP" if p.get("mapEsp", false) else "")
	var ds: Dictionary = UI.droneStats()
	return [
		["DAMAGE", "%.1f" % float(p.damage)],
		["FIRE RATE", "%.1f/s" % float(p.fireRate)],
		["PROJECTILES", str(p.multishot)],
		["CRIT", "%d%% ×%.2f" % [roundi(float(p.crit) * 100.0), float(p.critMult)]],
		["PIERCE / BOUNCE", "%s / %s" % [str(p.pierce), str(p.bulletBounces)]],
		["LIFESTEAL", "%.1f%% / Heal %d%%" % [float(p.lifesteal) * 100.0, roundi(float(p.get("healEfficiency", 0.70)) * float(c.heal) * 100.0)]],
		["PICKUP", pickup],
		["DRONES", "%d機 / 単体 %.1f / %.2f発/秒" % [int(p.droneCount), float(ds.damage), float(ds.rate)]],
	]

func _real_details(p: Dictionary) -> Array:
	if p.is_empty(): return []
	var out: Array = []
	if Meta.runGrowth != null:
		out.append("このランの成長適用：" + Meta.growthSummary(Meta.runGrowth) + "（途中変更なし）")
	out.append("敵 Lv.%d / シールド %s / バリア %.1f秒 / 付与封印 %.1f秒 / 回復阻害 %.1f秒。×印の紫弾・予告区域は全破壊＋封印、橙の菱形はバリア貫通。どちらもダッシュで回避できます。" % [
		Enemies.enemyLevelForWave(), str(p.shieldHits), float(p.barrierTime), float(p.barrierLock), float(p.wounded)])
	var parts: Array = []
	for i in Game.activeSlots.size():
		var s = Game.activeSlots[i]
		if s != null:
			parts.append("%d: %s Lv.%d / CD %.1f秒 / 残り %.1f秒" % [i + 1, Combat.ACTIVE_DEFS[s.id].name, int(s.level), Combat.activeCooldown(s), float(s.remaining)])
		else:
			parts.append("%d: 未取得" % (i + 1))
	out.append(" ｜ ".join(parts) + " / ボス報酬保留 %d回" % Game.abilityRewards.size())
	var hist: Array = []
	for h in Game.autoHistory: hist.append(str(h.name))
	out.append("カード保留 %d回 / 自動 %s / 最近の取得：%s" % [Game.pendingLevelUps, "ON" if Game.playPreferences.autoCards else "OFF", " → ".join(hist) if not hist.is_empty() else "なし"])
	var charging := 0
	for s in Game.activeSlots: if s != null and s.get("charging") != null: charging += 1
	out.append("チャージ効率 +%d%% / ビーム威力 ×%.2f / 装備パッシブ %d系統 / 充填中 %d枠" % [roundi(float(p.chargeEfficiency) * 100.0), float(p.beamPower), p.gearEffects.size(), charging])
	var dd: Dictionary = Game.runDamageTotals
	out.append("実ダメージ：本体 %s / ドローン %s / スキル %s / 装備 %s / 追加効果 %s" % [Kit.num(roundi(dd.player)), Kit.num(roundi(dd.drone)), Kit.num(roundi(dd.active)), Kit.num(roundi(dd.gear)), Kit.num(roundi(dd.other))])
	return out

# ------------------------------------------------------------------ tab: drone
func _page_drone() -> Control:
	var pg := _page()
	var l: VBoxContainer = pg[1]
	var cfg: Dictionary = UI.droneConfig
	_drone_refs.summary = Kit.label("", Kit.FS_SM, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.add_child(_drone_refs.summary)
	var t_en := Kit.toggle(cfg.enabled, func(v): UI.setDroneConfig({"enabled": v}); _refresh_drone())
	_drone_refs.enabled = t_en
	l.add_child(Kit.setting_row("ドローン稼働", t_en, "停止時は飛行中のドローン弾も消去。機数・強化は保持されます。"))
	l.add_child(_section("攻撃してよい敵"))
	var row := Kit.hbox(Kit.S4)
	for k in [["normal", "通常"], ["elite", "エリート"], ["boss", "ボス"]]:
		var h := Kit.hbox(Kit.S2)
		var tg := Kit.toggle(cfg[k[0]], func(v): UI.setDroneConfig({k[0]: v}); _refresh_drone())
		_drone_refs[k[0]] = tg
		h.add_child(tg)
		h.add_child(Kit.label(k[1], Kit.FS_MD))
		row.add_child(h)
	l.add_child(row)
	l.add_child(_section("攻撃優先順位"))
	var names: Array = []
	for pr in PRIORITIES: names.append(pr[1])
	var idx := 0
	for i in PRIORITIES.size():
		if PRIORITIES[i][0] == cfg.priority: idx = i
	var s1 := Kit.segmented(names.slice(0, 3), idx if idx < 3 else -1, Callable())
	var s2 := Kit.segmented(names.slice(3, 6), idx - 3 if idx >= 3 else -1, Callable())
	s1.selected.connect(func(i): s2.set_index(-1); UI.setDroneConfig({"priority": PRIORITIES[i][0]}); _refresh_drone())
	s2.selected.connect(func(i): s1.set_index(-1); UI.setDroneConfig({"priority": PRIORITIES[i + 3][0]}); _refresh_drone())
	_drone_refs.s1 = s1; _drone_refs.s2 = s2
	l.add_child(s1); l.add_child(s2)
	var out_lbl := Kit.label("出力  %d%%" % int(cfg.output), Kit.FS_MD, Kit.TEXT)
	_drone_refs.out_lbl = out_lbl
	var sl := Kit.slider(0, 100, 1, float(cfg.output), func(v):
		UI.setDroneConfig({"output": v}); _refresh_drone())
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drone_refs.slider = sl
	var orow := Kit.hbox(Kit.S4)
	orow.add_child(out_lbl)
	orow.add_child(sl)
	l.add_child(orow)
	l.add_child(Kit.button("稼働100%・全敵に戻す", "ghost", func():
		UI.setDroneConfig({"enabled": true, "normal": true, "elite": true, "boss": true, "output": 100}); _refresh_drone()))
	l.add_child(Kit.label("強化や機数は失いません。出力は現在のドローン火力に対する割合で、成長の上限ではありません。対象制限は誘導先と命中判定の両方へ適用します。", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	_refresh_drone()
	return pg[0]

func _refresh_drone() -> void:
	if _drone_refs.is_empty(): return
	var cfg: Dictionary = UI.droneConfig
	if is_instance_valid(_drone_refs.get("enabled")): _drone_refs.enabled.set_value(cfg.enabled)
	for k in ["normal", "elite", "boss"]:
		if is_instance_valid(_drone_refs.get(k)): _drone_refs[k].set_value(cfg[k])
	var idx := 0
	for i in PRIORITIES.size():
		if PRIORITIES[i][0] == cfg.priority: idx = i
	if is_instance_valid(_drone_refs.get("s1")):
		_drone_refs.s1.index = idx if idx < 3 else -1
		_drone_refs.s1._refresh()
		_drone_refs.s2.index = idx - 3 if idx >= 3 else -1
		_drone_refs.s2._refresh()
	if is_instance_valid(_drone_refs.get("out_lbl")): _drone_refs.out_lbl.text = "出力  %d%%" % int(cfg.output)
	if is_instance_valid(_drone_refs.get("slider")) and not is_equal_approx(_drone_refs.slider.value, float(cfg.output)):
		_drone_refs.slider.set_value_no_signal(float(cfg.output))
	if is_instance_valid(_drone_refs.get("summary")):
		var ds: Dictionary = UI.droneStats() if not Game.player.is_empty() else {"damage": 0.0, "rate": 0.0, "dps": 0.0}
		var stt := "稼働中" if cfg.enabled and cfg.output > 0 else "停止中"
		var tg: Array = []
		if cfg.normal: tg.append("通常")
		if cfg.elite: tg.append("エリート")
		if cfg.boss: tg.append("ボス")
		var pr_name := ""
		for pr in PRIORITIES:
			if pr[0] == cfg.priority: pr_name = pr[1]
		_drone_refs.summary.text = "%s / 出力 %d%% / 対象 %s / 優先 %s / 推定DPS %s" % [stt, int(cfg.output), "・".join(tg) if not tg.is_empty() else "なし", pr_name, Kit.num(roundi(float(ds.dps) * float(cfg.output) / 100.0))]

# ------------------------------------------------------------------ tab: input
func _page_input() -> Control:
	var pg := _page()
	var l: VBoxContainer = pg[1]
	l.add_child(_section("キー配置"))
	var cur: String = str(Inp.inputPreferences.get("scheme", "menus"))
	_layout_seg = Kit.segmented(["Q / E：カード・スキル画面", "Q / E / R：スキル発動"], 0 if cur == "menus" else 1,
		func(i): Inp.setKeyLayout("menus" if i == 0 else "abilities"))
	l.add_child(_layout_seg)
	l.add_child(Kit.label("標準：発動は数字1・2・3。 / 切替後：C カード・V スキル獲得・強化・Q/E/R で発動。", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	l.add_child(_section("入力方式"))
	var devs := ["auto", "keyboard", "touch"]
	_device_seg = Kit.segmented(["自動切替", "キーボード・マウス固定", "タッチ固定"], maxi(0, devs.find(str(Inp.inputPreferences.get("device", "auto")))),
		func(i): Inp.setInputDevice(devs[i]))
	l.add_child(_device_seg)
	l.add_child(Kit.label("設定はこの端末に保存", Kit.FS_XS, Kit.MUTE))
	_key_summary = Kit.label("", Kit.FS_SM, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.add_child(_key_summary)
	l.add_child(Kit.hsep())
	var hold := Kit.toggle(bool(Game.playPreferences.get("holdSkills", true)), func(v):
		Game.playPreferences.holdSkills = v; Game.savePlayPreferences())
	l.add_child(Kit.setting_row("スキル長押しで連続使用", hold, "押している間、CD終了ごとに再使用。タップ／短押しは1回。開始済みのチャージは離しても発射されます。"))
	l.add_child(Kit.hsep())
	var row := Kit.hbox(Kit.S2)
	var a := Kit.button("音声設定", "ghost", func(): UI.hook("openUtility", ["audio"]))
	var d := Kit.button("開発者パネル [F8]", "ghost", func(): UI.hook("openUtility", ["developer"]))
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(a); row.add_child(d)
	l.add_child(row)
	_refresh_input()
	return pg[0]

func _refresh_input() -> void:
	if _key_summary == null or not is_instance_valid(_key_summary): return
	var k: Dictionary = Inp.currentKeys()
	var sk: Array = []
	for c in k.skills: sk.append(Inp.keyLabel(str(c)))
	_key_summary.text = "%s：カード / %s：スキル獲得・強化 / %s：発動 / Space：ダッシュ / Esc：戻る・一時停止" % [Inp.keyLabel(str(k.cards)), Inp.keyLabel(str(k.rewards)), "・".join(sk)]
	if is_instance_valid(_layout_seg):
		_layout_seg.index = 0 if str(Inp.inputPreferences.get("scheme", "menus")) == "menus" else 1
		_layout_seg._refresh()

# ------------------------------------------------------------------ tab: suspend save
func _page_suspend() -> Control:
	var pg := _page()
	var l: VBoxContainer = pg[1]
	l.add_child(_section("中断セーブ", Kit.AMBER))
	_suspend_label = Kit.label(_suspend_msg, Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.add_child(_suspend_label)
	var b1 := Kit.button("中断保存してホーム", "primary", _on_suspend)
	var b2 := Kit.button("中断をファイルに保存", "ghost", _on_export)
	l.add_child(b1)
	l.add_child(b2)
	l.add_child(Kit.label("通常の恒久セーブとは別の1枠です。最後の中断地点は集計・破棄まで保持します。新しい進行を残す場合は保存し直してください。", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	return pg[0]

func _set_suspend_msg(m: String) -> void:
	_suspend_msg = m
	if _suspend_label != null and is_instance_valid(_suspend_label): _suspend_label.text = m

## 原作 suspendRunToHome (10474). The run-graph serializer (makeRunSave/validateRunSave/persistRunSave) is
## not in the Godot port; call Game.suspendRunToHome() if some module provides it.
func _on_suspend() -> void:
	if Game.has_method("suspendRunToHome"):
		Game.call("suspendRunToHome", false)
		return
	_set_suspend_msg("中断保存はまだこのビルドで利用できません。ランは保持しています。「ここで集計して終了」を使用してください。")
	_tab = 3
	_set_tab(3)
	UI.toast("中断セーブ未対応（ランは保持）", "warn")

func _on_export() -> void:
	if Game.has_method("downloadRunSave"):
		Game.call("downloadRunSave")
		return
	_set_suspend_msg("中断ファイルの書き出しはまだ利用できません。ランは保持しています。")
	UI.toast("中断ファイル書き出し未対応", "warn")
