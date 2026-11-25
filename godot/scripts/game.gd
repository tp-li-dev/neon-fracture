extends Node
## Game — run state, player, run systems, update() sim loop and fixed-step driver.
## Port of index.html (6080-6111, 6174-6195, 7251-7403, 7807-7861, 8112-8330, 8641, 8873-8944, 9067-9155, 9495-9530).
## DOM/HUD work is delegated to UI.hook(name, args). See report for the hook names used.

# ---------- World / run state ----------
var state: String = "menu"
var last: float = 0.0
var time: float = 0.0
var screenShake: float = 0.0
var flash: float = 0.0
var score: float = 0.0
var kills: int = 0
var wave: int = 1
var spawnTimer: float = 0.0
var waveTimer: float = 0.0
var bossAlive: bool = false
var bossWarningTimer: float = 0.0
var pendingLevelUps: int = 0
var combo: float = 1.0
var comboKills: int = 0
var comboTimer: float = 0.0
var bossesDefeated: int = 0
var stars: Array = []
var bullets: Array = []
var enemies: Array = []
var particles: Array = []
var gems: Array = []
var texts: Array = []
var drones: Array = []
var rings: Array = []
var fieldZones: Array = []
var uiTimer: float = 0.0
var maxComboRun: float = 1.0
var maxHitDamageRun: float = 0.0
var runStartedAt: float = 0.0
var runEndReason: String = "death"

# 視界外の敵を永遠に保持しない。
const ACTIVE_DESPAWN_DISTANCE: float = 1850.0

var PERF: Dictionary = {
	"maxBullets": 1280,
	"maxPlayerBullets": 980,
	"maxEnemyBullets": 230,
	"maxParticles": 260,
	"maxGems": 150,
	"maxTexts": 46,
	"maxRings": 48,
	"hudFps": 12,
	"maxEnemies": 190,
}

var save: Dictionary = {"high": 0, "wave": 0}

# ---------- Run-scoped systems ----------
var player: Dictionary = {}
var sceneDirty: bool = true
var lastRenderedState: String = ""
var runSettled: bool = false
var clearPending: bool = false
var enemySerial: int = 0
var bossSpawnSerial: int = 0
var bossPopulationTimer: float = 0.0
var finalBossEncounterStarted: bool = false
var hazards: Array = []
var abilityRewards: Array = []
var activeSlots: Array = [null, null, null]
var friendlyEffects: Array = []
var selectedAbilityId = null
var panelReturnState: String = "playing"
var currentCardChoices = null
var cardPanelOrigin: String = "playing"
var autoCardClock: float = 0.0
var statsClock: float = 0.0
var autoHistory: Array = []
var cardCooldowns: Dictionary = {}
var runDamageTotals: Dictionary = {"player": 0.0, "drone": 0.0, "active": 0.0, "gear": 0.0, "other": 0.0}
var xpProcessing: bool = false
var projectileUpdating: bool = false
var playPreferences: Dictionary = {"autoCards": false, "holdSkills": true}
var pausePendingAction = null

# Fixed-step loop
const FIXED_STEP: float = 1.0 / 60.0
const MAX_FRAME_DT: float = 0.20
const MAX_SIM_STEPS: int = 8
var simAccumulator: float = 0.0


func _ready() -> void:
	last = U.now_ms()
	if Inp.touchCapable:
		PERF.maxBullets = 760
		PERF.maxPlayerBullets = 540
		PERF.maxEnemyBullets = 150
		PERF.maxParticles = 190
		PERF.maxEnemies = 135
	var h = Meta.storage_get("nf_high")
	var w = Meta.storage_get("nf_wave")
	save.high = int(str(h)) if h != null and str(h) != "" else 0
	save.wave = int(str(w)) if w != null and str(w) != "" else 0
	var pp = Meta.storage_get("nf_play_preferences")
	if pp != null and str(pp) != "":
		var parsed = JSON.parse_string(str(pp))
		if parsed is Dictionary:
			for k in parsed:
				playPreferences[k] = parsed[k]
	player = playerBase()


# ---------- helpers ----------
func _snd(n: String) -> void:
	Audio.Sound.play(n)


func _hook(n: String, args: Array = []):
	return UI.hook(n, args)


func _getb(d: Dictionary, k: String, def = 0.0):
	var v = d.get(k, def)
	return def if v == null else v


func runXpNeeded(level) -> int:
	return maxi(12, roundi(8.0 + 5.0 * level + 2.0 * pow(float(level), 1.25)))


func playerBase() -> Dictionary:
	return {
		"x": World.W / 2.0, "y": World.H / 2.0,
		"vx": 0.0, "vy": 0.0,
		"r": 13,
		"speed": 275.0,
		"phaseSpeedTimer": 0.0,
		"beamPower": 1.0, "chargeEfficiency": 0.0, "gearEffects": {}, "gearTimers": {}, "gearKills": 0,
		"prismPower": 0.0, "prismTimer": 1.0, "cometPower": 0.0, "cometEvery": 9, "cometKills": 0,
		"haloPower": 0.0, "haloTimer": 1.0, "bladePower": 0.0, "bladeCount": 0, "beamBranches": 0,
		"fallingSky": false, "friendlyBladeClock": 0.0, "orbitHitTimes": {}, "gearOrbitHits": {},
		"hp": 100.0, "maxHp": 100.0,
		"level": 1, "xp": 0.0, "nextXp": runXpNeeded(1),
		"damage": 18.0,
		"fireRate": 6.5,
		"bulletSpeed": 760.0,
		"bulletSize": 4.0,
		"spread": 0.0,
		"multishot": 1,
		"pierce": 0,
		"crit": 0.08,
		"critMult": 2.0,
		"lifesteal": 0.0,
		"killHeal": 0.0,
		"armor": 0.0,
		"shieldHits": 0,
		"guardTimer": 0.0,
		"guardReduction": 0.0,
		"magnet": 115.0,
		"dashCooldown": 2.1,
		"dashReady": 1.0,
		"dashTime": 0.0,
		"invuln": 0.0,
		"shootTimer": 0.0,
		"regen": 0.0,
		"knockback": 1.0,
		"droneCount": 0,
		"droneDamage": 10.0,
		"droneRate": 1.25,
		"droneRange": 520.0,
		"dronePierce": 0,
		"droneTracking": false,
		"droneOverdrive": 0.0,
		"bulletBounces": 0,
		"bounceDamage": 1.0,
		"homing": 0.0,
		"homingActivationDist": 115.0,
		"homingRange": 720.0,
		"homingLead": 0.72,
		"homingTurnBoost": 1.0,
		"mapEsp": false,
		"mapEspAdvanced": false,
		"healEfficiency": 0.70,
		"barrierTime": 0.0, "barrierLock": 0.0, "dashInvuln": 0.0, "wounded": 0.0,
		"debuffResistance": 0.0, "activePower": 1.0, "activeHaste": 0.0,
		"playerOverdrive": 0.0, "overdrivePower": 1.0, "stasisTime": 0.0, "stasisPower": 1.0,
		"burnPower": 0.0, "fracturePower": 0.0, "bossDamage": 0.0, "piercePower": 0.0,
		"droneDamageTransfer": 0.18, "upgradeCounts": {},
		"globalPickup": false,
		"xpMultiplier": 1.0,
		"explosiveChance": 0.0,
		"explosiveDamage": 0.7,
		"explosiveRadius": 72.0,
		"chainChance": 0.0,
		"chainTargets": 1,
		"chainDamage": 0.4,
		"frostChance": 0.0,
		"frostStrength": 0.45,
		"frostDuration": 0.55,
		"echoChance": 0.0,
		"echoDamage": 0.5,
		"executeThreshold": 0.0,
		"executeBonus": 0.0,
		"executeInstant": false,
		"dashNova": 0.0,
		"dashNovaRadius": 90.0,
		"lowHpPower": 0.0,
		"singularityEvery": 0,
		"phoenix": 0,
		"skillRanks": {},
		"rarityCharge": 0,
		"epicGuarantee": false,
	}


func escapeText(v) -> String:
	return str(v).xml_escape(true)


func resetRunSystems() -> void:
	Meta.developerRun = Meta.freshDeveloperRun()
	runSettled = false
	clearPending = false
	enemySerial = 0
	hazards = []
	abilityRewards = []
	bossSpawnSerial = 0
	bossPopulationTimer = 0.6
	finalBossEncounterStarted = false
	activeSlots = [null, null, null]
	friendlyEffects = []
	selectedAbilityId = null
	currentCardChoices = null
	autoCardClock = 0.0
	statsClock = 0.0
	autoHistory = []
	cardCooldowns = {}
	xpProcessing = false
	projectileUpdating = false
	runDamageTotals = {"player": 0.0, "drone": 0.0, "active": 0.0, "gear": 0.0, "other": 0.0}
	_hook("hideActiveRewardScreen")
	sceneDirty = true
	lastRenderedState = ""


func cancelCombatInput() -> void:
	Inp.clearKeyboardMovement()
	Inp.cancelPointerInput()
	Inp.stopPlayerMotion()
	Inp.setMobileControls(false)


func finishPresentation() -> void:
	friendlyEffects = []
	for slot in activeSlots:
		if slot != null:
			slot.charging = null
	screenShake = 0.0
	flash = 0.0
	cancelCombatInput()
	_hook("finishPresentation")  # hides boss warning / upgrade / active reward / combat dock
	sceneDirty = true


func resumeAfterPanel(origin) -> void:
	state = "paused" if origin == "paused" else "playing"
	if state == "playing":
		_hook("focusCombat")
	else:
		renderRunStatus()
		_hook("showPause", [pause_info()])
		_hook("focusPanel", ["pauseScreen", "pauseResumeBtn"])
	last = U.now_ms()
	sceneDirty = true
	syncCombatHud()


func savePlayPreferences() -> void:
	Meta.storage_set("nf_play_preferences", JSON.stringify(playPreferences))


func toggleAutoCards() -> void:
	playPreferences.autoCards = not playPreferences.autoCards
	savePlayPreferences()
	syncCombatHud()


func gainShield(hits) -> bool:
	var c: Dictionary = Meta.challenge()
	if c.get("oneHit", false) or not c.get("shield", false) or player.barrierLock > 0 or hits <= 0:
		return false
	player.shieldHits += floori(hits)
	return true


func gainBarrier(seconds) -> bool:
	var c: Dictionary = Meta.challenge()
	if c.get("oneHit", false) or not c.get("barrier", false) or player.barrierLock > 0 or seconds <= 0:
		return false
	player.barrierTime = maxf(player.barrierTime, seconds)
	return true


# ---------- Run systems ----------
func updateRunSystems(dt: float) -> void:
	for s in activeSlots:
		if s != null:
			s.remaining = maxf(0.0, s.remaining - dt)
	_hook("updateSkillHolds")
	for k in ["barrierLock", "barrierTime", "dashInvuln", "wounded", "playerOverdrive", "stasisTime"]:
		player[k] = maxf(0.0, float(_getb(player, k, 0.0)) - dt)
	if player.stasisTime > 0:
		for e in enemies:
			if e.get("_dead", false) or U.dist2(e, player) > 340.0 * 340.0:
				continue
			e.slow = maxf(e.slow, 0.12)
			e.slowPower = maxf(e.slowPower, 0.7)
			Enemies.dealEnemyDamage(e, player.damage * 2.5 * player.stasisPower * dt, "active")
	drainRunXp()
	autoCardClock -= dt
	if playPreferences.autoCards and pendingLevelUps > 0 and autoCardClock <= 0:
		# One decision per 0.25 s; no synchronous popup or unbounded trigger recursion.
		var choices = currentCardChoices if currentCardChoices != null else Cards.chooseUpgradeSet()
		currentCardChoices = null
		var best = choices[0]
		for c in choices:
			if autoCardPriority(c) > autoCardPriority(best):
				best = c
		applyRunChoice(best, true)
		autoCardClock = 0.25


func autoCardPriority(c) -> float:
	var useful: int = 0 if (str(c.id).contains("drone") and player.droneCount <= 0) else 1
	var rr: int = int(Cards.rarityRank.get(c.rarity, 1))
	var bonus: int = 35 if (player.hp / player.maxHp < 0.4 and ["vitality", "armor", "regen"].has(c.id)) else 0
	return rr * 100 + bonus + useful


func applyRunChoice(u, automatic: bool = false) -> bool:
	if u == null or pendingLevelUps <= 0:
		return false
	u.apply.call()
	Meta.applyModeRestrictions()
	pendingLevelUps -= 1
	Enemies.syncDrones()
	_snd("card")
	var uid: String = str(u.id)
	var id: String = uid
	if uid.begins_with("end_"):
		var parts: PackedStringArray = uid.split("_")
		id = "_".join(parts.slice(0, 2))
	player.upgradeCounts[id] = int(player.upgradeCounts.get(id, 0)) + 1
	autoHistory.push_front({"name": u.name, "rarity": u.rarity, "level": player.level})
	if autoHistory.size() > 8:
		autoHistory.resize(8)
	if automatic and texts.size() < PERF.maxTexts:
		texts.push_back({"x": player.x, "y": player.y - 38, "text": "自動取得：%s" % str(u.name), "life": 0.9, "max": 0.9, "hue": 42 if u.rarity == "LEGENDARY" else 185, "size": 12})
	updateUI()
	return true


func drainRunXp() -> void:
	if xpProcessing:
		return
	xpProcessing = true
	var beforeLevel: int = player.level
	var work: int = 0
	while player.xp >= player.nextXp and work < 256:
		work += 1
		player.xp -= player.nextXp
		player.level += 1
		player.nextXp = runXpNeeded(player.level)
		pendingLevelUps += 1
		Cards.emitCardTrigger("on_level", {"level": player.level})
	xpProcessing = false
	if player.level > beforeLevel:
		_snd("level")


func closeCardChoices() -> void:
	if state != "upgrade":
		return
	_hook("hideUpgrade")
	resumeAfterPanel(cardPanelOrigin)


func renderCardChoices() -> void:
	if pendingLevelUps > 0 and currentCardChoices == null:
		currentCardChoices = Cards.chooseUpgradeSet()
	_hook("renderCardChoices", [{
		"pending": pendingLevelUps,
		"auto": playPreferences.autoCards,
		"choices": currentCardChoices if pendingLevelUps > 0 else [],
	}])


func syncCombatHud() -> void:
	_hook("syncCombatHud")


# ---------- Heal / run lifecycle ----------
func healPlayer(amount: float, source: String = "generic") -> float:
	var cfg: Dictionary = Meta.challenge()
	if player.is_empty() or runSettled or amount <= 0 or cfg.heal <= 0:
		return 0.0
	var he: float = float(player.get("healEfficiency", 0.70))
	var efficiency: float = maxf(0.0, minf(1.0, he * cfg.heal * (0.5 if player.wounded > 0 else 1.0)))
	var actual: float = minf(player.maxHp - player.hp, amount * efficiency)
	if actual <= 0:
		return 0.0
	player.hp += actual
	return actual


func resetGame() -> bool:
	Meta.runConfig = Meta.cleanRunConfig(Meta.runConfig)
	var setupError = Enemies.validateRunSetup()
	if setupError:
		Inp.showInputNotice(setupError, 3000)
		return false
	Inp.clearPhysicalMovement()
	cancelCombatInput()
	resetRunSystems()
	_hook("tryLandscapeLock")
	state = "playing"
	time = 0.0
	screenShake = 0.0
	flash = 0.0
	score = 0.0
	kills = 0
	wave = 1
	spawnTimer = 0.5
	waveTimer = 0.0
	bossAlive = false
	bossWarningTimer = 0.0
	pendingLevelUps = 0
	combo = 1.0
	comboKills = 0
	comboTimer = 0.0
	uiTimer = 0.0
	bossesDefeated = 0
	maxComboRun = 1.0
	maxHitDamageRun = 0.0
	runStartedAt = U.now_ms()
	runEndReason = "death"
	bullets = []
	enemies = []
	particles = []
	gems = []
	texts = []
	drones = []
	rings = []
	player = playerBase()
	Meta.runGrowth = Meta.captureRunGrowth()
	Meta.applyMetaBonuses(player, Meta.runGrowth)
	Meta.applyModeRestrictions()
	World.generateWorld()
	World.updateCamera(0.0, true)
	Enemies.syncDrones()
	_hook("resetGameUI", [Inp.touchCapable])  # hide start/gameover/upgrade/pause/bossWarning/runConfig, show HUD
	_hook("focusCombat")
	_hook("startRunSession")
	_hook("syncDroneControls")
	updateUI()
	_snd("start")
	return true


func gameOver(reason: String = "death") -> void:
	if runSettled or not ["playing", "paused", "upgrade", "ability"].has(state):
		return
	if _hook("sessionAlreadySettled"):
		Inp.showInputNotice("集計済みのランです")
		returnHome()
		return
	runSettled = true
	state = "gameover"
	Inp.clearPhysicalMovement()
	finishPresentation()

	var m: Dictionary = Meta.meta
	var eligible: bool = not Meta.developerRun.active
	var wasHigh: bool = eligible and score > save.high
	if wasHigh:
		save.high = floori(score)
		Meta.storage_set("nf_high", str(save.high))
	if eligible and wave > save.wave:
		save.wave = wave
		Meta.storage_set("nf_wave", str(save.wave))

	runEndReason = reason
	var earnedCredits = Meta.earnedCreditAmount()
	var earnedData = Meta.earnedDataAmount()
	var playerXpGain: int = floori(Meta.scoreToPlayerXp(score) * (1.0 + (Meta.challengeReward() - 1.0) * 0.55)) if eligible else 0
	var levelBefore = m.get("playerLevel", 1)
	var levelsGained: int = 0
	var newAchievements: Array = []
	var prof: Dictionary = Meta.scoreRewardProfile().duplicate()
	prof["rank"] = "DEV"
	var runLoot: Dictionary = {"count": 0, "newSyntax": 0, "cards": 0, "gear": 0, "profile": prof}
	if eligible:
		m.credits += earnedCredits
		m.data = int(m.get("data", 0) if m.get("data", 0) != null else 0) + earnedData
		m.totalRuns = int(m.get("totalRuns", 0) if m.get("totalRuns", 0) != null else 0) + 1
		levelsGained = Meta.awardPlayerXp(playerXpGain)
		Meta.updateRunRecords(reason)
		if Meta.runConfig.difficulty == "custom":
			m.records.lastCustomSetup = {"version": "v28.5", "config": Meta.runConfig.duplicate(true), "score": floori(score), "wave": wave, "enemyLevel": Enemies.enemyLevelForWave()}
		runLoot = Meta.grantRunLoot()
		newAchievements = Meta.checkAchievements()
		Meta.storage_set("nf_meta_v1", JSON.stringify(Meta.meta))

	var cfg: Dictionary = Meta.challenge()
	_hook("showGameOver", [{
		"reason": reason,
		"eligible": eligible,
		"wasHigh": wasHigh,
		"score": floori(score),
		"wave": wave,
		"kills": kills,
		"earnedCredits": earnedCredits,
		"earnedData": earnedData,
		"playerXpGain": playerXpGain,
		"levelBefore": levelBefore,
		"levelsGained": levelsGained,
		"playerLevel": Meta.meta.get("playerLevel", 1),
		"newAchievements": newAchievements,
		"runLoot": runLoot,
		"cp": cfg.cp,
		"cpLabel": cfg.label,
		"rewardMultiplier": Meta.challengeReward(),
		"mode": Meta.runConfig.mode,
		"finalWaveTarget": Meta.finalWaveTarget(),
		"growthSummary": Meta.growthSummary(Meta.runGrowth) if Meta.runGrowth != null else "",
		"devActions": Meta.developerRun.actions,
		"highScore": save.high,
		"bestWave": save.wave,
	}])
	Inp.setMobileControls(false)
	Meta.refreshMetaUI()
	_hook("markSessionSettled")
	_snd("death" if reason == "death" else "result")


func returnHome() -> void:
	Meta.developerRun = Meta.freshDeveloperRun()
	finishPresentation()
	Inp.clearPhysicalMovement()
	bullets = []
	enemies = []
	particles = []
	texts = []
	rings = []
	hazards = []
	drones = []
	gems = []
	state = "menu"
	Meta.runGrowth = null
	Inp.mouse.down = false
	Inp.keys.clear()
	Inp.setMobileControls(false)
	_hook("showHome")  # hides pause/gameover/upgrade/meta/how/pauseConfirm/hud; shows start
	Meta.refreshMetaUI()
	_hook("syncResumeEntry")
	_hook("clearRunSession")  # sessionId='' ; runLoadoutCards=[]
	last = U.now_ms()


func showPauseConfirm(action) -> void:
	pausePendingAction = action
	_hook("showPauseConfirm", [action])


func pause_info() -> Dictionary:
	return {
		"level": player.level,
		"score": floori(score),
		"credits": Meta.earnedCreditAmount(),
		"loot": Meta.runRewardCount(),
	}


func renderRunStatus() -> void:
	_hook("renderRunStatus")


func setPause(on: bool) -> void:
	if state == "upgrade" or state == "gameover" or state == "menu":
		return
	if on and state == "playing":
		state = "paused"
		cancelCombatInput()
		screenShake = 0.0
		flash = 0.0
		sceneDirty = true
		syncCombatHud()
		renderRunStatus()
		_hook("syncDroneControls")
		pausePendingAction = null
		Inp.setMobileControls(false)
		_hook("showPause", [pause_info()])
		_hook("focusPanel", ["pauseScreen", "pauseResumeBtn"])
		_hook("syncInputSettings")
	elif not on and state == "paused":
		state = "playing"
		_hook("hidePause")
		_hook("focusCombat")
		syncCombatHud()
		last = U.now_ms()


func togglePause() -> void:
	if state == "upgrade":
		closeCardChoices()
		return
	if state == "ability":
		Combat.closeAbilityRewards()
		return
	if state == "playing":
		setPause(true)
	elif state == "paused":
		setPause(false)


func addXP(amount) -> void:
	if not (amount is float or amount is int) or is_nan(amount) or is_inf(amount) or amount <= 0 or runSettled:
		return
	player.xp += amount * float(player.get("xpMultiplier", 1.0))
	drainRunXp()
	# No modal and no lost excess XP: levels accumulate as selection rights.


# ---------- Dash / damage ----------
func dash() -> void:
	if player.dashReady < 1 or player.dashTime > 0:
		return
	var dx: float = 0.0
	var dy: float = 0.0
	if Inp.keyboardMoveHeld("KeyW") or Inp.keyboardMoveHeld("ArrowUp"): dy -= 1
	if Inp.keyboardMoveHeld("KeyS") or Inp.keyboardMoveHeld("ArrowDown"): dy += 1
	if Inp.keyboardMoveHeld("KeyA") or Inp.keyboardMoveHeld("ArrowLeft"): dx -= 1
	if Inp.keyboardMoveHeld("KeyD") or Inp.keyboardMoveHeld("ArrowRight"): dx += 1
	if Inp.inputMode == "touch" and Inp.mobileMove.active and Inp.mobileMove.mag > 0.08:
		dx = Inp.mobileMove.x
		dy = Inp.mobileMove.y
	if dx == 0.0 and dy == 0.0:
		var a: float = atan2(Inp.mouse.y - player.y, Inp.mouse.x - player.x)
		dx = cos(a)
		dy = sin(a)
	else:
		var l: float = sqrt(dx * dx + dy * dy)
		dx /= l
		dy /= l
	player.vx = dx * 820.0
	player.vy = dy * 820.0
	player.dashTime = 0.16
	player.dashReady = 0.0
	player.dashInvuln = maxf(player.dashInvuln, 0.24)
	screenShake = maxf(screenShake, 5.0)
	if player.dashNova:
		Combat.explode(player.x, player.y, player.damage * player.dashNova, player.dashNovaRadius, 185, true)
	if player.gearEffects.get("ion", 0):
		Combat.addFriendly({"kind": "meteor", "x": player.x, "y": player.y, "warn": 0.6, "radius": 145, "damage": player.damage * (1 + player.gearEffects.ion * 0.24), "source": "gear", "hue": 190, "duration": 0.3})
	Cards.emitCardTrigger("on_dash", {})
	if rings.size() < PERF.maxRings:
		rings.push_back({"x": player.x, "y": player.y, "r": 18, "life": 0.28, "max": 0.28, "hue": 185})
	_snd("dash")


func damagePlayer(amount: float, attack: Dictionary = {}) -> bool:
	if state != "playing" or runSettled or amount <= 0:
		return false
	if Meta.developerRun.active and Meta.developerRun.god:
		return false
	var kind: String = attack.get("kind", "normal") if attack.get("kind", "") != "" else "normal"
	var cfg: Dictionary = Meta.challenge()
	# Evasion and brief hit-recovery invulnerability are not the destructible barrier.
	if player.dashInvuln > 0 or player.invuln > 0:
		return false
	if cfg.get("oneHit", false):
		player.hp = 0.0
		gameOver("death")
		return true
	var bypass: bool = kind == "pierce" or kind == "break"
	if kind == "break":
		_snd("break")
		var hadShield: bool = player.shieldHits > 0
		player.shieldHits = 0
		player.barrierTime = 0.0
		var lk = attack.get("lock", 3)
		if lk == null or lk == 0:
			lk = 3
		player.barrierLock = maxf(player.barrierLock, lk / (1.0 + player.debuffResistance))
		if hadShield:
			Cards.emitCardTrigger("on_shield_break", {"damage": amount, "enemy": attack.get("enemy")})
		if texts.size() < PERF.maxTexts:
			texts.push_back({"x": player.x, "y": player.y - 45, "text": "バリア破壊・付与封印", "life": 1.1, "max": 1.1, "hue": 320, "size": 14})
	if not bypass and player.barrierTime > 0:
		return false
	if not bypass and cfg.get("shield", false) and player.shieldHits > 0:
		_snd("shield")
		player.shieldHits -= 1
		player.invuln = 0.12
		Combat.onGearImpact(true)
		if player.shieldHits == 0:
			Cards.emitCardTrigger("on_shield_break", {"damage": amount, "enemy": attack.get("enemy")})
		if rings.size() < PERF.maxRings:
			rings.push_back({"x": player.x, "y": player.y, "r": 15, "life": 0.18, "max": 0.18, "hue": 190})
		return true
	if kind == "wound":
		player.wounded = maxf(player.wounded, 5.0 / (1.0 + player.debuffResistance))
	var actual: float = amount * (1.0 - player.armor) * ((1.0 - player.guardReduction) if player.guardTimer > 0 else 1.0)
	actual = maxf(0.1, actual)
	var previous: float = player.hp / player.maxHp
	player.hp = maxf(0.0, player.hp - actual)
	player.invuln = 0.35
	# Fatal hits cannot be retroactively cancelled by a healing trigger (Phoenix is explicit).
	if player.hp > 0:
		Combat.onGearImpact(false)
		Cards.emitCardTrigger("on_damage", {"damage": actual, "enemy": attack.get("enemy")})
		if previous > 0.35 and player.hp / player.maxHp <= 0.35:
			Cards.emitCardTrigger("on_low_hp", {"damage": actual, "enemy": attack.get("enemy")})
	flash = 0.1
	screenShake = maxf(screenShake, 6.0)
	if texts.size() < PERF.maxTexts:
		texts.push_back({"x": player.x, "y": player.y - 26, "text": "-%d" % ceili(actual), "life": 0.65, "max": 0.65, "hue": 355, "size": 14})
	if player.hp <= 0:
		if cfg.heal > 0 and player.phoenix > 0:
			player.phoenix -= 1
			player.hp = player.maxHp * 0.3
			player.dashInvuln = 1.8
			Combat.explode(player.x, player.y, player.damage * 3, 180, 35, true)
		else:
			gameOver("death")
			return true
	_snd("hit")
	return true


# ---------- Update ----------
func update(dt: float) -> void:
	if state != "playing" or runSettled:
		return
	if Inp.inputMode == "keyboard":
		Inp.syncKeyboardMirror()
	if clearPending:
		gameOver("clear")
		return
	time += dt
	waveTimer += dt
	flash = maxf(0.0, flash - dt)
	screenShake = maxf(0.0, screenShake - dt * 24.0)
	player.invuln = maxf(0.0, player.invuln - dt)
	player.guardTimer = maxf(0.0, player.guardTimer - dt)
	if player.guardTimer <= 0:
		player.guardReduction = 0.0
	player.shootTimer -= dt
	player.dashTime = maxf(0.0, player.dashTime - dt)
	player.dashReady = minf(1.0, player.dashReady + dt / player.dashCooldown)
	if player.regen:
		healPlayer(player.regen * dt, "regen")
	updateRunSystems(dt)
	if clearPending:
		gameOver("clear")
		return
	var targetWave: int = floori(time / float(Meta.currentWaveSeconds())) + 1
	if Meta.runConfig.mode == "clear":
		targetWave = mini(targetWave, int(Meta.finalWaveTarget()))
	if targetWave != wave:
		wave = targetWave
		waveTimer = 0.0
		score += 260 + wave * 42
		for e in enemies:
			if not e.get("_dead", false):
				Enemies.refreshEnemyLevel(e)
		texts.push_back({"x": player.x, "y": player.y - 100, "text": "WAVE %d / 敵 Lv.%d" % [wave, Enemies.enemyLevelForWave()], "life": 1.2, "max": 1.2, "hue": 190, "size": 21})
		var bi = Meta.challenge().get("bossInterval", 5)
		if bi == null or bi == 0:
			bi = 5
		if not Enemies.isBossOnly() and (wave % int(bi) == 0 or Meta.isFinalClearWave()) and not bossAlive:
			Enemies.spawnBoss()
		Cards.emitCardTrigger("on_wave", {"wave": wave})
	if not Enemies.isBossOnly() and Meta.isFinalClearWave() and not bossAlive and not clearPending:
		Enemies.spawnBoss()
	bossWarningTimer = maxf(0.0, bossWarningTimer - dt)
	if bossWarningTimer <= 0:
		_hook("hideBossWarning")
	if Inp.inputMode != "touch" and Inp.mobileMove.active:
		for c in Inp.stickControllers:
			if c is Dictionary and c.has("active") and c.active.call():
				c.reset.call()
	var dx: float = Render.dxMove()
	var dy: float = Render.dyMove()
	var length: float = sqrt(dx * dx + dy * dy)
	if length > 1:
		dx /= length
		dy /= length
	if length < 0.10:
		dx = 0.0
		dy = 0.0
	if player.dashTime <= 0:
		var speed: float = player.speed * (1.25 if player.phaseSpeedTimer > 0 else 1.0)
		var response: float = 12.0 if (dx != 0.0 or dy != 0.0) else 24.0
		player.vx += (dx * speed - player.vx) * minf(1.0, dt * response)
		player.vy += (dy * speed - player.vy) * minf(1.0, dt * response)
		if dx == 0.0 and dy == 0.0 and sqrt(player.vx * player.vx + player.vy * player.vy) < 2:
			player.vx = 0.0
			player.vy = 0.0
	player.x = U.clamp(player.x + player.vx * dt, 20.0, World.W - 20.0)
	player.y = U.clamp(player.y + player.vy * dt, 20.0, World.H - 20.0)
	World.updateFieldZones(dt)
	World.updateCamera(dt)
	if Inp.inputMode == "keyboard" and Inp.pointerClient.valid:
		Inp.updateMousePosition(Inp.pointerClient.x, Inp.pointerClient.y)
	if Inp.mobileAim.active and Inp.mobileAim.mag > 0.10:
		var al: float = sqrt(Inp.mobileAim.x * Inp.mobileAim.x + Inp.mobileAim.y * Inp.mobileAim.y)
		if al == 0.0:
			al = 1.0
		Inp.mouse.x = player.x + Inp.mobileAim.x / al * 720.0
		Inp.mouse.y = player.y + Inp.mobileAim.y / al * 720.0
		Inp.mouse.down = Inp.mobileAim.mag > 0.18
	if Inp.mouse.down and player.shootTimer <= 0:
		Combat.firePlayer()
	elif not Inp.mouse.down:
		player.shootTimer = maxf(0.0, player.shootTimer)  # Idle time cannot stockpile shots.
	Combat.updateFriendlySystems(dt)
	if clearPending:
		gameOver("clear")
		return
	Enemies.updateEncounterPopulation(dt)
	Combat.updateDrones(dt)
	Combat.updateProjectiles(dt)
	if state != "playing":
		return
	if clearPending:
		gameOver("clear")
		return
	Enemies.updateEnemies(dt)
	if state != "playing":
		return
	Enemies.updateHazards(dt)
	if state != "playing":
		return
	Combat.updateLoot(dt)
	Combat.updateVisualEffects(dt)
	if comboTimer > 0:
		comboTimer -= dt
	else:
		comboKills = 0
		combo = 1.0
	uiTimer -= dt
	if uiTimer <= 0:
		updateUI()
		uiTimer = 1.0 / float(PERF.hudFps)


func objective_text() -> String:
	var boss = null
	for e in enemies:
		if e.get("boss", false) and not e.get("_dead", false):
			boss = e
			break
	var bossName: String = "防衛異常体"
	if boss != null:
		if boss.get("bossKind", "") == "spinner":
			bossName = "回転異常体"
		elif boss.get("bossKind", "") == "hunter":
			bossName = "追跡異常体"
	var cfg: Dictionary = Meta.challenge()
	var dmgPct: int = roundi(Enemies.enemyScaling(Enemies.enemyLevelForWave()).damage * 100.0)
	var bi: int = int(cfg.get("bossInterval", 5))
	if bi == 0:
		bi = 5
	if bossAlive:
		var nb: int = Enemies.activeBosses().size()
		return "%s%s / %s CP%.1f" % [bossName, (" ほか / ボス%d体" % nb) if nb > 1 else "", cfg.label, cfg.cp]
	if Meta.isFinalClearWave():
		return "FINAL WAVE / 最終Bossを撃破せよ"
	if wave % bi == bi - 1:
		return "ボス反応接近 / 敵攻撃 %d%%" % dmgPct
	var head: String = ("CLEAR %d/%d" % [wave, Meta.finalWaveTarget()]) if Meta.runConfig.mode == "clear" else "ENDLESS"
	return "%s / 敵攻撃 %d%%" % [head, dmgPct]


func updateUI() -> void:
	var defense: Array = []
	if int(player.get("shieldHits", 0)) > 0:
		defense.append("SHIELD ×%d" % player.shieldHits)
	if float(player.get("guardTimer", 0)) > 0:
		defense.append("GUARD %.1fs" % player.guardTimer)
	var cw: float = Combat.comboWindow()
	_hook("updateUI", [{
		"hpPct": U.clamp(player.hp / player.maxHp * 100.0, 0.0, 100.0),
		"hpText": "%d / %d" % [ceili(player.hp), ceili(player.maxHp)],
		"levelText": "%02d" % player.level,
		"scoreText": "%06d" % floori(score),
		"comboText": "x%.2f" % combo,
		"comboKillsText": "%d 連鎖" % comboKills,
		"comboBarPct": comboTimer / cw * 100.0 if cw != 0.0 else 0.0,
		"waveText": "ウェーブ %02d" % wave,
		"objectiveText": objective_text(),
		"xpText": "%d / %d" % [floori(player.xp), player.nextXp],
		"xpPct": player.xp / player.nextXp * 100.0,
		"rarityBoostText": "次回エピック確定" if player.epicGuarantee else "希少共鳴 %d / 3" % player.rarityCharge,
		"epicGuarantee": player.epicGuarantee,
		"dashPct": player.dashReady * 100.0,
		"defenseText": " / ".join(defense),
	}])
	syncCombatHud()


# ---------- Fixed-step driver (original loop 9500-9526) ----------
## Call from main.gd _process(delta). Returns true when the scene should be (re)drawn this frame.
func step_frame(real_dt: float) -> bool:
	var now: float = U.now_ms()
	_hook("syncInputPresentation")
	var actualFrameDt: float = maxf(0.0, real_dt)
	var frameDt: float = minf(MAX_FRAME_DT, actualFrameDt)
	last = now
	if state == "playing":
		simAccumulator += frameDt
		var steps: int = 0
		while simAccumulator >= FIXED_STEP and steps < MAX_SIM_STEPS and state == "playing":
			update(FIXED_STEP)
			simAccumulator -= FIXED_STEP
			steps += 1
		if steps >= MAX_SIM_STEPS and simAccumulator > FIXED_STEP * 2.0:
			simAccumulator = FIXED_STEP
	else:
		simAccumulator = 0.0
		# Run time and effects never advance on the result / pause / reward screens.
		if state == "menu" or state == "config":
			time += frameDt * 0.22
			for r in rings:
				r.life -= frameDt
			rings = rings.filter(func(r): return r.life > 0)
	var draw: bool = state == "playing" or state == "menu" or state == "config" or sceneDirty or lastRenderedState != state
	if draw:
		sceneDirty = false
		lastRenderedState = state
	return draw


# ---------- Suspend/resume run save (delegates to scripts/runsave.gd; original 10360-10544) ----------
const _RS = preload("res://scripts/runsave.gd")
var pendingRunImport = null
func encodeRunGraph(root): return _RS.encodeRunGraph(root)
func decodeRunGraph(graph): return _RS.decodeRunGraph(graph)
func settledRunIds() -> Array: return _RS.settledRunIds()
func sessionAlreadySettled() -> bool: return _RS.sessionAlreadySettled()
func markSessionSettled() -> void: _RS.markSessionSettled()
func startRunSession() -> void: _RS.startRunSession()
func clearRunSession() -> void: _RS.clearRunSession()
func choiceDescriptor(c): return _RS.choiceDescriptor(c)
func restoreRunChoice(c): return _RS.restoreRunChoice(c)
func makeRunSave() -> Dictionary: return _RS.makeRunSave()
func validateRunSave(raw) -> Dictionary: return _RS.validateRunSave(raw)
func readSuspended() -> Dictionary: return _RS.readSuspended()
func clearSuspended() -> void: _RS.clearSuspended()
func syncResumeEntry() -> void: _RS.syncResumeEntry()
func persistRunSave(payload) -> String: return _RS.persistRunSave(payload)
func suspendRunToHome(force: bool = false) -> bool: return _RS.suspendRunToHome(force)
func downloadRunSave() -> String: return _RS.downloadRunSave()
func exportRunSave(path: String) -> String: return _RS.exportRunSave(path)
func importRunSave(path: String) -> String: return _RS.importRunSave(path)
func applyRunImport() -> String: return _RS.applyRunImport()
func restoreSuspended(payload = null) -> bool: return _RS.restoreSuspended(payload)
func resumeInfoText() -> String: return _RS.resumeInfoText()
