extends Node
## Procedural sound effects: every sound is synthesised once at _ready().

const RATE: int = 22050
const POOL_SIZE: int = 10

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1234
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_all()


func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(name) or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch, 0.05)
	p.play()


# ---------------------------------------------------------------- building

func _build_all() -> void:
	_streams["bonk"] = _make(_bonk())
	_streams["thud"] = _make(_thud())
	_streams["slip"] = _make(_slip())
	_streams["dash"] = _make(_dash())
	_streams["grab"] = _make(_grab())
	_streams["escape"] = _make(_escape())
	_streams["pick"] = _make(_pick())
	_streams["drop"] = _make(_drop())
	_streams["splash"] = _make(_splash())
	_streams["whistle"] = _make(_whistle())
	_streams["tick"] = _make(_tick())
	_streams["order_tick"] = _make(_order_tick())
	_streams["statue"] = _make(_statue())
	_streams["countdown"] = _make(_beep(660.0, 0.16))
	_streams["go"] = _make(_beep(990.0, 0.32))
	_streams["win"] = _make(_win())
	_streams["lose"] = _make(_lose())
	_streams["swing"] = _make(_swing())
	_streams["click"] = _make(_click())


## Normalises to ~0.8 peak, applies a short fade-out and packs 16-bit LE mono.
func _make(f: PackedFloat32Array) -> AudioStreamWAV:
	var n: int = f.size()
	var peak: float = 0.0
	for i in n:
		peak = maxf(peak, absf(f[i]))
	var g: float = 0.8 / maxf(peak, 0.0001)
	var fade: int = mini(int(0.012 * RATE), n)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v: float = f[i] * g
		var left: int = n - 1 - i
		if left < fade:
			v *= float(left) / float(fade)
		bytes.encode_s16(i * 2, clampi(int(v * 32767.0), -32767, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = false
	w.mix_rate = RATE
	w.data = bytes
	return w


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


## Adds src into dst starting at `at` seconds, scaled by `gain`.
func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, at: float, gain: float = 1.0) -> void:
	var o: int = int(at * RATE)
	for i in src.size():
		if o + i >= dst.size():
			break
		dst[o + i] += src[i] * gain


# ---------------------------------------------------------------- primitives

## Oscillator with exponential pitch sweep f0->f1, attack/decay envelope.
## wave: 0 sine, 1 square, 2 triangle. vib = vibrato depth (fraction), vib_hz rate.
func _tone(f0: float, f1: float, dur: float, wave: int = 0, decay: float = 5.0,
		attack: float = 0.003, vib: float = 0.0, vib_hz: float = 6.0) -> PackedFloat32Array:
	var b := _buf(dur)
	var n: int = b.size()
	var phase: float = 0.0
	var ratio: float = f1 / f0
	var att: float = maxf(attack * RATE, 1.0)
	for i in n:
		var t: float = float(i) / float(n)
		var f: float = f0 * pow(ratio, t)
		if vib > 0.0:
			f *= 1.0 + vib * sin(TAU * vib_hz * float(i) / RATE)
		phase += f / RATE
		var ph: float = phase - floorf(phase)
		var s: float
		match wave:
			1:
				s = 0.6 if ph < 0.5 else -0.6
			2:
				s = 4.0 * absf(ph - 0.5) - 1.0
			_:
				s = sin(TAU * ph)
		b[i] = s * exp(-decay * t) * minf(float(i) / att, 1.0)
	return b


## White noise through a one-pole lowpass whose cutoff coefficient sweeps a0->a1
## (0..1, bigger = brighter). Optionally high-passed by subtracting a slow lowpass.
func _noise(dur: float, a0: float, a1: float, decay: float = 4.0, attack: float = 0.002,
		hp: bool = false) -> PackedFloat32Array:
	var b := _buf(dur)
	var n: int = b.size()
	var lp: float = 0.0
	var slow: float = 0.0
	var att: float = maxf(attack * RATE, 1.0)
	for i in n:
		var t: float = float(i) / float(n)
		var a: float = lerpf(a0, a1, t)
		lp += a * (_rng.randf_range(-1.0, 1.0) - lp)
		var s: float = lp
		if hp:
			slow += 0.05 * (lp - slow)
			s = lp - slow
		b[i] = s * exp(-decay * t) * minf(float(i) / att, 1.0)
	return b


## Bell-shaped (sine) envelope on a buffer, for swishes.
func _bell(b: PackedFloat32Array, power: float = 1.0) -> PackedFloat32Array:
	var n: int = b.size()
	for i in n:
		b[i] *= pow(sin(PI * float(i) / float(n)), power)
	return b


# ---------------------------------------------------------------- sounds

func _bonk() -> PackedFloat32Array:
	var b := _tone(520.0, 190.0, 0.22, 0, 9.0)
	_mix(b, _tone(1040.0, 380.0, 0.12, 0, 16.0), 0.0, 0.35)
	_mix(b, _tone(330.0, 140.0, 0.2, 2, 11.0), 0.0, 0.5)
	_mix(b, _noise(0.03, 0.7, 0.4, 6.0), 0.0, 0.8)
	return b


func _thud() -> PackedFloat32Array:
	var b := _tone(120.0, 40.0, 0.42, 0, 6.0, 0.002)
	_mix(b, _noise(0.35, 0.18, 0.04, 6.0), 0.0, 1.1)
	_mix(b, _noise(0.04, 0.6, 0.3, 6.0), 0.0, 0.7)
	return b


func _slip() -> PackedFloat32Array:
	var b := _tone(1900.0, 280.0, 0.75, 0, 1.2, 0.01, 0.025, 11.0)
	_mix(b, _tone(3800.0, 560.0, 0.75, 0, 1.6, 0.01, 0.025, 11.0), 0.0, 0.15)
	return b


func _dash() -> PackedFloat32Array:
	return _bell(_noise(0.32, 0.08, 0.55, 0.0, 0.002, true), 1.3)


func _grab() -> PackedFloat32Array:
	var b := _bell(_noise(0.08, 0.3, 0.12, 0.0, 0.002), 0.8)
	var hup := _tone(180.0, 300.0, 0.14, 1, 5.0, 0.004)
	_mix(b, hup, 0.07, 0.55)
	_mix(b, _noise(0.14, 0.12, 0.2, 5.0), 0.07, 0.3)
	return b


func _escape() -> PackedFloat32Array:
	var b := _tone(180.0, 900.0, 0.12, 0, 1.0, 0.003)
	_mix(b, _tone(900.0, 260.0, 0.4, 0, 4.0, 0.003, 0.05, 28.0), 0.1, 1.0)
	_mix(b, _tone(1800.0, 520.0, 0.35, 0, 7.0, 0.003, 0.05, 28.0), 0.1, 0.25)
	return b


func _pick() -> PackedFloat32Array:
	var b := _tone(1200.0, 1500.0, 0.1, 2, 12.0, 0.001)
	_mix(b, _tone(2400.0, 3000.0, 0.06, 0, 18.0, 0.001), 0.0, 0.3)
	return b


func _drop() -> PackedFloat32Array:
	var b := _tone(380.0, 120.0, 0.16, 0, 9.0, 0.003)
	_mix(b, _noise(0.08, 0.2, 0.08, 7.0), 0.0, 0.5)
	return b


func _splash() -> PackedFloat32Array:
	var b := _noise(0.5, 0.65, 0.2, 5.0, 0.004, true)
	for k in 5:
		var f: float = _rng.randf_range(500.0, 1200.0)
		_mix(b, _tone(f, f * 2.0, 0.07, 0, 9.0, 0.002), 0.03 + k * 0.06, 0.5)
	return b


func _whistle() -> PackedFloat32Array:
	var b := _tone(2500.0, 2650.0, 0.5, 0, 1.0, 0.01, 0.03, 38.0)
	_mix(b, _noise(0.5, 0.5, 0.5, 1.0, 0.01, true), 0.0, 0.18)
	var env := _bell(b, 0.35)
	return env


func _tick() -> PackedFloat32Array:
	var b := _tone(1600.0, 1000.0, 0.05, 0, 14.0, 0.0005)
	_mix(b, _noise(0.012, 0.8, 0.5, 5.0, 0.0005), 0.0, 0.5)
	return b


func _order_tick() -> PackedFloat32Array:
	var b := _tone(1320.0, 1320.0, 0.07, 1, 6.0, 0.001)
	_mix(b, _tone(1760.0, 1760.0, 0.16, 1, 5.0, 0.001), 0.07, 1.0)
	_mix(b, _tone(3520.0, 3520.0, 0.1, 0, 12.0, 0.001), 0.07, 0.25)
	return b


func _statue() -> PackedFloat32Array:
	var b := _noise(0.5, 0.45, 0.08, 4.0, 0.001)
	for k in 6:
		_mix(b, _noise(0.04, 0.7, 0.3, 6.0, 0.0005), k * 0.05, 0.8)
	_mix(b, _tone(150.0, 70.0, 0.4, 0, 7.0), 0.0, 0.7)
	_mix(b, _tone(900.0, 500.0, 0.08, 1, 14.0), 0.02, 0.2)
	return b


func _beep(freq: float, dur: float) -> PackedFloat32Array:
	var b := _tone(freq, freq, dur, 0, 1.2, 0.004)
	_mix(b, _tone(freq * 2.0, freq * 2.0, dur, 0, 1.5, 0.004), 0.0, 0.2)
	return b


func _win() -> PackedFloat32Array:
	var b := _buf(1.3)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		var d: float = 0.12
		_mix(b, _tone(notes[i], notes[i], 0.3, 1, 4.0, 0.003), i * d, 0.5)
		_mix(b, _tone(notes[i] * 2.0, notes[i] * 2.0, 0.3, 0, 5.0, 0.003), i * d, 0.2)
	var t0: float = 0.52
	var chord: Array[float] = [523.25, 659.25, 783.99, 1046.5]
	for f in chord:
		_mix(b, _tone(f, f, 0.75, 1, 2.5, 0.004, 0.006, 6.0), t0, 0.28)
		_mix(b, _tone(f * 2.0, f * 2.0, 0.75, 0, 3.0, 0.004), t0, 0.1)
	return b


func _lose() -> PackedFloat32Array:
	var b := _buf(1.6)
	var notes: Array[float] = [311.13, 293.66, 277.18, 233.08]
	var starts: Array[float] = [0.0, 0.34, 0.68, 1.02]
	var durs: Array[float] = [0.3, 0.3, 0.3, 0.58]
	for i in notes.size():
		var f: float = notes[i]
		var d: float = durs[i]
		var fe: float = f * (0.8 if i == 3 else 0.97)
		var n := _tone(f, fe, d, 1, 1.5, 0.02, 0.035 if i == 3 else 0.02, 6.5 if i == 3 else 9.0)
		var m := _tone(f * 0.5, fe * 0.5, d, 2, 1.5, 0.02, 0.035 if i == 3 else 0.02, 6.5 if i == 3 else 9.0)
		var mixed := _buf(d)
		_mix(mixed, n, 0.0, 0.5)
		_mix(mixed, m, 0.0, 0.5)
		# wah: amplitude swell via a bell envelope
		_mix(b, _bell(mixed, 0.5), starts[i], 1.0)
	return b


func _swing() -> PackedFloat32Array:
	return _bell(_noise(0.16, 0.12, 0.45, 0.0, 0.002, true), 1.0)


func _click() -> PackedFloat32Array:
	var b := _tone(1100.0, 700.0, 0.04, 0, 20.0, 0.0005)
	_mix(b, _noise(0.01, 0.8, 0.5, 5.0, 0.0003), 0.0, 0.4)
	return b
