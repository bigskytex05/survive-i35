class_name Foliage
extends RefCounted
## Low-poly Central Texas trees, built once and shared by every chunk's
## MultiMesh: wide, lumpy live oaks and dark, pointy cedars (Ashe juniper).

static var _oak: ArrayMesh
static var _cedar: ArrayMesh


static func oak_mesh() -> ArrayMesh:
	if _oak == null:
		var mk := MeshKit.new()
		mk.prism(Vector3.ZERO, 0.32, 0.22, 2.2, 6, Palette.TRUNK)
		mk.blob(Vector3(0.0, 3.0, 0.0), Vector3(2.7, 1.6, 2.6), Palette.LEAF, 11)
		mk.blob(Vector3(1.4, 2.6, 0.7), Vector3(1.7, 1.2, 1.6), Palette.LEAF_DARK, 12)
		mk.blob(Vector3(-1.2, 2.8, -0.9), Vector3(1.6, 1.1, 1.5), Palette.LEAF_LIGHT, 13)
		_oak = mk.commit()
	return _oak


static func cedar_mesh() -> ArrayMesh:
	if _cedar == null:
		var mk := MeshKit.new()
		mk.prism(Vector3.ZERO, 0.2, 0.16, 0.9, 5, Palette.TRUNK)
		mk.prism(Vector3(0, 0.6, 0), 1.5, 0.0, 3.4, 7, Palette.LEAF_DARK)
		mk.prism(Vector3(0, 2.1, 0), 1.05, 0.0, 2.9, 7, Palette.LEAF_DARK.darkened(0.06))
		_cedar = mk.commit()
	return _cedar
