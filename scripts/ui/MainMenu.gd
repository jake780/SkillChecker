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
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.035, 0.036, 0.044))
	_draw_animated_background(viewport_size)
	if multiplayer_view != null and multiplayer_view.visible:
		_draw_logo(Vector2(viewport_size.x * 0.5 - 216.0, 44.0), 9.5, 56, false)
	else:
		_draw_logo(Vector2(viewport_size.x * 0.5 - 292.0, 68.0))

func _draw_animated_background(viewport_size: Vector2) -> void:
	for y in range(0, int(viewport_size.y), 48):
		var alpha := 0.055 + 0.025 * sin(pulse_time * 1.7 + float(y) * 0.035)
		draw_line(Vector2(0.0, float(y)), Vector2(viewport_size.x, float(y)), Color(0.18, 0.22, 0.3, alpha), 1.0)

	for x in range(-160, int(viewport_size.x) + 160, 96):
		var drift := fmod(pulse_time * 34.0 + float(x) * 0.37, 96.0)
		var line_x := float(x) + drift
		draw_line(Vector2(line_x, 0.0), Vector2(line_x - 180.0, viewport_size.y), Color(0.12, 0.68, 1.0, 0.055), 1.0)

	for i in range(54):
		var seed := float(i)
		var x := fmod(seed * 173.0 + pulse_time * (18.0 + fmod(seed, 5.0) * 4.0), viewport_size.x + 160.0) - 80.0
		var y := 116.0 + fmod(seed * 91.0 + sin(pulse_time * 0.7 + seed) * 42.0, maxf(viewport_size.y - 120.0, 1.0))
		var hue := fmod(seed * 0.067 + pulse_time * 0.08, 1.0)
		var pulse := 0.55 + absf(sin(pulse_time * 4.0 + seed)) * 0.45
		var color := Color.from_hsv(hue, 0.9, 1.0, 0.12 + pulse * 0.1)
		draw_circle(Vector2(x, y), 1.8 + pulse * 2.4, color)
		draw_circle(Vector2(x, y), 6.0 + pulse * 5.0, Color(color.r, color.g, color.b, 0.035))

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

	var options_title := _make_heading("Options", Vector2(164.0, 206.0))
	options_view.add_child(options_title)

	var controls_title := _make_heading("Controls", Vector2(914.0, 206.0))
	options_view.add_child(controls_title)

	var audio_column := VBoxContainer.new()
	audio_column.position = Vector2(72.0, 260.0)
	audio_column.custom_minimum_size = Vector2(380.0, 230.0)
	audio_column.add_theme_constant_override("separation", 18)
	options_view.add_child(audio_column)

	audio_column.add_child(_make_slider_row("Master", 0.85, func(value: float) -> void: AudioBuses.set_master_volume(value)))
	audio_column.add_child(_make_slider_row("Music", 0.75, func(value: float) -> void: AudioBuses.set_music_volume(value)))
	audio_column.add_child(_make_slider_row("SFX", 0.9, func(value: float) -> void: AudioBuses.set_sfx_volume(value)))
	audio_column.add_child(_make_window_row())

	var controls_scroll := ScrollContainer.new()
	controls_scroll.position = Vector2(808.0, 250.0)
	controls_scroll.custom_minimum_size = Vector2(430.0, 356.0)
	controls_scroll.size = Vector2(430.0, 356.0)
	controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options_view.add_child(controls_scroll)

	var controls_column := VBoxContainer.new()
	controls_column.custom_minimum_size = Vector2(400.0, 0.0)
	controls_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_column.add_theme_constant_override("separation", 7)
	controls_scroll.add_child(controls_column)

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
	back_button.offset_top = -76.0
	back_button.offset_bottom = -24.0
	back_button.pressed.connect(_show_main_view)
	options_view.add_child(back_button)

func _build_multiplayer_view() -> void:
	multiplayer_view = Control.new()
	multiplayer_view.anchor_right = 1.0
	multiplayer_view.anchor_bottom = 1.0
	add_child(multiplayer_view)

	var title := _make_heading("Multiplayer", Vector2(490.0, 150.0))
	title.custom_minimum_size = Vector2(300.0, 44.0)
	multiplayer_view.add_child(title)

	var connect_panel := _make_menu_panel(Vector2(56.0, 212.0), Vector2(520.0, 292.0))
	multiplayer_view.add_child(connect_panel)

	var connect_title := _make_panel_title("Create or Join", Vector2(0.0, 16.0), 520.0)
	connect_panel.add_child(connect_title)

	var profile_label := _make_option_label("Profile Name")
	profile_label.position = Vector2(28.0, 72.0)
	profile_label.custom_minimum_size = Vector2(148.0, 30.0)
	connect_panel.add_child(profile_label)

	var profile_input := LineEdit.new()
	profile_input.text = NetworkManager.profile_name
	profile_input.position = Vector2(176.0, 66.0)
	profile_input.custom_minimum_size = Vector2(304.0, 38.0)
	profile_input.size = Vector2(304.0, 38.0)
	profile_input.text_submitted.connect(func(new_text: String) -> void: NetworkManager.set_profile_name(new_text))
	profile_input.focus_exited.connect(func() -> void: NetworkManager.set_profile_name(profile_input.text))
	connect_panel.add_child(profile_input)

	var mode_label := _make_option_label("Game Mode")
	mode_label.position = Vector2(28.0, 128.0)
	mode_label.custom_minimum_size = Vector2(148.0, 30.0)
	connect_panel.add_child(mode_label)

	multiplayer_mode_options = OptionButton.new()
	multiplayer_mode_options.position = Vector2(176.0, 122.0)
	multiplayer_mode_options.custom_minimum_size = Vector2(304.0, 38.0)
	multiplayer_mode_options.size = Vector2(304.0, 38.0)
	multiplayer_mode_options.add_item(str(MODE_NAMES[MODE_RING_DUEL]))
	multiplayer_mode_options.set_item_metadata(0, MODE_RING_DUEL)
	multiplayer_mode_options.add_item(str(MODE_NAMES[MODE_LED_PONG]))
	multiplayer_mode_options.set_item_metadata(1, MODE_LED_PONG)
	multiplayer_mode_options.item_selected.connect(_on_multiplayer_mode_selected)
	connect_panel.add_child(multiplayer_mode_options)

	var ip_label := _make_option_label("Direct IP")
	ip_label.position = Vector2(28.0, 188.0)
	ip_label.custom_minimum_size = Vector2(148.0, 30.0)
	connect_panel.add_child(ip_label)

	direct_ip_input = LineEdit.new()
	direct_ip_input.placeholder_text = "Host IP, e.g. 192.168.1.25"
	direct_ip_input.position = Vector2(176.0, 182.0)
	direct_ip_input.custom_minimum_size = Vector2(304.0, 38.0)
	direct_ip_input.size = Vector2(304.0, 38.0)
	direct_ip_input.text_submitted.connect(func(_text: String) -> void: NetworkManager.join_lobby(direct_ip_input.text))
	connect_panel.add_child(direct_ip_input)

	var join_button := _make_lobby_button("JOIN DIRECT IP", Vector2(304.0, 46.0))
	join_button.position = Vector2(176.0, 232.0)
	join_button.pressed.connect(func() -> void: NetworkManager.join_lobby(direct_ip_input.text))
	connect_panel.add_child(join_button)

	start_lobby_button = _make_lobby_button("START GAME", Vector2(250.0, 48.0))
	start_lobby_button.position = Vector2(56.0, 522.0)
	start_lobby_button.pressed.connect(func() -> void: NetworkManager.start_game())
	multiplayer_view.add_child(start_lobby_button)

	host_button = _make_lobby_button("CREATE LOBBY", Vector2(250.0, 48.0))
	host_button.position = Vector2(326.0, 522.0)
	host_button.pressed.connect(func() -> void: NetworkManager.host_lobby(selected_mode))
	multiplayer_view.add_child(host_button)

	var back_button := _make_lobby_button("BACK", Vector2(250.0, 48.0))
	back_button.position = Vector2(56.0, 582.0)
	back_button.pressed.connect(_show_main_view)
	multiplayer_view.add_child(back_button)

	var disconnect_button := _make_lobby_button("DISCONNECT", Vector2(250.0, 48.0))
	disconnect_button.position = Vector2(326.0, 582.0)
	disconnect_button.pressed.connect(func() -> void: NetworkManager.close_lobby())
	multiplayer_view.add_child(disconnect_button)

	var lobby_panel := _make_menu_panel(Vector2(604.0, 212.0), Vector2(620.0, 178.0))
	multiplayer_view.add_child(lobby_panel)

	var lobby_title := _make_panel_title("Open LAN Lobbies", Vector2(0.0, 14.0), 620.0)
	lobby_panel.add_child(lobby_title)

	var lobby_scroll := ScrollContainer.new()
	lobby_scroll.position = Vector2(28.0, 58.0)
	lobby_scroll.custom_minimum_size = Vector2(564.0, 96.0)
	lobby_scroll.size = Vector2(564.0, 96.0)
	lobby_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lobby_panel.add_child(lobby_scroll)

	lobby_list = VBoxContainer.new()
	lobby_list.custom_minimum_size = Vector2(544.0, 0.0)
	lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_list.add_theme_constant_override("separation", 8)
	lobby_scroll.add_child(lobby_list)

	var room_panel := _make_menu_panel(Vector2(604.0, 404.0), Vector2(620.0, 112.0))
	multiplayer_view.add_child(room_panel)

	var players_title := _make_panel_title("Players", Vector2(0.0, 12.0), 280.0)
	room_panel.add_child(players_title)

	var player_scroll := ScrollContainer.new()
	player_scroll.position = Vector2(28.0, 48.0)
	player_scroll.custom_minimum_size = Vector2(252.0, 48.0)
	player_scroll.size = Vector2(252.0, 48.0)
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	room_panel.add_child(player_scroll)

	player_list = VBoxContainer.new()
	player_list.custom_minimum_size = Vector2(232.0, 0.0)
	player_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_list.add_theme_constant_override("separation", 4)
	player_scroll.add_child(player_list)

	multiplayer_status_label = Label.new()
	multiplayer_status_label.position = Vector2(308.0, 44.0)
	multiplayer_status_label.custom_minimum_size = Vector2(284.0, 28.0)
	multiplayer_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	multiplayer_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	multiplayer_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	multiplayer_status_label.add_theme_font_size_override("font_size", 16)
	multiplayer_status_label.add_theme_color_override("font_color", Color(0.78, 0.8, 0.86))
	room_panel.add_child(multiplayer_status_label)

	lobby_state_label = Label.new()
	lobby_state_label.position = Vector2(308.0, 74.0)
	lobby_state_label.custom_minimum_size = Vector2(284.0, 24.0)
	lobby_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lobby_state_label.add_theme_font_size_override("font_size", 18)
	lobby_state_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.28))
	room_panel.add_child(lobby_state_label)

	var chat_panel := _make_menu_panel(Vector2(604.0, 530.0), Vector2(620.0, 146.0))
	multiplayer_view.add_child(chat_panel)

	var chat_title := _make_panel_title("Lobby Chat", Vector2(0.0, 10.0), 620.0)
	chat_panel.add_child(chat_title)

	var chat_scroll := ScrollContainer.new()
	chat_scroll.position = Vector2(28.0, 42.0)
	chat_scroll.custom_minimum_size = Vector2(564.0, 58.0)
	chat_scroll.size = Vector2(564.0, 58.0)
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_panel.add_child(chat_scroll)

	chat_log = VBoxContainer.new()
	chat_log.custom_minimum_size = Vector2(544.0, 0.0)
	chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_log.add_theme_constant_override("separation", 2)
	chat_scroll.add_child(chat_log)

	chat_input = LineEdit.new()
	chat_input.position = Vector2(28.0, 106.0)
	chat_input.custom_minimum_size = Vector2(564.0, 32.0)
	chat_input.size = Vector2(564.0, 32.0)
	chat_input.placeholder_text = "Type lobby chat and press Enter"
	chat_input.text_submitted.connect(func(text: String) -> void:
		NetworkManager.send_chat_message(text)
		chat_input.text = ""
	)
	chat_panel.add_child(chat_input)

func _make_heading(text: String, pos: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.custom_minimum_size = Vector2(300.0, 44.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	return label

func _make_panel_title(text: String, pos: Vector2, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.custom_minimum_size = Vector2(width, 34.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	return label

func _make_menu_panel(pos: Vector2, panel_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.custom_minimum_size = panel_size
	panel.size = panel_size
	panel.add_theme_stylebox_override("panel", _panel_style())
	return panel

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.077, 0.088, 0.96)
	style.border_color = Color(0.2, 0.75, 1.0, 0.34)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.36)
	style.shadow_size = 10
	return style

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
	var mode_name := str(MODE_NAMES.get(NetworkManager.selected_mode, "Unknown Mode"))
	if NetworkManager.is_hosting():
		multiplayer_status_label.text = "Hosting | %s" % mode_name
		lobby_state_label.text = "HOST"
		lobby_state_label.add_theme_color_override("font_color", Color(0.25, 1.0, 0.45))
	elif NetworkManager.is_connected_to_lobby():
		multiplayer_status_label.text = "Connected | %s" % mode_name
		lobby_state_label.text = "JOINED"
		lobby_state_label.add_theme_color_override("font_color", Color(0.35, 0.78, 1.0))
	else:
		multiplayer_status_label.text = "Offline | %s" % mode_name
		lobby_state_label.text = "NO LOBBY"
		lobby_state_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.28))
	start_lobby_button.disabled = not NetworkManager.is_hosting()
	host_button.disabled = NetworkManager.is_connected_to_lobby()
	host_button.text = "CREATE LOBBY"
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
		lobby_list.add_child(_make_list_label("No LAN lobbies found. Create one or join by IP.", 544.0))
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
		button.custom_minimum_size = Vector2(544.0, 34.0)
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(func() -> void: NetworkManager.join_discovered_lobby(lobby_index))
		lobby_list.add_child(button)

func _refresh_player_list() -> void:
	if player_list == null:
		return
	_clear_container(player_list)
	if NetworkManager.player_profiles.is_empty():
		player_list.add_child(_make_list_label("Not in a lobby.", 232.0))
		return
	for peer_id in NetworkManager.player_profiles:
		var name := str(NetworkManager.player_profiles[peer_id])
		var suffix := " (Host)" if str(peer_id) == "1" else ""
		player_list.add_child(_make_list_label("%s%s" % [name, suffix], 232.0))

func _refresh_chat_log() -> void:
	if chat_log == null:
		return
	_clear_container(chat_log)
	if NetworkManager.chat_messages.is_empty():
		chat_log.add_child(_make_list_label("No messages yet.", 544.0))
		return
	var start_index := maxi(0, NetworkManager.chat_messages.size() - 3)
	for i in range(start_index, NetworkManager.chat_messages.size()):
		var message: Dictionary = NetworkManager.chat_messages[i]
		var sender := str(message.get("sender", "Player"))
		var text := str(message.get("text", ""))
		var line := "%s: %s" % [sender, text]
		chat_log.add_child(_make_list_label(line, 544.0))

func _clear_container(container: Container) -> void:
	for child in container.get_children():
		child.queue_free()

func _make_list_label(text: String, width: float = 544.0) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 22.0)
	label.clip_text = true
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

func _make_lobby_button(text: String, button_size: Vector2) -> Button:
	var button := _make_small_button(text)
	button.custom_minimum_size = button_size
	button.size = button_size
	button.add_theme_font_size_override("font_size", 18)
	return button

func _update_keybind_buttons() -> void:
	for action in keybind_buttons:
		var button: Button = keybind_buttons[action]
		button.text = InputConfig.action_label(action)

func _draw_logo(origin: Vector2, led_scale: float = 13.0, title_size: int = 76, show_subtitle: bool = true) -> void:
	var font := ThemeDB.get_fallback_font()
	var cursor := origin
	_draw_led_letter("L", cursor, led_scale)
	cursor.x += led_scale * 5.54
	_draw_led_letter("E", cursor, led_scale)
	cursor.x += led_scale * 5.54
	_draw_led_letter("D", cursor, led_scale)

	draw_string(font, origin + Vector2(led_scale * 16.92, led_scale * 6.31), "uel Online", HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0.92, 0.94, 0.98))
	if not show_subtitle:
		return
	var subtitle := "local duel now - online chaos later"
	var subtitle_width := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var viewport_size := get_viewport_rect().size
	draw_string(font, Vector2(viewport_size.x * 0.5 - subtitle_width * 0.5, origin.y + led_scale * 9.38), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.74, 0.76, 0.82))

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
