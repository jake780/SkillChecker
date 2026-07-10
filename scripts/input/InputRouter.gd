class_name InputRouter
extends Node

const DEFAULT_ACTIONS := {
	"p1_catch": KEY_F,
	"p2_catch": KEY_J,
	"p1_up": KEY_W,
	"p1_down": KEY_S,
	"p1_left": KEY_A,
	"p1_right": KEY_D,
	"p2_up": KEY_I,
	"p2_down": KEY_K,
	"p2_left": KEY_J,
	"p2_right": KEY_L,
	"restart_round": KEY_R,
	"menu_back": KEY_ESCAPE
}

static func ensure_default_actions() -> void:
	for action in DEFAULT_ACTIONS:
		ensure_key_action(action, DEFAULT_ACTIONS[action])

static func ensure_key_action(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	if not InputMap.action_get_events(action).is_empty():
		return

	var key := InputEventKey.new()
	key.keycode = keycode
	InputMap.action_add_event(action, key)

static func rebind_key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	InputMap.action_add_event(action, key)

static func action_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "Unbound"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.keycode != KEY_NONE:
				return OS.get_keycode_string(key_event.keycode)
			if key_event.physical_keycode != KEY_NONE:
				return OS.get_keycode_string(key_event.physical_keycode)
	return "Unbound"
