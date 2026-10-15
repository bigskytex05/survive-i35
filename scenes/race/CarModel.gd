class_name CarModel
extends Node3D
## Placeholder toy car built in code from boxes and cylinders.
##
## To swap in a real low-poly model, set CarData.model_scene to a scene with:
##   BodyPivot (Node3D)  - everything that should bounce/roll (body, glass, lights)
##   WheelFL / WheelFR / WheelRL / WheelRR (Node3D) - pivots at the wheel centers;
##     front ones steer around Y, all spin around X
## Optionally a MeshInstance3D at BodyPivot/Taillights for brake-light glow, and
## HeadlightL / HeadlightR markers (anywhere under BodyPivot) for the high beams.

const STEER_ANGLE := 0.42
const WHEEL_NAMES: Array[String] = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]

static var _wheel_meshes: Dictionary = {}

var wheel_radius := 0.44
var body_pivot: Node3D
## Where the headlight lenses are, in this node's space (the high beams shine from here).
var headlights: Array[Vector3] = []

var _wheels: Array[Node3D] = []
var _spinners: Array[Node3D] = []
var _tail_material: ShaderMaterial
var _spin := 0.0


func build(data: CarData, paint: Color) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_wheels.clear()
	_spinners.clear()
	wheel_radius = data.wheel_radius
	# Real models can override this with HeadlightL/HeadlightR markers.
	headlights = [Vector3(-data.size.x * 0.32, data.size.y * 0.5, -data.size.z * 0.5),
		Vector3(data.size.x * 0.32, data.size.y * 0.5, -data.size.z * 0.5)]
	if data.model_scene:
		var model := data.model_scene.instantiate()
		for child in model.get_children():
			child.owner = null
			model.remove_child(child)
			add_child(child)
		model.free()
	else:
		_build_placeholder(data, paint)
	body_pivot = get_node_or_null("BodyPivot")
	var markers: Array[Vector3] = []
	for marker_name: String in ["HeadlightL", "HeadlightR"]:
		var marker := find_child(marker_name, true, false) as Node3D
		if marker:
			markers.append(_local_to_model(marker).origin)
	if markers.size() == 2:
		headlights = markers
	for wheel_name in WHEEL_NAMES:
		var wheel := get_node_or_null(wheel_name) as Node3D
		if wheel:
			_wheels.append(wheel)
			_spinners.append(wheel.get_child(0) if wheel.get_child_count() > 0 else wheel)
	var tail := get_node_or_null("BodyPivot/Taillights") as MeshInstance3D
	if tail:
		_tail_material = Materials.glow(Palette.TAILLIGHT, 0.4)
		tail.material_override = _tail_material


## A descendant's transform relative to this node (works outside the tree too).
func _local_to_model(node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != self and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Suspension pose from PlayerCar's springs: roll and pitch in radians, heave in meters.
func set_body_pose(roll: float, pitch: float, heave: float) -> void:
	if body_pivot:
		body_pivot.rotation = Vector3(pitch, 0.0, roll)
		body_pivot.position.y = heave


func update_wheels(speed: float, steer: float, delta: float) -> void:
	_spin = fmod(_spin + speed / wheel_radius * delta, TAU)
	for spinner in _spinners:
		spinner.rotation.x = -_spin  # rolling forward = top of the wheel moves toward -Z
	for i in mini(2, _wheels.size()):
		_wheels[i].rotation.y = -steer * STEER_ANGLE


func set_brake_lights(on: bool) -> void:
	if _tail_material:
		_tail_material.set_shader_parameter("emission_energy", 2.2 if on else 0.4)


func _build_placeholder(data: CarData, paint: Color) -> void:
	body_pivot = Node3D.new()
	body_pivot.name = "BodyPivot"
	add_child(body_pivot)

	var mk := MeshKit.new()
	var tail_mk := MeshKit.new()
	# Each builder returns the axle positions along the car (front z, rear z).
	var axles: Vector2
	match data.body_style:
		CarData.BodyStyle.PICKUP:
			axles = _pickup(mk, tail_mk, data.size, paint)
		CarData.BodyStyle.HATCH:
			axles = _hatch(mk, tail_mk, data.size, paint)
		_:
			axles = _suv(mk, tail_mk, data.size, paint)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mk.commit()
	body_pivot.add_child(body)
	var tail := MeshInstance3D.new()
	tail.name = "Taillights"
	tail.mesh = tail_mk.commit()
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body_pivot.add_child(tail)

	# Wheels stay planted while the body bounces above them.
	var w := data.size.x
	var r := wheel_radius
	var wheel_mesh := _wheel_mesh(r)
	var positions: Array[Vector3] = [
		Vector3(-w * 0.5 + 0.12, r, axles.x), Vector3(w * 0.5 - 0.12, r, axles.x),
		Vector3(-w * 0.5 + 0.12, r, axles.y), Vector3(w * 0.5 - 0.12, r, axles.y),
	]
	for i in 4:
		var pivot := Node3D.new()
		pivot.name = WHEEL_NAMES[i]
		pivot.position = positions[i]
		var tire := MeshInstance3D.new()
		tire.name = "Tire"
		tire.mesh = wheel_mesh
		pivot.add_child(tire)
		add_child(pivot)


## Chunky toy SUV: tall lower body, inset glass "greenhouse", flat roof.
func _suv(mk: MeshKit, tail_mk: MeshKit, size: Vector3, paint: Color) -> Vector2:
	var w := size.x
	var h := size.y
	var l := size.z
	var r := wheel_radius
	var floor_y := r * 0.95
	var belt_y := h * 0.66
	var roof_y := h - 0.1
	var cabin_len := l * 0.6
	var cabin_z := l * 0.08  # cabin sits a little rearward
	mk.box(Vector3(0, (floor_y + belt_y) * 0.5, 0), Vector3(w, belt_y - floor_y, l), paint)
	mk.box(Vector3(0, (belt_y + roof_y) * 0.5, cabin_z), Vector3(w * 0.86, roof_y - belt_y, cabin_len), Palette.GLASS)
	mk.box(Vector3(0, roof_y + 0.05, cabin_z), Vector3(w * 0.9, 0.12, cabin_len + 0.06), paint.lightened(0.08))
	# Pillars between the windows so the cabin reads as a cabin.
	for x: float in [-1.0, 1.0]:
		for z: float in [-cabin_len * 0.5 + 0.08, cabin_z * 0.5, cabin_len * 0.5 - 0.08]:
			mk.box(Vector3(x * w * 0.435, (belt_y + roof_y) * 0.5, cabin_z + z), Vector3(0.06, roof_y - belt_y, 0.16), paint)
	_bumpers(mk, w, l, floor_y)
	_lamps(mk, tail_mk, w, l, belt_y - 0.2, Vector3(0.42, 0.16, 0.05), Vector3(0.4, 0.18, 0.05), 0.32, 0.3)
	var axle_z := l * 0.5 - r - 0.42
	return Vector2(-axle_z, axle_z)


## Lifted pickup: long hood, chrome grille, short cab, open bed, marker lights on the roof.
func _pickup(mk: MeshKit, tail_mk: MeshKit, size: Vector3, paint: Color) -> Vector2:
	var w := size.x
	var h := size.y
	var l := size.z
	var r := wheel_radius
	var floor_y := r * 1.05
	var belt_y := h * 0.62
	var roof_y := h - 0.06
	var front := -l * 0.5
	var cab_front := front + l * 0.32
	var bed_front := l * 0.1
	var nose_len := bed_front - front
	mk.box(Vector3(0, (floor_y + belt_y) * 0.5, front + nose_len * 0.5), Vector3(w, belt_y - floor_y, nose_len), paint)
	mk.box(Vector3(0, (belt_y + roof_y) * 0.5, (cab_front + bed_front) * 0.5), Vector3(w * 0.86, roof_y - belt_y, bed_front - cab_front), Palette.GLASS)
	mk.box(Vector3(0, roof_y + 0.05, (cab_front + bed_front) * 0.5), Vector3(w * 0.9, 0.12, bed_front - cab_front + 0.06), paint.lightened(0.08))
	for x: float in [-1.0, 1.0]:
		mk.box(Vector3(x * w * 0.435, (belt_y + roof_y) * 0.5, (cab_front + bed_front) * 0.5), Vector3(0.06, roof_y - belt_y, 0.16), paint)
	# Cab-roof marker lights: very Texas.
	for x: float in [-0.3, 0.0, 0.3]:
		mk.box(Vector3(x * w, roof_y + 0.14, cab_front + 0.12), Vector3(0.16, 0.08, 0.1), Palette.AMBER)
	# Open bed: floor, side walls, tailgate.
	var bed_back := l * 0.5
	var bed_mid := (bed_front + 0.08 + bed_back) * 0.5
	var bed_len := bed_back - bed_front - 0.08
	mk.box(Vector3(0, floor_y + 0.14, bed_mid), Vector3(w, 0.26, bed_len), Palette.TRIM)
	for x: float in [-1.0, 1.0]:
		mk.box(Vector3(x * (w * 0.5 - 0.07), (floor_y + belt_y) * 0.5, bed_mid), Vector3(0.14, belt_y - floor_y, bed_len), paint)
	mk.box(Vector3(0, (floor_y + belt_y) * 0.5, bed_back - 0.07), Vector3(w, belt_y - floor_y, 0.14), paint)
	# Big chrome grille.
	mk.box(Vector3(0, (floor_y + belt_y) * 0.5 + 0.04, front - 0.04), Vector3(w * 0.56, (belt_y - floor_y) * 0.7, 0.08), Palette.HUB)
	_bumpers(mk, w, l, floor_y)
	_lamps(mk, tail_mk, w, l, belt_y - 0.24, Vector3(0.42, 0.2, 0.05), Vector3(0.16, 0.38, 0.05), 0.3, 0.1)
	return Vector2(front + r + 0.8, l * 0.5 - r - 0.75)


## Low EV hatchback: no grille, a glass roof, light bars front and back.
func _hatch(mk: MeshKit, tail_mk: MeshKit, size: Vector3, paint: Color) -> Vector2:
	var w := size.x
	var h := size.y
	var l := size.z
	var r := wheel_radius
	var floor_y := r * 0.85
	var belt_y := h * 0.6
	var roof_y := h - 0.06
	var cabin_len := l * 0.62
	var cabin_z := l * 0.05
	mk.box(Vector3(0, (floor_y + belt_y) * 0.5, 0), Vector3(w, belt_y - floor_y, l), paint)
	mk.box(Vector3(0, (belt_y + roof_y) * 0.5, cabin_z), Vector3(w * 0.84, roof_y - belt_y, cabin_len), Palette.GLASS)
	# Panoramic glass roof inside a thin painted frame.
	mk.box(Vector3(0, roof_y + 0.03, cabin_z), Vector3(w * 0.88, 0.08, cabin_len + 0.04), paint.lightened(0.08))
	mk.box(Vector3(0, roof_y + 0.08, cabin_z), Vector3(w * 0.66, 0.04, cabin_len * 0.78), Palette.GLASS.darkened(0.25))
	for x: float in [-1.0, 1.0]:
		mk.box(Vector3(x * w * 0.425, (belt_y + roof_y) * 0.5, cabin_z - cabin_len * 0.5 + 0.08), Vector3(0.06, roof_y - belt_y, 0.16), paint)
	_bumpers(mk, w, l, floor_y)
	# Full-width light bars.
	mk.box(Vector3(0, belt_y - 0.1, -l * 0.5 - 0.02), Vector3(w * 0.84, 0.06, 0.04), Palette.HEADLIGHT)
	tail_mk.box(Vector3(0, belt_y - 0.1, l * 0.5 + 0.02), Vector3(w * 0.86, 0.08, 0.04), Palette.TAILLIGHT)
	headlights = [Vector3(-w * 0.32, belt_y - 0.1, -l * 0.5 - 0.03), Vector3(w * 0.32, belt_y - 0.1, -l * 0.5 - 0.03)]
	var axle_z := l * 0.5 - r - 0.4
	return Vector2(-axle_z, axle_z)


func _bumpers(mk: MeshKit, w: float, l: float, floor_y: float) -> void:
	mk.box(Vector3(0, floor_y + 0.12, -l * 0.5 - 0.06), Vector3(w * 1.02, 0.26, 0.2), Palette.TRIM)
	mk.box(Vector3(0, floor_y + 0.12, l * 0.5 + 0.06), Vector3(w * 1.02, 0.26, 0.2), Palette.TRIM)
	mk.box(Vector3(0, floor_y + 0.04, 0), Vector3(w * 1.01, 0.12, l * 0.98), Palette.TRIM)


## A pair of headlights (in the body mesh) and taillights (their own mesh, so
## they can glow). `inset` is how far each lamp sits in from the side.
func _lamps(mk: MeshKit, tail_mk: MeshKit, w: float, l: float, y: float, head: Vector3, tail: Vector3,
		head_inset: float, tail_inset: float) -> void:
	headlights.clear()
	for x: float in [-1.0, 1.0]:
		var hx := x * (w * 0.5 - head_inset)
		mk.box(Vector3(hx, y, -l * 0.5 - 0.01), head, Palette.HEADLIGHT)
		headlights.append(Vector3(hx, y, -l * 0.5 - 0.04))
		tail_mk.box(Vector3(x * (w * 0.5 - tail_inset), y, l * 0.5 + 0.01), tail, Palette.TAILLIGHT)


## Eight-sided tire with a hub cross on both faces so you can see it spin.
static func _wheel_mesh(radius: float) -> ArrayMesh:
	var key := snappedf(radius, 0.01)
	if not _wheel_meshes.has(key):
		var mk := MeshKit.new()
		var width := 0.42
		# Build the cylinder along Y, then lay it on its side (axis along X).
		mk.xf = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO)
		mk.prism(Vector3(0, -width * 0.5, 0), radius, radius, width, 8, Palette.TIRE, true, true)
		for y: float in [-width * 0.5 - 0.01, width * 0.5 + 0.01]:
			mk.box(Vector3(0, y, 0), Vector3(radius * 1.1, 0.03, 0.14), Palette.HUB)
			mk.box(Vector3(0, y, 0), Vector3(0.14, 0.03, radius * 1.1), Palette.HUB)
		_wheel_meshes[key] = mk.commit()
	return _wheel_meshes[key]
