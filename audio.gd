extends Node

const SAMPLE_RATE := 22050
const POOL_SIZE := 12

var muted := false
var headless := false
var streams: Dictionary = {}
var pool: Array = []
var pool_index := 0
var last_played: Dictionary = {}
var pulse_player: AudioStreamPlayer
var vent_player: AudioStreamPlayer
var duck_until := 0
var pulse_gain := -54.0
var ambient_player: AudioStreamPlayer

func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	if headless:
		return
	for _index in range(POOL_SIZE):
		var player := AudioStreamPlayer2D.new()
		player.max_distance = 1100.0
		player.attenuation = 1.4
		player.panning_strength = 1.0
		player.volume_db = -8.0
		add_child(player)
		pool.append(player)
	build_library()
	ambient_player = AudioStreamPlayer.new()
	ambient_player.stream = streams.get("ambient")
	ambient_player.volume_db = -24.0
	add_child(ambient_player)
	if not muted and ambient_player.stream != null:
		ambient_player.play()
	pulse_player = add_layer(synth_layer(false))
	vent_player = add_layer(synth_layer(true))

func add_layer(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var layer := AudioStreamPlayer.new()
	layer.stream = stream
	layer.volume_db = -55.0
	add_child(layer)
	return layer

static func synth_layer(venting: bool) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(SAMPLE_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11729
	var previous := 0.0
	for i in range(samples.size()):
		var t := float(i) / SAMPLE_RATE
		if venting:
			var noise := rng.randf_range(-1.0,1.0)
			samples[i] = (noise-previous)*0.16
			previous = noise
		else:
			samples[i] = sin(TAU*56*t)*exp(-6.5*fmod(t+0.02,0.5))*0.28
	return pack_pcm(samples,true)

func mix_flight(locked: bool, threat: float, venting: bool, delta: float) -> void:
	if headless or muted or pulse_player == null:
		return
	pulse_gain = move_toward(pulse_gain, lerpf(-31.0,-13.0,clampf(threat,0,1)) if locked else -55.0, delta*24)
	pulse_player.volume_db = pulse_gain
	if pulse_gain > -54.5 and not pulse_player.playing:
		pulse_player.play()
	elif pulse_gain <= -54.5 and pulse_player.playing:
		pulse_player.stop()
	if venting and not vent_player.playing:
		vent_player.volume_db = -15.0
		vent_player.play()
	elif not venting and vent_player.playing:
		vent_player.stop()
	ambient_player.volume_db = -38.0 if Time.get_ticks_msec() < duck_until else -24.0

func build_library() -> void:
	streams["muzzle"] = synth_tone(0.11, 760.0, 220.0, 0.28, 0.08, "saw")
	streams["missile"] = synth_tone(0.24, 240.0, 95.0, 0.32, 0.38, "noise")
	streams["shield"] = synth_tone(0.18, 620.0, 880.0, 0.24, 0.05, "sine")
	streams["impact"] = synth_tone(0.16, 175.0, 58.0, 0.34, 0.45, "noise")
	streams["overload"] = synth_alarm(0.45, 520.0, 340.0, 0.30)
	streams["system"] = synth_tone(0.32, 260.0, 740.0, 0.26, 0.12, "sine")
	streams["intercept"] = synth_tone(0.07, 1320.0, 880.0, 0.20, 0.04, "square")
	streams["rupture"] = synth_tone(0.55, 130.0, 32.0, 0.44, 0.65, "noise")
	streams["trade"] = synth_chime(0.24, 660.0, 990.0, 0.24)
	streams["dock"] = synth_tone(0.36, 150.0, 72.0, 0.30, 0.22, "saw")
	streams["mine"] = synth_tone(0.22, 310.0, 270.0, 0.22, 0.16, "saw")
	streams["ping"] = synth_tone(0.40, 980.0, 620.0, 0.22, 0.02, "sine")
	streams["emp"] = synth_tone(0.16,1270,165,0.25,0.22,"square")
	streams["beam"] = synth_tone(0.22,820,450,0.22,0.09,"sine")
	streams["breach"] = synth_tone(0.21,91,36,0.42,0.32,"noise")
	streams["click"] = synth_tone(0.04, 640.0, 420.0, 0.14, 0.02, "sine")
	streams["ambient"] = synth_ambient(4.0)

static func pack_pcm(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for index in range(samples.size()):
		var value := clampi(roundi(samples[index] * 32767.0), -32768, 32767)
		data[index * 2] = value & 0xFF
		data[index * 2 + 1] = (value >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream

static func synth_tone(duration: float, start_hz: float, end_hz: float, gain: float, noise_mix: float, wave: String) -> AudioStreamWAV:
	var total := maxi(1, int(SAMPLE_RATE * duration))
	var samples := PackedFloat32Array()
	samples.resize(total)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%f:%f" % [wave, start_hz, end_hz])
	for index in range(total):
		var progress := float(index) / float(total)
		var freq := lerpf(start_hz, end_hz, progress)
		phase += TAU * freq / float(SAMPLE_RATE)
		var osc := sin(phase)
		if wave == "saw":
			osc = fmod(phase / PI, 2.0) - 1.0
		elif wave == "square":
			osc = 1.0 if sin(phase) >= 0.0 else -1.0
		var noise := rng.randf_range(-1.0, 1.0)
		var attack := minf(1.0, progress * 24.0)
		var decay := pow(1.0 - progress, 1.55)
		samples[index] = lerpf(osc, noise, noise_mix) * gain * attack * decay
	return pack_pcm(samples)

static func synth_chime(duration: float, first_hz: float, second_hz: float, gain: float) -> AudioStreamWAV:
	var total := maxi(1, int(SAMPLE_RATE * duration))
	var samples := PackedFloat32Array()
	samples.resize(total)
	var phase := 0.0
	for index in range(total):
		var progress := float(index) / float(total)
		var freq := first_hz if progress < 0.42 else second_hz
		phase += TAU * freq / float(SAMPLE_RATE)
		var env := minf(1.0, progress * 35.0) * pow(1.0 - progress, 1.35)
		samples[index] = (sin(phase) * 0.78 + sin(phase * 2.0) * 0.22) * gain * env
	return pack_pcm(samples)

static func synth_alarm(duration: float, high_hz: float, low_hz: float, gain: float) -> AudioStreamWAV:
	var total := maxi(1, int(SAMPLE_RATE * duration))
	var samples := PackedFloat32Array()
	samples.resize(total)
	var phase := 0.0
	for index in range(total):
		var progress := float(index) / float(total)
		var pulse := int(progress * 6.0) % 2 == 0
		var freq := high_hz if pulse else low_hz
		phase += TAU * freq / float(SAMPLE_RATE)
		var env := minf(1.0, progress * 25.0) * (1.0 - progress * 0.65)
		samples[index] = (sin(phase) * 0.65 + (1.0 if sin(phase) >= 0.0 else -1.0) * 0.35) * gain * env
	return pack_pcm(samples)

static func synth_ambient(duration: float) -> AudioStreamWAV:
	var total := maxi(1, int(SAMPLE_RATE * duration))
	var samples := PackedFloat32Array()
	samples.resize(total)
	for index in range(total):
		var progress := float(index) / float(total)
		var theta := TAU * progress
		var hum := sin(theta * 220.0) * 0.38 + sin(theta * 330.0) * 0.20 + sin(theta * 110.0) * 0.42
		var swell := 0.72 + 0.28 * sin(theta * 2.0)
		samples[index] = hum * swell * 0.18
	return pack_pcm(samples, true)

func set_muted(value: bool) -> void:
	muted = value
	if headless or ambient_player == null:
		return
	if muted:
		ambient_player.stop()
		pulse_player.stop()
		vent_player.stop()
		for channel in pool:
			channel.stop()
	elif not ambient_player.playing and ambient_player.stream != null:
		ambient_player.play()

func toggle_mute() -> bool:
	set_muted(not muted)
	return muted

func play(kind: String, strength: float = 1.0, offset: Vector2 = Vector2.ZERO) -> void:
	if muted or headless or pool.is_empty():
		return
	var key := "missile" if kind == "muzzle" and strength > 1.0 else kind
	if key == "ship_breakup": key = "rupture"
	if not streams.has(key):
		return
	var now := Time.get_ticks_msec()
	var min_gap := 45 if key in ["muzzle", "intercept", "click"] else 90
	if now - int(last_played.get(key, -1000)) < min_gap:
		return
	last_played[key] = now
	if key in ["breach","rupture"] and offset.length() < 350.0:
		duck_until = now + 150
	var player: AudioStreamPlayer2D = pool[pool_index]
	player.global_position = get_viewport().get_visible_rect().get_center() + offset
	pool_index = (pool_index + 1) % pool.size()
	player.stream = streams[key]
	player.pitch_scale = clampf(1.0 + randf_range(-0.06, 0.06) - (strength - 1.0) * 0.08, 0.75, 1.30)
	player.volume_db = clampf(-10.0 + (strength - 1.0) * 3.0, -16.0, -4.0)
	player.play()
