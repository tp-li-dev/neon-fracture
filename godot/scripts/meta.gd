extends Node
## Meta — port of index.html lines 6112-7177 (difficulty/run config, research, growth, meta save,
## export/import, player XP, achievements, forge/gacha/loot) + the storage layer (user://).
## Other modules are reached through untyped lookups so this file compiles on its own.

const GAME_VERSION := "v28.10"
const SAVE_EXPORT_VERSION := 1
const SAVE_EXPORT_APP := "NEON_FRACTURE"
const MAX_SAFE := 9007199254740991.0
const CARD_FIELDS := ["trigger", "condition", "chance", "effect", "power"]
const GEAR_SLOTS := ["core", "armor", "drive"]

# ---------------------------------------------------------------- data (defs.json)
var _defs: Dictionary = {}
var DIFFICULTIES: Dictionary = {}
var CUSTOM_ENEMY_IDS: Array = []
var CUSTOM_BOSS_IDS: Array = []
var META_STATS: Dictionary = {}          # key -> {name, icon, base, step}
var MODULES: Array = []                  # data only {id, rarity, icon, name}; apply/desc live in Cards.MODULES
var MODULE_BY_ID: Dictionary = {}
var MODULE_SLOT: Dictionary = {}
var CARD_PARTS: Dictionary = {}          # type -> [part dicts]
var PART_BY_ID: Dictionary = {}          # id -> part dict (with "type")
var STARTER_PARTS: Array = []
var ACHIEVEMENTS: Array = []             # {id,name,desc,reward}; test via achievement_test(id)
var GACHA_TYPES := {
	"beginner": {"name": "BEGINNER", "cost": 60, "desc": "低コスト総合解析。序盤でも気軽に回せる。", "weights": [.52, .20, .28], "rareBonus": 0.0},
	"syntax": {"name": "SYNTAX", "cost": 90, "desc": "構文85%。カード工房の語彙を増やす。", "weights": [.85, .10, .05], "rareBonus": 0.0},
	"card": {"name": "CARD", "cost": 120, "desc": "完成カード70%。重複はDATAへ還元。", "weights": [.20, .70, .10], "rareBonus": .01},
	"gear": {"name": "GEAR", "cost": 120, "desc": "装備75%。重複で装備Lvが上昇。", "weights": [.15, .10, .75], "rareBonus": .01},
	"prism": {"name": "PRISM", "cost": 220, "desc": "高レア補正付き総合解析。終盤の厳選用。", "weights": [.34, .28, .38], "rareBonus": .075}
}

# ---------------------------------------------------------------- state
var developerRun: Dictionary = {}
var runConfig: Dictionary = {}
var runGrowth = null
var growthUIReady := false
var meta: Dictionary = {}
var save: Dictionary = {"high": 0, "wave": 0}
var pendingImportedSave = null
var researchBatch = 1
var selectedGachaType := "beginner"
var metaReturnState := "menu"
var last_error := ""
var storage_persistent := true
var _store_cache: Dictionary = {}

func _ready() -> void:
	_load_defs()
	developerRun = freshDeveloperRun()
	runConfig = loadRunConfig()
	save = {"high": _jsnum(_num_or0(storage_get("nf_high"))), "wave": _jsnum(_num_or0(storage_get("nf_wave")))}
	meta = loadMeta()
	_post_load_meta()

# ---------------------------------------------------------------- helpers
func _game() -> Node: return get_node_or_null("/root/Game")
func _cards() -> Node: return get_node_or_null("/root/Cards")

func _ui_hook(hook_name: String, args: Array = []) -> Variant:
	var ui := get_node_or_null("/root/UI")
	if ui != null and ui.has_method("hook"):
		return ui.hook(hook_name, args)
	return null

func _beep(f: float, d: float, t: String, g: float, s: float) -> void:
	var a := get_node_or_null("/root/Audio")
	if a != null and a.has_method("beep"):
		a.beep(f, d, t, g, s)

func _num(v) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT: return float(v)
		TYPE_NIL: return 0.0
		TYPE_BOOL: return 1.0 if v else 0.0
		TYPE_STRING:
			var s: String = String(v).strip_edges()
			if s == "": return 0.0
			if s.is_valid_float(): return s.to_float()
			return NAN
	return NAN

func _finite(x: float) -> bool: return not is_nan(x) and not is_inf(x)
func _num_or0(v) -> float:
	var n := _num(v)
	return 0.0 if is_nan(n) else n
func _jsnum(f: float) -> Variant:
	if _finite(f) and f == floorf(f) and absf(f) < MAX_SAFE: return int(f)
	return f
func _truthy(v) -> bool:
	match typeof(v):
		TYPE_NIL: return false
		TYPE_BOOL: return v
		TYPE_INT: return v != 0
		TYPE_FLOAT: return v != 0.0 and not is_nan(v)
		TYPE_STRING: return v != ""
	return true
func _floor_i(f: float, lo: float, hi: float) -> int:
	return int(floorf(clampf(f, lo, hi)))
func _is_num(v) -> bool: return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
func _dictv(v) -> Dictionary: return v if typeof(v) == TYPE_DICTIONARY else {}
func _max_values(d, floor_val: float = 0.0) -> float:
	var m := floor_val
	for v in _dictv(d).values(): m = maxf(m, _num_or0(v))
	return m
func _now_unix_ms() -> int: return int(Time.get_unix_time_from_system() * 1000.0)

func _load_defs() -> void:
	var f := FileAccess.open("res://data/defs.json", FileAccess.READ)
	if f == null:
		push_error("Meta: data/defs.json missing")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY: return
	_defs = parsed
	DIFFICULTIES = _defs.get("difficulties", {})
	for k in DIFFICULTIES:   # integral fields are ints in the original usage
		for ik in ["startLevel", "bossInterval"]:
			DIFFICULTIES[k][ik] = int(DIFFICULTIES[k][ik])
	CUSTOM_ENEMY_IDS = _defs.get("custom_enemy_ids", [])
	CUSTOM_BOSS_IDS = _defs.get("custom_boss_ids", [])
	META_STATS = _defs.get("meta_stats", {})
	for k in META_STATS:
		META_STATS[k].base = int(META_STATS[k].base)
		META_STATS[k].step = int(META_STATS[k].step)
	MODULES = _defs.get("modules", [])
	for m in MODULES: MODULE_BY_ID[m.id] = m
	MODULE_SLOT = _defs.get("module_slot", {})
	CARD_PARTS = _defs.get("card_parts", {})
	for t in CARD_PARTS:
		for p in CARD_PARTS[t]:
			p["type"] = t
			p["cost"] = int(p.get("cost", 0))
			PART_BY_ID[p.id] = p
	STARTER_PARTS = _defs.get("starter_parts", [])
	ACHIEVEMENTS = _defs.get("achievements", [])
	for a in ACHIEVEMENTS: a["reward"] = int(a["reward"])

func moduleSlot(id) -> String:
	return String(MODULE_SLOT.get(id, "core"))

func _normalize_card(raw) -> Dictionary:
	var c := _cards()
	if c != null and c.has_method("normalizeCard"):
		return c.normalizeCard(raw)
	var d: Dictionary = (raw as Dictionary).duplicate() if typeof(raw) == TYPE_DICTIONARY else {}
	var cost := 0
	for k in CARD_FIELDS: cost += int(PART_BY_ID.get(d.get(k), {}).get("cost", 0))
	d["cost"] = maxi(0, cost)
	d["rarity"] = "LEGENDARY" if cost >= 12 else "EPIC" if cost >= 8 else "RARE" if cost >= 5 else "COMMON"
	d["id"] = String(d.get("id", d.get("uid", _new_card_id())))
	d["name"] = String(d.get("name", "card")).strip_edges().substr(0, 64)
	d["favorite"] = _truthy(d.get("favorite", false))
	return d

func _new_card_id() -> String:
	return "card_%d_%s" % [_now_unix_ms(), str(randi() % 2147483647)]

func _valid_recipe(c) -> bool:
	if typeof(c) != TYPE_DICTIONARY: return false
	for k in CARD_FIELDS:
		var p = PART_BY_ID.get(c.get(k))
		if p == null or p.type != k: return false
	return true

func _recipe_issue(c) -> String:
	var cd := _cards()
	if cd != null and cd.has_method("recipeIssue"): return String(cd.recipeIssue(c))
	return "" if _valid_recipe(c) else "各欄から構文を1つずつ選択してください。"

func _card_signature(c: Dictionary) -> String:
	var a: Array = []
	for k in CARD_FIELDS: a.append(c[k])
	return JSON.stringify(a)

func _find_duplicate_card(card: Dictionary):
	if not _valid_recipe(card): return null
	var sig := _card_signature(card)
	for c in meta.get("cards", []):
		if _valid_recipe(c) and _card_signature(c) == sig: return c
	return null

# ================================================================ storage layer
func _store_path(key: String) -> String:
	var k := key
	if k.begins_with("nf_"): k = k.substr(3)
	var out := ""
	for ch in k:
		out += ch if (ch.unicode_at(0) < 128 and (ch.is_valid_identifier() or ch == "-" or ch.is_valid_int())) else "_"
	return "user://nf_%s.json" % out

func storage_get(key: String) -> Variant:
	if _store_cache.has(key): return _store_cache[key]
	var p := _store_path(key)
	if not FileAccess.file_exists(p): return null
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null: return null
	var s := f.get_as_text()
	_store_cache[key] = s
	return s

func storage_set(key: String, value: String) -> bool:
	var f := FileAccess.open(_store_path(key), FileAccess.WRITE)
	if f == null: return false
	f.store_string(value)
	f.close()
	_store_cache[key] = value
	return true

func storage_remove(key: String) -> void:
	_store_cache.erase(key)
	var p := _store_path(key)
	if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

# ================================================================ run config / challenge (6112-6171)
func freshDeveloperRun() -> Dictionary:
	return {"active": false, "cp": null, "enemyLevel": null, "enemyHp": 1, "enemyDamage": 1, "god": false, "actions": 0}

func defaultRunConfig() -> Dictionary:
	return {"mode": "endless", "difficulty": "easy", "clearWave": 30, "custom": {
		"density": 1.8, "hpGrowth": 2.0, "damageGrowth": 1.8, "elite": 2.0, "attack": 1.6, "bossInterval": 5,
		"shield": true, "heal": 1.0, "oneHit": false, "startLevel": 1, "levelRate": 2.0, "rosterMode": "auto",
		"enemyTypes": CUSTOM_ENEMY_IDS.duplicate(), "bossTypes": CUSTOM_BOSS_IDS.duplicate(), "bossEnabled": true, "bossLimit": 2}}

func boundedNumber(v, fallback: float, mn: float, mx: float) -> float:
	if v == null:
		return fallback   # JS undefined -> NaN -> fallback
	var n := _num(v)
	return clampf(n, mn, mx) if _finite(n) else fallback

func cleanCustomConfig(raw = null) -> Dictionary:
	var d: Dictionary = defaultRunConfig().custom
	var c: Dictionary = d.duplicate(true)
	if typeof(raw) == TYPE_DICTIONARY:
		for k in raw: c[k] = raw[k]
	var out: Dictionary = c.duplicate(true)
	out.density = boundedNumber(c.density, d.density, .5, 3.5)
	out.hpGrowth = boundedNumber(c.hpGrowth, 2.0, .5, 8.0)
	out.damageGrowth = boundedNumber(c.damageGrowth, 1.8, .5, 8.0)
	out.elite = boundedNumber(c.elite, 2.0, .5, 4.0)
	out.attack = boundedNumber(c.attack, 1.6, .7, 3.0)
	var bi := _num(c.bossInterval)
	out.bossInterval = int(bi) if (bi == 3.0 or bi == 4.0 or bi == 5.0 or bi == 10.0) else 5
	out.startLevel = _floor_i(boundedNumber(c.startLevel, 1.0, 1.0, 10000.0), 1, 10000)
	out.levelRate = boundedNumber(c.levelRate, 2.0, .5, 12.0)
	out.rosterMode = c.rosterMode if c.rosterMode in ["auto", "selected", "bossOnly"] else "auto"
	var et: Array = []
	if typeof(c.enemyTypes) == TYPE_ARRAY:
		for id in CUSTOM_ENEMY_IDS: if id in c.enemyTypes: et.append(id)
	else: et = CUSTOM_ENEMY_IDS.duplicate()
	out.enemyTypes = et
	var bt: Array = []
	if typeof(c.bossTypes) == TYPE_ARRAY:
		for id in CUSTOM_BOSS_IDS: if id in c.bossTypes: bt.append(id)
	else: bt = CUSTOM_BOSS_IDS.duplicate()
	out.bossTypes = bt
	out.bossEnabled = not (typeof(c.bossEnabled) == TYPE_BOOL and c.bossEnabled == false)
	out.bossLimit = roundi(boundedNumber(c.bossLimit, 2.0, 1.0, 3.0))
	out.shield = not (typeof(c.shield) == TYPE_BOOL and c.shield == false)
	out.heal = boundedNumber(c.heal, 1.0, 0.0, 1.0)
	out.oneHit = typeof(c.oneHit) == TYPE_BOOL and c.oneHit == true
	return out

func cleanRunConfig(raw = null) -> Dictionary:
	var r := _dictv(raw)
	var d := defaultRunConfig()
	var diff = r.get("difficulty")
	return {
		"mode": "clear" if r.get("mode") == "clear" else "endless",
		"difficulty": diff if (diff == "custom" or (typeof(diff) == TYPE_STRING and DIFFICULTIES.has(diff))) else d.difficulty,
		"clearWave": _floor_i(boundedNumber(r.get("clearWave"), 30.0, 5.0, 1000.0), 5, 1000),
		"custom": cleanCustomConfig(r.get("custom"))}

func loadRunConfig() -> Dictionary:
	var s = storage_get("nf_run_config")
	if s == null or String(s) == "": return cleanRunConfig({})
	var p = JSON.parse_string(String(s))
	if p == null: return defaultRunConfig()
	return cleanRunConfig(p)

func saveRunConfig() -> void:
	storage_set("nf_run_config", JSON.stringify(runConfig))

func customChallenge(raw = null) -> Dictionary:
	var c := cleanCustomConfig(raw if raw != null else runConfig.custom)
	var cp: float = pow(c.density, .42) * pow(c.hpGrowth, .30) * pow(c.damageGrowth, .28) * pow(c.elite, .13) * pow(c.attack, .20) * pow(5.0 / float(c.bossInterval), .12)
	cp *= pow(c.levelRate / 2.0, .35) * (1.0 + (log(float(c.startLevel)) / log(2.0)) / 16.0)
	if not c.shield: cp *= 1.22
	if c.heal <= .5: cp *= 1.13
	if c.heal <= 0: cp *= 1.13
	if c.oneHit: cp *= 1.72
	if c.rosterMode == "bossOnly": cp *= 1.0 + .12 * c.bossLimit
	elif not c.bossEnabled: cp *= .85
	cp = clampf(cp, .45, 12.0)
	var reward: float = (.72 + .28 * cp) if cp < 1.0 else clampf(1.0 + .72 * (log(cp) / log(2.0)), 1.0, 3.5)
	var out := c.duplicate(true)
	out.label = "CUSTOM / ALL BOSS" if c.rosterMode == "bossOnly" else "CUSTOM"
	out.cp = cp
	out.reward = reward
	out.barrier = c.shield
	return out

func baseChallenge() -> Dictionary:
	if runConfig.difficulty == "custom": return customChallenge()
	return DIFFICULTIES.get(runConfig.difficulty, DIFFICULTIES.get("easy", {}))

func challenge() -> Dictionary:
	var c := baseChallenge()
	if not developerRun.active or developerRun.cp == null: return c
	var cp: float = developerRun.cp
	var out := c.duplicate()
	out.cp = cp
	out.reward = (.72 + .28 * cp) if cp < 1.0 else clampf(1.0 + .72 * (log(cp) / log(2.0)), 1.0, 3.5)
	return out

func challengeReward() -> float:
	return float(challenge().reward) * (1.05 if runConfig.mode == "clear" else 1.0)
func currentWaveSeconds() -> int: return 13
func finalWaveTarget() -> Variant:
	var n := _num(runConfig.clearWave)
	if is_nan(n) or n == 0.0: n = 30.0
	return _jsnum(clampf(n, 5.0, 1000.0))
func isFinalClearWave(w = null) -> bool:
	var wv: float = float(_game().wave) if w == null else float(w)
	return runConfig.mode == "clear" and wv >= float(finalWaveTarget())
func applyModeRestrictions() -> void:
	var c := challenge()
	var p: Dictionary = _game().player
	if not c.shield: p.shieldHits = 0
	if not c.barrier: p.barrierTime = 0
	if c.oneHit: p.phoenix = 0

# ================================================================ research (6196-6214, 6801-6838)
func researchLevel(value) -> int:
	var n := _num(value)
	if not _finite(n): return 0
	return int(minf(MAX_SAFE, maxf(0.0, floorf(n))))

func researchNumber(n) -> String:
	var f := _num(n)
	if not _finite(f): return "—"
	var neg := f < 0
	var s := "%.2f" % absf(f)
	var parts := s.split(".")
	var ip: String = parts[0]
	var frac: String = parts[1].rstrip("0")
	var out := ""
	var cnt := 0
	for i in range(ip.length() - 1, -1, -1):
		if cnt > 0 and cnt % 3 == 0: out = "," + out
		out = ip[i] + out
		cnt += 1
	if frac != "": out += "." + frac
	if neg and (out != "0"): out = "-" + out
	return out

func mobilityPercent(lv: float) -> float:
	return lv * .8 if lv <= 30.0 else 24.0 + 8.0 * log(1.0 + (lv - 30.0) / 10.0)
func recoveryPercent(lv: float) -> float:
	return lv * .25 if lv <= 25.0 else 6.25 + 1.25 * (sqrt(1.0 + (lv - 25.0) / 5.0) - 1.0)

func research_value(key: String, lv) -> float:
	var l := float(lv)
	match key:
		"power", "hull", "active": return l * 5.0
		"mobility": return mobilityPercent(l)
		"critical": return l * 2.0
		"recovery": return recoveryPercent(l)
		"magnet": return l * 4.0
		"economy": return l * 3.0
		"rapid", "haste": return l * 2.0
	return 0.0

func research_desc(key: String, lv) -> String:
	var l := float(lv)
	var n: Callable = researchNumber
	match key:
		"power": return "本体弾ダメージ +%s%%" % n.call(l * 5.0)
		"hull": return "最大HP +%s%%" % n.call(l * 5.0)
		"mobility": return "移動速度 +%s%%（30段以降は緩やかに継続）" % n.call(mobilityPercent(l))
		"critical": return "会心率 +%spt / 会心威力 +%s%%。確率100%%超過分も威力へ" % [n.call(l * .8), n.call(l * 2.0)]
		"recovery": return "HP吸収 +%spt（25段以降は緩やかに継続・回復効率補正あり）" % n.call(recoveryPercent(l))
		"magnet": return "回収範囲 +%s%% / ランXP +%s%%。全域回収中もXP補正は有効" % [n.call(l * 4.0), n.call(l)]
		"economy": return "ラン終了CR +%s%%" % n.call(l * 3.0)
		"rapid": return "本体連射速度 +%s%%。大量射撃は既存の威力集約で処理" % n.call(l * 2.0)
		"active": return "アクティブスキル出力 +%s%%" % n.call(l * 5.0)
		"haste": return "スキル再使用効率 +%s%%。CD = 基礎CD ÷ (1 + 効率)" % n.call(l * 2.0)
	return ""

func sanitizeResearchStats(raw) -> Dictionary:
	var d := _dictv(raw)
	var out := {}
	for k in META_STATS: out[k] = researchLevel(d.get(k))
	return out

func statCost(key: String, lv = null) -> float:
	if not META_STATS.has(key): return INF
	var l: int = int(meta.stats.get(key, 0)) if lv == null else researchLevel(lv)
	return float(META_STATS[key].base) + float(META_STATS[key].step) * float(l)

func researchTotalCost(key: String, start, count) -> float:
	if not META_STATS.has(key) or float(count) < 0 or float(count) > MAX_SAFE: return INF
	var d: Dictionary = META_STATS[key]
	var c := float(count)
	return c * (float(d.base) + float(d.step) * float(start)) + float(d.step) * c * (c - 1.0) / 2.0

func _safe_int_f(f: float) -> bool: return _finite(f) and absf(f) <= MAX_SAFE and f == floorf(f)

func affordableResearchCount(key: String, credits = null, start = null) -> int:
	if not META_STATS.has(key): return 0
	var cr: float = float(meta.credits) if credits == null else float(credits)
	var st: int = int(meta.stats.get(key, 0)) if start == null else int(start)
	if not _finite(cr) or cr < statCost(key, st): return 0
	var lo := 0
	var hi := int(minf(floorf(cr / float(META_STATS[key].base)), MAX_SAFE - float(st)))
	while lo < hi:
		var mid := lo + int(ceil(float(hi - lo) / 2.0))
		var total := researchTotalCost(key, st, mid)
		if _safe_int_f(total) and total <= cr: lo = mid
		else: hi = mid - 1
	return lo

func researchQuote(key: String, amount = null) -> Dictionary:
	if amount == null: amount = researchBatch
	var lv := researchLevel(meta.stats.get(key, 0))
	var count: int = affordableResearchCount(key) if (typeof(amount) == TYPE_STRING and amount == "max") else int(_num_or0(amount))
	var cost := researchTotalCost(key, lv, count)
	var nxt := lv + count
	var valid := count > 0 and float(nxt) <= MAX_SAFE and _safe_int_f(cost) and cost <= float(meta.credits)
	return {"lv": lv, "count": count, "cost": (int(cost) if _safe_int_f(cost) else cost), "next": nxt, "valid": valid}

func buyStat(key: String, amount = null) -> bool:
	if _game().state != "meta" or not META_STATS.has(key): return false
	var q := researchQuote(key, amount)
	if not q.valid:
		_ui_hook("researchNotice", ["CRが不足しているか、計算可能な数値範囲を超えています。"])
		return false
	meta.credits -= int(q.cost)
	meta.stats[key] = q.next
	saveMeta()
	_ui_hook("researchNotice", ["%sを%s段強化。合計%s CR使用。次のランから有効。" % [META_STATS[key].name, researchNumber(q.count), researchNumber(q.cost)]])
	_beep(390, .07, "triangle", .03, 260)
	return true

# ================================================================ growth limits (6502-6550)
func defaultGrowthLimits() -> Dictionary:
	var r := {}
	for k in META_STATS: r[k] = null
	return {"playerLevel": null, "research": r}

func ownedPlayerLevel(value) -> int: return maxi(1, researchLevel(value))

func _growth_choice(value, mn: int, mx: int):
	if value == null or (typeof(value) == TYPE_STRING and value == ""): return null
	if not _is_num(value) or not _finite(float(value)): return null
	return maxi(mn, mini(mx, int(floorf(float(value)))))

func sanitizeGrowthLimits(raw, level, stats) -> Dictionary:
	var source := _dictv(raw)
	var ranks := sanitizeResearchStats(stats)
	var max_level := ownedPlayerLevel(level)
	var res := _dictv(source.get("research"))
	var r := {}
	for k in META_STATS: r[k] = _growth_choice(res.get(k), 0, ranks[k])
	return {"playerLevel": _growth_choice(source.get("playerLevel"), 1, max_level), "research": r}

func resolveGrowthLimits(owner = null, limits = null) -> Dictionary:
	var o: Dictionary = meta if owner == null else owner
	var lim = o.get("growthLimits") if limits == null else limits
	var max_level := ownedPlayerLevel(o.get("playerLevel"))
	var owned := sanitizeResearchStats(o.get("stats"))
	var prefs := sanitizeGrowthLimits(lim, max_level, owned)
	var st := {}
	for k in META_STATS: st[k] = prefs.research[k] if prefs.research[k] != null else owned[k]
	return {"playerLevel": prefs.playerLevel if prefs.playerLevel != null else max_level, "stats": st, "ownedPlayerLevel": max_level, "ownedStats": owned}

func captureRunGrowth() -> Dictionary:
	return resolveGrowthLimits().duplicate(true)

func growthSummary(g = null) -> String:
	var gg: Dictionary = resolveGrowthLimits() if g == null else g
	var changed := 0
	for k in META_STATS: if gg.stats[k] < gg.ownedStats[k]: changed += 1
	return "適用 Lv.%s / 獲得 Lv.%s · %s" % [researchNumber(gg.playerLevel), researchNumber(gg.ownedPlayerLevel), ("研究 %d項目を調整" % changed) if changed else "研究は最大値"]

func growthEditAllowed() -> bool:
	return _game().state == "meta" and metaReturnState in ["menu", "gameover", "config"]

func growthSavedNotice(message: String) -> void:
	_ui_hook("growthSavedNotice", [("保存済み：" if storage_persistent else "このタブ内に保持（永続保存不可・Export推奨）：") + message])

func setGrowthChoice(key: String, value) -> bool:
	if not growthEditAllowed() or not (key == "playerLevel" or META_STATS.has(key)): return false
	if value != null and (not _is_num(value) or not _finite(float(value))): return false
	var nxt := sanitizeGrowthLimits(meta.growthLimits, meta.playerLevel, meta.stats)
	if key == "playerLevel": nxt.playerLevel = value
	else: nxt.research[key] = value
	meta.growthLimits = sanitizeGrowthLimits(nxt, meta.playerLevel, meta.stats)
	storage_set("nf_meta_v1", JSON.stringify(meta))
	return true

func setAllGrowthChoices(follow: bool) -> bool:
	if not growthEditAllowed(): return false
	var raw := defaultGrowthLimits()
	if not follow:
		raw.playerLevel = 1
		for k in META_STATS: raw.research[k] = 0
	meta.growthLimits = sanitizeGrowthLimits(raw, meta.playerLevel, meta.stats)
	storage_set("nf_meta_v1", JSON.stringify(meta))
	_ui_hook("renderGrowthControls", [])
	_ui_hook("updateGrowthSummaries", [])
	growthSavedNotice("すべて最大値に追従します。獲得済みの成長をすべて適用。" if follow else "次のランはユーザーLv.1・全研究0段に固定。装備・カードは変更しません。")
	return true

# ================================================================ meta save (6552-6579)
func _default_records() -> Dictionary:
	return {"totalKills": 0, "totalBosses": 0, "clears": 0, "maxCombo": 0.0, "maxHit": 0.0, "highestCP": 0.0, "highestCPWave": 0,
		"longest": 0.0, "bestByDifficulty": {}, "waveByDifficulty": {}, "clearTimes": {}, "fractureWave": 0}

func defaultMeta() -> Dictionary:
	var syn := {}
	for id in STARTER_PARTS: syn[id] = 1
	return {"credits": 0, "data": 0, "playerLevel": 1, "playerXp": 0.0, "stats": sanitizeResearchStats({}), "growthLimits": defaultGrowthLimits(),
		"modules": {}, "equipped": null, "equippedGear": {"core": null, "armor": null, "drive": null}, "pity": 0, "totalRuns": 0,
		"syntax": syn, "cards": [], "equippedCards": [], "achievements": {}, "records": _default_records()}

func _fix_int_dict(d) -> Dictionary:
	var out := {}
	for k in _dictv(d): out[k] = int(_num_or0(d[k])) if _is_num(d[k]) else d[k]
	return out

func _fix_records(r: Dictionary) -> Dictionary:
	for k in ["totalKills", "totalBosses", "clears", "highestCPWave", "fractureWave"]:
		if r.has(k) and _is_num(r[k]): r[k] = int(r[k])
	for k in ["maxCombo", "maxHit", "highestCP", "longest"]:
		if r.has(k) and _is_num(r[k]): r[k] = float(r[k])
	r.bestByDifficulty = _fix_int_dict(r.get("bestByDifficulty"))
	r.waveByDifficulty = _fix_int_dict(r.get("waveByDifficulty"))
	return r

func loadMeta() -> Dictionary:
	var s = storage_get("nf_meta_v1")
	var raw = null
	if s != null and String(s) != "": raw = JSON.parse_string(String(s))
	if typeof(raw) != TYPE_DICTIONARY: return defaultMeta()
	var d := defaultMeta()
	var gear: Dictionary = d.equippedGear.duplicate()
	for k in _dictv(raw.get("equippedGear")): gear[k] = raw.equippedGear[k]
	var eq = raw.get("equipped")
	if eq != null and MODULE_BY_ID.has(eq): gear[moduleSlot(eq)] = eq
	for slot in gear.keys():
		if gear[slot] != null and not MODULE_BY_ID.has(gear[slot]): gear[slot] = null
	var out: Dictionary = d.duplicate(true)
	for k in raw: out[k] = raw[k]
	out.playerLevel = maxi(1, int(floorf(clampf(_num_or0(raw.get("playerLevel")) if _num_or0(raw.get("playerLevel")) != 0.0 else 1.0, -1e15, 1e15))))
	out.playerXp = maxf(0.0, _num_or0(raw.get("playerXp")))
	out.data = maxi(0, int(floorf(clampf(_num_or0(raw.get("data")), 0.0, 1e15))))
	out.credits = researchLevel(raw.get("credits"))
	out.pity = int(_num_or0(raw.get("pity")))
	out.totalRuns = int(_num_or0(raw.get("totalRuns")))
	out.stats = sanitizeResearchStats(raw.get("stats"))
	out.growthLimits = sanitizeGrowthLimits(raw.get("growthLimits"), raw.get("playerLevel"), raw.get("stats"))
	out.modules = _fix_int_dict(raw.get("modules"))
	out.equippedGear = gear
	out.achievements = _dictv(raw.get("achievements")).duplicate()
	var rr: Dictionary = d.records.duplicate(true)
	var rraw := _dictv(raw.get("records"))
	for k in rraw: rr[k] = rraw[k]
	rr.bestByDifficulty = _dictv(rraw.get("bestByDifficulty")).duplicate()
	rr.waveByDifficulty = _dictv(rraw.get("waveByDifficulty")).duplicate()
	rr.clearTimes = _dictv(rraw.get("clearTimes")).duplicate()
	out.records = _fix_records(rr)
	var syn: Dictionary = d.syntax.duplicate()
	for k in _dictv(raw.get("syntax")): syn[k] = raw.syntax[k]
	out.syntax = _fix_int_dict(syn)
	var cards: Array = []
	if typeof(raw.get("cards")) == TYPE_ARRAY:
		for c in raw.cards: cards.append(_normalize_card(c))
	out.cards = cards
	out.equippedCards = (raw.equippedCards as Array).slice(0, 3) if typeof(raw.get("equippedCards")) == TYPE_ARRAY else []
	return out

func _post_load_meta() -> void:
	var cards: Array = []
	for c in meta.cards: if _valid_recipe(c): cards.append(c)
	meta.cards = cards
	var seen := {}
	for c in meta.cards:
		if seen.has(c.id): c.id = _new_card_id()
		seen[c.id] = true
	var eqc: Array = []
	for id in meta.equippedCards: if seen.has(id) and not (id in eqc): eqc.append(id)
	meta.equippedCards = eqc
	repairOwnedSyntax()

func repairOwnedSyntax() -> void:
	for id in STARTER_PARTS: meta.syntax[id] = maxi(1, int(_num_or0(meta.syntax.get(id))))
	for c in meta.get("cards", []):
		if _valid_recipe(c):
			for k in CARD_FIELDS: meta.syntax[c[k]] = maxi(1, int(_num_or0(meta.syntax.get(c[k]))))

func saveMeta() -> void:
	storage_set("nf_meta_v1", JSON.stringify(meta))
	_ui_hook("refreshMetaUI", [])

# ================================================================ Save Export / Import (6582-6769)
func exportPayload() -> Dictionary:
	return {
		"app": SAVE_EXPORT_APP, "formatVersion": SAVE_EXPORT_VERSION,
		"exportedAt": Time.get_datetime_string_from_system(true) + ".000Z",
		"gameVersion": GAME_VERSION,
		"data": {"high": _num_or0(save.high), "wave": _num_or0(save.wave), "meta": meta.duplicate(true)}}

func export_to_string() -> String:
	return JSON.stringify(exportPayload(), "  ", false)

## Writes the save JSON to `path` (any Godot path). Returns OK or an Error code.
func export_to_file(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return FileAccess.get_open_error()
	f.store_string(export_to_string())
	f.close()
	_beep(520, .07, "triangle", .025, 260)
	return OK

## Returns null on failure and sets last_error. Otherwise a sanitized meta Dictionary.
func sanitizeImportedMeta(raw):
	if typeof(raw) != TYPE_DICTIONARY:
		last_error = "metaデータが不正です。"
		return null
	var d := defaultMeta()
	var stats: Dictionary = d.stats.duplicate()
	var rstats := _dictv(raw.get("stats"))
	for key in stats.keys(): stats[key] = researchLevel(rstats.get(key))
	var modules := {}
	if typeof(raw.get("modules")) == TYPE_DICTIONARY:
		for m in MODULES:
			var lv := _num(raw.modules.get(m.id))
			if _finite(lv) and lv > 0: modules[m.id] = clampi(int(floorf(clampf(lv, 0.0, 1e9))), 1, 5)
	var syntax: Dictionary = d.syntax.duplicate()
	if typeof(raw.get("syntax")) == TYPE_DICTIONARY:
		for id in raw.syntax:
			if PART_BY_ID.has(id) and _truthy(raw.syntax[id]): syntax[id] = 1
	var cards: Array = []
	if typeof(raw.get("cards")) == TYPE_ARRAY:
		for c in raw.cards:
			var n := _normalize_card(c)
			if _valid_recipe(n): cards.append(n)
	for c in cards:
		for k in CARD_FIELDS: syntax[c[k]] = 1
	var card_ids := {}
	for c in cards: card_ids[c.id] = true
	var eqc: Array = []
	if typeof(raw.get("equippedCards")) == TYPE_ARRAY:
		for id in raw.equippedCards: if card_ids.has(id): eqc.append(id)
		eqc = eqc.slice(0, 3)
	var equipped = raw.get("equipped")
	if not (equipped != null and MODULE_BY_ID.has(equipped) and modules.has(equipped)): equipped = null
	var gear := {"core": null, "armor": null, "drive": null}
	if typeof(raw.get("equippedGear")) == TYPE_DICTIONARY:
		for slot in gear.keys():
			var id = raw.equippedGear.get(slot)
			if id != null and MODULE_BY_ID.has(id) and modules.has(id) and moduleSlot(id) == slot: gear[slot] = id
	if equipped != null: gear[moduleSlot(equipped)] = equipped
	var plevel := _floor_i(_num_or0(raw.get("playerLevel")) if _num_or0(raw.get("playerLevel")) != 0.0 else 1.0, 1.0, 99999999.0)
	var records: Dictionary = d.records.duplicate(true)
	if typeof(raw.get("records")) == TYPE_DICTIONARY:
		for k in raw.records: records[k] = raw.records[k]
		records.bestByDifficulty = _dictv(raw.records.get("bestByDifficulty")).duplicate()
		records.waveByDifficulty = _dictv(raw.records.get("waveByDifficulty")).duplicate()
		records.clearTimes = _dictv(raw.records.get("clearTimes")).duplicate()
	var out := d.duplicate(true)
	out.credits = researchLevel(raw.get("credits"))
	out.data = _floor_i(_num_or0(raw.get("data")), 0.0, 999999999.0)
	out.playerLevel = plevel
	out.playerXp = clampf(_num_or0(raw.get("playerXp")), 0.0, 999999999999.0)
	out.stats = stats
	out.growthLimits = sanitizeGrowthLimits(raw.get("growthLimits"), plevel, stats)
	out.modules = modules
	out.equipped = null
	out.equippedGear = gear
	out.pity = _floor_i(_num_or0(raw.get("pity")), 0.0, 1000.0)
	out.totalRuns = _floor_i(_num_or0(raw.get("totalRuns")), 0.0, 99999999.0)
	out.achievements = _dictv(raw.get("achievements")).duplicate(true)
	out.records = _fix_records(records)
	out.syntax = syntax
	out.cards = cards
	out.equippedCards = eqc
	return out

## Returns {high, wave, meta, exportedAt, gameVersion} or {"error": String}.
func validateImportPayload(payload) -> Dictionary:
	if typeof(payload) != TYPE_DICTIONARY: return {"error": "JSON形式が不正です。"}
	if payload.get("app") != SAVE_EXPORT_APP: return {"error": "NEON FRACTUREのセーブデータではありません。"}
	if _num(payload.get("formatVersion")) != float(SAVE_EXPORT_VERSION):
		var fv = payload.get("formatVersion")
		return {"error": "未対応のセーブ形式です (v%s)。" % (str(fv) if fv != null else "?")}
	if typeof(payload.get("data")) != TYPE_DICTIONARY: return {"error": "セーブ本体がありません。"}
	var dd: Dictionary = payload.data
	var high := _floor_i(_num_or0(dd.get("high")), 0.0, 999999999999.0)
	var wave_n := _floor_i(_num_or0(dd.get("wave")), 0.0, 999999.0)
	var im = sanitizeImportedMeta(dd.get("meta"))
	if im == null: return {"error": last_error}
	return {"high": high, "wave": wave_n, "meta": im,
		"exportedAt": payload.exportedAt if typeof(payload.get("exportedAt")) == TYPE_STRING else null,
		"gameVersion": payload.gameVersion if typeof(payload.get("gameVersion")) == TYPE_STRING else "不明"}

## Reads + validates a save file. Returns the parsed dict (also stored in pendingImportedSave) or {"error": msg}.
func read_import_file(path: String) -> Dictionary:
	pendingImportedSave = null
	if not FileAccess.file_exists(path): return {"error": "ファイルを読み込めませんでした。"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {"error": "ファイルを読み込めませんでした。"}
	if f.get_length() > 8000000: return {"error": "セーブファイルが大きすぎます。8MB以下のJSONを選択してください。"}
	var text := f.get_as_text()
	var payload = JSON.parse_string(text)
	if payload == null: return {"error": "JSON形式が不正です。"}
	var parsed := validateImportPayload(payload)
	if parsed.has("error"): return parsed
	pendingImportedSave = parsed
	return parsed

func readImportFile(path: String) -> Dictionary: return read_import_file(path)

func applyImportedSave(imported = null) -> bool:
	var im = pendingImportedSave if imported == null else imported
	if im == null: return false
	save.high = im.high
	save.wave = im.wave
	meta = im.meta
	storage_set("nf_high", str(save.high))
	storage_set("nf_wave", str(save.wave))
	storage_set("nf_meta_v1", JSON.stringify(meta))
	pendingImportedSave = null
	_ui_hook("refreshMetaUI", [])
	_beep(380, .12, "triangle", .035, 520)
	return true

# ================================================================ player XP (6786-6799, 6839-6868)
func playerXpNeeded(level) -> int:
	return int(floorf(120.0 + 82.0 * sqrt(maxf(1.0, float(level)))))
func scoreToPlayerXp(s) -> int:
	var m := 1.0 + (challengeReward() - 1.0) * .52
	return maxi(20, int(floorf((25.0 + .72 * pow(maxf(0.0, float(s)), .72)) * m)))
func playerLevelBase(level = null) -> Dictionary:
	var lv: float = float(meta.playerLevel) if level == null else float(level)
	var q := sqrt(maxf(0.0, lv - 1.0))
	return {"damage": .90 * q, "maxHp": 4.2 * q, "magnet": 2.4 * q, "bulletSpeed": .65 * q}

func awardPlayerXp(amount) -> int:
	var gained := 0
	meta.playerXp = maxf(0.0, float(meta.get("playerXp", 0.0)) + float(amount))
	while meta.playerXp >= playerXpNeeded(meta.playerLevel):
		meta.playerXp -= playerXpNeeded(meta.playerLevel)
		meta.playerLevel += 1
		gained += 1
		if gained > 10000: break
	return gained

## p is the player Dictionary. Module apply closures are looked up in Cards.MODULE_BY_ID[id].apply (Callable(p, lv)).
func applyMetaBonuses(p: Dictionary, growth = null) -> void:
	var g: Dictionary = resolveGrowthLimits() if growth == null else growth
	var base := playerLevelBase(g.playerLevel)
	var st := sanitizeResearchStats(g.stats)
	p.damage += base.damage; p.maxHp += base.maxHp; p.magnet += base.magnet; p.bulletSpeed += base.bulletSpeed; p.hp = p.maxHp
	p.damage *= 1.0 + st.power * .05; p.maxHp *= 1.0 + st.hull * .05; p.hp = p.maxHp
	p.speed *= 1.0 + mobilityPercent(st.mobility) / 100.0
	p.lifesteal += recoveryPercent(st.recovery) / 100.0
	p.magnet *= 1.0 + st.magnet * .04; p.xpMultiplier *= 1.0 + st.magnet * .01
	p.fireRate *= 1.0 + st.rapid * .02; p.activePower *= 1.0 + st.active * .05; p.activeHaste += st.haste * .02
	var cards := _cards()
	for slot in GEAR_SLOTS:
		var id = _dictv(meta.get("equippedGear")).get(slot)
		var lv: int = int(meta.modules.get(id, 0)) if id != null else 0
		if id == null or lv <= 0 or cards == null: continue
		var mods = cards.get("MODULE_BY_ID")
		if typeof(mods) == TYPE_DICTIONARY and mods.has(id) and mods[id].get("apply") is Callable:
			mods[id].apply.call(p, lv)
	var raw_crit: float = p.crit + st.critical * .008
	p.crit = minf(1.0, raw_crit)
	p.critMult *= 1.0 + st.critical * .02 + maxf(0.0, raw_crit - 1.0)

func earnedCreditAmount() -> int:
	if developerRun.active: return 0
	var gm := _game()
	var raw: float = floorf(gm.score / 48.0) + gm.wave * 18 + floorf(gm.kills / 3.0) + gm.bossesDefeated * 120
	var diff_bonus := 1.0 + (challengeReward() - 1.0) * .60
	var g: Dictionary = runGrowth if runGrowth != null else resolveGrowthLimits()
	var economy: float = float(g.stats.economy)
	return maxi(0, int(floorf(raw * (1.0 + economy * .03) * diff_bonus)))

func earnedDataAmount() -> int:
	if developerRun.active: return 0
	var gm := _game()
	var base: float = 38.0 + floorf(gm.score / 1700.0) + gm.wave * 3 + gm.bossesDefeated * 16
	return maxi(20, int(floorf(base * (1.0 + (challengeReward() - 1.0) * .72))))

# ================================================================ achievements (6870-6900)
func achievement_test(id: String) -> bool:
	var r: Dictionary = meta.records
	match id:
		"first_run": return meta.totalRuns >= 1
		"kill_1k": return r.totalKills >= 1000
		"kill_10k": return r.totalKills >= 10000
		"boss_25": return r.totalBosses >= 25
		"wave_25": return _max_values(r.waveByDifficulty) >= 25
		"wave_50": return _max_values(r.waveByDifficulty) >= 50
		"level_25": return meta.playerLevel >= 25
		"level_100": return meta.playerLevel >= 100
		"hard_clear": return _truthy(meta.achievements.get("_hardClear"))
		"hardcore_clear": return _truthy(meta.achievements.get("_hardcoreClear"))
		"fracture_10": return r.fractureWave >= 10
		"cp5_wave20": return r.highestCPWave >= 20 and r.highestCP >= 5
		"cards_20": return meta.cards.size() >= 20
		"legend_card":
			for c in meta.cards: if c.get("rarity") == "LEGENDARY": return true
			return false
	return false

func updateRunRecords(reason: String) -> void:
	if developerRun.active: return
	var gm := _game()
	var r: Dictionary = meta.records
	var c := challenge()
	var d: String = runConfig.difficulty
	r.totalKills = int(r.get("totalKills", 0)) + int(gm.kills)
	r.totalBosses = int(r.get("totalBosses", 0)) + int(gm.bossesDefeated)
	r.maxCombo = maxf(float(r.get("maxCombo", 0)), float(gm.maxComboRun))
	r.maxHit = maxf(float(r.get("maxHit", 0)), float(gm.maxHitDamageRun))
	r.highestCP = maxf(float(r.get("highestCP", 0)), float(c.cp))
	r.longest = maxf(float(r.get("longest", 0)), float(gm.time))
	r.bestByDifficulty[d] = maxi(int(r.bestByDifficulty.get(d, 0)), int(floorf(gm.score)))
	r.waveByDifficulty[d] = maxi(int(r.waveByDifficulty.get(d, 0)), int(gm.wave))
	if d == "fracture": r.fractureWave = maxi(int(r.get("fractureWave", 0)), int(gm.wave))
	if float(c.cp) >= float(r.get("highestCP", 0)) - .0001: r.highestCPWave = maxi(int(r.get("highestCPWave", 0)), int(gm.wave))
	if reason == "clear":
		r.clears = int(r.get("clears", 0)) + 1
		if not r.has("clearTimes") or typeof(r.clearTimes) != TYPE_DICTIONARY: r.clearTimes = {}
		var key := "%s_%s" % [d, str(finalWaveTarget())]
		var elapsed := maxf(0.0, (Time.get_ticks_msec() - float(gm.runStartedAt)) / 1000.0)
		if not r.clearTimes.has(key) or r.clearTimes[key] == 0 or elapsed < float(r.clearTimes[key]): r.clearTimes[key] = elapsed
		if d in ["hard", "hardcore", "fracture"]: meta.achievements["_hardClear"] = true
		if d == "hardcore": meta.achievements["_hardcoreClear"] = true

## Returns Array of newly unlocked achievement dicts {id,name,desc,reward}.
func checkAchievements() -> Array:
	if developerRun.active: return []
	var newly: Array = []
	for a in ACHIEVEMENTS:
		if _truthy(meta.achievements.get(a.id)) or not achievement_test(a.id): continue
		meta.achievements[a.id] = _now_unix_ms()
		meta.data = int(meta.get("data", 0)) + int(a.reward)
		newly.append(a)
	return newly

## Data the renderAchievements() DOM function would show.
func achievementSummary() -> Dictionary:
	var unlocked := 0
	for a in ACHIEVEMENTS: if _truthy(meta.achievements.get(a.id)): unlocked += 1
	var r: Dictionary = meta.records
	var times: Array = []
	for v in _dictv(r.get("clearTimes")).values(): times.append(float(v))
	return {"unlocked": unlocked, "total": ACHIEVEMENTS.size(), "bestScore": _max_values(r.get("bestByDifficulty")), "bestWave": _max_values(r.get("waveByDifficulty")),
		"maxCP": float(r.get("highestCP", 0)), "maxCombo": float(r.get("maxCombo", 0)), "totalKills": int(r.get("totalKills", 0)), "clears": int(r.get("clears", 0)),
		"maxHit": float(r.get("maxHit", 0)), "fractureWave": int(r.get("fractureWave", 0)), "fastClear": (times.min() if times.size() else null)}

# ================================================================ forge / library / gacha / loot (6906-7157)
func unlockedParts(type: String) -> Array:
	var out: Array = []
	for p in CARD_PARTS.get(type, []): if _truthy(meta.syntax.get(p.id)): out.append(p)
	return out

## selection: {trigger,condition,chance,effect,power}; name optional. Replaces DOM-reading forgeCandidate().
func forgeCandidate(selection: Dictionary, card_name: String = "") -> Dictionary:
	var values: Dictionary = selection.duplicate()
	var nm := card_name.strip_edges()
	if nm != "": values["name"] = nm
	return _normalize_card(values)

func forgeValidation(card: Dictionary) -> String:
	var issue := _recipe_issue(card)
	if issue != "": return issue
	for k in CARD_FIELDS: if not _truthy(meta.syntax.get(card[k])): return "未解析の単語はまだ使用できません。"
	var cost: int = int(card.cost)
	if cost > 15: return "コストを%d下げてください（上限15）。" % (cost - 15)
	var owned = _find_duplicate_card(card)
	if owned != null: return "同一構成の所持カード「%s」があります。下の「所持カードを開く」で該当カードを直接確認できます。" % owned.name
	return ""

func createForgedCard(card: Dictionary) -> bool:
	if _game().state != "meta": return false
	var err := forgeValidation(card)
	if err != "":
		_ui_hook("forgeNotice", [err, "warn"])
		return false
	meta.cards = meta.cards + [card]
	saveMeta()
	_ui_hook("forgeNotice", ["「%s」を作成しました。保管庫から装備できます。" % card.name])
	_beep(760 if card.rarity == "LEGENDARY" else 520, .10, "triangle", .04, 340)
	return true

func rarityValue(r) -> int:
	return {"COMMON": 1, "RARE": 2, "EPIC": 3, "LEGENDARY": 4}.get(r, 1)

func rarityRoll(forceRare: bool = false, forceEpic: bool = false) -> String:
	var r := randf()
	if forceEpic: return "LEGENDARY" if r < .18 else "EPIC"
	if forceRare:
		if r < .05: return "LEGENDARY"
		if r < .27: return "EPIC"
		return "RARE"
	if r < .025: return "LEGENDARY"
	if r < .12: return "EPIC"
	if r < .40: return "RARE"
	return "COMMON"

func grantSyntaxPart(targetRarity = null) -> Dictionary:
	var pool: Array = []
	for t in CARD_PARTS: pool.append_array(CARD_PARTS[t])
	if targetRarity != null:
		var f: Array = []
		for p in pool: if rarityValue(p.rarity) <= rarityValue(targetRarity): f.append(p)
		pool = f
	var unowned: Array = []
	for p in pool: if not _truthy(meta.syntax.get(p.id)): unowned.append(p)
	var p: Dictionary = U.pick(unowned if unowned.size() else pool)
	var duplicate := _truthy(meta.syntax.get(p.id))
	meta.syntax[p.id] = int(meta.syntax.get(p.id, 0)) + 1
	var refund := 0
	if duplicate:
		refund = {"COMMON": 18, "RARE": 32, "EPIC": 60, "LEGENDARY": 110}.get(p.rarity, 18)
		meta.data = int(meta.get("data", 0)) + refund
	return {"kind": "syntax", "part": p, "rarity": p.rarity, "refund": refund}

func randomCardForRarity(rarity: String) -> Dictionary:
	var mx: int = {"COMMON": 4, "RARE": 7, "EPIC": 11, "LEGENDARY": 15}[rarity]
	var mn: int = {"COMMON": 0, "RARE": 5, "EPIC": 8, "LEGENDARY": 12}[rarity]
	var best = null
	for tries in 100:
		var c := _normalize_card({"trigger": U.pick(CARD_PARTS.trigger).id, "condition": U.pick(CARD_PARTS.condition).id, "chance": U.pick(CARD_PARTS.chance).id,
			"effect": U.pick(CARD_PARTS.effect).id, "power": U.pick(CARD_PARTS.power).id})
		if c.cost >= mn and c.cost <= mx and _recipe_issue(c) == "":
			best = c
			break
		if best == null: best = c
	var card: Dictionary = best if best != null else _normalize_card({"trigger": "on_kill", "condition": "always", "chance": "c50", "effect": "explode", "power": "p120"})
	var cd := _cards()
	if cd != null and cd.has_method("cardRarity"): card.rarity = cd.cardRarity(card.cost)
	if cd != null and cd.has_method("generatedCardName"): card.name = cd.generatedCardName(card)
	return card

func grantCompletedCard(rarity: String) -> Dictionary:
	var card := randomCardForRarity(rarity)
	var dup = _find_duplicate_card(card)
	var refund := 0
	var duplicate := false
	if dup != null:
		duplicate = true
		refund = 35 * rarityValue(card.rarity)
		meta.data = int(meta.get("data", 0)) + refund
	else:
		meta.cards.append(card)
	for k in CARD_FIELDS: meta.syntax[card[k]] = int(meta.syntax.get(card[k], 0)) + 1
	return {"kind": "card", "card": dup if dup != null else card, "rarity": card.rarity, "refund": refund, "duplicate": duplicate}

func pullModule(rarity: String) -> Dictionary:
	var pool: Array = []
	for m in MODULES: if m.rarity == rarity: pool.append(m)
	if pool.is_empty(): for m in MODULES: if m.rarity == "RARE": pool.append(m)
	var m: Dictionary = U.pick(pool)
	var old: int = int(meta.modules.get(m.id, 0))
	var refund := 0
	if old >= 5:
		refund = {"COMMON": 28, "RARE": 50, "EPIC": 90, "LEGENDARY": 160}[m.rarity]
		meta.data = int(meta.get("data", 0)) + refund
	else:
		meta.modules[m.id] = old + 1
	return {"kind": "module", "m": m, "rarity": m.rarity, "lv": int(meta.modules.get(m.id, 5)), "refund": refund}

func pullByGacha(type: String, rarity: String) -> Dictionary:
	var g: Dictionary = GACHA_TYPES.get(type, GACHA_TYPES.beginner)
	var r := randf()
	if r < g.weights[0]: return grantSyntaxPart(rarity)
	if r < g.weights[0] + g.weights[1]: return grantCompletedCard(rarity)
	return pullModule(rarity)

## Returns {ok, results, error}. Rendering is delegated via UI.hook("renderGachaResults",[results]).
func doGacha(count: int) -> Dictionary:
	var g: Dictionary = GACHA_TYPES.get(selectedGachaType, GACHA_TYPES.beginner)
	var cost: int = int(g.cost) * (9 if count == 10 else 1)
	if int(meta.get("data", 0)) < cost:
		_beep(100, .12, "square", .025, -20)
		return {"ok": false, "results": [], "error": "%s DATA必要です。" % researchNumber(cost)}
	meta.data -= cost
	var results: Array = []
	var got_rare_plus := false
	for i in count:
		var force_epic: bool = meta.pity >= 24
		var force_rare: bool = count == 10 and i == 9 and not got_rare_plus
		var rarity := rarityRoll(force_rare, force_epic)
		if g.rareBonus > 0 and not force_epic and randf() < g.rareBonus:
			rarity = "EPIC" if rarityValue(rarity) < 3 else rarity
		if rarityValue(rarity) >= 2: got_rare_plus = true
		results.append(pullByGacha(selectedGachaType, rarity))
		if rarityValue(rarity) >= 3: meta.pity = 0
		else: meta.pity += 1
	saveMeta()
	_ui_hook("renderGachaResults", [results])
	var best := 1
	for x in results: best = maxi(best, rarityValue(x.rarity))
	_beep(760 if best >= 4 else 610 if best >= 3 else 440, .16, "triangle", .045, 420)
	return {"ok": true, "results": results, "error": ""}

func scoreRewardProfile(s = null) -> Dictionary:
	var gm := _game()
	var sc: float = float(gm.score) if s == null else float(s)
	var c := challenge()
	var effective := sc * (1.0 + (challengeReward() - 1.0) * .72)
	var f := effective / (effective + 120000.0)
	var slots := 2
	var rank := "C"
	if effective >= 25000: slots = 3; rank = "B"
	if effective >= 75000: slots = 4; rank = "A"
	if effective >= 150000: slots = 5; rank = "S"
	if effective >= 300000: slots = 6; rank = "SS"
	if effective >= 600000: slots = 8; rank = "SSS"
	if effective >= 1000000: slots = 10
	slots = mini(12, slots + mini(2, int(gm.bossesDefeated)) + mini(2, int(floorf(log(maxf(1.0, float(c.cp))) / log(2.0)))))
	return {"factor": f, "effective": effective, "slots": slots, "rank": rank, "cp": c.cp, "reward": challengeReward(),
		"gear": .12 + (.42 - .12) * f, "card": .10 + (.32 - .10) * f, "rarePlus": .22 + (.50 - .22) * f,
		"epicPlus": .05 + (.20 - .05) * f, "legendary": .004 + (.055 - .004) * f}

func runRewardCount() -> int:
	return 0 if developerRun.active else int(scoreRewardProfile().slots)

func runRarityRoll(profile: Dictionary, mn: String = "COMMON") -> String:
	var r := randf()
	var rarity := "LEGENDARY" if r < profile.legendary else "EPIC" if r < profile.epicPlus else "RARE" if r < profile.rarePlus else "COMMON"
	if rarityValue(rarity) < rarityValue(mn): rarity = mn
	return rarity

func grantRunLoot() -> Dictionary:
	var profile := scoreRewardProfile()
	var score: float = float(_game().score)
	var results: Array = []
	var guarantees: Array = [{"kind": "syntax", "min": "COMMON"}]
	if score >= 75000 or profile.cp >= 2: guarantees.append({"kind": "any", "min": "RARE"})
	if score >= 150000 or profile.cp >= 3.2: guarantees.append({"kind": "gear", "min": "RARE"})
	if score >= 300000 or profile.cp >= 5: guarantees.append({"kind": "any", "min": "EPIC"})
	if score >= 600000 or profile.cp >= 6.8: guarantees.append({"kind": "gear", "min": "EPIC"})
	var cards := 0
	var new_syntax := 0
	var gear := 0
	for i in profile.slots:
		var g = guarantees[i] if i < guarantees.size() else null
		var rarity := runRarityRoll(profile, g.min if g != null else "COMMON")
		var kind: String = g.kind if g != null else "any"
		if kind == "any":
			var r := randf()
			kind = "gear" if r < profile.gear else "card" if r < profile.gear + profile.card else "syntax"
		var x: Dictionary
		if kind == "gear":
			x = pullModule(rarity); gear += 1
		elif kind == "card":
			x = grantCompletedCard(rarity); cards += 1
		else:
			var before := _owned_syntax_count()
			x = grantSyntaxPart(rarity)
			if _owned_syntax_count() > before: new_syntax += 1
		results.append(x)
	return {"count": profile.slots, "cards": cards, "newSyntax": new_syntax, "gear": gear, "results": results, "profile": profile}

func _owned_syntax_count() -> int:
	var n := 0
	for v in meta.syntax.values(): if _truthy(v): n += 1
	return n

# ---- library actions (the inline closures of renderCards/renderGear; added for UI) ----
func toggleEquipCard(id: String) -> bool:
	if id in meta.equippedCards: meta.equippedCards.erase(id)
	elif meta.equippedCards.size() < 3: meta.equippedCards.append(id)
	else:
		_ui_hook("libraryNotice", ["装備枠は3枚です。別のカードを外してから装備してください。", "warn"])
		return false
	saveMeta()
	return true

func toggleEquipGear(id: String) -> void:
	var slot := moduleSlot(id)
	meta.equippedGear[slot] = null if meta.equippedGear.get(slot) == id else id
	meta.equipped = null
	saveMeta()

func deleteCard(id: String) -> bool:
	for c in meta.cards:
		if c.id == id:
			if _truthy(c.get("favorite")): return false
			meta.cards = meta.cards.filter(func(x): return x.id != id)
			meta.equippedCards = meta.equippedCards.filter(func(x): return x != id)
			saveMeta()
			return true
	return false

func renameCard(id: String, new_name: String) -> void:
	var n := new_name.strip_edges()
	if n == "": return
	for c in meta.cards: if c.id == id: c.name = n.substr(0, 64)
	saveMeta()

func toggleFavoriteCard(id: String) -> void:
	for c in meta.cards: if c.id == id: c.favorite = not _truthy(c.get("favorite"))
	saveMeta()

func openMeta(from: String = "menu") -> void:
	metaReturnState = from if from in ["gameover", "config"] else "menu"
	_game().state = "meta"
	_ui_hook("openMeta", [from])

func closeMeta() -> void:
	_game().state = metaReturnState
	_ui_hook("closeMeta", [])

## UI refresh (原作 7036): UI milestone renders it.
func refreshMetaUI() -> void:
	UI.hook("refreshMetaUI")
