extends Node
## Enemies — port of NEON FRACTURE enemy logic (index.html 7404-7550, 7978-8016, 8721-8871).
## Enemy objects are Dictionaries with the original keys.

var ENEMY_TYPES: Dictionary = {}
var CUSTOM_ENEMY_IDS: Array = []
var CUSTOM_BOSS_IDS: Array = []

const SPAWN_SAFE_DISTANCE: float = 850.0
const SPAWN_TELEGRAPH: float = 0.58

# Run-state owned here (reset by Game.resetRunSystems: bossPopulationTimer=.6, finalBossEncounterStarted=false).
var bossPopulationTimer: float = 0.0
var finalBossEncounterStarted: bool = false

func _ready() -> void:
	var f := FileAccess.open("res://data/defs.json", FileAccess.READ)
	if f == null:
		push_error("Enemies: cannot open defs.json")
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	ENEMY_TYPES = d.get("enemy_types", {})
	CUSTOM_ENEMY_IDS = d.get("custom_enemy_ids", [])
	CUSTOM_BOSS_IDS = d.get("custom_boss_ids", [])

# ---------------------------------------------------------------- levels

func enemyLevelForWave(w = null, c = null) -> int:
	var wv: int = Game.wave if w == null else int(w)
	var cc: Dictionary = Meta.challenge() if c == null else c
	var dev: Dictionary = Meta.developerRun
	if dev.get("active", false) and dev.get("enemyLevel") != null:
		return int(dev.enemyLevel)
	var n: float = float(maxi(0, wv - 1))
	var rate: float = float(cc.get("levelRate", 2))
	var start: float = float(cc.get("startLevel", 1))
	return int(start) + floori(rate * n + 0.012 * maxf(0.0, rate - 2.0) * n * n) + floori(n / 5.0)

func enemyScaling(lv: int, boss: bool = false, c = null) -> Dictionary:
	var cc: Dictionary = Meta.challenge() if c == null else c
	var dev: Dictionary = Meta.developerRun
	var q: float = float(maxi(0, lv - 1))
	var pressure: float = maxf(0.0, float(cc.get("levelRate", 2)) - 2.0) / 4.0
	var devOn: bool = dev.get("active", false)
	var hpGrowth: float = float(cc.hpGrowth)
	var dmgGrowth: float = float(cc.damageGrowth)
	return {
		"hp": (1.0 + ((0.095 if boss else 0.115) * q + (0.0022 if boss else 0.0025) * q * q) * hpGrowth) * (float(dev.enemyHp) if devOn else 1.0),
		"damage": (1.0 + (0.10 * floorf(q / 2.0) + 0.0009 * pressure * q * q) * dmgGrowth) * (float(dev.enemyDamage) if devOn else 1.0),
	}

func refreshEnemyLevel(e: Dictionary) -> void:
	var lv: int = enemyLevelForWave()
	if e.level == lv:
		return
	var hpRatio: float = U.clamp(e.hp / e.maxHp, 0.0, 1.0) if e.maxHp > 0 else 1.0
	e.level = lv
	var growth: Dictionary = enemyScaling(lv, e.boss)
	e.maxHp = e.baseHp * growth.hp * (1.7 if e.elite else 1.0)
	e.hp = e.maxHp * hpRatio
	e.damage = e.baseDamage * growth.damage * (1.3 if e.elite else 1.0)
	e.armored = e.type == "bulwark" or (e.elite and lv >= 13)
	e.unstable = e.elite and lv >= 25 and e.type != "medic"

func enemyName(e: Dictionary) -> String:
	if e.boss:
		var names := {"warden": "防衛異常体", "spinner": "回転異常体", "hunter": "追跡異常体"}
		return names.get(e.bossKind, "異常体")
	if ENEMY_TYPES.has(e.type):
		return ENEMY_TYPES[e.type].name
	return "追跡機"

# ---------------------------------------------------------------- abilities / geometry

func enemyAbilityTick(e: Dictionary, dt: float) -> void:
	e.abilityTimer -= dt
	if e.type == "medic" and e.abilityTimer <= 0:
		e.abilityTimer = 3.5
		var n: int = 0
		for ally in Game.enemies:
			if is_same(ally, e) or ally.get("_dead", false) or ally.spawnDelay > 0 or ally.boss or U.dist2(ally, e) > 300.0 * 300.0:
				continue
			ally.hp = minf(ally.maxHp, ally.hp + ally.maxHp * 0.055)
			ally.hitFlash = 0.06
			if Game.rings.size() < Game.PERF.maxRings:
				Game.rings.push_back({"x": e.x, "y": e.y, "x2": ally.x, "y2": ally.y, "line": true, "life": 0.22, "max": 0.22, "hue": 145})
			n += 1
			if n >= 3:
				break
	if e.type == "bulwark" and e.abilityTimer <= 0:
		e.abilityTimer = 2.4
		for ally in Game.enemies:
			if ally.get("_dead", false) or ally.boss or U.dist2(ally, e) > 200.0 * 200.0:
				continue
			ally.protectedUntil = Game.time + 1.4

func segmentCircleT(x1: float, y1: float, x2: float, y2: float, cx: float, cy: float, r: float) -> float:
	var dx: float = x2 - x1
	var dy: float = y2 - y1
	var fx: float = x1 - cx
	var fy: float = y1 - cy
	var a: float = dx * dx + dy * dy
	var c: float = fx * fx + fy * fy - r * r
	if c <= 0:
		return 0.0
	if a < 1e-12:
		return INF
	var b: float = 2.0 * (fx * dx + fy * dy)
	var disc: float = b * b - 4.0 * a * c
	if disc < 0:
		return INF
	var t: float = (-b - sqrt(disc)) / (2.0 * a)
	return t if (t >= 0.0 and t <= 1.0) else INF

func distanceToSegment(px: float, py: float, x1: float, y1: float, x2: float, y2: float) -> float:
	var dx: float = x2 - x1
	var dy: float = y2 - y1
	var den: float = dx * dx + dy * dy
	if den == 0.0:
		den = 1.0
	var t: float = U.clamp(((px - x1) * dx + (py - y1) * dy) / den, 0.0, 1.0)
	var ex: float = px - x1 - t * dx
	var ey: float = py - y1 - t * dy
	return sqrt(ex * ex + ey * ey)

# ---------------------------------------------------------------- hazards / projectiles

func addHazard(spec: Dictionary) -> void:
	if Game.hazards.size() >= 48:
		return
	var player: Dictionary = Game.player
	if World.pointInCamera(spec.get("x", player.x), spec.get("y", player.y), 180):
		Audio.Sound.play("warning")
	var h := {"age": 0.0, "warn": 1.05, "duration": 0.22, "hit": false, "kind": "normal", "label": "危険区域"}
	h.merge(spec, true)
	Game.hazards.push_back(h)

func telegraphShot(e: Dictionary, a: float, kind: String = "normal", spread: float = 0.0) -> void:
	if not World.pointInCamera(e.x, e.y, 180):
		return
	var label: String = "破壊・付与封印" if kind == "break" else ("バリア貫通" if kind == "pierce" else "射撃予告")
	addHazard({"shape": "shot", "x": e.x, "y": e.y, "a": a, "length": 900, "warn": 0.55 if kind == "normal" else 1.05,
		"duration": 0.08, "kind": kind, "source": e, "damage": e.damage * 0.8, "label": label, "spread": spread})

func fireEnemyProjectile(x: float, y: float, a: float, speed: float, damage: float, kind: String = "normal", source = null) -> void:
	var cnt: int = 0
	for b in Game.bullets:
		if not b.get("_dead", false) and b.get("enemy", false):
			cnt += 1
	if cnt >= Game.PERF.maxEnemyBullets:
		return
	var isBoss: bool = source != null and source.get("boss", false)
	Game.bullets.push_back({"x": x, "y": y, "vx": cos(a) * speed, "vy": sin(a) * speed,
		"r": 5.5 if kind == "normal" else 8.0, "life": 4.3, "damage": damage, "enemy": true, "attackKind": kind,
		"source": source, "lock": 4 if isBoss else 3, "hue": 320 if kind == "break" else 15})

func updateHazards(dt: float) -> void:
	var player: Dictionary = Game.player
	for h in Game.hazards:
		if h.get("dead", false):
			continue
		var src = h.get("source")
		if src != null and src.get("_dead", false) and h.age < h.warn:
			h.dead = true
			continue
		h.age += dt
		if h.age >= h.warn and not h.hit:
			if h.shape == "shot":
				var offs: Array = [-h.spread, 0.0, h.spread] if h.get("spread", 0.0) != 0.0 else [0.0]
				for offset in offs:
					fireEnemyProjectile(h.x, h.y, h.a + offset, 280.0, h.damage, h.kind, src)
				h.hit = true
			else:
				var inside: bool
				if h.shape == "line":
					inside = distanceToSegment(player.x, player.y, h.x, h.y, h.x2, h.y2) <= h.width / 2.0 + player.r
				else:
					var ddx: float = player.x - h.x
					var ddy: float = player.y - h.y
					inside = sqrt(ddx * ddx + ddy * ddy) <= h.radius + player.r
				if inside:
					h.hit = true
					var lockv: int = 4 if (src != null and src.get("boss", false)) else 3
					Game.damagePlayer(h.damage, {"kind": h.kind, "enemy": src, "lock": lockv})
					if Game.state != "playing":
						return
		if h.age >= h.warn + h.duration:
			h.dead = true
	Game.hazards = Game.hazards.filter(func(hh): return not hh.get("dead", false))

func bossSpecial(e: Dictionary) -> void:
	if not World.pointInCamera(e.x, e.y, 180):
		return
	var player: Dictionary = Game.player
	var ratio: float = e.hp / e.maxHp
	var phase: int = 1 if ratio > 0.65 else (2 if ratio > 0.30 else 3)
	var seq: int = e.specialSequence
	e.specialSequence += 1
	var a: float = atan2(player.y - e.y, player.x - e.x)
	if e.bossKind == "warden":
		if seq % 2 == 0:
			addHazard({"shape": "circle", "x": player.x, "y": player.y, "radius": 125 + phase * 10, "warn": 1.35, "duration": 0.24,
				"damage": e.damage * 0.9, "kind": "break", "source": e, "label": "バリア破壊 / 付与封印"})
		else:
			for i in range(2 if phase >= 2 else 1):
				var angle: float = a + i * PI / 2.0
				addHazard({"shape": "line", "x": e.x, "y": e.y, "x2": e.x + cos(angle) * 1050, "y2": e.y + sin(angle) * 1050,
					"width": 26, "warn": 1.2, "duration": 0.22, "damage": e.damage, "kind": "pierce", "source": e, "label": "貫通レーザー"})
	elif e.bossKind == "spinner":
		var count: int = phase + 1
		for i in range(count):
			var angle2: float = a + 0.25 + i * TAU / count
			var brk: bool = seq % 3 == 2
			addHazard({"shape": "line", "x": e.x, "y": e.y, "x2": e.x + cos(angle2) * 960, "y2": e.y + sin(angle2) * 960,
				"width": 24, "warn": 1.25, "duration": 0.2, "damage": e.damage * 0.9, "kind": "break" if brk else "normal",
				"source": e, "label": "封印光線" if brk else "放射レーザー"})
	else:
		var tx: float = U.clamp(player.x + player.vx * 0.3, 50, World.W - 50)
		var ty: float = U.clamp(player.y + player.vy * 0.3, 50, World.H - 50)
		var odd: bool = seq % 2 != 0
		addHazard({"shape": "circle", "x": tx, "y": ty, "radius": 110, "warn": 1.15, "duration": 0.3,
			"damage": e.damage, "kind": "wound" if odd else "pierce", "source": e, "label": "侵食砲撃" if odd else "貫通砲撃"})
		if phase >= 2:
			telegraphShot(e, a, "break")
	if e.level >= 23 and seq % 3 == 2:
		var nonBoss: int = 0
		for x in Game.enemies:
			if not x.get("_dead", false) and not x.boss:
				nonBoss += 1
		if nonBoss < 10:
			var support = spawnEnemy("medic" if seq % 2 != 0 else "disruptor")
			if support != null:
				support.x = U.clamp(e.x + 110, 50, World.W - 50)
				support.y = U.clamp(e.y + 100, 50, World.H - 50)
				support.spawnDelay = 1.2
				support.spawnTotal = 1.2

# Damage is attributed explicitly: drone shots never inherit trigger chains.
func dealEnemyDamage(e, amount: float, source: String = "player", options: Dictionary = {}) -> float:
	if e == null or e.get("_dead", false) or e.spawnDelay > 0 or not is_finite(amount) or amount <= 0:
		return 0.0
	var player: Dictionary = Game.player
	if source == "drone":
		var dc: Dictionary = UI.droneConfig
		if not dc.enabled or not UI.droneTargetAllowed(e):
			return 0.0
		amount *= float(dc.output) / 100.0
		if amount <= 0:
			return 0.0
	var defense: float = 1.0 if options.get("ignoreArmor", false) else ((0.78 if e.get("armored", false) else 1.0) * (0.83 if float(e.get("protectedUntil", 0.0)) > Game.time else 1.0))
	var marked: float = 1.0 + 0.065 * sqrt(float(e.get("fractureStacks", 0)))
	var bossMul: float = (1.0 + float(player.get("bossDamage", 0.0))) if (e.boss and source != "drone") else 1.0
	var dealt: float = minf(e.hp, amount * defense * marked * bossMul)
	e.hp = maxf(0.0, e.hp - dealt)
	e.hitFlash = 0.065
	var key: String = source if Game.runDamageTotals.has(source) else "other"
	Game.runDamageTotals[key] += dealt
	Game.maxHitDamageRun = maxf(Game.maxHitDamageRun, dealt)
	if e.hp <= 0:
		Combat.killEnemy(e, true, source)
	return dealt

# ---------------------------------------------------------------- update

func updateEnemies(dt: float) -> void:
	var player: Dictionary = Game.player
	for e in Game.enemies.duplicate():
		if e.get("_dead", false):
			continue
		e.hitFlash = maxf(0.0, e.hitFlash - dt)
		if e.spawnDelay > 0:
			e.spawnDelay = maxf(0.0, e.spawnDelay - dt)
			continue
		e.slow = maxf(0.0, e.slow - dt)
		if e.slow <= 0:
			e.slowPower = 0.0
		if e.burnTime > 0:
			e.burnTime = maxf(0.0, e.burnTime - dt)
			dealEnemyDamage(e, e.burnDps * dt, "other")
			if e.get("_dead", false):
				continue
		enemyAbilityTick(e, dt)
		e.shootTimer -= dt
		e.specialTimer -= dt
		e.chargeTimer -= dt
		var pdx: float = player.x - e.x
		var pdy: float = player.y - e.y
		var a: float = atan2(pdy, pdx)
		var distance: float = sqrt(pdx * pdx + pdy * pdy)
		var speed: float = e.speed * ((1.0 - e.slowPower * (0.6 if e.boss else 1.0)) if e.slow > 0 else 1.0)
		if e.charge and e.windup <= 0 and e.chargeTime <= 0 and e.chargeTimer <= 0 and distance < 520:
			e.windup = 0.7
			e.chargeTimer = 3.7
			e.chargeAngle = a
		if e.windup > 0:
			e.windup -= dt
			e.vx *= 0.85
			e.vy *= 0.85
			if e.windup <= 0:
				e.chargeTime = 0.5
				e.vx = cos(e.chargeAngle) * 245.0
				e.vy = sin(e.chargeAngle) * 245.0
		elif e.chargeTime > 0:
			e.chargeTime = maxf(0.0, e.chargeTime - dt)
		else:
			var preferred: float = 320.0 if e.boss else (280.0 if e.shoot else (360.0 if e.type == "medic" else 0.0))
			var drive: float = 1.0
			if preferred != 0.0:
				drive = -0.45 if distance < preferred * 0.8 else (0.10 if distance < preferred * 1.1 else 1.0)
			var tx: float = cos(a) * speed * drive
			var ty: float = sin(a) * speed * drive
			if e.orbit:
				tx += cos(a + PI / 2.0) * speed * 0.7
				ty += sin(a + PI / 2.0) * speed * 0.7
			if e.boss:
				e.phase += dt * 0.65
				tx += cos(e.phase) * speed * 0.4
				ty += sin(e.phase) * speed * 0.25
			var tlen: float = sqrt(tx * tx + ty * ty)
			if tlen > speed:
				tx = tx / tlen * speed
				ty = ty / tlen * speed
			var follow: float = 1.0 - exp(-dt * (2.5 if e.boss else 4.2))
			e.vx += (tx - e.vx) * follow
			e.vy += (ty - e.vy) * follow
		e.x = clampf(e.x + e.vx * dt, e.r, World.W - e.r)
		e.y = clampf(e.y + e.vy * dt, e.r, World.H - e.r)
		if not e.boss and distance > Game.ACTIVE_DESPAWN_DISTANCE:
			e._dead = true
			continue
		if e.shoot and e.shootTimer <= 0 and distance < 950 and World.pointInCamera(e.x, e.y, 160):
			enemyShoot(e)
		if e.boss and e.specialTimer <= 0 and distance < 1250:
			bossSpecial(e)
			e.specialTimer = (6.0 - (1.0 if e.hp / e.maxHp < 0.5 else 0.0)) / sqrt(float(Meta.challenge().attack))
		var cdx: float = e.x - player.x
		var cdy: float = e.y - player.y
		if sqrt(cdx * cdx + cdy * cdy) < e.r + player.r:
			Game.damagePlayer(e.damage, {"kind": "normal", "enemy": e})
			if Game.state != "playing":
				return
			var push: float = atan2(e.y - player.y, e.x - player.x)
			e.vx += cos(push) * 80.0
			e.vy += sin(push) * 80.0
	Game.enemies = Game.enemies.filter(func(en): return not en.get("_dead", false))

# ---------------------------------------------------------------- spawning

func isBossOnly() -> bool:
	var rc: Dictionary = Meta.runConfig
	return rc.difficulty == "custom" and rc.custom.rosterMode == "bossOnly"

func activeBosses() -> Array:
	return Game.enemies.filter(func(e): return e.boss and not e.get("_dead", false))

func maxConcurrentBosses() -> int:
	if Meta.developerRun.get("active", false):
		return 3
	if isBossOnly():
		return int(Meta.cleanCustomConfig(Meta.runConfig.custom).bossLimit)
	return 1

func normalEnemyAllowed(type) -> bool:
	if not CUSTOM_ENEMY_IDS.has(type):
		return false
	if Meta.developerRun.get("active", false):
		return true
	var rc: Dictionary = Meta.runConfig
	if rc.difficulty != "custom":
		return true
	var c: Dictionary = rc.custom
	return c.rosterMode != "bossOnly" and (c.rosterMode != "selected" or c.enemyTypes.has(type))

func enemyTypeForWave():
	if isBossOnly():
		return null
	var rc: Dictionary = Meta.runConfig
	if rc.difficulty == "custom" and rc.custom.rosterMode == "selected":
		var ids: Array = rc.custom.enemyTypes.filter(func(id): return CUSTOM_ENEMY_IDS.has(id))
		return U.pick(ids) if ids.size() > 0 else null
	var lv: int = enemyLevelForWave()
	var table: Array = [["chaser", 32], ["swift", 16], ["tank", 11 if lv >= 3 else 0], ["shooter", 11 if lv >= 3 else 0],
		["splitter", 8 if lv >= 7 else 0], ["charger", 9 if lv >= 7 else 0], ["orbiter", 8 if lv >= 11 else 0],
		["disruptor", 8 if lv >= 5 else 0], ["lancer", 8 if lv >= 9 else 0], ["bombardier", 7 if lv >= 13 else 0],
		["medic", 6 if lv >= 9 else 0], ["bulwark", 6 if lv >= 13 else 0], ["suppressor", 7 if lv >= 17 else 0]]
	var caps := {"disruptor": 4, "lancer": 4, "bombardier": 4, "medic": 3, "bulwark": 3, "suppressor": 4}
	var counts := {}
	for e in Game.enemies:
		if not e.get("_dead", false):
			counts[e.type] = counts.get(e.type, 0) + 1
	for t in table:
		if caps.has(t[0]) and counts.get(t[0], 0) >= caps[t[0]]:
			t[1] = 0
	var total: float = 0.0
	for t in table:
		total += t[1]
	var r: float = randf() * total
	for t in table:
		r -= t[1]
		if r < 0:
			return t[0]
	return null

func chooseSpawnPoint(boss: bool = false) -> Dictionary:
	var player: Dictionary = Game.player
	var fallback := {"x": U.clamp(player.x + 900, 70, World.W - 70), "y": player.y}
	for attempt in range(28):
		var a: float = U.rand(0.0, TAU)
		var d: float = U.rand(690.0 if boss else 900.0, 840.0 if boss else 1220.0)
		var x: float = U.clamp(player.x + cos(a) * d, 70, World.W - 70)
		var y: float = U.clamp(player.y + sin(a) * d, 70, World.H - 70)
		fallback = {"x": x, "y": y}
		var dx: float = x - player.x
		var dy: float = y - player.y
		if sqrt(dx * dx + dy * dy) < (620.0 if boss else SPAWN_SAFE_DISTANCE):
			continue
		if World.pointInCamera(x, y, 75):
			continue
		return {"x": x, "y": y}
	return fallback

func spawnEnemy(type = "__wave", boss: bool = false, debugBossKind = null):
	if typeof(type) == TYPE_STRING and type == "__wave":
		type = enemyTypeForWave()
	if boss and activeBosses().size() >= maxConcurrentBosses():
		return null
	if not boss and not normalEnemyAllowed(type):
		return null
	if not boss:
		var live: int = 0
		for e0 in Game.enemies:
			if not e0.get("_dead", false):
				live += 1
		if live >= Game.PERF.maxEnemies:
			return null
	var p: Dictionary = chooseSpawnPoint(boss)
	var cfg: Dictionary = Meta.challenge()
	var d: Dictionary = ENEMY_TYPES.get(type, ENEMY_TYPES.chaser)
	var bossKind = null
	if boss:
		var allowed: Array
		if Meta.developerRun.get("active", false) and CUSTOM_BOSS_IDS.has(debugBossKind):
			allowed = [debugBossKind]
		elif Meta.runConfig.difficulty == "custom":
			allowed = Meta.runConfig.custom.bossTypes
		else:
			allowed = CUSTOM_BOSS_IDS
		if allowed.is_empty():
			return null
		bossKind = allowed[Game.bossSpawnSerial % allowed.size()]
		Game.bossSpawnSerial += 1
		var defs := {
			"warden": {"r": 43, "hp": 1080, "speed": 40, "damage": 35, "value": 360, "hue": 330, "shoot": true},
			"spinner": {"r": 40, "hp": 1020, "speed": 43, "damage": 32, "value": 360, "hue": 275, "shoot": true},
			"hunter": {"r": 37, "hp": 970, "speed": 48, "damage": 34, "value": 360, "hue": 18, "shoot": true}}
		d = defs[bossKind]
	var elite: bool = (not boss) and Game.wave >= 3 and randf() < minf(0.62, (0.04 + Game.wave * 0.015) * float(cfg.elite))
	Game.enemySerial += 1
	var e := {"id": Game.enemySerial, "x": p.x, "y": p.y, "vx": 0.0, "vy": 0.0, "type": type,
		"r": float(d.r) + (2.0 if elite else 0.0),
		"baseHp": float(d.hp), "baseDamage": float(d.damage), "hp": float(d.hp), "maxHp": float(d.hp), "level": 0,
		"speed": float(d.speed), "damage": float(d.damage),
		"value": floori(float(d.value) * (2 if elite else 1)), "hue": d.hue, "elite": elite,
		"shoot": d.get("shoot", false), "split": d.get("split", false), "charge": d.get("charge", false),
		"orbit": d.get("orbit", false), "boss": boss, "bossKind": bossKind,
		"finalBoss": boss and Meta.isFinalClearWave(),
		"spawnDelay": 1.1 if boss else 0.7, "spawnTotal": 1.1 if boss else 0.7,
		"shootTimer": 1.15, "abilityTimer": U.rand(1.3, 2.5), "specialTimer": 2.8, "specialSequence": 0,
		"chargeTimer": U.rand(1.5, 2.5), "chargeTime": 0.0, "windup": 0.0, "chargeAngle": 0.0,
		"slow": 0.0, "slowPower": 0.0, "hitFlash": 0.0, "phase": U.rand(0.0, TAU), "burnTime": 0.0, "burnDps": 0.0,
		"fractureStacks": 0}
	refreshEnemyLevel(e)
	Game.enemies.push_back(e)
	if boss:
		Game.bossAlive = true
	return e

func spawnBoss() -> bool:
	if Game.runSettled or Game.clearPending or activeBosses().size() >= maxConcurrentBosses():
		return false
	var rc: Dictionary = Meta.runConfig
	if rc.difficulty == "custom" and not isBossOnly() and not rc.custom.bossEnabled and not Meta.isFinalClearWave():
		return false
	var wasEmpty: bool = activeBosses().size() == 0
	var e = spawnEnemy("boss", true)
	if e == null:
		return false
	Game.bossAlive = true
	# Additional bosses never clear another live boss's projectiles.
	if wasEmpty:
		Game.bossWarningTimer = 1.35
		for b in Game.bullets:
			if b != null and b.get("enemy", false):
				b._dead = true
		UI.hook("showBossWarning", [])
	Cards.emitCardTrigger("on_boss_spawn", {"wave": Game.wave, "enemy": e})
	Audio.Sound.play("boss")
	return true

func validateRunSetup() -> String:
	var rc: Dictionary = Meta.runConfig
	if rc.difficulty != "custom":
		return ""
	var c: Dictionary = rc.custom
	if c.rosterMode == "selected" and c.enemyTypes.is_empty():
		return "出現させる通常敵を1種類以上選んでください。"
	if (c.bossEnabled or c.rosterMode == "bossOnly" or rc.mode == "clear") and c.bossTypes.is_empty():
		return "ボスを1種類以上選んでください。"
	return ""

func updateEncounterPopulation(dt: float) -> void:
	Game.bossAlive = activeBosses().size() > 0
	var cfg: Dictionary = Meta.challenge()
	if isBossOnly():
		# No trash enemies, summons or split children.
		if Meta.isFinalClearWave():
			var live: Array = activeBosses()
			if live.size() > 0:
				for e in live:
					e.finalBoss = true
				finalBossEncounterStarted = true
			elif not finalBossEncounterStarted and not Game.clearPending:
				if spawnBoss():
					finalBossEncounterStarted = true
			return
		bossPopulationTimer -= dt
		if bossPopulationTimer <= 0 and activeBosses().size() < maxConcurrentBosses():
			spawnBoss()
			bossPopulationTimer = 4.0 / sqrt(float(cfg.density))
		return
	Game.spawnTimer -= dt
	if Game.spawnTimer <= 0 and Game.bossWarningTimer <= 0:
		var regular: int = 0
		for e2 in Game.enemies:
			if not e2.get("_dead", false) and not e2.boss:
				regular += 1
		var density: float = float(cfg.density)
		var cap: int
		if Game.bossAlive:
			cap = roundi(7.0 + density * 2.0)
		else:
			cap = mini(int(Game.PERF.maxEnemies) - 2, roundi((22.0 + Game.wave * 2.1) * density))
		var batch: int
		if Game.bossAlive:
			batch = 1
		else:
			batch = maxi(2, roundi((2 + floori(Game.wave / 8.0)) * density))
		var i: int = 0
		while i < batch and regular + i < cap:
			spawnEnemy()
			i += 1
		Game.spawnTimer = maxf(0.18, 0.53 - minf(Game.wave, 24) * 0.012) / sqrt(density) * (2.0 if Game.bossAlive else 1.0)

func enemyShoot(e: Dictionary) -> void:
	var player: Dictionary = Game.player
	var a: float = atan2(player.y - e.y, player.x - e.x)
	var cfg: Dictionary = Meta.challenge()
	var attack: float = float(cfg.attack)
	if not e.boss:
		if e.type == "disruptor" or e.type == "lancer":
			telegraphShot(e, a, "break" if e.type == "disruptor" else "pierce")
			e.shootTimer = 4.5 if e.type == "disruptor" else 3.7
			return
		if e.type == "bombardier":
			if World.pointInCamera(e.x, e.y, 160):
				addHazard({"shape": "circle", "x": player.x, "y": player.y, "radius": 100,
					"warn": 1.3, "duration": 0.28, "damage": e.damage, "kind": "normal", "source": e, "label": "砲撃予告"})
			e.shootTimer = 4.2
			return
		var spread: Array = [-0.14, 0.0, 0.14] if (e.orbit or attack >= 1.4) else [0.0]
		for da in spread:
			fireEnemyProjectile(e.x, e.y, a + da, 215.0, e.damage * 0.65, "wound" if e.type == "suppressor" else "normal", e)
		e.shootTimer = 2.3 / sqrt(attack)
		return
	var ratio: float = e.hp / e.maxHp
	var phase: int = 1 if ratio > 0.65 else (2 if ratio > 0.30 else 3)
	if e.bossKind == "spinner":
		var count: int = 8 + phase * 2
		var gap: int = (e.specialSequence + phase) % count
		for i in range(count):
			if i != gap and i != (gap + 1) % count:
				fireEnemyProjectile(e.x, e.y, e.phase + i * TAU / count, 195.0, e.damage * 0.62, "normal", e)
	else:
		var count2: int = (3 + 2 * (phase - 1)) if e.bossKind == "hunter" else (3 + phase * 2)
		for i in range(count2):
			fireEnemyProjectile(e.x, e.y, a + (i - (count2 - 1) / 2.0) * 0.14, 270.0 if e.bossKind == "hunter" else 215.0, e.damage * 0.7, "normal", e)
		if phase == 3 and attack >= 1.6:
			for i in range(6):
				fireEnemyProjectile(e.x, e.y, e.phase + i * TAU / 6.0, 155.0, e.damage * 0.5, "normal", e)
	e.shootTimer = (1.65 - 0.2 * (phase - 1)) / sqrt(attack)

func syncDrones() -> void:
	# Only visual agents are batched. Logical drone count, damage, rate and training keep growing.
	var player: Dictionary = Game.player
	var visual: int = mini(8, maxi(0, floori(float(player.droneCount))))
	while Game.drones.size() < visual:
		Game.drones.push_back({"angle": U.rand(0.0, TAU), "shootTimer": U.rand(0.0, 0.5), "x": player.x, "y": player.y, "shotCredit": 0.0, "target": null})
	Game.drones.resize(visual)
