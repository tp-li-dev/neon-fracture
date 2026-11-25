extends RefCounted
## RunSave — suspend/resume run save. Port of index.html 10360-10544 (encodeRunGraph .. initRunFeatures).
## Static functions only; Game (game.gd) exposes thin same-named delegates at the end of that file.
## NOTE: intentionally has no `class_name` (scripts/ui/run_save.gd already declares class_name RunSave).
## Reach it via `Game.<name>()` or `preload("res://scripts/runsave.gd")`.
##
## JSON format is identical to the original: {app, formatVersion:1, gameVersion, runId, savedAt, summary, graph}
## where graph = {root, nodes:[{type:'object'|'array'|'set'|'map', data}]} and object references are
## {"$ref": nodeId} (undefined -> {"$undefined":1}). Port-side Sets/Maps are Dictionaries (id -> true / id -> value);
## they are emitted as 'set'/'map' nodes for the known field names below so HTML saves and Godot saves interchange.

const RUN_SAVE_KEY := "nf_suspended_run_v1"
const RUN_LEDGER_KEY := "nf_settled_run_ids_v1"
const RUN_FILE_APP := "NEON_FRACTURE_RUN"
const SID := "__sid"

## Dictionary fields that are JS Set / Map in the original.
const SET_FIELDS := ["hitIds"]
const MAP_FIELDS := ["orbitHitTimes", "gearOrbitHits", "hitTimes"]
## Fields the port keeps as int (JSON numbers parse as float).
const INT_FIELDS := ["id", "level", "rank"]

static var sessionId: String = ""
static var suspendedMemory: Variant = null
static var runSaveConfirm: bool = false
static var lastMessage: String = ""
static var _decErr: String = ""


# ---------------------------------------------------------------- graph codec
static func _skip(v: Variant) -> bool:
	var t: int = typeof(v)
	return t == TYPE_CALLABLE or t == TYPE_SIGNAL or t == TYPE_OBJECT or t == TYPE_RID

## Returns {"root": ..., "nodes": [...]} or {"error": msg}. Iterative (no recursion depth limit).
static func encodeRunGraph(root: Variant) -> Dictionary:
	var ctx := {"nodes": [], "queue": [], "tagged": [], "err": ""}
	var r: Variant = _enc(root, ctx, "")
	var qi: int = 0
	while qi < ctx.queue.size() and ctx.err == "":
		var item: Array = ctx.queue[qi]
		qi += 1
		var node: Dictionary = ctx.nodes[item[0]]
		var v: Variant = item[1]
		var data: Array = node.data
		match node.type:
			"array":
				for x in (v as Array):
					data.append(null if _skip(x) else _enc(x, ctx, ""))
			"set":
				for k in (v as Dictionary).keys():
					if typeof(k) == TYPE_STRING and k == SID: continue
					data.append(_enc(k, ctx, ""))
			"map":
				for k in (v as Dictionary).keys():
					if typeof(k) == TYPE_STRING and k == SID: continue
					var mv: Variant = v[k]
					data.append([_enc(k, ctx, ""), null if _skip(mv) else _enc(mv, ctx, "")])
			_:
				for k in (v as Dictionary).keys():
					var ks: String = str(k)
					if ks == SID or ks == "__proto__" or ks == "prototype" or ks == "constructor": continue
					var ov: Variant = v[k]
					if _skip(ov): continue
					var hint: String = ""
					if ov is Dictionary:
						if SET_FIELDS.has(ks): hint = "set"
						elif MAP_FIELDS.has(ks): hint = "map"
					data.append([ks, _enc(ov, ctx, hint)])
	for d in ctx.tagged:
		(d as Dictionary).erase(SID)
	if ctx.err != "":
		return {"error": ctx.err}
	return {"root": r, "nodes": ctx.nodes}

static func _enc(v: Variant, ctx: Dictionary, hint: String) -> Variant:
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
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.has(SID): return {"$ref": d[SID]}
			if ctx.nodes.size() >= 120000:
				ctx.err = "中断データが大きすぎます"
				return null
			var id: int = ctx.nodes.size()
			d[SID] = id
			ctx.tagged.append(d)
			var t: String = hint if hint != "" else "object"
			ctx.nodes.append({"type": t, "data": []})
			ctx.queue.append([id, d])
			return {"$ref": id}
		TYPE_ARRAY:
			if ctx.nodes.size() >= 120000:
				ctx.err = "中断データが大きすぎます"
				return null
			var aid: int = ctx.nodes.size()
			ctx.nodes.append({"type": "array", "data": []})
			ctx.queue.append([aid, v])
			return {"$ref": aid}
		_:
			ctx.err = "保存できない実行状態が含まれます"
			return null

## Returns {"root": Variant} or {"error": msg}.
static func decodeRunGraph(graph: Variant) -> Dictionary:
	if not (graph is Dictionary) or not (graph.get("nodes") is Array) or (graph.nodes as Array).size() > 120000:
		return {"error": "中断データの形式が不正です"}
	var nodes: Array = graph.nodes
	var objs: Array = []
	for n in nodes:
		if not (n is Dictionary) or not (n.get("data") is Array):
			return {"error": "中断データの要素が不正です"}
		match n.get("type"):
			"array": objs.append([])
			"set", "map", "object": objs.append({})
			_: return {"error": "未対応の中断データです"}
	_decErr = ""
	for i in nodes.size():
		var n2: Dictionary = nodes[i]
		var o: Variant = objs[i]
		var t: String = n2.type
		for item in n2.data:
			if t == "array":
				(o as Array).append(_dec(item, objs))
			elif t == "set":
				(o as Dictionary)[_key(_dec(item, objs))] = true
			else:
				if not (item is Array) or item.size() != 2:
					return {"error": "中断データのペアが不正です"}
				if t == "map":
					(o as Dictionary)[_key(_dec(item[0], objs))] = _dec(item[1], objs)
				else:
					var k: Variant = item[0]
					if typeof(k) != TYPE_STRING or k in ["__proto__", "constructor", "prototype", SID]:
						return {"error": "禁止されたデータ項目です"}
					var dv: Variant = _dec(item[1], objs)
					if INT_FIELDS.has(k) and typeof(dv) == TYPE_FLOAT and dv == floorf(dv) and absf(dv) < 1e15:
						dv = int(dv)
					(o as Dictionary)[k] = dv
		if _decErr != "": return {"error": _decErr}
	var root: Variant = _dec(graph.get("root"), objs)
	if _decErr != "": return {"error": _decErr}
	return {"root": root}

static func _key(k: Variant) -> Variant:
	if typeof(k) == TYPE_FLOAT and k == floorf(k) and absf(k) < 1e15: return int(k)
	return k

static func _dec(v: Variant, objs: Array) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING, TYPE_INT, TYPE_FLOAT:
			return v
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.size() == 1:
				if d.has("$undefined") and int(d["$undefined"]) == 1: return null
				if d.has("$ref") and (d["$ref"] is float or d["$ref"] is int):
					var r: float = float(d["$ref"])
					if r == floorf(r) and r >= 0 and int(r) < objs.size(): return objs[int(r)]
	_decErr = "中断データの参照が不正です"
	return null


# ---------------------------------------------------------------- ledger / session
static func newRunId() -> String:
	return "run_%d_%08x%08x" % [int(Time.get_unix_time_from_system() * 1000.0), randi(), randi()]

static func settledRunIds() -> Array:
	var raw: Variant = Meta.storage_get(RUN_LEDGER_KEY)
	if raw == null or str(raw) == "": return []
	var p: Variant = JSON.parse_string(str(raw))
	return p if p is Array else []

static func sessionAlreadySettled() -> bool:
	return sessionId != "" and settledRunIds().has(sessionId)

static func markSessionSettled() -> void:
	if sessionId == "": return
	var ids: Array = settledRunIds()
	if not ids.has(sessionId): ids.append(sessionId)
	if ids.size() > 2000: ids = ids.slice(ids.size() - 2000)
	Meta.storage_set(RUN_LEDGER_KEY, JSON.stringify(ids))
	var saved: Dictionary = readSuspended()
	if str(saved.get("runId", "")) == sessionId:
		clearSuspended()

static func startRunSession() -> void:
	sessionId = newRunId()
	var out: Array = []
	var m: Dictionary = Meta.meta
	for id in m.get("equippedCards", []):
		for c in m.get("cards", []):
			if c.id == id and Cards.validCardRecipe(c):
				out.append(Cards.normalizeCard(c.duplicate(true)))
				break
	Cards.runLoadoutCards = out
	runSaveConfirm = false

## hook clearRunSession (sessionId='' ; runLoadoutCards=[])
static func clearRunSession() -> void:
	sessionId = ""
	Cards.runLoadoutCards = []

static func choiceDescriptor(c: Variant) -> Variant:
	if not (c is Dictionary): return null
	return {"id": c.get("id"), "rarity": c.get("rarity"), "rank": c.get("rank")}

## Returns the rebuilt choice, or null when unsupported.
static func restoreRunChoice(c: Variant) -> Variant:
	if not (c is Dictionary) or typeof(c.get("id")) != TYPE_STRING: return null
	var id: String = c.id
	for sk in Cards.skills:
		if sk.id == id:
			if not sk.tiers.has(c.get("rarity")): return null
			return Cards.buildSkillChoice(sk, c.rarity)
	for u in Cards.uniqueEpics:
		if u.id == id: return Cards._unique_choice(u)
	for l in Cards.legendarySkills:
		if l.id == id:
			return {"id": l.id, "icon": l.icon, "name": l.name, "rarity": "LEGENDARY", "desc": l.desc, "apply": Cards._apply_legend.bind(l.id)}
	for e in Cards.endlessChoices():
		if e.id == id: return e
	return null


# ---------------------------------------------------------------- make
## Returns the save payload Dictionary, or {"error": msg}.
static func makeRunSave() -> Dictionary:
	var G = Game
	if G.runSettled or sessionId == "" or not ["paused", "upgrade", "ability"].has(G.state) or float(G.player.get("hp", 0)) <= 0:
		return {"error": "生存中のランを一時停止して保存してください"}
	var choices: Variant = null
	if G.currentCardChoices is Array:
		choices = []
		for c in G.currentCardChoices: choices.append(choiceDescriptor(c))
	var snap := {
		"player": G.player, "time": G.time, "score": G.score, "kills": G.kills, "wave": G.wave,
		"spawnTimer": G.spawnTimer, "waveTimer": G.waveTimer, "bossAlive": G.bossAlive, "bossWarningTimer": G.bossWarningTimer,
		"pendingLevelUps": G.pendingLevelUps, "combo": G.combo, "comboKills": G.comboKills, "comboTimer": G.comboTimer,
		"bossesDefeated": G.bossesDefeated, "maxComboRun": G.maxComboRun, "maxHitDamageRun": G.maxHitDamageRun,
		"runEndReason": G.runEndReason, "clearPending": G.clearPending, "enemySerial": G.enemySerial,
		"bossSpawnSerial": G.bossSpawnSerial, "bossPopulationTimer": Enemies.bossPopulationTimer,
		"finalBossEncounterStarted": Enemies.finalBossEncounterStarted,
		"enemies": G.enemies, "bullets": G.bullets, "gems": G.gems, "drones": G.drones, "hazards": G.hazards,
		"friendlyEffects": G.friendlyEffects, "fieldZones": G.fieldZones, "activeSlots": G.activeSlots,
		"abilityRewards": G.abilityRewards, "selectedAbilityId": G.selectedAbilityId, "currentChoices": choices,
		"autoCardClock": G.autoCardClock, "autoHistory": G.autoHistory, "cardCooldowns": G.cardCooldowns,
		"runDamageTotals": G.runDamageTotals, "runConfig": Meta.runConfig.duplicate(true), "runGrowth": Meta.runGrowth,
		"runLoadoutCards": Cards.runLoadoutCards, "developerRun": Meta.developerRun, "droneConfig": UI.droneConfig,
		"camera": {"x": World.camera.x, "y": World.camera.y}, "aim": {"x": Inp.mouse.x, "y": Inp.mouse.y},
		"autoCards": bool(G.playPreferences.get("autoCards", false)),
	}
	var graph: Dictionary = encodeRunGraph(snap)
	if graph.has("error"): return {"error": graph.error}
	var ch: Dictionary = Meta.challenge()
	return {"app": RUN_FILE_APP, "formatVersion": 1, "gameVersion": Meta.GAME_VERSION, "runId": sessionId,
		"savedAt": Time.get_datetime_string_from_system(true) + ".000Z",
		"summary": {"wave": G.wave, "level": G.player.level, "score": floori(G.score), "seconds": G.time,
			"mode": Meta.runConfig.mode, "difficulty": str(ch.get("label", "")), "developer": bool(Meta.developerRun.active)},
		"graph": graph}


# ---------------------------------------------------------------- validate
static func _fin(x: Variant) -> bool:
	return (x is float or x is int) and not (x is float and (is_nan(x) or is_inf(x)))

## Returns {"error": msg} or {"state": Dictionary} (decoded run snapshot, droneConfig/runConfig cleaned).
static func validateRunSave(payload: Variant) -> Dictionary:
	if not (payload is Dictionary) or payload.get("app") != RUN_FILE_APP or not _fin(payload.get("formatVersion")) \
			or int(payload.formatVersion) != 1 or not (payload.get("runId") is String) or str(payload.runId).length() > 128:
		return {"error": "このゲームの中断セーブではありません"}
	if settledRunIds().has(payload.runId):
		return {"error": "このランは既に集計済みです。報酬を二重に取得することはできません"}
	var dec: Dictionary = decodeRunGraph(payload.get("graph"))
	if dec.has("error"): return dec
	var s: Variant = dec.get("root")
	if not (s is Dictionary): return {"error": "プレイヤーの保存データが不正です"}
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
		if not b.get("enemy", false) and not (b.get("hitIds") is Dictionary):
			return {"error": "弾の命中履歴が不正です"}
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
	var cc: Variant = s.get("currentChoices")
	if cc != null:
		if not (cc is Array) or cc.size() != 3: return {"error": "カード候補が不正です"}
		for c in cc:
			if not (c is Dictionary): return {"error": "未対応のカード候補です"}
			var known: bool = ["end_damage", "end_rate", "end_active", "end_hp", "end_beam", "end_drone", "end_fleet"].has(c.get("id"))
			for sk in Cards.skills:
				if sk.id == c.get("id"):
					known = true
					if not sk.tiers.has(c.get("rarity")): return {"error": "カードのレアリティが不正です"}
			for u in Cards.uniqueEpics:
				if u.id == c.get("id"): known = true
			for l in Cards.legendarySkills:
				if l.id == c.get("id"): known = true
			if not known: return {"error": "未対応のカード候補です"}
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


# ---------------------------------------------------------------- slot storage
## Suspended payload, or {} when none (original: null).
static func readSuspended() -> Dictionary:
	if suspendedMemory is Dictionary: return suspendedMemory
	var raw: Variant = Meta.storage_get(RUN_SAVE_KEY)
	if raw != null and str(raw) != "":
		var p: Variant = JSON.parse_string(str(raw))
		if p is Dictionary and p.get("app") == RUN_FILE_APP and int(p.get("formatVersion", 0)) == 1:
			suspendedMemory = p
			return p
	return {}

static func clearSuspended() -> void:
	suspendedMemory = null
	Meta.storage_remove(RUN_SAVE_KEY)
	syncResumeEntry()

## Home screen refresh (original DOM updates) -> UI hook.
static func syncResumeEntry() -> void:
	UI.hook("syncResumeEntry")

## Home-screen text for the suspended slot (mirrors the original innerText).
static func resumeInfoText() -> String:
	var p: Dictionary = readSuspended()
	if p.is_empty(): return "中断セーブなし · 一時停止から保存できます"
	var s: Dictionary = p.get("summary", {})
	var sec: float = float(s.get("seconds", 0))
	return "中断中 · Wave %s / Lv.%s / %d分%d秒 / %s" % [str(int(s.get("wave", 0))), str(int(s.get("level", 1))),
		int(sec / 60.0), int(fmod(sec, 60.0)), "実験ラン" if s.get("developer", false) else str(s.get("difficulty", ""))]

## Returns "" on success or an error message.
static func persistRunSave(payload: Dictionary) -> String:
	var text: String = JSON.stringify(payload)
	if text.length() > 8000000: return "保存データが大きすぎます。ファイル書き出しを試してください"
	if not Meta.storage_set(RUN_SAVE_KEY, text): return "保存結果を確認できません"
	suspendedMemory = payload
	syncResumeEntry()
	return ""


# ---------------------------------------------------------------- suspend / export / import / restore
static func _msg(m: String) -> void:
	lastMessage = m
	UI.hook("suspendMessage", [m])

## Pause screen "中断保存してホーム". Returns true when saved and returned home.
static func suspendRunToHome(force: bool = false) -> bool:
	if Game.state != "paused": return false
	var old: Dictionary = readSuspended()
	if not old.is_empty() and str(old.get("runId", "")) != sessionId and not force:
		runSaveConfirm = true
		_msg("別の中断ランがあります。もう一度「中断保存してホーム」を押すと上書きします。")
		return false
	var data: Dictionary = makeRunSave()
	var err: String = str(data.get("error", ""))
	if err == "":
		var v: Dictionary = validateRunSave(_roundtrip(data))
		err = str(v.get("error", ""))
	if err == "":
		err = persistRunSave(data)
	if err != "":
		_msg("保存できませんでした。ランは保持しています。「中断をファイルに保存」を使用してください。 " + err)
		return false
	Game.returnHome()
	Inp.showInputNotice("中断セーブを保存しました。「続きから」で再開できます", 4000)
	return true

## Original validates the in-memory payload; ours goes through JSON text so decoded numbers match what a reload sees.
static func _roundtrip(data: Dictionary) -> Variant:
	return JSON.parse_string(JSON.stringify(data))

## Writes the save JSON to `path`. Returns "" on success or an error message.
static func exportRunSave(path: String) -> String:
	var data: Dictionary = makeRunSave()
	if data.has("error"): return str(data.error)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return "ファイルを書き出せませんでした"
	f.store_string(JSON.stringify(data))
	f.close()
	return ""

## Pause screen "中断をファイルに保存": Downloads / Documents / user:// fallback. Returns the written path or "".
static func downloadRunSave() -> String:
	var fname: String = "neon-fracture-run-wave%d-%d.json" % [Game.wave, int(Time.get_unix_time_from_system() * 1000.0)]
	var dirs: Array = [OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), ProjectSettings.globalize_path("user://")]
	var last_err: String = ""
	for d in dirs:
		if str(d) == "": continue
		var path: String = str(d).path_join(fname)
		last_err = exportRunSave(path)
		if last_err == "":
			_msg("中断JSONを保存しました: " + path + "。ブラウザ内の保存枠とは別です。")
			return path
		if last_err != "ファイルを書き出せませんでした": break
	_msg(last_err)
	return ""

## Reads + validates a run file into Game.pendingRunImport. Returns "" on success or an error message.
static func importRunSave(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return "ファイルを開けません"
	if f.get_length() > 8000000: return "8MB以下の中断JSONを選んでください"
	var p: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (p is Dictionary): return "JSONを解釈できません"
	var v: Dictionary = validateRunSave(p)
	if v.has("error"): return str(v.error)
	Game.pendingRunImport = p
	return ""

## "Apply" step of an import (original applyRunImport). Returns "" on success or an error message.
static func applyRunImport() -> String:
	var p: Variant = Game.pendingRunImport
	if not (p is Dictionary): return "取り込むデータがありません"
	var v: Dictionary = validateRunSave(_roundtrip(p))
	if v.has("error"): return str(v.error)
	var err: String = persistRunSave(p)
	if err != "":
		suspendedMemory = p
		Inp.showInputNotice("ブラウザへ永続保存できません。このタブ内で再開できます。元のJSONを保持してください", 5000)
		syncResumeEntry()
	Game.pendingRunImport = null
	return ""

## Restores the suspended run (paused, ready to resume). Menu/config state only. Returns true on success.
static func restoreSuspended(payload: Variant = null) -> bool:
	if not ["menu", "config"].has(Game.state): return false
	var pl: Variant = payload if payload != null else readSuspended()
	if not (pl is Dictionary) or (pl as Dictionary).is_empty():
		Inp.showInputNotice("再開できません: 中断セーブがありません", 6500)
		return false
	var v: Dictionary = validateRunSave(pl)
	if v.has("error"):
		Inp.showInputNotice("再開できません: " + str(v.error), 6500)
		return false
	var s: Dictionary = v.state
	var rc: Array = []
	if s.get("currentChoices") is Array:
		for c in s.currentChoices:
			var ch: Variant = restoreRunChoice(c)
			if ch == null:
				Inp.showInputNotice("再開できません: この版では復元できないカードです: " + str(c.get("id")), 6500)
				return false
			rc.append(ch)
	var G = Game
	Inp.clearPhysicalMovement()
	G.cancelCombatInput()
	G.resetRunSystems()
	G.player = s.player
	G.time = float(s.time); G.score = float(s.score); G.kills = int(s.kills); G.wave = int(s.wave)
	G.spawnTimer = float(s.spawnTimer); G.waveTimer = float(s.waveTimer)
	G.bossAlive = bool(s.bossAlive); G.bossWarningTimer = float(s.bossWarningTimer)
	G.pendingLevelUps = int(s.pendingLevelUps)
	G.combo = float(s.combo); G.comboKills = int(s.comboKills); G.comboTimer = float(s.comboTimer)
	G.bossesDefeated = int(s.bossesDefeated)
	G.maxComboRun = float(s.maxComboRun); G.maxHitDamageRun = float(s.maxHitDamageRun)
	G.runEndReason = str(s.runEndReason); G.clearPending = bool(s.clearPending)
	G.enemySerial = int(s.enemySerial); G.bossSpawnSerial = int(s.bossSpawnSerial)
	G.bossPopulationTimer = float(s.bossPopulationTimer); G.finalBossEncounterStarted = bool(s.finalBossEncounterStarted)
	Enemies.bossPopulationTimer = float(s.bossPopulationTimer)
	Enemies.finalBossEncounterStarted = bool(s.finalBossEncounterStarted)
	G.enemies = s.enemies; G.bullets = s.bullets; G.gems = s.gems; G.drones = s.drones
	G.hazards = s.hazards; G.friendlyEffects = s.friendlyEffects; G.fieldZones = s.fieldZones
	G.activeSlots = s.activeSlots; G.abilityRewards = s.abilityRewards; G.selectedAbilityId = s.selectedAbilityId
	G.autoCardClock = float(s.autoCardClock); G.autoHistory = s.autoHistory; G.cardCooldowns = s.cardCooldowns
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
	G.currentCardChoices = rc if s.get("currentChoices") is Array else null
	G.playPreferences["autoCards"] = bool(s.get("autoCards", false))
	World.camera.x = float(s.camera.x); World.camera.y = float(s.camera.y)
	World.clampCamera()
	Inp.mouse.x = float(s.aim.x); Inp.mouse.y = float(s.aim.y)
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
	_msg("中断セーブを復元しました。HP・敵・弾・CD・選択候補を保持。「ゲームに戻る」で再開します。")
	syncResumeEntry()
	return true
