extends Node
## Music and volume for the whole game.
##
## Buses: Master, with Music and SFX feeding it. The soundtrack loops on the
## Music bus and keeps playing across scene changes and while paused. The music
## and effects volumes and the mute switch (which silences everything) are saved
## to user://settings.cfg, which on the web lives in the browser's storage.
## M (or the gamepad's Back/Select button) toggles mute from anywhere.
##
## Every button in the game clicks when pressed (set a button's "sfx" meta to
## another sound name, or to &"" for silence). Stingers can duck the music.

signal changed

const MUSIC_PATH := "res://assets/audio/music/highway_momentum.mp3"
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_VOLUME := 0.6
const DEFAULT_SFX_VOLUME := 0.8

## 0..1, linear (the slider's value).
var music_volume := DEFAULT_VOLUME
var sfx_volume := DEFAULT_SFX_VOLUME
var muted := false
## Tests turn this off so they don't overwrite the player's settings file.
var save_enabled := true

var _player: AudioStreamPlayer
var _duck_db := 0.0
var _duck_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses([&"Music", &"SFX"])
	_load()
	var music: AudioStreamMP3 = load(MUSIC_PATH)
	music.loop = true
	_player = AudioStreamPlayer.new()
	_player.name = "Music"
	_player.stream = music
	_player.bus = &"Music"
	add_child(_player)
	_apply()
	# Headless runs (tests, exports) have no audio output; a stream played there
	# is never mixed, so it would never be cleaned up.
	if DisplayServer.get_name() != "headless":
		_player.play()
	get_tree().node_added.connect(_on_node_added)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mute"):
		toggle_mute()


func music_stream() -> AudioStream:
	return _player.stream if _player else null


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	# Reaching for the slider means you want to hear it.
	if muted and music_volume > 0.0:
		muted = false
	_apply()
	_save()
	changed.emit()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	if muted and sfx_volume > 0.0:
		muted = false
	_apply()
	_save()
	changed.emit()


## Lowers the music by `db` for `hold` seconds, then eases it back (stingers).
func duck(db: float, hold: float) -> void:
	if _duck_tween:
		_duck_tween.kill()
	_set_duck(db)
	_duck_tween = create_tween()
	_duck_tween.tween_interval(hold)
	_duck_tween.tween_method(_set_duck, db, 0.0, 1.2)


func _set_duck(db: float) -> void:
	_duck_db = db
	_apply()


func set_muted(on: bool) -> void:
	muted = on
	_apply()
	_save()
	changed.emit()


func toggle_mute() -> void:
	set_muted(not muted)


func _apply() -> void:
	AudioServer.set_bus_mute(0, muted)
	var music := AudioServer.get_bus_index(&"Music")
	AudioServer.set_bus_mute(music, music_volume <= 0.001)
	# A curve that feels even across the slider (linear amplitude is too steep at the top).
	AudioServer.set_bus_volume_db(music, linear_to_db(maxf(music_volume * music_volume, 0.0001)) + _duck_db)
	var sfx := AudioServer.get_bus_index(&"SFX")
	AudioServer.set_bus_mute(sfx, sfx_volume <= 0.001)
	AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(sfx_volume * sfx_volume, 0.0001)))


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(_on_button_pressed.bind(node))


func _on_button_pressed(button: BaseButton) -> void:
	var sound: StringName = button.get_meta(&"sfx", &"click")
	if sound != &"":
		Sfx.play(self, sound, -10.0 if sound == &"click" else -6.0)


## Adds the missing buses, each sending to Master. They're added in one go by
## raising bus_count: on the web, add_bus() puts each new bus in the wrong slot of
## the browser's mirror of the bus list (Godot 4.4), which routes the sound in a
## loop that never reaches the speakers.
func _setup_buses(names: Array[StringName]) -> void:
	var missing := names.filter(func(n: StringName) -> bool: return AudioServer.get_bus_index(n) < 0)
	var first := AudioServer.bus_count
	AudioServer.bus_count = first + missing.size()
	for i in missing.size():
		AudioServer.set_bus_name(first + i, missing[i])
		AudioServer.set_bus_send(first + i, &"Master")


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	music_volume = clampf(float(config.get_value("audio", "music_volume", DEFAULT_VOLUME)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", DEFAULT_SFX_VOLUME)), 0.0, 1.0)
	muted = bool(config.get_value("audio", "muted", false))


func _save() -> void:
	if not save_enabled:
		return
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep any other sections
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "muted", muted)
	config.save(SETTINGS_PATH)
