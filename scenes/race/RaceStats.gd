class_name RaceStats
extends RefCounted
## What happened during one run, for the results screen.

var near_misses := 0
var bonus_time := 0.0
var spin_outs := 0
var top_speed_mph := 0.0
## The equipped prop's id (the results screen shows its stat).
var prop_id: StringName = &""
## Cars crashed out by the censored gesture (the rager plus its pileup).
var road_rage_kos := 0
var drivers_blinded := 0
## Pulled over by the police, and the seconds those tickets cost.
var tickets := 0
var ticket_time := 0.0
## Chases you got away from.
var escapes := 0
