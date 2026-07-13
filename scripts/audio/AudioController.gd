class_name AudioController
extends Node

const AudioBuses := preload("res://scripts/audio/AudioBusSetup.gd")
const MIX_RATE := 44100
const SFX_VOLUME := 0.34
const MUSIC_VOLUME := 0.18
const BPM := 132.0

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var music_playback: AudioStreamGeneratorPlayback
var sfx_playback: AudioStreamGeneratorPlayback
var music_time := 0.0
var noise_seed := 0.37
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
		_add_voice_sweep(680.0, 1240.0, 0.15, SFX_VOLUME * 0.9, "pulse", 0.002, 0.10, -0.18)
		_add_voice_sweep(1040.0, 1680.0, 0.1, SFX_VOLUME * 0.34, "sine", 0.0, 0.07, 0.22)
		_add_voice_sweep(3400.0, 2200.0, 0.04, SFX_VOLUME * 0.16, "noise", 0.0, 0.035, 0.0)
	elif label == "GOOD":
		_add_voice_sweep(440.0, 660.0, 0.11, SFX_VOLUME * 0.76, "triangle", 0.004, 0.08, -0.12)
		_add_voice_sweep(740.0, 920.0, 0.07, SFX_VOLUME * 0.22, "sine", 0.0, 0.05, 0.16)
	elif label == "MISS":
		_add_voice_sweep(260.0, 92.0, 0.18, SFX_VOLUME * 0.82, "saw", 0.0, 0.13, 0.0)
		_add_voice_sweep(1800.0, 500.0, 0.08, SFX_VOLUME * 0.22, "noise", 0.0, 0.07, 0.0)
	_prime_sfx_buffer()

func play_attack(heavy: bool) -> void:
	if heavy:
		_add_voice_sweep(112.0, 42.0, 0.36, SFX_VOLUME * 1.28, "saw", 0.0, 0.30, -0.08)
		_add_voice_sweep(420.0, 96.0, 0.22, SFX_VOLUME * 0.72, "pulse", 0.0, 0.16, 0.18)
		_add_voice_sweep(3000.0, 1200.0, 0.13, SFX_VOLUME * 0.2, "noise", 0.0, 0.09, 0.0)
	else:
		_add_voice_sweep(260.0, 620.0, 0.13, SFX_VOLUME * 0.82, "pulse", 0.0, 0.09, -0.15)
		_add_voice_sweep(940.0, 540.0, 0.09, SFX_VOLUME * 0.42, "triangle", 0.0, 0.07, 0.2)
	_prime_sfx_buffer()

func play_no_charge() -> void:
	_add_voice_sweep(220.0, 140.0, 0.12, SFX_VOLUME * 0.45, "triangle", 0.0, 0.10, 0.0)
	_prime_sfx_buffer()

func play_round_start() -> void:
	_add_voice_sweep(330.0, 440.0, 0.11, SFX_VOLUME * 0.5, "triangle", 0.0, 0.08, -0.28)
	_add_voice_sweep(495.0, 660.0, 0.14, SFX_VOLUME * 0.46, "triangle", 0.02, 0.09, 0.0)
	_add_voice_sweep(660.0, 990.0, 0.18, SFX_VOLUME * 0.42, "sine", 0.04, 0.12, 0.28)
	_prime_sfx_buffer()

func play_sudden_death() -> void:
	_add_voice_sweep(58.0, 72.0, 0.56, SFX_VOLUME * 0.92, "saw", 0.0, 0.42, -0.12)
	_add_voice_sweep(330.0, 1180.0, 0.38, SFX_VOLUME * 0.48, "pulse", 0.02, 0.2, 0.18)
	_add_voice_sweep(1100.0, 3200.0, 0.24, SFX_VOLUME * 0.12, "noise", 0.02, 0.16, 0.0)
	_prime_sfx_buffer()

func play_win() -> void:
	_add_voice_sweep(392.0, 784.0, 0.20, SFX_VOLUME * 0.62, "triangle", 0.0, 0.15, -0.25)
	_add_voice_sweep(588.0, 1176.0, 0.26, SFX_VOLUME * 0.58, "triangle", 0.04, 0.18, 0.12)
	_add_voice_sweep(740.0, 1320.0, 0.3, SFX_VOLUME * 0.42, "sine", 0.08, 0.22, 0.3)
	_add_voice_sweep(2600.0, 1600.0, 0.12, SFX_VOLUME * 0.14, "noise", 0.0, 0.09, 0.0)
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
		var beat_time: float = music_time * BPM / 60.0
		var bar_beat: float = fmod(beat_time, 16.0)
		var sixteenth_phase: float = fmod(beat_time * 4.0, 1.0)
		var sixteenth_step := int(floor(beat_time * 4.0)) % 16
		var bass_index := int(floor(bar_beat / 4.0))
		var bass_freq: float = _bass_frequency(bass_index)
		var bass_gate := _gate(sixteenth_phase, 0.62) if _bass_step_is_on(sixteenth_step) else 0.0
		var bass: float = (_osc("pulse", bass_freq, music_time) * 0.72 + _osc("sine", bass_freq * 0.5, music_time) * 0.42) * bass_gate * 0.34

		var arp_index := int(floor(beat_time * 4.0)) % 8
		var arp_freq: float = _arp_frequency(arp_index)
		var arp: float = _osc("triangle", arp_freq, music_time) * _gate(sixteenth_phase, 0.34) * 0.15

		var sparkle_phase: float = fmod(beat_time * 8.0, 1.0)
		var sparkle_index := int(floor(beat_time * 8.0)) % 16
		var sparkle: float = _osc("sine", _sparkle_frequency(sparkle_index), music_time) * _gate(sparkle_phase, 0.14) * 0.024

		var pad: float = (
			_osc("sine", _pad_frequency(0), music_time) +
			_osc("sine", _pad_frequency(1), music_time) * 0.72 +
			_osc("sine", _pad_frequency(2), music_time) * 0.62
		) * 0.035

		var kick := 0.0
		var kick_phase: float = fmod(beat_time, 1.0)
		if kick_phase < 0.16:
			var kick_env := pow(1.0 - kick_phase / 0.16, 2.0)
			kick = sin(TAU * (46.0 + kick_env * 86.0) * music_time) * kick_env * 0.72

		var snare := 0.0
		var snare_phase: float = fmod(beat_time + 1.0, 2.0)
		if snare_phase < 0.11:
			snare = _noise() * (1.0 - snare_phase / 0.11) * 0.17

		var hat := 0.0
		var hat_phase: float = fmod(beat_time * 2.0, 1.0)
		if hat_phase < 0.07:
			hat = _noise() * (1.0 - hat_phase / 0.07) * 0.052

		var duck := 0.66 + 0.34 * clampf(kick_phase / 0.28, 0.0, 1.0)
		var sample := (bass * duck + arp * duck + sparkle + pad * duck + kick + snare + hat) * MUSIC_VOLUME
		sample = clampf(sample, -0.9, 0.9)
		music_playback.push_frame(Vector2(sample, sample))
		music_time += 1.0 / MIX_RATE

func _fill_sfx_buffer() -> void:
	if sfx_playback == null:
		return
	var frames := sfx_playback.get_frames_available()
	for i in range(frames):
		var left_sample := 0.0
		var right_sample := 0.0
		for voice in voices:
			var local_t := float(voice.get("t", 0.0))
			var duration := float(voice.get("duration", 0.0))
			if local_t < duration:
				var progress := local_t / maxf(duration, 0.001)
				var fade_in := maxf(float(voice.get("attack", 0.0)), 0.001)
				var release := maxf(float(voice.get("release", 0.0)), 0.001)
				var fade_out_start := maxf(duration - release, 0.001)
				var amp := 1.0
				if local_t < fade_in:
					amp = local_t / fade_in
				elif local_t > fade_out_start:
					amp = maxf((duration - local_t) / release, 0.0)
				var freq := lerpf(float(voice.get("freq", 440.0)), float(voice.get("end_freq", 440.0)), progress)
				var voice_sample := _osc(str(voice.get("wave", "sine")), freq, local_t) * float(voice.get("volume", 0.0)) * amp
				var pan := clampf(float(voice.get("pan", 0.0)), -1.0, 1.0)
				left_sample += voice_sample * (1.0 - maxf(pan, 0.0))
				right_sample += voice_sample * (1.0 + minf(pan, 0.0))
				voice["t"] = local_t + 1.0 / MIX_RATE
		voices = voices.filter(func(voice: Dictionary) -> bool: return float(voice.get("t", 0.0)) < float(voice.get("duration", 0.0)))
		left_sample = clampf(left_sample, -0.9, 0.9)
		right_sample = clampf(right_sample, -0.9, 0.9)
		sfx_playback.push_frame(Vector2(left_sample, right_sample))

func _add_voice(freq: float, duration: float, volume: float, wave: String, attack: float, release: float, pan: float = 0.0) -> void:
	_add_voice_sweep(freq, freq, duration, volume, wave, attack, release, pan)

func _add_voice_sweep(freq: float, end_freq: float, duration: float, volume: float, wave: String, attack: float, release: float, pan: float = 0.0) -> void:
	voices.append({
		"freq": freq,
		"end_freq": end_freq,
		"duration": duration,
		"volume": volume,
		"wave": wave,
		"attack": attack,
		"release": release,
		"pan": pan,
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
	if wave == "pulse":
		return 1.0 if phase < 0.28 else -1.0
	if wave == "saw":
		return phase * 2.0 - 1.0
	if wave == "triangle":
		return 1.0 - absf(phase * 4.0 - 2.0)
	if wave == "noise":
		return _noise()
	return sin(TAU * phase)

func _noise() -> float:
	var next := sin(noise_seed * 129.898 + 78.233) * 43758.5453
	noise_seed = absf(fmod(next, 1.0))
	return noise_seed * 2.0 - 1.0

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
		3:
			return 880.0
		4:
			return 659.25
		5:
			return 554.37
		6:
			return 493.88
		_:
			return 739.99

func _sparkle_frequency(index: int) -> float:
	match index % 8:
		0:
			return 880.0
		1:
			return 1108.73
		2:
			return 1318.51
		3:
			return 1760.0
		4:
			return 1479.98
		5:
			return 1318.51
		6:
			return 1108.73
		_:
			return 987.77

func _pad_frequency(index: int) -> float:
	match index:
		0:
			return 110.0
		1:
			return 164.81
		_:
			return 220.0

func _bass_step_is_on(step: int) -> bool:
	return step == 0 or step == 3 or step == 6 or step == 8 or step == 10 or step == 13 or step == 15

func _gate(phase: float, width: float) -> float:
	if phase > width:
		return 0.0
	return 1.0 - phase / width
