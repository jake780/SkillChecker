extends Control

var pulse_time := 0.0

func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.36
	for i in range(36):
		var angle := float(i) / 36.0 * TAU
		var hue := fmod(float(i) / 36.0 + pulse_time * 0.35, 1.0)
		var color := Color.from_hsv(hue, 0.95, 0.95)
		var dot_position := center + Vector2(cos(angle), sin(angle)) * radius
		var dot_radius := 6.0
		if i == int(fmod(pulse_time * 15.0, 36.0)):
			dot_radius = 11.0
			color = Color(1.0, 1.0, 0.25)
		draw_circle(dot_position, dot_radius, color)
		draw_circle(dot_position, dot_radius * 1.7, Color(color.r, color.g, color.b, 0.16))
