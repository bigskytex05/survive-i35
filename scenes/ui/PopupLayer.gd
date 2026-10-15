class_name PopupLayer
extends Control
## Short, punchy bubbles that pop in above the car, float up and fade
## ("NEAR MISS +0.5s", "SPUN OUT!"). Bubbles are pooled and stack when several
## arrive at once.

const RISE := 80.0
const LIFE := 1.4
const STACK_GAP := 50.0

var _idle: Array[PanelContainer] = []
var _live: Array[PanelContainer] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_text(text: String, color: Color, font_size := 28) -> void:
	var bubble := _take()
	var label := bubble.get_child(0) as Label
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	bubble.reset_size()
	bubble.pivot_offset = bubble.size * 0.5
	# Start above the car, nudged up past any bubbles that are still young.
	var start := Vector2((size.x - bubble.size.x) * 0.5, size.y * 0.5 - bubble.size.y * 0.5)
	for other in _live:
		if other != bubble and other.position.y > start.y - STACK_GAP and other.position.y < start.y + STACK_GAP:
			start.y = other.position.y - STACK_GAP
	bubble.position = start
	bubble.modulate.a = 1.0
	bubble.scale = Vector2(0.6, 0.6)
	bubble.visible = true
	var tween := bubble.create_tween()
	tween.tween_property(bubble, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(bubble, "position:y", start.y - RISE, LIFE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(bubble, "modulate:a", 0.0, 0.45).set_delay(LIFE - 0.45)
	tween.finished.connect(_retire.bind(bubble))


func _take() -> PanelContainer:
	var bubble: PanelContainer
	if _idle.is_empty():
		bubble = PanelContainer.new()
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := UiTheme.panel_box(Color(Palette.UI_PANEL, 0.95), 18, 10.0)
		box.content_margin_left = 20.0
		box.content_margin_right = 20.0
		bubble.add_theme_stylebox_override("panel", box)
		var label := Label.new()
		label.add_theme_font_override("font", UiTheme.font(900))
		bubble.add_child(label)
		add_child(bubble)
	else:
		bubble = _idle.pop_back()
	_live.append(bubble)
	return bubble


func _retire(bubble: PanelContainer) -> void:
	bubble.visible = false
	_live.erase(bubble)
	_idle.append(bubble)
