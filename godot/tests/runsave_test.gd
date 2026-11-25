extends SceneTree
## Headless test for suspend/resume run save (Game.suspendRunToHome / restoreSuspended / export / import).
##   godot --headless --path godot --script res://tests/runsave_test.gd
var fails := 0
const DT := 1.0 / 60.0

func ok(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)
	else:
		print("ok: ", m)

func run(sec: float) -> void:
	var G = root.get_node("Game")
	for i in int(sec * 60.0):
		G.player.hp = G.player.maxHp
		G.update(DT)
		if G.state != "playing":
			break

func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	var M = root.get_node("Meta")
	var C = root.get_node("Cards")
	var E = root.get_node("Enemies")
	var UIn = root.get_node("UI")
	var W = root.get_node("World")
	UIn.load_drone_config()
	W.generateWorld()
	M.storage_remove("nf_suspended_run_v1")
	M.storage_remove("nf_settled_run_ids_v1")
	var rc: Dictionary = M.cleanRunConfig({"mode": "endless", "difficulty": "easy"})
	M.runConfig = rc
	M.developerRun = M.freshDeveloperRun()
	ok(G.resetGame(), "resetGame")
	G.state = "playing"
	G.startRunSession()
	# active features: drones, cards, homing, actives, orbit blades
	G.player.droneCount = 4
	G.player.droneTracking = true
	G.player.dronePierce = 2
	E.syncDrones()
	var base := {"trigger": "on_kill", "condition": "always", "chance": "c100", "effect": "heal", "power": "p360"}
	var loadout: Array = []
	var effects: Array = C.CARD_PARTS.effect.map(func(x): return x.id)
	for i in mini(6, effects.size()):
		var c: Dictionary = base.duplicate()
		c.effect = effects[i]
		c.id = "t_%d" % i
		loadout.append(C.normalizeCard(c))
	C.runLoadoutCards = loadout
	G.activeSlots[0] = {"id": "lance", "level": 3, "remaining": 0.0, "charging": null}
	G.activeSlots[1] = {"id": "blades", "level": 2, "remaining": 0.0, "charging": null}
	G.time = 3.0 * float(M.currentWaveSeconds()) + 0.5
	G.wave = 4
	for i in 14:
		E.spawnEnemy()
	run(4.0)
	root.get_node("Combat").useActive(1)
	run(0.5)
	root.get_node("Combat").useActive(0)
	run(3.0)
	ok(G.state == "playing", "still playing")
	ok(G.enemies.size() > 0 and G.bullets.size() > 0, "enemies=%d bullets=%d drones=%d" % [G.enemies.size(), G.bullets.size(), G.drones.size()])
	# link some refs: a bullet homing onto an enemy, friendly effect hitTimes
	var homing := 0
	for b in G.bullets:
		if b.get("homingTarget") != null: homing += 1
	print("  homing refs=", homing, " friendly=", G.friendlyEffects.size(), " charging=", G.activeSlots[0].get("charging") != null)
	if G.enemies.size() > 1 and G.bullets.size() > 0:
		G.bullets[0].homingTarget = G.enemies[0]
	G.setPause(true)
	ok(G.state == "paused", "paused")
	var snap := {
		"score": G.score, "wave": G.wave, "time": G.time, "hp": G.player.hp, "kills": G.kills,
		"enemies": G.enemies.size(), "bullets": G.bullets.size(), "drones": G.drones.size(), "gems": G.gems.size(),
		"fx": G.friendlyEffects.size(), "level": G.player.level, "cards": C.runLoadoutCards.size(),
		"serial": G.enemySerial, "px": G.player.x, "py": G.player.y,
	}
	var first_enemy_id = G.enemies[0].id if G.enemies.size() > 0 else -1
	# --- make / validate
	var data: Dictionary = G.makeRunSave()
	ok(not data.has("error"), "makeRunSave " + str(data.get("error", "")))
	ok(data.app == "NEON_FRACTURE_RUN" and data.formatVersion == 1 and data.graph.has("nodes") and data.graph.has("root"), "format keys")
	var types := {}
	for n in data.graph.nodes: types[n.type] = int(types.get(n.type, 0)) + 1
	print("  nodes=", data.graph.nodes.size(), " types=", types)
	ok(types.has("set") and types.has("map"), "set/map nodes emitted")
	# live state not polluted by tagging
	ok(not G.enemies[0].has("__sid") and not G.player.has("__sid"), "no tag residue")
	var v: Dictionary = G.validateRunSave(JSON.parse_string(JSON.stringify(data)))
	ok(v.has("state"), "validate " + str(v.get("error", "")))
	var bad: Dictionary = G.validateRunSave({"app": "x"})
	ok(bad.has("error"), "reject foreign")
	# shared refs preserved
	if v.has("state") and homing + 1 > 0:
		var s: Dictionary = v.state
		var found := false
		for b in s.bullets:
			var ht = b.get("homingTarget")
			if ht != null:
				for e in s.enemies:
					if is_same(e, ht):
						found = true
		print("  homing ref -> enemy list identity preserved: ", found)
		ok(found or s.bullets.size() == 0, "homingTarget identity")
		if s.activeSlots[0] != null and s.activeSlots[0].get("charging") != null:
			var ch = s.activeSlots[0].charging
			var inlist := false
			for fx in s.friendlyEffects:
				if is_same(fx, ch): inlist = true
			ok(inlist, "charging shared with friendlyEffects")
	# --- suspend to home
	ok(G.suspendRunToHome(false), "suspendRunToHome")
	ok(G.state == "menu", "home state " + G.state)
	ok(not G.readSuspended().is_empty(), "readSuspended")
	print("  info: ", G.resumeInfoText())
	# fresh process emulation: drop memory cache, re-read from storage
	G._RS.suspendedMemory = null
	ok(not G.readSuspended().is_empty(), "readSuspended from storage")
	ok(G.restoreSuspended(), "restoreSuspended")
	ok(G.state == "paused", "restored paused: " + G.state)
	var after := {
		"score": G.score, "wave": G.wave, "time": G.time, "hp": G.player.hp, "kills": G.kills,
		"enemies": G.enemies.size(), "bullets": G.bullets.size(), "drones": G.drones.size(), "gems": G.gems.size(),
		"fx": G.friendlyEffects.size(), "level": G.player.level, "cards": C.runLoadoutCards.size(),
		"serial": G.enemySerial, "px": G.player.x, "py": G.player.y,
	}
	for k in snap:
		ok(absf(float(snap[k]) - float(after[k])) < 1e-6, "equal %s %s" % [k, str(snap[k])])
	ok(G.enemies.size() == 0 or G.enemies[0].id == first_enemy_id, "enemy id kept (int)")
	ok(typeof(G.enemies[0].id) == TYPE_INT if G.enemies.size() > 0 else true, "enemy id int type")
	# continue running
	G.setPause(false)
	ok(G.state == "playing", "resumed")
	run(6.0)
	ok(G.state == "playing", "keeps running 6s")
	G.setPause(true)
	# --- file export / import round trip
	var path := "user://runsave_test_export.json"
	ok(G.exportRunSave(path) == "", "exportRunSave")
	M.storage_remove("nf_suspended_run_v1")
	G._RS.suspendedMemory = null
	ok(G.readSuspended().is_empty(), "slot cleared")
	var snap2: Array = [G.score, G.wave, G.enemies.size(), G.bullets.size()]
	G.returnHome()
	ok(G.importRunSave(path) == "", "importRunSave")
	ok(G.pendingRunImport is Dictionary, "pendingRunImport set")
	ok(G.applyRunImport() == "", "applyRunImport")
	ok(not G.readSuspended().is_empty(), "slot refilled by import")
	ok(G.restoreSuspended(), "restore from import")
	ok(G.score == snap2[0] and G.wave == snap2[1] and G.enemies.size() == snap2[2] and G.bullets.size() == snap2[3], "state equal after import")
	G.setPause(false)
	run(4.0)
	ok(G.state == "playing", "runs after import")
	# --- settled ledger blocks re-import
	G.setPause(true)
	var rid: String = str(G.makeRunSave().runId)
	G.markSessionSettled()
	ok(G.settledRunIds().has(rid), "ledger has run id")
	ok(G.validateRunSave(JSON.parse_string(FileAccess.get_file_as_string(path))).has("error"), "settled run rejected")
	print("=== DONE fails=", fails)
	quit(1 if fails > 0 else 0)
