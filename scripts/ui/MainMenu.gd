extends Control

signal play_pressed(mode_id: String)

const AudioBuses := preload("res://scripts/audio/AudioBusSetup.gd")
const InputConfig := preload("res://scripts/input/InputRouter.gd")
const ModeRingPreview := preload("res://scripts/ui/ModeRingPreview.gd")
const ModePongPreview := preload("res://scripts/ui/ModePongPreview.gd")

const MODE_RING_DUEL := "ring_duel"
const MODE_LED_PONG := "led_pong"
const MODE_NAMES := {
	"ring_duel": "LED Ring Duel",
	"led_pong": "LED Pong"
}

var pulse_time := 0.0
var main_view: Control
var options_view: Control
var mode_select_view: Control
var multiplayer_view: Control
var mode_button: Button
var multiplayer_status_label: Label
var lobby_state_label: Label
var lobby_list: VBoxContainer
var player_list: VBoxContainer
var chat_log: VBoxContainer
var chat_input: LineEdit
var host_button: Button
var start_lobby_button: Button
var direct_ip_input: LineEdit
var multiplayer_mode_options: OptionButton
var selected_mode := MODE_RING_DUEL
var waiting_for_action := ""
var keybind_buttons: Dictionary = {}

func _ready() -> void:
	AudioBuses.ensure_buses()
	InputConfig.ensure_default_actions()
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_main_view()
	_build_mode_select_view()
	_build_options_view()
	_build_multiplayer_view()
	NetworkManager.lobby_changed.connect(_refresh_multiplayer_view)
	NetworkManager.lobbies_changed.connect(_refresh_lobby_list)
	NetworkManager.chat_changed.connect(_refresh_chat_log)
	NetworkManager.connection_status_changed.connect(func(_message: String) -> void: _refresh_multiplayer_view())
	_show_main_view()

func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()

func _input(event: InputEvent) -> void:
	if waiting_for_action == "":
		if (options_view.visible or mode_select_view.visible or multiplayer_view.visible) and event.is_action_pressed("menu_back"):
			_show_main_view()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode != KEY_NONE:
			InputConfig.rebind_key(waiting_for_action, key_event.keycode)
			_update_keybind_buttons()
			waiting_for_action = ""
			get_viewport().set_input_as_handled()

func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.055, 0.055, 0.062))
	_draw_logo(Vector2(viewport_size.x * 0.5 - 292.0, 68.0))

func _build_main_view() -> void:
	main_view = Control.new()
	main_view.anchor_right = 1.0
	main_view.anchor_bottom = 1.0
	add_child(main_view)

	var menu := VBoxContainer.new()
	menu.anchor_left = 0.5
	menu.anchor_right = 0.5
	menu.offset_left = -270.0
	menu.offset_right = 270.0
	menu.offset_top = 260.0
	menu.add_theme_constant_override("separation", 14)
	main_view.add_child(menu)

	var play_button := _make_menu_button("PLAY")
	play_button.pressed.connect(func() -> void: play_pressed.emit(selected_mode))
	menu.add_child(play_button)

	mode_button = _make_menu_button("SELECT GAME MODE")
	mode_button.pressed.connect(_show_mode_select_view)
	menu.add_child(mode_button)

	var multiplayer_button := _make_menu_button("MULTIPLAYER")
	multiplayer_button.pressed.connect(_show_multiplayer_view)
	menu.add_child(multiplayer_button)

	var options_button := _make_menu_button("OPTIONS")
	options_button.pressed.connect(_show_options_view)
	menu.add_child(options_button)

	var quit_button := _make_menu_button("QUIT")
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	menu.add_child(quit_button)

func _build_mode_select_view() -> void:
	mode_select_view = Control.new()
	mode_select_view.anchor_right = 1.0
	mode_select_view.anchor_bottom = 1.0
	add_child(mode_select_view)

	var title := _make_heading("Select Game Mode", Vector2(490.0, 214.0))
	title.custom_minimum_size = Vector2(300.0, 44.0)
	mode_select_view.add_child(title)

	mode_select_view.add_child(_make_mode_card(
		MODE_RING_DUEL,
		Vector2(210.0, 286.0),
		ModeRingPreview.new(),
		"LED Ring Duel",
		"Catch the spinning light and auto-blast at full charge."
	))
	mode_select_view.add_child(_make_mode_card(
		MODE_LED_PONG,
		Vector2(670.0, 286.0),
		ModePongPreview.new(),
		"LED Pong",
		"Deflect growing waves of neon LED balls."
	))

	var back_button := _make_menu_button("Back to Menu")
	back_button.anchor_left = 0.5
	back_button.anchor_right = 0.5
	back_button.anchor_top = 1.0
	back_button.anchor_bottom = 1.0
	back_button.offset_left = -270.0
	back_button.offset_right = 270.0
	back_button.offset_top = -82.0
	back_button.offset_bottom = -28.0
	back_button.pressed.connect(_show_main_view)
	mode_select_view.add_child(back_button)

func _build_options_view() -> void:
	options_view = Control.new()
	options_view.anchor_right = 1.0
	options_view.anchor_bottom = 1.0
	add_child(options_view)

	var options_title := _make_heading("Options", Vector2(170.0, 198.0))
	options_view.add_child(options_title)

	var controls_title := _make_heading("Controls", Vector2(930.0, 198.0))
	options_view.add_child(controls_title)

	var audio_column := VBoxContainer.new()
	audio_column.position = Vector2(58.0, 248.0)
	audio_column.custom_minimum_size = Vector2(380.0, 230.0)
	audio_column.add_theme_constant_override("separation", 18)
	options_view.add_child(audio_column)

	audio_column.add_child(_make_slider_row("Master", 0.85, func(value: float) -> void: AudioBuses.set_master_volume(value)))
	audio_column.add_child(_make_slider_row("Music", 0.75, func(value: float) -> void: AudioBuses.set_music_volume(value)))
	audio_column.add_child(_make_slider_row("SFX", 0.9, func(value: float) -> void: AudioBuses.set_sfx_volume(value)))
	audio_column.add_child(_make_window_row())

	var controls_column := VBoxContainer.new()
	controls_column.position = Vector2(850.0, 230.0)
	controls_column.custom_minimum_size = Vector2(380.0, 250.0)
	controls_column.add_theme_constant_override("separation", 4)
	options_view.add_child(controls_column)

	controls_column.add_child(_make_keybind_row("Player 1 Catch", "p1_catch"))
	controls_column.add_child(_make_keybind_row("Player 2 Catch", "p2_catch"))
	controls_column.add_child(_make_keybind_row("P1 Up", "p1_up"))
	controls_column.add_child(_make_keybind_row("P1 Down", "p1_down"))
	controls_column.add_child(_make_keybind_row("P1 Left", "p1_left"))
	controls_column.add_child(_make_keybind_row("P1 Right", "p1_right"))
	controls_column.add_child(_make_keybind_row("P2 Up", "p2_up"))
	controls_column.add_child(_make_keybind_row("P2 Down", "p2_down"))
	controls_column.add_child(_make_keybind_row("P2 Left", "p2_left"))
	controls_column.add_child(_make_keybind_row("P2 Right", "p2_right"))
	controls_column.add_child(_make_keybind_row("Restart Round", "restart_round"))
	controls_column.add_child(_make_keybind_row("Back/Menu", "menu_back"))

	var back_button := _make_menu_button("Back to Menu")
	back_button.anchor_left = 0.5
	back_button.anchor_right = 0.5
	back_button.anchor_top = 1.0
	back_button.anchor_bottom = 1.0
	back_button.offset_left = -270.0
	back_button.offset_right = 270.0
	back_button.offset_top = -82.0
	back_button.offset_bottom = -28.0
	back_button.pressed.connect(_show_main_view)
	options_view.add_child(back_button)

func _build_multiplayer_view() -> void:
	multiplayer_view = Control.new()
	multiplayer_view.anchor_right = 1.0
	multiplayer_view.anchor_bottom = 1.0
	add_child(multiplayer_view)

	var title := _make_heading("Multiplayer", Vector2(490.0, 198.0))
	title.custom_minimum_size = Vector2(300.0, 44.0)
	multiplayer_view.add_child(title)

	var profile_label := _make_option_label("Profile Name")
	profile_label.position = Vector2(76.0, 252.0)
	profile_label.custom_minimum_size = Vector2(160.0, 30.0)
	multiplayer_view.add_child(profile_label)

	var profile_input := LineEdit.new()
	profile_input.text = NetworkManager.profile_name
	profile_input.position = Vector2(236.0, 246.0)
	profile_input.custom_minimum_size = Vector2(300.0, 38.0)
	profile_input.text_submitted.connect(func(new_text: String) -> void: NetworkManager.set_profile_name(new_text))
	profile_input.focus_exited.connect(func() -> void: NetworkManager.set_profile_name(profile_input.text))
	multiplayer_view.add_child(profile_input)

	var mode_label := _make_option_label("Game Mode")
	mode_label.position = Vector2(76.0, 314.0)
	mode_label.custom_minimum_size = Vector2(160.0, 30.0)
	multiplayer_view.add_child(mode_label)

	multiplayer_mode_options = OptionButton.new()
	multiplayer_mode_options.position = Vector2(236.0, 306.0)
	multiplayer_mode_options.custom_minimum_size = Vector2(300.0, 38.0)
	multiplayer_mode_options.add_item(str(MODE_NAMES[MODE_RING_DUEL]))
	multiplayer_mode_options.set_item_metadata(0, MODE_RING_DUEL)
	multiplayer_mode_options.add_item(str(MODE_NAMES[MODE_LED_PONG]))
	multiplayer_mode_options.set_item_metadata(1, MODE_LED_PONG)
	multiplayer_mode_options.item_selected.connect(_on_multiplayer_mode_selected)
	multiplayer_view.add_child(multiplayer_mode_options)

	var ip_label := _make_option_label("Direct IP")
	ip_label.position = Vector2(76.0, 410.0)
	ip_label.custom_minimum_size = Vector2(160.0, 30.0)
	multiplayer_view.add_child(ip_label)

	direct_ip_input = LineEdit.new()
	direct_ip_input.placeholder_text = "Host IP, e.g. 192.168.1.25"
	direct_ip_input.position = Vector2(236.0, 404.0)
	direct_ip_input.custom_minimum_size = Vector2(300.0, 38.0)
	direct_ip_input.text_submitted.connect(func(_text: String) -> void: NetworkManager.join_lobby(direct_ip_input.text))
	multiplayer_view.add_child(direct_ip_input)

	var join_button := _make_menu_button("JOIN DIRECT IP")
	join_button.position = Vector2(76.0, 562.0)
	join_button.custom_minimum_size = Vector2(460.0, 52.0)
	join_button.pressed.connect(func() -> void: NetworkManager.join_lobby(direct_ip_input.text))
	multiplayer_view.add_child(join_button)

	multiplayer_status_label = Label.new()
	multiplayer_status_label.position = Vector2(622.0, 394.0)
	multiplayer_status_label.custom_minimum_size = Vector2(520.0, 30.0)
	multiplayer_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	multiplayer_status_label.add_theme_font_size_override("font_size", 16)
	multiplayer_status_label.add_theme_color_override("font_color", Color(0.78, 0.8, 0.86))
	multiplayer_view.add_child(multiplayer_status_label)

	lobby_state_label = Label.new()
	lobby_state_label.position = Vector2(622.0, 426.0)
	lobby_state_label.custom_minimum_size = Vector2(520.0, 32.0)
	lobby_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_state_label.add_theme_font_size_override("font_size", 18)
	lobby_state_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.28))
	multiplayer_view.add_child(lobby_state_label)

	var lobby_title := _make_heading("Open LAN Lobbies", Vector2(718.0, 244.0))
	lobby_title.custom_minimum_size = Vector2(360.0, 38.0)
	multiplayer_view.add_child(lobby_title)

	lobby_list = VBoxContainer.new()
	lobby_list.position = Vector2(622.0, 292.0)
	lobby_list.custom_minimum_size = Vector2(520.0, 42.0)
	lobby_list.add_theme_constant_override("separation", 8)
	multiplayer_view.add_child(lobby_list)

	var players_title := _make_heading("Players", Vector2(718.0, 334.0))
	players_title.custom_minimum_size = Vector2(360.0, 32.0)
	players_title.add_theme_font_size_override("font_size", 24)
	multiplayer_view.add_child(players_title)

	player_list = VBoxContainer.new()
	player_list.position = Vector2(622.0, 366.0)
	player_list.custom_minimum_size = Vector2(520.0, 48.0)
	player_list.add_theme_constant_override("separation", 6)
	multiplayer_view.add_child(player_list)

	var chat_title := _make_heading("Lobby Chat", Vector2(650.0, 524.0))
	chat_title.custom_minimum_size = Vector2(300.0, 30.0)
	chat_title.add_theme_font_size_override("font_size", 24)
	multiplayer_view.add_child(chat_title)

	chat_log = VBoxContainer.new()
	chat_log.position = Vector2(622.0, 558.0)
	chat_log.custom_minimum_size = Vector2(520.0, 62.0)
	chat_log.add_theme_constant_override("separation", 2)
	multiplayer_view.add_child(chat_log)

	chat_input = LineEdit.new()
	chat_input.position = Vector2(622.0, 624.0)
	chat_input.custom_minimum_size = Vector2(520.0, 34.0)
	chat_input.placeholder_text = "Type lobby chat and press Enter"
	chat_input.text_submitted.connect(func(text: String) -> void:
		NetworkManager.send_chat_message(text)
		chat_input.text = ""
	)
	multiplayer_view.add_child(chat_input)

	start_lobby_button = _make_menu_button("START LOBBY GAME")
	start_lobby_button.position = Vector2(622.0, 666.0)
	start_lobby_button.custom_minimum_size = Vector2(200.0, 48.0)
	start_lobby_button.pressed.connect(func() -> void: NetworkManager.start_game())
	multiplayer_view.add_child(start_lobby_button)

	host_button = _make_menu_button("CREATE LOBBY")
	host_button.position = Vector2(842.0, 666.0)
	host_button.custom_minimum_size = Vector2(214.0, 48.0)
	host_button.add_theme_font_size_override("font_size", 14)
	host_button.pressed.connect(func() -> void: NetworkManager.host_lobby(selected_mode))
	multiplayer_view.add_child(host_button)

	var disconnect_button := _make_menu_button("DISCONNECT")
	disconnect_button.position = Vector2(1076.0, 666.0)
	disconnect_button.custom_minimum_size = Vector2(188.0, 48.0)
	disconnect_button.add_theme_font_size_override("font_size", 18)
	disconnect_button.pressed.connect(func() -> void: NetworkManager.close_lobby())
	multiplayer_view.add_child(disconnect_button)

	var back_button := _make_menu_button("Back to Menu")
	back_button.position = Vector2(76.0, 620.0)
	back_button.custom_minimum_size = Vector2(460.0, 48.0)
	back_button.pressed.connect(_show_main_view)
	multiplayer_view.add_child(back_button)

func _make_heading(text: String, pos: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.custom_minimum_size = Vector2(300.0, 44.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	return label

func _make_menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(540.0, 54.0)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(0.02, 0.025, 0.03))
	button.add_theme_color_override("font_hover_color", Color(0.02, 0.025, 0.03))
	button.add_theme_color_override("font_pressed_color", Color(0.02, 0.025, 0.03))
	button.add_theme_color_override("font_focus_color", Color(0.02, 0.025, 0.03))
	button.add_theme_stylebox_override("normal", _button_style(Color(0.32, 0.32, 0.34)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.42, 0.42, 0.45)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.24, 0.24, 0.26)))
	button.add_theme_stylebox_override("focus", _button_style(Color(0.5, 0.5, 0.54)))
	return button

func _make_mode_card(mode_id: String, card_position: Vector2, preview: Control, title: String, description: String) -> Button:
	var card_button := Button.new()
	card_button.position = card_position
	card_button.custom_minimum_size = Vector2(400.0, 250.0)
	card_button.size = Vector2(400.0, 250.0)
	card_button.text = ""
	card_button.add_theme_stylebox_override("normal", _button_style(Color(0.24, 0.24, 0.27)))
	card_button.add_theme_stylebox_override("hover", _button_style(Color(0.31, 0.31, 0.35)))
	card_button.add_theme_stylebox_override("pressed", _button_style(Color(0.2, 0.2, 0.22)))
	card_button.pressed.connect(func() -> void:
		selected_mode = mode_id
		_show_main_view()
	)

	preview.position = Vector2(110.0, 20.0)
	preview.custom_minimum_size = Vector2(180.0, 130.0)
	preview.size = Vector2(180.0, 130.0)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_button.add_child(preview)

	var mode_title := Label.new()
	mode_title.text = title
	mode_title.position = Vector2(0.0, 154.0)
	mode_title.custom_minimum_size = Vector2(400.0, 34.0)
	mode_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_title.add_theme_font_size_override("font_size", 24)
	mode_title.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	mode_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_button.add_child(mode_title)

	var mode_desc := Label.new()
	mode_desc.text = description
	mode_desc.position = Vector2(36.0, 186.0)
	mode_desc.custom_minimum_size = Vector2(328.0, 54.0)
	mode_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_desc.add_theme_font_size_override("font_size", 14)
	mode_desc.add_theme_color_override("font_color", Color(0.76, 0.78, 0.84))
	mode_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_button.add_child(mode_desc)
	return card_button

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.58, 0.58, 0.62)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style

func _show_main_view() -> void:
	waiting_for_action = ""
	main_view.visible = true
	options_view.visible = false
	mode_select_view.visible = false
	multiplayer_view.visible = false
	if mode_button != null:
		mode_button.text = "SELECT GAME MODE: %s" % MODE_NAMES.get(selected_mode, "Unknown Mode")

func _show_options_view() -> void:
	main_view.visible = false
	options_view.visible = true
	mode_select_view.visible = false
	multiplayer_view.visible = false
	_update_keybind_buttons()

func _show_mode_select_view() -> void:
	main_view.visible = false
	options_view.visible = false
	mode_select_view.visible = true
	multiplayer_view.visible = false

func _show_multiplayer_view() -> void:
	main_view.visible = false
	options_view.visible = false
	mode_select_view.visible = false
	multiplayer_view.visible = true
	if not NetworkManager.is_connected_to_lobby():
		NetworkManager.set_selected_mode(selected_mode)
	_refresh_multiplayer_view()

func _refresh_multiplayer_view() -> void:
	if multiplayer_status_label == null:
		return
	if NetworkManager.is_connected_to_lobby():
		selected_mode = NetworkManager.selected_mode
	_update_multiplayer_mode_option()
	multiplayer_status_label.text = "%s | Mode: %s" % [NetworkManager.status_message, MODE_NAMES.get(NetworkManager.selected_mode, "Unknown Mode")]
	if NetworkManager.is_hosting():
		lobby_state_label.text = "LOBBY CREATED - YOU ARE HOSTING"
		lobby_state_label.add_theme_color_override("font_color", Color(0.25, 1.0, 0.45))
	elif NetworkManager.is_connected_to_lobby():
		lobby_state_label.text = "JOINED LOBBY - WAITING FOR HOST"
		lobby_state_label.add_theme_color_override("font_color", Color(0.35, 0.78, 1.0))
	else:
		lobby_state_label.text = "NO LOBBY - CREATE OR JOIN MANUALLY"
		lobby_state_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.28))
	start_lobby_button.disabled = not NetworkManager.is_hosting()
	host_button.disabled = NetworkManager.is_connected_to_lobby()
	host_button.text = "CREATE LOBBY: %s" % MODE_NAMES.get(selected_mode, "Unknown Mode")
	multiplayer_mode_options.disabled = NetworkManager.is_connected_to_lobby() and not NetworkManager.is_hosting()
	chat_input.editable = NetworkManager.is_connected_to_lobby()
	chat_input.placeholder_text = "Type lobby chat and press Enter" if NetworkManager.is_connected_to_lobby() else "Join or create a lobby to chat"
	_refresh_lobby_list()
	_refresh_player_list()
	_refresh_chat_log()

func _on_multiplayer_mode_selected(index: int) -> void:
	var mode_id := str(multiplayer_mode_options.get_item_metadata(index))
	selected_mode = mode_id
	if not NetworkManager.is_connected_to_lobby() or NetworkManager.is_hosting():
		NetworkManager.set_selected_mode(mode_id)
	_refresh_multiplayer_view()

func _update_multiplayer_mode_option() -> void:
	if multiplayer_mode_options == null:
		return
	for i in range(multiplayer_mode_options.get_item_count()):
		if str(multiplayer_mode_options.get_item_metadata(i)) == selected_mode:
			multiplayer_mode_options.select(i)
			return

func _refresh_lobby_list() -> void:
	if lobby_list == null:
		return
	_clear_container(lobby_list)
	if NetworkManager.discovered_lobbies.is_empty():
		lobby_list.add_child(_make_list_label("No LAN lobbies found yet. Host on one PC, join on another."))
		return
	for i in range(NetworkManager.discovered_lobbies.size()):
		var lobby_index := i
		var lobby: Dictionary = NetworkManager.discovered_lobbies[i]
		var text := "%s  |  %s  |  %s/%s  |  %s" % [
			lobby.get("name", "LAN Lobby"),
			MODE_NAMES.get(lobby.get("mode", "ring_duel"), "Unknown Mode"),
			lobby.get("players", 1),
			lobby.get("max_players", 8),
			lobby.get("address", "")
		]
		var button := _make_small_button(text)
		button.custom_minimum_size = Vector2(520.0, 34.0)
		button.pressed.connect(func() -> void: NetworkManager.join_discovered_lobby(lobby_index))
		lobby_list.add_child(button)

func _refresh_player_list() -> void:
	if player_list == null:
		return
	_clear_container(player_list)
	if NetworkManager.player_profiles.is_empty():
		player_list.add_child(_make_list_label("Not connected to a lobby."))
		return
	for peer_id in NetworkManager.player_profiles:
		var name := str(NetworkManager.player_profiles[peer_id])
		var suffix := " (Host)" if str(peer_id) == "1" else ""
		player_list.add_child(_make_list_label("%s%s" % [name, suffix]))

func _refresh_chat_log() -> void:
	if chat_log == null:
		return
	_clear_container(chat_log)
	if NetworkManager.chat_messages.is_empty():
		chat_log.add_child(_make_list_label("No messages yet. Say hello before the chaos starts."))
		return
	var start_index := maxi(0, NetworkManager.chat_messages.size() - 3)
	for i in range(start_index, NetworkManager.chat_messages.size()):
		var message: Dictionary = NetworkManager.chat_messages[i]
		var sender := str(message.get("sender", "Player"))
		var text := str(message.get("text", ""))
		var line := "%s: %s" % [sender, text]
		chat_log.add_child(_make_list_label(line))

func _clear_container(container: Container) -> void:
	for child in container.get_children():
		child.queue_free()

func _make_list_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(520.0, 26.0)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.86, 0.88, 0.94))
	return label

func _make_slider_row(label_text: String, default_value: float, callback: Callable) -> HBoxContainer:
	callback.call(default_value)

	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(380.0, 30.0)
	row.add_theme_constant_override("separation", 12)

	var label := _make_option_label(label_text)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = default_value * 100.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value := Label.new()
	value.text = "%d%%" % int(slider.value)
	value.custom_minimum_size = Vector2(48.0, 0.0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	row.add_child(value)

	slider.value_changed.connect(func(new_value: float) -> void:
		value.text = "%d%%" % int(new_value)
		callback.call(new_value / 100.0)
	)

	return row

func _make_window_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(380.0, 38.0)
	row.add_theme_constant_override("separation", 12)
	row.add_child(_make_option_label("Window"))

	var window_options := OptionButton.new()
	window_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	window_options.add_item("Windowed")
	window_options.add_item("Borderless")
	window_options.add_item("Fullscreen")
	window_options.item_selected.connect(_on_window_mode_selected)
	row.add_child(window_options)
	return row

func _make_keybind_row(label_text: String, action: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(380.0, 34.0)
	row.add_theme_constant_override("separation", 12)
	row.add_child(_make_option_label(label_text))

	var button := _make_small_button(InputConfig.action_label(action))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		waiting_for_action = action
		button.text = "Press any key..."
		button.grab_focus()
	)
	keybind_buttons[action] = button
	row.add_child(button)
	return row

func _make_option_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(128.0, 0.0)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	return label

func _make_small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(132.0, 28.0)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color(0.02, 0.025, 0.03))
	button.add_theme_color_override("font_hover_color", Color(0.02, 0.025, 0.03))
	button.add_theme_color_override("font_pressed_color", Color(0.02, 0.025, 0.03))
	button.add_theme_color_override("font_focus_color", Color(0.02, 0.025, 0.03))
	button.add_theme_stylebox_override("normal", _button_style(Color(0.24, 0.24, 0.26)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.36, 0.36, 0.39)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.18, 0.18, 0.2)))
	return button

func _update_keybind_buttons() -> void:
	for action in keybind_buttons:
		var button: Button = keybind_buttons[action]
		button.text = InputConfig.action_label(action)

func _draw_logo(origin: Vector2) -> void:
	var font := ThemeDB.get_fallback_font()
	var led_scale := 13.0
	var cursor := origin
	_draw_led_letter("L", cursor, led_scale)
	cursor.x += 72.0
	_draw_led_letter("E", cursor, led_scale)
	cursor.x += 72.0
	_draw_led_letter("D", cursor, led_scale)

	draw_string(font, origin + Vector2(220.0, 82.0), "uel Online", HORIZONTAL_ALIGNMENT_LEFT, -1, 76, Color(0.92, 0.94, 0.98))
	var subtitle := "local duel now - online chaos later"
	var subtitle_width := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(640.0 - subtitle_width / 2.0, 190.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.74, 0.76, 0.82))

func _draw_led_letter(letter: String, origin: Vector2, scale: float) -> void:
	var pattern := _letter_pattern(letter)
	for y in range(pattern.size()):
		var row: String = pattern[y]
		for x in range(row.length()):
			if row.substr(x, 1) == "1":
				var led_position := origin + Vector2(float(x) * scale, float(y) * scale)
				var hue := fmod(float(x) * 0.14 + float(y) * 0.09 + pulse_time * 1.9, 1.0)
				var value := 0.76 + absf(sin(pulse_time * 8.0 + float(x * 7 + y * 3))) * 0.24
				var color := Color.from_hsv(hue, 0.95, value)
				draw_circle(led_position, scale * 0.43, color)
				draw_circle(led_position, scale * 0.68, Color(color.r, color.g, color.b, 0.16))

func _letter_pattern(letter: String) -> Array[String]:
	if letter == "L":
		return ["10000", "10000", "10000", "10000", "10000", "10000", "11111"]
	if letter == "E":
		return ["11111", "10000", "10000", "11110", "10000", "10000", "11111"]
	return ["11110", "10001", "10001", "10001", "10001", "10001", "11110"]

func _on_window_mode_selected(index: int) -> void:
	match index:
		0:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
