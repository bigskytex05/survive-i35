class_name RaceClock
extends Node
## The level timer. It counts down in physics time, so pausing stops it and
## tests are deterministic, and it takes bonuses and penalties.

signal expired

var time_left := 180.0
var running := false


func start(seconds: float) -> void:
	time_left = seconds
	running = true


func stop() -> void:
	running = false


## Bonus (positive) or penalty (negative) seconds.
func add(seconds: float) -> void:
	time_left = maxf(0.0, time_left + seconds)


func _physics_process(delta: float) -> void:
	if not running:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		running = false
		expired.emit()


## "2:59" normally, "9.4" in the final ten seconds.
static func format(seconds: float) -> String:
	if seconds < 10.0:
		return "%.1f" % maxf(seconds, 0.0)
	var whole := floori(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]


## Always "m:ss.t" (results screen).
static func format_precise(seconds: float) -> String:
	var t := maxf(seconds, 0.0)
	var minutes := floori(t / 60.0)
	return "%d:%s" % [minutes, ("%.1f" % (t - minutes * 60.0)).pad_zeros(2)]
