extends Node
## Combat — friendly effects, active abilities, gear/loadout effects, drones, projectiles,
## loot, player shooting, hit/kill/gem handling. Port of NEON FRACTURE index.html
## (7551-7806 sans draw, 7896-7977, 8017-8037, 8648-8720, 8945-9066).

# ---- convenience accessors to Game/World/Inp state (always read live; arrays are
# ---- reassigned by Game so writes go through Game.<name> explicitly) ----
var player:
	get: return Game.player
var time: float:
	get: return Game.time
var W: float:
	get: return World.W
var H: float:
	get: return World.H
var mouse:
	get: return Inp.mouse
var PERF:
	get: return Game.PERF

# Active skills are run-only, earned once per boss defeat, independent of card choices.
# (Index lists ACTIVE_DEFS under Render; it is defined here and Render may read Combat.ACTIVE_DEFS.)
var ACTIVE_DEFS: Dictionary = {
	"nova": {"name": "反転ノヴァ", "icon": "✹", "cd": 15, "desc": "周囲の敵を攻撃し、近くの敵弾を消去。", "base": 4.5},
	"lance": {"name": "貫通砲", "icon": "⇢", "cd": 10, "desc": "0.7秒チャージ後に貫通ビーム。充填中は移動・照準可能。発射からCD開始。装甲無視。", "base": 7.5},
	"cleanse": {"name": "再起動", "icon": "✚", "cd": 22, "desc": "封印・侵食を解除。HPを少量回復し、ダッシュを回復。", "base": 0},
	"stasis": {"name": "重力拘束", "icon": "◎", "cd": 19, "desc": "周囲の敵を足止めしながら継続ダメージ。ボスにも有効。", "base": 2.5},
	"missiles": {"name": "誘導斉射", "icon": "⌖", "cd": 13, "desc": "近い敵へ装備スキル専用の誘導弾を射出。", "base": 2.2},
	"overdrive": {"name": "本体オーバードライブ", "icon": "⚡", "cd": 24, "desc": "一定時間、本体の弾ダメージと連射速度を強化。", "base": 0},
	"prism": {"name": "プリズム・バースト", "icon": "✧", "cd": 17, "desc": "0.95秒チャージ後、3方向へ装甲無視ビーム。光線ごとに420%ダメージ。", "base": 4.2},
	"orbital": {"name": "星雨砲撃", "icon": "☄", "cd": 18, "desc": "照準地点と周囲へ6発の彗星。予告後にそれぞれ180%の範囲攻撃。", "base": 1.8},
	"blades": {"name": "ブレード・サテライト", "icon": "✥", "cd": 20, "desc": "5秒間、6枚の旋回刃を展開。接触ダメージは同じ敵へ0.3秒間隔。", "base": 1.2},
	"arclattice": {"name": "雷光連結", "icon": "ϟ", "cd": 14, "desc": "近い敵から5体へ連鎖雷を3回放つ。1回150%ダメージ。", "base": 1.5},
	"singularity": {"name": "重力崩壊", "icon": "◉", "cd": 24, "desc": "照準位置に重力井戸。0.9秒後から3秒の拘束・継続ダメージ、最後に爆発。", "base": 1.6},
}

var GEM_TYPES: Dictionary = {
	"fragment": {"hue": 185, "r": 4, "xp": 2, "label": "断片"},
	"dense": {"hue": 220, "r": 5, "xp": 6, "label": "高密度"},
	"vital": {"hue": 145, "r": 5, "xp": 4, "label": "生命", "heal": .02},
	"rare": {"hue": 280, "r": 6, "xp": 10, "label": "希少", "rarity": 1},
	"boss": {"hue": 42, "r": 8, "xp": 45, "label": "ボスコア", "heal": .08, "epic": true},
}

# ---------------------------------------------------------------- helpers
func _snd(name: String) -> void:
	var s = Audio.Sound
	if s != null:
		s.play(name)

func _hyp(dx: float, dy: float) -> float:
	return sqrt(dx * dx + dy * dy)

## JS `v || fallback`
func _or(v, fb):
	if v == null:
		return fb
	if v is bool:
		return v if v else fb
	if v is int or v is float:
		if v == 0 or is_nan(float(v)):
			return fb
		return v
	if v is String and v == "":
		return fb
	return v

## JS `opts.k ?? fallback`
func _nn(d: Dictionary, k: String, fb):
	if d.has(k) and d[k] != null:
		return d[k]
	return fb

func _dead(o) -> bool:
	return o != null and o.get("_dead", false)

func _index_of(arr: Array, obj) -> int:
	for i in arr.size():
		if is_same(arr[i], obj):
			return i
	return -1

func _tail(arr: Array, n: int) -> Array:
	if arr.size() > n:
		return arr.slice(arr.size() - n)
	return arr

# ---------------------------------------------------------------- friendly effects
func chargeSeconds(base: float) -> float:
	return base / (1.0 + maxf(0.0, float(player.get("chargeEfficiency", 0))))

func aimAngle() -> float:
	return atan2(mouse.y - player.y, mouse.x - player.x)

func aimPoint(range_: float = 850.0) -> Dictionary:
	var a: float = aimAngle()
	var d: float = minf(range_, _hyp(mouse.x - player.x, mouse.y - player.y))
	return {"x": U.clamp(player.x + cos(a) * d, 20, W - 20), "y": U.clamp(player.y + sin(a) * d, 20, H - 20)}

func addFriendly(spec: Dictionary):
	if Game.runSettled or Game.state != "playing":
		return null
	var h: Dictionary = {"age": 0.0, "warn": .6, "duration": .3, "source": "active", "hue": 185, "damage": 0.0, "power": 1,
		"hit": false, "x": player.x, "y": player.y, "a": aimAngle()}
	h.merge(spec, true)
	Game.friendlyEffects.append(h)
	if h.get("kind", "") == "beam":
		_snd("charge")
	return h

func friendlyArea(x: float, y: float, radius: float, damage: float, source: String, options: Dictionary = {}) -> void:
	for e in Game.enemies.duplicate():
		if not _dead(e) and e.spawnDelay <= 0 and _hyp(e.x - x, e.y - y) <= radius + e.r:
			Enemies.dealEnemyDamage(e, damage, source, options)
			if not _dead(e) and _or(options.get("slow", 0), 0) != 0:
				e.slow = maxf(e.slow, 1.4)
				e.slowPower = maxf(e.slowPower, options.slow)

func friendlyArc(x: float, y: float, power: float, source: String, targets: int = 4) -> void:
	_snd("lightning")
	var used: Dictionary = {}
	var origin = {"x": x, "y": y}
	for hop in targets:
		var nxt = null
		var best: float = (340.0 if hop > 0 else 800.0)
		best = best * best
		for e in Game.enemies:
			if _dead(e) or e.spawnDelay > 0 or used.has(e.id):
				continue
			var d: float = U.dist2(e, origin)
			if d < best:
				best = d
				nxt = e
		if nxt == null:
			break
		used[nxt.id] = true
		if Game.rings.size() < PERF.maxRings:
			Game.rings.append({"x": origin.x, "y": origin.y, "x2": nxt.x, "y2": nxt.y, "line": true, "life": .26, "max": .26, "hue": 205})
		Enemies.dealEnemyDamage(nxt, power, source)
		origin = nxt

func castPattern(kind: String, power: float = 1.0, source: String = "active", target = null):
	var at: Dictionary
	if target != null and target.has("x") and target.has("y") and is_finite(float(target.x)) and is_finite(float(target.y)):
		at = {"x": target.x, "y": target.y}
	else:
		at = aimPoint()
	if kind == "chargebeam":
		return addFriendly({"kind": "beam", "warn": chargeSeconds(.65), "damage": player.damage * .85 * power * player.beamPower, "source": source, "follow": true, "length": 1250, "width": 20, "hue": 185, "branches": 0})
	if kind == "meteor":
		var m := {"kind": "meteor", "warn": .75, "radius": 150, "damage": player.damage * 1.4 * power, "source": source, "hue": 195, "duration": .38}
		m.merge(at, true)
		return addFriendly(m)
	if kind == "arcgrid":
		return addFriendly({"kind": "arc", "warn": .35, "damage": player.damage * .8 * power, "source": source, "targets": 4, "hue": 205})
	if kind == "orbitblade":
		return addFriendly({"kind": "orbit", "warn": .2, "duration": 3.2, "radius": 145, "damage": player.damage * .45 * power, "source": source, "count": 4, "hitTimes": {}, "hue": 185})
	if kind == "gravitywell":
		var w := {"kind": "well", "warn": .8, "duration": 2.8, "radius": 195, "damage": player.damage * .75 * power, "source": source, "hue": 225}
		w.merge(at, true)
		return addFriendly(w)
	if kind == "nova_shard":
		for i in 8:
			shoot(player.x, player.y, float(i) / 8.0 * TAU, player.damage * .27 * power, {"source": source, "noProc": true, "noCrit": true, "bounces": 2, "pierce": 0, "homing": 0, "silent": true, "r": 4})
	return null

func activeCharge(slot: Dictionary, index: int, kind: String, power: float):
	var prism: bool = kind == "prism"
	var effect = addFriendly({"kind": "beam", "warn": chargeSeconds(.95 if prism else .7),
		"damage": player.damage * (4.2 if prism else 7.5) * power * player.beamPower,
		"follow": true, "length": 1300 if prism else 1500, "width": 25 if prism else 34,
		"branches": (1 + int(player.get("beamBranches", 0))) if prism else int(player.get("beamBranches", 0)),
		"source": "active", "hue": 205 if prism else 185, "duration": .32,
		"slot": slot, "index": index, "skillId": slot.id, "ignoreArmor": true})
	slot.charging = effect
	return effect

func bladePositions(cx: float, cy: float, radius: float, count: int, phase: float) -> Array:
	var out: Array = []
	for i in count:
		out.append({"x": cx + cos(phase + i * TAU / count) * radius, "y": cy + sin(phase + i * TAU / count) * radius})
	return out

func bladeDamage(blades: Array, damage: float, source: String, hitTimes: Dictionary) -> void:
	for e in Game.enemies:
		if _dead(e) or e.spawnDelay > 0 or float(hitTimes.get(e.id, 0)) > time:
			continue
		var lim: float = (e.r + 20.0) * (e.r + 20.0)
		var touch: bool = false
		for b in blades:
			if U.dist2(b, e) < lim:
				touch = true
				break
		if touch:
			hitTimes[e.id] = time + .3
			Enemies.dealEnemyDamage(e, damage, source)
	# Dead IDs must not accumulate over an endless run.
	if hitTimes.size() > 256:
		var ids: Dictionary = {}
		for e in Game.enemies:
			ids[e.id] = true
		for id in hitTimes.keys():
			if not ids.has(id):
				hitTimes.erase(id)

func dischargeFriendly(h: Dictionary) -> void:
	h.hit = true
	var kind: String = h.get("kind", "")
	if kind == "beam":
		h.x2 = h.x + cos(h.a) * h.length
		h.y2 = h.y + sin(h.a) * h.length
		var angles: Array = [h.a]
		var hb: float = float(_or(h.get("branches", 0), 0))
		var branches: int = mini(3, int(hb))
		var weight: float = (1.0 + 2.0 * hb) / (1.0 + 2.0 * branches)
		for i in range(1, branches + 1):
			angles.append(h.a + i * .18)
			angles.append(h.a - i * .18)
		h.angles = angles
		for a in angles:
			var x2: float = h.x + cos(a) * h.length
			var y2: float = h.y + sin(a) * h.length
			for e in Game.enemies.duplicate():
				if not _dead(e) and Enemies.distanceToSegment(e.x, e.y, h.x, h.y, x2, y2) < e.r + h.width / 2.0:
					Enemies.dealEnemyDamage(e, h.damage * weight, h.source, {"ignoreArmor": bool(h.get("ignoreArmor", false))})
		var slot = h.get("slot", null)
		if slot != null:
			slot.charging = null
			slot.remaining = activeCooldown(slot)
			Cards.emitCardTrigger("on_charge", {"skill": h.get("skillId")})
		_snd("beam")
	elif kind == "meteor":
		_snd("meteor")
		friendlyArea(h.x, h.y, h.radius, h.damage, h.source, ({"slow": h.slow} if _or(h.get("slow", 0), 0) != 0 else {}))
		if Game.rings.size() < PERF.maxRings:
			Game.rings.append({"x": h.x, "y": h.y, "r": 12, "extent": h.radius, "life": .4, "max": .4, "hue": h.hue})
		var i: int = 0
		while i < 12 and Game.particles.size() < PERF.maxParticles:
			var a2: float = float(i) / 12.0 * TAU
			Game.particles.append({"x": h.x, "y": h.y, "vx": cos(a2) * 180, "vy": sin(a2) * 180, "life": .35, "max": .35, "hue": h.hue, "size": 3})
			i += 1
	elif kind == "arc":
		friendlyArc(player.x, player.y, h.damage, h.source, int(_or(h.get("targets", 4), 4)))

func updateFriendlySystems(dt: float) -> void:
	# Only called by the fixed simulation while playing. Panels pause both charge and cooldown.
	var snapshot: Array = Game.friendlyEffects.duplicate()
	for h in snapshot:
		if h.get("dead", false):
			continue
		if not h.hit and h.get("follow", false):
			h.x = player.x
			h.y = player.y
			h.a = aimAngle()
		var before: float = h.age
		h.age += dt
		if not h.hit and h.age >= h.warn:
			dischargeFriendly(h)
		var live_dt: float = maxf(0.0, minf(h.age, h.warn + h.duration) - maxf(before, h.warn))
		var kind: String = h.get("kind", "")
		if live_dt > 0 and kind == "well":
			for e in Game.enemies:
				if _dead(e) or e.spawnDelay > 0:
					continue
				var d: float = _hyp(e.x - h.x, e.y - h.y)
				if d <= h.radius + e.r:
					var pull: float = minf(maxf(0.0, d - 18.0), (18.0 if e.get("boss", false) else 68.0) * live_dt)
					var dd: float = d if d != 0.0 else 1.0
					e.x += (h.x - e.x) / dd * pull
					e.y += (h.y - e.y) / dd * pull
					e.slow = maxf(e.slow, .18)
					e.slowPower = maxf(e.slowPower, .50)
					Enemies.dealEnemyDamage(e, h.damage * live_dt, h.source)
		if live_dt > 0 and kind == "orbit":
			bladeDamage(bladePositions(player.x, player.y, h.radius, h.count, time * 2.5), h.damage, h.source, h.hitTimes)
		if h.age >= h.warn + h.duration:
			if kind == "well":
				_snd("explosion")
				friendlyArea(h.x, h.y, h.radius, h.damage * 2.5, h.source)
				if Game.rings.size() < PERF.maxRings:
					Game.rings.append({"x": h.x, "y": h.y, "r": 12, "extent": h.radius, "life": .35, "max": .35, "hue": h.hue})
			h.dead = true
			# break the effect<->slot reference cycle
			if h.has("slot"):
				h.erase("slot")
	Game.friendlyEffects = Game.friendlyEffects.filter(func(f): return not f.get("dead", false))
	updateLoadoutEffects(dt)

func gearReady(key: String, seconds: float) -> bool:
	if float(player.gearTimers.get(key, 0)) > time:
		return false
	player.gearTimers[key] = time + seconds
	return true

func onGearImpact(blocked: bool = false) -> void:
	var g: Dictionary = player.gearEffects
	var reactive: float = float(g.get("reactive", 0))
	var cryo: float = float(g.get("cryo", 0))
	if reactive != 0.0 and gearReady("reactive", 2.8):
		castPattern("nova_shard", (.2 + reactive * .07) / .27, "gear")
	if not blocked and cryo != 0.0 and gearReady("cryo", 4):
		addFriendly({"kind": "meteor", "warn": .15, "radius": 210, "damage": player.damage * (.8 + cryo * .3), "source": "gear", "hue": 195, "slow": .6, "duration": .3})

func onPrimaryKill(e: Dictionary) -> void:
	player.gearKills += 1
	player.cometKills += 1
	var comet: float = float(player.gearEffects.get("comet", 0))
	if comet != 0.0 and int(player.gearKills) % 6 == 0:
		castPattern("meteor", (1.0 + comet * .45) / 1.4, "gear", e)
	if float(player.cometPower) > 0 and int(player.cometEvery) > 0 and int(player.cometKills) % int(player.cometEvery) == 0:
		var p = {"x": e.x, "y": e.y}
		var count: int = 3 if player.get("fallingSky", false) else 1
		for i in count:
			addFriendly({"kind": "meteor",
				"x": U.clamp(p.x + (cos(i * 2.8) * 90 if i > 0 else 0), 20, W - 20),
				"y": U.clamp(p.y + (sin(i * 2.8) * 90 if i > 0 else 0), 20, H - 20),
				"warn": .7 + i * .15, "radius": 150, "damage": player.damage * player.cometPower, "source": "other", "hue": 195, "duration": .35})

func updateLoadoutEffects(dt: float) -> void:
	var g: Dictionary = player.gearEffects
	var prism: float = float(g.get("prism", 0))
	var thunder: float = float(g.get("thunder", 0))
	var relay: float = float(g.get("relay", 0))
	var ember: float = float(g.get("ember", 0))
	var orbit: float = float(g.get("orbit", 0))
	if mouse.down:
		if prism != 0.0 and gearReady("prism", 4):
			addFriendly({"kind": "beam", "warn": chargeSeconds(.6), "follow": true, "length": 1180, "width": 18, "damage": player.damage * (1.0 + prism * .32) * player.beamPower, "source": "gear", "hue": 195, "branches": 0})
		if thunder != 0.0 and gearReady("thunder", 3):
			friendlyArc(player.x, player.y, player.damage * (.6 + thunder * .28), "gear", 3)
		if relay != 0.0 and gearReady("relay", 3.5):
			var a: float = aimAngle()
			for off in [-.10, .10]:
				shoot(player.x, player.y, a + off, player.damage * (.4 + relay * .12), {"source": "gear", "noProc": true, "noCrit": true, "homing": .85, "homingActivationDist": 65, "homingRange": 1400, "pierce": 0, "bounces": 0, "silent": true})
		if float(player.get("prismPower", 0)) > 0 and gearReady("runPrism", 3.6):
			addFriendly({"kind": "beam", "warn": chargeSeconds(.55), "follow": true, "length": 1200, "width": 22, "damage": player.damage * player.prismPower * player.beamPower, "source": "other", "hue": 185, "branches": player.get("beamBranches", 0)})
	if ember != 0.0 and gearReady("ember", 2):
		friendlyArea(player.x, player.y, 180, player.damage * (.25 + ember * .1), "gear")
		if Game.rings.size() < PERF.maxRings:
			Game.rings.append({"x": player.x, "y": player.y, "r": 30, "extent": 150, "life": .35, "max": .35, "hue": 190})
	if float(player.get("haloPower", 0)) > 0 and gearReady("halo", 1.7):
		friendlyArc(player.x, player.y, player.damage * player.haloPower, "other", 3)
	if orbit != 0.0:
		bladeDamage(bladePositions(player.x, player.y, 150, 4, time * 2.4), player.damage * (.25 + orbit * .10), "gear", player.gearOrbitHits)
	if float(player.get("bladePower", 0)) > 0:
		var count: int = mini(8, int(player.bladeCount))
		bladeDamage(bladePositions(player.x, player.y, 180, count, time * 2.4 + .5), player.damage * player.bladePower * player.bladeCount / float(maxi(1, count)), "other", player.orbitHitTimes)

# ---------------------------------------------------------------- active abilities
func activePower(slot: Dictionary) -> float:
	return (1.0 + .32 * (slot.level - 1)) * float(_or(player.get("activePower", 1), 1))

func activeCooldown(slot: Dictionary) -> float:
	return float(ACTIVE_DEFS[slot.id].cd) / (1.0 + .10 * sqrt(maxf(0.0, float(slot.level - 1))) + float(player.get("activeHaste", 0)))

func queueAbilityReward() -> void:
	var pool: Array = ACTIVE_DEFS.keys()
	var offers: Array = []
	for s in Game.activeSlots:
		if s != null:
			offers.append(s.id)
			break
	while offers.size() < 3 and pool.size() > 0:
		var idx: int = int(floor(randf() * pool.size()))
		var nxt = pool[idx]
		pool.remove_at(idx)
		if nxt != null and not offers.has(nxt):
			offers.append(nxt)
	Game.abilityRewards.append({"offers": offers, "boss": Game.bossesDefeated, "wave": Game.wave})
	UI.hook("syncCombatHud")

func openAbilityRewards() -> void:
	if not (Game.state == "playing" or Game.state == "paused"):
		return
	Game.panelReturnState = Game.state
	Game.state = "ability"
	Game.cancelCombatInput()
	Game.selectedAbilityId = null
	UI.hook("openAbilityRewards")
	renderAbilityRewards()
	UI.hook("syncCombatHud")

func closeAbilityRewards() -> void:
	if Game.state != "ability":
		return
	UI.hook("closeAbilityRewards")
	Game.resumeAfterPanel(Game.panelReturnState)

func renderAbilityRewards() -> void:
	UI.hook("renderAbilityRewards")

func assignAbility(id, index: int) -> bool:
	if Game.state != "ability" or Game.abilityRewards.is_empty() or not Game.abilityRewards[0].offers.has(id) or index < 0 or index > 2:
		return false
	for i in Game.activeSlots.size():
		var s = Game.activeSlots[i]
		if s != null and s.id == id and i != index:
			return false
	var old = Game.activeSlots[index]
	var cooldown: float = float(old.remaining) if old != null else 0.0
	if old != null and old.get("charging") != null:
		old.charging.dead = true
		cooldown = maxf(cooldown, activeCooldown(old))
		old.charging = null
	Game.activeSlots[index] = {"id": id, "level": (old.level + 1) if (old != null and old.id == id) else 1, "remaining": cooldown, "charging": null}
	Game.abilityRewards.pop_front()
	Game.selectedAbilityId = null
	_snd("card")
	renderAbilityRewards()
	UI.hook("syncCombatHud")
	return true

func useActive(index: int) -> bool:
	var s = Game.activeSlots[index] if index >= 0 and index < Game.activeSlots.size() else null
	if Game.state != "playing" or s == null or s.remaining > 0 or s.get("charging") != null:
		return false
	var power: float = activePower(s)
	var a: float = atan2(mouse.y - player.y, mouse.x - player.x)
	s.remaining = activeCooldown(s)
	var id: String = s.id
	if id == "nova":
		for b in Game.bullets:
			if b.get("enemy", false) and U.dist2(b, player) < 520.0 * 520.0:
				b._dead = true
		for e in Game.enemies.duplicate():
			if U.dist2(e, player) < 390.0 * 390.0:
				Enemies.dealEnemyDamage(e, player.damage * 4.5 * power, "active")
		Game.rings.append({"x": player.x, "y": player.y, "r": 50, "extent": 360, "life": .55, "max": .55, "hue": 185})
	elif id == "lance" or id == "prism":
		s.remaining = 0
		activeCharge(s, index, id, power)
	elif id == "cleanse":
		player.barrierLock = 0
		player.wounded = 0
		Game.healPlayer(player.maxHp * .08 * power, "active")
		player.dashReady = 1
		player.guardTimer = maxf(player.guardTimer, 2.5)
		player.guardReduction = maxf(player.guardReduction, .35)
	elif id == "stasis":
		player.stasisTime = 2.4 + .45 * sqrt(float(s.level))
		player.stasisPower = power
	elif id == "missiles":
		var count: int = 6 + int(floor(sqrt(float(s.level - 1)) * 2.0))
		for i in count:
			shoot(player.x, player.y, a + (i - (count - 1) / 2.0) * .18, player.damage * 2.2 * power,
				{"silent": true, "source": "active", "noProc": true, "homing": .95, "homingActivationDist": 55, "homingRange": 1800, "pierce": 0, "bounces": 0})
	elif id == "overdrive":
		player.playerOverdrive = 4.0 + .5 * sqrt(float(s.level - 1))
		player.overdrivePower = 1.0 + .45 * sqrt(power)
	if id == "orbital":
		var at: Dictionary = aimPoint()
		for i in 6:
			var ang: float = float(i) / 6.0 * TAU
			var r: float = 170.0 if i > 0 else 0.0
			addFriendly({"kind": "meteor", "x": U.clamp(at.x + cos(ang) * r, 20, W - 20), "y": U.clamp(at.y + sin(ang) * r, 20, H - 20),
				"radius": 135, "warn": .8 + i * .13, "duration": .4, "damage": player.damage * 1.8 * power, "source": "active", "hue": 195})
	elif id == "blades":
		addFriendly({"kind": "orbit", "warn": .15, "duration": 5, "radius": 170, "count": 6, "hitTimes": {}, "damage": player.damage * 1.2 * power, "source": "active", "hue": 185})
	elif id == "arclattice":
		for i in 3:
			addFriendly({"kind": "arc", "warn": .2 + i * .32, "damage": player.damage * 1.5 * power, "source": "active", "targets": 5, "hue": 205})
	elif id == "singularity":
		var wspec := {"kind": "well", "warn": .9, "duration": 3, "radius": 240, "damage": player.damage * 1.6 * power, "source": "active", "hue": 225}
		wspec.merge(aimPoint(), true)
		addFriendly(wspec)
	var bastion: float = float(player.gearEffects.get("bastion", 0))
	if bastion != 0.0 and gearReady("bastion", 5):
		player.guardTimer = maxf(player.guardTimer, 2.5)
		player.guardReduction = maxf(player.guardReduction, .2 + bastion * .04)
	Cards.emitCardTrigger("on_active", {"skill": id})
	if Game.texts.size() < PERF.maxTexts:
		Game.texts.append({"x": player.x, "y": player.y - 62 - index * 20, "text": ACTIVE_DEFS[id].name, "life": .8, "max": .8, "hue": 42, "size": 16})
	_snd("charge" if s.get("charging") != null else "skill")
	UI.hook("syncCombatHud")
	return true

# ---------------------------------------------------------------- drones
func updateDrones(dt: float) -> void:
	player.droneOverdrive = maxf(0.0, player.droneOverdrive - dt)
	var stat: Dictionary = UI.droneStats()
	var over: float = 1.3 if player.droneOverdrive > 0 else 1.0
	var n: int = Game.drones.size()
	var weight: float = (stat.fleetWeight / n) if n > 0 else 0.0
	var cfg = UI.droneConfig
	var firing: bool = bool(cfg.enabled) and cfg.output > 0
	for i in n:
		var d: Dictionary = Game.drones[i]
		d.angle += dt * .85
		var ox: float = player.x + cos(d.angle + i * TAU / n) * 58
		var oy: float = player.y + sin(d.angle + i * TAU / n) * 58
		var target = d.get("target", null) if firing else null
		d.targetClock = float(d.get("targetClock", 0)) - dt
		if firing and (d.targetClock <= 0 or not UI.droneTargetAllowed(target) or U.dist2(target, player) > pow(player.droneRange, 2)):
			target = UI.selectDroneTarget()
			d.target = target
			d.targetClock = .16
		var tx: float = ox
		var ty: float = oy
		if target != null and player.get("droneTracking", false):
			var ta: float = atan2(target.y - player.y, target.x - player.x)
			tx = player.x + cos(ta) * 110 + cos(d.angle + i) * 30
			ty = player.y + sin(ta) * 110 + sin(d.angle + i) * 30
		d.x += (tx - d.x) * (1.0 - exp(-dt * 7.0))
		d.y += (ty - d.y) * (1.0 - exp(-dt * 7.0))
		if not firing or target == null:
			d.shotCredit = 0
			d.target = null
			continue
		d.shotCredit += stat.rate * over * dt
		if d.shotCredit >= 1:
			var due: int = int(floor(d.shotCredit))
			d.shotCredit -= due
			var speed: float = 600.0 + player.bulletSpeed * .15
			var lead: float = minf(.45, _hyp(target.x - d.x, target.y - d.y) / speed)
			var ang: float = atan2(target.y + float(target.get("vy", 0)) * lead - d.y, target.x + float(target.get("vx", 0)) * lead - d.x)
			shoot(d.x, d.y, ang, stat.damage * weight * due * over,
				{"speed": speed, "r": 3, "drone": true, "silent": true, "pierce": player.dronePierce, "homing": .4 if player.get("droneTracking", false) else 0, "bounces": 0, "life": 2.3})
			_snd("drone")

# ---------------------------------------------------------------- projectiles
func updateProjectiles(dt: float) -> void:
	Game.projectileUpdating = true
	_update_projectiles_inner(dt)
	Game.projectileUpdating = false
	Game.bullets = Game.bullets.filter(func(b): return b != null and not b.get("_dead", false))

func _update_projectiles_inner(dt: float) -> void:
	var frame: Array = Game.bullets.duplicate()
	# Perf: uniform grid over live (spawned) enemies so swept hit tests only visit nearby enemies
	# instead of bullets x enemies. Semantics identical to the original linear scan (hits are sorted by t).
	var grid: Dictionary = {}
	var maxR: float = 0.0
	var any_player_bullet: bool = false
	for b0 in frame:
		if b0 != null and not b0.get("enemy", false):
			any_player_bullet = true
			break
	if any_player_bullet:
		for e0 in Game.enemies:
			if e0.get("_dead", false) or e0.spawnDelay > 0:
				continue
			var key: int = int(floor(e0.x / 128.0)) * 4096 + int(floor(e0.y / 128.0))
			if grid.has(key):
				grid[key].append(e0)
			else:
				grid[key] = [e0]
			if e0.r > maxR:
				maxR = e0.r
	for b in frame:
		if b == null or b.get("_dead", false):
			continue
		var oldX: float = b.x
		var oldY: float = b.y
		var is_enemy: bool = b.get("enemy", false)
		if not is_enemy and b.homing > 0 and b.travelled >= b.homingActivationDist:
			var t = b.homingTarget
			if t == null or _dead(t) or t.spawnDelay > 0 or (b.fromDrone and not UI.droneTargetAllowed(t)) or b.hitIds.has(t.id) or U.dist2(t, b) > pow(b.homingRange * 1.25, 2):
				t = null
				var best: float = b.homingRange * b.homingRange
				for e in Game.enemies:
					if _dead(e) or e.spawnDelay > 0 or (b.fromDrone and not UI.droneTargetAllowed(e)) or b.hitIds.has(e.id):
						continue
					var dd: float = U.dist2(e, b)
					if dd < best:
						best = dd
						t = e
				b.homingTarget = t
			if t != null:
				var speed: float = _hyp(b.vx, b.vy)
				var distance: float = _hyp(t.x - b.x, t.y - b.y)
				var lead: float = minf(.4, distance / maxf(1.0, speed)) * float(_or(b.get("homingLead", 1), 1))
				var a: float = atan2(t.y + float(t.get("vy", 0)) * lead - b.y, t.x + float(t.get("vx", 0)) * lead - b.x)
				var now: float = atan2(b.vy, b.vx)
				var delta: float = atan2(sin(a - now), cos(a - now))
				var turn: float = (5.8 + 10.5 * b.homing) * float(_or(b.get("homingTurnBoost", 1), 1)) * dt
				var nxt: float = now + U.clamp(delta, -turn, turn)
				b.vx = cos(nxt) * speed
				b.vy = sin(nxt) * speed
		b.x += b.vx * dt
		b.y += b.vy * dt
		b.travelled = float(b.get("travelled", 0)) + _hyp(b.vx, b.vy) * dt
		b.life -= dt
		if not is_enemy and b.bounces > 0 and (b.x < 8 or b.x > W - 8 or b.y < 8 or b.y > H - 8):
			if b.x < 8 or b.x > W - 8:
				b.vx = -b.vx
			if b.y < 8 or b.y > H - 8:
				b.vy = -b.vy
			b.x = U.clamp(b.x, 8, W - 8)
			b.y = U.clamp(b.y, 8, H - 8)
			b.bounces -= 1
			b.damage *= float(_or(b.get("bounceGain", 1), 1))
		if b.life <= 0 or b.x < -90 or b.y < -90 or b.x > W + 90 or b.y > H + 90:
			b._dead = true
			continue
		if is_enemy:
			if Enemies.segmentCircleT(oldX, oldY, b.x, b.y, player.x, player.y, b.r + player.r) != INF:
				Game.damagePlayer(b.damage, {"kind": b.get("attackKind", "normal"), "enemy": b.get("source"), "lock": b.get("lock")})
				b._dead = true
				if Game.state != "playing":
					return
			continue
		# Swept hit tests prevent high-speed bullets jumping through a small enemy.
		var hits: Array = []
		var pad: float = b.r + maxR
		var gx0: int = int(floor((minf(oldX, b.x) - pad) / 128.0))
		var gx1: int = int(floor((maxf(oldX, b.x) + pad) / 128.0))
		var gy0: int = int(floor((minf(oldY, b.y) - pad) / 128.0))
		var gy1: int = int(floor((maxf(oldY, b.y) + pad) / 128.0))
		for gx in range(gx0, gx1 + 1):
			for gy in range(gy0, gy1 + 1):
				var cell = grid.get(gx * 4096 + gy)
				if cell == null:
					continue
				for e in cell:
					if e.get("_dead", false) or (b.fromDrone and not UI.droneTargetAllowed(e)) or b.hitIds.has(e.id):
						continue
					var tt: float = Enemies.segmentCircleT(oldX, oldY, b.x, b.y, e.x, e.y, b.r + e.r)
					if tt != INF:
						hits.append({"e": e, "t": tt})
		if hits.size() > 1:
			hits.sort_custom(func(p, q): return p.t < q.t)
		for hh in hits:
			var e2 = hh.e
			if _dead(e2) or b.get("_dead", false):
				continue
			b.hitIds[e2.id] = true
			b.lastHit = e2
			hitEnemy(e2, b)
			if b.pierce > 0:
				b.pierce -= 1
				b.damage *= .90 * (1.0 + (float(player.get("piercePower", 0)) if b.source == "player" else 0.0))
				if not b.noProc and b.source == "player":
					Cards.emitCardTrigger("on_pierce", {"enemy": e2, "bullet": b})
			elif ricochetBullet(b, e2):
				break
			else:
				b._dead = true
				break

# ---------------------------------------------------------------- loot / visual updates
func updateLoot(dt: float) -> void:
	var collected: Array = []
	for g in Game.gems:
		if g.get("collected", false):
			continue
		g.life -= dt
		var dx: float = player.x - g.x
		var dy: float = player.y - g.y
		var d: float = _hyp(dx, dy)
		if player.get("globalPickup", false) or d < player.magnet:
			# Loot follows a straight pull line, never a projectile-like outward trail.
			var move: float = minf(d, (1300.0 if player.get("globalPickup", false) else 480.0) * dt)
			var dd: float = d if d != 0.0 else 1.0
			g.x += dx / dd * move
			g.y += dy / dd * move
		if _hyp(player.x - g.x, player.y - g.y) < player.r + 12:
			collected.append(g)
	for g in collected:
		collectGem(g)
	Game.gems = Game.gems.filter(func(g): return not g.get("collected", false) and g.life > 0)

func updateVisualEffects(dt: float) -> void:
	var damp: float = pow(.18, dt)
	for p in Game.particles:
		p.life -= dt
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.vx *= damp
		p.vy *= damp
	Game.particles = _tail(Game.particles.filter(func(p): return p.life > 0), int(PERF.maxParticles))
	for r in Game.rings:
		r.life -= dt
	Game.rings = _tail(Game.rings.filter(func(r): return r.life > 0), int(PERF.maxRings))
	for t in Game.texts:
		t.life -= dt
		t.y -= 24 * dt
	Game.texts = _tail(Game.texts.filter(func(t): return t.life > 0), int(PERF.maxTexts))

# ---------------------------------------------------------------- entities
func sanitizeBullets() -> int:
	var before: int = Game.bullets.size()
	Game.bullets = Game.bullets.filter(func(b): return b != null and is_finite(float(b.x)) and is_finite(float(b.y)) and is_finite(float(b.vx)) and is_finite(float(b.vy)))
	return before - Game.bullets.size()

func ensurePlayerBulletCapacity() -> void:
	var count: int = 0
	for b in Game.bullets:
		if b != null and not b.get("_dead", false) and not b.get("enemy", false):
			count += 1
	if count < PERF.maxPlayerBullets:
		return
	var old = null
	for b in Game.bullets:
		if b != null and not b.get("_dead", false) and not b.get("enemy", false) and not World.pointInCamera(b.x, b.y, 100):
			old = b
			break
	if old == null:
		for b in Game.bullets:
			if b != null and not b.get("_dead", false) and not b.get("enemy", false):
				old = b
				break
	if old != null:
		old._dead = true
	if not Game.projectileUpdating:
		Game.bullets = Game.bullets.filter(func(b): return b != null and not b.get("_dead", false))

func shoot(x: float, y: float, angle: float, damage: float, opts: Dictionary = {}):
	if not is_finite(damage) or damage <= 0:
		return null
	ensurePlayerBulletCapacity()
	var drone: bool = bool(opts.get("drone", false))
	var critChance: float = 0.0 if opts.get("noCrit", false) else (player.crit * .25 if drone else player.crit)
	var crit: bool = randf() < critChance
	var multiplier: float = (1.0 + (player.critMult - 1.0) * .3) if drone else player.critMult
	var speed: float = float(_or(opts.get("speed", null), (600.0 + player.bulletSpeed * .15) if drone else player.bulletSpeed))
	var b: Dictionary = {"x": x, "y": y, "vx": cos(angle) * speed, "vy": sin(angle) * speed,
		"r": _or(opts.get("r", null), 3 if drone else player.bulletSize),
		"life": _or(opts.get("life", null), 1.8), "damage": damage * (multiplier if crit else 1.0), "crit": crit,
		"source": _or(opts.get("source", null), "drone" if drone else "player"),
		"noProc": drone or bool(opts.get("noProc", false)),
		"pierce": _nn(opts, "pierce", 0 if drone else player.pierce),
		"bounces": _nn(opts, "bounces", 0 if drone else player.bulletBounces),
		"bounceGain": 1 if drone else player.bounceDamage,
		"homing": _nn(opts, "homing", 0 if drone else player.homing),
		"homingActivationDist": _nn(opts, "homingActivationDist", 35 if drone else player.homingActivationDist),
		"homingRange": _nn(opts, "homingRange", player.droneRange if drone else player.homingRange),
		"homingLead": _nn(opts, "homingLead", .85 if drone else player.homingLead),
		"homingTurnBoost": _nn(opts, "homingTurnBoost", 1 if drone else player.homingTurnBoost),
		"homingTarget": null, "travelled": 0.0, "fromDrone": drone, "lastHit": null, "hitIds": {}}
	Game.bullets.append(b)
	return b

func nearestEnemyInRange(x: float, y: float, range_: float = INF, exclude = null):
	var target = null
	var best: float = range_ * range_
	for e in Game.enemies:
		if _dead(e) or e.spawnDelay > 0 or (exclude != null and is_same(e, exclude)):
			continue
		var d: float = (e.x - x) * (e.x - x) + (e.y - y) * (e.y - y)
		if d < best:
			best = d
			target = e
	return target

func ricochetBullet(b: Dictionary, hit) -> bool:
	if float(_or(b.get("bounces", 0), 0)) <= 0:
		return false
	var target = null
	var best: float = 720.0 * 720.0
	for e in Game.enemies:
		if _dead(e) or e.spawnDelay > 0 or is_same(e, hit) or b.hitIds.has(e.id):
			continue
		var d: float = U.dist2(e, b)
		if d < best:
			best = d
			target = e
	b.bounces -= 1
	b.lastHit = hit
	b.damage *= float(_or(b.get("bounceGain", 1), 1))
	b.homingTarget = target
	if target != null:
		var sp: float = _hyp(b.vx, b.vy)
		var a: float = atan2(target.y - b.y, target.x - b.x)
		b.vx = cos(a) * sp
		b.vy = sin(a) * sp
	else:
		b.vx = -b.vx
		b.vy = -b.vy
	return true

func firePlayer() -> void:
	var rate: float = player.fireRate * (1.45 if player.playerOverdrive > 0 else 1.0)
	var volleys: int = maxi(1, int(floor(maxf(0.0, -player.shootTimer) * rate)) + 1)
	var rawCount: int = maxi(1, int(floor(player.multishot)))
	var count: int = mini(32, rawCount)
	var weight: float = float(rawCount) / float(count) * volleys
	var a: float = atan2(mouse.y - player.y, mouse.x - player.x)
	var low: float = (1.0 + player.lowHpPower) if player.hp / player.maxHp <= .35 else 1.0
	var boost: float = player.overdrivePower if player.playerOverdrive > 0 else 1.0
	var step: float = minf(.12, float(_or(player.get("spread", 0), .045)))
	for i in count:
		shoot(player.x + cos(a) * 18, player.y + sin(a) * 18, a + (i - (count - 1) / 2.0) * step, player.damage * low * boost * weight)
	var echoChance: float = float(player.get("echoChance", 0))
	if echoChance != 0.0 and randf() < echoChance:
		var echoCount: int = mini(count, 5)
		for i in echoCount:
			shoot(player.x, player.y, a + (i - (echoCount - 1) / 2.0) * step + .025,
				player.damage * low * boost * player.echoDamage * weight, {"silent": true})
	player.shootTimer += volleys / rate
	if Game.particles.size() < PERF.maxParticles:
		Game.particles.append({"x": player.x + cos(a) * 18, "y": player.y + sin(a) * 18, "vx": cos(a) * 90, "vy": sin(a) * 90, "life": .12, "max": .12, "size": 3, "hue": 185})
	_snd("shot")

# ---------------------------------------------------------------- hit / kill / gems
func hitEnemy(e, b: Dictionary) -> void:
	if e == null or _dead(e) or e.spawnDelay > 0:
		return
	var source: String = _or(b.get("source", null), "drone" if b.get("fromDrone", false) else "player")
	var primary: bool = source == "player" and not b.get("noProc", false)
	var damage: float = b.damage
	var thr: float = float(player.get("executeThreshold", 0))
	if primary and thr != 0.0 and e.hp / e.maxHp <= thr:
		if player.get("executeInstant", false) and not e.get("boss", false):
			damage = e.hp * 4
		else:
			damage *= 1.0 + player.executeBonus
	var dealt: float = float(Enemies.dealEnemyDamage(e, damage, source))
	if primary:
		if player.lifesteal > 0:
			Game.healPlayer(dealt * player.lifesteal, "lifesteal")
		if not _dead(e):
			var fc: float = float(player.get("frostChance", 0))
			if fc != 0.0 and randf() < fc:
				e.slow = maxf(e.slow, player.frostDuration)
				e.slowPower = maxf(e.slowPower, player.frostStrength)
			if player.burnPower > 0:
				e.burnTime = 2.5
				e.burnDps = maxf(e.burnDps, player.damage * player.burnPower)
			if player.fracturePower > 0:
				e.fractureStacks += player.fracturePower
		Cards.emitCardTrigger("on_hit", {"enemy": e, "dealt": dealt, "bullet": b})
		if b.get("crit", false):
			Cards.emitCardTrigger("on_crit", {"enemy": e, "dealt": dealt, "bullet": b})
			if randf() < player.chainChance:
				chainLightning(e, dealt * player.chainDamage, int(player.chainTargets))
	if primary and b.get("crit", false) and Game.texts.size() < 20:
		Game.texts.append({"x": e.x, "y": e.y - 18, "text": str(roundi(dealt)) + "!", "life": .45, "max": .45, "hue": 45, "size": 12})
	if Game.particles.size() < PERF.maxParticles:
		Game.particles.append({"x": b.x, "y": b.y, "vx": U.rand(-40, 40), "vy": U.rand(-40, 40), "life": .16, "max": .16, "size": 2, "hue": e.hue})

func chainLightning(origin, damage: float, hops: int = 1) -> void:
	if origin == null:
		return
	var current = origin
	var used: Dictionary = {origin.id: true}
	for hop in mini(hops, Game.enemies.size()):
		var target = null
		var best: float = 200.0 * 200.0
		for e in Game.enemies:
			if _dead(e) or e.spawnDelay > 0 or used.has(e.id):
				continue
			var d: float = U.dist2(e, current)
			if d < best:
				best = d
				target = e
		if target == null:
			break
		used[target.id] = true
		if Game.rings.size() < PERF.maxRings:
			Game.rings.append({"x": current.x, "y": current.y, "x2": target.x, "y2": target.y, "line": true, "life": .13, "max": .13, "hue": 190})
		Enemies.dealEnemyDamage(target, damage * pow(.86, hop), "other")
		current = target

func explode(x: float, y: float, damage: float, radius: float, hue: float = 290, noProc: bool = false) -> void:
	if Game.runSettled:
		return
	if World.pointInCamera(x, y, 200):
		_snd("explosion")
	if Game.rings.size() < PERF.maxRings:
		Game.rings.append({"x": x, "y": y, "r": 12, "extent": radius, "life": .3, "max": .3, "hue": hue})
	Game.screenShake = maxf(Game.screenShake, 2.5)
	for e in Game.enemies.duplicate():
		if _dead(e) or e.spawnDelay > 0:
			continue
		var d: float = _hyp(e.x - x, e.y - y)
		if d < radius:
			Enemies.dealEnemyDamage(e, damage * (1.0 - .4 * d / radius), "other")

func dropGem(x: float, y: float, kind: String = "fragment", enemyLevel = null) -> void:
	if enemyLevel == null:
		enemyLevel = Enemies.enemyLevelForWave()
	var type: Dictionary = GEM_TYPES.get(kind, GEM_TYPES.fragment)
	var value: int = maxi(1, roundi(type.xp * (1.0 + .065 * maxf(0.0, float(enemyLevel) - 1.0))))
	if Game.gems.size() >= PERF.maxGems:
		for g in Game.gems:
			if g.kind == kind:
				g.value += value
				g.count = int(_or(g.get("count", 1), 1)) + 1
				g.life = maxf(g.life, 28)
				return
		var merge = null
		for g in Game.gems:
			if g.kind == "fragment" or g.kind == "dense":
				merge = g
				break
		if merge != null:
			var index: int = _index_of(Game.gems, merge)
			var next = null
			for g in Game.gems:
				if not is_same(g, merge) and (g.kind == "fragment" or g.kind == "dense"):
					next = g
					break
			if next != null:
				next.value += merge.value
				Game.gems.remove_at(index)
	Game.gems.append({"x": U.clamp(x, 18, W - 18), "y": U.clamp(y, 18, H - 18), "vx": 0, "vy": 0,
		"r": 10 if kind == "boss" else (8 if kind == "rare" else 6),
		"value": value, "kind": kind, "hue": type.hue, "life": 32, "count": 1})

func collectGem(g) -> void:
	if g == null or g.get("collected", false) or Game.runSettled:
		return
	g.collected = true
	_snd("level" if g.kind == "boss" else "pickup")
	var type: Dictionary = GEM_TYPES.get(g.kind, GEM_TYPES.fragment)
	var cnt: int = int(_or(g.get("count", 1), 1))
	if type.has("heal"):
		Game.healPlayer(player.maxHp * type.heal * cnt, "gem")
	if type.has("rarity"):
		player.rarityCharge += type.rarity * cnt
	if type.has("epic"):
		player.epicGuarantee = true
		player.legendaryCharge = int(_or(player.get("legendaryCharge", 0), 0)) + cnt
	Game.addXP(g.value)
	Cards.emitCardTrigger("on_pickup", {"gem": g})
	Game.score += (3 + g.value) * Game.combo

func comboWindow() -> float:
	# 初期火力でも次の撃破へ繋げやすく、ボス戦では長い攻撃間隔を許容する。
	return 6.0 if Game.bossAlive else 4.2

func killEnemy(e, chained: bool = false, source: String = "player") -> void:
	if e == null or _dead(e) or Game.runSettled:
		return
	e._dead = true
	var is_boss: bool = e.get("boss", false)
	if is_boss or World.pointInCamera(e.x, e.y, 120):
		_snd("bossKill" if is_boss else "kill")
	Game.kills += 1
	Game.comboKills += 1
	Game.comboTimer = comboWindow()
	Game.combo = U.clamp(1.0 + floor(Game.comboKills / 4) * .25, 1, 5)
	Game.maxComboRun = maxf(Game.maxComboRun, Game.combo)
	Game.score += e.value * 10 * Game.combo
	var primary: bool = source == "player"
	if primary:
		onPrimaryKill(e)
		if Game.comboKills % 10 == 0:
			Cards.emitCardTrigger("on_combo", {"enemy": e, "comboKills": Game.comboKills})
		Cards.emitCardTrigger("on_kill", {"enemy": e})
		if float(player.get("killHeal", 0)) != 0.0:
			Game.healPlayer(player.maxHp * player.killHeal, "kill")
	if is_boss:
		Game.bossAlive = Enemies.activeBosses().size() > 0
		Game.bossesDefeated += 1
		Game.score += 1800 * Game.combo
		queueAbilityReward()
		for b in Game.bullets:
			if b.get("enemy", false) and is_same(b.get("source"), e):
				b._dead = true
		dropGem(e.x, e.y, "boss", e.level)
		dropGem(e.x - 20, e.y + 12, "dense", e.level)
		dropGem(e.x + 20, e.y + 12, "dense", e.level)
		if e.get("finalBoss", false) and Enemies.activeBosses().size() == 0:
			var bossGem = null
			for g in Game.gems:
				if g.kind == "boss" and not g.get("collected", false):
					bossGem = g
					break
			if bossGem != null:
				collectGem(bossGem)
			Game.clearPending = true
		if Game.texts.size() < PERF.maxTexts:
			Game.texts.append({"x": e.x, "y": e.y - 50, "text": "ボス撃破 / スキル獲得権 +1", "life": 1.4, "max": 1.4, "hue": 42, "size": 19})
	else:
		var kind: String
		if e.get("elite", false):
			kind = "rare"
		elif ["tank", "splitter", "bulwark", "bombardier"].has(e.get("type", "")):
			kind = "dense"
		elif e.get("type", "") == "medic":
			kind = "vital"
		elif randf() < .04:
			kind = "rare"
		else:
			kind = "fragment"
		dropGem(e.x, e.y, kind, e.level)
		if e.get("unstable", false):
			Enemies.addHazard({"shape": "circle", "x": e.x, "y": e.y, "radius": 92, "warn": 1.2, "duration": .2, "damage": e.damage * .65, "kind": "normal", "label": "撃破時爆発"})
	# Recursion has a computational budget; drone kills cannot reproduce player procs.
	if source != "drone" and (primary or player.get("chainReaction", false)) and player.explosiveChance > 0 and randf() < player.explosiveChance and Cards.cardProcDepth < 4:
		Cards.cardProcDepth += 1
		explode(e.x, e.y, player.damage * player.explosiveDamage, player.explosiveRadius, e.hue, true)
		Cards.cardProcDepth -= 1
	var se: int = int(player.get("singularityEvery", 0))
	if primary and se > 0 and Game.kills % se == 0:
		explode(e.x, e.y, player.damage * 2.2, 155, 285, true)
	if e.get("split", false) and not is_boss:
		for i in 2:
			var child = Enemies.spawnEnemy("swift")
			if child == null:
				break
			child.x = U.clamp(e.x + (-16 if i == 0 else 16), 20, W - 20)
			child.y = e.y
			child.baseHp *= .5
			child.level = 0
			Enemies.refreshEnemyLevel(child)
			child.spawnDelay = .45
			child.spawnTotal = .45
	var fx: int = 12 if is_boss else 3
	var k: int = 0
	while k < fx and Game.particles.size() < PERF.maxParticles:
		Game.particles.append({"x": e.x, "y": e.y, "vx": U.rand(-100, 100), "vy": U.rand(-100, 100), "life": .4, "max": .4, "size": 2, "hue": e.hue})
		k += 1
	Game.screenShake = maxf(Game.screenShake, 5.0 if is_boss else 1.0)
