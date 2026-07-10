class_name RingController
extends Node2D

signal catch_resolved(player_id: int, result: Dictionary)

const SEGMENT_COUNT := 60
const RADIUS := 182.0
const LED_RADIUS := 9.0
const PLAYER_TARGETS := {
	1: 180.0,
	2: 0.0
}

@export var base_degrees_per_second := 160.0
@export var max_degrees_per_second := 390.0
@export var sudden_death_degrees_per_second := 520.0
@export var target_oscillation_degrees := 45.0
@export var target_oscillation_cycles_per_second := 0.22

var spinner_degrees := 270.0
var current_speed := base_degrees_per_second
var spin_direction := 1.0
var feedback := ""
var feedback_color := Color.WHITE
var feedback_timer := 0.0
var pulse_timer := 0.0
var sudden_death := false
var victory_flash := false
var victory_celebration_timer := 0.0
var victory_celebration_color := Color.WHITE
var victory_celebration_emit_debt := 0.0
var particles: Array[Dictionary] = []
var shockwaves: Array[Dictionary] = []

func _process(delta: float) -> void:
	var target_speed := sudden_death_degrees_per_second if sudden_death else current_speed
	spinner_degrees = wrapf(spinner_degrees + target_speed * spin_direction * delta, 0.0, 360.0)
	feedback_timer = maxf(feedback_timer - delta, 0.0)
	pulse_timer += delta
	_update_victory_celebration(delta)
	_update_particles(delta)
	_update_shockwaves(delta)
	queue_redraw()

func resolve_catch(player_id: int) -> Dictionary:
	var result := SkillCheckResolver.resolve(spinner_degrees, target_degrees_for_player(player_id))
	catch_resolved.emit(player_id, result)
	return result

func target_degrees_for_player(player_id: int) -> float:
	var base_degrees := float(PLAYER_TARGETS[player_id])
	var oscillation := sin(pulse_timer * TAU * target_oscillation_cycles_per_second) * target_oscillation_degrees
	return wrapf(base_degrees + oscillation, 0.0, 360.0)

func add_speed_pressure(amount: float) -> void:
	current_speed = clampf(current_speed + amount * 42.0, base_degrees_per_second, max_degrees_per_second)

func reverse_spin_direction(show_reverse_feedback := true) -> void:
	spin_direction *= -1.0
	if show_reverse_feedback:
		show_feedback("REVERSE", Color(1.0, 0.86, 0.18))

func reset_ring() -> void:
	spinner_degrees = 270.0
	current_speed = base_degrees_per_second
	spin_direction = 1.0
	feedback = ""
	feedback_timer = 0.0
	sudden_death = false
	victory_flash = false
	victory_celebration_timer = 0.0
	victory_celebration_emit_debt = 0.0
	particles.clear()
	shockwaves.clear()
	queue_redraw()

func show_feedback(label: String, color: Color) -> void:
	feedback = label
	feedback_color = color
	feedback_timer = 0.55

func spawn_hit_particles(player_id: int, label: String, color: Color) -> void:
	if label != "PERFECT" and label != "GOOD":
		return
	var count := 110 if label == "PERFECT" else 34
	var target_degrees := target_degrees_for_player(player_id)
	var origin := _point_for_degrees(target_degrees, RADIUS)
	for i in range(count):
		var spread := randf_range(-1.8, 1.8) if label == "PERFECT" else randf_range(-0.9, 0.9)
		var radians := deg_to_rad(target_degrees) + spread
		var speed := randf_range(110.0, 390.0) if label == "PERFECT" else randf_range(65.0, 170.0)
		var particle_color := color.lerp(Color(1.0, 1.0, 0.35), randf_range(0.0, 0.55)) if label == "PERFECT" else color
		particles.append({
			"position": origin,
			"velocity": Vector2(cos(radians), sin(radians)) * speed,
			"color": particle_color,
			"life": 0.0,
			"ttl": randf_range(0.5, 1.05) if label == "PERFECT" else randf_range(0.28, 0.5),
			"radius": randf_range(3.5, 9.0) if label == "PERFECT" else randf_range(2.0, 5.0)
		})
	if label == "PERFECT":
		shockwaves.append({
			"position": origin,
			"color": color,
			"life": 0.0,
			"ttl": 0.42,
			"start_radius": 16.0,
			"end_radius": 118.0
		})

func set_sudden_death(enabled: bool) -> void:
	sudden_death = enabled

func set_victory_flash(enabled: bool) -> void:
	victory_flash = enabled
	queue_redraw()

func start_victory_celebration(color: Color) -> void:
	victory_celebration_color = color
	victory_celebration_timer = 2.6
	victory_celebration_emit_debt = 0.0
	_spawn_center_celebration_particles(150)
	for i in range(3):
		shockwaves.append({
			"position": Vector2.ZERO,
			"color": color.lerp(Color(1.0, 0.95, 0.25), float(i) * 0.18),
			"life": -float(i) * 0.12,
			"ttl": 0.72 + float(i) * 0.14,
			"start_radius": 20.0 + float(i) * 12.0,
			"end_radius": RADIUS + 90.0 + float(i) * 26.0
		})

func _update_victory_celebration(delta: float) -> void:
	if victory_celebration_timer <= 0.0:
		return
	victory_celebration_timer = maxf(victory_celebration_timer - delta, 0.0)
	victory_celebration_emit_debt += delta * 150.0
	var emit_count := int(victory_celebration_emit_debt)
	if emit_count <= 0:
		return
	victory_celebration_emit_debt -= float(emit_count)
	_spawn_center_celebration_particles(emit_count)

func _spawn_center_celebration_particles(count: int) -> void:
	for i in range(count):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(120.0, 620.0)
		var color := victory_celebration_color.lerp(Color.from_hsv(randf(), 0.95, 1.0), randf_range(0.08, 0.5))
		particles.append({
			"position": Vector2(randf_range(-18.0, 18.0), randf_range(-18.0, 18.0)),
			"velocity": Vector2(cos(angle), sin(angle)) * speed,
			"color": color,
			"life": 0.0,
			"ttl": randf_range(0.8, 2.25),
			"radius": randf_range(4.0, 12.0)
		})

func _update_particles(delta: float) -> void:
	for particle in particles:
		particle["life"] = particle["life"] + delta
		particle["position"] = particle["position"] + particle["velocity"] * delta
		particle["velocity"] = particle["velocity"] * 0.88
	particles = particles.filter(func(particle: Dictionary) -> bool: return particle["life"] < particle["ttl"])

func _update_shockwaves(delta: float) -> void:
	for shockwave in shockwaves:
		shockwave["life"] = shockwave["life"] + delta
	shockwaves = shockwaves.filter(func(shockwave: Dictionary) -> bool: return shockwave["life"] < shockwave["ttl"])

func _draw() -> void:
	var ring_color := Color(0.16, 0.22, 0.34)
	draw_arc(Vector2.ZERO, RADIUS + 24.0, 0.0, TAU, 128, Color(0.03, 0.06, 0.11), 18.0, true)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 128, ring_color, 4.0, true)

	_draw_target_zone(target_degrees_for_player(1), Color(0.15, 0.65, 1.0), "P1")
	_draw_target_zone(target_degrees_for_player(2), Color(1.0, 0.22, 0.55), "P2")

	for i in range(SEGMENT_COUNT):
		var degrees := float(i) / float(SEGMENT_COUNT) * 360.0
		var led_position := _point_for_degrees(degrees, RADIUS)
		var distance := SkillCheckResolver.angle_distance_degrees(degrees, spinner_degrees)
		var led_color := Color(0.09, 0.13, 0.21)
		var led_size := LED_RADIUS
		if victory_flash:
			var hue := fmod(float(i) * 0.075 + pulse_timer * 1.8 + sin(float(i) * 9.31 + pulse_timer * 8.0) * 0.08, 1.0)
			var value := 0.72 + absf(sin(float(i) * 4.17 + pulse_timer * 13.0)) * 0.28
			led_color = Color.from_hsv(hue, 0.95, value)
			led_size = 9.5 + sin(pulse_timer * 12.0 + float(i)) * 3.0
		elif distance < 5.0:
			led_color = Color(0.95, 1.0, 0.25)
			led_size = 13.0 + sin(pulse_timer * 18.0) * 2.0
		elif distance < 18.0:
			led_color = Color(0.35, 0.85, 1.0)
			led_size = 9.5
		draw_circle(led_position, led_size, led_color)

	if feedback_timer > 0.0:
		var alpha := clampf(feedback_timer / 0.55, 0.0, 1.0)
		draw_circle(Vector2.ZERO, 58.0 + (1.0 - alpha) * 24.0, Color(feedback_color.r, feedback_color.g, feedback_color.b, alpha * 0.24))

	for particle in particles:
		var alpha := 1.0 - float(particle["life"]) / float(particle["ttl"])
		var color: Color = particle["color"]
		var particle_position: Vector2 = particle["position"]
		var particle_radius: float = particle["radius"]
		draw_circle(particle_position, particle_radius * alpha, Color(color.r, color.g, color.b, alpha))

	for shockwave in shockwaves:
		if float(shockwave["life"]) < 0.0:
			continue
		var progress := clampf(float(shockwave["life"]) / float(shockwave["ttl"]), 0.0, 1.0)
		var color: Color = shockwave["color"]
		var shock_position: Vector2 = shockwave["position"]
		var shock_radius: float = lerpf(shockwave["start_radius"], shockwave["end_radius"], progress)
		draw_arc(shock_position, shock_radius, 0.0, TAU, 64, Color(color.r, color.g, color.b, 1.0 - progress), 4.0, true)

func _draw_target_zone(degrees: float, color: Color, label: String) -> void:
	var good_start := deg_to_rad(degrees - SkillCheckResolver.GOOD_WINDOW_DEGREES)
	var good_end := deg_to_rad(degrees + SkillCheckResolver.GOOD_WINDOW_DEGREES)
	var perfect_start := deg_to_rad(degrees - SkillCheckResolver.PERFECT_WINDOW_DEGREES)
	var perfect_end := deg_to_rad(degrees + SkillCheckResolver.PERFECT_WINDOW_DEGREES)
	draw_arc(Vector2.ZERO, RADIUS + 19.0, good_start, good_end, 16, Color(color.r, color.g, color.b, 0.32), 14.0, true)
	draw_arc(Vector2.ZERO, RADIUS + 19.0, perfect_start, perfect_end, 8, Color(color.r, color.g, color.b, 0.95), 7.0, true)
	var label_position := _point_for_degrees(degrees, RADIUS + 58.0)
	draw_string(ThemeDB.get_fallback_font(), label_position - Vector2(18.0, -7.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)

func _point_for_degrees(degrees: float, radius: float) -> Vector2:
	var radians := deg_to_rad(degrees)
	return Vector2(cos(radians), sin(radians)) * radius
