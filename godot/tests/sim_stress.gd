extends Node2D
## Headless stress harness for the simulation modules.
##   godot --headless --path godot res://tests/sim_stress.tscn            (all scenarios)
##   NF_SCENARIO=enemies godot --headless --path godot --script res://tests/sim_stress.gd
## Scenarios: enemies bosses elites levelups modules cards drones actives dash death clear hardcore fracture perf
## Prints "FAIL ..." lines on invariant violations; engine SCRIPT ERRORs show on stderr.

const DT: float = 1.0 / 60.0
var fails: int = 0
var invincible: bool = true
var autopick: bool = true
var stats: Dictionary = {}

var render: bool = OS.get_environment("NF_RENDER") != ""

func _draw() -> void:
	if render and Game.state != "menu":
		Render.draw(self)

func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["sans-serif"])
	Render.font = sf
	UI.load_drone_config()
	World.generateWorld()
	var want: String = OS.get_environment("NF_SCENARIO")
	var all: Array = ["enemies", "bosses", "elites", "levelups", "modules", "cards", "drones", "actives", "dash", "death", "clear", "hardcore", "fracture", "perf"]
	var list: Array = all if want == "" else want.split(",")
	for s in list:
		print("=== scenario ", s)
		invincible = true
		autopick = true
		await call("sc_" + s)
	var ks: Array = cov.keys()
	ks.sort()
	print("=== COVERAGE: ", ", ".join(ks))
	print("=== DONE fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ helpers
func fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func start(cfg: Dictionary = {}) -> void:
	var rc: Dictionary = Meta.cleanRunConfig({"mode": "endless", "difficulty": "easy"})
	rc.merge(cfg, true)
	Meta.runConfig = rc
	Meta.developerRun = Meta.freshDeveloperRun()
	if not Game.resetGame():
		fail("resetGame refused")
	Game.state = "playing"

func set_wave(w: int) -> void:
	Game.time = float(w - 1) * float(Meta.currentWaveSeconds()) + 0.5
	Game.wave = w

func nearest_enemy():
	var best = null
	var bd: float = INF
	var p: Dictionary = Game.player
	for e in Game.enemies:
		if e.get("_dead", false) or float(e.get("spawnDelay", 0.0)) > 0.0:
			continue
		var d: float = U.dist2(e, p)
		if d < bd:
			bd = d
			best = e
	return best

var botT: float = 0.0
func bot_step() -> void:
	var p: Dictionary = Game.player
	if p.is_empty():
		return
	botT += DT
	if invincible:
		p.hp = p.maxHp
	var e = nearest_enemy()
	Inp.inputMode = "touch"
	Inp.mobileMove.active = true
	var mx: float = cos(botT * 0.7)
	var my: float = sin(botT * 0.5)
	if e != null:
		var d: float = sqrt(U.dist2(e, p))
		if d < 300:
			mx = (p.x - e.x) / maxf(d, 1.0)
			my = (p.y - e.y) / maxf(d, 1.0)
		Inp.mouse.x = e.x
		Inp.mouse.y = e.y
	Inp.mobileMove.x = mx
	Inp.mobileMove.y = my
	Inp.mouse.down = true
	if fmod(botT, 3.0) < DT:
		Game.dash()
	for i in 3:
		if Game.activeSlots[i] != null and fmod(botT + i, 2.0) < DT:
			Combat.useActive(i)

func handle_panels() -> void:
	if Game.state == "upgrade":
		if Game.currentCardChoices == null:
			Game.currentCardChoices = Cards.chooseUpgradeSet()
		var ch: Array = Game.currentCardChoices
		if ch.is_empty():
			fail("empty upgrade choices")
			Game.closeCardChoices()
		elif autopick:
			Cards.selectUpgrade(ch[randi() % ch.size()])
			if Game.state == "upgrade" and Game.pendingLevelUps <= 0:
				Game.closeCardChoices()
	elif Game.state == "ability":
		var r: Dictionary = Game.abilityRewards[0] if Game.abilityRewards.size() > 0 else {}
		if r.is_empty():
			Combat.closeAbilityRewards()
		else:
			var id: String = r.offers[randi() % r.offers.size()]
			var idx: int = randi() % 3
			if not Combat.assignAbility(id, idx):
				for j in 3:
					if Combat.assignAbility(id, j):
						break
				if Game.abilityRewards.size() > 0 and Game.abilityRewards[0] == r:
					Game.abilityRewards.pop_front()
			if Game.abilityRewards.is_empty():
				Combat.closeAbilityRewards()
	elif Game.state == "paused":
		Game.state = "playing"

func sample_coverage() -> void:
	if Game.hazards.size() > 0:
		cov["hazards"] = int(cov.get("hazards", 0)) + 1
		for h in Game.hazards:
			cov["haz_" + str(h.get("kind", "?"))] = 1
	for f in Game.friendlyEffects:
		cov["friendly_" + str(f.get("kind", "?"))] = 1
	for b in Game.bullets:
		if b.get("fromDrone", false): cov["drone_bullet"] = 1
		if b.get("enemy", false): cov["enemy_bullet_" + str(b.get("kind", "normal"))] = 1
		if b.get("homing", 0) != 0 and b.get("homing", 0) != null: cov["homing_bullet"] = 1
		if typeof(b.get("source")) == TYPE_STRING: cov["src_" + b.source] = 1
	for e in Game.enemies:
		cov["enemy_" + str(e.type)] = 1
		if e.get("elite", false): cov["elite"] = 1
		if e.get("boss", false): cov["boss_" + str(e.get("bossKind"))] = 1
	if Game.state == "ability": cov["ability_panel"] = 1
	if Game.state == "upgrade": cov["upgrade_panel"] = 1
	if Game.bossesDefeated > 0: cov["boss_defeated"] = 1
	if Game.gems.size() > 0: cov["gems"] = 1
	if Game.drones.size() > 0: cov["drones"] = 1

var cov: Dictionary = {}

func check_invariants(tag: String) -> void:
	var p: Dictionary = Game.player
	for k in ["x", "y", "hp", "maxHp", "damage", "fireRate", "speed", "vx", "vy"]:
		var v: float = float(p.get(k, 0.0))
		if is_nan(v) or is_inf(v):
			fail("%s player.%s = %s" % [tag, k, v])
	for e in Game.enemies:
		if is_nan(float(e.x)) or is_nan(float(e.y)) or is_nan(float(e.hp)):
			fail("%s enemy NaN type=%s" % [tag, e.type])
			Game.enemies.erase(e)
			break
	for b in Game.bullets:
		if is_nan(float(b.x)) or is_nan(float(b.y)):
			fail("%s bullet NaN" % tag)
			Game.bullets.erase(b)
			break
	var P: Dictionary = Game.PERF
	if Game.bullets.size() > P.maxBullets + 300: fail("%s bullets=%d" % [tag, Game.bullets.size()])
	if Game.enemies.size() > P.maxEnemies + 40: fail("%s enemies=%d" % [tag, Game.enemies.size()])
	if Game.particles.size() > P.maxParticles + 100: fail("%s particles=%d" % [tag, Game.particles.size()])
	if Game.gems.size() > P.maxGems + 100: fail("%s gems=%d" % [tag, Game.gems.size()])
	if Game.texts.size() > P.maxTexts + 50: fail("%s texts=%d" % [tag, Game.texts.size()])
	if Game.rings.size() > P.maxRings + 50: fail("%s rings=%d" % [tag, Game.rings.size()])
	if Game.hazards.size() > 300: fail("%s hazards=%d" % [tag, Game.hazards.size()])
	if Game.friendlyEffects.size() > 300: fail("%s friendly=%d" % [tag, Game.friendlyEffects.size()])

## Simulate `secs` seconds. Returns number of steps run. cb is called each step (optional).
func run(secs: float, tag: String, cb: Callable = Callable()) -> int:
	var n: int = int(secs / DT)
	var done: int = 0
	for i in n:
		if Game.state == "playing":
			bot_step()
			if cb.is_valid():
				cb.call(i)
			Game.update(DT)
			sample_coverage()
			done += 1
		elif Game.state == "gameover" or Game.state == "menu" or Game.state == "cleared":
			break
		else:
			handle_panels()
		if i % 30 == 0:
			check_invariants(tag)
		if render and i % 6 == 0:
			queue_redraw()
			await get_tree().process_frame
	print("  [%s] steps=%d state=%s t=%.1f wave=%d kills=%d en=%d bul=%d gems=%d part=%d hp=%.0f/%.0f lvl=%d" % [tag, done, Game.state, Game.time, Game.wave, Game.kills, Game.enemies.size(), Game.bullets.size(), Game.gems.size(), Game.particles.size(), Game.player.hp, Game.player.maxHp, Game.player.level])
	return done

# ------------------------------------------------------------------ scenarios
func sc_enemies() -> void:
	start()
	for t in Enemies.ENEMY_TYPES.keys():
		set_wave(8)
		var e = Enemies.spawnEnemy(t)
		if e == null:
			print("  spawnEnemy(%s) -> null (restricted?)" % t)
			continue
		var e2 = Enemies.spawnEnemy(t)
		print("  spawned ", t)
		await run(10.0, "enemy_" + t)
		Game.enemies = []
		Game.bullets = []
	start()
	set_wave(6)
	await run(40.0, "waves")

func sc_bosses() -> void:
	for kind in Enemies.CUSTOM_BOSS_IDS:
		start()
		Meta.developerRun.active = true
		set_wave(10)
		var e = Enemies.spawnEnemy("boss", true, kind)
		if e == null:
			fail("boss spawn null " + kind)
			continue
		print("  boss ", kind, " ", e.bossKind)
		await run(40.0, "boss_" + kind, func(i):
			for en in Game.enemies:
				if en.boss and i % 600 == 599:
					en.hp = en.maxHp * 0.3
		)
		# kill boss
		for en in Game.enemies.duplicate():
			if en.boss:
				Enemies.dealEnemyDamage(en, 1e9, "player")
		await run(5.0, "boss_dead_" + kind)
	start()
	set_wave(5)
	print("  spawnBoss ", Enemies.spawnBoss())
	await run(20.0, "spawnBoss")

func sc_elites() -> void:
	start({"difficulty": "hard"})
	set_wave(15)
	for i in 30:
		Enemies.spawnEnemy()
	var el: int = 0
	for e in Game.enemies:
		if e.elite: el += 1
	print("  elites=", el)
	await run(25.0, "elites")

func sc_levelups() -> void:
	start()
	var p: Dictionary = Game.player
	for k in 60:
		p.xp = p.nextXp
		Game.drainRunXp()
		Cards.showUpgrade()
		handle_panels()
		while Game.state == "upgrade":
			handle_panels()
	print("  level=", p.level, " ranks=", p.skillRanks.size())
	Game.state = "playing"
	for i in 6:
		Enemies.spawnEnemy()
	await run(20.0, "post_levelups")
	# legendary: force
	for l in Cards.legendarySkills:
		start()
		Game.pendingLevelUps = 1
		Game.state = "playing"
		var ch := {"id": l.id, "icon": l.icon, "name": l.name, "rarity": "LEGENDARY", "desc": l.desc, "apply": Cards._apply_legend.bind(l.id)}
		if not Game.applyRunChoice(ch):
			fail("legend apply " + l.id)
		for i in 6:
			Enemies.spawnEnemy()
		await run(6.0, "legend_" + l.id)
	for u in Cards.uniqueEpics:
		start()
		Game.pendingLevelUps = 1
		Game.applyRunChoice(Cards._unique_choice(u))
		for i in 6:
			Enemies.spawnEnemy()
		await run(6.0, "unique_" + u.id)
	# every skill at every rank
	for s in Cards.skills:
		start()
		Game.pendingLevelUps = 3
		for r in 3:
			Game.applyRunChoice(Cards.buildSkillChoice(s))
		for i in 6:
			Enemies.spawnEnemy()
		await run(6.0, "skill_" + s.id)
	# endless choices
	start()
	for c in Cards.endlessChoices():
		Game.pendingLevelUps = 1
		Game.applyRunChoice(c)
	await run(10.0, "endless")

func sc_modules() -> void:
	start()
	var lv: int = 10
	for m in Cards.MODULES:
		start()
		Cards.module_apply(m.id, Game.player, lv)
		Game.player.hp = Game.player.maxHp
		Enemies.syncDrones()
		set_wave(5)
		for i in 8:
			Enemies.spawnEnemy()
		await run(6.0, "module_" + m.id)
	start()
	for m in Cards.MODULES:
		Cards.module_apply(m.id, Game.player, 10)
	Game.player.hp = Game.player.maxHp
	Enemies.syncDrones()
	set_wave(12)
	await run(40.0, "all_modules")
	# via Meta equip
	for slot in ["core", "armor", "drive"]:
		pass

func sc_cards() -> void:
	start()
	var base: Dictionary = {"trigger": "on_kill", "condition": "always", "chance": "c100", "effect": "heal", "power": "p360"}
	var effects: Array = Cards.CARD_PARTS.effect.map(func(x): return x.id)
	var triggers: Array = Cards.CARD_PARTS.trigger.map(func(x): return x.id)
	var loadout: Array = []
	for i in effects.size():
		var c: Dictionary = base.duplicate()
		c.effect = effects[i]
		c.trigger = triggers[i % triggers.size()]
		c.id = "t_%d" % i
		loadout.append(Cards.normalizeCard(c))
	# Also every effect on on_kill/on_hit
	for ef in effects:
		for tg in ["on_kill", "on_hit", "on_crit", "on_dash"]:
			var c2: Dictionary = base.duplicate()
			c2.effect = ef
			c2.trigger = tg
			c2.id = "u_%s_%s" % [ef, tg]
			loadout.append(Cards.normalizeCard(c2))
	Cards.runLoadoutCards = loadout
	set_wave(8)
	for i in 15:
		Enemies.spawnEnemy()
	await run(30.0, "cards")
	for t in triggers:
		Cards.emitCardTrigger(t, {"enemy": nearest_enemy(), "level": 3, "wave": 2, "skill": "nova"})
	await run(5.0, "cards2")
	Cards.runLoadoutCards = []

func sc_drones() -> void:
	start()
	Game.player.droneCount = 8
	Game.player.dronePierce = 2
	Game.player.droneTracking = true
	Game.player.droneRange = 1600
	Enemies.syncDrones()
	print("  drones=", Game.drones.size())
	set_wave(8)
	await run(30.0, "drones")
	for pr in ["nearest", "boss", "elite", "weakest", "strongest", "aim"]:
		UI.setDroneConfig({"priority": pr})
		await run(5.0, "drone_" + pr)
	UI.setDroneConfig({"enabled": false})
	await run(3.0, "drone_off")
	UI.setDroneConfig({"enabled": true, "priority": "nearest"})
	Game.player.droneCount = 0
	Enemies.syncDrones()
	await run(2.0, "drone_zero")

func sc_actives() -> void:
	for id in Combat.ACTIVE_DEFS.keys():
		start()
		Game.activeSlots[0] = {"id": id, "level": 5, "remaining": 0.0, "charging": null}
		set_wave(8)
		for i in 12:
			Enemies.spawnEnemy()
		await run(3.0, "pre_" + id)
		for k in 6:
			Game.activeSlots[0].remaining = 0.0
			if not Combat.useActive(0) and Game.activeSlots[0].get("charging") == null:
				print("  useActive false for ", id)
			await run(3.0, "active_" + id)
	start()
	for i in 3:
		Combat.queueAbilityReward()
	Combat.openAbilityRewards()
	await run(10.0, "ability_panel")

func sc_dash() -> void:
	start()
	set_wave(6)
	for i in 10:
		Enemies.spawnEnemy()
	Game.player.dashNova = 1.0
	Game.player.dashInvuln = 0.5
	await run(20.0, "dash", func(i):
		if i % 20 == 0:
			Game.player.dashReady = 1.0
			Game.dash()
		if i % 100 == 0:
			Game.gainShield(2)
			Game.gainBarrier(1.5)
	)

func sc_death() -> void:
	invincible = false
	for round in 3:
		start({"difficulty": "hard"})
		set_wave(12)
		Game.player.hp = 30
		Game.player.maxHp = 30
		for i in 40:
			Enemies.spawnEnemy()
		var n: int = await run(60.0, "death%d" % round)
		print("  state after: ", Game.state, " reason=", Game.runEndReason)
		if Game.state != "gameover":
			fail("expected gameover, got " + Game.state)
		Game.gameOver("death")
		Game.returnHome()
	start()
	await run(10.0, "after_reset")

func sc_clear() -> void:
	start({"mode": "clear", "clearWave": 5})
	set_wave(1)
	var steps: int = 0
	for i in 12000:
		if Game.state == "playing":
			bot_step()
			Game.update(DT)
			steps += 1
			if Game.wave < 5 and steps % 300 == 0:
				Game.wave += 1
			for e in Game.enemies:
				if e.boss and Meta.isFinalClearWave():
					e.hp = minf(e.hp, 50)
		elif Game.state in ["upgrade", "ability", "paused"]:
			handle_panels()
		else:
			break
		if i % 60 == 0:
			check_invariants("clear")
	print("  clear end state=", Game.state, " wave=", Game.wave, " reason=", Game.runEndReason, " bossesDefeated=", Game.bossesDefeated)

func sc_hardcore() -> void:
	start({"difficulty": "hardcore"})
	set_wave(6)
	await run(40.0, "hardcore")
	start({"difficulty": "hard"})
	set_wave(6)
	await run(30.0, "hard")
	start({"difficulty": "normal"})
	await run(20.0, "normal")

func sc_fracture() -> void:
	start({"difficulty": "fracture"})
	set_wave(10)
	await run(40.0, "fracture")
	start({"difficulty": "custom", "mode": "endless"})
	await run(10.0, "custom")

func sc_perf() -> void:
	start()
	invincible = true
	set_wave(20)
	Game.player.damage = 1.0
	Game.player.maxHp = 1e9
	for i in 190:
		Enemies.spawnEnemy("chaser")
	for e in Game.enemies:
		e.spawnDelay = 0.0
		e.hp = 1e12
		e.maxHp = 1e12
	var t0 := Time.get_ticks_usec()
	var n: int = 0
	for i in 300:
		if Game.state != "playing":
			break
		bot_step()
		Game.update(DT)
		n += 1
		for e in Game.enemies:
			e.hp = 1e12
	var dtms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, n)
	print("  PERF Game.update ms/step with %d enemies, %d bullets: %.2f" % [Game.enemies.size(), Game.bullets.size(), dtms])
