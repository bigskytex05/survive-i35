extends TestSuite
## Music, sound effects and volume: the soundtrack loops on its own bus, the
## sliders and the mute switch drive the buses, M toggles mute, the controls are
## on screen in the race, the pause menu and the garage, and the race makes the
## right noises at the right moments (headless runs record them in Sfx.heard).

var _saved_volume := 0.0
var _saved_sfx := 0.0
var _saved_muted := false


func _keep_settings() -> void:
	AudioManager.save_enabled = false
	_saved_volume = AudioManager.music_volume
	_saved_sfx = AudioManager.sfx_volume
	_saved_muted = AudioManager.muted


func _restore_settings() -> void:
	AudioManager.set_music_volume(_saved_volume)
	AudioManager.set_sfx_volume(_saved_sfx)
	AudioManager.set_muted(_saved_muted)
	AudioManager.save_enabled = true


func test_music_loops_on_its_own_bus() -> void:
	var music := AudioServer.get_bus_index(&"Music")
	check(music > 0 and AudioServer.get_bus_index(&"SFX") > 0, "Music and SFX buses exist")
	var stream := AudioManager.music_stream() as AudioStreamMP3
	check(stream != null and stream.loop, "the soundtrack is loaded and loops")
	check(AudioManager.get_node("Music").bus == &"Music", "on the Music bus")


func test_slider_and_mute_drive_the_buses() -> void:
	_keep_settings()
	var music := AudioServer.get_bus_index(&"Music")
	AudioManager.set_muted(false)
	AudioManager.set_music_volume(0.5)
	check_near(AudioServer.get_bus_volume_db(music), linear_to_db(0.25), 0.01, "half the slider")
	check(not AudioServer.is_bus_mute(music) and not AudioServer.is_bus_mute(0), "audible")
	AudioManager.set_music_volume(0.0)
	check(AudioServer.is_bus_mute(music), "all the way down silences the music")
	AudioManager.set_muted(true)
	check(AudioServer.is_bus_mute(0), "mute silences everything")
	AudioManager.set_music_volume(0.3)
	check(not AudioManager.muted and not AudioServer.is_bus_mute(0), "touching the slider unmutes")
	var event := InputEventAction.new()
	event.action = &"toggle_mute"
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	check(AudioManager.muted, "M toggles mute")
	_restore_settings()


func test_controls_are_easy_to_find() -> void:
	_keep_settings()
	var race: Race = await start_race(make_level(), false)
	var controls: AudioControls = race.hud._audio
	check(controls != null and controls.is_visible_in_tree(), "on the race HUD")
	AudioManager.set_music_volume(0.8)
	check_near(controls.slider().value, 0.8, 0.001, "the HUD slider follows the volume")
	controls.slider().value = 0.4
	check_near(AudioManager.music_volume, 0.4, 0.001, "and sets it")
	controls.mute_button().pressed.emit()
	check(AudioManager.muted, "the speaker button mutes")
	check(not race.get_node("PauseMenu").find_children("*", "AudioControls", true, false).is_empty(), "in the pause menu")
	await end_race(race)
	var garage: Garage = load("res://scenes/main/Garage.tscn").instantiate()
	garage.change_scene_on_go = false
	add_child(garage)
	await get_tree().process_frame
	check(not garage.find_children("*", "AudioControls", true, false).is_empty(), "and in the garage")
	garage.queue_free()
	await get_tree().process_frame
	GameState.clear()
	_restore_settings()


func test_every_sound_exists() -> void:
	for sound in Sfx.NAMES:
		var stream := Sfx.stream(sound) as AudioStreamWAV
		check(stream != null and stream.get_length() > 0.03, "%s.wav loads" % sound)
		if stream == null:
			continue
		var loops := sound in [&"engine_v8", &"engine_six", &"engine_ev", &"tire_squeal", &"siren"]
		check((stream.loop_mode == AudioStreamWAV.LOOP_FORWARD) == loops,
			"%s %s" % [sound, "loops" if loops else "plays once"])
	for path in ["res://data/cars/truck.tres", "res://data/cars/suv.tres", "res://data/cars/ev.tres"]:
		var car: CarData = load(path)
		check(car.engine_sound in Sfx.NAMES, "%s has an engine sound" % car.display_name)


func test_effects_slider_drives_the_sfx_bus() -> void:
	_keep_settings()
	var sfx := AudioServer.get_bus_index(&"SFX")
	AudioManager.set_muted(false)
	AudioManager.set_sfx_volume(0.5)
	check_near(AudioServer.get_bus_volume_db(sfx), linear_to_db(0.25), 0.01, "half the effects slider")
	AudioManager.set_sfx_volume(0.0)
	check(AudioServer.is_bus_mute(sfx), "all the way down silences the effects")
	var menu := (load("res://scenes/ui/PauseMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	var controls: AudioControls = menu.find_children("*", "AudioControls", true, false)[0]
	check(controls.effects() != null, "the pause menu has an effects slider")
	if controls.effects():
		controls.effects().value = 0.7
		check_near(AudioManager.sfx_volume, 0.7, 0.001, "which sets the effects volume")
	menu.queue_free()
	await get_tree().process_frame
	_restore_settings()


func test_buttons_click() -> void:
	var button := Button.new()
	add_child(button)
	Sfx.heard.clear()
	button.pressed.emit()
	check(&"click" in Sfx.heard, "pressing a button clicks")
	button.set_meta(&"sfx", &"")
	Sfx.heard.clear()
	button.pressed.emit()
	check(Sfx.heard.is_empty(), "unless it opts out")
	button.queue_free()


func test_engine_note_climbs_through_the_gears() -> void:
	var suv: CarData = load("res://data/cars/suv.tres")
	var ev: CarData = load("res://data/cars/ev.tres")
	check_near(RaceAudio.engine_pitch(suv, 0.0), suv.engine_pitch.x, 0.001, "idle at a standstill")
	check(RaceAudio.engine_pitch(suv, 0.19) > RaceAudio.engine_pitch(suv, 0.05), "revs up in first gear")
	check(RaceAudio.engine_pitch(suv, 0.21) < RaceAudio.engine_pitch(suv, 0.19), "drops at the shift")
	check_near(RaceAudio.engine_pitch(suv, 1.0), suv.engine_pitch.y, 0.001, "tops out at top speed")
	var rising := true
	for i in 20:
		rising = rising and RaceAudio.engine_pitch(ev, (i + 1) / 20.0) > RaceAudio.engine_pitch(ev, i / 20.0)
	check(rising, "the EV has no gears: its whine just rises")


func test_race_sounds() -> void:
	Sfx.heard.clear()
	var race: Race = await start_race(make_level(), true, 3.0)
	await hold([], 200)
	check(Sfx.heard.count(&"beep") == 3, "three countdown beeps")
	check(&"beep_go" in Sfx.heard, "and a GO beep")
	check(&"engine_six" in Sfx.heard and Sfx.is_looping(race.audio.engine()), "the SUV's engine runs")
	var idle := race.audio.engine().pitch_scale
	await hold([&"accelerate"], 90)
	check(race.audio.engine().pitch_scale > idle, "and revs as it speeds up")
	# A hard swerve at speed squeals the tires.
	await hold([&"accelerate", &"steer_left"], 30)
	check(Sfx.is_looping(race.audio.squeal()), "hard swerve: tires squeal")
	await hold([], 60)
	# A spin-out crashes.
	race.car.spin_out(1.0)
	check(&"crash" in Sfx.heard, "spin-out: crash")
	await hold([], 100)
	# A near miss whooshes and chimes.
	race.traffic.near_miss.emit(null)
	check(&"whoosh" in Sfx.heard and &"bonus" in Sfx.heard, "near miss: whoosh and chime")
	# The last ten seconds tick, and running out plays the sad trombone.
	race.clock.time_left = 3.5
	await hold([], 40)
	check(&"tick" in Sfx.heard, "the clock ticks at the end")
	race.clock.time_left = 0.01
	await hold([], 5)
	check(&"fail" in Sfx.heard, "out of time: sad trombone")
	await end_race(race)


func test_finish_fanfare() -> void:
	Sfx.heard.clear()
	var race: Race = await start_race(make_level(300.0, 120.0), false)
	place_player(race.car, race.road, 290.0, RoadSpec.lane_center(1), 30.0)
	await hold([&"accelerate"], 60)
	check(race.state == Race.State.FINISHED, "crossed the line")
	check(&"win" in Sfx.heard, "finish: fanfare")
	await end_race(race)
