class_name Sfx
extends RefCounted
## Sound effects. The sounds are WAV files in assets/audio/sfx/, synthesized by
## tools/make_sfx.gd (swap any of them for a real recording with the same name).
## Everything plays on the SFX bus (see AudioManager for its volume).
##
## Headless runs (tests, the balance bot) have no audio output, so nothing is
## actually played there; the names are recorded in `heard` instead, so tests
## can check what the player would have heard.

const DIR := "res://assets/audio/sfx/"
## Every sound the game uses (tests check the files exist).
const NAMES: Array[StringName] = [
	&"engine_v8", &"engine_six", &"engine_ev", &"tire_squeal", &"siren", &"siren_whoop",
	&"crash", &"bump", &"scrape", &"whoosh", &"bonus", &"beep", &"beep_go", &"tick",
	&"click", &"confirm", &"win", &"fail", &"ticket", &"firework", &"horn", &"horn_short",
	&"bleep", &"whoomp", &"radar_beep",
]
## Distance (meters) at which a sound out on the road is heard at full volume.
const NEAR := 12.0
## Beyond this, it's too far away to bother playing.
const FAR := 220.0
## How many recent names `heard` keeps.
const HEARD_MAX := 64

static var heard: Array[StringName] = []
static var _cache: Dictionary = {}
static var _silent := -1


static func stream(sound: StringName) -> AudioStream:
	if not _cache.has(sound):
		_cache[sound] = load(DIR + String(sound) + ".wav")
	return _cache[sound]


## Fire-and-forget playback; the player frees itself when done.
static func play(parent: Node, sound: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if is_silent():
		_remember(sound)
		return
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = stream(sound)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## A sound out on the road, `distance` meters from the player: quieter the
## farther away it is, and skipped once it's too far to hear.
static func play_at(parent: Node, sound: StringName, distance: float, volume_db := 0.0, pitch := 1.0) -> void:
	if distance > FAR:
		return
	play(parent, sound, volume_db + distance_db(distance), pitch)


## Volume change for a sound `distance` meters away (0 dB within NEAR).
static func distance_db(distance: float) -> float:
	return -20.0 * log(maxf(distance, NEAR) / NEAR) / log(10.0)


## A looping player for engines, tire squeal and sirens. The caller adds it to
## the tree, then drives its volume and pitch (see `set_loop`).
static func loop_player(sound: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = stream(sound)
	player.volume_db = -80.0
	return player


## Fades a loop in or out: `level` 0 stops it, anything above starts it.
## Volume is `level` (0..1) on top of `volume_db`.
static func set_loop(player: AudioStreamPlayer, level: float, volume_db := 0.0, pitch := 1.0) -> void:
	if player == null or not player.is_inside_tree():
		return
	player.pitch_scale = clampf(pitch, 0.05, 4.0)
	if level <= 0.001:
		if player.playing:
			player.stop()
		player.set_meta(&"silent_loop", false)
		return
	player.volume_db = volume_db + linear_to_db(level)
	if is_looping(player):
		return
	if is_silent():
		player.set_meta(&"silent_loop", true)
		_remember(_name_of(player.stream))
	else:
		player.play()


## Whether a loop is running (or would be, in a headless run).
static func is_looping(player: AudioStreamPlayer) -> bool:
	return player != null and (player.playing or bool(player.get_meta(&"silent_loop", false)))


static func is_silent() -> bool:
	if _silent < 0:
		_silent = 1 if DisplayServer.get_name() == "headless" else 0
	return _silent == 1


static func _remember(sound: StringName) -> void:
	heard.append(sound)
	if heard.size() > HEARD_MAX:
		heard.remove_at(0)


static func _name_of(audio: AudioStream) -> StringName:
	return StringName(audio.resource_path.get_file().get_basename()) if audio else &""
