extends Node
## Fidelity checks for Game/Inp (godot --headless --path godot res://tests/game_audit.tscn)
var fails := 0
func _chk(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", m)
func _ready() -> void:
	Game.player = Game.playerBase()
	Game.runSettled = false
	# addXP: xpMultiplier 0 behaves as 1 (JS ||)
	Game.player.xpMultiplier = 0.0
	Game.player.xp = 0.0
	Game.addXP(3)
	_chk(is_equal_approx(Game.player.xp, 3.0), "addXP xpMultiplier 0 -> 1")
	Game.addXP(NAN); Game.addXP(-1)
	_chk(is_equal_approx(Game.player.xp, 3.0), "addXP ignores NaN/neg")
	# runXpNeeded
	_chk(Game.runXpNeeded(1) == 15, "runXpNeeded(1)=" + str(Game.runXpNeeded(1)))
	# damagePlayer with null kind must not error
	Game.state = "playing"
	Game.player.hp = 100.0
	Game.player.invuln = 0.0; Game.player.dashInvuln = 0.0
	_chk(Game.damagePlayer(10.0, {"kind": null}), "damagePlayer null kind")
	_chk(is_equal_approx(Game.player.hp, 90.0), "damage applied")
	# session hooks reach runsave
	Game.state = "menu"
	Game.startRunSession()
	_chk(preload("res://scripts/runsave.gd").sessionId != "", "session started")
	print("game_audit done fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
