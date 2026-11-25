extends Node2D
var n := 0
var acc := 0.0
func _ready():
	Game.resetGame()
	var p = Game.player
	var types := ["chaser","swift","tank","shooter","splitter","charger","orbiter","disruptor","lancer","bombardier","medic","bulwark","suppressor"]
	Game.wave = 10
	for i in 190:
		var e = Enemies.spawnEnemy(types[i % 13])
		if e == null: continue
		e.spawnDelay = 0.0
		e.x = p.x + randf_range(-780, 780); e.y = p.y + randf_range(-420, 420)
		e.elite = i % 5 == 0
		e.armored = i % 7 == 0
	Enemies.spawnBoss()
	for e in Game.enemies:
		e.spawnDelay = 0.0
		e.x = p.x + randf_range(-780, 780); e.y = p.y + randf_range(-420, 420)
	for i in 500:
		Game.bullets.append({"x": p.x + randf_range(-780, 780), "y": p.y + randf_range(-420, 420), "vx": 100.0, "vy": 50.0, "r": 4.0, "life": 3.0, "damage": 1.0, "enemy": i % 3 == 0, "attackKind": ["normal","break","pierce","wound"][i % 4]})
	for i in 40:
		Game.hazards.append({"age": 0.5, "warn": 1.0, "duration": .2, "hit": false, "kind": "normal", "label": "x", "shape": "circle", "x": p.x + randf_range(-700,700), "y": p.y + randf_range(-400,400), "radius": 80.0})
	World.camera.x = p.x - 800; World.camera.y = p.y - 450
	print("enemies ", Game.enemies.size())
func _process(_d):
	queue_redraw()
func _draw():
	var t0 := Time.get_ticks_usec()
	Render.draw(self)
	var dt := Time.get_ticks_usec() - t0
	n += 1
	if n > 10:
		acc += dt
	if n == 70:
		print("draw ms avg ", acc / 60.0 / 1000.0, " drawcalls ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " objs ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
		get_tree().quit()
