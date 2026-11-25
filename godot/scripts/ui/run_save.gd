class_name RunSave
extends RefCounted
## Suspended-run (中断セーブ) logic. Port of original index.html 10360-10512
## (encodeRunGraph / decodeRunGraph / startRunSession / makeRunSave / validateRunSave /
##  readSuspended / clearSuspended / persistRunSave / suspendRunToHome / downloadRunSave / restoreSuspended).
## Used by screen_home (CONTINUE panel) and available to the pause screen:
##   RunSave.suspend_to_home(force) -> {ok, confirm, msg}      (pause "中断保存してホーム")
##   RunSave.export_file()          -> {ok, path, msg}          (pause "中断をファイルに保存")
## Hooks routed here by screen_home: startRunSession / clearRunSession / markSessionSettled /
## sessionAlreadySettled / syncResumeEntry.

const RUN_SAVE_KEY := "nf_suspended_run_v1"
const RUN_LEDGER_KEY := "nf_settled_run_ids_v1"
const RUN_FILE_APP := "NEON_FRACTURE_RUN"

static var sessionId: String = ""
static var memory: Variant = null       # cached payload (Dictionary) or null
static var save_confirm: bool = false

# ---------------------------------------------------------------- graph codec
## Graph: every Dictionary/Array becomes a node; values become primitives or {"$r": id}.
## Shared Dictionary references (enemy <-> bullet source, drones...) are preserved via a temporary "__sid" tag.
static func encode_graph(root: Variant) -> Dictionary:
	var ctx := {"nodes": [], "tagged": [], "err": "", "depth": 0}
	var r: Variant = _enc(root, ctx)
	for d in ctx.tagged:
		(d as Dictionary).erase("__sid")
	if ctx.err != "":
		return {"error": ctx.err}
	return {"root": r, "nodes": ctx.nodes}

static func _enc(v: Variant, ctx: Dictionary) -> Variant:
	if ctx.err != "": return null
	match typeof(v):
		TYPE_NIL: return null
		TYPE_BOOL, TYPE_INT, TYPE_STRING: return v
		TYPE_STRING_NAME: return String(v)
		TYPE_FLOAT:
			if is_nan(v) or is_inf(v):
				ctx.err = "保存できない数値が含まれます"
				return 0.0
			return v
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_OBJECT, TYPE_RID:
			return null
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.has("__sid"):
				return {"$r": d["__sid"]}
			if ctx.nodes.size() >= 120000:
				ctx.err = "中断データが大きすぎます"
				return null
			if ctx.depth > 160:
				ctx.err = "中断データの階層が深すぎます"
				return null
			var id: int = ctx.nodes.size()
			d["__sid"] = id
			ctx.tagged.append(d)
			var node := {"t": "d", "data": []}
			ctx.nodes.append(node)
			ctx.depth += 1
			for k in d.keys():
				if typeof(k) == TYPE_STRING and k == "__sid": continue
				var ev: Variant = _enc(d[k], ctx)
				node.data.append([_enc(k, ctx), ev])
			ctx.depth -= 1
			return {"$r": id}
		TYPE_ARRAY:
			if ctx.nodes.size() >= 120000:
				ctx.err = "中断データが大きすぎます"
				return null
			if ctx.depth > 160:
				ctx.err = "中断データの階層が深すぎます"
				return null
			var aid: int = ctx.nodes.size()
			var anode := {"t": "a", "data": []}
			ctx.nodes.append(anode)
			ctx.depth += 1
			for item in (v as Array):
				anode.data.append(_enc(item, ctx))
			ctx.depth -= 1
			return {"$r": aid}
		_:
			return v   # Vector2, Color, ... (Marshalls handles them)

static func decode_graph(g: Variant) -> Dictionary:
	if not (g is Dictionary) or not (g.get("nodes") is Array) or (g.nodes as Array).size() > 120000:
		return {"error": "中断データの形式が不正です"}
	var nodes: Array = g.nodes
	var objs: Array = []
	for n in nodes:
		if not (n is Dictionary) or not (n.get("data") is Array):
			return {"error": "中断データの要素が不正です"}
		if n.t == "a": objs.append([])
		elif n.t == "d": objs.append({})
		else: return {"error": "未対応の中断データです"}
	for i in nodes.size():
		var n2: Dictionary = nodes[i]
		var o: Variant = objs[i]
		for item in n2.data:
			if n2.t == "a":
				(o as Array).append(_dec(item, objs))
			else:
				if not (item is Array) or item.size() != 2:
					return {"error": "中断データのペアが不正です"}
				var key: Variant = item[0]
				if typeof(key) == TYPE_STRING and key in ["__proto__", "constructor", "prototype"]:
					return {"error": "禁止されたデータ項目です"}
				(o as Dictionary)[key] = _dec(item[1], objs)
	return {"root": _dec(g.get("root"), objs)}

static func _dec(v: Variant, objs: Array) -> Variant:
	if v is Dictionary and (v as Dictionary).has("$r"):
		var idx: int = int(v["$r"])
		if idx >= 0 and idx < objs.size(): return objs[idx]
		return null
	return v

# ---------------------------------------------------------------- ledger / session
static func new_run_id() -> String:
	return "run_%d_%08x" % [int(Time.get_unix_time_from_system() * 1000.0), randi()]

static func settled_ids() -> Array:
	var raw: Variant = Meta.storage_get(RUN_LEDGER_KEY)
	if raw == null or str(raw) == "": return []
	var p: Variant = JSON.parse_string(str(raw))
	return p if p is Array else []

static func is_settled(id: String) -> bool:
	return settled_ids().has(id)

## hook sessionAlreadySettled
static func session_already_settled() -> bool:
	return sessionId != "" and is_settled(sessionId)

## hook markSessionSettled
static func mark_session_settled() -> void:
	if sessionId == "": return
	var ids := settled_ids()
	if not ids.has(sessionId): ids.append(sessionId)
	if ids.size() > 2000: ids = ids.slice(ids.size() - 2000)
	Meta.storage_set(RUN_LEDGER_KEY, JSON.stringify(ids))
	var saved: Dictionary = read()
	if str(saved.get("runId", "")) == sessionId:
		clear()

## hook startRunSession (also snapshots the equipped cards into Cards.runLoadoutCards)
static func start_session() -> void:
	sessionId = new_run_id()
	var out: Array = []
	var m: Dictionary = Meta.meta
	for id in m.get("equippedCards", []):
		for c in m.get("cards", []):
			if c.id == id and Cards.validCardRecipe(c):
				out.append(Cards.normalizeCard(c.duplicate(true)))
				break
	Cards.runLoadoutCards = out
	save_confirm = false

## hook clearRunSession
static func clear_session() -> void:
	sessionId = ""
	Cards.runLoadoutCards = []

# ---------------------------------------------------------------- slot storage
## Returns the suspended payload or {} when none.
static func read() -> Dictionary:
	if memory is Dictionary: return memory
	var raw: Variant = Meta.storage_get(RUN_SAVE_KEY)
	if raw != null and str(raw) != "":
		var p: Variant = JSON.parse_string(str(raw))
		if p is Dictionary and p.get("app") == RUN_FILE_APP and int(p.get("formatVersion", 0)) == 1:
			memory = p
			return p
	return {}

static func has_save() -> bool:
	return not read().is_empty()

static func clear() -> void:
	memory = null
	Meta.storage_remove(RUN_SAVE_KEY)
	UI.hook("syncResumeEntry")

## Returns "" on success, else an error message.
static func persist(payload: Dictionary) -> String:
	var text := JSON.stringify(payload)
	if text.length() > 8000000: return "保存データが大きすぎます。ファイル書き出しを試してください"
	if not Meta.storage_set(RUN_SAVE_KEY, text): return "保存結果を確認できません"
	memory = payload
	UI.hook("syncResumeEntry")
	return ""

static func summary_text(p: Dictionary) -> String:
	if p.is_empty(): return "中断セーブなし · 一時停止から保存できます"
	var s: Dictionary = p.get("summary", {})
	var sec: float = float(s.get("seconds", 0))
	return "中断中 · Wave %s / Lv.%s / %d分%d秒 / %s" % [str(int(s.get("wave", 0))), str(int(s.get("level", 1))),
		int(sec / 60.0), int(fmod(sec, 60.0)), "実験ラン" if s.get("developer", false) else str(s.get("difficulty", ""))]

# ---------------------------------------------------------------- make
static func _choice_desc(c: Variant) -> Variant:
	if c == null or not (c is Dictionary): return null
	return {"id": c.get("id"), "rarity": c.get("rarity"), "rank": c.get("rank")}

static func make_save() -> Dictionary:
	var G = Game
	if G.runSettled or sessionId == "" or not ["paused", "upgrade", "ability"].has(G.state) or float(G.player.get("hp", 0)) <= 0:
		return {"error": "生存中のランを一時停止して保存してください"}
	var choices: Variant = null
	if G.currentCardChoices is Array:
		choices = []
		for c in G.currentCardChoices: choices.append(_choice_desc(c))
	var snap := {
		"player": G.player, "time": G.time, "score": G.score, "kills": G.kills, "wave": G.wave,
		"spawnTimer": G.spawnTimer, "waveTimer": G.waveTimer, "bossAlive": G.bossAlive, "bossWarningTimer": G.bossWarningTimer,
		"pendingLevelUps": G.pendingLevelUps, "combo": G.combo, "comboKills": G.comboKills, "comboTimer": G.comboTimer,
		"bossesDefeated": G.bossesDefeated, "maxComboRun": G.maxComboRun, "maxHitDamageRun": G.maxHitDamageRun,
		"runEndReason": G.runEndReason, "clearPending": G.clearPending, "enemySerial": G.enemySerial, "bossSpawnSerial": G.bossSpawnSerial,
		"bossPopulationTimer": Enemies.bossPopulationTimer, "finalBossEncounterStarted": Enemies.finalBossEncounterStarted,
		"enemies": G.enemies, "bullets": G.bullets, "gems": G.gems, "drones": G.drones, "hazards": G.hazards,
		"friendlyEffects": G.friendlyEffects, "fieldZones": G.fieldZones, "activeSlots": G.activeSlots,
		"abilityRewards": G.abilityRewards, "selectedAbilityId": G.selectedAbilityId, "currentChoices": choices,
		"autoCardClock": G.autoCardClock, "autoHistory": G.autoHistory, "cardCooldowns": G.cardCooldowns,
		"runDamageTotals": G.runDamageTotals, "runConfig": Meta.runConfig, "runGrowth": Meta.runGrowth,
		"runLoadoutCards": Cards.runLoadoutCards, "developerRun": Meta.developerRun, "droneConfig": UI.droneConfig,
		"camera": {"x": World.camera.x, "y": World.camera.y}, "aim": {"x": Inp.mouse.x, "y": Inp.mouse.y},
		"autoCards": bool(G.playPreferences.get("autoCards", false)),
	}
	var graph := encode_graph(snap)
	if graph.has("error"): return {"error": graph.error}
	var ch: Dictionary = Meta.challenge()
	return {"app": RUN_FILE_APP, "formatVersion": 1, "gameVersion": Meta.GAME_VERSION, "runId": sessionId,
		"savedAt": Time.get_datetime_string_from_system(true) + "Z",
		"summary": {"wave": G.wave, "level": G.player.level, "score": floori(G.score), "seconds": G.time,
			"mode": Meta.runConfig.mode, "difficulty": str(ch.get("label", "")), "developer": bool(Meta.developerRun.active)},
		"graph": Marshalls.variant_to_base64(graph, false)}

# ---------------------------------------------------------------- validate
static func _fin(x: Variant) -> bool:
	return (x is float or x is int) and not (x is float and (is_nan(x) or is_inf(x)))

## Returns {"error": msg} or {"state": Dictionary}.
static func validate(payload: Variant) -> Dictionary:
	if not (payload is Dictionary) or payload.get("app") != RUN_FILE_APP or int(payload.get("formatVersion", 0)) != 1 \
			or not (payload.get("runId") is String) or str(payload.runId).length() > 128:
		return {"error": "このゲームの中断セーブではありません"}
	if is_settled(str(payload.runId)):
		return {"error": "このランは既に集計済みです。報酬を二重に取得することはできません"}
	if not (payload.get("graph") is String):
		return {"error": "中断データの形式が不正です"}
	var gv: Variant = Marshalls.base64_to_variant(str(payload.graph), false)
	var dec := decode_graph(gv)
	if dec.has("error"): return dec
	var s: Variant = dec.get("root")
	if not (s is Dictionary): return {"error": "中断データの形式が不正です"}
	var p: Variant = s.get("player")
	if not (p is Dictionary) or not _fin(p.get("hp")) or p.hp <= 0 or not _fin(p.get("maxHp")) or p.hp > p.maxHp \
			or not _fin(p.get("damage")) or p.damage <= 0:
		return {"error": "プレイヤーの保存データが不正です"}
	for k in ["x", "y", "speed", "fireRate", "bulletSpeed", "level", "xp", "nextXp", "droneCount"]:
		if not _fin(p.get(k)) or p[k] < 0: return {"error": "プレイヤーの数値が不正です"}
	if p.level < 1 or p.nextXp <= 0 or p.fireRate <= 0 or p.bulletSpeed <= 0 or p.x > World.W or p.y > World.H:
		return {"error": "プレイヤーの値が範囲外です"}
	for k in ["time", "score", "kills", "wave", "pendingLevelUps", "bossesDefeated", "enemySerial"]:
		if not _fin(s.get(k)) or s[k] < 0: return {"error": "進行データが不正です"}
	for k in ["enemies", "bullets", "gems", "drones", "hazards", "friendlyEffects", "fieldZones", "activeSlots", "abilityRewards", "runLoadoutCards", "autoHistory"]:
		if not (s.get(k) is Array): return {"error": "保存された一覧が不正です: " + k}
	if s.enemies.size() > 2000 or s.bullets.size() > 20000 or s.activeSlots.size() != 3:
		return {"error": "保存された件数が不正です"}
	var ids := {}
	for e in s.enemies:
		if not (e is Dictionary) or not _fin(e.get("id")) or ids.has(e.id) or not _fin(e.get("x")) or not _fin(e.get("y")) \
				or not _fin(e.get("hp")) or not _fin(e.get("r")):
			return {"error": "敵の保存データが不正です"}
		ids[e.id] = true
	for b in s.bullets:
		if not (b is Dictionary): return {"error": "弾の保存データが不正です"}
		for k in ["x", "y", "vx", "vy", "r", "life", "damage"]:
			if not _fin(b.get(k)): return {"error": "弾の保存データが不正です"}
	if not (p.get("orbitHitTimes") is Dictionary) or not (p.get("gearOrbitHits") is Dictionary) or not (p.get("skillRanks") is Dictionary) \
			or not (p.get("gearTimers") is Dictionary) or not (p.get("upgradeCounts") is Dictionary):
		return {"error": "強化状態が不正です"}
	for slot in s.activeSlots:
		if slot != null and (not (slot is Dictionary) or not Combat.ACTIVE_DEFS.has(slot.get("id")) or not _fin(slot.get("level")) \
				or slot.level < 1 or not _fin(slot.get("remaining"))):
			return {"error": "スキルが不正です"}
	for a in s.abilityRewards:
		if not (a is Dictionary) or not (a.get("offers") is Array):
			return {"error": "スキル報酬が不正です"}
		for oid in a.offers:
			if not Combat.ACTIVE_DEFS.has(oid): return {"error": "スキル報酬が不正です"}
	if s.get("currentChoices") != null:
		if not (s.currentChoices is Array) or s.currentChoices.size() != 3: return {"error": "カード候補が不正です"}
		for c in s.currentChoices:
			if not (c is Dictionary) or not _choice_known(c): return {"error": "未対応のカード候補です"}
	for c in s.runLoadoutCards:
		if not Cards.validCardRecipe(c): return {"error": "装備カードが不正です"}
	var base: Dictionary = Game.playerBase()
	for k in base:
		if (base[k] is float or base[k] is int) and not _fin(p.get(k)):
			return {"error": "プレイヤーの項目が不足しています: " + str(k)}
	var cam: Variant = s.get("camera")
	var aim: Variant = s.get("aim")
	if not (cam is Dictionary) or not _fin(cam.get("x")) or not _fin(cam.get("y")) or not (aim is Dictionary) or not _fin(aim.get("x")) or not _fin(aim.get("y")):
		return {"error": "カメラ・照準が不正です"}
	if not (s.get("runConfig") is Dictionary) or not (s.get("runGrowth") is Dictionary) or not (s.get("runDamageTotals") is Dictionary) \
			or not (s.get("cardCooldowns") is Dictionary) or not (s.get("developerRun") is Dictionary):
		return {"error": "保存の構成が不足しています"}
	s["droneConfig"] = UI.cleanDroneConfig(s.get("droneConfig"))
	s["runConfig"] = Meta.cleanRunConfig(s.runConfig)
	return {"state": s}

static func _choice_known(c: Dictionary) -> bool:
	var id: Variant = c.get("id")
	for sk in Cards.skills:
		if sk.id == id: return sk.tiers.has(c.get("rarity"))
	for u in Cards.uniqueEpics:
		if u.id == id: return true
	for l in Cards.legendarySkills:
		if l.id == id: return true
	return ["end_damage", "end_rate", "end_active", "end_hp", "end_beam", "end_drone", "end_fleet"].has(id)

static func restore_choice(c: Dictionary) -> Variant:
	var id: Variant = c.get("id")
	for sk in Cards.skills:
		if sk.id == id: return Cards.buildSkillChoice(sk, c.get("rarity"))
	for u in Cards.uniqueEpics:
		if u.id == id: return Cards._unique_choice(u)
	for l in Cards.legendarySkills:
		if l.id == id:
			return {"id": l.id, "icon": l.icon, "name": l.name, "rarity": "LEGENDARY", "desc": l.desc, "apply": Cards._apply_legend.bind(l.id)}
	for e in Cards.endlessChoices():
		if e.id == id: return e
	return null

# ---------------------------------------------------------------- suspend / export / import / restore
## Pause screen "中断保存してホーム". Returns {ok, confirm, msg}.
static func suspend_to_home(force: bool = false) -> Dictionary:
	if Game.state != "paused": return {"ok": false, "confirm": false, "msg": "一時停止中のみ保存できます"}
	var old := read()
	if not old.is_empty() and str(old.get("runId", "")) != sessionId and not force:
		save_confirm = true
		return {"ok": false, "confirm": true, "msg": "別の中断ランがあります。もう一度「中断保存してホーム」を押すと上書きします。"}
	var data := make_save()
	if data.has("error"):
		return {"ok": false, "confirm": false, "msg": "保存できませんでした。ランは保持しています。「中断をファイルに保存」を使用してください。 " + str(data.error)}
	var v := validate(data)
	if v.has("error"):
		return {"ok": false, "confirm": false, "msg": "保存できませんでした。ランは保持しています。「中断をファイルに保存」を使用してください。 " + str(v.error)}
	var err := persist(data)
	if err != "":
		return {"ok": false, "confirm": false, "msg": "保存できませんでした。ランは保持しています。「中断をファイルに保存」を使用してください。 " + err}
	Game.returnHome()
	Inp.showInputNotice("中断セーブを保存しました。「続きから」で再開できます", 4000)
	return {"ok": true, "confirm": false, "msg": ""}

## Pause screen "中断をファイルに保存" (writes a JSON file; Downloads dir when available, else user://).
static func export_file() -> Dictionary:
	var data := make_save()
	if data.has("error"): return {"ok": false, "path": "", "msg": str(data.error)}
	var fname := "neon-fracture-run-wave%d-%d.json" % [Game.wave, int(Time.get_unix_time_from_system() * 1000.0)]
	var dirs: Array = [OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), ProjectSettings.globalize_path("user://")]
	for d in dirs:
		if str(d) == "": continue
		var path := str(d).path_join(fname)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null: continue
		f.store_string(JSON.stringify(data))
		f.close()
		return {"ok": true, "path": path, "msg": "中断JSONを保存しました: " + path}
	return {"ok": false, "path": "", "msg": "ファイルを書き出せませんでした"}

## Reads + validates a run file. Returns {"payload": Dictionary} or {"error": msg}.
static func read_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {"error": "ファイルを開けません"}
	if f.get_length() > 8000000: return {"error": "8MB以下の中断JSONを選んでください"}
	var p: Variant = JSON.parse_string(f.get_as_text())
	if not (p is Dictionary): return {"error": "JSONを解釈できません"}
	var v := validate(p)
	if v.has("error"): return v
	return {"payload": p}

## Returns "" on success or an error message. Only valid in menu / config state.
static func restore(payload: Variant = null) -> String:
	if not ["menu", "config"].has(Game.state): return "メニューからのみ再開できます"
	var pl: Dictionary = payload if payload is Dictionary else read()
	if pl.is_empty(): return "中断セーブがありません"
	var v := validate(pl)
	if v.has("error"): return str(v.error)
	var s: Dictionary = v.state
	var G = Game
	Inp.clearPhysicalMovement()
	G.cancelCombatInput()
	G.resetRunSystems()
	G.player = s.player
	G.time = s.time; G.score = s.score; G.kills = int(s.kills); G.wave = int(s.wave)
	G.spawnTimer = s.spawnTimer; G.waveTimer = s.waveTimer
	G.bossAlive = s.bossAlive; G.bossWarningTimer = s.bossWarningTimer
	G.pendingLevelUps = int(s.pendingLevelUps)
	G.combo = s.combo; G.comboKills = int(s.comboKills); G.comboTimer = s.comboTimer
	G.bossesDefeated = int(s.bossesDefeated)
	G.maxComboRun = s.maxComboRun; G.maxHitDamageRun = s.maxHitDamageRun
	G.runEndReason = str(s.runEndReason); G.clearPending = bool(s.clearPending)
	G.enemySerial = int(s.enemySerial); G.bossSpawnSerial = int(s.bossSpawnSerial)
	G.bossPopulationTimer = s.bossPopulationTimer; G.finalBossEncounterStarted = bool(s.finalBossEncounterStarted)
	Enemies.bossPopulationTimer = s.bossPopulationTimer; Enemies.finalBossEncounterStarted = bool(s.finalBossEncounterStarted)
	G.enemies = s.enemies; G.bullets = s.bullets; G.gems = s.gems; G.drones = s.drones
	G.hazards = s.hazards; G.friendlyEffects = s.friendlyEffects; G.fieldZones = s.fieldZones
	G.activeSlots = s.activeSlots; G.abilityRewards = s.abilityRewards; G.selectedAbilityId = s.selectedAbilityId
	G.autoCardClock = s.autoCardClock; G.autoHistory = s.autoHistory; G.cardCooldowns = s.cardCooldowns
	G.runDamageTotals = s.runDamageTotals
	Meta.runConfig = s.runConfig; Meta.runGrowth = s.runGrowth
	Cards.runLoadoutCards = s.runLoadoutCards
	var dev: Dictionary = Meta.freshDeveloperRun()
	for k in s.developerRun: dev[k] = s.developerRun[k]
	Meta.developerRun = dev
	UI.droneConfig = s.droneConfig
	sessionId = str(pl.runId)
	G.runStartedAt = U.now_ms() - float(G.time) * 1000.0
	G.runSettled = false
	G.currentCardChoices = null
	if s.get("currentChoices") is Array:
		var rc: Array = []
		for c in s.currentChoices:
			var ch: Variant = restore_choice(c)
			if ch == null:
				return "この版では復元できないカードです: " + str(c.get("id"))
			rc.append(ch)
		G.currentCardChoices = rc
	G.playPreferences["autoCards"] = bool(s.get("autoCards", false))
	World.camera.x = s.camera.x; World.camera.y = s.camera.y
	World.clampCamera()
	Inp.mouse.x = s.aim.x; Inp.mouse.y = s.aim.y
	G.particles = []; G.rings = []; G.texts = []
	G.screenShake = 0.0; G.flash = 0.0; G.uiTimer = 0.0; G.simAccumulator = 0.0
	UI.hook("resetGameUI", [Inp.touchCapable])
	G.state = "playing"
	G.setPause(true)
	UI.hook("syncDroneControls")
	G.updateUI()
	G.last = U.now_ms()
	G.sceneDirty = true
	G.lastRenderedState = ""
	UI.hook("syncResumeEntry")
	return ""
