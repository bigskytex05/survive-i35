class_name MeshKit
extends RefCounted
## Tiny builder for chunky low-poly meshes made in code.
##
## Every part gets a vertex color, so a whole prop (a tree, a car body, a stretch
## of road) becomes one mesh with one shared material = one draw call.
## Set `xf` before adding a part to position/rotate it.
##
## Godot treats clockwise triangles as front-facing. tri() takes the intended
## outward normal and fixes the winding itself, so callers never think about it.

var xf := Transform3D.IDENTITY

var _st := SurfaceTool.new()
var _empty := true


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


## Finishes the mesh and assigns the shared vertex-colored material.
func commit() -> ArrayMesh:
	if _empty:
		return ArrayMesh.new()
	var mesh := _st.commit()
	mesh.surface_set_material(0, Materials.vertex_colored())
	return mesh


func tri(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	var n := (xf.basis * normal).normalized()
	# With clockwise front faces, the visible side's normal is (c - a) x (b - a).
	if (pc - pa).cross(pb - pa).dot(n) < 0.0:
		var t := pb
		pb = pc
		pc = t
	# Palette colors are sRGB; Godot converts vertex colors to linear itself.
	_st.set_color(color)
	_st.set_normal(n)
	_st.add_vertex(pa)
	_st.add_vertex(pb)
	_st.add_vertex(pc)
	_empty = false


## Four corners given in order around the edge (either direction).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	tri(a, b, c, normal, color)
	tri(a, c, d, normal, color)


func box(center: Vector3, size: Vector3, color: Color, top_color: Color = Color(0, 0, 0, 0)) -> void:
	var h := size * 0.5
	var top := color if top_color.a == 0.0 else top_color
	# Corner i has +x when bit 0 is set, +y for bit 1, +z for bit 2.
	var c: Array[Vector3] = []
	for i in 8:
		c.append(center + Vector3(
			h.x if i & 1 else -h.x,
			h.y if i & 2 else -h.y,
			h.z if i & 4 else -h.z))
	quad(c[1], c[3], c[7], c[5], Vector3.RIGHT, color)
	quad(c[0], c[2], c[6], c[4], Vector3.LEFT, color)
	quad(c[2], c[3], c[7], c[6], Vector3.UP, top)
	quad(c[0], c[1], c[5], c[4], Vector3.DOWN, color)
	quad(c[4], c[5], c[7], c[6], Vector3.BACK, color)
	quad(c[0], c[1], c[3], c[2], Vector3.FORWARD, color)


## Upright n-sided prism / frustum / cone (r_top = 0) standing on `base`.
func prism(base: Vector3, r_bottom: float, r_top: float, height: float, sides: int, color: Color,
		cap_top := true, cap_bottom := false) -> void:
	var top_center := base + Vector3.UP * height
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var side_n := (d0 + d1).normalized()
		var b0 := base + d0 * r_bottom
		var b1 := base + d1 * r_bottom
		var t0 := top_center + d0 * r_top
		var t1 := top_center + d1 * r_top
		if r_top <= 0.0001:
			tri(b0, b1, top_center, side_n, color)
		else:
			quad(b0, b1, t1, t0, side_n, color)
			if cap_top:
				tri(top_center, t0, t1, Vector3.UP, color)
		if cap_bottom:
			tri(base, b0, b1, Vector3.DOWN, color)


## Lumpy low-poly ball (a jittered icosahedron) for tree canopies, bushes, etc.
func blob(center: Vector3, radius: Vector3, color: Color, seed_value := 0, jitter := 0.14) -> void:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var raw: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var verts: Array[Vector3] = []
	for v in raw:
		var k := 1.0 + rng.randf_range(-jitter, jitter)
		verts.append(center + v.normalized() * radius * k)
	for f in faces:
		var a := verts[f.x]
		var b := verts[f.y]
		var c := verts[f.z]
		tri(a, b, c, ((a + b + c) / 3.0 - center).normalized(), color)
