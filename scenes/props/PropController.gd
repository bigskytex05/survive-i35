class_name PropController
extends Node3D
## Runs the player's prop during a race: reads the prop button (Space, gamepad
## A, the on-screen PROP button), enforces the cooldown and hands the actual
## work to the prop's behavior script. The cooldown starts when the prop fires.

signal used

var data: PropData
var prop: Prop
var cooldown_left := 0.0

var _race: Race


func setup(race: Race, prop_data: PropData) -> void:
	_race = race
	data = prop_data
	if prop:
		prop.queue_free()
		prop = null
	if data and data.behavior:
		prop = data.behavior.new() as Prop
		prop.name = String(data.id).to_pascal_case()
		add_child(prop)
		prop.setup(race, data)


func is_active_kind() -> bool:
	return data != null and data.kind == PropData.Kind.ACTIVE


func _physics_process(delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if prop:
		prop.tick(delta)
	if Input.is_action_just_pressed("use_prop"):
		try_use()


## Fires the prop if it's an active one, it's ready and the player is in
## control. Returns whether it fired.
func try_use() -> bool:
	if prop == null or not is_active_kind() or cooldown_left > 0.0 or not _race.can_use_props():
		return false
	if not prop.use():
		return false
	cooldown_left = data.cooldown
	used.emit()
	return true


## 1 right after a use .. 0 when ready.
func cooldown_fraction() -> float:
	if not is_active_kind() or data.cooldown <= 0.0:
		return 0.0
	return cooldown_left / data.cooldown


func active_fraction() -> float:
	return prop.active_fraction() if prop else 0.0


func blocks_speed_traps() -> bool:
	return prop != null and prop.blocks_speed_traps()
