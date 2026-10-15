class_name RaceAudio
extends Node
## Everything you hear during a race except the music: your engine (its note
## climbs through the gears; the EV just whines higher), tire squeal in hard
## turns, under heavy braking and in spin-outs, bumps, barrier scrapes and
## crashes, the whoosh and chime of a near miss, other drivers' horns and
## pileups, the countdown beeps, the clock ticking through the last ten
## seconds, police sirens, and the stinger at the end. Sounds come from Sfx.

const ENGINE_DB := -21.0
## Extra engine volume with your foot down.
const THROTTLE_DB := 4.0
const SQUEAL_DB := -14.0
## Sideways slide (m/s) where the tires start to squeal, and where they're at full cry.
const SQUEAL_SLIP := Vector2(1.7, 5.0)
## Seconds between barrier-scrape sounds while you grind along it.
const SCRAPE_EVERY := 0.32
const TICK_FROM := 10
const SIREN_DB := -9.0

var _race: Race
var _engine: AudioStreamPlayer
var _squeal: AudioStreamPlayer
var _siren: AudioStreamPlayer
var _squeal_level := 0.0
var _engine_throttle := 0.0
var _scrape_in := 0.0
var _last_tick := -1


func setup(race: Race) -> void:
	_race = race
	_engine = Sfx.loop_player(race.car.car_data.engine_sound)
	_engine.name = "Engine"
	add_child(_engine)
	_squeal = Sfx.loop_player(&"tire_squeal")
	_squeal.name = "Squeal"
	add_child(_squeal)
	_siren = Sfx.loop_player(&"siren")
	_siren.name = "Siren"
	add_child(_siren)
	race.car.bumped.connect(_on_bumped)
	race.car.scraped.connect(_on_scraped)
	race.traffic.near_miss.connect(_on_near_miss)
	race.traffic.wrecked.connect(_on_wrecked)
	race.traffic.honked.connect(_on_honked)
	race.police.chase_started.connect(_on_chase_started)
	race.police.escaped.connect(_on_escaped)


func engine() -> AudioStreamPlayer:
	return _engine


func squeal() -> AudioStreamPlayer:
	return _squeal


func siren() -> AudioStreamPlayer:
	return _siren


## The engine note for a car at `speed_ratio` (0..1 of top speed): it rises
## through each gear and drops back at the shift. No gears: a straight climb.
static func engine_pitch(data: CarData, speed_ratio: float) -> float:
	var r := clampf(speed_ratio, 0.0, 1.0)
	var low := data.engine_pitch.x
	var high := data.engine_pitch.y
	if data.engine_gears <= 0:
		return lerpf(low, high, r)
	var geared := r * data.engine_gears
	var gear := mini(int(geared), data.engine_gears - 1)
	var within := geared - gear
	# Each shift lands a little higher than the last, like a real gearbox.
	var start := low if gear == 0 else lerpf(low, high, 0.42 + 0.06 * gear)
	return lerpf(start, high, within)


func _physics_process(delta: float) -> void:
	if _race == null:
		return
	_update_engine(delta)
	_update_squeal(delta)
	_update_siren()
	_update_clock()
	_scrape_in = maxf(0.0, _scrape_in - delta)


func _update_engine(delta: float) -> void:
	var car := _race.car
	var throttle := car.throttle
	var ratio := absf(car.speed) / car.top_speed()
	if _race.state == Race.State.COUNTDOWN:
		# Revving at the line.
		throttle = Input.get_action_strength("accelerate")
		ratio = throttle * 0.35
	_engine_throttle = move_toward(_engine_throttle, throttle, delta * 4.0)
	var pitch := engine_pitch(car.car_data, ratio) * (1.0 + 0.04 * _engine_throttle)
	Sfx.set_loop(_engine, 1.0, ENGINE_DB + THROTTLE_DB * (_engine_throttle - 1.0), pitch)


func _update_squeal(delta: float) -> void:
	var car := _race.car
	var target := 0.0
	if car.is_spinning():
		target = clampf(car.velocity.length() / 15.0, 0.35, 1.0)
	elif car.surface == RoadSpec.Surface.LANE or car.surface == RoadSpec.Surface.SHOULDER:
		var slip := absf(car.velocity.dot(RoadGeo.right(car.yaw)))
		target = clampf((slip - SQUEAL_SLIP.x) / (SQUEAL_SLIP.y - SQUEAL_SLIP.x), 0.0, 1.0)
		if car.brake > 0.6 and car.speed > 15.0:
			target = maxf(target, 0.25 + 0.35 * clampf((car.speed - 15.0) / 20.0, 0.0, 1.0))
	# Squeal starts sharp and dies away a little slower.
	_squeal_level = move_toward(_squeal_level, target, delta * (8.0 if target > _squeal_level else 3.0))
	Sfx.set_loop(_squeal, _squeal_level, SQUEAL_DB, 0.92 + 0.16 * clampf(absf(car.speed) / 40.0, 0.0, 1.0))


## The chasing cruiser's siren, louder the closer it gets, a touch higher
## while it's gaining on you.
func _update_siren() -> void:
	var cop := _race.police.cop if _race.police else null
	if cop == null:
		Sfx.set_loop(_siren, 0.0)
		return
	var car := _race.car
	var distance := Vector2(cop.fp.s - car.road_s, cop.fp.d - car.road_d).length()
	var closing := cop.speed - car.speed
	Sfx.set_loop(_siren, 1.0, SIREN_DB + Sfx.distance_db(distance), 1.0 + clampf(closing / 340.0, -0.04, 0.04))


func _on_chase_started(cop: PoliceCar, _reason: StringName) -> void:
	Sfx.play_at(self, &"siren_whoop", _distance_to(cop), -4.0)


func _on_escaped(_cop: PoliceCar) -> void:
	Sfx.play(self, &"bonus", -8.0)


func _update_clock() -> void:
	if _race.state != Race.State.RACING or not _race.clock.running:
		return
	var second := ceili(_race.clock.time_left)
	if second <= TICK_FROM and second > 0 and second != _last_tick:
		_last_tick = second
		Sfx.play(self, &"tick", -6.0, 1.0 + 0.04 * (TICK_FROM - second))


# --- Race moments (called by Race) -----------------------------------------------------

func countdown(_number: int) -> void:
	Sfx.play(self, &"beep", -7.0)


func go() -> void:
	Sfx.play(self, &"beep_go", -5.0)


func finished() -> void:
	Sfx.play(self, &"win", -3.0)
	AudioManager.duck(-9.0, 2.0)


func failed() -> void:
	Sfx.play(self, &"fail", -3.0)
	AudioManager.duck(-12.0, 2.6)


# --- Bumps and traffic -----------------------------------------------------------------

## Hard hits (the ones that spin you out) crash; lighter ones thud.
func _on_bumped(strength: float) -> void:
	if strength >= _race.car.hard_crash_speed - 0.01:
		Sfx.play(self, &"crash", -2.0, randf_range(0.92, 1.06))
	elif strength > 1.0:
		var k := clampf((strength - 1.0) / 7.0, 0.0, 1.0)
		Sfx.play(self, &"bump", lerpf(-16.0, -4.0, k), randf_range(0.9, 1.1))


func _on_scraped(speed: float) -> void:
	if speed < 4.0 or _scrape_in > 0.0:
		return
	_scrape_in = SCRAPE_EVERY
	Sfx.play(self, &"scrape", lerpf(-16.0, -6.0, clampf(speed / 40.0, 0.0, 1.0)), randf_range(0.9, 1.12))


func _on_near_miss(_car: TrafficCar) -> void:
	if _race.state != Race.State.RACING:
		return
	Sfx.play(self, &"whoosh", -6.0, randf_range(0.9, 1.1))
	Sfx.play(self, &"bonus", -12.0)


func _on_wrecked(car: TrafficCar) -> void:
	Sfx.play_at(self, &"crash", _distance_to(car), -4.0, randf_range(0.85, 1.1))


func _on_honked(car: TrafficCar) -> void:
	Sfx.play_at(self, &"horn" if randf() < 0.4 else &"horn_short", _distance_to(car), -7.0,
		randf_range(0.85, 1.15))


func _distance_to(car: TrafficCar) -> float:
	return Vector2(car.fp.s - _race.car.road_s, car.fp.d - _race.car.road_d).length()
