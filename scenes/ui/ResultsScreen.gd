class_name ResultsScreen
extends CanvasLayer
## End-of-race card for both outcomes: a headline, the level's funny line, a
## few stats, Retry and Change Loadout (back to the garage). Phase 6 adds stars
## and Next Level.

signal retry_pressed
signal loadout_pressed

@onready var _root: Control = $Root
@onready var _title: Label = %Title
@onready var _line: Label = %Line
@onready var _stats: GridContainer = %Stats
@onready var _retry: Button = %Retry
@onready var _loadout: Button = %Loadout


func _ready() -> void:
	_root.theme = UiTheme.get_theme()
	_title.add_theme_font_override("font", UiTheme.font(900))
	_retry.pressed.connect(retry_pressed.emit)
	_loadout.pressed.connect(loadout_pressed.emit)
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func show_win(level: LevelData, stats: RaceStats, time_left: float) -> void:
	_open("You made it!", Palette.UI_ACCENT, level.success_line, [
		["Time left", RaceClock.format_precise(time_left)],
		["Near misses", _near_misses(stats)],
		["Spin-outs", str(stats.spin_outs)],
		["Tickets", _tickets(stats)],
		["Top speed", "%d mph" % roundi(stats.top_speed_mph)],
	] + _prop_rows(stats))


func show_fail(level: LevelData, stats: RaceStats, miles_short: float) -> void:
	_open("Out of time", Palette.UI_TEXT, level.fail_line, [
		["Short by", "%.1f mi" % miles_short],
		["Near misses", _near_misses(stats)],
		["Spin-outs", str(stats.spin_outs)],
		["Tickets", _tickets(stats)],
	] + _prop_rows(stats))


## The equipped prop's own stat, if it has one.
func _prop_rows(stats: RaceStats) -> Array:
	match stats.prop_id:
		&"censored_gesture":
			return [["Road rage KOs", str(stats.road_rage_kos)]]
		&"high_beams":
			return [["Drivers blinded", str(stats.drivers_blinded)]]
	return []


func _tickets(stats: RaceStats) -> String:
	if stats.tickets == 0:
		return "0" if stats.escapes == 0 else "0  (lost %d %s)" % [stats.escapes, "cop" if stats.escapes == 1 else "cops"]
	return "%d  (-%ds)" % [stats.tickets, roundi(stats.ticket_time)]


func _near_misses(stats: RaceStats) -> String:
	if stats.near_misses == 0:
		return "0"
	return "%d  (+%.1fs)" % [stats.near_misses, stats.bonus_time]


func _open(title: String, color: Color, line: String, rows: Array) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", color)
	_line.text = line
	for child in _stats.get_children():
		child.queue_free()
	for row: Array in rows:
		var key := Label.new()
		key.text = row[0]
		key.add_theme_color_override("font_color", Palette.UI_MUTED)
		_stats.add_child(key)
		var value := Label.new()
		value.text = row[1]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stats.add_child(value)
	_root.visible = true
	_retry.grab_focus()
