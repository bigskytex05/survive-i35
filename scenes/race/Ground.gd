class_name Ground
extends MeshInstance3D
## A huge pasture plane that follows the car. Its grass pattern is anchored to
## world space in the shader, and distance fog hides the edges.

var target: Node3D


func _ready() -> void:
	var mat := (mesh as PlaneMesh).material as ShaderMaterial
	mat.set_shader_parameter("grass", Palette.GRASS)
	mat.set_shader_parameter("grass_dry", Palette.GRASS_DRY)
	mat.set_shader_parameter("grass_dark", Palette.GRASS_DARK)


func _physics_process(_delta: float) -> void:
	if target:
		global_position = Vector3(target.global_position.x, -0.04, target.global_position.z)
