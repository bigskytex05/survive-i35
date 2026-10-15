extends Prop
## Censored Hand Gesture (active): your driver throws a gesture out the window
## at the nearest driver within RANGE meters (always pixelated, always under a
## big CENSORED bar, always bleeped). They lose it and swerve at you:
## - usually they miss, overcorrect and crash out, taking 1-3 cars with them
##   (a pileup that clears the road ahead; each one is a Road Rage KO);
## - HIT_CHANCE of the time their lunge is aimed to connect and spins you out,
##   unless you steer or brake out of the way first.
## A state trooper in range gets it instead (they're hard to miss), and that's
## a chase. Nobody in range: nothing happens and no cooldown is spent.

const RANGE := 15.0
const HIT_CHANCE := 0.25
const HONK_DELAY := 0.4

## Tests set this to 0 or 1 to force an outcome.
var hit_chance := HIT_CHANCE
var rng := RandomNumberGenerator.new()


func setup(race_node: Race, prop_data: PropData) -> void:
	super(race_node, prop_data)
	rng.randomize()


func use() -> bool:
	var trooper: Variant = race.police.trooper_near(RANGE)
	if trooper != null:
		race.police.provoke(trooper, &"gesture")
		var trooper_d: float = trooper.d if trooper is SpeedTrap else (trooper as PoliceCar).fp.d
		_flip(trooper_d)
		return true
	var target := race.traffic.rage_target_near(RANGE)
	if target == null:
		race.hud.popup("Nobody close enough to see it.", Palette.UI_MUTED, 22)
		return false
	race.traffic.enrage(target, rng.randf() < hit_chance)
	_flip(target.fp.d)
	get_tree().create_timer(HONK_DELAY, false, true).timeout.connect(_honk)
	return true


## Out of the window on the target's side (the driver's window when it's dead ahead).
func _flip(target_d: float) -> void:
	race.hud.show_gesture(1.0 if target_d > race.car.road_d + 1.0 else -1.0)
	Sfx.play(self, &"bleep", -8.0)


func _honk() -> void:
	Sfx.play(self, &"horn", -6.0)
