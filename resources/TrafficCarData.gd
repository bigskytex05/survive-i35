class_name TrafficCarData
extends Resource
## One kind of traffic vehicle. Add a type by creating a .tres with this script
## and adding it to TrafficSpawner's roster. For custom antics, give it a
## `behavior` script (see scenes/traffic/behaviors/).

enum BodyStyle { SEDAN, MINIVAN, PICKUP, SEMI, WORK_TRUCK, POLICE }

@export var id: StringName = &""
@export var display_name := ""
## How it drives, as a label ("normal", "cautious", "aggressive", "hauler"...).
## Behavior scripts and the future meme cars can key off it.
@export var personality: StringName = &"normal"
## Optional script extending TrafficBehavior that overrides how this car drives.
@export var behavior: Script
## Relative odds of this type being picked when traffic spawns.
@export var spawn_weight := 1.0
## Optional TrafficCar subclass for vehicles with a mind of their own (the
## police car's PoliceCar). Empty = a regular TrafficCar.
@export var car_script: Script

@export_group("Body")
@export var body_style: BodyStyle = BodyStyle.SEDAN
## Width, height, length in meters. Also its collision rectangle.
@export var size := Vector3(1.85, 1.45, 4.7)
## Relative weight in collisions (the player's SUV is 1.0).
@export var mass := 0.85
## Paint choices. Empty = Palette.TRAFFIC_PAINTS (work trucks: work yellow).
@export var paints: PackedColorArray = PackedColorArray()
## Optional real model, replacing the code-built placeholder. It needs a Body
## mesh plus optional Taillights, BlinkLeft, BlinkRight and Beacon meshes.
@export var model_scene: PackedScene

@export_group("Driving")
## Cruise speed relative to the posted limit in mph (x = slowest, y = fastest),
## so traffic slows down by itself where the limit drops.
@export var speed_vs_limit_mph := Vector2(-3.0, 8.0)
## Gentle acceleration in m/s^2 (an 18-wheeler is slow to get going).
@export var acceleration := 2.2
## Following distance in seconds. Lower = tailgater.
@export var headway := 1.2
## 0 = only changes lanes when it really pays off, 1 = weaves constantly.
@export_range(0.0, 1.0) var lane_change_aggression := 0.4
## Chance of using the turn signal before a lane change.
@export_range(0.0, 1.0) var signal_chance := 0.75
## Preference for the right-hand lanes (slow vehicles keep right).
@export_range(0.0, 1.0) var keep_right := 0.1
