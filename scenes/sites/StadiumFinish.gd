extends FinishSite
## Kickoff's destination: the big college stadium next to I-35.
##
## The highway carries on past it. A signed exit ramp peels off the right
## shoulder into a huge game-day parking lot (parked cars, tailgate tents,
## smoking grills, an $80 parking booth), and the finish line is the lot's gate.
## Miss the exit and you can still cut right across the shoulder into the lot;
## you're done the moment you're off the highway lanes past the gate.
##
## The scoreboard counts down to kickoff with the race clock, and fireworks go
## off over the stadium when you make it.
##
## Everything is built in code, low-poly and vertex-colored, in this site's
## local frame (Scenery.at(s, d): s meters past the gate, d meters right of the
## median).

## The home team's color (the level's featured traffic paint).
const TEAM := Color(0.75, 0.4, 0.17)
const LOT_ASPHALT := Color(0.52, 0.5, 0.47)
const DENIM := Color(0.27, 0.33, 0.45)
const KHAKI := Color(0.72, 0.64, 0.48)
const SPARK_COLORS: Array[Color] = [Color(1.0, 0.55, 0.2), Color(1.0, 0.95, 0.85), Color(1.0, 0.8, 0.3)]

# Exit ramp and lot, in site coordinates.
const RAMP_TAPER := 320.0    # the ramp starts widening this far before the gate
const RAMP_FULL := 220.0     # ...and is full width from here
const RAMP_OUTER := 25.0
const LOT_START := -40.0
const LOT_END := 520.0
const LOT_FAR := 150.0       # how far the paved lot reaches (visual)
const LOT_LIMIT := 112.0     # how far right you can drive in it
const AISLE_OUTER := 31.0    # the drive-in aisle stays clear up to here
const ROWS: Array[float] = [35.5, 41.5, 54.5, 60.5, 73.5, 79.5]
const STALL := 2.8
# The stadium: center (s, d), radii (along s, across), wall height.
const STADIUM := Vector2(330.0, 122.0)
const RADII := Vector2(110.0, 86.0)
const WALL := 34.0
const PLAZA := 1.18          # plaza ring, as a multiple of the radii
const SEGMENTS := 48
const SHOWCASE_HEIGHT := 30.0

var _scoreboard_top: Label3D
var _scoreboard_main: Label3D
var _marquee_top: Label3D
var _marquee_main: Label3D
var _shown_second := -1
var _finished := false
var _said := {}
var _flag_arm: Node3D
var _time := 0.0
var _bursts: Array[Dictionary] = []
var _bursts_left := 0
var _burst_in := 0.0
var _spark_mesh: BoxMesh
var _spark_mats: Array[Material] = []
var _rng := RandomNumberGenerator.new()
## Where the tailgates are (s along the first parking row).
var _tents: Array[float] = []


func _ready() -> void:
	_rng.seed = 35


# --- Road and rules -------------------------------------------------------------------

func _shape_road() -> void:
	var end := route.distance
	var shoulder := RoadSpec.shoulder_outer_edge()
	finish_min_d = RoadSpec.lanes_outer_edge()
	finish_brake = 0.6
	road.open_zone = Vector2(end - RAMP_TAPER - 10.0, end + LOT_END + 20.0)
	road.add_paved_zone(end - RAMP_TAPER, end - RAMP_FULL, shoulder - 0.5, (shoulder + RAMP_OUTER) * 0.5)
	road.add_paved_zone(end - RAMP_FULL, end + LOT_START, shoulder - 0.5, RAMP_OUTER)
	road.add_paved_zone(end + LOT_START, end + LOT_END, shoulder - 0.5, LOT_LIMIT)
	# A guardrail lines the ramp; past the gate the whole lot is open.
	road.add_limit_zone(end - RAMP_TAPER - 10.0, end + LOT_START, RAMP_OUTER + 0.6)
	road.add_limit_zone(end + LOT_START, end + LOT_END, LOT_LIMIT)


func hint_at(s: float, d: float) -> String:
	var to_go := route.distance - s
	if to_go < 680.0 and _say_once(&"ahead"):
		return "STADIUM EXIT AHEAD: KEEP RIGHT"
	if to_go < 200.0 and to_go > 0.0 and d < RoadSpec.lane_center(2) - 1.0 and _say_once(&"now"):
		return "THAT'S YOUR EXIT! GET RIGHT!"
	if to_go < 0.0 and d < finish_min_d and _say_once(&"missed"):
		return "MISSED IT! CUT RIGHT INTO THE LOT"
	return ""


func _say_once(key: StringName) -> bool:
	if _said.has(key):
		return false
	_said[key] = true
	return true


func on_clock(time_left: float) -> void:
	if _finished or _scoreboard_main == null:
		return
	var second := ceili(time_left)
	if second == _shown_second:
		return
	_shown_second = second
	if time_left <= 0.0:
		_show_board("KICKOFF!", "0:00")
	else:
		_show_board("KICKOFF IN", RaceClock.format(float(second)) if time_left >= 10.0 else str(second))


func on_finished() -> void:
	_finished = true
	_show_board("WELCOME,", "FAN!")
	_bursts_left = 7
	_burst_in = 0.2


## The stadium scoreboard and the roadside marquee show the same thing.
func _show_board(top: String, main: String) -> void:
	for label: Label3D in [_scoreboard_top, _marquee_top]:
		label.text = top
	for label: Label3D in [_scoreboard_main, _marquee_main]:
		label.text = main


func showcase_point() -> Variant:
	return to_global(_ring(0.0, 0.0, SHOWCASE_HEIGHT))


# --- Animation: the attendant's flag and the fireworks ----------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	if _flag_arm:
		_flag_arm.rotation.z = 0.9 + sin(_time * 7.0) * 0.6
	if _bursts_left > 0:
		_burst_in -= delta
		if _burst_in <= 0.0:
			_bursts_left -= 1
			_burst_in = _rng.randf_range(0.25, 0.5)
			_launch_burst()
	for i in range(_bursts.size() - 1, -1, -1):
		var burst := _bursts[i]
		burst.age += delta
		var t: float = burst.age / 1.8
		for spark: MeshInstance3D in burst.sparks:
			var v: Vector3 = spark.get_meta(&"v")
			v.y -= 7.0 * delta
			v *= exp(-1.2 * delta)
			spark.set_meta(&"v", v)
			spark.position += v * delta
			spark.scale = Vector3.ONE * maxf(1.0 - t, 0.01)
		if t >= 1.0:
			for spark: MeshInstance3D in burst.sparks:
				spark.queue_free()
			_bursts.remove_at(i)


func _launch_burst() -> void:
	if _spark_mesh == null:
		_spark_mesh = BoxMesh.new()
		_spark_mesh.size = Vector3.ONE * 2.8
		for color in SPARK_COLORS:
			_spark_mats.append(Materials.glow(color, 3.0))
	var center := _ring(_rng.randf() * TAU, _rng.randf_range(0.0, 0.5), _rng.randf_range(62.0, 84.0))
	Sfx.play(self, &"firework", _rng.randf_range(-11.0, -6.0), _rng.randf_range(0.85, 1.15))
	var material := _spark_mats[_rng.randi() % _spark_mats.size()]
	var burst := {"age": 0.0, "sparks": []}
	for i in 26:
		var spark := MeshInstance3D.new()
		spark.mesh = _spark_mesh
		spark.material_override = material
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spark.position = center
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 1), _rng.randf_range(-1, 1)).normalized()
		spark.set_meta(&"v", dir * _rng.randf_range(18.0, 30.0))
		add_child(spark)
		spark.reset_physics_interpolation()
		burst.sparks.append(spark)
	_bursts.append(burst)


# --- Building ----------------------------------------------------------------------------

func _build() -> void:
	var paved := MeshKit.new()
	var structures := MeshKit.new()
	var cars := MeshKit.new()
	var stadium := MeshKit.new()
	var glow := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var tent_s := 24.0
	while tent_s < 210.0:
		_tents.append(tent_s)
		tent_s += rng.randf_range(15.0, 24.0)
	_build_pavement(paved)
	_build_signs(structures)
	_build_gate(structures)
	_build_lot(structures, cars, glow)
	_build_stadium(stadium, glow)
	add_child(Scenery.mesh_node("Pavement", paved, false))
	add_child(Scenery.mesh_node("Structures", structures))
	add_child(Scenery.mesh_node("ParkedCars", cars))
	add_child(Scenery.mesh_node("Stadium", stadium, false))
	add_child(Scenery.mesh_node("Lights", glow, false, Materials.glow(Palette.HEADLIGHT, 1.4)))
	_build_labels()
	_build_attendant()
	_build_smoke()


## Point on the stadium's ellipse: angle a (0 = far end, PI = the end facing the
## approach, -PI/2 = the side facing the highway), scaled, at height y.
func _ring(a: float, scale: float, y: float) -> Vector3:
	var s := STADIUM.x + RADII.x * scale * cos(a)
	var d := STADIUM.y + RADII.y * scale * sin(a)
	return Vector3(d, y, -s)


func _ring_normal(a: float) -> Vector3:
	return Vector3(sin(a) / RADII.y, 0.0, -cos(a) / RADII.x).normalized()


func _in_plaza(s: float, d: float, margin := 1.0) -> bool:
	var u := (s - STADIUM.x) / (RADII.x * PLAZA * margin)
	var v := (d - STADIUM.y) / (RADII.y * PLAZA * margin)
	return u * u + v * v < 1.0


func _build_pavement(mk: MeshKit) -> void:
	var shoulder := RoadSpec.shoulder_outer_edge()
	# Ramp: widens off the shoulder, then runs full width to the gate.
	var steps := 8
	for i in steps:
		var s0 := lerpf(-RAMP_TAPER, -RAMP_FULL, float(i) / steps)
		var s1 := lerpf(-RAMP_TAPER, -RAMP_FULL, float(i + 1) / steps)
		var w0 := lerpf(shoulder, RAMP_OUTER, float(i) / steps)
		var w1 := lerpf(shoulder, RAMP_OUTER, float(i + 1) / steps)
		mk.quad(Vector3(shoulder, 0.015, -s0), Vector3(w0, 0.015, -s0), Vector3(w1, 0.015, -s1),
			Vector3(shoulder, 0.015, -s1), Vector3.UP, Palette.ASPHALT)
	Scenery.ground_rect(mk, -RAMP_FULL, LOT_START, shoulder, RAMP_OUTER, 0.015, Palette.ASPHALT)
	Scenery.ground_rect(mk, LOT_START, LOT_END, shoulder, LOT_FAR, 0.015, LOT_ASPHALT)
	# Concrete plaza around the stadium.
	var center := _ring(0.0, 0.0, 0.03)
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		mk.tri(center, _ring(a0, PLAZA, 0.03), _ring(a1, PLAZA, 0.03), Vector3.UP, Palette.CONCRETE_SHADE)
	# Paint: the exit lane's dashed edge, arrows, the lot edge, the checkered gate line.
	var s := -RAMP_FULL
	while s < -6.0:
		Scenery.ground_rect(mk, s, s + 3.0, shoulder - 0.08, shoulder + 0.08, 0.045, Palette.LANE_WHITE)
		s += 12.0
	for arrow_s: float in [-160.0, -80.0]:
		Scenery.road_arrow(mk, Scenery.at(arrow_s, (shoulder + RAMP_OUTER) * 0.5), Palette.LANE_WHITE)
	Scenery.ground_rect(mk, 4.0, LOT_END, shoulder + 0.1, shoulder + 0.26, 0.045, Palette.LANE_WHITE)
	var from := RoadSpec.lanes_outer_edge()
	var count := 12
	var sq := (RAMP_OUTER - from) / count
	for row in 2:
		for i in count:
			var dark := (i + row) % 2 == 0
			Scenery.ground_rect(mk, (row - 1) * sq, row * sq, from + i * sq, from + (i + 1) * sq, 0.05,
				Palette.UI_TEXT if dark else Palette.LANE_WHITE)
	# Stall lines for every parking row.
	for row_d in ROWS:
		var stall_s := LOT_START + 6.0
		while stall_s < LOT_END - 6.0:
			if not _in_plaza(stall_s, row_d):
				Scenery.ground_rect(mk, stall_s - 0.06, stall_s + 0.06, row_d - 2.8, row_d + 2.8, 0.045, Palette.LANE_WHITE)
			stall_s += STALL


func _build_signs(mk: MeshKit) -> void:
	# Half a mile out: a big green roadside sign with an exit tab.
	var far := Scenery.at(-600.0, 20.5)
	Scenery.sign_board(mk, far, Vector2(9.0, 3.4), 2.4, Palette.SIGN_GREEN)
	mk.xf = far
	mk.box(Vector3(-2.6, 6.55, 0.0), Vector3(3.5, 1.1, 0.1), Palette.SIGN_WHITE)
	mk.box(Vector3(-2.6, 6.55, 0.03), Vector3(3.3, 0.9, 0.1), Palette.SIGN_GREEN)
	# At the ramp: an overhead sign over the right lane, with a yellow EXIT ONLY plate.
	mk.xf = Scenery.at(-360.0, 20.5)
	mk.box(Vector3(0, 4.3, -0.3), Vector3(0.4, 8.6, 0.4), Palette.HUB)
	mk.box(Vector3(-7.0, 8.2, -0.3), Vector3(14.0, 0.3, 0.3), Palette.HUB)
	mk.box(Vector3(-8.0, 6.7, 0.0), Vector3(10.2, 3.0, 0.1), Palette.SIGN_WHITE)
	mk.box(Vector3(-8.0, 6.7, 0.03), Vector3(10.0, 2.8, 0.1), Palette.SIGN_GREEN)
	mk.box(Vector3(-6.0, 4.75, 0.03), Vector3(4.4, 0.95, 0.1), Palette.WORK_YELLOW)
	mk.xf = Transform3D.IDENTITY
	# Guardrail along the ramp's outer edge.
	var post_s := -RAMP_TAPER + 10.0
	while post_s < LOT_START:
		mk.xf = Scenery.at(post_s, RAMP_OUTER + 0.9)
		mk.box(Vector3(0, 0.4, 0), Vector3(0.14, 0.8, 0.14), Palette.HUB)
		post_s += 4.0
	mk.xf = Transform3D.IDENTITY
	var rail_from := -RAMP_TAPER + 10.0
	mk.box(Vector3(RAMP_OUTER + 0.82, 0.65, -(rail_from + LOT_START) * 0.5), Vector3(0.1, 0.32, LOT_START - rail_from), Palette.HUB)


func _build_gate(mk: MeshKit) -> void:
	# Cantilevered "STADIUM PARKING" sign over the ramp.
	mk.xf = Scenery.at(0.0, 27.6)
	mk.box(Vector3(0, 3.7, -0.4), Vector3(0.45, 7.4, 0.45), Palette.HUB)
	mk.box(Vector3(-7.0, 7.0, -0.4), Vector3(14.0, 0.3, 0.3), Palette.HUB)
	mk.box(Vector3(-8.0, 8.1, 0.0), Vector3(11.4, 2.5, 0.12), Palette.SIGN_WHITE)
	mk.box(Vector3(-8.0, 8.1, 0.03), Vector3(11.0, 2.1, 0.12), TEAM)
	# Ticket booth with a striped arm (raised, today's your lucky day).
	mk.xf = Scenery.at(6.0, 30.5)
	mk.box(Vector3(0, 1.35, 0), Vector3(2.6, 2.7, 2.4), Palette.SIGN_WHITE)
	mk.box(Vector3(-1.31, 1.7, 0), Vector3(0.04, 0.9, 1.8), Palette.GLASS)
	mk.box(Vector3(0, 2.85, 0), Vector3(3.2, 0.3, 3.0), TEAM)
	for i in 6:
		mk.box(Vector3(-1.6, 1.4 + i * 0.6, 1.0), Vector3(0.14, 0.6, 0.14), Palette.POLICE_RED if i % 2 == 0 else Palette.SIGN_WHITE)
	mk.xf = Transform3D.IDENTITY
	# Price sign just before the gate.
	Scenery.sign_board(mk, Scenery.at(-26.0, 28.4), Vector2(4.8, 3.0), 0.8, Palette.SIGN_WHITE, TEAM)
	# The stadium's roadside marquee, angled toward the exit ramp.
	mk.xf = _marquee_xf()
	mk.box(Vector3(0, 5.0, -0.6), Vector3(1.6, 10.0, 1.2), Palette.CONCRETE)
	mk.box(Vector3(0, 13.0, -0.4), Vector3(15.4, 8.2, 1.0), TEAM)
	mk.box(Vector3(0, 13.0, 0.0), Vector3(14.0, 6.8, 0.4), Color(0.09, 0.09, 0.1))
	mk.xf = Transform3D.IDENTITY


func _marquee_xf() -> Transform3D:
	return Scenery.at(-70.0, 33.0, -0.45)


func _build_lot(mk: MeshKit, cars: MeshKit, glow: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	# Tailgates line the first row along the drive-in aisle.
	for i in _tents.size():
		_tailgate(mk, _tents[i], 34.6, i, rng)
	# Parked cars, nose to nose in double rows, leaving room for the tents.
	for row in ROWS.size():
		var row_d := ROWS[row]
		var yaw := PI * 0.5 if row % 2 == 0 else -PI * 0.5
		var stall_s := LOT_START + 6.0 + STALL * 0.5
		while stall_s < LOT_END - 6.0:
			var here := stall_s
			stall_s += STALL
			if _in_plaza(here, row_d, 1.04):
				continue
			if row == 0 and _tents.any(func(t: float) -> bool: return absf(t - here) < 3.4):
				continue
			if rng.randf() > (0.86 if row_d < 50.0 else 0.72):
				continue
			var paint := TEAM if rng.randf() < 0.3 else Palette.TRAFFIC_PAINTS[rng.randi() % Palette.TRAFFIC_PAINTS.size()]
			Scenery.parked_car(cars, Scenery.at(here, row_d, yaw + rng.randf_range(-0.05, 0.05)), paint, rng.randi() % 3)
	# Light poles along the aisle.
	var pole_s := 20.0
	while pole_s < LOT_END - 20.0:
		if not _in_plaza(pole_s, AISLE_OUTER + 1.0):
			Scenery.light_pole(mk, glow, Scenery.at(pole_s, AISLE_OUTER + 1.0))
		pole_s += 70.0
	# Fans streaming toward the gates.
	for i in 26:
		var a := PI + rng.randf_range(-0.9, 0.9)
		var spot := _ring(a, PLAZA * rng.randf_range(0.92, 1.0), 0.0)
		var face := atan2(_ring(a, 0.0, 0.0).x - spot.x, _ring(a, 0.0, 0.0).z - spot.z)
		Scenery.person(mk, Transform3D(Basis(Vector3.UP, face), spot), _shirt(rng), _pants(rng),
			Scenery.SKIN[rng.randi() % Scenery.SKIN.size()], rng.randf() < 0.2)


## One tailgate: a canopy, a grill, a cooler, maybe cornhole, and the crew.
func _tailgate(mk: MeshKit, s: float, d: float, index: int, rng: RandomNumberGenerator) -> void:
	Scenery.canopy(mk, Scenery.at(s, d), TEAM if index % 2 == 0 else Palette.SIGN_WHITE)
	Scenery.grill(mk, Scenery.at(s + 1.9, d - 1.2))
	Scenery.cooler(mk, Scenery.at(s - 1.6, d - 1.0), Palette.POLICE_BLUE if index % 3 == 0 else Palette.POLICE_RED)
	if index % 3 == 1:
		Scenery.cornhole(mk, Scenery.at(s - 1.0, d - 4.2, PI * 0.5), TEAM)
		Scenery.cornhole(mk, Scenery.at(s + 6.0, d - 4.2, -PI * 0.5), TEAM)
	for i in rng.randi_range(2, 4):
		var spot := Scenery.at(s + rng.randf_range(-1.8, 1.8), d - rng.randf_range(1.6, 3.2), rng.randf_range(-PI, PI))
		Scenery.person(mk, spot, _shirt(rng), _pants(rng), Scenery.SKIN[rng.randi() % Scenery.SKIN.size()],
			rng.randf() < 0.35)


func _shirt(rng: RandomNumberGenerator) -> Color:
	return TEAM if rng.randf() < 0.65 else (Palette.SIGN_WHITE if rng.randf() < 0.6 else Palette.TRIM)


func _pants(rng: RandomNumberGenerator) -> Color:
	return DENIM if rng.randf() < 0.7 else KHAKI


func _build_stadium(mk: MeshKit, glow: MeshKit) -> void:
	var dark := Color(0.22, 0.2, 0.19)
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var am := (a0 + a1) * 0.5
		var n := _ring_normal(am)
		# Facade, the team-color band near the top, and the rim.
		mk.quad(_ring(a0, 1.0, 0.0), _ring(a1, 1.0, 0.0), _ring(a1, 1.0, WALL), _ring(a0, 1.0, WALL), n, Palette.CONCRETE)
		mk.quad(_ring(a0, 1.004, WALL - 7.0), _ring(a1, 1.004, WALL - 7.0), _ring(a1, 1.004, WALL - 3.5),
			_ring(a0, 1.004, WALL - 3.5), n, TEAM)
		mk.quad(_ring(a0, 1.0, WALL), _ring(a1, 1.0, WALL), _ring(a1, 0.93, WALL), _ring(a0, 0.93, WALL), Vector3.UP,
			Palette.CONCRETE_SHADE)
		# Concourse gates at ground level and a row of windows.
		var g0 := lerpf(a0, a1, 0.2)
		var g1 := lerpf(a0, a1, 0.8)
		if i % 2 == 0:
			mk.quad(_ring(g0, 1.006, 0.2), _ring(g1, 1.006, 0.2), _ring(g1, 1.006, 7.0), _ring(g0, 1.006, 7.0), n, dark)
		mk.quad(_ring(g0, 1.006, 14.0), _ring(g1, 1.006, 14.0), _ring(g1, 1.006, 17.0), _ring(g0, 1.006, 17.0), n, dark)
		# Stands sloping down to the field, in team-color and white sections.
		var seats := TEAM if (i / 4) % 2 == 0 else Palette.SIGN_WHITE
		mk.quad(_ring(a0, 0.93, WALL - 1.0), _ring(a1, 0.93, WALL - 1.0), _ring(a1, 0.6, 3.0), _ring(a0, 0.6, 3.0),
			Vector3.UP, seats)
		# Pennants on the rim.
		if i % 3 == 0:
			var p := _ring(am, 0.995, WALL)
			mk.xf = Transform3D(Basis.IDENTITY, p)
			mk.box(Vector3(0, 2.0, 0), Vector3(0.15, 4.0, 0.15), Palette.HUB)
			mk.box(Vector3(0.8, 3.4, 0), Vector3(1.6, 1.0, 0.06), TEAM if i % 2 == 0 else Palette.SIGN_WHITE)
			mk.xf = Transform3D.IDENTITY
	# The field: grass, team-color end zones, a few white lines.
	var field := Vector2(110.0, 49.0)
	var c := STADIUM
	Scenery.ground_rect(mk, c.x - field.x * 0.5, c.x + field.x * 0.5, c.y - field.y * 0.5, c.y + field.y * 0.5, 0.2,
		Color(0.36, 0.55, 0.3))
	for end: float in [-1.0, 1.0]:
		var e0 := c.x + end * field.x * 0.5
		Scenery.ground_rect(mk, minf(e0, e0 - end * 10.0), maxf(e0, e0 - end * 10.0), c.y - field.y * 0.5,
			c.y + field.y * 0.5, 0.22, TEAM)
	var yard := -40.0
	while yard <= 40.0:
		Scenery.ground_rect(mk, c.x + yard - 0.15, c.x + yard + 0.15, c.y - field.y * 0.5, c.y + field.y * 0.5, 0.23,
			Palette.SIGN_WHITE)
		yard += 10.0
	# Press box on the side facing the highway.
	var press := _ring(-PI * 0.5, 0.96, 0.0)
	mk.xf = Transform3D(Basis.IDENTITY, press)
	mk.box(Vector3(2.0, WALL + 4.5, 0), Vector3(9.0, 9.0, 70.0), Palette.CONCRETE)
	mk.box(Vector3(-2.55, WALL + 5.0, 0), Vector3(0.1, 3.4, 66.0), Palette.GLASS)
	mk.box(Vector3(2.0, WALL + 9.2, 0), Vector3(9.6, 0.6, 71.0), TEAM)
	mk.xf = Transform3D.IDENTITY
	# Light towers, banks tilted toward the field.
	for a: float in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var foot := _ring(a, 1.1, 0.0)
		var inward := atan2(_ring(a, 0.0, 0.0).x - foot.x, _ring(a, 0.0, 0.0).z - foot.z)
		mk.xf = Transform3D(Basis(Vector3.UP, inward), foot)
		mk.prism(Vector3.ZERO, 1.6, 0.7, 64.0, 4, Palette.HUB)
		mk.box(Vector3(0, 66.0, -0.6), Vector3(11.0, 6.5, 1.0), Palette.TRIM)
		glow.xf = Transform3D(Basis(Vector3.UP, inward) * Basis(Vector3.RIGHT, -0.35), foot + Vector3.UP * 66.0)
		glow.box(Vector3(0, 0, 0.6), Vector3(10.0, 5.5, 0.3), Palette.HEADLIGHT)
	mk.xf = Transform3D.IDENTITY
	glow.xf = Transform3D.IDENTITY
	# Scoreboard above the far end, facing the field and the approach.
	var board := _ring(0.0, 0.9, 0.0)
	mk.xf = Transform3D(Basis.IDENTITY, board)
	for x: float in [-14.0, 14.0]:
		mk.box(Vector3(x, WALL * 0.5 + 6.0, 0), Vector3(2.0, WALL + 12.0, 2.0), Palette.HUB)
	mk.box(Vector3(0, WALL + 15.0, 0), Vector3(54.0, 28.0, 2.4), TEAM)
	mk.box(Vector3(0, WALL + 15.0, 0.5), Vector3(50.0, 24.0, 2.0), Color(0.09, 0.09, 0.1))
	mk.xf = Transform3D.IDENTITY
	# Name banner in front of the end facing the approach (low enough for the chase camera).
	var front := _ring(PI, 1.0, 0.0) + Vector3(0, 0, 3.0)
	Scenery.sign_board(mk, Transform3D(Basis.IDENTITY, front), Vector2(46.0, 10.0), 6.0, TEAM)


func _build_labels() -> void:
	var dark := Palette.UI_TEXT
	var far := Scenery.at(-600.0, 20.5)
	add_child(Scenery.sign_text(far, 4.1, ["STADIUM PARKING", "1/2 MILE"], [80, 56]))
	add_child(Scenery.sign_text(far * Transform3D(Basis.IDENTITY, Vector3(-2.6, 0, 0)), 6.55, ["EXIT 235"], [52]))
	var over := Scenery.at(-360.0, 20.5) * Transform3D(Basis.IDENTITY, Vector3(-8.0, 0, 0))
	add_child(Scenery.sign_text(over, 6.7, ["STADIUM PARKING", "EXIT 235"], [80, 52]))
	add_child(Scenery.sign_text(over * Transform3D(Basis.IDENTITY, Vector3(2.0, 0, 0)), 4.75, ["EXIT ONLY"], [62], dark))
	var gate := Scenery.at(0.0, 27.6) * Transform3D(Basis.IDENTITY, Vector3(-8.0, 0, 0.1))
	add_child(Scenery.sign_text(gate, 8.1, ["STADIUM PARKING"], [116]))
	add_child(Scenery.sign_text(Scenery.at(-26.0, 28.4), 2.3, ["GAME DAY PARKING", "$80", "CASH ONLY  ·  NO REFUNDS"],
		[42, 110, 30], dark))
	var front := Transform3D(Basis.IDENTITY, _ring(PI, 1.0, 0.0) + Vector3(0, 0, 3.0))
	add_child(Scenery.sign_text(front, 11.0, ["TEXAS-SIZED", "MEMORIAL STADIUM"], [190, 130], Palette.SIGN_WHITE, 0.025))
	var board := Transform3D(Basis.IDENTITY, _ring(0.0, 0.9, 0.0) + Vector3(0, 0, 1.6))
	var amber := Color(1.0, 0.72, 0.28)
	_scoreboard_top = Scenery.label("KICKOFF IN", 210, 0.025, amber)
	_scoreboard_top.transform = board * Transform3D(Basis.IDENTITY, Vector3(0, WALL + 22.0, 0))
	add_child(_scoreboard_top)
	_scoreboard_main = Scenery.label("", 400, 0.025, amber)
	_scoreboard_main.transform = board * Transform3D(Basis.IDENTITY, Vector3(0, WALL + 10.5, 0))
	add_child(_scoreboard_main)
	_marquee_top = Scenery.label("KICKOFF IN", 120, 0.012, amber)
	_marquee_top.transform = _marquee_xf() * Transform3D(Basis.IDENTITY, Vector3(0, 15.0, 0.25))
	add_child(_marquee_top)
	_marquee_main = Scenery.label("", 300, 0.012, amber)
	_marquee_main.transform = _marquee_xf() * Transform3D(Basis.IDENTITY, Vector3(0, 11.9, 0.25))
	add_child(_marquee_main)


## The parking attendant at the gate, waving a flag that never stops.
func _build_attendant() -> void:
	var mk := MeshKit.new()
	Scenery.person(mk, Transform3D.IDENTITY, Palette.WORK_YELLOW, DENIM, Scenery.SKIN[2])
	var body := Scenery.mesh_node("Attendant", mk)
	body.transform = Scenery.at(1.5, 26.6, -0.5)
	add_child(body)
	_flag_arm = Node3D.new()
	_flag_arm.position = Vector3(0.3, 1.38, 0)
	body.add_child(_flag_arm)
	var arm := MeshKit.new()
	arm.box(Vector3(0, 0.3, 0), Vector3(0.12, 0.6, 0.12), Palette.WORK_YELLOW)
	arm.box(Vector3(0, 0.95, 0), Vector3(0.04, 0.9, 0.04), Palette.HUB)
	arm.box(Vector3(0.3, 1.2, 0), Vector3(0.6, 0.42, 0.03), Palette.CONE_ORANGE)
	_flag_arm.add_child(Scenery.mesh_node("Flag", arm))


## Grill smoke at every other tailgate.
func _build_smoke() -> void:
	for i in range(0, _tents.size(), 2):
		var smoke := SmokePlume.new()
		smoke.position = Scenery.at(_tents[i] + 1.9, 34.6 - 1.2).origin + Vector3(0, 0.9, 0)
		smoke.scale = Vector3.ONE * 0.45
		add_child(smoke)
		smoke.start()
