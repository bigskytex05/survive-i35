class_name TicketCard
extends CanvasLayer
## "PULLED OVER": the trooper's line and your citation, on a paper ticket over
## the frozen race. It closes itself after SHOW_TIME (or sooner with Enter,
## Space or a tap, once it's been up for SKIP_AFTER), then emits `closed`.
## Built in code; runs while the tree is paused.

signal closed

const SHOW_TIME := 3.4
const SKIP_AFTER := 1.0
const PAPER := Color(0.99, 0.96, 0.86)

var _root: Control
var _quote: Label
var _charge: Label
var _penalty: Label
var _t := -1.0


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.get_theme()
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.09, 0.06, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	var paper := UiTheme.panel_box(PAPER, 10, 26.0)
	paper.border_color = Palette.POLICE_BLUE
	paper.set_border_width_all(0)
	paper.border_width_top = 10
	panel.add_theme_stylebox_override("panel", paper)
	panel.rotation = -0.025
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := _label(box, "PULLED OVER", 44, Palette.POLICE_RED, 900)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quote = _label(box, "", 22, Palette.UI_TEXT, 750)
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rule := ColorRect.new()
	rule.color = Color(Palette.UI_MUTED, 0.5)
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(rule)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)
	_label(grid, "CITATION", 16, Palette.UI_MUTED, 900)
	_charge = _label(grid, "", 20, Palette.UI_TEXT, 900)
	_charge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_charge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(grid, "FINE", 16, Palette.UI_MUTED, 900)
	_penalty = _label(grid, "", 24, Palette.UI_WARN, 900)
	_penalty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var tip := _label(box, "Tip: spot the cruiser, brake to the limit, cruise past, then floor it.", 15,
		Palette.UI_MUTED, 750)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func is_open() -> bool:
	return _root.visible


## `lines` = [what the trooper says, what the ticket's for].
func open(lines: Array[String], penalty: float) -> void:
	_quote.text = "“%s”" % lines[0]
	_charge.text = lines[1]
	_penalty.text = "\u2212%d SECONDS" % roundi(penalty)
	_root.visible = true
	_t = 0.0


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	_t = -1.0
	closed.emit()


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var skip := _t >= SKIP_AFTER and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("use_prop"))
	if _t >= SHOW_TIME or skip:
		close()


func _on_dim_input(event: InputEvent) -> void:
	if _t >= SKIP_AFTER and (event is InputEventMouseButton or event is InputEventScreenTouch) and event.is_pressed():
		close()


func _label(parent: Node, text: String, font_size: int, color: Color, weight: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.font(weight))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
