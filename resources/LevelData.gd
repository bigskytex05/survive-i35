class_name LevelData
extends Resource
## One trip down I-35. Add a level by creating a new .tres with this script.
## It sets the route, the clock, traffic, speed traps and the scenery at both
## ends; construction and special events join in later phases.

@export var id: StringName = &""
@export var title := ""
@export_multiline var scenario := ""
## Town ids from Corridor.TOWNS. Every trip ends in Austin or Dallas.
@export var start_town: StringName = &"round_rock"
@export var destination: StringName = &"austin"
## Length of the drive in game meters (the real corridor is compressed).
@export var distance_m := 4800.0
## Seconds on the clock at GO.
@export var time_limit := 180.0

@export_group("Traffic")
## Cars per kilometer per lane in open country. Towns and metro approaches add more.
@export var traffic_density := 7.0
## A paint that shows up more often than usual (burnt orange on game day).
## Leave transparent for none.
@export var feature_paint := Color(0, 0, 0, 0)
@export_range(0.0, 1.0) var feature_paint_chance := 0.0

@export_group("Police")
## Speed traps along the way (spread over the open road; new spots every run).
@export_range(0, 8) var speed_traps := 0

@export_group("Set pieces")
## Scenery around the start line: a scene whose root extends StartSite (the
## start town's water tower, signs and landmarks). Empty = open highway.
@export var start_site: PackedScene
## The destination at the finish line: a scene whose root extends FinishSite
## (Kickoff ends in a stadium parking lot). Empty = an overhead city-limit sign.
@export var finish_site: PackedScene

@export_group("Lines")
@export_multiline var success_line := ""
@export_multiline var fail_line := ""
