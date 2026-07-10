class_name AudioController
extends Node

const AudioBuses := preload("res://scripts/audio/AudioBusSetup.gd")
const MIX_RATE := 44100
const SFX_VOLUME := 0.28
const MUSIC_VOLUME := 0.16

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var music_playback: AudioStreamGeneratorPlayback
var sfx_playback: AudioStreamGeneratorPlayback
var music_time := 0.0
var voices: Array[Dictionary] = []

func _ready() -> void:
	AudioBuses.ensure_buses()
	music_player = _make_generator_player("MusicPlayer", 0.45)
	sfx_player = _make_generator_player("SfxPlayer", 0.035)
	music_player.bus = AudioBuses.MUSIC_BUS
	sfx_player.bus = AudioBuses.SFX_BUS
	music_player.play()
	sfx_player.play()
	music_playback = music_player.get_stream_playback()
	sfx_playback = sfx_player.get_stream_playback()

func _process(_delta: float) -> void:
	_fill_music_buffer()
	_fill_sfx_buffer()

func play_catch(label: String) -> void:
	if label == "PERFECT":
		_add_voice(740.0, 0.13, SFX_VOLUME, "square", 0.012, 0.1)
		_add_voice(1110.0, 0.11, SFX_VOLUME * 0.72, "sine", 0.02, 0.09)
	elif label == "GOOD":
		_add_voice(520.0, 0.1, SFX_VOLUME * 0.8, "sine", 0.01, 0.08)
	elif label == "MISS":
		_add_voice(130.0, 0.16, SFX_VOLUME * 0.9, "saw", 0.0, 0.14)
	_prime_sfx_buffer()

func play_attack(heavy: bool) -> void:
	if heavy:
		_add_voice(88.0, 0.34, SFX_VOLUME * 1.3, "saw", 0.0, 0.28)
		_add_voice(176.0, 0.24, SFX_VOLUME, "square", 0.0, 0.18)
	else:
		_add_voice(220.0, 0.14, SFX_VOLUME, "square", 0.0, 0.12)
		_add_voice(330.0, 0.09, SFX_VOLUME * 0.75, "sine", 0.0, 0.08)
	_prime_sfx_buffer()

func play_no_charge() -> void:
	_add_voice(155.0, 0.12, SFX_VOLUME * 0.65, "sine", 0.0, 0.11)
	_prime_sfx_buffer()

func play_round_start() -> void:
	_add_voice(330.0, 0.12, SFX_VOLUME * 0.75, "sine", 0.01, 0.1)
	_add_voice(660.0, 0.12, SFX_VOLUME * 0.5, "sine", 0.03, 0.09)
	_prime_sfx_buffer()

func play_sudden_death() -> void:
	_add_voice(58.0, 0.5, SFX_VOLUME * 1.1, "saw", 0.0, 0.45)
	_add_voice(880.0, 0.22, SFX_VOLUME * 0.6, "square", 0.02, 0.18)
	_prime_sfx_buffer()

func play_win() -> void:
	_add_voice(392.0, 0.18, SFX_VOLUME * 0.8, "sine", 0.01, 0.16)
	_add_voice(588.0, 0.22, SFX_VOLUME * 0.7, "sine", 0.04, 0.18)
	_add_voice(784.0, 0.28, SFX_VOLUME * 0.65, "sine", 0.08, 0.2)
	_prime_sfx_buffer()

func _make_generator_player(player_name: String, buffer_length: float) -> AudioStreamPlayer:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = buffer_length
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	add_child(player)
	return player

func _fill_music_buffer() -> void:
	if music_playback == null:
		return
	var frames := music_playback.get_frames_available()
	for i in range(frames):
		var beat: float = fmod(music_time * 2.0, 8.0)
		var bass_index := int(floor(beat / 2.0))
		var bass_freq: float = _bass_frequency(bass_index)
		var bass: float = _osc("square", bass_freq, music_time) * _gate(beat, 0.54) * 0.34
		var arp_index := int(floor(fmod(music_time * 8.0, 4.0)))
		var arp_freq: float = _arp_frequency(arp_index)
		var arp: float = _osc("sine", arp_freq, music_time) * _gate(fmod(music_time * 8.0, 1.0), 0.38) * 0.14
		var kick := 0.0
		var beat_phase: float = fmod(music_time * 2.0, 1.0)
		if beat_phase < 0.08:
			kick = sin(TAU * (90.0 - beat_phase * 620.0) * music_time) * (1.0 - beat_phase / 0.08) * 0.62
		var sample := (bass + arp + kick) * MUSIC_VOLUME
		music_playback.push_frame(Vector2(sample, sample))
		music_time += 1.0 / MIX_RATE

func _fill_sfx_buffer() -> void:
	if sfx_playback == null:
		return
	var frames := sfx_playback.get_frames_available()
	for i in range(frames):
		var sample := 0.0
		for voice in voices:
			if voice["t"] < voice["duration"]:
				var local_t: float = voice["t"]
				var fade_in: float = maxf(voice["attack"], 0.001)
				var fade_out_start: float = maxf(voice["duration"] - voice["release"], 0.001)
				var amp := 1.0
				if local_t < fade_in:
					amp = local_t / fade_in
				elif local_t > fade_out_start:
					amp = maxf((voice["duration"] - local_t) / maxf(voice["release"], 0.001), 0.0)
				sample += _osc(voice["wave"], voice["freq"], local_t) * voice["volume"] * amp
				voice["t"] += 1.0 / MIX_RATE
		voices = voices.filter(func(voice: Dictionary) -> bool: return voice["t"] < voice["duration"])
		sample = clampf(sample, -0.9, 0.9)
		sfx_playback.push_frame(Vector2(sample, sample))

func _add_voice(freq: float, duration: float, volume: float, wave: String, attack: float, release: float) -> void:
	voices.append({
		"freq": freq,
		"duration": duration,
		"volume": volume,
		"wave": wave,
		"attack": attack,
		"release": release,
		"t": 0.0
	})

func _prime_sfx_buffer() -> void:
	if sfx_playback == null:
		return
	sfx_playback.clear_buffer()
	_fill_sfx_buffer()

func _osc(wave: String, freq: float, t: float) -> float:
	var phase := fmod(t * freq, 1.0)
	if wave == "square":
		return 1.0 if phase < 0.5 else -1.0
	if wave == "saw":
		return phase * 2.0 - 1.0
	return sin(TAU * phase)

func _bass_frequency(index: int) -> float:
	match index:
		0:
			return 55.0
		1:
			return 55.0
		2:
			return 82.41
		_:
			return 73.42

func _arp_frequency(index: int) -> float:
	match index:
		0:
			return 440.0
		1:
			return 554.37
		2:
			return 659.25
		_:
			return 880.0

func _gate(phase: float, width: float) -> float:
	if phase > width:
		return 0.0
	return 1.0 - phase / width
