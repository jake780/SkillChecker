class_name AudioBusSetup
extends RefCounted

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

static func ensure_buses() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)

static func set_master_volume(percent: float) -> void:
	_set_bus_volume("Master", percent)

static func set_music_volume(percent: float) -> void:
	ensure_buses()
	_set_bus_volume(MUSIC_BUS, percent)

static func set_sfx_volume(percent: float) -> void:
	ensure_buses()
	_set_bus_volume(SFX_BUS, percent)

static func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus(AudioServer.get_bus_count())
	var index := AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")

static func _set_bus_volume(bus_name: String, percent: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	var clamped := clampf(percent, 0.0, 1.0)
	AudioServer.set_bus_mute(index, clamped <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(clamped, 0.001)))
