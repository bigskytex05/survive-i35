extends WorldEnvironment
## Applies the Palette to sky, fog, ambient light and the sun, so the whole
## golden-hour look is tuned from Palette.gd. Distance fog uses the horizon
## color, which makes the far road melt into the sky.

@export var sun: DirectionalLight3D


func _ready() -> void:
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	if sky_material:
		sky_material.sky_top_color = Palette.SKY_TOP
		sky_material.sky_horizon_color = Palette.SKY_HORIZON
		sky_material.ground_horizon_color = Palette.SKY_HORIZON
		sky_material.ground_bottom_color = Palette.FOG
	environment.ambient_light_color = Palette.AMBIENT
	environment.fog_light_color = Palette.FOG
	if sun:
		sun.light_color = Palette.SUN
