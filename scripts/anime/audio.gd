extends Node
# Procedural audio: every sound is synthesised in code (no audio files).

const SET = preload("res://scripts/anime/settings.gd")
const RATE := 22050

var _sfx: Dictionary = {}
var _pool: Array = []
var _music: AudioStreamPlayer = null
var _wind: AudioStreamPlayer = null
var _thread: Thread = null
var _music_stream: AudioStreamWAV = null

func _ready() -> void:
	add_to_group("audio")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_sfx()
	for i in range(8):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_wind = AudioStreamPlayer.new()
	add_child(_wind)
	_wind.stream = _make_wind()
	_wind.play()
	apply_volumes()
	_thread = Thread.new()
	_thread.start(_gen_music)

func apply_volumes() -> void:
	if _music != null:
		_music.volume_db = linear_to_db(maxf(SET.music, 0.0001)) - 9.0
		_music.stream_paused = SET.music < 0.01
	if _wind != null:
		_wind.volume_db = linear_to_db(maxf(SET.sfx, 0.0001)) - 24.0

func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
		if _music_stream != null and _music != null:
			_music.stream = _music_stream
			_music.play()

func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

func play(nm: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _sfx.has(nm) or SET.sfx < 0.01:
		return
	var pl: AudioStreamPlayer = null
	for p in _pool:
		var ap: AudioStreamPlayer = p as AudioStreamPlayer
		if not ap.playing:
			pl = ap
			break
	if pl == null:
		pl = _pool[0] as AudioStreamPlayer
	pl.stream = _sfx[nm] as AudioStream
	pl.volume_db = vol_db + linear_to_db(maxf(SET.sfx, 0.0001))
	pl.pitch_scale = pitch
	pl.play()

# ------------------------------------------------------------ helpers
func _wav(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * float(RATE)))
	return b

# sine with exponential decay, added into buf starting at start_sec
func _tone(buf: PackedFloat32Array, start_sec: float, freq: float, dur: float, amp: float, decay: float, harm: float = 0.3) -> void:
	var s0: int = int(start_sec * float(RATE))
	var n: int = int(dur * float(RATE))
	for i in range(n):
		var idx: int = s0 + i
		if idx >= buf.size():
			break
		var t: float = float(i) / float(RATE)
		var env: float = exp(-t * decay) * minf(1.0, t * 120.0)
		var ph: float = TAU * freq * t
		buf[idx] += (sin(ph) + harm * sin(ph * 2.0)) * env * amp

func _chirp(buf: PackedFloat32Array, start_sec: float, f0: float, f1: float, dur: float, amp: float, decay: float) -> void:
	var s0: int = int(start_sec * float(RATE))
	var n: int = int(dur * float(RATE))
	var ph: float = 0.0
	for i in range(n):
		var idx: int = s0 + i
		if idx >= buf.size():
			break
		var k: float = float(i) / float(n)
		var f: float = lerpf(f0, f1, k)
		ph += TAU * f / float(RATE)
		var t: float = float(i) / float(RATE)
		buf[idx] += sin(ph) * exp(-t * decay) * minf(1.0, t * 150.0) * amp

func _noise(buf: PackedFloat32Array, start_sec: float, dur: float, amp: float, decay: float, hp: float = 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + int(start_sec * 1000.0)
	var s0: int = int(start_sec * float(RATE))
	var n: int = int(dur * float(RATE))
	var prev: float = 0.0
	for i in range(n):
		var idx: int = s0 + i
		if idx >= buf.size():
			break
		var t: float = float(i) / float(RATE)
		var nz: float = rng.randf() * 2.0 - 1.0
		var y: float = nz - prev * hp
		prev = nz
		buf[idx] += y * exp(-t * decay) * minf(1.0, t * 200.0) * amp

# ------------------------------------------------------------ sfx bank
func _make_sfx() -> void:
	var b: PackedFloat32Array
	b = _buf(0.20)
	_noise(b, 0.0, 0.20, 0.55, 16.0, 0.95)
	_chirp(b, 0.0, 900.0, 300.0, 0.15, 0.10, 18.0)
	_sfx["slash"] = _wav(b, RATE, false)
	b = _buf(0.22)
	_chirp(b, 0.0, 220.0, 70.0, 0.2, 0.7, 14.0)
	_noise(b, 0.0, 0.06, 0.4, 40.0, 0.7)
	_sfx["hit"] = _wav(b, RATE, false)
	b = _buf(0.45)
	_chirp(b, 0.0, 420.0, 90.0, 0.4, 0.55, 7.0)
	_noise(b, 0.0, 0.2, 0.35, 12.0, 0.8)
	_tone(b, 0.0, 880.0, 0.3, 0.2, 9.0)
	_sfx["kill"] = _wav(b, RATE, false)
	b = _buf(0.18)
	_chirp(b, 0.0, 260.0, 620.0, 0.15, 0.5, 9.0)
	_sfx["jump"] = _wav(b, RATE, false)
	b = _buf(0.5)
	var notes: Array = [1046.5, 1318.5, 1568.0, 2093.0]
	for k in range(notes.size()):
		_tone(b, float(k) * 0.07, float(notes[k]), 0.4, 0.28, 8.0, 0.25)
	_sfx["pickup"] = _wav(b, RATE, false)
	b = _buf(0.5)
	_chirp(b, 0.0, 300.0, 1200.0, 0.35, 0.4, 5.0)
	_noise(b, 0.0, 0.35, 0.25, 6.0, 0.9)
	_tone(b, 0.1, 1568.0, 0.35, 0.2, 7.0)
	_sfx["skill"] = _wav(b, RATE, false)
	b = _buf(1.0)
	_chirp(b, 0.0, 140.0, 40.0, 0.8, 0.9, 4.0)
	_noise(b, 0.0, 0.5, 0.45, 5.0, 0.8)
	_tone(b, 0.05, 523.25, 0.9, 0.18, 3.0)
	_tone(b, 0.05, 659.25, 0.9, 0.16, 3.0)
	_tone(b, 0.05, 783.99, 0.9, 0.16, 3.0)
	_sfx["burst"] = _wav(b, RATE, false)
	b = _buf(0.3)
	_chirp(b, 0.0, 380.0, 120.0, 0.25, 0.6, 9.0)
	_noise(b, 0.0, 0.08, 0.3, 30.0, 0.7)
	_sfx["hurt"] = _wav(b, RATE, false)
	b = _buf(0.22)
	_noise(b, 0.0, 0.22, 0.5, 10.0, 0.6)
	_chirp(b, 0.0, 500.0, 200.0, 0.2, 0.15, 12.0)
	_sfx["dash"] = _wav(b, RATE, false)
	b = _buf(0.08)
	_tone(b, 0.0, 1300.0, 0.07, 0.35, 30.0, 0.1)
	_sfx["click"] = _wav(b, RATE, false)
	b = _buf(0.06)
	_noise(b, 0.0, 0.05, 0.25, 70.0, 0.5)
	_sfx["step"] = _wav(b, RATE, false)
	b = _buf(0.35)
	_tone(b, 0.0, 700.0, 0.3, 0.3, 12.0, 0.2)
	_tone(b, 0.05, 1050.0, 0.28, 0.22, 12.0, 0.2)
	_sfx["heal"] = _wav(b, RATE, false)
	b = _buf(2.2)
	var vn: Array = [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0]
	for k in range(vn.size()):
		_tone(b, float(k) * 0.16, float(vn[k]), 1.2, 0.26, 3.0, 0.3)
	_sfx["victory"] = _wav(b, RATE, false)

func _make_wind() -> AudioStreamWAV:
	var rate: int = 11025
	var n: int = rate * 3
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		var nz: float = rng.randf() * 2.0 - 1.0
		lp += (nz - lp) * 0.06
		out[i] = lp * (0.5 + 0.5 * sin(t * TAU * 2.0 + 0.7)) * 1.4
	return _wav(out, rate, true)

# ------------------------------------------------------------ music (runs in a thread)
func _gen_music() -> void:
	var rate: int = 11025
	var step: float = 0.30
	var total: int = int(step * 32.0 * float(rate))
	var buf := PackedFloat32Array()
	buf.resize(total)
	var scale: Array = [261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25, 783.99]
	var pat: Array = [
		[0, 2, 3, 5, 3, 2, 0, 2],
		[1, 3, 4, 6, 4, 3, 1, 3],
		[0, 3, 5, 7, 5, 3, 2, 3],
		[2, 4, 5, 6, 5, 4, 3, 1],
	]
	var bass: Array = [130.81, 110.0, 87.31, 98.0]
	for bar in range(4):
		var row: Array = pat[bar]
		for k in range(8):
			var f: float = float(scale[int(row[k])])
			_note(buf, rate, (bar * 8 + k) * step, f, 0.85, 0.20, 3.4)
		_note(buf, rate, float(bar) * 8.0 * step, float(bass[bar]), 2.2, 0.26, 1.3)
		_note(buf, rate, (float(bar) * 8.0 + 4.0) * step, float(bass[bar]) * 1.5, 1.2, 0.12, 2.0)
	_music_stream = _wav(buf, rate, true)

func _note(buf: PackedFloat32Array, rate: int, start: float, freq: float, dur: float, amp: float, decay: float) -> void:
	var s0: int = int(start * float(rate))
	var n: int = int(dur * float(rate))
	var size: int = buf.size()
	for i in range(n):
		var t: float = float(i) / float(rate)
		var env: float = exp(-t * decay) * minf(1.0, t * 90.0)
		var ph: float = TAU * freq * t
		var v: float = (sin(ph) + 0.35 * sin(ph * 2.0) * exp(-t * 3.0)) * env * amp
		buf[(s0 + i) % size] += v
