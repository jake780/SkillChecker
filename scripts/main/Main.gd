extends Node

const AudioBuses := preload("res://scripts/audio/AudioBusSetup.gd")
const InputConfig := preload("res://scripts/input/InputRouter.gd")
const MAIN_MENU_SCENE := preload("res://scenes/ui/MainMenu.tscn")
const DUEL_ARENA_SCENE := preload("res://scenes/duel/DuelArena.tscn")
const LED_PONG_SCENE := preload("res://scenes/pong/LEDPongArena.tscn")

var current_scene: Node
var context_layer: CanvasLayer
var context_panel: Control
var quick_options: Control

func _ready() -> void:
	AudioBuses.ensure_buses()
	InputConfig.ensure_default_actions()
	NetworkManager.network_game_requested.connect(_start_game)
	_build_context_menu()
	_show_menu()

func _unhandled_input(event: InputEvent) -> void:
	if current_scene != null and current_scene.name != "MainMenu" and event.is_action_pressed("menu_back"):
		_toggle_context_menu()
		get_viewport().set_input_as_handled()

func _show_menu() -> void:
	_hide_context_menu()
	_clear_current_scene()
	var menu := MAIN_MENU_SCENE.instantiate()
	menu.play_pressed.connect(_start_game)
	add_child(menu)
	current_scene = menu

func _start_game(mode_id: String) -> void:
	_hide_context_menu()
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

func _build_context_menu() -> void:
	context_layer = CanvasLayer.new()
	context_layer.layer = 50
	add_child(context_layer)

	context_panel = Control.new()
	context_panel.visible = false
	context_panel.anchor_right = 1.0
	context_panel.anchor_bottom = 1.0
	context_layer.add_child(context_panel)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.58)
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	context_panel.add_child(shade)

	var menu_box := PanelContainer.new()
	menu_box.anchor_left = 0.5
	menu_box.anchor_right = 0.5
	menu_box.anchor_top = 0.5
	menu_box.anchor_bottom = 0.5
	menu_box.offset_left = -210.0
	menu_box.offset_right = 210.0
	menu_box.offset_top = -160.0
	menu_box.offset_bottom = 160.0
	menu_box.add_theme_stylebox_override("panel", _panel_style(Color(0.12, 0.12, 0.135, 0.98)))
	context_panel.add_child(menu_box)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	layout.custom_minimum_size = Vector2(420.0, 320.0)
	menu_box.add_child(layout)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	layout.add_child(title)

	var resume_button := _context_button("RESUME")
	resume_button.pressed.connect(_hide_context_menu)
	layout.add_child(resume_button)

	var options_button := _context_button("OPTIONS")
	options_button.pressed.connect(func() -> void: quick_options.visible = not quick_options.visible)
	layout.add_child(options_button)

	quick_options = VBoxContainer.new()
	quick_options.visible = false
	quick_options.add_theme_constant_override("separation", 8)
	layout.add_child(quick_options)
	quick_options.add_child(_make_context_slider("Master", 0.85, func(value: float) -> void: AudioBuses.set_master_volume(value)))
	quick_options.add_child(_make_context_slider("Music", 0.75, func(value: float) -> void: AudioBuses.set_music_volume(value)))
	quick_options.add_child(_make_context_slider("SFX", 0.9, func(value: float) -> void: AudioBuses.set_sfx_volume(value)))
	quick_options.add_child(_make_context_window_row())

	var quit_button := _context_button("QUIT GAME")
	quit_button.pressed.connect(func() -> void:
		NetworkManager.close_lobby()
		_show_menu()
	)
	layout.add_child(quit_button)

func _toggle_context_menu() -> void:
	if context_panel == null:
		return
	context_panel.visible = not context_panel.visible
	if context_panel.visible and quick_options != null:
		quick_options.visible = false

func _hide_context_menu() -> void:
	if context_panel != null:
		context_panel.visible = false

func _context_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360.0, 48.0)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color(0.02, 0.025, 0.03))
	button.add_theme_color_override("font_hover_color", Color(0.02, 0.025, 0.03))
	button.add_theme_color_override("font_pressed_color", Color(0.02, 0.025, 0.03))
	button.add_theme_stylebox_override("normal", _button_style(Color(0.44, 0.44, 0.47)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.56, 0.56, 0.6)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.32, 0.32, 0.35)))
	return button

func _make_context_slider(label_text: String, default_value: float, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(74.0, 0.0)
	label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
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
	value.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	row.add_child(value)

	slider.value_changed.connect(func(new_value: float) -> void:
		value.text = "%d%%" % int(new_value)
		callback.call(new_value / 100.0)
	)
	return row

func _make_context_window_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = "Window"
	label.custom_minimum_size = Vector2(74.0, 0.0)
	label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	row.add_child(label)

	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_item("Windowed")
	options.add_item("Borderless")
	options.add_item("Fullscreen")
	options.item_selected.connect(_on_context_window_mode_selected)
	row.add_child(options)
	return row

func _on_context_window_mode_selected(index: int) -> void:
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

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.62, 0.62, 0.68)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style

func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.35, 0.35, 0.4)
	style.set_border_width_all(2)
	style.content_margin_left = 24.0
	style.content_margin_top = 24.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 24.0
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style
