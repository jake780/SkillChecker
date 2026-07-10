class_name PlayerDuelState
extends RefCounted

signal changed

const MAX_HEALTH := 100.0
const MAX_CHARGE := 100.0

var id := 1
var display_name := "Player"
var catch_action := ""
var color := Color.WHITE
var health := MAX_HEALTH
var charge := 0.0
var score := 0
var last_result := ""
var flash_timer := 0.0

func _init(
	_player_id := 1,
	_player_name := "Player",
	_player_color := Color.WHITE,
	_catch_action := ""
) -> void:
	id = _player_id
	display_name = _player_name
	color = _player_color
	catch_action = _catch_action
	reset_round()

func reset_round() -> void:
	health = MAX_HEALTH
	charge = 0.0
	last_result = "READY"
	flash_timer = 0.0
	changed.emit()

func add_charge(amount: float) -> void:
	charge = clampf(charge + amount, 0.0, MAX_CHARGE)
	changed.emit()

func can_spend(amount: float) -> bool:
	return charge >= amount

func spend_charge(amount: float) -> bool:
	if not can_spend(amount):
		return false
	charge = clampf(charge - amount, 0.0, MAX_CHARGE)
	changed.emit()
	return true

func take_damage(amount: float) -> void:
	health = clampf(health - amount, 0.0, MAX_HEALTH)
	flash_timer = 0.18
	changed.emit()

func set_result(result: String) -> void:
	last_result = result
	changed.emit()

func tick(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer = maxf(flash_timer - delta, 0.0)
