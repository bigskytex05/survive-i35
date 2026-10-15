extends Prop
## Radar Detector (passive): speed traps can't clock you for the whole trip.
## It doesn't stop a chase that started some other way (say, ramming a cop).
## A little detector sits on the HUD and beeps faster as a trap gets close
## (Police.threat_at), purely for fun.

## 0 = all clear .. 1 = a speed trap right here.
var threat := 0.0

var _beep_in := 0.0


func setup(race_node: Race, prop_data: PropData) -> void:
	super(race_node, prop_data)
	race.hud.show_radar(true)


func blocks_speed_traps() -> bool:
	return true


func tick(delta: float) -> void:
	threat = race.police.threat_at(race.car.road_s) if race.police else 0.0
	race.hud.set_radar_threat(threat)
	if threat <= 0.05:
		_beep_in = 0.0
		return
	_beep_in -= delta
	if _beep_in <= 0.0:
		_beep_in = lerpf(0.9, 0.12, threat)
		Sfx.play(self, &"radar_beep", -10.0)
