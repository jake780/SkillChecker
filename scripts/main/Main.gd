extends Node

const AudioBuses := preload("res://scripts/audio/AudioBusSetup.gd")
const InputConfig := preload("res://scripts/input/InputRouter.gd")
const MAIN_MENU_SCENE := preload("res://scenes/ui/MainMenu.tscn")
const DUEL_ARENA_SCENE := preload("res://scenes/duel/DuelArena.tscn")
const LED_PONG_SCENE := preload("res://scenes/pong/LEDPongArena.tscn")

var current_scene: Node

func _ready() -> void:
	AudioBuses.ensure_buses()
	InputConfig.ensure_default_actions()
	NetworkManager.network_game_requested.connect(_start_game)
	_show_menu()

func _unhandled_input(event: InputEvent) -> void:
	if current_scene != null and current_scene.name != "MainMenu" and event.is_action_pressed("menu_back"):
		_show_menu()
		get_viewport().set_input_as_handled()

func _show_menu() -> void:
	_clear_current_scene()
	var menu := MAIN_MENU_SCENE.instantiate()
	menu.play_pressed.connect(_start_game)
	add_child(menu)
	current_scene = menu

func _start_game(mode_id: String) -> void:
	_clear_current_scene()
	var arena: Node
	if mode_id == "led_pong":
		arena = LED_PONG_SCENE.instantiate()
	else:
		arena = DUEL_ARENA_SCENE.instantiate()
	add_child(arena)
	current_scene = arena

func _clear_current_scene() -> void:
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
