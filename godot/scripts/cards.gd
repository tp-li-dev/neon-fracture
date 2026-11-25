extends Node
## Cards — gear modules, card-syntax system, in-run upgrade/skill system.
## Port of index.html lines 6216-6500 and 8324-8640.
## Run choices (skills/legendary/unique/endless) are Dictionaries
## {id, icon, name, rarity, rank?, desc, apply: Callable}; call `u.apply.call()`.

# ---------------------------------------------------------------- data
var MODULES: Array = []
var MODULE_BY_ID: Dictionary = {}
var MODULE_SLOT: Dictionary = {}
var CARD_PARTS: Dictionary = {}
var PART_BY_ID: Dictionary = {}
var STARTER_PARTS: Array = []

const MODULE_RARITY := {
	"COMMON": {"label": "コモン", "cls": "text-slate-300", "border": "border-slate-400/15"},
	"RARE": {"label": "レア", "cls": "text-cyan-300", "border": "border-cyan-300/20"},
	"EPIC": {"label": "エピック", "cls": "text-violet-300", "border": "border-violet-300/25"},
	"LEGENDARY": {"label": "レジェンダリー", "cls": "text-amber-300", "border": "border-amber-300/30"},
}
const GEAR_SLOT_LABEL := {"core": "CORE", "armor": "ARMOR", "drive": "DRIVE"}
const CARD_RARITY := {
	"COMMON": {"label": "コモン", "cls": "text-slate-300", "border": "border-slate-400/20", "min": 0},
	"RARE": {"label": "レア", "cls": "text-cyan-300", "border": "border-cyan-300/25", "min": 5},
	"EPIC": {"label": "エピック", "cls": "text-violet-300", "border": "border-violet-300/30", "min": 8},
	"LEGENDARY": {"label": "レジェンダリー", "cls": "text-amber-300", "border": "border-amber-300/35", "min": 12},
}
const CARD_FIELDS := ["trigger", "condition", "chance", "effect", "power"]

var cardProcDepth: int = 0
## Declared in the original as `let ...,runLoadoutCards=[]` (line 10397, UI area); owned here.
var runLoadoutCards: Array = []

var forgeSelection: Dictionary = {"trigger": "on_kill", "condition": "always", "chance": "c25", "effect": "heal", "power": "p80"}
var libraryPage: int = 0
var gearPage: int = 0
var forgeOwnedKey: String = ""
var forgeLastCreated = null
var libraryFocusId = null
const LIBRARY_PAGE_SIZE := 18

const rarityRank := {"COMMON": 1, "RARE": 2, "EPIC": 3, "LEGENDARY": 4}
const rankRarity := {1: "COMMON", 2: "RARE", 3: "EPIC", 4: "LEGENDARY"}
const rareLabel := {"COMMON": "コモン", "RARE": "レア", "EPIC": "エピック", "LEGENDARY": "レジェンダリー"}
const rareClass := {"COMMON": "text-slate-400", "RARE": "text-cyan-300", "EPIC": "text-violet-300", "LEGENDARY": "text-amber-300"}

## skills: [{id, icon, name, tiers:{COMMON:{desc},RARE:{desc},EPIC:{desc}}, req:bool(has req)}]
## apply via skill_apply(id, tier_index 0..2); requirement via skill_req(id).
var skills: Array = []
var uniqueEpics: Array = []
var legendarySkills: Array = []


func _init() -> void:
	_load_defs()
	_build_skills()


func _ready() -> void:
	pass


func _load_defs() -> void:
	var f := FileAccess.open("res://data/defs.json", FileAccess.READ)
	if f == null:
		push_error("Cards: cannot open defs.json")
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	MODULES = d.get("modules", [])
	MODULE_BY_ID = {}
	for m in MODULES:
		var mid: String = m.id
		m["apply"] = func(p, lv): module_apply(mid, p, lv)
		MODULE_BY_ID[m.id] = m
	MODULE_SLOT = d.get("module_slot", {})
	CARD_PARTS = d.get("card_parts", {})
	PART_BY_ID = {}
	for type in CARD_PARTS:
		for part in CARD_PARTS[type]:
			var q: Dictionary = part.duplicate()
			q["type"] = type
			PART_BY_ID[part.id] = q
	STARTER_PARTS = d.get("starter_parts", [])


func moduleSlot(id) -> String:
	return str(MODULE_SLOT.get(id, "core"))


# ---------------------------------------------------------------- helpers
## JS-like number to string (integers without ".0").
func _n(x) -> String:
	var f: float = float(x)
	if absf(f) < 1e15 and is_equal_approx(f, roundf(f)):
		return str(int(roundf(f)))
	return str(f)


func _f(x, digits: int) -> String:
	return ("%." + str(digits) + "f") % float(x)


func _part(id) -> Dictionary:
	if id == null:
		return {}
	return PART_BY_ID.get(id, {})


# ---------------------------------------------------------------- modules
func module_desc(id: String, lv: int) -> String:
	match id:
		"pulse": return "弾ダメージ +" + _n(lv * 4) + "%"
		"shell": return "最大HP +" + _n(lv * 7)
		"vector": return "移動速度 +" + _n(lv * 2.5) + "%"
		"collector": return "回収範囲 +" + _n(lv * 15)
		"rail": return "貫通 +1 / ダメージ +" + _n(lv * 3) + "%"
		"crimson": return "HP吸収 +" + _f(lv * .45, 2) + "%"
		"reactor": return "連射速度 +" + _n(lv * 4) + "%"
		"fortune": return "開始時に希少共鳴 +" + _n(min(2, ceili(lv / 2.0)))
		"nova": return "撃破爆発率 " + _n(10 + lv * 5) + "%で開始"
		"oracle": return "クリ率 +" + _n(lv * 4) + "% / クリ倍率 +" + _f(lv * .1, 1)
		"dronecore": return "ドローン1機 / 威力 +" + _n(lv * 18) + "%"
		"chronos": return "ダッシュCD -" + _n(min(40, lv * 8)) + "%"
		"sovereign": return "ダメージ +" + _n(lv * 7) + "% / クリ率 +" + _n(lv * 5) + "%"
		"mirrorcore": return "跳弾 +" + _n(min(2, ceili(lv / 3.0))) + " / 跳弾威力 +" + _n(lv * 4) + "%"
		"seeker": return "誘導 " + _n(24 + lv * 8) + "% / 予測照準 / 弾速 +" + _n(lv * 4) + "%"
		"prismcore": return "発射数 +" + _n(min(3, lv)) + " / 跳弾 +2 / 連射 +" + _n(lv * 8) + "%"
		"aegis": return "開始Shield +" + _n(ceili(lv / 2.0)) + " / HP +" + _n(lv * 5)
		"nanoframe": return "毎秒回復 +" + _f(lv * .35, 2) + " / 被ダメ -" + _n(lv * 3) + "%"
		"voidskin": return "HP +" + _n(lv * 10) + " / 被ダメ -" + _n(min(32, lv * 6)) + "%"
		"swarmdrive": return "Drone連射 +" + _n(lv * 12) + "% / 索敵 +" + _n(lv * 55)
		"phasecollector": return "回収範囲 +" + _n(lv * 85) + (" / 全域回収" if lv >= 4 else "")
		"swarmmind": return "Drone +" + _n(min(2, lv)) + " / 火力 +" + _n(lv * 25) + "% / 完全追尾"
		"capacitor": return "ビーム威力 +" + _n(lv * 9) + "% / チャージ効率 +" + _n(lv * 8) + "%"
		"prism_lens": return "射撃中4秒ごとにチャージ光線。威力 " + _n(roundi((1 + lv * .32) * 100)) + "% / 貫通"
		"comet_core": return "本体で6体撃破ごとに彗星砲撃。威力 " + _n(roundi((1 + lv * .45) * 100)) + "% / 半径155"
		"thunder_heart": return "射撃中3秒ごとに3体へ連鎖雷。1体 " + _n(roundi((.6 + lv * .28) * 100)) + "%ダメージ"
		"reactive_plate": return "シールド消費時/被弾時に全周8発の反撃。1発 " + _n(roundi((.2 + lv * .07) * 100)) + "% / 再発動2.8秒"
		"cryo_frame": return "被弾時に凍結波。威力 " + _n(roundi((.8 + lv * .3) * 100)) + "% / 60%減速 / 再発動4秒"
		"ember_shell": return "近くの敵へ2秒ごとに熱波。威力 " + _n(roundi((.25 + lv * .1) * 100)) + "% / 半径180"
		"bastion_frame": return "スキル使用時、2.5秒のGuard。軽減" + _n(20 + lv * 4) + "% / 再発動5秒 / スキル出力+" + _n(lv * 5) + "%"
		"iondrive": return "ダッシュ地点に遅延爆発。威力 " + _n(roundi((1 + lv * .24) * 100)) + "% / 半径145"
		"overclock_drive": return "チャージ効率 +" + _n(lv * 10) + "% / スキル再使用効率 +" + _n(lv * 7) + "%"
		"relay_drive": return "射撃中3.5秒ごとに専用誘導弾2発。1発 " + _n(roundi((.4 + lv * .12) * 100)) + "%"
		"orbital_drive": return "周囲を回る刃4枚。接触で" + _n(roundi((.25 + lv * .1) * 100)) + "%ダメージ / 同じ敵は0.3秒間隔"
	return ""


## Applies module `id` at level `lv` to player dictionary `p`.
func module_apply(id: String, p: Dictionary, lv: int) -> void:
	match id:
		"pulse": p.damage *= 1 + lv * .04
		"shell":
			p.maxHp += lv * 7
			p.hp += lv * 7
		"vector": p.speed *= 1 + lv * .025
		"collector": p.magnet += lv * 15
		"rail":
			p.pierce += 1
			p.damage *= 1 + lv * .03
		"crimson": p.lifesteal += lv * .0045
		"reactor": p.fireRate *= 1 + lv * .04
		"fortune": p.rarityCharge += min(2, ceili(lv / 2.0))
		"nova":
			p.explosiveChance = maxf(p.explosiveChance, .10 + lv * .05)
			p.explosiveDamage = maxf(p.explosiveDamage, .9)
		"oracle":
			p.crit = minf(1, p.crit + lv * .04)
			p.critMult += lv * .1
		"dronecore":
			p.droneCount += 1
			p.droneDamage *= 1 + lv * .18
		"chronos": p.dashCooldown *= 1 - minf(.40, lv * .08)
		"sovereign":
			p.damage *= 1 + lv * .07
			p.crit = minf(1, p.crit + lv * .05)
		"mirrorcore":
			p.bulletBounces += min(2, ceili(lv / 3.0))
			p.bounceDamage *= 1 + lv * .04
		"seeker":
			p.homing = maxf(p.homing, .24 + lv * .08)
			p.homingRange = maxf(p.homingRange, 820 + lv * 90)
			p.homingLead = maxf(p.homingLead, .82)
			p.homingActivationDist = minf(p.homingActivationDist, 95)
			p.bulletSpeed *= 1 + lv * .04
		"prismcore":
			p.multishot = min(17, p.multishot + min(3, lv))
			p.bulletBounces += 2
			p.fireRate = minf(42, p.fireRate * (1 + lv * .08))
		"aegis":
			p.shieldHits += ceili(lv / 2.0)
			p.maxHp += lv * 5
			p.hp += lv * 5
		"nanoframe":
			p.regen += lv * .35
			p.armor = 1 - (1 - p.armor) * (1 - minf(.22, lv * .03))
		"voidskin":
			p.maxHp += lv * 10
			p.hp += lv * 10
			p.armor = 1 - (1 - p.armor) * (1 - minf(.32, lv * .06))
		"swarmdrive":
			p.droneRate *= 1 + lv * .12
			p.droneRange += lv * 55
		"phasecollector":
			p.magnet += lv * 85
			if lv >= 4:
				p.globalPickup = true
		"swarmmind":
			p.droneCount += min(2, lv)
			p.droneDamage *= 1 + lv * .25
			p.droneRate *= 1 + lv * .18
			p.droneRange = 1600
			p.dronePierce += 1
			p.droneTracking = true
		"capacitor":
			p.beamPower *= 1 + lv * .09
			p.chargeEfficiency += lv * .08
		"prism_lens": p.gearEffects.prism = lv
		"comet_core": p.gearEffects.comet = lv
		"thunder_heart": p.gearEffects.thunder = lv
		"reactive_plate": p.gearEffects.reactive = lv
		"cryo_frame": p.gearEffects.cryo = lv
		"ember_shell": p.gearEffects.ember = lv
		"bastion_frame":
			p.gearEffects.bastion = lv
			p.activePower *= 1 + lv * .05
		"iondrive": p.gearEffects.ion = lv
		"overclock_drive":
			p.chargeEfficiency += lv * .10
			p.activeHaste += lv * .07
		"relay_drive": p.gearEffects.relay = lv
		"orbital_drive": p.gearEffects.orbit = lv


# ---------------------------------------------------------------- card syntax
func cardRarity(cost) -> String:
	return "LEGENDARY" if cost >= 12 else "EPIC" if cost >= 8 else "RARE" if cost >= 5 else "COMMON"


func cardCost(parts: Dictionary) -> int:
	var s: float = 0.0
	for k in ["trigger", "condition", "chance", "effect", "power"]:
		s += float(_part(parts.get(k)).get("cost", 0))
	return int(maxf(0.0, s))


func _replace_first(s: String, what: String, with_: String) -> String:
	var i := s.find(what)
	if i < 0:
		return s
	return s.substr(0, i) + with_ + s.substr(i + what.length())


func describeCard(card: Dictionary) -> String:
	var t: String = _part(card.get("trigger")).get("text", "")
	var c: String = _part(card.get("condition")).get("text", "")
	var ch: String = _part(card.get("chance")).get("text", "")
	var effect = card.get("effect")
	var e: String = _part(effect).get("text", "")
	var power: float = float(_part(card.get("power")).get("value", 1.0))
	var p: String = _part(card.get("power")).get("text", "")
	if effect == "shield":
		var hits: int = maxi(1, ceili(power * 1.7))
		e = str(hits) + "回の攻撃を完全無効化するシールドを得る"
		p = "1回で+" + str(hits) + " / 再発動1.3秒"
	elif effect == "guard":
		e = _f(1.4 * power, 1) + "秒間、被ダメージを" + str(roundi(minf(.72, .30 + .16 * power) * 100)) + "%軽減する"
		p = ""
	elif effect == "radial":
		e = "全方向へ" + str(maxi(6, roundi(6 + power * 3))) + "発の特殊弾を放つ"
	elif effect == "barrage":
		e = "近い敵へ" + str(maxi(3, roundi(2 + power * 2))) + "発の追撃弾幕を放つ"
	var out: String = t + "、" + (c + "、" if c != "" else "") + ch + e + ("（" + p + "）" if p != "" else "") + "。" + (" 再発動2.8秒。" if effect == "barrier" else "") + " 本体由来の攻撃で発動。"
	return _replace_first(out, "、、", "、")


func generatedCardName(card: Dictionary) -> String:
	var effs := {"heal": "紅の回路", "shield": "多層装甲", "guard": "防壁", "reflect": "反照", "explode": "虚無爆裂", "lightning": "雷鎖", "frostnova": "氷界", "knockpulse": "衝撃環", "radial": "星散", "barrage": "追撃雨", "barrier": "絶対障壁", "dashreset": "時空跳躍", "resonance": "共鳴炉", "ricochet": "鏡界弾", "homing": "追跡弾", "droneboost": "群体加速", "globalcollect": "事象回収", "bulletclear": "反転障壁", "chargebeam": "蓄光砲", "meteor": "彗星", "arcgrid": "雷網", "orbitblade": "旋回刃", "gravitywell": "重力井戸", "nova_shard": "光片"}
	var trigs := {"on_kill": "処刑", "on_hit": "刻印", "on_crit": "断罪", "on_dash": "位相", "on_damage": "反逆", "on_wave": "開幕", "on_shield_break": "破砕", "on_low_hp": "背水", "on_level": "昇華", "on_pickup": "収集", "on_boss_spawn": "迎撃", "on_combo": "連奏", "on_pierce": "貫徹", "on_active": "共鳴", "on_charge": "充填"}
	var prefixes := {"COMMON": "", "RARE": "強化型 ", "EPIC": "超越型 ", "LEGENDARY": "《終極》"}
	var eff: String = effs.get(card.get("effect"), "未知構文")
	var trig: String = trigs.get(card.get("trigger"), "変異")
	var prefix: String = prefixes.get(card.get("rarity"), "")
	return prefix + trig + eff


func validCardRecipe(c) -> bool:
	if c == null or typeof(c) != TYPE_DICTIONARY:
		return false
	for k in CARD_FIELDS:
		if _part(c.get(k)).get("type", "") != k:
			return false
	return true


func cardSignature(card):
	if not validCardRecipe(card):
		return null
	var arr: Array = []
	for k in CARD_FIELDS:
		arr.append(card.get(k))
	return JSON.stringify(arr)


func findDuplicateCard(card):
	var sig = cardSignature(card)
	if sig == null:
		return null
	var cards: Array = Meta.meta.get("cards", []) if Meta.meta != null else []
	for c in cards:
		if validCardRecipe(c) and cardSignature(c) == sig:
			return c
	return null


func recipeIssue(c) -> String:
	if not validCardRecipe(c):
		return "各欄から構文を1つずつ選択してください。"
	if c.get("condition") in ["elite", "boss", "enemy_low"] and not (c.get("trigger") in ["on_hit", "on_kill", "on_crit", "on_pierce", "on_damage", "on_low_hp"]):
		return "対象の敵が存在しないトリガーです。「対象が…」条件を変更してください。"
	return ""


func cardCooldown(card: Dictionary) -> float:
	var base := {"barrier": 2.8, "shield": 1.3, "chargebeam": 1.8, "meteor": 1.6, "arcgrid": 2.4, "orbitblade": 4.2, "gravitywell": 4.6, "nova_shard": 1.1}
	var eff = card.get("effect")
	if base.has(eff):
		return base[eff]
	return .25 if card.get("trigger") in ["on_hit", "on_crit", "on_pierce"] else .15


func _rand_base36(n: int) -> String:
	var chars := "0123456789abcdefghijklmnopqrstuvwxyz"
	var s := ""
	for i in n:
		s += chars[randi() % chars.length()]
	return s


func _truthy_str(v) -> String:
	if v == null or (typeof(v) == TYPE_STRING and v == "") or (typeof(v) == TYPE_BOOL and v == false) or ((typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and v == 0):
		return ""
	return str(v)


func normalizeCard(raw) -> Dictionary:
	var c: Dictionary = raw.duplicate() if typeof(raw) == TYPE_DICTIONARY else {}
	c["cost"] = cardCost(c)
	c["rarity"] = cardRarity(c.cost)
	var id := _truthy_str(c.get("id"))
	if id == "":
		id = _truthy_str(c.get("uid"))
	if id == "":
		id = "card_%d_%s" % [int(Time.get_unix_time_from_system() * 1000), _rand_base36(7)]
	c["id"] = id
	var nm := _truthy_str(c.get("name")).strip_edges()
	if nm == "":
		nm = generatedCardName(c).strip_edges()
	nm = nm.substr(0, 64)
	if nm == "":
		nm = generatedCardName(c)
	c["name"] = nm
	c["favorite"] = bool(c.get("favorite", false)) if c.get("favorite") != null else false
	return c


func _ctx_enemy(ctx: Dictionary):
	var e = ctx.get("enemy")
	return e if typeof(e) == TYPE_DICTIONARY else null


func conditionPass(card: Dictionary, ctx: Dictionary = {}) -> bool:
	var player: Dictionary = Game.player
	var en = _ctx_enemy(ctx)
	match card.get("condition"):
		"hp35": return player.hp / player.maxHp <= .35
		"hp70": return player.hp / player.maxHp >= .70
		"elite": return en != null and bool(en.get("elite", false))
		"boss": return en != null and bool(en.get("boss", false))
		"combo8": return Game.comboKills >= 8
		"shieldless": return float(player.get("shieldHits", 0)) <= 0
		"nearby5":
			var n := 0
			for e in Game.enemies:
				if not e.get("_dead", false):
					var dx: float = e.x - player.x
					var dy: float = e.y - player.y
					if sqrt(dx * dx + dy * dy) < 260:
						n += 1
			return n >= 5
		"enemy_low": return en != null and en.hp / en.maxHp <= .30
		"fullhp": return player.hp / player.maxHp >= .90
		"bossfight": return bool(Game.bossAlive)
		"shielded": return player.shieldHits > 0
		"dashready": return player.dashReady >= 1
		"moving": return sqrt(player.vx * player.vx + player.vy * player.vy) > 35
		"many_enemies":
			var n2 := 0
			for e in Game.enemies:
				if not e.get("_dead", false):
					n2 += 1
			return n2 >= 20
	return true


func nearestEnemy(x: float, y: float):
	var target = null
	var best: float = 260.0 * 260.0
	for e in Game.enemies:
		if e.get("_dead", false):
			continue
		var d: float = (e.x - x) * (e.x - x) + (e.y - y) * (e.y - y)
		if d < best:
			best = d
			target = e
	return target


func emitCardTrigger(trigger: String, ctx: Dictionary = {}) -> void:
	var bullet = ctx.get("bullet")
	var bullet_block := false
	if typeof(bullet) == TYPE_DICTIONARY:
		bullet_block = bool(bullet.get("fromDrone", false)) or bool(bullet.get("noProc", false))
	if Game.runSettled or Game.state != "playing" or cardProcDepth > 1 or runLoadoutCards.is_empty() or bullet_block:
		return
	cardProcDepth += 1
	var player: Dictionary = Game.player
	for card in runLoadoutCards:
		if card == null or card.get("trigger") != trigger or not conditionPass(card, ctx):
			continue
		var id = card.get("id")
		if float(Game.cardCooldowns.get(id, 0)) > Game.time:
			continue
		var chance: float = float(_part(card.get("chance")).get("value", 1.0))
		if randf() > chance:
			continue
		var cd: float = cardCooldown(card)
		Game.cardCooldowns[id] = Game.time + cd
		var power: float = float(_part(card.get("power")).get("value", 1.0))
		var anchor = _ctx_enemy(ctx)
		var e = anchor if (anchor != null and not anchor.get("_dead", false)) else null
		var eff = card.get("effect")
		if eff == "heal":
			Game.healPlayer(player.maxHp * .025 * power, "card")
		elif eff == "shield":
			Game.gainShield(maxi(1, ceili(power * 1.7)))
		elif eff == "guard":
			player.guardTimer = maxf(player.get("guardTimer", 0), 1.4 * power)
			player.guardReduction = maxf(player.get("guardReduction", 0), minf(.72, .30 + .16 * power))
		elif eff == "reflect":
			var dmg: float = maxf(player.damage * .7 * power, float(ctx.get("damage", 0)) * 1.5 * power)
			Combat.explode(player.x, player.y, dmg, 95 + 18 * power, 190, true)
		elif eff == "explode":
			var x: float = anchor.x if anchor != null else player.x
			var y: float = anchor.y if anchor != null else player.y
			Combat.explode(x, y, player.damage * .85 * power, 72 + 18 * power, 300, true)
		elif eff == "lightning":
			var origin = e if e != null else nearestEnemy(player.x, player.y)
			if origin != null:
				Combat.chainLightning(origin, player.damage * .65 * power, maxi(1, floori(power + 1)))
		elif eff == "frostnova":
			var radius: float = 145 + 25 * power
			for foe in Game.enemies:
				if foe.get("_dead", false):
					continue
				var dx: float = foe.x - player.x
				var dy: float = foe.y - player.y
				if sqrt(dx * dx + dy * dy) <= radius:
					foe.slow = maxf(foe.get("slow", 0), 1.2 * power)
					foe.slowPower = maxf(foe.get("slowPower", 0), minf(.78, .42 + .12 * power))
			if Game.rings.size() < Game.PERF.maxRings:
				Game.rings.append({"x": player.x, "y": player.y, "r": 18, "life": .32, "max": .32, "hue": 195})
		elif eff == "knockpulse":
			var radius2: float = 130 + 28 * power
			for foe in Game.enemies:
				if foe.get("_dead", false):
					continue
				var dx: float = foe.x - player.x
				var dy: float = foe.y - player.y
				var d: float = sqrt(dx * dx + dy * dy)
				if d == 0.0:
					d = 1.0
				if d <= radius2:
					foe.vx += dx / d * 180 * power
					foe.vy += dy / d * 180 * power
					Enemies.dealEnemyDamage(foe, player.damage * .28 * power, "other")
			if Game.rings.size() < Game.PERF.maxRings:
				Game.rings.append({"x": player.x, "y": player.y, "r": 15, "life": .28, "max": .28, "hue": 185})
		elif eff == "radial":
			var count: int = maxi(6, roundi(6 + power * 3))
			for i in count:
				Combat.shoot(player.x, player.y, float(i) / count * TAU, player.damage * .55 * power, {"silent": true, "source": "card", "noProc": true, "pierce": 0})
		elif eff == "barrage":
			var target = e if e != null else nearestEnemy(player.x, player.y)
			if target != null:
				var count2: int = maxi(3, roundi(2 + power * 2))
				var base: float = atan2(target.y - player.y, target.x - player.x)
				for i in count2:
					Combat.shoot(player.x, player.y, base + U.rand(-.13, .13), player.damage * .42 * power, {"silent": true, "source": "card", "noProc": true, "pierce": 0, "speed": player.bulletSpeed * .9})
		elif eff == "barrier":
			Game.gainBarrier(.45 * power)
		elif eff == "dashreset":
			player.dashReady = 1
		elif eff == "resonance":
			Game.addXP(maxi(1, floori(2 * power)))
		elif eff == "ricochet":
			var count3: int = maxi(4, roundi(3 + power * 2))
			for i in count3:
				Combat.shoot(player.x, player.y, float(i) / count3 * TAU, player.damage * .45 * power, {"silent": true, "source": "card", "noProc": true, "pierce": 0, "bounces": maxi(1, floori(power))})
		elif eff == "homing":
			var count4: int = maxi(2, roundi(1 + power))
			for i in count4:
				var t = Combat.nearestEnemyInRange(player.x, player.y, 1400)
				var a: float = atan2(t.y - player.y, t.x - player.x) if t != null else float(i) / count4 * TAU
				Combat.shoot(player.x, player.y, a + U.rand(-.08, .08), player.damage * .5 * power, {"silent": true, "source": "card", "noProc": true, "homing": .65, "homingActivationDist": 80, "homingRange": 1500, "homingLead": .95, "bounces": 1})
		elif eff == "droneboost":
			player.droneOverdrive = maxf(player.get("droneOverdrive", 0), 2.2 * power)
			if player.droneCount == 0:
				player.droneCount = 1
				Enemies.syncDrones()
		elif eff == "globalcollect":
			var loot: Array = Game.gems
			Game.gems = []
			for g in loot:
				Combat.collectGem(g)
		elif eff == "bulletclear":
			var snapshot: Array = []
			for b in Game.bullets:
				if b != null and b.get("enemy", false) and not b.get("_dead", false):
					snapshot.append(b)
			var retaliate_max: int = roundi(3 + power * 2)
			var converted := 0
			for eb in snapshot:
				if eb.get("_dead", false):
					continue
				eb._dead = true
				converted += 1
				if converted <= retaliate_max:
					var t2 = nearestEnemy(player.x, player.y)
					if t2 != null:
						Combat.shoot(player.x, player.y, atan2(t2.y - player.y, t2.x - player.x), player.damage * .55 * power, {"silent": true, "source": "card", "noProc": true, "bounces": 1})
		elif eff in ["chargebeam", "meteor", "arcgrid", "orbitblade", "gravitywell", "nova_shard"]:
			Combat.castPattern(eff, power, "other", e)
		if Game.texts.size() < Game.PERF.maxTexts:
			var rar = card.get("rarity")
			Game.texts.append({"x": player.x, "y": player.y - 42, "text": card.get("name", ""), "life": .55, "max": .55, "hue": 42 if rar == "LEGENDARY" else 280 if rar == "EPIC" else 190, "size": 10})
	cardProcDepth -= 1


func searchKey(value) -> String:
	var s := ("" if value == null else str(value)).to_lower()
	var out := ""
	for i in s.length():
		var cp := s.unicode_at(i)
		if cp >= 0x30A1 and cp <= 0x30F6:
			cp -= 0x60
		out += char(cp)
	var parts := out.split(" ", false)
	var clean: PackedStringArray = []
	for part in parts:
		for q in part.split("\t", false):
			if q != "":
				clean.append(q)
	return " ".join(clean)


func nameMatches(name: String, query: String) -> bool:
	var hay := searchKey(name)
	for q in searchKey(query).split(" ", false):
		if not hay.contains(q):
			return false
	return true


func libraryNotice(message: String, kind: String = "ok") -> void:
	UI.hook("libraryNotice", [message, kind])


func forgeNotice(message: String, kind: String = "ok") -> void:
	UI.hook("forgeNotice", [message, kind])


# ---------------------------------------------------------------- in-run skills
func _tiers(descs: Array) -> Dictionary:
	return {"COMMON": {"desc": descs[0]}, "RARE": {"desc": descs[1]}, "EPIC": {"desc": descs[2]}}


func _add_skill(id: String, name: String, icon: String, descs: Array, has_req: bool = false) -> void:
	skills.append({"id": id, "icon": icon, "name": name, "tiers": _tiers(descs), "req": has_req})


func addRunFamily(id: String, name: String, icon: String, descs: Array, has_req: bool = false) -> void:
	## Apply behaviour for the families is in skill_apply(); this registers display data.
	_add_skill(id, name, icon, descs, has_req)


func _build_skills() -> void:
	skills = []
	_add_skill("damage", "オーバーチャージ", "✦", ["弾ダメージ +18%", "弾ダメージ +38%、弾速 +8%", "弾ダメージ +80%、弾サイズ +1。火力特化の最終形。"])
	_add_skill("firerate", "ハイパーフィード", "⌁", ["連射速度 +15%", "連射速度 +32%", "連射速度 +60%、弾速 +20%。強化を重ねても伸び続ける。"])
	_add_skill("crit", "弱点解析", "◇", ["クリティカル率 +12%", "クリティカル率 +28%、倍率 +0.35倍", "クリティカル率を100%にする。常時クリティカル。"])
	_add_skill("lifesteal", "吸収コード", "♥", ["与えたダメージの2%をHP吸収。回復効率補正を受ける。", "HP吸収を4.5%へ。撃破時に最大HPの0.3%回復。", "HP吸収を7.5%へ。撃破時に最大HPの0.6%回復。"])
	_add_skill("explosive", "ヴォイド爆発", "✹", ["撃破時25%で爆発。周囲へ70%ダメージ。", "撃破時60%で大型爆発。周囲へ100%ダメージ。", "撃破時100%で爆発。範囲110、140%ダメージ。"])
	_add_skill("chain", "連鎖雷撃", "ϟ", ["クリティカル時25%で1体へ雷撃が連鎖。", "発動率60%。最大2体へ連鎖し、威力も上昇。", "クリティカル時100%発動。最大4体へ強烈に連鎖。"])
	_add_skill("frost", "冷却弾", "❄", ["命中時30%で敵を45%減速。", "命中時65%で敵を60%減速。効果時間も延長。", "命中時100%で敵を72%減速。ボスにも有効。"])
	_add_skill("multishot", "分裂射撃", "⋰", ["発射弾数 +1", "発射弾数 +2。拡散を少し抑える。", "発射弾数 +4。弾幕をさらに広げる。"])
	_add_skill("pierce", "ゴースト弾", "⇢", ["貫通数 +1", "貫通数 +2。貫通後の威力減衰を緩和。", "貫通数 +5。群れを一直線に切り裂く。"])
	_add_skill("drone", "戦闘ドローン", "◎", ["Drone +1 / 索敵 +120。本体攻撃力の18%など一部数値のみ継承。", "Drone +2 / 専用火力 +25% / 連射 +20% / 専用貫通 +1。", "Drone +3 / 火力 +40% / 連射 +35% / 追跡射撃。吸血・命中カード・爆発は継承しない。"])
	_add_skill("ricochet", "リコシェ・コア", "↗", ["弾が敵・壁で1回反射。", "反射 +2、反射後ダメージ +15%。", "反射 +4、反射後ダメージ +35%。群れの中を連鎖する。"])
	_add_skill("homing", "シーカー弾", "⌖", ["約115距離を直進後、近い敵へロック。移動先を予測して追尾。", "約90距離後に起動。追尾55%、索敵1100、予測精度UP。弾速 +10%。", "約65距離後に起動。追尾90%、全画面級索敵。最寄り敵を強く予測追尾。"])
	_add_skill("dash", "位相ダッシュ", "◫", ["ダッシュ再使用時間 -15%", "再使用時間 -30%。ダッシュ時に小型衝撃波。", "再使用時間 -45%。ダッシュ時に160%ダメージの衝撃波。"])
	_add_skill("vitality", "ハードライト装甲", "⬡", ["最大HP +20、HPを10回復。", "最大HP +45、HPを20回復。", "最大HP +80、最大HPの30%を回復。"])
	_add_skill("speed", "フェイズレッグ", "➤", ["移動速度 +10%", "移動速度 +22%、ダッシュ再使用時間 -10%", "移動速度 +38%、ダッシュ再使用時間 -20%。"])
	_add_skill("armor", "耐衝撃メッシュ", "▣", ["被ダメージ 8%軽減", "さらに16%軽減。", "さらに28%軽減。高耐久ビルドの中核。"])
	_add_skill("regen", "自己修復", "+", ["毎秒HP +0.45回復。", "毎秒HP +1.1回復。", "毎秒HP +2.2回復、最大HP +30。"])
	_add_skill("magnet", "重力井戸", "◉", ["経験値吸引範囲 +90", "経験値吸引範囲 +190", "マップ全体の経験値を常時回収。XP獲得 +12%。"])
	_add_skill("echo", "残響弾", "≋", ["射撃時15%で追加射撃が発生。威力50%。", "発動率45%、追加射撃の威力75%。", "射撃時100%で残響射撃。追加射撃も100%威力。"])
	_add_skill("execute", "処刑プロトコル", "☠", ["HP20%以下の敵へのダメージ +40%", "HP28%以下の敵へのダメージ +90%", "通常敵はHP22%以下で即死。ボスには+150%ダメージ。"])
	_add_skill("berserk", "レッドゾーン", "▲", ["HP35%以下で攻撃力 +20%", "HP35%以下で攻撃力 +45%", "HP35%以下で攻撃力 +85%。瀕死ほど危険で強い。"])

	uniqueEpics = [
		{"id": "singularity", "icon": "◌", "name": "特異点崩壊", "maxRank": 1, "desc": "8体撃破するたび、撃破地点に大規模な重力爆発を発生。"},
		{"id": "phoenix", "icon": "♨", "name": "フェニックス・コア", "maxRank": 1, "desc": "致死ダメージを1度だけ無効化し、HP30%で復活。周囲も吹き飛ばす。"},
		{"id": "bloodmoon", "icon": "☾", "name": "ブラッドムーン", "maxRank": 1, "desc": "HP吸収を最低9%へ。撃破回復を最大HPの0.8%へ強化。回復効率補正は受ける。"},
		{"id": "tactical_esp", "icon": "⌖", "name": "TACTICAL ESP", "maxRank": 1, "desc": "ミニマップに全敵をESP表示。通常・Elite・Bossを色分けし、画面外のElite/Boss方向も追跡。"},
	]

	legendarySkills = [
		{"id": "event_horizon", "icon": "◉", "name": "EVENT HORIZON", "desc": "マップ全体の経験値を常時回収。取得XP +30%。"},
		{"id": "swarm_intelligence", "icon": "⌘", "name": "SWARM INTELLIGENCE", "desc": "Drone +4 / 索敵2000 / 追跡射撃 / 連射+35% / 専用火力+40% / 専用貫通+1。"},
		{"id": "mirror_storm", "icon": "↗", "name": "MIRROR STORM", "desc": "全弾が追加6回反射。反射するたび威力が増える。"},
		{"id": "infinite_magazine", "icon": "∞", "name": "INFINITE MAGAZINE", "desc": "発射数 +4、連射×1.8、弾速+25%。高密度射撃用の弾管理を解放。"},
		{"id": "chain_reaction", "icon": "✹", "name": "CHAIN REACTION", "desc": "撃破爆発100%。爆発撃破も連鎖し、範囲・威力が大幅上昇。"},
		{"id": "predator_guidance", "icon": "⌖", "name": "PREDATOR GUIDANCE", "desc": "シーカーが約45距離後に起動。最寄り敵を2400範囲でロックし、未来位置を強予測して急旋回する。"},
		{"id": "omniscience", "icon": "◈", "name": "OMNISCIENCE", "desc": "ESPを完全解放。全敵・Elite・Boss・経験値をミニマップ表示し、画面外の危険方向も全域追跡。"},
	]

	addRunFamily("scorch", "灼熱弾", "♨", ["本体弾が2.5秒間の燃焼を付与。毎秒、本体攻撃力の20%。", "燃焼の毎秒ダメージを45%へ。ドローンには継承されない。", "燃焼の毎秒ダメージを80%へ。硬い敵を継続的に削る。"])
	addRunFamily("fracture_round", "装甲破砕弾", "▧", ["本体弾の命中で破砕を蓄積。蓄積量に応じて敵の被ダメージ上昇。", "1ヒットの破砕蓄積を2へ。長期戦ほど効果が増える。", "1ヒットの破砕蓄積を3へ。護衛機・ボスへの集中射撃を強化。"])
	addRunFamily("boss_hunter", "巨体狩り", "◇", ["本体・アクティブ・追加効果のボスダメージ +15%。", "さらにボスダメージ +30%。ドローンには継承されない。", "さらにボスダメージ +50%。"])
	addRunFamily("purification", "抗侵食回路", "✚", ["デバフ耐性 +25%。封印・回復阻害の時間 = 基礎時間 ÷ (1+耐性)。", "デバフ耐性をさらに +40%。無効化ではなく効果時間を短縮。", "デバフ耐性をさらに +70%。"])
	addRunFamily("ability_amplifier", "スキル出力増幅", "⚡", ["アクティブスキルの威力・回復量を15%強化。", "アクティブスキルの出力をさらに30%強化。", "アクティブスキルの出力をさらに50%強化。"])
	addRunFamily("ability_cycler", "高速再装填", "◫", ["スキル再使用効率 +12%。効率に応じてCDが短縮。", "再使用効率をさらに +22%。", "再使用効率をさらに +40%。CDは徐々に短縮し続ける。"])
	addRunFamily("drone_training", "補助火器訓練", "◎", ["ドローン専用火力 +15%。本体の命中効果は複製しない。", "ドローン専用火力 +25%、専用連射 +10%。", "ドローン専用火力 +40%、専用連射 +20%。"], true)
	addRunFamily("pierce_amp", "加速貫通弾", "⇢", ["本体弾が貫通する際の威力倍率に +6%。", "貫通威力補正をさらに +10%。", "貫通威力補正をさらに +16%。貫通を重ねると高火力へ。"])
	addRunFamily("xp_scanner", "学習アクセラレータ", "□", ["取得XP +10%。カードの取得機会を増やす。", "取得XPをさらに +18%。", "取得XPをさらに +28%。"])
	legendarySkills.append({"id": "reactor_master", "icon": "⚡", "name": "REACTOR MASTER", "desc": "アクティブスキル出力 ×1.8 / 再使用効率 +40%。スキル主軸の最終形。"})
	legendarySkills.append({"id": "thermal_overload", "icon": "♨", "name": "THERMAL OVERLOAD", "desc": "燃焼威力 ×2.2 / 本体のボスダメージ +35%。硬い敵を焼き切る。"})
	legendarySkills.append({"id": "auxiliary_network", "icon": "⌘", "name": "AUXILIARY NETWORK", "desc": "ドローン専用火力 +40% / 本体攻撃力の継承を18%→24%へ。カード効果は継承しない。"})

	addRunFamily("prism_barrel", "蓄光バレル", "⇢", ["射撃中3.6秒ごとに、0.55秒チャージ後に70%威力の貫通光線。本体のみ。", "自動光線を120%威力へ。ビーム威力 +10%。", "自動光線を200%威力へ。ビーム威力 +25%。"])
	addRunFamily("comet_rain", "彗星誘導", "☄", ["本体で9体撃破ごとに予告砲撃。威力100%。", "本体で7体撃破ごとに予告砲撃。威力160%。", "本体で5体撃破ごとに予告砲撃。威力250%。"])
	addRunFamily("lightning_halo", "雷光オーラ", "ϟ", ["1.7秒ごとに近い3体へ35%の連鎖雷。本体由来効果は誘発しない。", "連鎖雷を65%威力へ。", "連鎖雷を110%威力へ。"])
	addRunFamily("charge_coil", "充填コイル", "◫", ["チャージ効率 +15%。ビーム威力 +10%。", "チャージ効率をさらに +30%。ビーム威力 +20%。", "チャージ効率をさらに +50%。ビーム威力 +35%。"])
	addRunFamily("satellite_blades", "旋回する光刃", "✥", ["周囲に2枚の光刃。接触すると45%ダメージ。", "光刃を3枚・70%威力へ。", "光刃を4枚・110%威力へ。同じ敵への再ヒットは0.3秒間隔。"])
	legendarySkills.append({"id": "solar_crown", "icon": "☀", "name": "SOLAR CROWN", "desc": "本体自動光線とアクティブビームに左右2本ずつ追加。ビーム威力 ×1.4。"})
	legendarySkills.append({"id": "falling_sky", "icon": "☄", "name": "FALLING SKY", "desc": "撃破による彗星砲撃が3連発に進化。彗星威力 ×1.5。"})


func _any_active_slot() -> bool:
	for s in Game.activeSlots:
		if s:
			return true
	return false


func _active_slot_is(ids: Array) -> bool:
	for s in Game.activeSlots:
		if s and typeof(s) == TYPE_DICTIONARY and s.get("id") in ids:
			return true
	return false


## Requirement check of an in-run skill family (only drone_training has one).
func skill_req(id: String) -> bool:
	if id == "drone_training":
		return Game.player.droneCount > 0
	return true


func legendary_requires(id: String) -> bool:
	var p: Dictionary = Game.player
	var ranks: Dictionary = p.skillRanks
	match id:
		"event_horizon": return true
		"swarm_intelligence": return p.droneCount >= 2 or ranks.get("drone", 0) >= 2
		"mirror_storm": return p.bulletBounces >= 1 or ranks.get("ricochet", 0) >= 1
		"infinite_magazine": return true
		"chain_reaction": return p.explosiveChance > .2
		"predator_guidance": return p.homing >= .45 or ranks.get("homing", 0) >= 2
		"omniscience": return bool(p.get("mapEsp", false))
		"reactor_master": return _any_active_slot()
		"thermal_overload": return p.burnPower > 0
		"auxiliary_network": return p.droneCount > 0
		"solar_crown": return p.prismPower > 0 or _active_slot_is(["lance", "prism"])
		"falling_sky": return p.cometPower > 0
	return false


func legendary_apply(id: String) -> void:
	var p: Dictionary = Game.player
	match id:
		"event_horizon":
			p.globalPickup = true
			p.xpMultiplier *= 1.30
		"swarm_intelligence":
			p.droneCount += 4
			p.droneRange = 2000
			p.droneTracking = true
			p.droneRate *= 1.35
			p.droneDamage *= 1.4
			p.dronePierce += 1
			Enemies.syncDrones()
		"mirror_storm":
			p.bulletBounces += 6
			p.bounceDamage *= 1.28
		"infinite_magazine":
			p.multishot += 4
			p.fireRate *= 1.8
			p.bulletSpeed *= 1.25
		"chain_reaction":
			p.explosiveChance = 1
			p.explosiveDamage = maxf(2, p.explosiveDamage * 1.6)
			p.explosiveRadius = maxf(145, p.explosiveRadius * 1.25)
			p.chainReaction = true
		"predator_guidance":
			p.homing = maxf(p.homing, 1.15)
			p.homingActivationDist = 45
			p.homingRange = 2400
			p.homingLead = 1.25
			p.homingTurnBoost = 1.55
		"omniscience":
			p.mapEsp = true
			p.mapEspAdvanced = true
		"reactor_master":
			p.activePower *= 1.8
			p.activeHaste += .4
		"thermal_overload":
			p.burnPower *= 2.2
			p.bossDamage += .35
		"auxiliary_network":
			p.droneDamage *= 1.4
			p.droneDamageTransfer = .24
		"solar_crown":
			p.beamBranches += 2
			p.beamPower *= 1.4
		"falling_sky":
			p.fallingSky = true
			p.cometPower *= 1.5


func unique_apply(id: String) -> void:
	var p: Dictionary = Game.player
	match id:
		"singularity": p.singularityEvery = 8
		"phoenix": p.phoenix = 1
		"bloodmoon":
			p.lifesteal = maxf(p.lifesteal, .09)
			p.killHeal = maxf(p.killHeal, .008)
		"tactical_esp": p.mapEsp = true


func endless_apply(id: String) -> void:
	var p: Dictionary = Game.player
	match id:
		"end_damage": p.damage *= 1.12
		"end_rate": p.fireRate *= 1.08
		"end_active":
			p.activePower *= 1.12
			p.activeHaste += .05
		"end_hp":
			p.maxHp += 25
			Game.healPlayer(10, "upgrade")
		"end_beam":
			p.beamPower *= 1.12
			p.chargeEfficiency += .08
		"end_drone":
			p.droneDamage *= 1.12
			p.droneRate *= 1.06
		"end_fleet":
			p.droneCount += 1
			Enemies.syncDrones()


## Applies tier `i` (0=COMMON,1=RARE,2=EPIC) of skill family `id` to Game.player.
func skill_apply(id: String, i: int) -> void:
	var p: Dictionary = Game.player
	match id:
		"damage":
			match i:
				0: p.damage *= 1.18
				1:
					p.damage *= 1.38
					p.bulletSpeed *= 1.08
				2:
					p.damage *= 1.8
					p.bulletSize = minf(8, p.bulletSize + 1)
		"firerate":
			match i:
				0: p.fireRate *= 1.15
				1: p.fireRate *= 1.32
				2:
					p.fireRate *= 1.6
					p.bulletSpeed *= 1.2
		"crit":
			match i:
				0: p.crit = minf(1, p.crit + .12)
				1:
					p.crit = minf(1, p.crit + .28)
					p.critMult += .35
				2:
					p.crit = 1
					p.critMult += .5
		"lifesteal":
			match i:
				0: p.lifesteal = maxf(p.lifesteal, .02)
				1:
					p.lifesteal = maxf(p.lifesteal, .045)
					p.killHeal = maxf(p.killHeal, .003)
				2:
					p.lifesteal = maxf(p.lifesteal, .075)
					p.killHeal = maxf(p.killHeal, .006)
		"explosive":
			match i:
				0:
					p.explosiveChance = maxf(p.explosiveChance, .25)
					p.explosiveDamage = maxf(p.explosiveDamage, .7)
				1:
					p.explosiveChance = maxf(p.explosiveChance, .60)
					p.explosiveDamage = maxf(p.explosiveDamage, 1)
					p.explosiveRadius = maxf(p.explosiveRadius, 90)
				2:
					p.explosiveChance = 1
					p.explosiveDamage = maxf(p.explosiveDamage, 1.4)
					p.explosiveRadius = maxf(p.explosiveRadius, 110)
		"chain":
			match i:
				0:
					p.chainChance = maxf(p.chainChance, .25)
					p.chainTargets = max(p.chainTargets, 1)
				1:
					p.chainChance = maxf(p.chainChance, .60)
					p.chainTargets = max(p.chainTargets, 2)
					p.chainDamage = maxf(p.chainDamage, .55)
				2:
					p.chainChance = 1
					p.chainTargets = max(p.chainTargets, 4)
					p.chainDamage = maxf(p.chainDamage, .72)
		"frost":
			match i:
				0:
					p.frostChance = maxf(p.frostChance, .30)
					p.frostStrength = maxf(p.frostStrength, .45)
				1:
					p.frostChance = maxf(p.frostChance, .65)
					p.frostStrength = maxf(p.frostStrength, .60)
					p.frostDuration = maxf(p.frostDuration, .9)
				2:
					p.frostChance = 1
					p.frostStrength = maxf(p.frostStrength, .72)
					p.frostDuration = maxf(p.frostDuration, 1.15)
		"multishot":
			match i:
				0:
					p.multishot += 1
					p.spread += .045
				1:
					p.multishot += 2
					p.spread += .055
				2:
					p.multishot += 4
					p.spread += .065
		"pierce":
			match i:
				0: p.pierce += 1
				1: p.pierce += 2
				2: p.pierce += 5
		"drone":
			match i:
				0:
					p.droneCount += 1
					p.droneRange += 120
				1:
					p.droneCount += 2
					p.droneDamage *= 1.25
					p.droneRate *= 1.2
					p.dronePierce += 1
				2:
					p.droneCount += 3
					p.droneDamage *= 1.4
					p.droneRate *= 1.35
					p.droneRange = 1800
					p.droneTracking = true
					p.dronePierce += 1
			Enemies.syncDrones()
		"ricochet":
			match i:
				0: p.bulletBounces += 1
				1:
					p.bulletBounces += 2
					p.bounceDamage *= 1.15
				2:
					p.bulletBounces += 4
					p.bounceDamage *= 1.35
		"homing":
			match i:
				0:
					p.homing = maxf(p.homing, .24)
					p.homingActivationDist = minf(p.homingActivationDist, 115)
					p.homingRange = maxf(p.homingRange, 760)
				1:
					p.homing = maxf(p.homing, .55)
					p.homingActivationDist = minf(p.homingActivationDist, 90)
					p.homingRange = maxf(p.homingRange, 1100)
					p.homingLead = maxf(p.homingLead, .90)
					p.bulletSpeed *= 1.10
				2:
					p.homing = maxf(p.homing, .90)
					p.homingActivationDist = minf(p.homingActivationDist, 65)
					p.homingRange = maxf(p.homingRange, 1900)
					p.homingLead = maxf(p.homingLead, 1.08)
					p.homingTurnBoost = maxf(p.homingTurnBoost, 1.2)
		"dash":
			match i:
				0: p.dashCooldown *= .85
				1:
					p.dashCooldown *= .70
					p.dashNova = maxf(p.dashNova, .6)
				2:
					p.dashCooldown *= .55
					p.dashNova = maxf(p.dashNova, 1.6)
					p.dashNovaRadius = 125
		"vitality":
			match i:
				0:
					p.maxHp += 20
					Game.healPlayer(10, "vitality")
				1:
					p.maxHp += 45
					Game.healPlayer(20, "vitality")
				2:
					p.maxHp += 80
					Game.healPlayer(p.maxHp * .30, "vitality")
		"speed":
			match i:
				0: p.speed *= 1.10
				1:
					p.speed *= 1.22
					p.dashCooldown *= .90
				2:
					p.speed *= 1.38
					p.dashCooldown *= .80
		"armor":
			match i:
				0: p.armor = 1 - (1 - p.armor) * .92
				1: p.armor = 1 - (1 - p.armor) * .84
				2: p.armor = 1 - (1 - p.armor) * .72
		"regen":
			match i:
				0: p.regen += .45
				1: p.regen += 1.1
				2:
					p.regen += 2.2
					p.maxHp += 30
					Game.healPlayer(15, "regen_upgrade")
		"magnet":
			match i:
				0: p.magnet += 90
				1: p.magnet += 190
				2:
					p.globalPickup = true
					p.xpMultiplier *= 1.12
		"echo":
			match i:
				0:
					p.echoChance = maxf(p.echoChance, .15)
					p.echoDamage = maxf(p.echoDamage, .5)
				1:
					p.echoChance = maxf(p.echoChance, .45)
					p.echoDamage = maxf(p.echoDamage, .75)
				2:
					p.echoChance = 1
					p.echoDamage = 1
		"execute":
			match i:
				0:
					p.executeThreshold = maxf(p.executeThreshold, .20)
					p.executeBonus = maxf(p.executeBonus, .40)
				1:
					p.executeThreshold = maxf(p.executeThreshold, .28)
					p.executeBonus = maxf(p.executeBonus, .90)
				2:
					p.executeThreshold = maxf(p.executeThreshold, .22)
					p.executeBonus = maxf(p.executeBonus, 1.5)
					p.executeInstant = true
		"berserk":
			p.lowHpPower = maxf(p.lowHpPower, [.20, .45, .85][i])
		"scorch": p.burnPower = maxf(p.burnPower, [.2, .45, .8][i])
		"fracture_round": p.fracturePower = max(p.fracturePower, i + 1)
		"boss_hunter": p.bossDamage += [.15, .3, .5][i]
		"purification": p.debuffResistance += [.25, .4, .7][i]
		"ability_amplifier": p.activePower *= [1.15, 1.3, 1.5][i]
		"ability_cycler": p.activeHaste += [.12, .22, .4][i]
		"drone_training":
			p.droneDamage *= [1.15, 1.25, 1.4][i]
			p.droneRate *= [1, 1.1, 1.2][i]
		"pierce_amp": p.piercePower += [.06, .10, .16][i]
		"xp_scanner": p.xpMultiplier *= [1.1, 1.18, 1.28][i]
		"prism_barrel":
			p.prismPower = maxf(p.prismPower, [.7, 1.2, 2][i])
			p.beamPower *= [1, 1.1, 1.25][i]
		"comet_rain":
			p.cometPower = maxf(p.cometPower, [1, 1.6, 2.5][i])
			p.cometEvery = [9, 7, 5][i]
		"lightning_halo": p.haloPower = maxf(p.haloPower, [.35, .65, 1.1][i])
		"charge_coil":
			p.chargeEfficiency += [.15, .30, .5][i]
			p.beamPower *= [1.1, 1.2, 1.35][i]
		"satellite_blades":
			p.bladePower = maxf(p.bladePower, [.45, .7, 1.1][i])
			p.bladeCount = max(p.bladeCount, [2, 3, 4][i])


# bound-callable targets (used as choice `apply`)
func _apply_skill(sid: String, rank: int) -> void:
	skill_apply(sid, rank - 1)
	var ranks: Dictionary = Game.player.skillRanks
	ranks[sid] = max(ranks.get(sid, 0), rank)


func _apply_legend(lid: String) -> void:
	legendary_apply(lid)
	Game.player.skillRanks[lid] = 4


func _apply_unique(uid: String) -> void:
	unique_apply(uid)
	Game.player.skillRanks[uid] = 3


func endlessChoices() -> Array:
	var p: Dictionary = Game.player
	var pool: Array = [
		{"id": "end_damage", "icon": "✦", "name": "出力の継続研究", "desc": "本体弾ダメージ +12%。繰り返し取得可能。"},
		{"id": "end_rate", "icon": "⌁", "name": "連射の継続研究", "desc": "本体連射 +8%。描画できない分の弾も威力へ集約。"},
		{"id": "end_active", "icon": "⚡", "name": "スキルの継続研究", "desc": "スキル出力 +12%、再使用効率 +5%。"},
		{"id": "end_hp", "icon": "⬡", "name": "耐久の継続研究", "desc": "最大HP +25。HPを10回復。"},
	]
	if p.prismPower > 0 or _active_slot_is(["lance", "prism"]):
		pool.append({"id": "end_beam", "icon": "⇢", "name": "光子出力の継続研究", "desc": "ビーム威力 +12% / チャージ効率 +8%。"})
	if p.droneCount > 0:
		pool.append({"id": "end_drone", "icon": "◎", "name": "ドローンの継続研究", "desc": "ドローン火力 +12% / 連射 +6%。固定上限なし。"})
		pool.append({"id": "end_fleet", "icon": "⌘", "name": "群体拡張", "desc": "ドローン +1。機数の火力効率は逓減するが、成長は止まらない。"})
	var one_hit: bool = bool(Meta.challenge().get("oneHit", false))
	var out: Array = []
	for c in pool:
		if one_hit and c.id == "end_hp":
			continue
		var d: Dictionary = c.duplicate()
		d["rarity"] = "RARE"
		d["apply"] = endless_apply.bind(c.id)
		out.append(d)
	return out


func rollRarity() -> String:
	var p: Dictionary = Game.player
	var legendary: float = minf(.055, .004 + p.level * .0009 + Game.bossesDefeated * .002) if p.level >= 12 else 0.0
	var epic: float = minf(.20, .07 + p.level * .0035)
	var rare: float = minf(.40, .27 + p.level * .002)
	var r: float = randf()
	if r < legendary:
		return "LEGENDARY"
	if r < legendary + epic:
		return "EPIC"
	if r < legendary + epic + rare:
		return "RARE"
	return "COMMON"


func buildSkillChoice(skill: Dictionary, forcedRarity = null) -> Dictionary:
	var current: int = int(Game.player.skillRanks.get(skill.id, 0))
	var rolled: String = forcedRarity if forcedRarity != null else rollRarity()
	if rolled == "LEGENDARY":
		rolled = "EPIC"
	var rank: int = maxi(rarityRank[rolled], mini(3, current + 1))
	rank = mini(3, rank)
	var rarity: String = rankRarity[rank]
	var tier: Dictionary = skill.tiers[rarity]
	return {"id": skill.id, "icon": skill.icon, "name": skill.name, "rarity": rarity, "rank": rank, "desc": tier.desc,
		"apply": _apply_skill.bind(skill.id, rank)}


func _unique_choice(u: Dictionary) -> Dictionary:
	return {"id": u.id, "icon": u.icon, "name": u.name, "rarity": "EPIC", "desc": u.desc, "apply": _apply_unique.bind(u.id)}


func chooseUpgradeSet() -> Array:
	var p: Dictionary = Game.player
	var ranks: Dictionary = p.skillRanks
	var c: Dictionary = Meta.challenge()
	var one_hit: bool = bool(c.get("oneHit", false))
	var no_heal: bool = float(c.get("heal", 1)) <= 0
	var available: Array = []
	for s in skills:
		if ranks.get(s.id, 0) >= 3:
			continue
		if s.get("req", false) and not skill_req(s.id):
			continue
		if one_hit and s.id in ["lifesteal", "vitality", "armor", "regen"]:
			continue
		if no_heal and s.id in ["lifesteal", "regen"]:
			continue
		available.append(s)
	var chosen: Array = []
	var used := {}
	var legend_pool: Array = []
	for l in legendarySkills:
		if not ranks.get(l.id, 0) and legendary_requires(l.id):
			legend_pool.append(l)
	var force_legend: bool = float(p.get("legendaryCharge", 0)) >= 3
	if legend_pool.size() > 0 and (force_legend or (p.level >= 12 and randf() < minf(.11, .015 + p.level * .0014))):
		var l = U.pick(legend_pool)
		chosen.append({"id": l.id, "icon": l.icon, "name": l.name, "rarity": "LEGENDARY", "desc": l.desc, "apply": _apply_legend.bind(l.id)})
		used[l.id] = true
		if force_legend:
			p.legendaryCharge -= 3
	var force_epic: bool = bool(p.get("epicGuarantee", false))
	var force_rare: bool = p.rarityCharge >= 3
	while chosen.size() < 3 and available.size() > 0:
		var s: Dictionary = available.pop_at(randi() % available.size())
		var forced = "EPIC" if force_epic else "RARE" if force_rare else null
		var choice: Dictionary = buildSkillChoice(s, forced)
		if choice.rarity == "EPIC" and randf() < .22:
			var uniq: Array = []
			for u in uniqueEpics:
				if ranks.get(u.id, 0) or used.has(u.id):
					continue
				if no_heal and u.id in ["phoenix", "bloodmoon"]:
					continue
				uniq.append(u)
			if uniq.size() > 0:
				choice = _unique_choice(U.pick(uniq))
		if used.has(choice.id):
			continue
		chosen.append(choice)
		used[choice.id] = true
		if force_epic:
			p.epicGuarantee = false
			force_epic = false
		elif force_rare:
			p.rarityCharge -= 3
			force_rare = false
	var remaining_unique: Array = []
	for u in uniqueEpics:
		if not ranks.get(u.id, 0) and not used.has(u.id) and not (no_heal and u.id in ["phoenix", "bloodmoon"]):
			remaining_unique.append(u)
	while chosen.size() < 3 and remaining_unique.size() > 0:
		var u2: Dictionary = remaining_unique.pop_at(randi() % remaining_unique.size())
		chosen.append(_unique_choice(u2))
	var repeat: Array = endlessChoices()
	var any_max := false
	for r in ranks.values():
		if r >= 3:
			any_max = true
			break
	if available.size() > 0 and any_max and chosen.size() == 3 and randf() < .28:
		var idx := -1
		for i in range(chosen.size() - 1, -1, -1):
			if chosen[i].rarity == "COMMON":
				idx = i
				break
		if idx >= 0:
			chosen[idx] = U.pick(repeat)
	while chosen.size() < 3 and repeat.size() > 0:
		chosen.append(repeat.pop_at(randi() % repeat.size()))
	return chosen


func showUpgrade() -> void:
	if not (Game.state in ["playing", "paused"]):
		return
	Game.cardPanelOrigin = Game.state
	Game.state = "upgrade"
	Game.cancelCombatInput()
	UI.hook("showUpgrade", [])
	Game.renderCardChoices()
	Game.sceneDirty = true
	UI.hook("syncCombatHud", [])


func selectUpgrade(u) -> void:
	if Game.state != "upgrade" or Game.currentCardChoices == null:
		return
	var found := false
	for c in Game.currentCardChoices:
		if is_same(c, u) or c == u:
			found = true
			break
	if not found:
		return
	if not Game.applyRunChoice(u):
		return
	Game.currentCardChoices = null
	Game.renderCardChoices()
	if Game.pendingLevelUps <= 0:
		Game.closeCardChoices()
