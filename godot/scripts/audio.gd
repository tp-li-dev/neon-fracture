extends Node

## Compatibility: other modules call Audio.Sound.play("name") as in the original.
var Sound: Node = self
## Audio — port of createGameAudio / beep / Sound (原作 5449-5680).
## Sounds are procedural oscillator tones (sine/square/triangle/sawtooth with an
## exponential frequency slide, attack/hold/exponential-decay envelope, optional
## biquad lowpass). Each distinct tone is rendered once into an AudioStreamWAV
## (16-bit mono 22050 Hz) and played through a fixed pool of AudioStreamPlayers.
## Bus gains (master x channel) are applied per player via volume_db.
## Not ported: the DynamicsCompressor, AnalyserNode metering, AudioContext
## resume/gesture state machine (Godot handles activation), clock-stall watchdog.

const SAMPLE_RATE: int = 22050
const MAX_VOICES: int = 24
const BUSES: Array = ["shots", "drones", "skills", "feedback", "ui"]
const CHANNEL_CAPS: Dictionary = {"shots": 4, "drones": 2, "skills": 8, "feedback": 6, "ui": 4}
const PREF_KEY: String = "nf_audio_v1"
const WAVEFORMS: Array = ["sine", "triangle", "sawtooth", "square"]

const DEFAULTS: Dictionary = {"master": 65, "shots": 70, "drones": 45, "skills": 80, "feedback": 85, "ui": 65, "muted": false}

const SOUNDS: Dictionary = {
	"shot": {"channel": "shots", "freq": 880.0, "duration": .105, "type": "square", "gain": .048, "slide": -420.0, "attack": .003, "hold": .019, "lowpass": 2800.0, "gap": .055, "priority": 3},
	"drone": {"channel": "drones", "freq": 460.0, "duration": .065, "type": "sine", "gain": .04, "slide": -140.0, "gap": .12, "priority": 1},
	"beam": {"channel": "skills", "freq": 640.0, "duration": .28, "type": "sawtooth", "gain": .085, "slide": -480.0, "gap": .10, "priority": 3},
	"charge": {"channel": "skills", "freq": 260.0, "duration": .22, "type": "sine", "gain": .045, "slide": 420.0, "gap": .25, "priority": 2},
	"meteor": {"channel": "skills", "freq": 125.0, "duration": .26, "type": "triangle", "gain": .12, "slide": -85.0, "gap": .095, "priority": 3},
	"explosion": {"channel": "skills", "freq": 165.0, "duration": .18, "type": "triangle", "gain": .10, "slide": -115.0, "gap": .11, "priority": 2},
	"lightning": {"channel": "skills", "freq": 920.0, "duration": .13, "type": "sawtooth", "gain": .04, "slide": -660.0, "gap": .11, "priority": 2},
	"skill": {"channel": "skills", "freq": 420.0, "duration": .18, "type": "triangle", "gain": .09, "slide": 240.0, "gap": .09, "priority": 2},
	"dash": {"channel": "skills", "freq": 160.0, "duration": .14, "type": "sawtooth", "gain": .055, "slide": 440.0, "gap": .12, "priority": 2},
	"hit": {"channel": "feedback", "freq": 96.0, "duration": .18, "type": "sawtooth", "gain": .105, "slide": -52.0, "gap": .12, "priority": 4},
	"shield": {"channel": "feedback", "freq": 790.0, "duration": .12, "type": "sine", "gain": .065, "slide": -240.0, "gap": .1, "priority": 3},
	"break": {"channel": "feedback", "freq": 210.0, "duration": .27, "type": "square", "gain": .055, "slide": -150.0, "gap": .25, "priority": 4},
	"warning": {"channel": "feedback", "freq": 240.0, "duration": .28, "type": "square", "gain": .055, "slide": 180.0, "gap": .65, "priority": 4},
	"boss": {"channel": "feedback", "freq": 105.0, "duration": .40, "type": "sawtooth", "gain": .075, "slide": 80.0, "gap": .6, "priority": 4},
	"kill": {"channel": "feedback", "freq": 300.0, "duration": .07, "type": "triangle", "gain": .045, "slide": 160.0, "gap": .14, "priority": 1},
	"bossKill": {"channel": "feedback", "freq": 340.0, "duration": .32, "type": "triangle", "gain": .11, "slide": 600.0, "gap": .3, "priority": 4},
	"pickup": {"channel": "ui", "freq": 760.0, "duration": .05, "type": "sine", "gain": .035, "slide": 170.0, "gap": .16, "priority": 1},
	"level": {"channel": "ui", "freq": 540.0, "duration": .22, "type": "triangle", "gain": .065, "slide": 380.0, "gap": .45, "priority": 3},
	"card": {"channel": "ui", "freq": 560.0, "duration": .18, "type": "triangle", "gain": .07, "slide": 300.0, "gap": .14, "priority": 3},
	"click": {"channel": "ui", "freq": 500.0, "duration": .055, "type": "sine", "gain": .04, "slide": 110.0, "gap": .07, "priority": 1},
	"start": {"channel": "ui", "freq": 250.0, "duration": .22, "type": "triangle", "gain": .085, "slide": 450.0, "gap": .3, "priority": 3},
	"result": {"channel": "ui", "freq": 330.0, "duration": .35, "type": "triangle", "gain": .085, "slide": 430.0, "gap": .4, "priority": 4},
	"death": {"channel": "ui", "freq": 145.0, "duration": .40, "type": "triangle", "gain": .09, "slide": -105.0, "gap": .4, "priority": 4},
	"test": {"channel": "ui", "freq": 520.0, "duration": .42, "type": "sine", "gain": .12, "slide": 160.0, "gap": .45, "priority": 4},
}

var prefs: Dictionary = DEFAULTS.duplicate()
var scene: String = "menu"
var gated: bool = false                 #原作 mutedByPage (background / pagehide)
var counts: Dictionary = {"played": 0, "blocked": 0, "muted": 0, "rateLimited": 0, "limited": 0, "stolen": 0, "ended": 0, "errors": 0, "rebuilds": 0}
var played_by_kind: Dictionary = {}

var _pool: Array = []                   # AudioStreamPlayer[MAX_VOICES]
var _voices: Array = []                 # active voice Dictionaries
var _voice_id: int = 0
var _rate_marks: Dictionary = {}        # key -> last play time (s)
var _named_cache: Dictionary = {}       # sound name -> AudioStreamWAV (no override)
var _var_cache: Dictionary = {}         # signature -> AudioStreamWAV (overrides / beep)
var _audition_serial: int = 0


func _ready() -> void:
	_load_prefs()
	_init_pool()
	for name in SOUNDS.keys():
		_named_cache[name] = _render(SOUNDS[name])


func _init_pool() -> void:
	if not _pool.is_empty():
		return
	for i in MAX_VOICES:
		var pl := AudioStreamPlayer.new()
		pl.bus = &"Master"
		add_child(pl)
		_pool.append(pl)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		background()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		foreground()


# ---------------------------------------------------------------- public API

## 原作 Sound.gesture / unlock. Godot handles audio activation itself; kept for parity.
func unlock() -> bool:
	return true


func gesture(_reason: String = "gesture") -> bool:
	return unlock()


## 原作 Sound.play(name, override). Override keys merge over the named sound's spec.
func play(name: String, override: Dictionary = {}) -> bool:
	if not SOUNDS.has(name):
		return false
	var def: Dictionary = SOUNDS[name]
	if override.is_empty():
		return _play_tone(def, name, false, name)
	var merged: Dictionary = def.duplicate()
	for k in override.keys():
		merged[k] = override[k]
	return _play_tone(merged, name, false, "")


## 原作 beep(freq, duration, type, gain, slide) (menu cues, UI bus).
func beep(freq: float = 440.0, duration: float = .05, type: String = "sine", gain: float = .03, slide: float = 0.0) -> bool:
	return _play_tone({"freq": freq, "duration": duration, "type": type, "gain": gain, "slide": slide,
		"channel": "ui", "gap": .065, "priority": 2}, "menu-tone", false, "")


## 原作 Sound.setScene(state). Call with Game.state each change.
func setScene(next: String) -> void:
	if scene == next:
		return
	scene = next
	_audition_serial += 1
	_rate_marks.clear()
	for v in _voices.duplicate():
		if v.audition:
			_dispose(v)
	if next != "playing":
		for k in ["shots", "drones", "skills", "feedback"]:
			stop_all(k)


## 原作 Sound.setPreference. k: "master"|bus name (0..100) or "muted" (bool).
func setPreference(k: String, value: Variant) -> bool:
	if k == "muted":
		prefs["muted"] = bool(value)
	elif (k == "master" or BUSES.has(k)) and is_finite(float(value)):
		prefs[k] = clampf(float(value), 0.0, 100.0)
	else:
		return false
	_apply_gains()
	if prefs["muted"] or prefs["master"] == 0:
		stop_all()
	if BUSES.has(k) and prefs[k] == 0:
		stop_all(k)
	_save_prefs()
	return true


func preferences() -> Dictionary:
	return prefs.duplicate()


func set_muted(on: bool) -> bool:
	return setPreference("muted", on)


func set_master(value: float) -> bool:
	return setPreference("master", value)


## 原作 Sound.stopAll(channel?)
func stop_all(channel: String = "") -> void:
	for v in _voices.duplicate():
		if channel == "" or v.channel == channel:
			_dispose(v)


## 原作 Sound.background / foreground (page hidden). Stops and gates playback.
func background() -> void:
	gated = true
	_audition_serial += 1
	_rate_marks.clear()
	stop_all()


func foreground() -> void:
	gated = false


## 原作 Sound.recover / rebuild: drop all voices (no AudioContext to recreate in Godot).
func recover() -> bool:
	return unlock()


func rebuild() -> bool:
	counts["rebuilds"] += 1
	stop_all()
	_rate_marks.clear()
	return true


## 原作 Sound.test(name): audition 'test' (1 hit), 'shot' or 'drone' (5 hits) at their bus volume.
func test(name: String = "test") -> bool:
	if not ["test", "shot", "drone"].has(name):
		return false
	_audition_serial += 1
	var token: int = _audition_serial
	unlock()
	var spec: Dictionary = SOUNDS[name]
	var channel: String = spec.channel
	if prefs["muted"] or prefs["master"] <= 0 or prefs[channel] <= 0:
		return false
	var n: int = 1 if name == "test" else 5
	var count: int = 0
	for i in n:
		if gated or token != _audition_serial:
			return count > 0
		if _play_tone(spec, name, true, name):
			count += 1
		if i < n - 1:
			await get_tree().create_timer(.14 if name == "drone" else .105).timeout
	return count > 0


## 原作 Sound.sample() (subset) for diagnostics UI.
func sample() -> Dictionary:
	return {
		"state": "running" if not gated else "suspended",
		"scene": scene,
		"muted": prefs["muted"],
		"master": prefs["master"],
		"preferences": prefs.duplicate(),
		"needsGesture": false,
		"background": gated,
		"voices": _voices.size(),
		"maxVoices": MAX_VOICES,
		"counts": counts.duplicate(),
		"playedByKind": played_by_kind.duplicate(),
	}


# ---------------------------------------------------------------- internals

func _num(v: Variant, fallback: float) -> float:
	# JS `Number(v) || fallback`
	var f: float = float(v) if v != null else 0.0
	return f if (f != 0.0 and is_finite(f)) else fallback


func _nz(d: Dictionary, k: String, fallback: float) -> float:
	# JS `d[k] ?? fallback`
	var v: Variant = d.get(k, null)
	return fallback if v == null else float(v)


func _drop(reason: String) -> bool:
	counts[reason] = int(counts.get(reason, 0)) + 1
	return false


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _db_for(channel: String) -> float:
	var lin: float = (prefs["master"] / 100.0) * (prefs[channel] / 100.0)
	return linear_to_db(maxf(lin, .0001))


func _apply_gains() -> void:
	for v in _voices:
		var pl: AudioStreamPlayer = v.pl
		pl.volume_db = _db_for(v.channel)


func _dispose(v: Dictionary, stop: bool = true) -> void:
	if not _voices.has(v):
		return
	_voices.erase(v)
	var pl: AudioStreamPlayer = v.pl
	if stop and pl.playing:
		pl.stop()
	counts["ended"] += 1


func _free_player() -> AudioStreamPlayer:
	for pl in _pool:
		var busy := false
		for v in _voices:
			if v.pl == pl:
				busy = true
				break
		if not busy:
			return pl
	return null


func _play_tone(spec: Dictionary, key: String, audition: bool, named: String) -> bool:
	var channel: String = str(spec.get("channel", "ui"))
	if not BUSES.has(channel):
		channel = "ui"
	if prefs["muted"] or prefs["master"] <= 0 or prefs[channel] <= 0:
		return _drop("muted")
	if gated:
		return _drop("blocked")
	if channel != "ui" and scene != "playing" and not audition:
		return _drop("blocked")
	var now: float = _now()
	var gap: float = maxf(0.0, _nz(spec, "gap", .07))
	if _rate_marks.has(key) and now - float(_rate_marks[key]) < gap:
		return _drop("rateLimited")
	var duration: float = clampf(_num(spec.get("duration", .08), .08), .035, 1.2)
	var priority: float = _num(spec.get("priority", 1), 1.0)

	# Retire voices whose time has passed (原作 onended may be late).
	for v in _voices.duplicate():
		if v.end < now - .02:
			_dispose(v)

	var own: Array = _voices.filter(func(v): return v.channel == channel)
	var quota: int = MAX_VOICES if key == "shot" else MAX_VOICES - 2
	if own.size() >= CHANNEL_CAPS[channel] or _voices.size() >= quota:
		var candidates: Array = own if own.size() >= CHANNEL_CAPS[channel] else _voices
		var eligible: Array = []
		for v in candidates:
			if key == "shot":
				if v.priority <= priority:
					eligible.append(v)
			elif v.key != "shot" and v.priority < priority:
				eligible.append(v)
		if eligible.is_empty():
			return _drop("limited")
		eligible.sort_custom(func(a, b): return a.priority < b.priority or (a.priority == b.priority and a.start < b.start))
		_dispose(eligible[0])
		counts["stolen"] += 1

	var pl: AudioStreamPlayer = _free_player()
	if pl == null:
		return _drop("limited")
	pl.stream = _stream_for(spec, named)
	pl.volume_db = _db_for(channel)
	pl.play()
	_voice_id += 1
	_voices.append({"id": _voice_id, "pl": pl, "key": key, "channel": channel, "priority": priority,
		"start": now, "end": now + duration + .012, "audition": audition})
	_rate_marks[key] = now
	counts["played"] += 1
	played_by_kind[key] = int(played_by_kind.get(key, 0)) + 1
	return true


func _stream_for(spec: Dictionary, named: String) -> AudioStreamWAV:
	if named != "" and _named_cache.has(named):
		return _named_cache[named]
	var sig: String = "%s|%s|%s|%s|%s|%s|%s|%s" % [spec.get("freq"), spec.get("duration"), spec.get("type"),
		spec.get("gain"), spec.get("slide"), spec.get("attack"), spec.get("hold"), spec.get("lowpass")]
	if _var_cache.has(sig):
		return _var_cache[sig]
	if _var_cache.size() >= 128:
		_var_cache.clear()
	var wav: AudioStreamWAV = _render(spec)
	_var_cache[sig] = wav
	return wav


## Render one tone to 16-bit mono PCM, matching the Web Audio graph of 原作 playTone:
## osc (freq ramp exp to freq+slide over duration) -> [lowpass] -> gain envelope.
func _render(spec: Dictionary) -> AudioStreamWAV:
	var freq: float = clampf(_num(spec.get("freq", 440.0), 440.0), 35.0, 8000.0)
	var duration: float = clampf(_num(spec.get("duration", .08), .08), .035, 1.2)
	var type: String = str(spec.get("type", "sine"))
	if not WAVEFORMS.has(type):
		type = "sine"
	var amp: float = clampf(_num(spec.get("gain", .03), .03), .0001, .18)
	var slide: float = float(spec.get("slide", 0.0))
	var target: float = clampf(freq + slide, 30.0, 10000.0)
	var attack: float = minf(duration * .25, maxf(.001, _nz(spec, "attack", .006)))
	var hold: float = minf(duration * .35, maxf(0.0, _num(spec.get("hold", 0.0), 0.0)))
	var hold_end: float = attack + hold
	var lowpass: float = float(spec.get("lowpass", 0.0))
	var use_lp: bool = lowpass != 0.0

	# RBJ lowpass biquad (Q .6) when requested.
	var b0: float = 1.0; var b1: float = 0.0; var b2: float = 0.0; var a1: float = 0.0; var a2: float = 0.0
	if use_lp:
		var fc: float = clampf(lowpass, 10.0, SAMPLE_RATE * .49)
		var w0: float = TAU * fc / SAMPLE_RATE
		var alpha: float = sin(w0) / (2.0 * .6)
		var cw: float = cos(w0)
		var a0: float = 1.0 + alpha
		b0 = (1.0 - cw) / 2.0 / a0
		b1 = (1.0 - cw) / a0
		b2 = b0
		a1 = -2.0 * cw / a0
		a2 = (1.0 - alpha) / a0
	var x1: float = 0.0; var x2: float = 0.0; var y1: float = 0.0; var y2: float = 0.0

	var total: float = duration + .008
	var count: int = int(ceil(total * SAMPLE_RATE))
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var cycles: float = 0.0
	var log_ratio: float = log(target / freq)
	var floor_gain: float = .0001
	var log_floor: float = log(floor_gain / amp)
	for i in count:
		var t: float = i / float(SAMPLE_RATE)
		# frequency: exponential ramp freq -> target over duration, then held
		var tt: float = minf(t, duration)
		var f: float = freq * exp(log_ratio * tt / duration) if slide != 0.0 else freq
		cycles += f / SAMPLE_RATE
		var frac: float = fposmod(cycles, 1.0)
		var x: float = 0.0
		match type:
			"sine": x = sin(TAU * frac)
			"square": x = 1.0 if frac < .5 else -1.0
			"triangle":
				if frac < .25: x = 4.0 * frac
				elif frac < .75: x = 2.0 - 4.0 * frac
				else: x = 4.0 * frac - 4.0
			_: x = 2.0 * frac - 1.0   # sawtooth
		if use_lp:
			var y: float = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
			x2 = x1; x1 = x; y2 = y1; y1 = y
			x = y
		# envelope: linear attack -> hold -> exponential decay to .0001 at duration -> linear to 0 by +.008
		var env: float
		if t < attack:
			env = amp * t / attack
		elif t < hold_end:
			env = amp
		elif t < duration:
			var k: float = (t - hold_end) / maxf(duration - hold_end, .000001)
			env = amp * exp(log_floor * k)
		elif t < duration + .008:
			env = floor_gain * (1.0 - (t - duration) / .008)
		else:
			env = 0.0
		var s: int = clampi(int(round(clampf(x * env, -1.0, 1.0) * 32767.0)), -32768, 32767)
		bytes.encode_s16(i * 2, s)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


func _load_prefs() -> void:
	prefs = DEFAULTS.duplicate()
	var raw: String = ""
	var meta: Node = get_node_or_null("/root/Meta")
	if meta and meta.has_method("storage_get"):
		raw = str(meta.call("storage_get", PREF_KEY))
	if raw == "" or raw == "<null>":
		return
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return
	for k in ["master"] + BUSES:
		var v: Variant = parsed.get(k, null)
		if (v is float or v is int) and is_finite(float(v)):
			prefs[k] = clampf(float(v), 0.0, 100.0)
	prefs["muted"] = parsed.get("muted", false) == true
	if not (parsed.get("drones", null) is float or parsed.get("drones", null) is int):
		prefs["drones"] = minf(DEFAULTS["drones"], prefs["shots"])


func _save_prefs() -> void:
	var meta: Node = get_node_or_null("/root/Meta")
	if meta and meta.has_method("storage_set"):
		meta.call("storage_set", PREF_KEY, JSON.stringify(prefs))
