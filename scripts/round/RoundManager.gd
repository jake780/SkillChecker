extends Node2D

const InputConfig := preload("res://scripts/input/InputRouter.gd")

@onready var ring: RingController = $RingController
@onready var audio: AudioController = $AudioController

var players: Array[PlayerDuelState] = []
var round_active := false
var round_over := false
var countdown := 2.2
var match_message := "GET READY"
var message_timer := 0.0
var shake_timer := 0.0
var shake_strength := 0.0
var round_time := 0.0
var sudden_death_started := false
var impact_particles: Array[Dictionary] = []
var projectile_particles: Array[Dictionary] = []
var local_player_id := 0
var network_sync_timer := 0.0

func _ready() -> void:
	InputConfig.ensure_default_actions()
	local_player_id = NetworkManager.local_player_id()
	players = [
		PlayerDuelState.new(1, "PLAYER 1", Color(0.15, 0.65, 1.0), "p1_catch"),
		PlayerDuelState.new(2, "PLAYER 2", Color(1.0, 0.22, 0.55), "p2_catch")
	]
	ring.catch_resolved.connect(_on_catch_resolved)
	reset_match()

func _process(delta: float) -> void:
	if NetworkManager.is_network_match() and not NetworkManager.is_hosting():
		_update_projectile_particles(delta)
		_update_impact_particles(delta)
		queue_redraw()
		return

	for player in players:
		player.tick(delta)

	if countdown > 0.0:
		countdown -= delta
		match_message = str(ceili(countdown))
		if countdown <= 0.0:
			round_active = true
			match_message = "DUEL"
			message_timer = 0.7
			audio.play_round_start()
	else:
		round_time += delta

	if round_active and round_time > 28.0 and not sudden_death_started:
		sudden_death_started = true
		ring.set_sudden_death(true)
		_show_message("SUDDEN DEATH")
		audio.play_sudden_death()
		_pulse_screen(0.35, 8.0)

	message_timer = maxf(message_timer - delta, 0.0)
	shake_timer = maxf(shake_timer - delta, 0.0)
	_update_projectile_particles(delta)
	_update_impact_particles(delta)
	if NetworkManager.is_network_match() and NetworkManager.is_hosting():
		_sync_duel_state_if_ready(delta)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_round"):
		if NetworkManager.is_network_match() and not NetworkManager.is_hosting():
			_request_duel_restart.rpc_id(1)
		else:
			reset_match()
		get_viewport().set_input_as_handled()
		return

	if not round_active:
		return

	if NetworkManager.is_network_match():
		var player_id := NetworkManager.local_player_id()
		var action := "p1_catch"
		if event.is_action_pressed(action):
			if NetworkManager.is_hosting():
				_resolve_network_catch(player_id)
			else:
				_submit_duel_catch.rpc_id(1)
			get_viewport().set_input_as_handled()
		return

	for player in players:
		if event.is_action_pressed(player.catch_action):
			var result := ring.resolve_catch(player.id)
			_apply_catch_result(player, result)
			get_viewport().set_input_as_handled()

func reset_match() -> void:
	for player in players:
		player.reset_round()
	countdown = 2.2
	round_active = false
	round_over = false
	round_time = 0.0
	sudden_death_started = false
	match_message = "GET READY"
	message_timer = 0.0
	shake_timer = 0.0
	impact_particles.clear()
	projectile_particles.clear()
	ring.reset_ring()
	audio.play_round_start()
	queue_redraw()

func _on_catch_resolved(player_id: int, result: Dictionary) -> void:
	var player := _player_by_id(player_id)
	var color: Color = player.color if player else Color.WHITE
	ring.show_feedback(result["label"], color)
	ring.spawn_hit_particles(player_id, result["label"], color)
	audio.play_catch(result["label"])
	if NetworkManager.is_network_match() and NetworkManager.is_hosting():
		_play_duel_catch_effect.rpc(player_id, str(result["label"]))

func _apply_catch_result(player: PlayerDuelState, result: Dictionary) -> void:
	player.set_result(result["label"])
	if result["charge"] >= 0.0:
		player.add_charge(result["charge"])
		ring.add_speed_pressure(result["speed_bonus"])
		if result["label"] == "PERFECT":
			_show_message("%s PERFECT" % player.display_name)
			ring.reverse_spin_direction(false)
			_pulse_screen(0.16, 4.0)
		_try_auto_attack(player)
	else:
		player.add_charge(result["charge"])
		_show_message("%s MISS" % player.display_name)

func _try_auto_attack(player: PlayerDuelState) -> void:
	if not round_active or player.charge < PlayerDuelState.MAX_CHARGE:
		return
	var defender := players[1] if player.id == 1 else players[0]
	var outcome := AttackResolver.try_attack(player, defender)
	_show_message(outcome["message"])
	if outcome["success"]:
		audio.play_attack(outcome["heavy"])
		_spawn_projectile_particles(player, defender)
		_spawn_damage_particles(defender, outcome["heavy"], player.color)
		if NetworkManager.is_network_match() and NetworkManager.is_hosting():
			_play_duel_attack_effect.rpc(player.id, defender.id, bool(outcome["heavy"]))
		_pulse_screen(0.35, 18.0)
		_check_round_winner()
	else:
		audio.play_no_charge()

func _resolve_network_catch(player_id: int) -> void:
	if not round_active:
		return
	var player := _player_by_id(player_id)
	if player == null:
		return
	var result := ring.resolve_catch(player_id)
	_apply_catch_result(player, result)

func _check_round_winner() -> void:
	for player in players:
		if player.health <= 0.0:
			var winner := players[1] if player.id == 1 else players[0]
			winner.score += 1
			round_active = false
			round_over = true
			match_message = "%s WINS" % winner.display_name
			message_timer = 999.0
			ring.set_sudden_death(false)
			ring.set_victory_flash(true)
			ring.start_victory_celebration(winner.color)
			audio.play_win()
			if NetworkManager.is_network_match() and NetworkManager.is_hosting():
				_play_duel_win_effect.rpc(winner.id)

func _show_message(message: String) -> void:
	match_message = message
	message_timer = 1.0

func _pulse_screen(duration: float, strength: float) -> void:
	shake_timer = duration
	shake_strength = strength

func _spawn_damage_particles(defender: PlayerDuelState, heavy: bool, attacker_color: Color) -> void:
	var origin := _player_hud_center(defender.id)
	var count := 170 if heavy else 48
	for i in range(count):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(130.0, 420.0) if heavy else randf_range(80.0, 260.0)
		var color := attacker_color.lerp(Color(1.0, 0.95, 0.25), randf_range(0.0, 0.65))
		impact_particles.append({
			"position": origin + Vector2(randf_range(-42.0, 42.0), randf_range(-22.0, 22.0)),
			"velocity": Vector2(cos(angle), sin(angle)) * speed,
			"color": color,
			"life": 0.0,
			"ttl": randf_range(0.45, 0.95) if heavy else randf_range(0.28, 0.62),
			"radius": randf_range(4.0, 10.0) if heavy else randf_range(2.5, 6.0)
		})

func _spawn_projectile_particles(attacker: PlayerDuelState, defender: PlayerDuelState) -> void:
	var start := _player_blast_origin(attacker)
	var end := _player_blast_origin(defender)
	var direction := (end - start).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	for i in range(170):
		var progress := randf_range(0.0, 1.0)
		var beam_position := start.lerp(end, progress) + perpendicular * randf_range(-38.0, 38.0)
		var speed := randf_range(520.0, 980.0)
		var color := attacker.color.lerp(Color(1.0, 1.0, 0.25), randf_range(0.15, 0.75))
		projectile_particles.append({
			"position": beam_position,
			"velocity": direction * speed + perpendicular * randf_range(-120.0, 120.0),
			"color": color,
			"life": 0.0,
			"ttl": randf_range(0.2, 0.55),
			"radius": randf_range(3.0, 8.0)
		})

func _player_blast_origin(player: PlayerDuelState) -> Vector2:
	var panel_rect := _player_hud_rect(player.id)
	if player.id == 1:
		return panel_rect.position + Vector2(panel_rect.size.x, panel_rect.size.y * 0.5)
	return panel_rect.position + Vector2(0.0, panel_rect.size.y * 0.5)

func _player_hud_center(player_id: int) -> Vector2:
	var panel_rect := _player_hud_rect(player_id)
	return panel_rect.position + panel_rect.size * 0.5

func _player_hud_rect(player_id: int) -> Rect2:
	var panel_size := Vector2(342.0, 132.0)
	var viewport_size := get_viewport_rect().size
	var panel_x := 56.0 if player_id == 1 else viewport_size.x - panel_size.x - 56.0
	return Rect2(Vector2(panel_x, 0.0), panel_size)

func _update_projectile_particles(delta: float) -> void:
	for particle in projectile_particles:
		particle["life"] = particle["life"] + delta
		particle["position"] = particle["position"] + particle["velocity"] * delta
		particle["velocity"] = particle["velocity"] * 0.9
	projectile_particles = projectile_particles.filter(func(particle: Dictionary) -> bool: return particle["life"] < particle["ttl"])

func _update_impact_particles(delta: float) -> void:
	for particle in impact_particles:
		particle["life"] = particle["life"] + delta
		particle["position"] = particle["position"] + particle["velocity"] * delta
		particle["velocity"] = particle["velocity"] * 0.86
	impact_particles = impact_particles.filter(func(particle: Dictionary) -> bool: return particle["life"] < particle["ttl"])

func _player_by_id(player_id: int) -> PlayerDuelState:
	for player in players:
		if player.id == player_id:
			return player
	return null

func _sync_duel_state_if_ready(delta: float) -> void:
	network_sync_timer -= delta
	if network_sync_timer > 0.0:
		return
	_sync_duel_state.rpc(_duel_state())
	network_sync_timer = 1.0 / 20.0

func _duel_state() -> Dictionary:
	return {
		"players": [_player_state(players[0]), _player_state(players[1])],
		"round_active": round_active,
		"round_over": round_over,
		"countdown": countdown,
		"match_message": match_message,
		"message_timer": message_timer,
		"round_time": round_time,
		"sudden_death_started": sudden_death_started,
		"ring_spinner_degrees": ring.spinner_degrees,
		"ring_current_speed": ring.current_speed,
		"ring_spin_direction": ring.spin_direction,
		"ring_pulse_timer": ring.pulse_timer,
		"ring_sudden_death": ring.sudden_death,
		"ring_victory_flash": ring.victory_flash
	}

func _player_state(player: PlayerDuelState) -> Dictionary:
	return {
		"health": player.health,
		"charge": player.charge,
		"score": player.score,
		"last_result": player.last_result,
		"flash_timer": player.flash_timer
	}

func _apply_duel_state(state: Dictionary) -> void:
	var player_states: Variant = state.get("players", [])
	if player_states is Array:
		for i in range(mini(players.size(), player_states.size())):
			var player_state: Variant = player_states[i]
			if player_state is Dictionary:
				var typed_player_state: Dictionary = player_state
				_apply_player_state(players[i], typed_player_state)
	round_active = bool(state.get("round_active", round_active))
	round_over = bool(state.get("round_over", round_over))
	countdown = float(state.get("countdown", countdown))
	match_message = str(state.get("match_message", match_message))
	message_timer = float(state.get("message_timer", message_timer))
	round_time = float(state.get("round_time", round_time))
	sudden_death_started = bool(state.get("sudden_death_started", sudden_death_started))
	ring.spinner_degrees = float(state.get("ring_spinner_degrees", ring.spinner_degrees))
	ring.current_speed = float(state.get("ring_current_speed", ring.current_speed))
	ring.spin_direction = float(state.get("ring_spin_direction", ring.spin_direction))
	ring.pulse_timer = float(state.get("ring_pulse_timer", ring.pulse_timer))
	ring.sudden_death = bool(state.get("ring_sudden_death", ring.sudden_death))
	ring.victory_flash = bool(state.get("ring_victory_flash", ring.victory_flash))

func _apply_player_state(player: PlayerDuelState, state: Dictionary) -> void:
	player.health = float(state.get("health", player.health))
	player.charge = float(state.get("charge", player.charge))
	player.score = int(state.get("score", player.score))
	player.last_result = str(state.get("last_result", player.last_result))
	player.flash_timer = float(state.get("flash_timer", player.flash_timer))

@rpc("authority", "reliable")
func _play_duel_catch_effect(player_id: int, label: String) -> void:
	if NetworkManager.is_hosting():
		return
	var player := _player_by_id(player_id)
	var color: Color = player.color if player else Color.WHITE
	ring.show_feedback(label, color)
	ring.spawn_hit_particles(player_id, label, color)
	audio.play_catch(label)

@rpc("authority", "reliable")
func _play_duel_attack_effect(attacker_id: int, defender_id: int, heavy: bool) -> void:
	if NetworkManager.is_hosting():
		return
	var attacker := _player_by_id(attacker_id)
	var defender := _player_by_id(defender_id)
	if attacker == null or defender == null:
		return
	audio.play_attack(heavy)
	_spawn_projectile_particles(attacker, defender)
	_spawn_damage_particles(defender, heavy, attacker.color)
	_pulse_screen(0.35, 18.0)

@rpc("authority", "reliable")
func _play_duel_win_effect(winner_id: int) -> void:
	if NetworkManager.is_hosting():
		return
	var winner := _player_by_id(winner_id)
	if winner == null:
		return
	ring.start_victory_celebration(winner.color)
	audio.play_win()

@rpc("any_peer", "reliable")
func _submit_duel_catch() -> void:
	if not NetworkManager.is_hosting():
		return
	var player_id: int = NetworkManager.peer_player_id(multiplayer.get_remote_sender_id())
	_resolve_network_catch(player_id)

@rpc("any_peer", "reliable")
func _request_duel_restart() -> void:
	if NetworkManager.is_hosting() and round_over:
		reset_match()

@rpc("authority", "unreliable")
func _sync_duel_state(state: Dictionary) -> void:
	if NetworkManager.is_hosting():
		return
	_apply_duel_state(state)

func _draw() -> void:
	if players.size() < 2:
		return

	var offset := Vector2.ZERO
	if shake_timer > 0.0:
		offset = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))

	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.055, 0.055, 0.062))
	_draw_grid(offset)
	_draw_player_panel(players[0], _player_hud_rect(1))
	_draw_player_panel(players[1], _player_hud_rect(2))
	_draw_score_counter()
	_draw_center_text()
	_draw_controls()
	_draw_round_over_banner()
	_draw_projectile_particles()
	_draw_impact_particles()

func _draw_grid(offset: Vector2) -> void:
	var size := get_viewport_rect().size
	for x in range(0, int(size.x), 40):
		draw_line(Vector2(x, 0) + offset, Vector2(x, size.y) + offset, Color(0.11, 0.11, 0.12, 0.72), 1.0)
	for y in range(0, int(size.y), 40):
		draw_line(Vector2(0, y) + offset, Vector2(size.x, y) + offset, Color(0.11, 0.11, 0.12, 0.72), 1.0)

func _draw_player_panel(player: PlayerDuelState, panel_rect: Rect2) -> void:
	var font := ThemeDB.get_fallback_font()
	var top_left := panel_rect.position
	_draw_bottom_rounded_panel(panel_rect, Color(0.03, 0.055, 0.1, 0.92), Color(player.color.r, player.color.g, player.color.b, 0.88), 12.0, 3.0)

	var title_pos := top_left + Vector2(18, 30)
	draw_string(font, title_pos, player.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, player.color)

	_draw_bar(top_left + Vector2(18, 50), Vector2(306, 20), player.health / PlayerDuelState.MAX_HEALTH, Color(0.25, 1.0, 0.45), "HP", "%d" % int(player.health))
	_draw_bar(top_left + Vector2(18, 82), Vector2(306, 20), player.charge / PlayerDuelState.MAX_CHARGE, Color(1.0, 0.86, 0.18), "CHARGE", "%d / %d" % [int(player.charge), int(PlayerDuelState.MAX_CHARGE)])

	var result_color := Color.WHITE if player.flash_timer <= 0.0 else Color(1.0, 0.24, 0.24)
	draw_string(font, top_left + Vector2(18, 122), player.last_result, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, result_color)

func _draw_bar(bar_position: Vector2, size: Vector2, percent: float, color: Color, label: String, value_text: String) -> void:
	var font := ThemeDB.get_fallback_font()
	var bar_rect := Rect2(bar_position, size)
	var fill_width := size.x * clampf(percent, 0.0, 1.0)
	_draw_rounded_rect_fill(bar_rect, Color(0.0, 0.0, 0.0, 0.42), 6.0)
	if fill_width > 0.0:
		_draw_rounded_rect_fill(Rect2(bar_position, Vector2(fill_width, size.y)), color, minf(6.0, fill_width * 0.5))
	_draw_rounded_rect_outline(bar_rect, Color(1.0, 1.0, 1.0, 0.24), 6.0, 1.0)
	draw_string(font, bar_position + Vector2(8, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.02, 0.025, 0.04))
	var value_width := font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, bar_position + Vector2(size.x - value_width - 8, 16), value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.02, 0.025, 0.04))

func _draw_bottom_rounded_panel(rect: Rect2, fill: Color, border: Color, radius: float, border_width: float) -> void:
	var rect_pos := rect.position
	var rect_size := rect.size
	var clamped_radius := minf(radius, minf(rect_size.x * 0.5, rect_size.y * 0.5))
	var points := PackedVector2Array()
	points.append(rect_pos)
	points.append(rect_pos + Vector2(rect_size.x, 0.0))
	points = _append_arc_points(points, rect_pos + Vector2(rect_size.x - clamped_radius, rect_size.y - clamped_radius), clamped_radius, 0.0, PI * 0.5, 8)
	points.append(rect_pos + Vector2(clamped_radius, rect_size.y))
	points = _append_arc_points(points, rect_pos + Vector2(clamped_radius, rect_size.y - clamped_radius), clamped_radius, PI * 0.5, PI, 8)
	draw_colored_polygon(points, fill)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, border, border_width, true)

func _append_arc_points(points: PackedVector2Array, center: Vector2, radius: float, start_angle: float, end_angle: float, steps: int) -> PackedVector2Array:
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := lerpf(start_angle, end_angle, t)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points

func _draw_rounded_rect_fill(rect: Rect2, color: Color, radius: float) -> void:
	var rect_pos := rect.position
	var rect_size := rect.size
	var clamped_radius := minf(radius, minf(rect_size.x * 0.5, rect_size.y * 0.5))
	draw_rect(Rect2(rect_pos + Vector2(clamped_radius, 0.0), Vector2(rect_size.x - clamped_radius * 2.0, rect_size.y)), color)
	draw_rect(Rect2(rect_pos + Vector2(0.0, clamped_radius), Vector2(rect_size.x, rect_size.y - clamped_radius * 2.0)), color)
	draw_circle(rect_pos + Vector2(clamped_radius, clamped_radius), clamped_radius, color)
	draw_circle(rect_pos + Vector2(rect_size.x - clamped_radius, clamped_radius), clamped_radius, color)
	draw_circle(rect_pos + Vector2(clamped_radius, rect_size.y - clamped_radius), clamped_radius, color)
	draw_circle(rect_pos + Vector2(rect_size.x - clamped_radius, rect_size.y - clamped_radius), clamped_radius, color)

func _draw_rounded_rect_outline(rect: Rect2, color: Color, radius: float, width: float) -> void:
	var rect_pos := rect.position
	var rect_size := rect.size
	var clamped_radius := minf(radius, minf(rect_size.x * 0.5, rect_size.y * 0.5))
	draw_line(rect_pos + Vector2(clamped_radius, 0.0), rect_pos + Vector2(rect_size.x - clamped_radius, 0.0), color, width)
	draw_line(rect_pos + Vector2(rect_size.x, clamped_radius), rect_pos + Vector2(rect_size.x, rect_size.y - clamped_radius), color, width)
	draw_line(rect_pos + Vector2(clamped_radius, rect_size.y), rect_pos + Vector2(rect_size.x - clamped_radius, rect_size.y), color, width)
	draw_line(rect_pos + Vector2(0.0, clamped_radius), rect_pos + Vector2(0.0, rect_size.y - clamped_radius), color, width)
	draw_arc(rect_pos + Vector2(rect_size.x - clamped_radius, clamped_radius), clamped_radius, -PI * 0.5, 0.0, 8, color, width, true)
	draw_arc(rect_pos + Vector2(rect_size.x - clamped_radius, rect_size.y - clamped_radius), clamped_radius, 0.0, PI * 0.5, 8, color, width, true)
	draw_arc(rect_pos + Vector2(clamped_radius, rect_size.y - clamped_radius), clamped_radius, PI * 0.5, PI, 8, color, width, true)
	draw_arc(rect_pos + Vector2(clamped_radius, clamped_radius), clamped_radius, PI, PI * 1.5, 8, color, width, true)

func _draw_score_counter() -> void:
	var font := ThemeDB.get_fallback_font()
	var viewport_size := get_viewport_rect().size
	var score_rect := Rect2(Vector2(viewport_size.x * 0.5 - 82.0, 8.0), Vector2(164.0, 62.0))
	_draw_rounded_rect_fill(score_rect, Color(0.025, 0.027, 0.032, 0.92), 12.0)
	_draw_rounded_rect_outline(score_rect, Color(1.0, 1.0, 1.0, 0.18), 12.0, 1.0)

	var score_text := "%d : %d" % [players[0].score, players[1].score]
	var score_size := 34
	var score_width := font.get_string_size(score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, score_size).x
	draw_string(font, Vector2(viewport_size.x * 0.5 - score_width * 0.5, 52.0), score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, score_size, Color(0.93, 0.96, 1.0))

func _draw_center_text() -> void:
	if round_over:
		return
	if message_timer <= 0.0 and round_active:
		return
	var font := ThemeDB.get_fallback_font()
	var color := Color(0.9, 0.96, 1.0)
	var size := 36
	if not round_active or countdown > 0.0:
		size = 50
	var text_width := font.get_string_size(match_message, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(640 - text_width / 2.0, 104), match_message, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_round_over_banner() -> void:
	if not round_over:
		return
	var font := ThemeDB.get_fallback_font()
	var viewport_size := get_viewport_rect().size
	var banner_rect := Rect2(Vector2(viewport_size.x * 0.5 - 260.0, viewport_size.y - 112.0), Vector2(520, 86))
	_draw_rounded_rect_fill(banner_rect, Color(0.02, 0.03, 0.07, 0.9), 8.0)
	_draw_rounded_rect_outline(banner_rect, Color(1.0, 0.86, 0.18, 0.9), 8.0, 3.0)
	var title_size := 34
	var title_width := font.get_string_size(match_message, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	draw_string(font, Vector2(viewport_size.x * 0.5 - title_width / 2.0, banner_rect.position.y + 38.0), match_message, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(1.0, 0.96, 0.35))
	var prompt := "Press R for rematch"
	var prompt_size := 18
	var prompt_width := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, prompt_size).x
	draw_string(font, Vector2(viewport_size.x * 0.5 - prompt_width / 2.0, banner_rect.position.y + 68.0), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, prompt_size, Color(0.82, 0.9, 1.0))

func _draw_controls() -> void:
	var font := ThemeDB.get_fallback_font()
	var viewport_size := get_viewport_rect().size
	var font_size := 18
	var y := viewport_size.y - 28.0
	if NetworkManager.is_network_match():
		var local_text := "YOU: %s catch" % InputConfig.action_label("p1_catch")
		draw_string(font, Vector2(56.0, y), local_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.82, 0.9, 1.0))
		return
	var p1_text := "P1: %s catch" % InputConfig.action_label("p1_catch")
	var p2_text := "P2: %s catch" % InputConfig.action_label("p2_catch")
	var p2_width := font.get_string_size(p2_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(56.0, y), p1_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.15, 0.65, 1.0))
	draw_string(font, Vector2(viewport_size.x - p2_width - 56.0, y), p2_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.22, 0.55))

func _draw_projectile_particles() -> void:
	for particle in projectile_particles:
		var progress := float(particle["life"]) / float(particle["ttl"])
		var color_value: Variant = particle.get("color", Color.WHITE)
		var position_value: Variant = particle.get("position", Vector2.ZERO)
		if not color_value is Color or not position_value is Vector2:
			continue
		var color: Color = color_value
		var particle_position: Vector2 = position_value
		var particle_radius := float(particle.get("radius", 2.0))
		draw_circle(particle_position, particle_radius * (1.0 - progress), Color(color.r, color.g, color.b, 1.0 - progress))

func _draw_impact_particles() -> void:
	for particle in impact_particles:
		var progress := float(particle["life"]) / float(particle["ttl"])
		var color_value: Variant = particle.get("color", Color.WHITE)
		var position_value: Variant = particle.get("position", Vector2.ZERO)
		if not color_value is Color or not position_value is Vector2:
			continue
		var color: Color = color_value
		var particle_position: Vector2 = position_value
		var particle_radius := float(particle.get("radius", 2.0))
		draw_circle(particle_position, particle_radius * (1.0 - progress), Color(color.r, color.g, color.b, 1.0 - progress))
