extends Node2D

const InputConfig := preload("res://scripts/input/InputRouter.gd")

@onready var audio: AudioController = $AudioController

const ROUND_TARGET := 50
const MATCH_TARGET := 3
const PADDLE_WIDTH := 11.0
const PADDLE_HEIGHT := 71.0
const PADDLE_MARGIN := 56.0
const PADDLE_MAX_SPEED := 650.0
const PADDLE_ACCELERATION := 2600.0
const PADDLE_DECELERATION := 2200.0
const BALL_RADIUS := 8.0
const MAX_BALLS := 10
const WALL_TOP := 86.0
const WALL_BOTTOM_MARGIN := 60.0
const WALL_THICKNESS := 12.0
const LEFT_BARRIER_RATIO := 0.34
const RIGHT_BARRIER_RATIO := 0.66
const SPAWN_MIN_ANGLE := 0.24
const SPAWN_MAX_ANGLE := 0.82
const MAX_BALL_SUBSTEPS := 5
const MAX_PARTICLES := 360
const BOUNCE_PARTICLES := 8
const SCORE_PARTICLES := 42
const ROUND_WIN_PARTICLES := 130

var p1_position := Vector2.ZERO
var p2_position := Vector2.ZERO
var p1_previous_position := Vector2.ZERO
var p2_previous_position := Vector2.ZERO
var p1_velocity := Vector2.ZERO
var p2_velocity := Vector2.ZERO
var p1_rounds := 0
var p2_rounds := 0
var p1_leds := 0
var p2_leds := 0
var balls: Array[Dictionary] = []
var impact_particles: Array[Dictionary] = []
var spawn_timer := 0.0
var round_message := "LED PONG"
var message_timer := 1.2
var round_pause_timer := 0.0
var pending_round_message := ""
var match_over := false
var bounce_audio_cooldown := 0.0
var bounce_network_cooldown := 0.0
var local_player_id := 0
var network_input_axes: Dictionary = {
	1: Vector2.ZERO,
	2: Vector2.ZERO
}
var network_send_timer := 0.0
var network_sync_timer := 0.0

func _ready() -> void:
	InputConfig.ensure_default_actions()
	local_player_id = NetworkManager.local_player_id()
	reset_match()

func _process(delta: float) -> void:
	if NetworkManager.is_network_match():
		_process_network(delta)
		return

	if match_over:
		_update_particles(delta)
		queue_redraw()
		return
	if round_pause_timer > 0.0:
		round_pause_timer -= delta
		_update_particles(delta)
		message_timer = maxf(message_timer - delta, 0.0)
		if round_pause_timer <= 0.0:
			_start_round(pending_round_message)
			audio.play_round_start()
		queue_redraw()
		return

	_update_paddles(delta)
	_update_balls(delta)
	bounce_audio_cooldown = maxf(bounce_audio_cooldown - delta, 0.0)
	bounce_network_cooldown = maxf(bounce_network_cooldown - delta, 0.0)
	if match_over:
		_update_particles(delta)
		queue_redraw()
		return
	_update_spawning(delta)
	_update_particles(delta)
	message_timer = maxf(message_timer - delta, 0.0)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if match_over and event.is_action_pressed("restart_round"):
		if NetworkManager.is_network_match():
			if NetworkManager.is_hosting():
				reset_match()
			else:
				_request_pong_restart.rpc_id(1)
		else:
			reset_match()
		get_viewport().set_input_as_handled()

func _process_network(delta: float) -> void:
	if NetworkManager.is_hosting():
		if match_over:
			_update_particles(delta)
			_sync_pong_state_if_ready(delta)
			queue_redraw()
			return
		if round_pause_timer > 0.0:
			round_pause_timer -= delta
			_update_particles(delta)
			message_timer = maxf(message_timer - delta, 0.0)
			if round_pause_timer <= 0.0:
				_start_round(pending_round_message)
				audio.play_round_start()
			_sync_pong_state_if_ready(delta)
			queue_redraw()
			return

		network_input_axes[1] = _local_axis_for_player(1)
		_update_paddles_with_axes(delta, _network_axis_for_player(1), _network_axis_for_player(2))
		_update_balls(delta)
		bounce_audio_cooldown = maxf(bounce_audio_cooldown - delta, 0.0)
		bounce_network_cooldown = maxf(bounce_network_cooldown - delta, 0.0)
		if not match_over:
			_update_spawning(delta)
		_update_particles(delta)
		message_timer = maxf(message_timer - delta, 0.0)
		_sync_pong_state_if_ready(delta)
	else:
		network_send_timer -= delta
		if network_send_timer <= 0.0:
			_submit_pong_axis.rpc_id(1, _local_axis_for_player(local_player_id))
			network_send_timer = 1.0 / 30.0
		_predict_client_visuals(delta)
		_update_particles(delta)
		bounce_network_cooldown = maxf(bounce_network_cooldown - delta, 0.0)
	queue_redraw()

func reset_match() -> void:
	p1_rounds = 0
	p2_rounds = 0
	_start_round("LED PONG")
	match_over = false

func _start_round(message: String) -> void:
	var viewport_size := get_viewport_rect().size
	var paddle_radius := _paddle_bounds_radius()
	p1_position = Vector2(paddle_radius, viewport_size.y * 0.5)
	p2_position = Vector2(viewport_size.x - paddle_radius, viewport_size.y * 0.5)
	p1_previous_position = p1_position
	p2_previous_position = p2_position
	p1_velocity = Vector2.ZERO
	p2_velocity = Vector2.ZERO
	p1_leds = 0
	p2_leds = 0
	balls.clear()
	impact_particles.clear()
	spawn_timer = 0.35
	round_message = message
	message_timer = 1.2
	round_pause_timer = 0.0
	pending_round_message = ""

func _update_paddles(delta: float) -> void:
	_update_paddles_with_axes(delta, _local_axis_for_player(1), _local_axis_for_player(2))

func _local_axis_for_player(player_id: int) -> Vector2:
	var prefix := "p1"
	if not NetworkManager.is_network_match():
		prefix = "p1" if player_id == 1 else "p2"
	return Vector2(
		Input.get_action_strength("%s_right" % prefix) - Input.get_action_strength("%s_left" % prefix),
		Input.get_action_strength("%s_down" % prefix) - Input.get_action_strength("%s_up" % prefix)
	)

func _network_axis_for_player(player_id: int) -> Vector2:
	var axis: Variant = network_input_axes.get(player_id, Vector2.ZERO)
	if axis is Vector2:
		return axis
	return Vector2.ZERO

func _update_paddles_with_axes(delta: float, p1_axis: Vector2, p2_axis: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	p1_previous_position = p1_position
	p2_previous_position = p2_position
	p1_velocity = _paddle_velocity_for_input(p1_velocity, p1_axis, delta)
	p2_velocity = _paddle_velocity_for_input(p2_velocity, p2_axis, delta)

	var paddle_radius := _paddle_bounds_radius()
	var half_paddle_height := PADDLE_HEIGHT * 0.5
	var min_y := WALL_TOP + WALL_THICKNESS * 0.5 + half_paddle_height
	var max_y := viewport_size.y - WALL_BOTTOM_MARGIN - WALL_THICKNESS * 0.5 - half_paddle_height
	var p1_min_x := paddle_radius
	var p1_max_x := _left_barrier_x(viewport_size) - paddle_radius
	var p2_min_x := _right_barrier_x(viewport_size) + paddle_radius
	var p2_max_x := viewport_size.x - paddle_radius

	p1_position = _clamp_paddle_position(p1_position + p1_velocity * delta, p1_min_x, p1_max_x, min_y, max_y)
	p2_position = _clamp_paddle_position(p2_position + p2_velocity * delta, p2_min_x, p2_max_x, min_y, max_y)
	p1_velocity = _stop_blocked_velocity(p1_position, p1_velocity, p1_min_x, p1_max_x, min_y, max_y)
	p2_velocity = _stop_blocked_velocity(p2_position, p2_velocity, p2_min_x, p2_max_x, min_y, max_y)

func _predict_client_visuals(delta: float) -> void:
	_predict_local_paddle(delta)
	_advance_client_balls(delta)

func _predict_local_paddle(delta: float) -> void:
	if local_player_id == 0:
		return
	var viewport_size := get_viewport_rect().size
	var paddle_radius := _paddle_bounds_radius()
	var half_paddle_height := PADDLE_HEIGHT * 0.5
	var min_y := WALL_TOP + WALL_THICKNESS * 0.5 + half_paddle_height
	var max_y := viewport_size.y - WALL_BOTTOM_MARGIN - WALL_THICKNESS * 0.5 - half_paddle_height
	var axis := _local_axis_for_player(local_player_id)
	if local_player_id == 1:
		var p1_min_x := paddle_radius
		var p1_max_x := _left_barrier_x(viewport_size) - paddle_radius
		p1_velocity = _paddle_velocity_for_input(p1_velocity, axis, delta)
		p1_position = _clamp_paddle_position(p1_position + p1_velocity * delta, p1_min_x, p1_max_x, min_y, max_y)
		p1_velocity = _stop_blocked_velocity(p1_position, p1_velocity, p1_min_x, p1_max_x, min_y, max_y)
	else:
		var p2_min_x := _right_barrier_x(viewport_size) + paddle_radius
		var p2_max_x := viewport_size.x - paddle_radius
		p2_velocity = _paddle_velocity_for_input(p2_velocity, axis, delta)
		p2_position = _clamp_paddle_position(p2_position + p2_velocity * delta, p2_min_x, p2_max_x, min_y, max_y)
		p2_velocity = _stop_blocked_velocity(p2_position, p2_velocity, p2_min_x, p2_max_x, min_y, max_y)

func _advance_client_balls(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	for ball in balls:
		var position_value: Variant = ball.get("position", Vector2.ZERO)
		var velocity_value: Variant = ball.get("velocity", Vector2.ZERO)
		if not position_value is Vector2 or not velocity_value is Vector2:
			continue
		var position: Vector2 = position_value
		var velocity: Vector2 = velocity_value
		var radius := float(ball.get("radius", BALL_RADIUS))
		position += velocity * delta
		if position.y - radius <= WALL_TOP:
			position.y = WALL_TOP + radius
			velocity.y = absf(velocity.y)
		elif position.y + radius >= viewport_size.y - WALL_BOTTOM_MARGIN:
			position.y = viewport_size.y - WALL_BOTTOM_MARGIN - radius
			velocity.y = -absf(velocity.y)
		ball["position"] = position
		ball["velocity"] = velocity

func _paddle_velocity_for_input(current_velocity: Vector2, axis: Vector2, delta: float) -> Vector2:
	if axis.length_squared() > 0.01:
		var target_velocity := axis.normalized() * PADDLE_MAX_SPEED
		return current_velocity.move_toward(target_velocity, PADDLE_ACCELERATION * delta)
	return current_velocity.move_toward(Vector2.ZERO, PADDLE_DECELERATION * delta)

func _clamp_paddle_position(position: Vector2, min_x: float, max_x: float, min_y: float, max_y: float) -> Vector2:
	return Vector2(clampf(position.x, min_x, max_x), clampf(position.y, min_y, max_y))

func _stop_blocked_velocity(position: Vector2, velocity: Vector2, min_x: float, max_x: float, min_y: float, max_y: float) -> Vector2:
	var stopped_velocity := velocity
	if (position.x <= min_x and stopped_velocity.x < 0.0) or (position.x >= max_x and stopped_velocity.x > 0.0):
		stopped_velocity.x = 0.0
	if (position.y <= min_y and stopped_velocity.y < 0.0) or (position.y >= max_y and stopped_velocity.y > 0.0):
		stopped_velocity.y = 0.0
	return stopped_velocity

func _paddle_bounds_radius() -> float:
	return PADDLE_WIDTH * 0.5

func _update_spawning(delta: float) -> void:
	spawn_timer -= delta
	var total_leds := p1_leds + p2_leds
	var max_balls := mini(2 + int(total_leds / 8), MAX_BALLS)
	if spawn_timer <= 0.0 and balls.size() < max_balls:
		_spawn_ball()
		var spawn_interval := clampf(1.3 - float(total_leds) * 0.018, 0.26, 1.3)
		spawn_timer = spawn_interval

func _spawn_ball() -> void:
	if balls.size() >= MAX_BALLS:
		return
	var viewport_size := get_viewport_rect().size
	var total_leds := p1_leds + p2_leds
	var round_pressure := p1_rounds + p2_rounds
	var speed := randf_range(245.0, 315.0) + float(total_leds) * 4.2 + float(round_pressure) * 45.0
	var side := -1.0 if randf() < 0.5 else 1.0
	var vertical_side := -1.0 if randf() < 0.5 else 1.0
	var angle := randf_range(SPAWN_MIN_ANGLE, SPAWN_MAX_ANGLE) * vertical_side
	var color := Color.from_hsv(randf(), 0.92, 1.0)
	balls.append({
		"position": viewport_size * 0.5 + Vector2(randf_range(-24.0, 24.0), randf_range(-36.0, 36.0)),
		"velocity": Vector2(cos(angle) * side, sin(angle)).normalized() * speed,
		"color": color,
		"radius": BALL_RADIUS + randf_range(-1.5, 2.5),
		"spin": randf_range(0.0, TAU),
		"p1_hit_cooldown": 0.0,
		"p2_hit_cooldown": 0.0
	})

func _update_balls(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	var p1_rect := _paddle_rect(1)
	var p2_rect := _paddle_rect(2)
	var p1_swept_rect := _swept_paddle_rect(p1_previous_position, p1_position)
	var p2_swept_rect := _swept_paddle_rect(p2_previous_position, p2_position)

	for ball in balls:
		var position_value: Variant = ball.get("position", Vector2.ZERO)
		var velocity_value: Variant = ball.get("velocity", Vector2.ZERO)
		var color_value: Variant = ball.get("color", Color.WHITE)
		if not position_value is Vector2 or not velocity_value is Vector2 or not color_value is Color:
			continue
		var position: Vector2 = position_value
		var velocity: Vector2 = velocity_value
		var radius := float(ball.get("radius", BALL_RADIUS))
		var ball_color: Color = color_value
		ball["p1_hit_cooldown"] = maxf(float(ball.get("p1_hit_cooldown", 0.0)) - delta, 0.0)
		ball["p2_hit_cooldown"] = maxf(float(ball.get("p2_hit_cooldown", 0.0)) - delta, 0.0)
		var step_count := clampi(int(ceil(velocity.length() * delta / maxf(radius * 0.9, 1.0))), 1, MAX_BALL_SUBSTEPS)
		var step_delta := delta / float(step_count)

		for step in range(step_count):
			position += velocity * step_delta

			if position.y - radius <= WALL_TOP:
				position.y = WALL_TOP + radius
				velocity.y = absf(velocity.y)
				_emit_bounce_effect(position, ball_color, "GOOD")
			elif position.y + radius >= viewport_size.y - WALL_BOTTOM_MARGIN:
				position.y = viewport_size.y - WALL_BOTTOM_MARGIN - radius
				velocity.y = -absf(velocity.y)
				_emit_bounce_effect(position, ball_color, "GOOD")

			var p1_hit := _paddle_hit_info(position, radius, p1_rect, p1_swept_rect)
			var p1_normal_value: Variant = p1_hit.get("normal", Vector2.ZERO)
			var p1_normal := Vector2.ZERO
			if p1_normal_value is Vector2:
				p1_normal = p1_normal_value
			if float(ball["p1_hit_cooldown"]) <= 0.0 and bool(p1_hit["hit"]) and _is_moving_into_paddle(velocity, p1_velocity, p1_normal):
				position = position + p1_normal * float(p1_hit["depth"])
				velocity = _paddle_bounce_velocity(velocity, p1_velocity, p1_normal, float(p1_hit["hit_factor"]))
				ball["p1_hit_cooldown"] = 0.09
				ball["p2_hit_cooldown"] = 0.035
				velocity *= 1.035
				_emit_bounce_effect(position, Color(0.15, 0.65, 1.0), "PERFECT")
			else:
				var p2_hit := _paddle_hit_info(position, radius, p2_rect, p2_swept_rect)
				var p2_normal_value: Variant = p2_hit.get("normal", Vector2.ZERO)
				var p2_normal := Vector2.ZERO
				if p2_normal_value is Vector2:
					p2_normal = p2_normal_value
				if float(ball["p2_hit_cooldown"]) <= 0.0 and bool(p2_hit["hit"]) and _is_moving_into_paddle(velocity, p2_velocity, p2_normal):
					position = position + p2_normal * float(p2_hit["depth"])
					velocity = _paddle_bounce_velocity(velocity, p2_velocity, p2_normal, float(p2_hit["hit_factor"]))
					ball["p2_hit_cooldown"] = 0.09
					ball["p1_hit_cooldown"] = 0.035
					velocity *= 1.035
					_emit_bounce_effect(position, Color(1.0, 0.22, 0.55), "PERFECT")

		ball["position"] = position
		ball["velocity"] = velocity

	var round_ended := false
	var scored_balls := balls.filter(func(ball: Dictionary) -> bool:
		var position_value: Variant = ball.get("position", Vector2.ZERO)
		if not position_value is Vector2:
			return false
		var position: Vector2 = position_value
		return position.x < -40.0 or position.x > viewport_size.x + 40.0
	)
	var balls_after_score := balls.filter(func(ball: Dictionary) -> bool:
		var position_value: Variant = ball.get("position", Vector2.ZERO)
		if not position_value is Vector2:
			return false
		var position: Vector2 = position_value
		return position.x >= -40.0 and position.x <= viewport_size.x + 40.0
	)
	for scored_ball in scored_balls:
		balls = balls_after_score
		var scored_position_value: Variant = scored_ball.get("position", Vector2.ZERO)
		if not scored_position_value is Vector2:
			continue
		var scored_position: Vector2 = scored_position_value
		if scored_position.x < 0.0:
			round_ended = _score_led(2, scored_position)
		else:
			round_ended = _score_led(1, scored_position)
		if round_ended:
			return
		_double_balls_to_cap()
		balls_after_score = balls

func _double_balls_to_cap() -> void:
	var spawn_count := mini(balls.size(), MAX_BALLS - balls.size())
	for i in range(spawn_count):
		_spawn_ball()

func _is_moving_into_paddle(ball_velocity: Vector2, paddle_velocity: Vector2, normal: Vector2) -> bool:
	return (ball_velocity - paddle_velocity).dot(normal) < 0.0

func _paddle_bounce_velocity(velocity: Vector2, paddle_velocity: Vector2, normal: Vector2, hit_factor: float) -> Vector2:
	var tangent := Vector2(-normal.y, normal.x)
	var relative_velocity := velocity - paddle_velocity
	var reflected := relative_velocity - normal * 2.0 * relative_velocity.dot(normal)
	var speed := maxf(270.0, reflected.length() + 42.0)
	var shaped_velocity := (reflected.normalized() + tangent * clampf(hit_factor, -1.0, 1.0) * 0.28).normalized() * speed
	return shaped_velocity + paddle_velocity * 0.32

func _play_bounce_audio(label: String) -> void:
	if bounce_audio_cooldown > 0.0:
		return
	bounce_audio_cooldown = 0.035
	audio.play_catch(label)

func _emit_bounce_effect(position: Vector2, color: Color, label: String) -> void:
	_spawn_bounce_particles(position, color)
	_play_bounce_audio(label)
	if NetworkManager.is_network_match() and NetworkManager.is_hosting() and bounce_network_cooldown <= 0.0:
		bounce_network_cooldown = 0.04
		_play_pong_bounce_effect.rpc(position, color, label)

func _sync_pong_state_if_ready(delta: float) -> void:
	network_sync_timer -= delta
	if network_sync_timer > 0.0:
		return
	_sync_pong_state.rpc(_pong_state())
	network_sync_timer = 1.0 / 20.0

func _pong_state() -> Dictionary:
	return {
		"p1_position": p1_position,
		"p2_position": p2_position,
		"p1_velocity": p1_velocity,
		"p2_velocity": p2_velocity,
		"p1_rounds": p1_rounds,
		"p2_rounds": p2_rounds,
		"p1_leds": p1_leds,
		"p2_leds": p2_leds,
		"balls": _packed_balls(),
		"round_message": round_message,
		"message_timer": message_timer,
		"round_pause_timer": round_pause_timer,
		"pending_round_message": pending_round_message,
		"match_over": match_over
	}

func _packed_balls() -> Array:
	var packed_balls: Array = []
	for ball in balls:
		packed_balls.append([
			ball["position"],
			ball["velocity"],
			ball["color"],
			ball["radius"],
			ball["spin"]
		])
	return packed_balls

func _apply_pong_state(state: Dictionary) -> void:
	var new_p1_position: Variant = state.get("p1_position", p1_position)
	var new_p2_position: Variant = state.get("p2_position", p2_position)
	var new_p1_velocity: Variant = state.get("p1_velocity", p1_velocity)
	var new_p2_velocity: Variant = state.get("p2_velocity", p2_velocity)
	if new_p1_position is Vector2:
		p1_position = new_p1_position
	if new_p2_position is Vector2:
		p2_position = new_p2_position
	if new_p1_velocity is Vector2:
		p1_velocity = new_p1_velocity
	if new_p2_velocity is Vector2:
		p2_velocity = new_p2_velocity
	p1_rounds = int(state.get("p1_rounds", p1_rounds))
	p2_rounds = int(state.get("p2_rounds", p2_rounds))
	p1_leds = int(state.get("p1_leds", p1_leds))
	p2_leds = int(state.get("p2_leds", p2_leds))
	var new_balls: Variant = state.get("balls", balls)
	if new_balls is Array:
		_apply_packed_balls(new_balls)
	round_message = str(state.get("round_message", round_message))
	message_timer = float(state.get("message_timer", message_timer))
	round_pause_timer = float(state.get("round_pause_timer", round_pause_timer))
	pending_round_message = str(state.get("pending_round_message", pending_round_message))
	match_over = bool(state.get("match_over", match_over))

func _apply_packed_balls(packed_balls: Array) -> void:
	var updated_balls: Array[Dictionary] = []
	for i in range(packed_balls.size()):
		var packed_ball: Variant = packed_balls[i]
		if not packed_ball is Array:
			continue
		var ball_data: Array = packed_ball as Array
		if ball_data.size() < 5:
			continue
		var position_value: Variant = ball_data[0]
		var velocity_value: Variant = ball_data[1]
		var color_value: Variant = ball_data[2]
		if not position_value is Vector2 or not velocity_value is Vector2 or not color_value is Color:
			continue
		var p1_cooldown := 0.0
		var p2_cooldown := 0.0
		if i < balls.size():
			p1_cooldown = float(balls[i].get("p1_hit_cooldown", 0.0))
			p2_cooldown = float(balls[i].get("p2_hit_cooldown", 0.0))
		updated_balls.append({
			"position": position_value,
			"velocity": velocity_value,
			"color": color_value,
			"radius": float(ball_data[3]),
			"spin": float(ball_data[4]),
			"p1_hit_cooldown": p1_cooldown,
			"p2_hit_cooldown": p2_cooldown
		})
	balls = updated_balls

@rpc("any_peer", "unreliable")
func _submit_pong_axis(axis: Vector2) -> void:
	if not NetworkManager.is_hosting():
		return
	var player_id: int = NetworkManager.peer_player_id(multiplayer.get_remote_sender_id())
	network_input_axes[player_id] = axis

@rpc("any_peer", "reliable")
func _request_pong_restart() -> void:
	if NetworkManager.is_hosting() and match_over:
		reset_match()

@rpc("authority", "unreliable")
func _sync_pong_state(state: Dictionary) -> void:
	if NetworkManager.is_hosting():
		return
	_apply_pong_state(state)

@rpc("authority", "unreliable")
func _play_pong_bounce_effect(position: Vector2, color: Color, label: String) -> void:
	if NetworkManager.is_hosting():
		return
	_spawn_bounce_particles(position, color)
	_play_bounce_audio(label)

func _score_led(player_id: int, position: Vector2) -> bool:
	if player_id == 1:
		p1_leds += 1
		round_message = "P1 LED"
		_emit_score_effect(position, Color(0.15, 0.65, 1.0))
	else:
		p2_leds += 1
		round_message = "P2 LED"
		_emit_score_effect(position, Color(1.0, 0.22, 0.55))
	message_timer = 0.45
	return _check_round_end()

func _emit_score_effect(position: Vector2, color: Color) -> void:
	_spawn_score_particles(position, color)
	if NetworkManager.is_network_match() and NetworkManager.is_hosting():
		_play_pong_score_effect.rpc(position, color)

@rpc("authority", "reliable")
func _play_pong_score_effect(position: Vector2, color: Color) -> void:
	if NetworkManager.is_hosting():
		return
	_spawn_score_particles(position, color)

func _check_round_end() -> bool:
	if p1_leds < ROUND_TARGET and p2_leds < ROUND_TARGET:
		return false

	if p1_leds >= ROUND_TARGET:
		p1_rounds += 1
		round_message = "P1 ROUND"
		_start_round_pause(1)
	else:
		p2_rounds += 1
		round_message = "P2 ROUND"
		_start_round_pause(2)
	message_timer = 2.0

	if p1_rounds >= MATCH_TARGET or p2_rounds >= MATCH_TARGET:
		match_over = true
		round_message = "PLAYER 1 WINS" if p1_rounds > p2_rounds else "PLAYER 2 WINS"
		round_pause_timer = 0.0
		audio.play_win()
	return true

func _start_round_pause(winner_id: int) -> void:
	round_pause_timer = 2.0
	message_timer = 2.0
	pending_round_message = round_message
	balls.clear()
	_emit_round_win_effect(winner_id)
	audio.play_win()

func _emit_round_win_effect(winner_id: int) -> void:
	_spawn_round_win_particles(winner_id)
	if NetworkManager.is_network_match() and NetworkManager.is_hosting():
		_play_pong_round_win_effect.rpc(winner_id)

@rpc("authority", "reliable")
func _play_pong_round_win_effect(winner_id: int) -> void:
	if NetworkManager.is_hosting():
		return
	_spawn_round_win_particles(winner_id)
	audio.play_win()

func _paddle_rect(player_id: int) -> Rect2:
	if player_id == 1:
		return Rect2(p1_position - Vector2(PADDLE_WIDTH, PADDLE_HEIGHT) * 0.5, Vector2(PADDLE_WIDTH, PADDLE_HEIGHT))
	return Rect2(p2_position - Vector2(PADDLE_WIDTH, PADDLE_HEIGHT) * 0.5, Vector2(PADDLE_WIDTH, PADDLE_HEIGHT))

func _swept_paddle_rect(previous_position: Vector2, current_position: Vector2) -> Rect2:
	var previous_rect := Rect2(previous_position - Vector2(PADDLE_WIDTH, PADDLE_HEIGHT) * 0.5, Vector2(PADDLE_WIDTH, PADDLE_HEIGHT))
	var current_rect := Rect2(current_position - Vector2(PADDLE_WIDTH, PADDLE_HEIGHT) * 0.5, Vector2(PADDLE_WIDTH, PADDLE_HEIGHT))
	var min_pos := Vector2(
		minf(previous_rect.position.x, current_rect.position.x),
		minf(previous_rect.position.y, current_rect.position.y)
	)
	var max_pos := Vector2(
		maxf(previous_rect.position.x + previous_rect.size.x, current_rect.position.x + current_rect.size.x),
		maxf(previous_rect.position.y + previous_rect.size.y, current_rect.position.y + current_rect.size.y)
	)
	return Rect2(min_pos, max_pos - min_pos)

func _circle_hits_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(clampf(center.x, rect.position.x, rect.position.x + rect.size.x), clampf(center.y, rect.position.y, rect.position.y + rect.size.y))
	return center.distance_squared_to(closest) <= radius * radius

func _paddle_hit_info(center: Vector2, radius: float, current_rect: Rect2, swept_rect: Rect2) -> Dictionary:
	var current_hit := _circle_rect_hit_info(center, radius, current_rect)
	if bool(current_hit["hit"]):
		return current_hit
	return _circle_rect_hit_info(center, radius, swept_rect)

func _circle_rect_hit_info(center: Vector2, radius: float, rect: Rect2) -> Dictionary:
	var closest := Vector2(clampf(center.x, rect.position.x, rect.position.x + rect.size.x), clampf(center.y, rect.position.y, rect.position.y + rect.size.y))
	var delta := center - closest
	var distance := delta.length()
	if distance > radius:
		return {"hit": false}

	var normal := Vector2.ZERO
	var depth := radius - distance
	if distance > 0.001:
		normal = delta / distance
	else:
		var left_depth := absf(center.x - rect.position.x)
		var right_depth := absf(rect.position.x + rect.size.x - center.x)
		var top_depth := absf(center.y - rect.position.y)
		var bottom_depth := absf(rect.position.y + rect.size.y - center.y)
		var min_depth := minf(minf(left_depth, right_depth), minf(top_depth, bottom_depth))
		if min_depth == left_depth:
			normal = Vector2.LEFT
			depth = radius + left_depth
		elif min_depth == right_depth:
			normal = Vector2.RIGHT
			depth = radius + right_depth
		elif min_depth == top_depth:
			normal = Vector2.UP
			depth = radius + top_depth
		else:
			normal = Vector2.DOWN
			depth = radius + bottom_depth

	var paddle_center_y := rect.position.y + rect.size.y * 0.5
	var hit_factor := clampf((center.y - paddle_center_y) / (rect.size.y * 0.5), -1.0, 1.0)
	return {
		"hit": true,
		"normal": normal,
		"depth": depth,
		"hit_factor": hit_factor
	}

func _spawn_bounce_particles(position: Vector2, color: Color) -> void:
	for i in range(BOUNCE_PARTICLES):
		var angle := randf_range(0.0, TAU)
		impact_particles.append({
			"position": position,
			"velocity": Vector2(cos(angle), sin(angle)) * randf_range(70.0, 240.0),
			"color": color,
			"life": 0.0,
			"ttl": randf_range(0.18, 0.42),
			"radius": randf_range(2.0, 5.0)
		})
	_trim_particles()

func _spawn_score_particles(position: Vector2, color: Color) -> void:
	for i in range(SCORE_PARTICLES):
		var angle := randf_range(0.0, TAU)
		var particle_color := color.lerp(Color.from_hsv(randf(), 0.95, 1.0), 0.35)
		impact_particles.append({
			"position": position,
			"velocity": Vector2(cos(angle), sin(angle)) * randf_range(130.0, 430.0),
			"color": particle_color,
			"life": 0.0,
			"ttl": randf_range(0.35, 0.85),
			"radius": randf_range(3.0, 8.0)
		})
	_trim_particles()

func _spawn_round_win_particles(winner_id: int) -> void:
	var viewport_size := get_viewport_rect().size
	var color := Color(0.15, 0.65, 1.0) if winner_id == 1 else Color(1.0, 0.22, 0.55)
	var origin := Vector2(viewport_size.x * 0.5, viewport_size.y * 0.5)
	for i in range(ROUND_WIN_PARTICLES):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(110.0, 560.0)
		var particle_color := color.lerp(Color.from_hsv(randf(), 0.95, 1.0), randf_range(0.1, 0.55))
		impact_particles.append({
			"position": origin + Vector2(randf_range(-150.0, 150.0), randf_range(-62.0, 62.0)),
			"velocity": Vector2(cos(angle), sin(angle)) * speed,
			"color": particle_color,
			"life": 0.0,
			"ttl": randf_range(0.65, 1.55),
			"radius": randf_range(3.5, 10.0)
		})
	_trim_particles()

func _trim_particles() -> void:
	while impact_particles.size() > MAX_PARTICLES:
		impact_particles.remove_at(0)

func _update_particles(delta: float) -> void:
	for particle in impact_particles:
		particle["life"] = particle["life"] + delta
		particle["position"] = particle["position"] + particle["velocity"] * delta
		particle["velocity"] = particle["velocity"] * 0.88
	impact_particles = impact_particles.filter(func(particle: Dictionary) -> bool: return particle["life"] < particle["ttl"])

func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.055, 0.055, 0.062))
	_draw_grid()
	_draw_walls()
	_draw_lane_barriers()
	_draw_center_line()
	_draw_scoreboard()
	_draw_paddle(p1_position, -PI * 0.5, Color(0.15, 0.65, 1.0))
	_draw_paddle(p2_position, -PI * 0.5, Color(1.0, 0.22, 0.55))
	_draw_balls()
	_draw_particles()
	_draw_controls()
	_draw_message()

func _draw_grid() -> void:
	var viewport_size := get_viewport_rect().size
	for x in range(0, int(viewport_size.x), 40):
		draw_line(Vector2(float(x), 0.0), Vector2(float(x), viewport_size.y), Color(0.11, 0.11, 0.12, 0.72), 1.0)
	for y in range(0, int(viewport_size.y), 40):
		draw_line(Vector2(0.0, float(y)), Vector2(viewport_size.x, float(y)), Color(0.11, 0.11, 0.12, 0.72), 1.0)

func _draw_center_line() -> void:
	var viewport_size := get_viewport_rect().size
	for y in range(96, int(viewport_size.y - 54.0), 24):
		draw_circle(Vector2(viewport_size.x * 0.5, float(y)), 3.0, Color(0.78, 0.84, 1.0, 0.22))

func _draw_lane_barriers() -> void:
	var viewport_size := get_viewport_rect().size
	var top_y := WALL_TOP + WALL_THICKNESS * 0.5 + 16.0
	var bottom_y := viewport_size.y - WALL_BOTTOM_MARGIN - WALL_THICKNESS * 0.5 - 16.0
	var color := Color(0.72, 0.76, 0.82, 0.54)
	for barrier_x in [_left_barrier_x(viewport_size), _right_barrier_x(viewport_size)]:
		for y in range(int(top_y), int(bottom_y), 18):
			draw_circle(Vector2(barrier_x, float(y)), 3.0, color)

func _draw_walls() -> void:
	var viewport_size := get_viewport_rect().size
	var top_rect := Rect2(Vector2(0.0, WALL_TOP - WALL_THICKNESS * 0.5), Vector2(viewport_size.x, WALL_THICKNESS))
	var bottom_rect := Rect2(Vector2(0.0, viewport_size.y - WALL_BOTTOM_MARGIN - WALL_THICKNESS * 0.5), Vector2(viewport_size.x, WALL_THICKNESS))
	var wall_color := Color(0.62, 0.68, 0.78, 0.74)
	var glow_color := Color(0.36, 0.72, 1.0, 0.13)
	draw_rect(Rect2(top_rect.position - Vector2(0.0, 8.0), top_rect.size + Vector2(0.0, 16.0)), glow_color)
	draw_rect(Rect2(bottom_rect.position - Vector2(0.0, 8.0), bottom_rect.size + Vector2(0.0, 16.0)), glow_color)
	draw_rect(top_rect, wall_color)
	draw_rect(bottom_rect, wall_color)
	for x in range(14, int(viewport_size.x), 28):
		draw_circle(Vector2(float(x), WALL_TOP), 3.0, Color(0.88, 0.94, 1.0, 0.65))
		draw_circle(Vector2(float(x), viewport_size.y - WALL_BOTTOM_MARGIN), 3.0, Color(0.88, 0.94, 1.0, 0.65))

func _draw_scoreboard() -> void:
	var font := ThemeDB.get_fallback_font()
	var viewport_size := get_viewport_rect().size
	var rounds := "%d : %d" % [p1_rounds, p2_rounds]
	var rounds_width := font.get_string_size(rounds, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	draw_string(font, Vector2(viewport_size.x * 0.5 - rounds_width * 0.5, 36.0), rounds, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.93, 0.96, 1.0))

	var leds := "%02d / %d LEDs      %02d / %d LEDs" % [p1_leds, ROUND_TARGET, p2_leds, ROUND_TARGET]
	var leds_width := font.get_string_size(leds, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(font, Vector2(viewport_size.x * 0.5 - leds_width * 0.5, 62.0), leds, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.78, 0.8, 0.86))

func _draw_paddle(center: Vector2, angle: float, color: Color) -> void:
	var axis := Vector2(cos(angle), sin(angle))
	var normal := Vector2(-axis.y, axis.x)
	_draw_rotated_paddle_bar(center, axis, normal, PADDLE_WIDTH, PADDLE_HEIGHT, color)

func _draw_rotated_paddle_bar(center: Vector2, axis: Vector2, normal: Vector2, width: float, height: float, color: Color) -> void:
	var half_length := height * 0.5
	var half_width := width * 0.5
	var start := center - axis * half_length
	var end := center + axis * half_length
	var points := PackedVector2Array([
		start - normal * half_width,
		end - normal * half_width,
		end + normal * half_width,
		start + normal * half_width
	])
	draw_colored_polygon(points, color)
	draw_circle(start, half_width, color)
	draw_circle(end, half_width, color)

func _left_barrier_x(viewport_size: Vector2) -> float:
	return viewport_size.x * LEFT_BARRIER_RATIO

func _right_barrier_x(viewport_size: Vector2) -> float:
	return viewport_size.x * RIGHT_BARRIER_RATIO

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

func _draw_balls() -> void:
	for ball in balls:
		var position_value: Variant = ball.get("position", Vector2.ZERO)
		var color_value: Variant = ball.get("color", Color.WHITE)
		if not position_value is Vector2 or not color_value is Color:
			continue
		var position: Vector2 = position_value
		var color: Color = color_value
		var radius := float(ball.get("radius", BALL_RADIUS))
		draw_circle(position, radius, color)
		draw_circle(position, radius * 1.18, Color(color.r, color.g, color.b, 0.08))

func _draw_particles() -> void:
	for particle in impact_particles:
		var progress := float(particle["life"]) / float(particle["ttl"])
		var color_value: Variant = particle.get("color", Color.WHITE)
		var position_value: Variant = particle.get("position", Vector2.ZERO)
		if not color_value is Color or not position_value is Vector2:
			continue
		var color: Color = color_value
		var position: Vector2 = position_value
		var radius := float(particle.get("radius", 2.0))
		draw_circle(position, radius * (1.0 - progress), Color(color.r, color.g, color.b, 1.0 - progress))

func _draw_controls() -> void:
	var font := ThemeDB.get_fallback_font()
	var viewport_size := get_viewport_rect().size
	var y := viewport_size.y - 12.0
	if NetworkManager.is_network_match():
		var local_text := "YOU: %s/%s/%s/%s" % [InputConfig.action_label("p1_up"), InputConfig.action_label("p1_left"), InputConfig.action_label("p1_down"), InputConfig.action_label("p1_right")]
		draw_string(font, Vector2(56.0, y), local_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.82, 0.9, 1.0))
		return
	draw_string(font, Vector2(56.0, y), "P1: %s/%s/%s/%s" % [InputConfig.action_label("p1_up"), InputConfig.action_label("p1_left"), InputConfig.action_label("p1_down"), InputConfig.action_label("p1_right")], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.15, 0.65, 1.0))
	var p2_text := "P2: %s/%s/%s/%s" % [InputConfig.action_label("p2_up"), InputConfig.action_label("p2_left"), InputConfig.action_label("p2_down"), InputConfig.action_label("p2_right")]
	var p2_width := font.get_string_size(p2_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(viewport_size.x - p2_width - 56.0, y), p2_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.22, 0.55))

func _draw_message() -> void:
	if message_timer <= 0.0 and not match_over:
		return
	var font := ThemeDB.get_fallback_font()
	var viewport_size := get_viewport_rect().size
	var size := 42 if match_over or round_pause_timer > 0.0 else 28
	var text_width := font.get_string_size(round_message, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var y := viewport_size.y - 150.0 if match_over else 124.0
	if round_pause_timer > 0.0:
		y = viewport_size.y * 0.5 - 12.0
	draw_string(font, Vector2(viewport_size.x * 0.5 - text_width * 0.5, y), round_message, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1.0, 0.96, 0.35))
	if match_over:
		var prompt := "Press %s for rematch" % InputConfig.action_label("restart_round")
		var prompt_width := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(font, Vector2(viewport_size.x * 0.5 - prompt_width * 0.5, y + 32.0), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.82, 0.9, 1.0))
