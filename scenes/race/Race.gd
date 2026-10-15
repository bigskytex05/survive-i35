class_name Race
extends Node3D
## One race: a countdown, then the clock runs while you drive the level's
## stretch of I-35 through traffic. Cross the finish line before it hits zero.
##
## The race owns the flow (COUNTDOWN -> RACING -> FINISHED or FAILED) and wires
## the pieces together: road, player car, prop, traffic, clock, roadside
## markers, police (speed traps and chases), HUD, sound (RaceAudio) and the
## results screen. The car, paint and prop come from the
## garage (GameState); a race started on its own uses the ones set on the scene.
##
## The level's set pieces make each trip's ends its own: a StartSite in the
## start town and a FinishSite at the destination (Kickoff ends in a stadium
## parking lot, which you have to exit the highway to reach). After a site
## finish the camera swings round to show the place off before the results.

enum State { COUNTDOWN, RACING, FINISHED, FAILED }

const NEAR_MISS_BONUS := 0.5
const RESULTS_DELAY := 1.6
## Longer when there's a destination to look at.
const SHOWCASE_DELAY := 3.8
## The chase camera tilts up over the last stretch to a site finish.
const REVEAL_FROM := 520.0
const REVEAL_FULL := 140.0
const SPIN_LINES: Array[String] = ["SPUN OUT!", "WHOOPS!", "Y'ALL OK?", "SPUN OUT!", "BLESS YOUR HEART"]
const GARAGE_SCENE := "res://scenes/main/Garage.tscn"

@export var level: LevelData
@export var car_data: CarData
## Transparent = the car's default paint.
@export var paint := Color(0, 0, 0, 0)
@export var prop_data: PropData
## Take level, car, paint and prop from GameState when the garage set them.
@export var use_loadout := true
@export_range(0, 2) var start_lane := 1
## Posted limit shown on the HUD (construction zones lower it from Phase 3).
@export var speed_limit_mph := 75
## Set to 0 to start racing straight away (tests).
@export var countdown_seconds := 3.0
@export var traffic_enabled := true
## 0 = speed traps in new spots every run.
@export var police_seed := 0

var state := State.COUNTDOWN
var route: RouteMap
var stats := RaceStats.new()
var start_site: StartSite
var finish_site: FinishSite
var audio: RaceAudio
var police: Police
var ticket: TicketCard

var _countdown_left := 0.0
var _countdown_shown := -1
var _results_in := -1.0
var _jams_announced: Array[int] = []

@onready var road: RoadManager = $RoadManager
@onready var car: PlayerCar = $PlayerCar
@onready var camera: RaceCamera = $RaceCamera
@onready var ground: Ground = $Ground
@onready var traffic: TrafficSpawner = $TrafficSpawner
@onready var markers: RouteMarkers = $RouteMarkers
@onready var clock: RaceClock = $RaceClock
@onready var hud: HUD = $HUD
@onready var touch: TouchControls = $TouchControls
@onready var pause_menu: Node = $PauseMenu
@onready var results: ResultsScreen = $ResultsScreen
@onready var props: PropController = $Props


func _ready() -> void:
	if use_loadout and GameState.has_loadout:
		level = GameState.level
		car_data = GameState.car
		paint = GameState.paint
		prop_data = GameState.prop
	route = RouteMap.from_level(level)
	if car_data:
		car.setup(car_data, paint)
	road.clear_zones()
	if level.finish_site:
		# Before the road is built: the site shapes the road around itself.
		finish_site = level.finish_site.instantiate() as FinishSite
		add_child(finish_site)
		finish_site.setup(road, route)
	road.reset()
	road.update_stream(0.0)
	if level.start_site:
		start_site = level.start_site.instantiate() as StartSite
		add_child(start_site)
		start_site.setup(road, route)
	car.road = road
	car.place_at(road.sample(0.0, RoadSpec.lane_center(start_lane)), road.yaw_at(0.0))
	audio = RaceAudio.new()
	audio.name = "Audio"
	add_child(audio)
	camera.target = car
	camera.snap()
	ground.target = car
	markers.setup(road, route, finish_site == null)
	if finish_site:
		markers.posts_until_s = route.distance - finish_site.roadside_clear_before

	var profile := TrafficProfile.for_level(level, route)
	traffic.setup(road, car, profile, speed_limit_mph)
	traffic.feature_paint = level.feature_paint
	traffic.feature_paint_chance = level.feature_paint_chance
	if traffic_enabled:
		traffic.reset()
		car.safe_lane_picker = traffic.safest_lane
	else:
		traffic.process_mode = Node.PROCESS_MODE_DISABLED
	traffic.near_miss.connect(_on_near_miss)
	traffic.slowdown_ahead.connect(_on_slowdown_ahead)
	traffic.road_rage_ko.connect(_on_road_rage_ko)
	police = Police.new()
	police.name = "Police"
	police.process_physics_priority = 15  # after the traffic tick
	add_child(police)
	police.setup(self, police_seed)
	police.chase_started.connect(_on_chase_started)
	police.pulled_over.connect(_on_pulled_over)
	police.escaped.connect(_on_escaped)
	police.trap_dodged.connect(_on_trap_dodged)
	ticket = TicketCard.new()
	ticket.name = "TicketCard"
	add_child(ticket)
	audio.setup(self)

	clock.time_left = level.time_limit
	clock.expired.connect(_fail)
	hud.car = car
	hud.clock = clock
	hud.camera = camera
	props.setup(self, prop_data)
	hud.setup_prop(props)
	touch.set_prop(props)
	stats.prop_id = prop_data.id if prop_data else &""
	hud.setup_route(route)
	hud.set_speed_limit(speed_limit_mph)
	hud.set_touch_mode(touch.is_shown())
	touch.shown_changed.connect(hud.set_touch_mode)
	car.bumped.connect(_on_car_bumped)
	car.spun_out.connect(_on_spun_out)
	pause_menu.restart_pressed.connect(_restart)
	pause_menu.loadout_pressed.connect(_to_garage)
	results.retry_pressed.connect(_restart)
	results.loadout_pressed.connect(_to_garage)

	car.input_enabled = false
	_countdown_left = countdown_seconds
	if countdown_seconds > 0.0:
		hud.show_intro(level.title, "%s to %s  ·  %s" % [route.start_name, route.end_name, RaceClock.format(level.time_limit)],
			level.scenario)
		if start_site:
			camera.intro(start_site.showcase_point(), countdown_seconds)
	else:
		_go()


func _physics_process(delta: float) -> void:
	road.update_stream(car.road_s)
	markers.update(car.road_s)
	if finish_site:
		finish_site.update(car.road_s)
		finish_site.on_clock(clock.time_left)
		camera.lift = smoothstep(route.distance - REVEAL_FROM, route.distance - REVEAL_FULL, car.road_s)
	match state:
		State.COUNTDOWN:
			_countdown_left -= delta
			var n := ceili(_countdown_left)
			if _countdown_left <= 0.0:
				_go()
			elif n != _countdown_shown:
				_countdown_shown = n
				hud.banner(str(n), Palette.UI_TEXT, 0.45)
				audio.countdown(n)
		State.RACING:
			stats.top_speed_mph = maxf(stats.top_speed_mph, car.speed_mph())
			_announce_jams()
			if police.cop:
				hud.update_pursuit(car.road_s - police.cop.fp.s, police.alongside_t / Police.PULL_OVER_TIME,
					police.escape_t / Police.ESCAPE_TIME)
			if finish_site:
				var hint := finish_site.hint_at(car.road_s, car.road_d)
				if hint != "":
					hud.popup(hint, Palette.UI_ACCENT, 26)
			if crossed_finish():
				_finish()
		State.FINISHED, State.FAILED:
			if _results_in > 0.0:
				_results_in -= delta
				if _results_in <= 0.0:
					_show_results()


func _go() -> void:
	state = State.RACING
	car.input_enabled = true
	clock.start(level.time_limit)
	traffic.waves_enabled = true
	hud.hide_intro()
	if countdown_seconds > 0.0:
		hud.banner("GO!", Palette.UI_ACCENT, 0.5)
		audio.go()


## Past the line, and (for sites like the stadium) in the right place: you
## have to be off the highway and into the lot.
func crossed_finish() -> bool:
	if car.road_s < route.distance:
		return false
	return finish_site == null or finish_site.is_finished(car.road_s, car.road_d)


func _finish() -> void:
	state = State.FINISHED
	clock.stop()
	_end_race()
	hud.banner("FINISH!", Palette.UI_ACCENT, -1.0)
	audio.finished()
	if finish_site:
		car.auto_brake = finish_site.finish_brake
		finish_site.on_finished()
		var target: Variant = finish_site.showcase_point()
		if target != null:
			camera.showcase(target)
			_results_in = SHOWCASE_DELAY
			hud.banner("FINISH!", Palette.UI_ACCENT, 1.1)  # then out of the way of the view


func _fail() -> void:
	if state != State.RACING:
		return
	state = State.FAILED
	_end_race()
	hud.banner("TIME'S UP", Palette.UI_WARN, -1.0)
	audio.failed()


func _end_race() -> void:
	police.stand_down()
	hud.show_pursuit(false)
	car.input_enabled = false
	car.auto_brake = 0.35
	traffic.waves_enabled = false
	pause_menu.allowed = false
	_results_in = RESULTS_DELAY


func _show_results() -> void:
	touch.set_suppressed(true)
	hud.hide_banner()
	if state == State.FINISHED:
		results.show_win(level, stats, clock.time_left)
	else:
		results.show_fail(level, stats, route.miles_left(car.road_s))


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_garage() -> void:
	get_tree().paused = false
	# Deferred: this runs inside a button's input handling.
	get_tree().change_scene_to_file.call_deferred(GARAGE_SCENE)


## Props only fire while the player is actually driving.
func can_use_props() -> bool:
	return state == State.RACING and car.input_enabled and not car.is_spinning()


## High beams blinded a driver; `announce` pops the "BLINDED!" bubble (once per use).
func on_driver_blinded(announce: bool) -> void:
	stats.drivers_blinded += 1
	if announce:
		hud.popup("BLINDED!", Palette.UI_BONUS)


## "Austin traffic ahead" once per metro jam, just before you reach it.
func _announce_jams() -> void:
	for i in traffic.profile.jams.size():
		var jam: Vector2 = traffic.profile.jams[i]
		if i in _jams_announced or car.road_s < jam.x - 250.0 or car.road_s > jam.y:
			continue
		_jams_announced.append(i)
		var town := route.end_name if jam.x > route.distance * 0.5 else route.start_name
		hud.popup("%s TRAFFIC AHEAD" % town.to_upper(), Palette.UI_WARN)


func _on_near_miss(_car: TrafficCar) -> void:
	if state != State.RACING:
		return
	clock.add(NEAR_MISS_BONUS)
	stats.near_misses += 1
	stats.bonus_time += NEAR_MISS_BONUS
	hud.popup("NEAR MISS  +%.1fs" % NEAR_MISS_BONUS, Palette.UI_BONUS)
	hud.flash_bonus(NEAR_MISS_BONUS)


func _on_road_rage_ko(count: int) -> void:
	if state != State.RACING:
		return
	stats.road_rage_kos += count
	hud.popup("ROAD RAGE KO!" if count == 1 else "ROAD RAGE KO x%d!" % count, Palette.UI_BONUS, 32)
	camera.add_shake(0.25)


# --- Police ------------------------------------------------------------------------

func _on_chase_started(_cop: PoliceCar, reason: StringName) -> void:
	match reason:
		&"speeding":
			hud.popup("CLOCKED AT %d!" % police.clocked_mph, Palette.UI_WARN, 34)
		&"rammed":
			hud.popup("YOU HIT A TROOPER?!", Palette.UI_WARN, 32)
		&"high_beams":
			hud.popup("Did you just high-beam a TROOPER?", Palette.UI_WARN, 28)
		&"gesture":
			hud.popup("...at a STATE TROOPER?!", Palette.UI_WARN, 30)
	hud.show_pursuit(true)


## Pulled over: the world waits while you get your ticket, which costs
## Police.TICKET_PENALTY seconds. Then you pull back out from the shoulder.
func _on_pulled_over(_cop: PoliceCar) -> void:
	stats.tickets += 1
	stats.ticket_time += Police.TICKET_PENALTY
	clock.add(-Police.TICKET_PENALTY)
	hud.show_pursuit(false)
	camera.snap()
	Sfx.play(AudioManager, &"ticket", -4.0)  # AudioManager keeps playing while paused
	pause_menu.allowed = false
	get_tree().paused = true
	ticket.open(police.ticket_lines(), Police.TICKET_PENALTY)
	await ticket.closed
	get_tree().paused = false
	if state == State.RACING:
		pause_menu.allowed = true
		hud.popup("TICKET  -%ds" % roundi(Police.TICKET_PENALTY), Palette.UI_WARN, 32)
		hud.flash_bonus(-Police.TICKET_PENALTY)


func _on_escaped(_cop: PoliceCar) -> void:
	stats.escapes += 1
	hud.show_pursuit(false)
	hud.popup("LOST HIM!", Palette.UI_BONUS, 34)


func _on_trap_dodged(_trap: SpeedTrap) -> void:
	hud.popup("RADAR DETECTOR: TRAP DODGED", Palette.UI_BONUS, 22)


func _on_slowdown_ahead() -> void:
	if state == State.RACING:
		hud.popup("Slowdown ahead. Reason: none.", Palette.UI_TEXT, 22)


func _on_spun_out() -> void:
	if state == State.RACING:
		stats.spin_outs += 1
		hud.popup(SPIN_LINES[randi() % SPIN_LINES.size()], Palette.UI_WARN)
	camera.add_shake(0.6)


func _on_car_bumped(strength: float) -> void:
	camera.add_shake(clampf(strength * 0.05, 0.05, 0.7))
