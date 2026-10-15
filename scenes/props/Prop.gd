class_name Prop
extends Node3D
## Base for prop behaviors. PropController creates one from PropData.behavior,
## calls setup() once, use() when the player presses the prop button and the
## cooldown is over, and tick() every physics frame. Props reach the rest of the
## race (car, traffic, HUD) through `race`.

var data: PropData
var race: Race


func setup(race_node: Race, prop_data: PropData) -> void:
	race = race_node
	data = prop_data


## Fire the prop. Return false when nothing happened, so no cooldown is spent.
func use() -> bool:
	return false


func tick(_delta: float) -> void:
	pass


## 0..1 of the current activation left (the HUD's "on" ring); 0 when idle.
func active_fraction() -> float:
	return 0.0


## Speed traps ask this before clocking the player (police arrive in Phase 4).
func blocks_speed_traps() -> bool:
	return false
