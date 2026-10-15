class_name Corridor
extends RefCounted
## The stylized I-35 corridor, south to north. Miles are approximate I-35 mile
## markers (they count up going north; Dallas is on I-35E), so the HUD strip and
## the roadside posts read like the real thing even though the drive is
## heavily compressed. Metro towns get a jam on their approach.

const TOWNS: Dictionary = {
	&"austin": {"name": "Austin", "mile": 234.0, "metro": true},
	&"round_rock": {"name": "Round Rock", "mile": 252.0, "metro": false},
	&"georgetown": {"name": "Georgetown", "mile": 261.0, "metro": false},
	&"salado": {"name": "Salado", "mile": 284.0, "metro": false},
	&"temple": {"name": "Temple", "mile": 301.0, "metro": false},
	&"waco": {"name": "Waco", "mile": 335.0, "metro": false},
	&"west": {"name": "West", "mile": 353.0, "metro": false},
	&"hillsboro": {"name": "Hillsboro", "mile": 368.0, "metro": false},
	&"dallas": {"name": "Dallas", "mile": 428.0, "metro": true},
}


static func has_town(id: StringName) -> bool:
	return TOWNS.has(id)


static func town_name(id: StringName) -> String:
	return TOWNS[id]["name"]


static func town_mile(id: StringName) -> float:
	return TOWNS[id]["mile"]


static func is_metro(id: StringName) -> bool:
	return TOWNS[id]["metro"]


## Towns strictly between `from` and `to`, in driving order.
static func towns_between(from: StringName, to: StringName) -> Array[StringName]:
	var a := town_mile(from)
	var b := town_mile(to)
	var found: Array[StringName] = []
	for id: StringName in TOWNS:
		var mile := town_mile(id)
		if mile > minf(a, b) and mile < maxf(a, b):
			found.append(id)
	found.sort_custom(func(x: StringName, y: StringName) -> bool:
		return absf(town_mile(x) - a) < absf(town_mile(y) - a))
	return found
