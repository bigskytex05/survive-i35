class_name Scenery
extends RefCounted
## Builders for set-piece scenery: signs, parked cars, people, tailgate tents,
## light poles. All low-poly and vertex-colored, so a whole set piece bakes into
## a few meshes (one draw call each).
##
## Positions use a site's local frame: at(s, d) is s meters down the road from
## the site's origin and d meters right of the median. Things face oncoming
## drivers (+Z) unless rotated.

const SKIN: Array[Color] = [
	Color(0.93, 0.76, 0.61), Color(0.85, 0.65, 0.49), Color(0.73, 0.52, 0.37),
	Color(0.55, 0.38, 0.27), Color(0.42, 0.29, 0.21),
]


static func at(s: float, d: float, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(d, 0.0, -s))


static func mesh_node(node_name: String, mk: MeshKit, shadows := true, material: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mk.commit()
	if material:
		mi.material_override = material
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Flat-shaded sign lettering (unshaded, so it reads in any light).
static func label(text: String, font_size: int, pixel: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font(900)
	l.font_size = font_size
	l.pixel_size = pixel
	l.outline_size = 0
	l.modulate = color
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	return l


## A roadside sign on two posts: a white-bordered board of `size` (width,
## height) whose bottom edge is `bottom` meters up, facing +Z.
static func sign_board(mk: MeshKit, xf: Transform3D, size: Vector2, bottom: float, face: Color,
		border := Palette.SIGN_WHITE) -> void:
	var mid := bottom + size.y * 0.5
	for x: float in [-size.x * 0.3, size.x * 0.3]:
		mk.xf = xf * Transform3D(Basis.IDENTITY, Vector3(x, 0, -0.12))
		mk.box(Vector3(0, mid * 0.5, 0), Vector3(0.16, mid, 0.16), Palette.HUB)
	mk.xf = xf
	mk.box(Vector3(0, mid, 0), Vector3(size.x + 0.24, size.y + 0.24, 0.1), border)
	mk.box(Vector3(0, mid, 0.03), Vector3(size.x, size.y, 0.1), face)
	mk.xf = Transform3D.IDENTITY


## Lines of sign text stacked around height `center_y`, on the front of a board
## at `xf`. Returns a node holding the labels.
static func sign_text(xf: Transform3D, center_y: float, lines: Array, sizes: Array,
		color := Palette.SIGN_WHITE, pixel := 0.01) -> Node3D:
	var node := Node3D.new()
	node.transform = xf
	var heights: Array[float] = []
	var total := 0.0
	for i in lines.size():
		var h: float = sizes[i] * pixel * 1.12
		heights.append(h)
		total += h
	var y := center_y + total * 0.5
	for i in lines.size():
		var l := label(lines[i], sizes[i], pixel, color)
		l.position = Vector3(0, y - heights[i] * 0.5, 0.1)
		node.add_child(l)
		y -= heights[i]
	return node


## A parked car seen from above: body and a glass cabin with a painted roof.
## Its length runs along local Z. `kind` 0 = sedan, 1 = SUV, 2 = pickup.
static func parked_car(mk: MeshKit, xf: Transform3D, paint: Color, kind: int) -> void:
	mk.xf = xf
	var l := 4.6 if kind == 0 else (4.9 if kind == 1 else 5.5)
	var h := 1.45 if kind == 0 else 1.8
	var w := 1.85
	var belt := h * 0.58
	mk.box(Vector3(0, (0.3 + belt) * 0.5, 0), Vector3(w, belt - 0.3, l), paint)
	var cabin_len := l * (0.5 if kind != 2 else 0.32)
	var cabin_z := l * (0.05 if kind != 2 else -0.08)
	mk.box(Vector3(0, (belt + h) * 0.5, cabin_z), Vector3(w * 0.86, h - belt, cabin_len), Palette.GLASS,
		paint.lightened(0.08))
	mk.box(Vector3(0, 0.18, 0), Vector3(w * 0.9, 0.36, l * 0.9), Palette.TIRE)
	mk.xf = Transform3D.IDENTITY


## A standing person about 1.75 m tall, facing +Z. `arm_up` raises the right arm
## (cheering, waving).
static func person(mk: MeshKit, xf: Transform3D, shirt: Color, pants: Color, skin: Color, arm_up := false) -> void:
	mk.xf = xf
	for x: float in [-0.12, 0.12]:
		mk.box(Vector3(x, 0.42, 0), Vector3(0.17, 0.84, 0.2), pants)
	mk.box(Vector3(0, 1.13, 0), Vector3(0.46, 0.6, 0.26), shirt)
	mk.box(Vector3(-0.3, 1.1, 0), Vector3(0.13, 0.56, 0.15), shirt)
	if arm_up:
		mk.box(Vector3(0.3, 1.62, 0), Vector3(0.13, 0.56, 0.15), shirt)
	else:
		mk.box(Vector3(0.3, 1.1, 0), Vector3(0.13, 0.56, 0.15), shirt)
	mk.blob(Vector3(0, 1.6, 0), Vector3(0.17, 0.19, 0.17), skin, 3, 0.08)
	mk.xf = Transform3D.IDENTITY


## A pop-up tailgate canopy (3 m square) with a folding table under it.
static func canopy(mk: MeshKit, xf: Transform3D, color: Color) -> void:
	mk.xf = xf
	for x: float in [-1.45, 1.45]:
		for z: float in [-1.45, 1.45]:
			mk.box(Vector3(x, 1.25, z), Vector3(0.07, 2.5, 0.07), Palette.HUB)
	mk.box(Vector3(0, 2.52, 0), Vector3(3.1, 0.06, 3.1), color)
	# Pyramid top (a four-sided cone turned to sit square) and a valance.
	mk.xf = xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO)
	mk.prism(Vector3(0, 2.55, 0), 2.2, 0.0, 0.9, 4, color)
	mk.xf = xf
	for side: float in [-1.0, 1.0]:
		mk.box(Vector3(0, 2.38, side * 1.55), Vector3(3.1, 0.28, 0.04), Palette.SIGN_WHITE)
		mk.box(Vector3(side * 1.55, 2.38, 0), Vector3(0.04, 0.28, 3.1), Palette.SIGN_WHITE)
	# Folding table.
	mk.box(Vector3(0, 0.74, -0.4), Vector3(1.8, 0.05, 0.75), Palette.SIGN_WHITE)
	for x: float in [-0.8, 0.8]:
		mk.box(Vector3(x, 0.37, -0.4), Vector3(0.05, 0.74, 0.6), Palette.TRIM)
	mk.xf = Transform3D.IDENTITY


## A kettle grill on legs.
static func grill(mk: MeshKit, xf: Transform3D) -> void:
	mk.xf = xf
	for x: float in [-0.2, 0.2]:
		mk.box(Vector3(x, 0.35, 0), Vector3(0.04, 0.7, 0.04), Palette.TRIM)
	mk.prism(Vector3(0, 0.62, 0), 0.32, 0.36, 0.28, 8, Palette.TIRE)
	mk.prism(Vector3(0, 0.9, 0), 0.36, 0.12, 0.2, 8, Palette.TIRE)
	mk.xf = Transform3D.IDENTITY


static func cooler(mk: MeshKit, xf: Transform3D, color: Color) -> void:
	mk.xf = xf
	mk.box(Vector3(0, 0.22, 0), Vector3(0.7, 0.44, 0.42), color, Palette.SIGN_WHITE)
	mk.xf = Transform3D.IDENTITY


## A cornhole board (slanted, with its hole).
static func cornhole(mk: MeshKit, xf: Transform3D, color: Color) -> void:
	mk.xf = xf * Transform3D(Basis(Vector3.RIGHT, 0.22), Vector3(0, 0.2, 0))
	mk.box(Vector3.ZERO, Vector3(0.6, 0.05, 1.2), color)
	mk.box(Vector3(0, 0.03, -0.35), Vector3(0.16, 0.02, 0.16), Palette.TIRE)
	mk.xf = Transform3D.IDENTITY


## A tall lot light pole. Its lamp head goes in `glow_mk` (a glowing mesh).
static func light_pole(mk: MeshKit, glow_mk: MeshKit, xf: Transform3D, height := 13.0) -> void:
	mk.xf = xf
	mk.prism(Vector3.ZERO, 0.22, 0.14, height, 6, Palette.HUB)
	mk.box(Vector3(0, height, 0), Vector3(2.6, 0.18, 0.18), Palette.HUB)
	glow_mk.xf = xf
	for x: float in [-1.1, 1.1]:
		glow_mk.box(Vector3(x, height - 0.18, 0), Vector3(0.7, 0.16, 0.45), Palette.HEADLIGHT)
	mk.xf = Transform3D.IDENTITY
	glow_mk.xf = Transform3D.IDENTITY


## A flat painted arrow on the pavement pointing toward -Z (down the road).
static func road_arrow(mk: MeshKit, xf: Transform3D, color: Color, y := 0.04) -> void:
	mk.xf = xf
	mk.quad(Vector3(-0.2, y, 2.0), Vector3(0.2, y, 2.0), Vector3(0.2, y, -0.4), Vector3(-0.2, y, -0.4), Vector3.UP, color)
	mk.tri(Vector3(-0.7, y, -0.4), Vector3(0.7, y, -0.4), Vector3(0, y, -1.8), Vector3.UP, color)
	mk.xf = Transform3D.IDENTITY


## A flat axis-aligned rectangle on the ground in site coordinates: from s0 to
## s1 down the road, d0 to d1 across it, at height y.
static func ground_rect(mk: MeshKit, s0: float, s1: float, d0: float, d1: float, y: float, color: Color) -> void:
	mk.xf = Transform3D.IDENTITY
	mk.quad(Vector3(d0, y, -s0), Vector3(d1, y, -s0), Vector3(d1, y, -s1), Vector3(d0, y, -s1), Vector3.UP, color)
