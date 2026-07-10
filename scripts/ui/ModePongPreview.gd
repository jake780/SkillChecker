extends Control

var pulse_time := 0.0

func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.04, 0.045, 0.055))
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.12), false, 2.0)

	var p1_y := 36.0 + sin(pulse_time * 2.2) * 18.0
	var p2_y := 60.0 + cos(pulse_time * 2.0) * 18.0
	_draw_led_paddle(Vector2(20.0, p1_y), Color(0.15, 0.65, 1.0))
	_draw_led_paddle(Vector2(size.x - 26.0, p2_y), Color(1.0, 0.22, 0.55))

	for i in range(6):
		var x := fmod(pulse_time * (18.0 + float(i) * 5.0) + float(i) * 31.0, size.x - 52.0) + 26.0
		var y := 28.0 + absf(sin(pulse_time * (1.4 + float(i) * 0.13) + float(i))) * (size.y - 58.0)
		var color := Color.from_hsv(fmod(float(i) * 0.17 + pulse_time * 0.8, 1.0), 0.95, 1.0)
		draw_circle(Vector2(x, y), 5.0, color)
		draw_circle(Vector2(x, y), 11.0, Color(color.r, color.g, color.b, 0.12))

	for y in range(12, int(size.y), 18):
		draw_circle(Vector2(size.x * 0.5, float(y)), 2.0, Color(0.8, 0.85, 1.0, 0.28))

func _draw_led_paddle(pos: Vector2, color: Color) -> void:
	for i in range(6):
		var led_pos := pos + Vector2(0.0, float(i) * 10.0)
		draw_circle(led_pos, 4.0, color)
		draw_circle(led_pos, 8.0, Color(color.r, color.g, color.b, 0.13))
