class_name TrafficCar
extends Node3D
## One AI driver. It lives in road coordinates (its Footprint) and is stepped
## by TrafficSpawner, which also recycles it once it's far from the player.
##
## - Speed follows the Intelligent Driver Model: cruise at a desired speed,
##   keep a time gap to whatever is ahead, and brake harder the faster that
##   gap is closing (so it brakes for the player, wrecks and slowdowns alike).
## - Lane changes weigh "how much faster could I go over there?" against a
##   keep-right habit, and only happen into a safe gap. Some drivers signal
##   first; some don't (it's I-35).
## - When hit, the driver is rattled for a moment: it slides, maybe spins,
##   puts the hazards on, then eases back into the nearest lane.
## - Props reach in from outside: the censored gesture enrages a driver (RAGE:
##   honk, then lunge at the player; a miss ends in a crash-out), wrecks
##   (WRECKED) smoke for a while and then get towed, and high beams blind
##   drivers for a few seconds (slower, wandering in the lane).

enum Mode { CRUISE, SIGNAL, CHANGE, KNOCKED, RAGE, WRECKED }

## It just crashed out (a rager who missed, or caught up in a pileup).
signal crashed(car: TrafficCar)

const MIN_GAP := 2.5          # meters kept to the car ahead, even when stopped
const COMFORT_BRAKE := 3.0    # m/s^2 a calm driver brakes with
const MAX_BRAKE := 9.0        # m/s^2 emergency stop
## Braking cap when only the desired speed dropped (a slowdown, a jam), not a car.
const SLOWDOWN_BRAKE := 4.5
const BLINK_PERIOD := 0.7
## Closing speed (m/s) that rattles a driver instead of just nudging the car.
const KNOCK_SPEED := 3.0
## Sideways speed while changing lanes, m/s (calm .. aggressive drivers).
const LANE_SPEED := Vector2(1.3, 2.6)
## Road rage: a short wind-up (angry face, horn) creeping toward the player,
## then a lunge. A driver who's going to miss pulls up RAGE_SHORT meters short.
const RAGE_WINDUP := 0.45
const RAGE_LUNGE := 1.1
const RAGE_CREEP := 1.2       # m/s sideways during the wind-up
const RAGE_LATERAL := 4.5     # m/s sideways during the lunge
const RAGE_CHASE := Vector2(4.0, 9.0)  # m/s^2 speeding up / slowing down to stay alongside
const RAGE_SHORT := 0.8
## How long a driver stays visibly angry after landing a hit.
const ANGRY_AFTER := 1.5
## Crash-outs slide to a stop, smoke for WRECK_HOLD seconds, then get towed.
const WRECK_FRICTION := 7.0
const WRECK_HOLD := 6.0
const TOW_TIME := 0.5
## High beams: blinded drivers want this fraction of their speed and wander.
const BLIND_SPEED := 0.6
const BLIND_WANDER := 0.45
const ICON_HEIGHT := 1.3      # meters above the roof
const ICON_SIZE := 1.6        # meters across
const ANGRY_ICON := preload("res://assets/ui/mood_angry.svg")
const DIZZY_ICON := preload("res://assets/ui/mood_dizzy.svg")

var data: TrafficCarData
var fp := Footprint.new()
var behavior: TrafficBehavior
## +1 drives the player's way, -1 is oncoming.
var dir := 1
var lane := 1
## Speed along its direction of travel, m/s (never negative).
var speed := 0.0
## What it would cruise at on an open road, m/s.
var cruise := 30.0
## The posted limit, m/s (behaviors like the left-lane camper use it).
var speed_limit := 33.5
## Last tick's acceleration; braking turns the brake lights on.
var accel := 0.0
var mode: Mode = Mode.CRUISE
## Near-miss bookkeeping for TrafficSpawner.
var pass_rel := 0.0
var near_miss_ready := true
## Seconds since it last touched the player (a touch voids the near miss).
var touched_cooldown := 0.0
## While raging: the player's footprint and whether this driver will connect.
var rage_target: Footprint
var rage_will_hit := false
## Set when it crashes out mid-rage; the spawner turns it into a pileup.
var crashed_out := false
## A towed wreck, ready to be recycled.
var expired := false
## Seconds of high-beam blindness left.
var blind_t := 0.0
## Seconds until this driver will lean on the horn again.
var honk_cooldown := 0.0

var _target_lane := 1
var _from_d := 0.0
var _to_d := 0.0
var _change_t := 0.0
var _change_time := 2.0
var _signal_left := 0.0
var _blink := 0  # -1 left, 1 right, 2 hazards, 0 off
var _blink_phase := 0.0
var _decide_in := 1.0
var _knock_t := 0.0
var _knock_vd := 0.0
var _spin_rate := 0.0
var _steer_yaw := 0.0
var _braking := false
var _age := 0.0
var _wander_phase := 0.0
var _rage_t := 0.0
var _rage_side := 1.0
var _angry_t := 0.0
var _wreck_t := 0.0
var _tow_scale := 1.0
var _icon: Sprite3D
var _icon_age := 0.0
var _smoke: SmokePlume

var _body: MeshInstance3D
var _tail: MeshInstance3D
var _blink_left: MeshInstance3D
var _blink_right: MeshInstance3D


## Builds the model once per pooled node (a pool only ever holds one type).
func build(type: TrafficCarData) -> void:
	data = type
	fp.car = self
	fp.half_len = type.size.z * 0.5
	fp.half_wid = type.size.x * 0.5
	fp.mass = type.mass
	if type.behavior:
		behavior = type.behavior.new() as TrafficBehavior
	if type.model_scene:
		var model := type.model_scene.instantiate()
		for child in model.get_children():
			child.owner = null
			model.remove_child(child)
			add_child(child)
		model.free()
		_body = get_node_or_null("Body") as MeshInstance3D
		_tail = get_node_or_null("Taillights") as MeshInstance3D
		_blink_left = get_node_or_null("BlinkLeft") as MeshInstance3D
		_blink_right = get_node_or_null("BlinkRight") as MeshInstance3D
	else:
		_body = _add_mesh("Body", null, true)
		_tail = _add_mesh("Taillights", TrafficModel.tail_mesh(type))
		_blink_left = _add_mesh("BlinkLeft", TrafficModel.blinker_mesh(type, -1.0))
		_blink_right = _add_mesh("BlinkRight", TrafficModel.blinker_mesh(type, 1.0))
		if type.body_style == TrafficCarData.BodyStyle.WORK_TRUCK:
			_add_mesh("Beacon", TrafficModel.beacon_mesh(type)).material_override = TrafficModel.beacon_material()
	if _tail:
		_tail.material_override = TrafficModel.tail_material(false)
	for lamp: MeshInstance3D in [_blink_left, _blink_right]:
		if lamp:
			lamp.material_override = TrafficModel.blinker_material()
			lamp.visible = false


func _add_mesh(node_name: String, mesh: Mesh, shadow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Puts a pooled car back on the road.
func activate(s: float, lane_index: int, direction: int, start_speed: float, cruise_speed: float,
		paint: Color, rng: RandomNumberGenerator) -> void:
	dir = direction
	lane = lane_index
	_target_lane = lane
	fp.s = s
	fp.d = RoadSpec.lane_center(lane) * dir
	fp.rel_yaw = 0.0 if dir > 0 else PI
	speed = start_speed
	fp.v_s = speed * dir
	fp.v_d = 0.0
	cruise = cruise_speed
	accel = 0.0
	mode = Mode.CRUISE
	_blink = 0
	_knock_t = 0.0
	_knock_vd = 0.0
	_spin_rate = 0.0
	_steer_yaw = 0.0
	_decide_in = rng.randf_range(0.5, 2.0)
	_blink_phase = rng.randf() * BLINK_PERIOD
	_wander_phase = rng.randf() * TAU
	near_miss_ready = true
	touched_cooldown = 0.0
	rage_target = null
	crashed_out = false
	expired = false
	blind_t = 0.0
	honk_cooldown = 0.0
	_angry_t = 0.0
	_wreck_t = 0.0
	_tow_scale = 1.0
	if _icon:
		_icon.texture = null
		_icon.visible = false
	if _smoke:
		_smoke.stop()
	if _body and data.model_scene == null:
		_body.mesh = TrafficModel.body_mesh(data, paint)
	visible = true


## -1 left, 1 right, 2 hazards, 0 off.
func blinker() -> int:
	return _blink


## One tick of driving. `desired` is the speed it wants here (cruise speed times
## any slowdown); `lanes` knows who is around.
func drive(delta: float, desired: float, lanes: TrafficLanes, rng: RandomNumberGenerator) -> void:
	_age += delta
	touched_cooldown = maxf(0.0, touched_cooldown - delta)
	honk_cooldown = maxf(0.0, honk_cooldown - delta)
	_angry_t = maxf(0.0, _angry_t - delta)
	if behavior:
		desired = behavior.desired_speed(self, desired)
		behavior.on_tick(self, delta)
	if blind_t > 0.0:
		blind_t = maxf(0.0, blind_t - delta)
		desired *= BLIND_SPEED
	fp.v_d = 0.0
	match mode:
		Mode.KNOCKED:
			_drive_knocked(delta)
			return
		Mode.WRECKED:
			_drive_wrecked(delta)
			return
		Mode.RAGE:
			_drive_rage(delta, rng)
			return
		Mode.SIGNAL:
			_signal_left -= delta
			if _signal_left <= 0.0:
				var around := lanes.around(TrafficLanes.lane_band(_target_lane), fp)
				if _gap_safe(around[0], around[1]):
					_begin_change()
				else:
					mode = Mode.CRUISE  # thought better of it
					_blink = 0
		Mode.CHANGE:
			_advance_change(delta)
		Mode.CRUISE:
			if dir > 0:
				var center := RoadSpec.lane_center(lane)
				if blind_t > 0.0:
					# Can't see a thing: no lane changes, just wandering.
					center += sin(_age * 2.4 + _wander_phase) * BLIND_WANDER
					fp.d = move_toward(fp.d, center, 1.0 * delta)
				else:
					_decide_in -= delta
					if _decide_in <= 0.0:
						_decide_in = rng.randf_range(0.6, 1.4)
						_consider_lane_change(desired, lanes, rng)
					# Drift back to the lane center after a nudge.
					fp.d = move_toward(fp.d, center, 0.6 * delta)
	accel = _idm(desired, lanes.leader(fp, dir))
	speed = maxf(0.0, speed + accel * delta)
	fp.s += speed * dir * delta
	fp.v_s = speed * dir
	# Lane changes angle the nose a little; after a knock it straightens out.
	var target_yaw := (0.0 if dir > 0 else PI) + _steer_yaw
	fp.rel_yaw = lerp_angle(fp.rel_yaw, target_yaw, 1.0 - exp(-6.0 * delta))


## Intelligent Driver Model acceleration toward `desired`, behind `lead`.
func _idm(desired: float, lead: Footprint) -> float:
	var a_max := data.acceleration
	var ratio := speed / maxf(desired, 0.5)
	# Easing off for a lower desired speed is firm but not a panic stop.
	var a := maxf(a_max * (1.0 - ratio * ratio * ratio * ratio), -SLOWDOWN_BRAKE)
	if lead != null:
		var closing := speed - lead.v_s * dir
		var wanted_gap := MIN_GAP + maxf(0.0, speed * data.headway + speed * closing / (2.0 * sqrt(a_max * COMFORT_BRAKE)))
		var k := wanted_gap / maxf(gap_to(lead), 0.25)
		a -= a_max * k * k
	return clampf(a, -MAX_BRAKE, a_max)


## Bumper-to-bumper distance to a body ahead (negative when overlapping).
func gap_to(other: Footprint) -> float:
	return (other.s * dir - other.reach_s()) - (fp.s * dir + fp.reach_s())


func _consider_lane_change(desired: float, lanes: TrafficLanes, rng: RandomNumberGenerator) -> void:
	var here := _idm(desired, lanes.leader(fp, dir, TrafficLanes.lane_band(lane)))
	var aggression := data.lane_change_aggression
	var best := -1
	var best_gain := 0.2 + 0.6 * (1.0 - aggression)
	var safe: Array[int] = []
	for target: int in [lane - 1, lane + 1]:
		if target < 0 or target >= RoadSpec.LANES:
			continue
		var around := lanes.around(TrafficLanes.lane_band(target), fp)
		if not _gap_safe(around[0], around[1]):
			continue
		safe.append(target)
		var gain := _idm(desired, around[0]) - here + _lane_bias(target) - _lane_bias(lane)
		if gain > best_gain:
			best_gain = gain
			best = target
	if best < 0 and not safe.is_empty() and rng.randf() < aggression * 0.05:
		best = safe[rng.randi() % safe.size()]  # no reason; felt like it
	if best >= 0:
		start_lane_change(best, rng.randf() < data.signal_chance, rng)


## How much this driver likes a lane, in the same units as acceleration gain.
func _lane_bias(target: int) -> float:
	var bias := data.keep_right * float(target)
	if behavior:
		bias += behavior.lane_preference(self, target)
	return bias


## Is there room to merge between `lead` and `follow` in the target lane?
## Aggressive drivers accept tighter gaps, but nobody merges in behind
## something slower without room to brake for it: the car keeps rolling
## through the whole lane change before it can react to what's ahead.
func _gap_safe(lead: Footprint, follow: Footprint) -> bool:
	var caution := 1.0 - 0.35 * data.lane_change_aggression
	if lead != null:
		var closing := maxf(0.0, speed - lead.v_s)
		var room := MIN_GAP + 2.0 + closing * 1.2 * caution + closing * closing / (2.0 * COMFORT_BRAKE)
		if gap_to(lead) < room:
			return false
	if follow != null:
		var gap := (fp.s - fp.reach_s()) - (follow.s + follow.reach_s())
		var fv := follow.v_s
		if gap < (4.0 + maxf(0.0, fv - speed) * 1.5 + fv * 0.3) * caution:
			return false
	return true


func start_lane_change(target: int, use_signal: bool, rng: RandomNumberGenerator) -> void:
	_target_lane = target
	if use_signal:
		mode = Mode.SIGNAL
		_signal_left = rng.randf_range(0.9, 1.5)
		_blink = 1 if target > lane else -1
	else:
		_begin_change()


func _begin_change() -> void:
	mode = Mode.CHANGE
	_from_d = fp.d
	_to_d = RoadSpec.lane_center(_target_lane) * dir
	_change_t = 0.0
	var lateral := lerpf(LANE_SPEED.x, LANE_SPEED.y, data.lane_change_aggression)
	_change_time = maxf(absf(_to_d - _from_d) / lateral, 0.6)


func _advance_change(delta: float) -> void:
	_change_t += delta
	var u := clampf(_change_t / _change_time, 0.0, 1.0)
	fp.d = lerpf(_from_d, _to_d, u * u * (3.0 - 2.0 * u))  # smoothstep: ease in and out
	fp.v_d = (_to_d - _from_d) / _change_time * 6.0 * u * (1.0 - u)
	_steer_yaw = -atan2(fp.v_d, maxf(speed, 4.0))
	if u >= 0.5:
		lane = _target_lane
	if u >= 1.0:
		mode = Mode.CRUISE
		_blink = 0
		_steer_yaw = 0.0
		fp.v_d = 0.0


## A collision. push and dv are in (s, d); closing is how hard it hit (m/s).
func hit(push: Vector2, dv: Vector2, closing: float, rng: RandomNumberGenerator) -> void:
	fp.s += push.x
	fp.d += push.y
	speed = maxf(0.0, speed + dv.x * dir)
	fp.v_s = speed * dir
	if mode == Mode.WRECKED:
		_knock_vd += dv.y  # wrecks just get shoved around
		return
	if closing < KNOCK_SPEED and absf(dv.y) < 0.6:
		return  # a nudge
	if mode == Mode.RAGE:
		# Clipped something mid-tantrum: that's a crash-out (and a pileup).
		crash_out(signf(dv.y) if absf(dv.y) > 0.1 else -_rage_side, rng, true)
		return
	if mode == Mode.CHANGE or mode == Mode.SIGNAL:
		lane = TrafficLanes.nearest_lane(fp.d)
	mode = Mode.KNOCKED
	_knock_t = clampf(0.6 + closing * 0.12, 0.6, 2.5)
	_knock_vd += dv.y
	if closing > 7.0:
		_spin_rate += rng.randf_range(1.0, 2.6) * (1.0 if rng.randf() < 0.5 else -1.0)
	_blink = 2
	_steer_yaw = 0.0


func _drive_knocked(delta: float) -> void:
	_knock_t -= delta
	speed = maxf(0.0, speed - 5.0 * delta)
	accel = -5.0
	fp.s += speed * dir * delta
	fp.v_s = speed * dir
	fp.d += _knock_vd * delta
	fp.v_d = _knock_vd
	_knock_vd *= exp(-2.5 * delta)
	fp.rel_yaw = wrapf(fp.rel_yaw + _spin_rate * delta, -PI, PI)
	_spin_rate *= exp(-2.0 * delta)
	_clamp_to_road()
	if _knock_t <= 0.0 and absf(_spin_rate) < 0.3:
		# Collect yourself and get back in a lane.
		_spin_rate = 0.0
		_knock_vd = 0.0
		_blink = 0
		_target_lane = TrafficLanes.nearest_lane(fp.d)
		lane = _target_lane
		_begin_change()


## The median barrier and the fence stop it like they stop the player.
func _clamp_to_road() -> void:
	var reach := fp.reach_d()
	var lo := RoadSpec.MEDIAN_HALF_BASE + reach + 0.05
	var hi := RoadSpec.FENCE_D - reach
	if fp.d < lo or fp.d > hi:
		fp.d = clampf(fp.d, lo, hi)
		_knock_vd = 0.0


# --- Props: road rage, wrecks, high beams --------------------------------------

## The player just made a rude gesture at this driver. `target` is the
## player's footprint, which the spawner keeps up to date.
func enrage(target: Footprint, will_hit: bool, rng: RandomNumberGenerator) -> void:
	if mode == Mode.CHANGE or mode == Mode.SIGNAL:
		lane = TrafficLanes.nearest_lane(fp.d)
	mode = Mode.RAGE
	rage_target = target
	rage_will_hit = will_hit
	_rage_t = 0.0
	var dd := target.d - fp.d
	_rage_side = signf(dd) if absf(dd) > 0.5 else (1.0 if rng.randf() < 0.5 else -1.0)
	_blink = 0
	blind_t = 0.0


func is_lunging() -> bool:
	return mode == Mode.RAGE and _rage_t >= RAGE_WINDUP


## Stays alongside the player, creeps toward them, then lunges. A driver who
## connects is handled by the spawner (rage_landed); one who misses yanks the
## wheel back and crashes out.
func _drive_rage(delta: float, rng: RandomNumberGenerator) -> void:
	_rage_t += delta
	var p := rage_target
	# Chase the player's position along the road (rage targets always drive our way).
	var want := maxf(p.v_s + clampf((p.s - fp.s) * 1.6, -7.0, 7.0), 0.0)
	var new_speed := move_toward(speed, want, (RAGE_CHASE.x if want > speed else RAGE_CHASE.y) * delta)
	accel = (new_speed - speed) / delta
	speed = new_speed
	fp.s += speed * delta
	fp.v_s = speed
	var aim := p.d
	if not rage_will_hit:
		aim -= _rage_side * (fp.half_wid + p.half_wid + RAGE_SHORT)
	var lateral := RAGE_LATERAL if is_lunging() else RAGE_CREEP
	fp.v_d = clampf((aim - fp.d) * 5.0, -lateral, lateral)
	fp.d += fp.v_d * delta
	_clamp_to_road()
	_steer_yaw = -atan2(fp.v_d, maxf(speed, 4.0))
	fp.rel_yaw = lerp_angle(fp.rel_yaw, _steer_yaw, 1.0 - exp(-8.0 * delta))
	if is_lunging() and (_rage_t >= RAGE_WINDUP + RAGE_LUNGE or (not rage_will_hit and absf(aim - fp.d) < 0.25)):
		crash_out(-_rage_side, rng, true)  # missed, overcorrected, lost it


## Its lunge connected: rattled for a moment, then it drives off, still fuming.
func rage_landed() -> void:
	mode = Mode.KNOCKED
	_knock_t = 0.8
	rage_target = null
	_angry_t = ANGRY_AFTER
	_steer_yaw = 0.0


## Loses it for good: slides and spins toward `away_side` (+1 = toward the
## outer shoulder), then sits smoking with the hazards on until it's towed.
## `chain` asks the spawner to start a pileup around it.
func crash_out(away_side: float, rng: RandomNumberGenerator, chain := false) -> void:
	if mode == Mode.WRECKED:
		return
	if mode == Mode.CHANGE or mode == Mode.SIGNAL:
		lane = TrafficLanes.nearest_lane(fp.d)
	mode = Mode.WRECKED
	crashed_out = chain
	rage_target = null
	blind_t = 0.0
	_angry_t = 0.0
	_knock_vd = away_side * rng.randf_range(3.0, 5.0)
	_spin_rate = rng.randf_range(2.2, 3.6) * (1.0 if rng.randf() < 0.5 else -1.0)
	_wreck_t = 0.0
	_blink = 2
	_steer_yaw = 0.0
	if _smoke == null:
		_smoke = SmokePlume.new()
		_smoke.position = Vector3(0.0, data.size.y * 0.7, -data.size.z * 0.3)
		add_child(_smoke)
	_smoke.start()
	crashed.emit(self)


func is_wrecked() -> bool:
	return mode == Mode.WRECKED


func _drive_wrecked(delta: float) -> void:
	speed = maxf(0.0, speed - WRECK_FRICTION * delta)
	accel = -WRECK_FRICTION if speed > 0.0 else 0.0
	fp.s += speed * dir * delta
	fp.v_s = speed * dir
	fp.d += _knock_vd * delta
	fp.v_d = _knock_vd
	_knock_vd *= exp(-2.0 * delta)
	fp.rel_yaw = wrapf(fp.rel_yaw + _spin_rate * delta, -PI, PI)
	_spin_rate *= exp(-1.6 * delta)
	_clamp_to_road()
	if speed > 0.3 or absf(_spin_rate) > 0.2:
		return
	_wreck_t += delta
	if _wreck_t >= WRECK_HOLD:
		# Towed: shrink away, then the spawner recycles it.
		_tow_scale = clampf(1.0 - (_wreck_t - WRECK_HOLD) / TOW_TIME, 0.0, 1.0)
		if _tow_scale <= 0.0:
			expired = true


## High beams. Keeps the driver blinded for at least `seconds` more; returns
## true if they weren't blinded already. Wrecks and ragers don't care.
func blind(seconds: float) -> bool:
	if mode == Mode.WRECKED or mode == Mode.RAGE:
		return false
	var fresh := blind_t <= 0.0
	blind_t = maxf(blind_t, seconds)
	return fresh


func is_blinded() -> bool:
	return blind_t > 0.0


## The face floating over the car: angry while raging, dizzy while blinded.
func _update_icon(delta: float) -> void:
	var want: Texture2D = null
	if mode == Mode.RAGE or _angry_t > 0.0:
		want = ANGRY_ICON
	elif blind_t > 0.0:
		want = DIZZY_ICON
	if _icon == null:
		if want == null:
			return
		_icon = Sprite3D.new()
		_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_icon.shaded = false
		_icon.no_depth_test = true
		_icon.render_priority = 10
		_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_icon.pixel_size = ICON_SIZE / float(ANGRY_ICON.get_width())
		_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_icon)
	if want != _icon.texture:
		_icon.texture = want
		_icon.visible = want != null
		_icon_age = 0.0
	if not _icon.visible:
		return
	_icon_age += delta
	# Pop in with a little overshoot, then bob.
	var pop := minf(_icon_age / 0.18, 1.0)
	var k := 1.0 + 0.35 * sin(pop * PI) if pop < 1.0 else 1.0
	_icon.scale = Vector3.ONE * pop * k
	_icon.position = Vector3(0.0, data.size.y + ICON_HEIGHT + sin(_age * 5.0) * 0.12, 0.0)


## Moves the node to its road position and updates the lights and mood icon.
func sync_to_road(road: RoadManager, time: float, delta := 0.0) -> void:
	var yaw := road.yaw_at(fp.s) + fp.rel_yaw
	transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * _tow_scale), road.sample(fp.s, fp.d))
	_update_icon(delta)
	var braking := accel < -1.2 or speed < 0.5
	if braking != _braking and _tail:
		_braking = braking
		_tail.material_override = TrafficModel.tail_material(braking)
	var lit := _blink != 0 and fmod(time + _blink_phase, BLINK_PERIOD) < BLINK_PERIOD * 0.55
	if _blink_left:
		_blink_left.visible = lit and (_blink == -1 or _blink == 2)
	if _blink_right:
		_blink_right.visible = lit and (_blink == 1 or _blink == 2)
