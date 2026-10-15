extends Node
## What the player picked on the way to the road: level, car, paint and prop.
## The garage fills it in and the race reads it, so Retry keeps the same loadout.
## Saving it between sessions arrives with the save system (Phase 6).

const DEFAULT_LEVEL := preload("res://data/levels/01_kickoff.tres")

var level: LevelData = DEFAULT_LEVEL
var car: CarData
## Transparent = the car's default paint.
var paint := Color(0, 0, 0, 0)
var prop: PropData
## False until the garage hands over a loadout. Races started on their own
## (tests, F6 in the editor) keep the car and prop set on the Race scene.
var has_loadout := false


func set_loadout(new_car: CarData, new_paint: Color, new_prop: PropData) -> void:
	car = new_car
	paint = new_paint
	prop = new_prop
	has_loadout = true


func clear() -> void:
	level = DEFAULT_LEVEL
	car = null
	paint = Color(0, 0, 0, 0)
	prop = null
	has_loadout = false
