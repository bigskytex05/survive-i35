class_name TrafficModel
extends RefCounted
## Placeholder low-poly traffic vehicles built in code, cached per
## (style, size, paint) so pooled cars share meshes.
##
## A car is one body mesh (wheels included: from the chase camera they're too
## small to see spin) plus small light meshes that use shared glowing
## materials: taillights (dim or braking), turn signals, a work-truck beacon and
## a police light bar (red and blue halves that flash when the lights are on).
## Local space matches the player's car: -Z is forward, +X is right.

static var _bodies: Dictionary = {}
static var _lights: Dictionary = {}
static var _tail_dim: ShaderMaterial
static var _tail_bright: ShaderMaterial
static var _blinker: ShaderMaterial
static var _beacon: ShaderMaterial
static var _police: Dictionary = {}


static func body_mesh(data: TrafficCarData, paint: Color) -> ArrayMesh:
	var key := "%d|%s|%s" % [data.body_style, data.size, paint.to_html()]
	if not _bodies.has(key):
		_bodies[key] = _build_body(data.body_style, data.size, paint)
	return _bodies[key]


static func tail_mesh(data: TrafficCarData) -> ArrayMesh:
	return _light(data, "tail", func(mk: MeshKit, w: float, l: float, rear_y: float, _front_y: float) -> void:
		for x: float in [-1.0, 1.0]:
			mk.box(Vector3(x * (w * 0.5 - 0.26), rear_y, l * 0.5 + 0.02), Vector3(0.36, 0.2, 0.06), Palette.TAILLIGHT))


## Turn-signal lamps on one side (-1 = left, 1 = right), front and rear.
static func blinker_mesh(data: TrafficCarData, side: float) -> ArrayMesh:
	return _light(data, "blink%d" % side, func(mk: MeshKit, w: float, l: float, rear_y: float, front_y: float) -> void:
		mk.box(Vector3(side * (w * 0.5 - 0.12), front_y, -l * 0.5 - 0.03), Vector3(0.22, 0.14, 0.06), Palette.AMBER)
		mk.box(Vector3(side * (w * 0.5 - 0.06), rear_y + 0.18, l * 0.5 + 0.03), Vector3(0.14, 0.16, 0.06), Palette.AMBER))


## Amber light bar on a work truck's cab roof.
static func beacon_mesh(data: TrafficCarData) -> ArrayMesh:
	return _light(data, "beacon", func(mk: MeshKit, w: float, l: float, _rear_y: float, _front_y: float) -> void:
		mk.box(Vector3(0.0, data.size.y * 0.87 + 0.12, -l * 0.5 + 1.2), Vector3(w * 0.5, 0.2, 0.32), Palette.AMBER))


## One half of a police light bar: -1 = the red (left) half, 1 = the blue one.
static func police_bar_mesh(data: TrafficCarData, side: float) -> ArrayMesh:
	return _light(data, "police%d" % side, func(mk: MeshKit, w: float, l: float, _rear_y: float, _front_y: float) -> void:
		var color := Palette.POLICE_RED if side < 0.0 else Palette.POLICE_BLUE
		mk.box(Vector3(side * w * 0.2, data.size.y + 0.1, -l * 0.04), Vector3(w * 0.38, 0.16, 0.34), color))


## Light bar material: `lit` is a flash, otherwise the lens just shows its color.
static func police_material(side: float, lit: bool) -> ShaderMaterial:
	var key := "%d|%s" % [side, lit]
	if not _police.has(key):
		var color := Palette.POLICE_RED if side < 0.0 else Palette.POLICE_BLUE
		_police[key] = Materials.glow(color, 4.5 if lit else 0.25)
	return _police[key]


static func tail_material(braking: bool) -> ShaderMaterial:
	if _tail_dim == null:
		_tail_dim = Materials.glow(Palette.TAILLIGHT, 0.4)
		_tail_bright = Materials.glow(Palette.TAILLIGHT, 2.6)
	return _tail_bright if braking else _tail_dim


static func blinker_material() -> ShaderMaterial:
	if _blinker == null:
		_blinker = Materials.glow(Palette.AMBER, 2.6)
	return _blinker


## Shared by every beacon; TrafficSpawner pulses its brightness.
static func beacon_material() -> ShaderMaterial:
	if _beacon == null:
		_beacon = Materials.glow(Palette.AMBER, 1.0)
	return _beacon


static func _light(data: TrafficCarData, kind: String, build: Callable) -> ArrayMesh:
	var key := "%s|%d|%s" % [kind, data.body_style, data.size]
	if not _lights.has(key):
		var heights := _lamp_heights(data.body_style, data.size.y)
		var mk := MeshKit.new()
		build.call(mk, data.size.x, data.size.z, heights.x, heights.y)
		_lights[key] = mk.commit()
	return _lights[key]


## Lamp heights for a body style: x = rear lamps, y = front lamps.
static func _lamp_heights(style: TrafficCarData.BodyStyle, h: float) -> Vector2:
	match style:
		TrafficCarData.BodyStyle.SEMI:
			return Vector2(1.45, 1.3)
		TrafficCarData.BodyStyle.WORK_TRUCK:
			return Vector2(1.15, 1.25)
		TrafficCarData.BodyStyle.PICKUP:
			return Vector2(h * 0.6 - 0.2, h * 0.6 - 0.15)
		TrafficCarData.BodyStyle.MINIVAN:
			return Vector2(h * 0.55 - 0.1, h * 0.55 - 0.15)
	return Vector2(h * 0.58 - 0.14, h * 0.58 - 0.18)


static func _build_body(style: TrafficCarData.BodyStyle, size: Vector3, paint: Color) -> ArrayMesh:
	var mk := MeshKit.new()
	match style:
		TrafficCarData.BodyStyle.SEDAN:
			_car(mk, size, paint, 0.34, 0.58, 0.48, 0.05)
		TrafficCarData.BodyStyle.MINIVAN:
			_car(mk, size, paint, 0.36, 0.55, 0.72, 0.1)
		TrafficCarData.BodyStyle.PICKUP:
			_pickup(mk, size, paint)
		TrafficCarData.BodyStyle.SEMI:
			_semi(mk, size, paint)
		TrafficCarData.BodyStyle.WORK_TRUCK:
			_work_truck(mk, size, paint)
		TrafficCarData.BodyStyle.POLICE:
			_police_car(mk, size, paint)
	return mk.commit()


## Box car: lower body, inset glass cabin and a roof. Cabin length and offset
## are fractions of the car length (positive offset = toward the rear).
static func _car(mk: MeshKit, size: Vector3, paint: Color, r: float, belt: float,
		cabin: float, cabin_offset: float) -> void:
	var w := size.x
	var h := size.y
	var l := size.z
	var floor_y := r * 0.9
	var belt_y := h * belt
	var roof_y := h - 0.06
	var cabin_len := l * cabin
	var cabin_z := l * cabin_offset
	mk.box(Vector3(0, (floor_y + belt_y) * 0.5, 0), Vector3(w, belt_y - floor_y, l), paint)
	mk.box(Vector3(0, (belt_y + roof_y) * 0.5, cabin_z), Vector3(w * 0.84, roof_y - belt_y, cabin_len), Palette.GLASS)
	mk.box(Vector3(0, roof_y + 0.04, cabin_z), Vector3(w * 0.88, 0.1, cabin_len + 0.06), paint.lightened(0.08))
	_trim(mk, w, l, floor_y)
	_headlights(mk, w, l, belt_y - 0.18)
	_wheels(mk, w, r, [-(l * 0.5 - r - 0.5), l * 0.5 - r - 0.5])


static func _pickup(mk: MeshKit, size: Vector3, paint: Color) -> void:
	var w := size.x
	var h := size.y
	var l := size.z
	var r := 0.42
	var floor_y := r * 0.95
	var belt_y := h * 0.6
	var roof_y := h - 0.05
	var cab_front := -l * 0.5 + l * 0.3
	var bed_front := l * 0.06
	# Hood and cab as one lower box, glass cab on top.
	mk.box(Vector3(0, (floor_y + belt_y) * 0.5, (-l * 0.5 + bed_front) * 0.5), Vector3(w, belt_y - floor_y, bed_front + l * 0.5), paint)
	mk.box(Vector3(0, (belt_y + roof_y) * 0.5, (cab_front + bed_front) * 0.5), Vector3(w * 0.86, roof_y - belt_y, bed_front - cab_front), Palette.GLASS)
	mk.box(Vector3(0, roof_y + 0.04, (cab_front + bed_front) * 0.5), Vector3(w * 0.9, 0.1, bed_front - cab_front + 0.06), paint.lightened(0.08))
	# Open bed: floor, two side walls and a tailgate.
	var bed_len := l * 0.5 - bed_front
	var bed_mid := (bed_front + l * 0.5) * 0.5
	mk.box(Vector3(0, floor_y + 0.12, bed_mid), Vector3(w, 0.24, bed_len), Palette.TRIM)
	for x: float in [-1.0, 1.0]:
		mk.box(Vector3(x * (w * 0.5 - 0.06), (floor_y + belt_y) * 0.5, bed_mid), Vector3(0.12, belt_y - floor_y, bed_len), paint)
	mk.box(Vector3(0, (floor_y + belt_y) * 0.5, l * 0.5 - 0.06), Vector3(w, belt_y - floor_y, 0.12), paint)
	_trim(mk, w, l, floor_y)
	_headlights(mk, w, l, belt_y - 0.15)
	_wheels(mk, w, r, [-(l * 0.5 - r - 0.55), l * 0.5 - r - 0.6])


## Conventional American tractor (long hood, tall sleeper) and a box trailer.
static func _semi(mk: MeshKit, size: Vector3, paint: Color) -> void:
	var w := size.x
	var h := size.y
	var l := size.z
	var r := 0.52
	var front := -l * 0.5
	var trailer_front := front + 5.4
	# Tractor: chassis, hood, sleeper cab, windshield band and grille.
	mk.box(Vector3(0, 0.75, front + 3.1), Vector3(w * 0.8, 0.5, 6.2), Palette.TRIM)
	mk.box(Vector3(0, 1.3, front + 1.05), Vector3(w * 0.88, 1.2, 2.1), paint)
	mk.box(Vector3(0, 2.05, front + 3.4), Vector3(w * 0.96, 2.7, 2.6), paint)
	mk.box(Vector3(0, 2.8, front + 2.12), Vector3(w * 0.9, 0.7, 0.06), Palette.GLASS)
	mk.box(Vector3(0, 1.25, front - 0.04), Vector3(w * 0.6, 0.8, 0.08), Palette.TRIM)
	_headlights(mk, w * 0.88, l, 1.3)
	# Trailer: a long box riding high, with a dark undercarriage at the back.
	var trailer_len := l * 0.5 - trailer_front
	var trailer_mid := (trailer_front + l * 0.5) * 0.5
	mk.box(Vector3(0, (1.3 + h) * 0.5, trailer_mid), Vector3(w, h - 1.3, trailer_len), Palette.TRAILER, Palette.TRAILER.darkened(0.04))
	mk.box(Vector3(0, 1.0, l * 0.5 - 2.0), Vector3(w * 0.9, 0.5, 3.6), Palette.TRIM)
	mk.box(Vector3(0, 0.75, l * 0.5 - 0.1), Vector3(w * 0.96, 0.18, 0.12), Palette.TRIM)
	_wheels(mk, w, r, [front + 1.2, front + 4.4, front + 5.6, l * 0.5 - 2.6, l * 0.5 - 1.4], 0.6)


## Cab-over dump truck with a tall bed and a striped rear bumper.
static func _work_truck(mk: MeshKit, size: Vector3, paint: Color) -> void:
	var w := size.x
	var h := size.y
	var l := size.z
	var r := 0.55
	var front := -l * 0.5
	var cab_back := front + 2.4
	mk.box(Vector3(0, 0.8, 0), Vector3(w * 0.8, 0.5, l - 0.4), Palette.TRIM)
	mk.box(Vector3(0, 1.25, (front + cab_back) * 0.5), Vector3(w, 1.3, 2.4), paint)
	mk.box(Vector3(0, 2.25, (front + cab_back) * 0.5), Vector3(w * 0.92, 0.7, 2.3), Palette.GLASS)
	mk.box(Vector3(0, h * 0.87, (front + cab_back) * 0.5), Vector3(w * 0.96, 0.16, 2.4), paint.lightened(0.08))
	_headlights(mk, w, l, 1.25)
	var bed_front := cab_back + 0.3
	var bed_mid := (bed_front + l * 0.5 - 0.2) * 0.5
	var bed_len := l * 0.5 - 0.2 - bed_front
	mk.box(Vector3(0, (1.15 + h) * 0.5, bed_mid), Vector3(w, h - 1.15, bed_len), paint.darkened(0.06), paint)
	# Orange-and-white striped bumper.
	for i in 6:
		var x := -w * 0.5 + w * (i + 0.5) / 6.0
		mk.box(Vector3(x, 0.75, l * 0.5 - 0.1), Vector3(w / 6.0, 0.22, 0.14), Palette.CONE_ORANGE if i % 2 == 0 else Palette.SIGN_WHITE)
	_wheels(mk, w, r, [front + 1.2, l * 0.5 - 2.5, l * 0.5 - 1.3], 0.5)


## A state trooper's cruiser: a black sedan with white doors, a push bar and
## (separately, so it can flash) the light bar on the roof.
static func _police_car(mk: MeshKit, size: Vector3, paint: Color) -> void:
	_car(mk, size, paint, 0.36, 0.56, 0.46, 0.04)
	var w := size.x
	var l := size.z
	var r := 0.36
	var belt_y := size.y * 0.56
	for x: float in [-1.0, 1.0]:
		mk.box(Vector3(x * (w * 0.5 + 0.01), (r * 0.9 + belt_y) * 0.5 + 0.04, l * 0.02), Vector3(0.04, belt_y - r * 0.9 - 0.1, l * 0.42), Palette.SIGN_WHITE)
	mk.box(Vector3(0, r + 0.15, -l * 0.5 - 0.18), Vector3(w * 0.6, 0.34, 0.12), Palette.TRIM)
	mk.box(Vector3(0, size.y + 0.0, -l * 0.04), Vector3(w * 0.84, 0.06, 0.4), Palette.TRIM)


static func _trim(mk: MeshKit, w: float, l: float, floor_y: float) -> void:
	mk.box(Vector3(0, floor_y + 0.1, -l * 0.5 - 0.05), Vector3(w * 1.02, 0.24, 0.16), Palette.TRIM)
	mk.box(Vector3(0, floor_y + 0.1, l * 0.5 + 0.05), Vector3(w * 1.02, 0.24, 0.16), Palette.TRIM)
	mk.box(Vector3(0, floor_y + 0.03, 0), Vector3(w * 1.01, 0.1, l * 0.98), Palette.TRIM)


static func _headlights(mk: MeshKit, w: float, l: float, y: float) -> void:
	for x: float in [-1.0, 1.0]:
		mk.box(Vector3(x * (w * 0.5 - 0.32), y, -l * 0.5 - 0.02), Vector3(0.38, 0.15, 0.05), Palette.HEADLIGHT)


## Eight-sided wheels on both sides at each axle position (z values).
static func _wheels(mk: MeshKit, w: float, r: float, axles: Array, width := 0.36) -> void:
	for z: float in axles:
		for x: float in [-1.0, 1.0]:
			# Build the cylinder along Y, then lay it on its side (axis along X).
			mk.xf = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x * (w * 0.5 - width * 0.4), r, z))
			mk.prism(Vector3(0, -width * 0.5, 0), r, r, width, 8, Palette.TIRE, true, true)
	mk.xf = Transform3D.IDENTITY
