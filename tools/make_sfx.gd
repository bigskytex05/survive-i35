extends SceneTree
## Generates the game's sound effects as WAV files in assets/audio/sfx/.
## Everything is synthesized (no samples, no licenses to track), and the files
## are committed, so the game never builds sounds at runtime. To use a real
## recording instead, drop a WAV with the same name over the generated one.
##
## Run: tools/make_sfx.sh (regenerates every file and reimports).
##
## Loops (engines, tire squeal, siren) are seamless by construction: every
## tone and modulation completes whole cycles in the loop, noise is cross-faded
## across the seam, and engine pulses wrap around the end of the buffer.
## Loop points are set in each file's .import (see LOOPS).

const RATE := 44100
const OUT := "res://assets/audio/sfx/"
## Sounds that loop, and so get a forward loop in their import settings.
const LOOPS: Array[String] = ["engine_v8", "engine_six", "engine_ev", "tire_squeal", "siren"]
## Peak level every file is normalized to (in-game volumes set the mix).
const PEAK := 0.89

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 35
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var sounds := {
		"engine_v8": engine_pulses(40.0, 8, [1.0, 0.62, 0.92, 0.55, 0.98, 0.7, 0.85, 0.6], [115.0, 290.0], 46.0, 0.5),
		"engine_six": engine_pulses(52.0, 6, [1.0, 0.9, 0.96, 0.86, 1.0, 0.92], [165.0, 420.0], 64.0, 0.32),
		"engine_ev": engine_ev(),
		"tire_squeal": tire_squeal(),
		"siren": siren(),
		"siren_whoop": siren_whoop(),
		"crash": crash(),
		"bump": bump(),
		"scrape": scrape(),
		"whoosh": whoosh(),
		"bonus": bonus(),
		"beep": beep(523.25, 0.16),
		"beep_go": beep(1046.5, 0.6),
		"tick": tick(),
		"click": click(),
		"confirm": confirm(),
		"win": win(),
		"fail": fail(),
		"ticket": ticket(),
		"firework": firework(),
		"horn": horn(0.72, true),
		"horn_short": horn(0.3, false),
		"bleep": bleep(),
		"whoomp": whoomp(),
		"radar_beep": radar_beep(),
	}
	for sound_name: String in sounds:
		_save(sound_name, sounds[sound_name])
	print("wrote %d sounds to %s" % [sounds.size(), OUT])
	quit()


# --- Engines ----------------------------------------------------------------------

## A combustion engine as a train of firing pulses: `rate` pulses a second, each
## a decaying ring of the exhaust's `resonances` plus a puff of noise, with a
## per-cylinder strength `pattern` (an uneven V8 burbles; a six is smoother).
## One second long, rendered into a circular buffer so the tails wrap the seam.
func engine_pulses(rate: float, cylinders: int, pattern: Array, resonances: Array, decay: float, noise: float) -> PackedFloat32Array:
	var n := RATE
	var buf := PackedFloat32Array()
	buf.resize(n)
	var pulses := int(rate)
	var pulse_len := int(RATE * 0.09)
	var lp := Biquad.lowpass(900.0, 0.7)
	for p in pulses:
		var start := int(float(p) / rate * RATE)
		var amp: float = pattern[p % cylinders] * rng.randf_range(0.9, 1.1)
		for j in pulse_len:
			var t := float(j) / RATE
			var attack := minf(t / 0.0015, 1.0)  # no click at each firing
			var env := exp(-t * decay) * attack
			var ring := sin(TAU * resonances[0] * t) + 0.45 * sin(TAU * resonances[1] * t + 0.7)
			var puff := lp.process(rng.randf_range(-1.0, 1.0)) * exp(-t * decay * 2.5) * noise * attack
			buf[(start + j) % n] += amp * (ring * env + puff)
	# A little low thrum under it all, then squash it like an exhaust would.
	for i in n:
		var t := float(i) / RATE
		buf[i] = tanh(1.7 * (buf[i] + 0.25 * sin(TAU * rate * 0.5 * t)))
	return buf


## The EV: an electric motor's whine (a clean tone and two overtones), the
## inverter's faint high buzz, and a soft hum. All whole-hertz, one second.
func engine_ev() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(RATE)
	for i in RATE:
		var t := float(i) / RATE
		var whine := sin(TAU * 310.0 * t) + 0.32 * sin(TAU * 620.0 * t + 0.4) + 0.12 * sin(TAU * 930.0 * t + 1.1)
		var inverter := 0.05 * sin(TAU * 2480.0 * t) * (0.6 + 0.4 * sin(TAU * 31.0 * t))
		var hum := 0.22 * sin(TAU * 62.0 * t)
		out[i] = (whine + inverter + hum) * (0.92 + 0.08 * sin(TAU * 5.0 * t))
	return out


# --- Tires, impacts, passes ---------------------------------------------------------

## Tire squeal: a wavering squeal tone (its wobble is periodic over the loop) on
## a bed of band-passed hiss. One second.
func tire_squeal() -> PackedFloat32Array:
	var hiss := _loop_noise(RATE, Biquad.bandpass(2300.0, 1.1))
	var out := PackedFloat32Array()
	out.resize(RATE)
	for i in RATE:
		var t := float(i) / RATE
		# Frequency wobble integrated by hand: phase of 1080 Hz plus sine FM terms.
		var phase := TAU * 1080.0 * t \
			- 50.0 / 3.0 * cos(TAU * 3.0 * t) - 34.0 / 7.0 * cos(TAU * 7.0 * t + 1.3) \
			- 20.0 / 17.0 * cos(TAU * 17.0 * t + 0.4)
		var tone := sin(phase) + 0.4 * sin(phase * 1.5) + 0.18 * sin(phase * 2.0)
		var flutter := 0.78 + 0.22 * sin(TAU * 11.0 * t)
		out[i] = (0.55 * tone * flutter + 0.75 * hiss[i])
	return out


## A big hit: a thump, a burst of crunch, ringing sheet metal and glass.
func crash() -> PackedFloat32Array:
	var n := int(RATE * 1.1)
	var out := PackedFloat32Array()
	out.resize(n)
	var crunch := Biquad.lowpass(3200.0, 0.8)
	var late := Biquad.lowpass(1800.0, 0.8)
	var partials := [[430.0, 0.5, 5.0], [1135.0, 0.35, 7.0], [1712.0, 0.28, 8.5], [2390.0, 0.2, 10.0], [3170.0, 0.14, 13.0]]
	var pings: Array = []
	for i in 28:
		pings.append([rng.randf_range(0.02, 0.55), rng.randf_range(2900.0, 6800.0), rng.randf_range(35.0, 80.0), rng.randf_range(0.05, 0.16)])
	var thump_phase := 0.0
	for i in n:
		var t := float(i) / RATE
		thump_phase += TAU * lerpf(75.0, 34.0, minf(t / 0.25, 1.0)) / RATE
		var x := sin(thump_phase) * exp(-t * 9.0)
		x += crunch.process(rng.randf_range(-1.0, 1.0)) * exp(-t * 7.0) * 1.4
		if t > 0.13:
			x += late.process(rng.randf_range(-1.0, 1.0)) * exp(-(t - 0.13) * 11.0) * 0.6
		for p: Array in partials:
			x += sin(TAU * p[0] * t) * p[1] * exp(-t * p[2]) * 0.8
		for g: Array in pings:
			var dt: float = t - g[0]
			if dt >= 0.0 and dt < 0.15:
				x += sin(TAU * g[1] * dt) * exp(-dt * g[2]) * g[3]
		out[i] = tanh(1.3 * x)
	return out


## A light knock: car-on-car or car-on-barrier without much in it.
func bump() -> PackedFloat32Array:
	var n := int(RATE * 0.32)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := Biquad.lowpass(1400.0, 0.7)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(95.0, 48.0, minf(t / 0.12, 1.0)) / RATE
		var x := sin(phase) * exp(-t * 17.0)
		x += lp.process(rng.randf_range(-1.0, 1.0)) * exp(-t * 32.0) * 0.8
		x += sin(TAU * 245.0 * t) * exp(-t * 26.0) * 0.35
		out[i] = tanh(1.4 * x)
	return out


## Metal grinding along the barrier.
func scrape() -> PackedFloat32Array:
	var n := int(RATE * 0.6)
	var out := PackedFloat32Array()
	out.resize(n)
	var bp := Biquad.bandpass(1900.0, 2.2)
	var bp2 := Biquad.bandpass(3400.0, 3.0)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.015, 1.0) * exp(-t * 3.2)
		var chatter := 0.55 + 0.45 * absf(sin(TAU * 37.0 * t + sin(TAU * 5.0 * t)))
		var grind := 0.18 * (fmod(t * 233.0, 1.0) * 2.0 - 1.0)
		var noise := rng.randf_range(-1.0, 1.0)
		out[i] = (bp.process(noise) * 2.2 + bp2.process(noise) * 1.2 + grind) * chatter * env
	return out


## A car flashing past: a swell of wind that brightens and fades.
func whoosh() -> PackedFloat32Array:
	var n := int(RATE * 0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	var bp := Biquad.new()
	for i in n:
		var t := float(i) / RATE
		var u := t / 0.55
		var center := 500.0 + 2100.0 * sin(PI * minf(u * 1.15, 1.0))
		bp.set_bandpass(center, 0.9)
		var env := pow(sin(PI * u), 2.0)
		out[i] = bp.process(rng.randf_range(-1.0, 1.0)) * env
	return out


## The near-miss time bonus: two bright chimes going up.
func bonus() -> PackedFloat32Array:
	var n := int(RATE * 0.42)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var x := _chime(1318.5, t) * 0.8
		if t > 0.075:
			x += _chime(1975.5, t - 0.075)
		out[i] = x
	return out


func _chime(freq: float, t: float) -> float:
	return (sin(TAU * freq * t) + 0.28 * sin(TAU * freq * 2.0 * t) + 0.1 * sin(TAU * freq * 3.0 * t)) \
		* minf(t / 0.004, 1.0) * exp(-t * 9.0)


# --- Countdown, clock, UI ---------------------------------------------------------

## A start-light beep: a soft square-ish tone.
func beep(freq: float, seconds: float) -> PackedFloat32Array:
	var n := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.004, 1.0) * minf((seconds - t) / 0.03, 1.0) * (1.0 if seconds < 0.3 else exp(-t * 2.5))
		out[i] = _buzz(freq, t, 4) * env
	return out


## The last ten seconds' clock tick.
func tick() -> PackedFloat32Array:
	var n := int(RATE * 0.06)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp := Biquad.highpass(2500.0, 0.7)
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 1850.0 * t) * 0.8 + hp.process(rng.randf_range(-1.0, 1.0)) * 0.5) * exp(-t * 110.0)
	return out


## A menu button.
func click() -> PackedFloat32Array:
	var n := int(RATE * 0.05)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp := Biquad.highpass(1800.0, 0.7)
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 1400.0 * t) * 0.7 + hp.process(rng.randf_range(-1.0, 1.0)) * 0.35) * exp(-t * 150.0)
	return out


## A step forward in the menus (Next, Hit the Road): two quick notes up.
func confirm() -> PackedFloat32Array:
	var n := int(RATE * 0.24)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var x := _chime(880.0, t) * 0.7
		if t > 0.07:
			x += _chime(1318.5, t - 0.07)
		out[i] = x
	return out


# --- Stingers -----------------------------------------------------------------------

## Made it: a quick brassy arpeggio up to a held major chord.
func win() -> PackedFloat32Array:
	var n := int(RATE * 2.1)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes := [[0.0, 392.0], [0.1, 523.25], [0.2, 659.25], [0.3, 783.99]]
	var chord := [523.25, 659.25, 783.99, 1046.5]
	for i in n:
		var t := float(i) / RATE
		var x := 0.0
		for note: Array in notes:
			var dt: float = t - note[0]
			if dt >= 0.0 and dt < 0.16:
				x += _brass(note[1], dt, 0.85) * minf(dt / 0.01, 1.0) * minf((0.16 - dt) / 0.03, 1.0)
		if t >= 0.42:
			var dt := t - 0.42
			var vib := 1.0 + 0.006 * sin(TAU * 5.5 * dt) * minf(dt / 0.4, 1.0)
			var env := minf(dt / 0.02, 1.0) * exp(-dt * 1.3)
			for f: float in chord:
				x += _brass(f * vib, dt, 0.6 + 0.3 * exp(-dt * 3.0)) * env * 0.42
		out[i] = tanh(x * 0.9)
	return out


## Out of time: the sad trombone. Wah, wah, wah, waaaah.
func fail() -> PackedFloat32Array:
	var n := int(RATE * 2.6)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes := [[0.0, 0.42, 293.66], [0.46, 0.42, 277.18], [0.92, 0.42, 261.63], [1.38, 1.15, 246.94]]
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := 0.0
		for note: Array in notes:
			var dt: float = t - note[0]
			var length: float = note[1]
			if dt < 0.0 or dt > length:
				continue
			var last := length > 1.0
			var vib := 1.0 + (0.018 * sin(TAU * 5.2 * dt) * minf(dt / 0.3, 1.0) if last else 0.0)
			phase += TAU * note[2] * vib / RATE
			# Each note swells open like a plunger mute coming off the bell.
			var bright := 0.35 + 0.55 * minf(dt / 0.18, 1.0)
			var env := minf(dt / 0.04, 1.0) * minf((length - dt) / 0.06, 1.0)
			x += _brass_phase(phase, bright) * env
		out[i] = tanh(x * 0.8)
	return out


## Pulled over: the ticket rings up. Ka-ching.
func ticket() -> PackedFloat32Array:
	var n := int(RATE * 1.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp := Biquad.highpass(3000.0, 0.7)
	for i in n:
		var t := float(i) / RATE
		var x := hp.process(rng.randf_range(-1.0, 1.0)) * exp(-t * 45.0) * 0.9
		if t > 0.11:
			var dt := t - 0.11
			x += sin(TAU * 105.0 * dt) * exp(-dt * 30.0) * 0.8
			for p: Array in [[2093.0, 0.6], [2637.0, 0.45], [3136.0, 0.35], [4186.0, 0.25], [5274.0, 0.12]]:
				x += sin(TAU * p[0] * dt) * p[1] * exp(-dt * 3.2)
		out[i] = tanh(x)
	return out


## One firework: a rising whistle, a bang and a crackle.
func firework() -> PackedFloat32Array:
	var n := int(RATE * 1.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := Biquad.lowpass(1600.0, 0.7)
	var phase := 0.0
	var crackles: Array = []
	for i in 40:
		crackles.append([rng.randf_range(0.62, 1.4), rng.randf_range(0.2, 0.6)])
	for i in n:
		var t := float(i) / RATE
		var x := 0.0
		if t < 0.5:
			phase += TAU * lerpf(1100.0, 2700.0, t / 0.5) / RATE
			x += sin(phase) * 0.18 * minf(t / 0.05, 1.0) * minf((0.5 - t) / 0.05, 1.0)
		if t >= 0.52:
			var dt := t - 0.52
			x += sin(TAU * 52.0 * dt) * exp(-dt * 7.0) * 1.0
			x += lp.process(rng.randf_range(-1.0, 1.0)) * exp(-dt * 6.0) * 1.2
		for c: Array in crackles:
			var dt: float = t - c[0]
			if dt >= 0.0 and dt < 0.012:
				x += rng.randf_range(-1.0, 1.0) * c[1] * (1.0 - dt / 0.012)
		out[i] = tanh(x)
	return out


# --- Police ---------------------------------------------------------------------------

## The wail: a smooth rise and fall between about 620 and 1380 Hz every two
## seconds. The phase is integrated by hand so the loop closes exactly.
func siren() -> PackedFloat32Array:
	var length := 2.0
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var phase := TAU * (1000.0 * t - 380.0 * length / TAU * sin(TAU * t / length))
		out[i] = sin(phase) + 0.3 * sin(2.0 * phase) + 0.14 * sin(3.0 * phase)
	return out


## Lights on: the "whoop whoop" a trooper gives you.
func siren_whoop() -> PackedFloat32Array:
	var n := int(RATE * 0.72)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := fmod(t, 0.36) / 0.36
		phase += TAU * (550.0 + 1050.0 * pow(u, 0.55)) / RATE
		var env := minf(u / 0.05, 1.0) * minf((1.0 - u) / 0.12, 1.0)
		out[i] = (sin(phase) + 0.3 * sin(2.0 * phase) + 0.14 * sin(3.0 * phase)) * env
	return out


# --- Props ---------------------------------------------------------------------------

## A car horn: two notes about a major third apart. `double` honks twice.
func horn(seconds: float, double: bool) -> PackedFloat32Array:
	var n := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var gap := double and t > 0.28 and t < 0.36
		var env := minf(t / 0.008, 1.0) * minf((seconds - t) / 0.03, 1.0)
		if double:
			env *= minf(absf(t - 0.32) / 0.04, 1.0)  # soften the edges of the gap
		out[i] = 0.0 if gap else (_buzz(392.0, t, 3) + _buzz(494.0, t, 3)) * 0.5 * env
	return out


## The TV censor bleep: a flat 1 kHz tone.
func bleep() -> PackedFloat32Array:
	return _tone(0.55, func(t: float) -> float: return sin(TAU * 1000.0 * t))


## High beams snapping on: a low thump that drops in pitch.
func whoomp() -> PackedFloat32Array:
	var n := int(RATE * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(150.0, 42.0, minf(t / 0.3, 1.0)) / RATE
		out[i] = sin(phase) * exp(-t * 7.0)
	return out


## The radar detector's chirp.
func radar_beep() -> PackedFloat32Array:
	return _tone(0.08, func(t: float) -> float: return sin(TAU * 2400.0 * t))


# --- Helpers ------------------------------------------------------------------------

func _tone(seconds: float, sample: Callable) -> PackedFloat32Array:
	var n := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = sample.call(float(i) / RATE)
	return out


## A soft square-ish wave (odd harmonics only), like a cheap horn or beeper.
static func _buzz(freq: float, t: float, harmonics: int) -> float:
	var x := 0.0
	for h in harmonics:
		var k := 2 * h + 1
		x += sin(TAU * freq * k * t) / k
	return x


## A brass-ish tone: all harmonics, rolled off by `bright` (0 dull .. 1 blaring).
static func _brass(freq: float, t: float, bright: float) -> float:
	return _brass_phase(TAU * freq * t, bright)


static func _brass_phase(phase: float, bright: float) -> float:
	var x := 0.0
	var amp := 1.0
	for k in range(1, 11):
		x += sin(phase * k) * amp / k
		amp *= bright
	return x


## Filtered noise that loops seamlessly: the tail is cross-faded into the head.
func _loop_noise(n: int, filter: Biquad) -> PackedFloat32Array:
	var fade := int(RATE * 0.08)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	for i in n + fade:
		raw[i] = filter.process(rng.randf_range(-1.0, 1.0))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i]
	for i in fade:
		var u := float(i) / fade
		out[i] = raw[i] * u + raw[n + i] * (1.0 - u)
	return out


## Normalizes, adds short fades (one-shots only; loops must stay seamless) and
## writes 16-bit mono PCM plus loop-aware import settings.
func _save(sound_name: String, samples: PackedFloat32Array) -> void:
	var looped := sound_name in LOOPS
	var peak := 0.0
	for v in samples:
		peak = maxf(peak, absf(v))
	var gain := PEAK / maxf(peak, 0.0001)
	var n := samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := samples[i] * gain
		if not looped:
			var t := float(i) / RATE
			v *= minf(minf(t / 0.002, float(n - 1 - i) / RATE / 0.01), 1.0)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	var path := OUT + sound_name + ".wav"
	wav.save_to_wav(ProjectSettings.globalize_path(path))
	var import := FileAccess.open(ProjectSettings.globalize_path(path + ".import"), FileAccess.WRITE)
	import.store_string(IMPORT_TEMPLATE % [path, 2 if looped else 1, n if looped else -1])


## Uncompressed (plays the same on every platform, including the web's sample
## playback), no trimming or normalizing (that would break loop points).
const IMPORT_TEMPLATE := """[remap]

importer="wav"
type="AudioStreamWAV"

[deps]

source_file="%s"

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=%d
edit/loop_begin=0
edit/loop_end=%d
compress/mode=0
"""


## RBJ-cookbook biquad filter (lowpass, highpass, bandpass), one sample at a time.
class Biquad:
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	static func lowpass(freq: float, q: float) -> Biquad:
		var f := Biquad.new()
		var w := TAU * freq / RATE
		var alpha := sin(w) / (2.0 * q)
		f._coeffs(0.5 * (1.0 - cos(w)), 1.0 - cos(w), 0.5 * (1.0 - cos(w)), 1.0 + alpha, -2.0 * cos(w), 1.0 - alpha)
		return f

	static func highpass(freq: float, q: float) -> Biquad:
		var f := Biquad.new()
		var w := TAU * freq / RATE
		var alpha := sin(w) / (2.0 * q)
		f._coeffs(0.5 * (1.0 + cos(w)), -(1.0 + cos(w)), 0.5 * (1.0 + cos(w)), 1.0 + alpha, -2.0 * cos(w), 1.0 - alpha)
		return f

	static func bandpass(freq: float, q: float) -> Biquad:
		var f := Biquad.new()
		f.set_bandpass(freq, q)
		return f

	func set_bandpass(freq: float, q: float) -> void:
		var w := TAU * freq / RATE
		var alpha := sin(w) / (2.0 * q)
		_coeffs(alpha, 0.0, -alpha, 1.0 + alpha, -2.0 * cos(w), 1.0 - alpha)

	func _coeffs(nb0: float, nb1: float, nb2: float, a0: float, na1: float, na2: float) -> void:
		b0 = nb0 / a0
		b1 = nb1 / a0
		b2 = nb2 / a0
		a1 = na1 / a0
		a2 = na2 / a0

	func process(x: float) -> float:
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y
