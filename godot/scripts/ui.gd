extends Node
## UI hook bus (milestone 3 fills real screens). Sim code calls UI.hook("name", [args]);
## it is a no-op until a handler named `h_<name>` exists on this node.
func hook(name: String, args: Array = []) -> Variant:
	var m := "h_" + name
	if has_method(m):
		return callv(m, args)
	return null

# ---------------------------------------------------------------- drone control (原作 7889-10312)
const DRONE_DEFAULTS := {"enabled": true, "normal": true, "elite": true, "boss": true, "priority": "nearest", "output": 100}
var droneConfig: Dictionary = DRONE_DEFAULTS.duplicate()

func cleanDroneConfig(raw: Variant = {}) -> Dictionary:
	var r: Dictionary = raw if raw is Dictionary else {}
	var pr: String = str(r.get("priority", "nearest"))
	var out: float = 100.0
	if r.has("output") and (r["output"] is float or r["output"] is int):
		out = clampf(float(r["output"]), 0.0, 100.0)
	return {"enabled": r.get("enabled", true) != false, "normal": r.get("normal", true) != false,
		"elite": r.get("elite", true) != false, "boss": r.get("boss", true) != false,
		"priority": pr if pr in ["nearest", "boss", "elite", "weakest", "strongest", "aim"] else "nearest", "output": out}

func droneStats() -> Dictionary:
	var p: Dictionary = Game.player
	var n: float = maxf(0.0, float(p.droneCount))
	var damage: float = (6.0 + p.damage * float(p.get("droneDamageTransfer", 0.18))) * (p.droneDamage / 10.0)
	var rate: float = (1.1 + p.fireRate * 0.18) * (p.droneRate / 1.25)
	var fleet: float = pow(n, 0.60)
	return {"damage": damage, "rate": rate, "fleetWeight": fleet,
		"dps": damage * rate * fleet * (1.0 + p.crit * 0.25 * (p.critMult - 1.0) * 0.30)}

func droneTargetAllowed(e) -> bool:
	if e == null or e.get("_dead", false) or float(e.get("spawnDelay", 0.0)) > 0.0:
		return false
	if e.get("boss", false): return droneConfig.boss
	if e.get("elite", false): return droneConfig.elite
	return droneConfig.normal

func selectDroneTarget():
	var best = null
	var rank := INF
	var distance := INF
	var p: Dictionary = Game.player
	for e in Game.enemies:
		var d: float = U.dist2(e, p)
		if not droneTargetAllowed(e) or d > p.droneRange * p.droneRange:
			continue
		var r: float
		match droneConfig.priority:
			"boss": r = 0.0 if e.get("boss", false) else 1.0
			"elite": r = 0.0 if e.get("elite", false) else 1.0
			"weakest": r = e.hp
			"strongest": r = -e.hp
			"aim": r = U.dist2(e, Inp.mouse)
			_: r = d
		if r < rank or (r == rank and d < distance):
			best = e; rank = r; distance = d
	return best

func setDroneConfig(patch: Dictionary) -> void:
	var merged := droneConfig.duplicate()
	merged.merge(patch, true)
	droneConfig = cleanDroneConfig(merged)
	Meta.storage_set("nf_drone_control_v1", JSON.stringify(droneConfig))
	for d in Game.drones:
		d.target = null; d.targetClock = 0; d.shotCredit = 0
	if not droneConfig.enabled or droneConfig.output == 0:
		for b in Game.bullets:
			if b.get("fromDrone", false): b._dead = true
	Game.sceneDirty = true

func toggleDrones() -> void:
	setDroneConfig({"enabled": not droneConfig.enabled})
	hook("showInputNotice", ["ドローン " + ("稼働" if droneConfig.enabled else "停止") + "（機数・強化は保持）", 1600])

func load_drone_config() -> void:
	var raw = Meta.storage_get("nf_drone_control_v1")
	if raw != null and str(raw) != "":
		var j = JSON.parse_string(str(raw))
		droneConfig = cleanDroneConfig(j if j is Dictionary else {})
