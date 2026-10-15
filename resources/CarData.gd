class_name CarData
extends Resource
## Everything that makes one player car feel different. Add a car by creating
## a new .tres with this script and listing it in Garage.tscn; no code changes needed.

## Placeholder body shapes (CarModel builds them from boxes).
enum BodyStyle { SUV, PICKUP, HATCH }

@export var id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""

@export_group("Handling")
@export var top_speed_mph := 105.0
## Forward acceleration from a standstill, m/s^2 (fades toward top speed).
@export var acceleration := 9.0
@export var brake_power := 22.0
## Max turn rate in rad/s at low speed (it calms down at high speed).
@export var steer_rate := 1.5
## How fast sideways slip dies out, per second. Lower = more drift.
@export var grip := 8.0
## Relative weight for collisions (1.0 = SUV). Heavier cars lose less speed in bumps.
@export var mass := 1.0
## Multiplier on shoulder/grass drag. The SUV's "Shoulder Surfer" trait is a low value.
@export_range(0.0, 1.0) var offroad_drag := 1.0

@export_group("Body")
@export var body_style: BodyStyle = BodyStyle.SUV
## Collision and placeholder-body size in meters: width, height, length.
@export var size := Vector3(2.1, 1.8, 4.5)
@export var wheel_radius := 0.44
@export var default_paint := Color(0.84, 0.31, 0.22)
## Optional real model scene. Leave empty to use the code-built placeholder.
## A model needs a BodyPivot node plus WheelFL/WheelFR/WheelRL/WheelRR (see CarModel.gd).
@export var model_scene: PackedScene

@export_group("Sound")
## Looping engine sound (a name in assets/audio/sfx/); its pitch follows speed.
@export var engine_sound: StringName = &"engine_six"
## Gears the engine note climbs through on the way to top speed. 0 = no gears:
## the pitch just rises with speed (the EV's whine).
@export var engine_gears := 5
## Engine pitch at a standstill and at the top of each gear.
@export var engine_pitch := Vector2(0.75, 1.9)

@export_group("Trait")
## Code checks traits by id (has_trait): &"bully", &"shoulder_surfer", &"silent_running".
@export var trait_id: StringName = &""
@export var trait_name := ""
@export_multiline var trait_description := ""
## How far police can spot you speeding, relative to normal (speed traps, Phase 4).
## The EV's "Silent Running" is below 1.
@export var police_detection_scale := 1.0


func has_trait(id: StringName) -> bool:
	return trait_id == id
