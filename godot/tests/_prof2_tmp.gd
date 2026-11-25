extends Node2D
var n := 0
var tex: ImageTexture
func _ready():
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x + .5 - 32, y + .5 - 32).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(32.0 - d, 0, 1)))
	tex = ImageTexture.create_from_image(img)
func _process(_d): queue_redraw()
func _draw():
	n += 1
	if n < 20: return
	var a := Time.get_ticks_usec()
	for i in 500: draw_circle(Vector2(i % 50 * 30, i / 50 * 30), 5.0, Color.RED)
	var b := Time.get_ticks_usec()
	for i in 500: draw_texture_rect(tex, Rect2(i % 50 * 30 - 5, i / 50 * 30 - 5, 10, 10), false, Color.RED)
	var c := Time.get_ticks_usec()
	for i in 500: draw_arc(Vector2(i % 50 * 30, i / 50 * 30), 5.0, 0, TAU, 16, Color.RED, 1.5)
	var d := Time.get_ticks_usec()
	var pts := PackedVector2Array()
	for i in 500: pts.append(Vector2(i%50*30, i/50*30)); pts.append(Vector2(i%50*30+10, i/50*30))
	draw_multiline(pts, Color.RED, 2.0)
	var e := Time.get_ticks_usec()
	for i in 500: draw_set_transform(Vector2(i,i), 0.1)
	var f := Time.get_ticks_usec()
	print("circle ", (b-a)/1000.0, " tex ", (c-b)/1000.0, " arc ", (d-c)/1000.0, " multiline ", (e-d)/1000.0, " xform ", (f-e)/1000.0)
	if n > 40: get_tree().quit()
