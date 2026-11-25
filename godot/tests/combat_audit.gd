extends Node
## Headless numeric tests for Combat. Run: godot --headless --path godot res://tests/combat_audit.tscn
var fails: int = 0

func ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", msg)

func near(a: float, b: float, msg: String, eps: float = 1e-6) -> void:
	ok(absf(a - b) <= eps, "%s: got %s want %s" % [msg, a, b])

func mk(id: int, x: float, y: float, hp: float = 1000.0) -> Dictionary:
	var e: Dictionary
	e = {"id": id, "x": x, "y": y, "r": 12.0, "hp": hp, "maxHp": hp, "spawnDelay": 0.0, "slow": 0.0, "slowPower": 0.0,
		"hitFlash": 0.0, "hue": 0, "value": 1, "level": 1, "fractureStacks": 0, "burnTime": 0.0, "burnDps": 0.0, "vx": 0.0, "vy": 0.0, "boss": false, "elite": false}
	Game.enemies.append(e)
	return e

func _ready() -> void:
	UI.load_drone_config()
	World.generateWorld()
	var rc: Dictionary = Meta.cleanRunConfig({"mode": "endless", "difficulty": "easy"})
	Meta.runConfig = rc
	Meta.developerRun = Meta.freshDeveloperRun()
	ok(Game.resetGame(), "resetGame")
	Game.state = "playing"
	Game.enemies.clear()
	Game.bullets.clear()
	var p: Dictionary = Game.player
	p.x = 500.0
	p.y = 500.0
	p.damage = 10.0
	p.crit = 0.0
	p.critMult = 2.0
	p.lifesteal = 0.0
	p.executeThreshold = 0
	p.frostChance = 0
	p.burnPower = 0
	p.fracturePower = 0
	p.chainChance = 0.0

	# --- explosion falloff: dmg*(1-.4*d/r), strictly < radius
	var a := mk(1, 1000, 1000)
	var b := mk(2, 1050, 1000)
	var c := mk(3, 1100, 1000)  # d == radius -> not hit
	Combat.explode(1000, 1000, 100.0, 100.0)
	near(1000.0 - a.hp, 100.0 * 1.0, "explode d=0")
	near(1000.0 - b.hp, 100.0 * (1.0 - .4 * .5), "explode d=50")
	near(1000.0 - c.hp, 0.0, "explode d==radius")
	Game.enemies.clear()

	# --- chain lightning: hop count, 0.86^hop falloff, range 200, no repeats
	var o := mk(10, 300, 300, 1e9)
	var xs: Array = []
	for i in 5:
		xs.append(mk(11 + i, 300 + 150 * (i + 1), 300, 1e9))
	Combat.chainLightning(o, 100.0, 3)
	near(1e9 - xs[0].hp, 100.0, "chain hop0")
	near(1e9 - xs[1].hp, 86.0, "chain hop1", 1e-3)
	near(1e9 - xs[2].hp, 100.0 * .86 * .86, "chain hop2", 1e-3)
	near(1e9 - xs[3].hp, 0.0, "chain only 3 hops", 1e-3)
	near(1e9 - o.hp, 0.0, "chain origin untouched", 1e-3)
	Game.enemies.clear()

	# --- friendlyArc: first hop range 800, later 340, count
	var f0 := mk(20, 500, 500 + 700, 1e9)
	var f1 := mk(21, 500, 500 + 700 + 330, 1e9)
	var f2 := mk(22, 500, 500 + 700 + 330 + 345, 1e9)
	Combat.friendlyArc(500, 500, 50.0, "other", 4)
	near(1e9 - f0.hp, 50.0, "arc hop0")
	near(1e9 - f1.hp, 50.0, "arc hop1 (330<340)")
	near(1e9 - f2.hp, 0.0, "arc hop2 (345>340)")
	Game.enemies.clear()

	# --- shoot/hit: crit multiplier, lifesteal, execute
	p.crit = 2.0  # always crit
	var bl = Combat.shoot(0, 0, 0.0, 10.0, {"noCrit": true})
	ok(not bl.crit and bl.damage == 10.0, "noCrit")
	var bc = Combat.shoot(0, 0, 0.0, 10.0)
	near(bc.damage, 20.0, "crit x2")
	p.crit = 4.0  # drone crit chance is crit*.25 -> 1.0 (deterministic)
	var dr = Combat.shoot(0, 0, 0.0, 10.0, {"drone": true})
	p.crit = 2.0
	near(dr.damage, 10.0 * (1.0 + (2.0 - 1.0) * .3), "drone crit mult")
	ok(dr.noProc and dr.source == "drone", "drone flags")
	ok(Combat.shoot(0, 0, 0.0, 0.0) == null and Combat.shoot(0, 0, 0.0, NAN) == null, "shoot rejects 0/NaN")
	p.crit = 0.0
	Game.bullets.clear()

	var t := mk(30, 700, 700, 1000.0)
	p.executeThreshold = .5
	p.executeBonus = .5
	t.hp = 400.0
	var bb := {"x": 700, "y": 700, "damage": 100.0, "source": "player", "crit": false, "noProc": false}
	Combat.hitEnemy(t, bb)
	near(400.0 - t.hp, 150.0, "execute bonus")
	p.executeInstant = true
	t.hp = 400.0
	Combat.hitEnemy(t, bb)
	near(400.0 - t.hp, 400.0, "execute instant caps at hp")
	p.executeThreshold = 0
	Game.enemies.clear()

	# --- projectile sweep ties: bullet starting inside two overlapping enemies hits in array order
	Game.enemies.clear()
	Game.bullets.clear()
	var e1 := mk(40, 900, 900, 1e9)
	var e2 := mk(41, 905, 900, 1e9)
	var e3 := mk(42, 910, 900, 1e9)
	var bp = Combat.shoot(905, 900, 0.0, 10.0, {"pierce": 5, "bounces": 0, "homing": 0})
	var order: Array = []
	# wrap damage observation via hp deltas after one step
	Combat.updateProjectiles(1.0 / 60.0)
	ok(bp.hitIds.has(40) and bp.hitIds.has(41) and bp.hitIds.has(42), "pierce hits all 3")
	near(1e9 - e1.hp, 10.0, "pierce first dmg")
	near(1e9 - e2.hp, 10.0 * .9 * (1.0 + float(p.get("piercePower", 0))), "pierce second dmg decays")
	# non-pierce bullet dies on first hit in array order
	Game.bullets.clear()
	var bn = Combat.shoot(905, 900, 0.0, 10.0, {"pierce": 0, "bounces": 0, "homing": 0})
	e1.hp = 1e9; e2.hp = 1e9; e3.hp = 1e9
	Combat.updateProjectiles(1.0 / 60.0)
	ok(e1.hp < 1e9 and e2.hp == 1e9 and e3.hp == 1e9, "tie order: array-first enemy takes the hit")

	# --- grid equivalence: fast bullet crossing many cells vs brute force
	Game.enemies.clear()
	Game.bullets.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 60:
		mk(100 + i, rng.randf_range(50, 1500), rng.randf_range(50, 1500), 1e9)
	var mism: int = 0
	for trial in 40:
		Game.bullets.clear()
		for e in Game.enemies:
			e.hp = 1e9
		var ang: float = rng.randf() * TAU
		var bx = Combat.shoot(rng.randf_range(0, 1500), rng.randf_range(0, 1500), ang, 10.0, {"pierce": 3, "bounces": 0, "homing": 0, "speed": 20000.0, "r": rng.randf_range(2, 40)})
		var ox: float = bx.x; var oy: float = bx.y
		var nx: float = ox + bx.vx / 60.0
		var ny: float = oy + bx.vy / 60.0
		var hits: Array = []
		for i in Game.enemies.size():
			var e = Game.enemies[i]
			var tt: float = Enemies.segmentCircleT(ox, oy, nx, ny, e.x, e.y, bx.r + e.r)
			if tt != INF:
				hits.append([tt, i])
		hits.sort_custom(func(m, n): return m[0] < n[0] or (m[0] == n[0] and m[1] < n[1]))
		var expect: Array = []
		var pierce: int = 3
		for h in hits:
			expect.append(Game.enemies[h[1]].id)
			if pierce > 0:
				pierce -= 1
			else:
				break
		Combat.updateProjectiles(1.0 / 60.0)
		var got: Array = []
		for e in Game.enemies:
			if e.hp < 1e9:
				got.append(e.id)
		expect.sort(); got.sort()
		if expect != got and bx.life > 0 and nx > -90 and nx < World.W + 90 and ny > -90 and ny < World.H + 90:
			mism += 1
	ok(mism == 0, "grid sweep mismatches vs brute force: %d" % mism)

	print("=== combat_audit DONE fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
