class_name RoadMeshBuilder
extends RefCounted
## Generates highway geometry for one chunk in chunk-local space.
## Meshes are cached by (length, curvature): every pooled chunk with the same
## shape shares them, so streaming new road costs almost nothing.
##
## Two meshes per chunk:
##  - surface: asphalt, shoulders and paint. Flat, never casts shadows.
##  - structures: median barrier, fence, poles, delineators. Casts shadows.

const CURVE_STEP := 6.0      # meters between cross-sections on curves
const PAINT_Y := 0.025       # paint floats just above the asphalt (no z-fighting)

static var _surface_cache: Dictionary = {}
static var _structure_cache: Dictionary = {}


static func surface_mesh(length: float, kappa: float) -> ArrayMesh:
	var key := _key(length, kappa)
	if not _surface_cache.has(key):
		_surface_cache[key] = _build_surface(length, kappa)
	return _surface_cache[key]


## `open_right` leaves out the player's-side fence, delineators and poles.
static func structures_mesh(length: float, kappa: float, open_right := false) -> ArrayMesh:
	var key := _key(length, kappa) + ("|open" if open_right else "")
	if not _structure_cache.has(key):
		_structure_cache[key] = _build_structures(length, kappa, open_right)
	return _structure_cache[key]


static func _key(length: float, kappa: float) -> String:
	return "%.2f|%.7f" % [length, kappa]


static func _steps(length: float, kappa: float) -> int:
	return 1 if absf(kappa) < RoadGeo.EPS else maxi(1, ceili(length / CURVE_STEP))


## A flat band of road between offsets d0 < d1 from s0 to s1, following the curve.
static func _band(mk: MeshKit, kappa: float, s0: float, s1: float, d0: float, d1: float,
		y: float, color: Color) -> void:
	var n := _steps(s1 - s0, kappa)
	var lift := Vector3(0.0, y, 0.0)
	for i in n:
		var a := lerpf(s0, s1, float(i) / n)
		var b := lerpf(s0, s1, float(i + 1) / n)
		mk.quad(
			RoadGeo.point(kappa, a, d0) + lift, RoadGeo.point(kappa, b, d0) + lift,
			RoadGeo.point(kappa, b, d1) + lift, RoadGeo.point(kappa, a, d1) + lift,
			Vector3.UP, color)


static func _build_surface(length: float, kappa: float) -> ArrayMesh:
	var mk := MeshKit.new()
	var lanes_out := RoadSpec.lanes_outer_edge()
	var shoulder_out := RoadSpec.shoulder_outer_edge()
	var lw := RoadSpec.LINE_WIDTH
	# Both carriageways are mirror images: side = +1 is the player's.
	for side: float in [1.0, -1.0]:
		var bands := [
			[RoadSpec.MEDIAN_HALF_BASE, RoadSpec.LANE0_EDGE, Palette.SHOULDER],
			[RoadSpec.LANE0_EDGE, lanes_out, Palette.ASPHALT],
			[lanes_out, shoulder_out, Palette.SHOULDER],
			[shoulder_out, shoulder_out + RoadSpec.GRAVEL_WIDTH, Palette.GRAVEL],
		]
		for band in bands:
			var d0: float = band[0] * side
			var d1: float = band[1] * side
			_band(mk, kappa, 0.0, length, minf(d0, d1), maxf(d0, d1), 0.0, band[2])
		# Solid edge lines: yellow on the median side, white on the outside.
		var inner := RoadSpec.LANE0_EDGE + 0.12
		var outer := lanes_out - 0.12
		_band(mk, kappa, 0.0, length, minf(inner * side, (inner + lw) * side),
			maxf(inner * side, (inner + lw) * side), PAINT_Y, Palette.LANE_YELLOW)
		_band(mk, kappa, 0.0, length, minf(outer * side, (outer - lw) * side),
			maxf(outer * side, (outer - lw) * side), PAINT_Y, Palette.LANE_WHITE)
		# Dashed lane dividers. Chunk lengths are multiples of DASH_PERIOD so the
		# pattern continues seamlessly from chunk to chunk.
		for lane in range(1, RoadSpec.LANES):
			var d := (RoadSpec.LANE0_EDGE + RoadSpec.LANE_WIDTH * lane) * side
			var s := 0.0
			while s < length - 0.01:
				_band(mk, kappa, s, minf(s + RoadSpec.DASH_LENGTH, length),
					d - lw * 0.5, d + lw * 0.5, PAINT_Y, Palette.LANE_WHITE)
				s += RoadSpec.DASH_PERIOD
	return mk.commit()


static func _build_structures(length: float, kappa: float, open_right: bool) -> ArrayMesh:
	var mk := MeshKit.new()
	_jersey_barrier(mk, kappa, length)
	var shoulder_out := RoadSpec.shoulder_outer_edge()
	for side: float in ([-1.0] if open_right else [1.0, -1.0]):
		# Ranch fence: posts with a single strand of wire.
		var s := 4.0
		while s < length:
			_place(mk, kappa, s, RoadSpec.FENCE_D * side)
			mk.box(Vector3(0, 0.65, 0), Vector3(0.16, 1.3, 0.16), Palette.FENCE_POST)
			s += 8.0
		_wire(mk, kappa, length, RoadSpec.FENCE_D * side, 1.05)
		# White delineator posts along the shoulder.
		s = 10.0
		while s < length:
			_place(mk, kappa, s, (shoulder_out + 0.45) * side)
			mk.box(Vector3(0, 0.5, 0), Vector3(0.1, 1.0, 0.1), Palette.DELINEATOR)
			s += 40.0
	# Wooden utility poles beyond the fence on the player's side.
	for s: float in ([] if open_right else [30.0, 90.0]):
		if s < length:
			_place(mk, kappa, s, RoadSpec.FENCE_D + 12.0)
			mk.prism(Vector3.ZERO, 0.17, 0.13, 9.5, 6, Palette.POLE)
			mk.box(Vector3(0, 8.9, 0), Vector3(2.6, 0.16, 0.16), Palette.POLE)
	mk.xf = Transform3D.IDENTITY
	return mk.commit()


## Points the builder at road coordinate (s, d), aligned with the road heading.
static func _place(mk: MeshKit, kappa: float, s: float, d: float) -> void:
	mk.xf = Transform3D(Basis(Vector3.UP, RoadGeo.heading(kappa, s)), RoadGeo.point(kappa, s, d))


## Concrete Jersey barrier swept along the median.
static func _jersey_barrier(mk: MeshKit, kappa: float, length: float) -> void:
	mk.xf = Transform3D.IDENTITY
	var hb := RoadSpec.MEDIAN_HALF_BASE
	var h := RoadSpec.MEDIAN_HEIGHT
	# Classic Jersey profile (d, y): steep lower lip, sloped face, narrow top.
	var profile: Array[Vector2] = [
		Vector2(-hb, 0.0), Vector2(-hb + 0.1, 0.25), Vector2(-0.12, h),
		Vector2(0.12, h), Vector2(hb - 0.1, 0.25), Vector2(hb, 0.0),
	]
	var n := _steps(length, kappa)
	for i in n:
		var a := length * i / n
		var b := length * (i + 1) / n
		var r := RoadGeo.right(RoadGeo.heading(kappa, (a + b) * 0.5))
		for j in profile.size() - 1:
			var p0 := profile[j]
			var p1 := profile[j + 1]
			var edge := p1 - p0
			var outward := Vector2(-edge.y, edge.x).normalized()
			var color := Palette.CONCRETE if outward.y > 0.9 else Palette.CONCRETE_SHADE
			mk.quad(
				RoadGeo.point(kappa, a, p0.x) + Vector3.UP * p0.y,
				RoadGeo.point(kappa, b, p0.x) + Vector3.UP * p0.y,
				RoadGeo.point(kappa, b, p1.x) + Vector3.UP * p1.y,
				RoadGeo.point(kappa, a, p1.x) + Vector3.UP * p1.y,
				r * outward.x + Vector3.UP * outward.y, color)


## A thin, double-sided strand of wire at offset d.
static func _wire(mk: MeshKit, kappa: float, length: float, d: float, y: float) -> void:
	mk.xf = Transform3D.IDENTITY
	var n := _steps(length, kappa)
	for i in n:
		var a := length * i / n
		var b := length * (i + 1) / n
		var r := RoadGeo.right(RoadGeo.heading(kappa, (a + b) * 0.5))
		var lo := Vector3.UP * y
		var hi := Vector3.UP * (y + 0.05)
		var pa := RoadGeo.point(kappa, a, d)
		var pb := RoadGeo.point(kappa, b, d)
		mk.quad(pa + lo, pb + lo, pb + hi, pa + hi, r, Palette.WIRE)
		mk.quad(pa + lo, pb + lo, pb + hi, pa + hi, -r, Palette.WIRE)
