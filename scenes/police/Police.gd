class_name Police
extends Node3D
## Speed traps and chases.
##
## - Each level has LevelData.speed_traps traps, spread over the open road
##   between the start and the destination (new spots every run, never in a
##   metro jam). A trap is built once the road reaches it (SpeedTrap), and
##   traffic eases off to the limit as it passes one: brake lights ahead are a
##   tell, as is the glint off the cruiser's windshield.
## - Its radar clocks you from DETECT_BEFORE meters before the cruiser (less in
##   the EV: CarData.police_detection_scale) to just past it. Over the limit
##   plus GRACE_MPH in there and the chase is on; at or under it, nothing
##   happens. Spot the cop, brake, cruise past, floor it. With the Radar
##   Detector prop, traps never trigger.
## - Radar or not, these start a chase too: hitting a cruiser (parked or
##   moving), high-beaming one, or flipping one off.
## - The chase: a PoliceCar comes after you. Let it sit alongside for
##   PULL_OVER_TIME and you're pulled over (Race shows the ticket and takes
##   TICKET_PENALTY off the clock). Stay ESCAPE_GAP ahead for ESCAPE_TIME
##   (traffic helps: it brakes for slowpokes too) and you've lost it.
## - "SPEED LIMIT 75" signs stand along the road.

signal chase_started(cop: PoliceCar, reason: StringName)
signal pulled_over(cop: PoliceCar)
signal escaped(cop: PoliceCar)
## You blew through a trap and the Radar Detector kept you off its radar.
signal trap_dodged(trap: SpeedTrap)

const POLICE_DATA := preload("res://data/traffic/police.tres")
## Short enough that the cruiser is on screen (the chase camera shows about
## 100-160 m of road) a couple of seconds before its radar can clock you.
const DETECT_BEFORE := 60.0
const DETECT_AFTER := 12.0
const GRACE_MPH := 5.0
## Being alongside: within this far along the road and across it.
const ALONGSIDE_S := 3.5
const ALONGSIDE_D := 5.4
const PULL_OVER_TIME := 2.0
const ESCAPE_GAP := 120.0
const ESCAPE_TIME := 8.0
## This far back, it's simply gone.
const LOST_GAP := 320.0
const TICKET_PENALTY := 15.0
## After a ticket: you pull back out from the shoulder at this speed (m/s)
## with the cruiser parked behind you, lights still going.
const RESUME_SPEED := 13.0
## Traps stay this far from the start, from the finish (on top of a finish
## site's own stretch) and from metro jams.
const START_CLEAR := 700.0
const END_CLEAR := 450.0
const JAM_CLEAR := 150.0
## The radar detector starts to chirp this far out.
const THREAT_RANGE := 450.0
## Traffic eases off to the limit (minus SLOW_UNDER_MPH) around a trap.
const SLOW_BEFORE := 170.0
const SLOW_AFTER := 30.0
const SLOW_UNDER_MPH := 3.0
const FIRST_SIGN := 320.0
const SIGN_EVERY := 1500.0

var traps: Array[SpeedTrap] = []
## The cruiser chasing you, or null.
var cop: PoliceCar
## Seconds it has been alongside / you've been well clear of it.
var alongside_t := 0.0
var escape_t := 0.0
var chase_reason: StringName = &""
## Your speed when the radar clocked you (for the ticket).
var clocked_mph := 0

var _race: Race
var _signs: Array[float] = []
var _signs_placed := 0
var _rng := RandomNumberGenerator.new()


func setup(race: Race, rng_seed := 0) -> void:
	_race = race
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	var to := race.route.distance - END_CLEAR - (race.finish_site.straight_before if race.finish_site else 0.0)
	var spans := _open_road(START_CLEAR, to, race.traffic.profile.jams)
	for s in _spread(spans, race.level.speed_traps):
		add_trap(s)
	var s := FIRST_SIGN
	while s < to:
		_signs.append(s)
		s += SIGN_EVERY
	race.traffic.slow_speed = (race.speed_limit_mph - SLOW_UNDER_MPH) / PlayerCar.MPS_TO_MPH
	race.traffic.player_contact.connect(_on_player_contact)


## Adds a trap with its cruiser at road position s (tests place their own).
func add_trap(s: float) -> SpeedTrap:
	var trap := SpeedTrap.new()
	trap.name = "SpeedTrap%d" % traps.size()
	trap.setup(s, _rng.randi())
	add_child(trap)
	traps.append(trap)
	return trap


## How far before a cruiser its radar clocks this car.
func detection_radius(car: CarData) -> float:
	return DETECT_BEFORE * car.police_detection_scale


func is_chasing() -> bool:
	return cop != null


## 0 = no trap anywhere near .. 1 = one right here (the Radar Detector's LEDs).
## A chase pins it.
func threat_at(s: float) -> float:
	if cop:
		return 1.0
	var threat := 0.0
	for trap in traps:
		var rel := trap.s - s
		if trap.launched or rel < -DETECT_AFTER or rel > THREAT_RANGE:
			continue
		threat = maxf(threat, clampf(1.0 - rel / THREAT_RANGE, 0.0, 1.0))
	return threat


## The nearest trooper within `reach` meters (bumper to bumper) that isn't
## already chasing you: a parked SpeedTrap or a PoliceCar in traffic. Null if none.
func trooper_near(reach: float) -> Variant:
	var p := _race.traffic.player_footprint()
	var best: Variant = null
	var best_dist := reach
	for trap in traps:
		if trap.placed and not trap.launched:
			var dist := _gap(p, trap.cop_footprint(POLICE_DATA))
			if dist <= best_dist:
				best = trap
				best_dist = dist
	for car in _race.traffic.active_cars():
		if car is PoliceCar and not (car as PoliceCar).is_pursuing():
			var dist := _gap(p, car.fp)
			if dist <= best_dist:
				best = car
				best_dist = dist
	return best


## Something you did got a trooper's attention: `target` is a SpeedTrap or a
## PoliceCar. Returns whether a chase started (not if one's already on).
func provoke(target: Variant, reason: StringName) -> bool:
	if cop != null or _race.state != Race.State.RACING:
		return false
	if target is SpeedTrap:
		if (target as SpeedTrap).launched or not (target as SpeedTrap).placed:
			return false
		_launch(target, reason)
	elif target is PoliceCar:
		_start_chase(target, reason)
	else:
		return false
	return true


## Ends any chase without a ticket (the race is over).
func stand_down() -> void:
	if cop:
		cop.go_off_duty()
	cop = null
	alongside_t = 0.0
	escape_t = 0.0


func _physics_process(delta: float) -> void:
	if _race == null:
		return
	_place_ahead()
	if _race.state != Race.State.RACING:
		return
	var car := _race.car
	if cop:
		_update_chase(delta, car)
	else:
		_check_traps(car)
		_check_parked_bumps()


func _place_ahead() -> void:
	var reach := _race.road.streamed_to()
	for trap in traps:
		if not trap.placed and reach > trap.s + SpeedTrap.OVERPASS_REACH:
			trap.place(_race.road, POLICE_DATA)
			_race.traffic.slow_zones.append(Vector2(trap.s - SLOW_BEFORE, trap.s + SLOW_AFTER))
	while _signs_placed < _signs.size() and reach > _signs[_signs_placed] + 10.0:
		_build_sign(_signs[_signs_placed])
		_signs_placed += 1


func _check_traps(car: PlayerCar) -> void:
	var too_fast := car.speed_mph() > _race.speed_limit_mph + GRACE_MPH
	var radius := detection_radius(car.car_data)
	for trap in traps:
		if not trap.placed or trap.launched or trap.dodged:
			continue
		var rel := trap.s - car.road_s
		if rel < -DETECT_AFTER or rel > radius or car.road_d < 0.0 or not too_fast:
			continue
		if _race.props.blocks_speed_traps():
			trap.dodged = true
			trap_dodged.emit(trap)
			continue
		clocked_mph = roundi(car.speed_mph())
		_launch(trap, &"speeding")
		return


## Ran into a parked cruiser.
func _check_parked_bumps() -> void:
	var p := _race.traffic.player_footprint()
	for trap in traps:
		if trap.placed and not trap.launched and _gap(p, trap.cop_footprint(POLICE_DATA)) < 0.4 \
				and _race.car.speed_mph() > 3.0:
			_launch(trap, &"rammed")
			return


func _on_player_contact(car: TrafficCar, closing: float) -> void:
	if car is PoliceCar and not (car as PoliceCar).is_pursuing() and closing > 2.0:
		provoke(car, &"rammed")


func _launch(trap: SpeedTrap, reason: StringName) -> void:
	trap.launch()
	var fp := trap.cop_footprint(POLICE_DATA)
	_start_chase(_race.traffic.spawn_police(POLICE_DATA, fp.s, fp.d, fp.rel_yaw), reason)


func _start_chase(car: PoliceCar, reason: StringName) -> void:
	cop = car
	cop.pursue(_race.traffic.player_footprint())
	alongside_t = 0.0
	escape_t = 0.0
	chase_reason = reason
	if reason != &"speeding":
		clocked_mph = roundi(_race.car.speed_mph())
	chase_started.emit(car, reason)


func _update_chase(delta: float, car: PlayerCar) -> void:
	if not is_instance_valid(cop) or not cop.is_pursuing():
		cop = null
		return
	var lead := car.road_s - cop.fp.s
	if absf(lead) < ALONGSIDE_S and absf(car.road_d - cop.fp.d) < ALONGSIDE_D and not car.is_spinning():
		alongside_t += delta
	else:
		alongside_t = maxf(0.0, alongside_t - delta * 1.5)
	if lead > ESCAPE_GAP:
		escape_t += delta
	else:
		escape_t = maxf(0.0, escape_t - delta * 0.5)
	if alongside_t >= PULL_OVER_TIME:
		_pull_over(car)
	elif escape_t >= ESCAPE_TIME or lead > LOST_GAP:
		var gone := cop
		stand_down()
		escaped.emit(gone)


## Both cars onto the shoulder: you just ahead, the cruiser parked behind with
## its lights going. Race shows the ticket while the world waits.
func _pull_over(car: PlayerCar) -> void:
	var gone := cop
	cop = null
	alongside_t = 0.0
	escape_t = 0.0
	var road := _race.road
	var s := car.road_s
	var d := maxf(car.road_d, (RoadSpec.lanes_outer_edge() + RoadSpec.shoulder_outer_edge()) * 0.5)
	d = minf(d, road.outer_limit_at(s) - car.car_data.size.x)
	car.place_at(road.sample(s, d), road.yaw_at(s))
	car.velocity = RoadGeo.forward(road.yaw_at(s)) * RESUME_SPEED
	car.speed = RESUME_SPEED
	gone.park(s - car.car_data.size.z * 0.5 - 6.0, d)
	# The world freezes for the ticket: show the cruiser where it parked now.
	gone.sync_to_road(road, Time.get_ticks_msec() / 1000.0)
	gone.reset_physics_interpolation()
	pulled_over.emit(gone)


## What the trooper says, and what the ticket's for.
func ticket_lines() -> Array[String]:
	match chase_reason:
		&"rammed":
			return ["You hit a patrol car. On purpose? Don't answer that.", "Bumping a patrol car"]
		&"high_beams":
			return ["You high-beamed a STATE TROOPER. In broad daylight.", "Improper use of high beams"]
		&"gesture":
			return ["I saw that. Everybody saw that. Even with the bar over it.", "Disorderly gesturing"]
	var lines: Array[String] = [
		"License and registration. You know how fast you were going?",
		"Son, this is I-35. Not the Autobahn.",
		"In a mighty big hurry to go sit in traffic, huh?",
		"Clocked you at %d. Limit's %d. Do the math." % [clocked_mph, _race.speed_limit_mph],
	]
	return [lines[_rng.randi() % lines.size()], "%d mph in a %d" % [clocked_mph, _race.speed_limit_mph]]


## The open stretches of [from, to] once metro jams (plus a margin) are cut out.
static func _open_road(from: float, to: float, jams: Array[Vector2]) -> Array[Vector2]:
	var spans: Array[Vector2] = [Vector2(from, to)]
	for jam in jams:
		var cut := Vector2(jam.x - JAM_CLEAR, jam.y + JAM_CLEAR)
		var next: Array[Vector2] = []
		for span in spans:
			if cut.y <= span.x or cut.x >= span.y:
				next.append(span)
				continue
			if cut.x > span.x:
				next.append(Vector2(span.x, cut.x))
			if cut.y < span.y:
				next.append(Vector2(cut.y, span.y))
		spans = next
	return spans


## `count` spots evenly spread over the spans (each jittered within its share).
func _spread(spans: Array[Vector2], count: int) -> Array[float]:
	var spots: Array[float] = []
	var total := 0.0
	for span in spans:
		total += span.y - span.x
	if count <= 0 or total <= 0.0:
		return spots
	var share := total / count
	for i in count:
		var along := share * (i + _rng.randf_range(0.2, 0.8))
		for span in spans:
			var length := span.y - span.x
			if along <= length:
				spots.append(span.x + along)
				break
			along -= length
	return spots


## Bumper-to-bumper distance between two bodies (0 or less when touching).
static func _gap(a: Footprint, b: Footprint) -> float:
	var gap_s := absf(b.s - a.s) - a.reach_s() - b.reach_s()
	var gap_d := absf(b.d - a.d) - a.reach_d() - b.reach_d()
	if gap_s <= 0.0 and gap_d <= 0.0:
		return maxf(gap_s, gap_d)
	return Vector2(maxf(gap_s, 0.0), maxf(gap_d, 0.0)).length()


## A white "SPEED LIMIT 75" sign on the right-hand side.
func _build_sign(at_s: float) -> void:
	var road := _race.road
	var node := Node3D.new()
	node.name = "LimitSign"
	node.transform = Transform3D(Basis(Vector3.UP, road.yaw_at(at_s)), road.sample(at_s, 0.0))
	var xf := Scenery.at(0.0, RoadSpec.shoulder_outer_edge() + 2.2, -0.12)
	var mk := MeshKit.new()
	Scenery.sign_board(mk, xf, Vector2(2.0, 2.5), 1.7, Palette.SIGN_WHITE, Palette.UI_TEXT)
	node.add_child(Scenery.mesh_node("Board", mk))
	node.add_child(Scenery.sign_text(xf, 1.7 + 1.25, ["SPEED", "LIMIT", str(_race.speed_limit_mph)], [44, 44, 100],
		Palette.UI_TEXT))
	add_child(node)
	node.reset_physics_interpolation()
