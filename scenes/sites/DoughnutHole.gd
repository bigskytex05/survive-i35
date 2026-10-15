extends Node3D
## Round Rock's landmark (a parody): a doughnut shop with a giant glazed
## doughnut on a pole, famous for a glaze so orange it's practically a team
## color. Place it beside the road in a StartSite scene (+Z faces the road's
## oncoming drivers).

const DOUGH := Color(0.86, 0.64, 0.38)
const GLAZE := Color(0.96, 0.62, 0.24)


func _ready() -> void:
	var mk := MeshKit.new()
	# The shop: cream walls, a striped awning, a big window.
	mk.box(Vector3(0, 2.0, 0), Vector3(12.0, 4.0, 8.0), Palette.SIGN_WHITE)
	mk.box(Vector3(0, 4.2, 0), Vector3(12.6, 0.4, 8.6), GLAZE)
	mk.box(Vector3(0, 1.8, 4.02), Vector3(7.0, 1.8, 0.06), Palette.GLASS)
	for i in 8:
		mk.box(Vector3(-5.25 + i * 1.5, 3.2, 4.6), Vector3(1.5, 0.5, 1.2), GLAZE if i % 2 == 0 else Palette.SIGN_WHITE)
	# The doughnut, on a tall pole beside the shop.
	mk.box(Vector3(9.0, 6.0, 0), Vector3(0.5, 12.0, 0.5), Palette.HUB)
	mk.xf = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(9.0, 13.6, 0))
	_torus(mk, 2.6, 1.15, 18, 8)
	mk.xf = Transform3D.IDENTITY
	add_child(Scenery.mesh_node("DoughnutShop", mk))
	var sign_node := Scenery.sign_text(Transform3D(Basis.IDENTITY, Vector3(0, 0, 4.4)), 5.6,
		["ROUND ROCK DOUGHNUT HOLE", "GLAZED SINCE FOREVER"], [70, 44], Palette.UI_TEXT)
	add_child(sign_node)
	var board := MeshKit.new()
	board.box(Vector3(0, 5.6, 4.3), Vector3(11.0, 1.9, 0.1), Palette.SIGN_WHITE)
	add_child(Scenery.mesh_node("ShopSign", board))


## A low-poly torus around local Y: dough underneath, glaze on top.
static func _torus(mk: MeshKit, major: float, minor: float, rings: int, sides: int) -> void:
	for i in rings:
		var a0 := TAU * i / rings
		var a1 := TAU * (i + 1) / rings
		for j in sides:
			var b0 := TAU * j / sides
			var b1 := TAU * (j + 1) / sides
			var p00 := _torus_point(a0, b0, major, minor)
			var p10 := _torus_point(a1, b0, major, minor)
			var p11 := _torus_point(a1, b1, major, minor)
			var p01 := _torus_point(a0, b1, major, minor)
			var mid := (a0 + a1) * 0.5
			var tube := (b0 + b1) * 0.5
			var normal := Vector3(cos(mid) * cos(tube), sin(tube), sin(mid) * cos(tube))
			mk.quad(p00, p10, p11, p01, normal, GLAZE if sin(tube) > -0.2 else DOUGH)


static func _torus_point(a: float, b: float, major: float, minor: float) -> Vector3:
	var r := major + minor * cos(b)
	return Vector3(cos(a) * r, minor * sin(b), sin(a) * r)
