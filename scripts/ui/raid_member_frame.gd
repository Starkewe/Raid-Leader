extends PanelContainer
class_name RaidMemberFrame

const DodgeTuningScript := preload("res://scripts/combat/dodge_tuning.gd")

signal hovered(unit)
signal unhovered(unit)

@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var health_bar: ProgressBar = $VBoxContainer/HealthBar
@onready var cast_bar: ProgressBar = $VBoxContainer/CastBar
@onready var status_label: Label = $VBoxContainer/StatusLabel

var unit: Node = null
var display_name: String = ""
var normal_modulate: Color

func _ready():
	normal_modulate = modulate

	mouse_filter = Control.MOUSE_FILTER_STOP

	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	health_bar.show_percentage = false
	cast_bar.show_percentage = false
	cast_bar.visible = true
	cast_bar.value = 0

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if not unit.has_method("get_dodge_charge_display"):
		return

	var segments: Array = unit.get_dodge_charge_display()

	if segments.is_empty():
		return

	var gap := 2.0 if segments.size() > 1 else 0.0
	var total_width := maxf(size.x - 4.0, 1.0)
	var segment_width := (total_width - gap * float(segments.size() - 1)) / float(segments.size())
	var bar_height := 2.0
	var bar_y := size.y - bar_height
	var empty_color := Color(0.32, 0.28, 0.12, 0.28)
	var charging_color := Color(0.82, 0.66, 0.12, 0.78)
	var ready_color := Color(1.0, 0.84, 0.12, 1.0)

	for segment_index in range(segments.size()):
		var segment: Dictionary = segments[segment_index]
		var x := 2.0 + float(segment_index) * (segment_width + gap)
		var segment_rect := Rect2(Vector2(x, bar_y), Vector2(segment_width, bar_height))
		draw_rect(segment_rect, empty_color)

		var fill := clampf(float(segment.get("fill", 0.0)), 0.0, 1.0)

		if fill <= 0.0:
			continue

		var fill_color := ready_color if bool(segment.get("ready", false)) else charging_color

		if bool(segment.get("flash", false)):
			var flash_strength := float(segment.get("flash_strength", 0.0))
			fill_color = fill_color.lightened(flash_strength)

		draw_rect(
			Rect2(
				segment_rect.position,
				Vector2(segment_width * fill, bar_height)
			),
			fill_color
		)

func setup(new_unit: Node, new_display_name: String):
	unit = new_unit
	display_name = new_display_name
	update_from_unit()

func update_from_unit(update_status: bool = true):
	if unit == null or not is_instance_valid(unit):
		name_label.text = display_name
		health_bar.value = 0
		cast_bar.value = 0

		if update_status:
			status_label.text = "Missing"

		return

	update_health_bar()
	update_cast_bar()

	if update_status:
		update_status_label()

func update_health_bar():
	var current_health := get_unit_current_health()
	var max_health := get_unit_max_health()

	health_bar.max_value = max(max_health, 1)
	health_bar.value = clamp(current_health, 0, max_health)

	name_label.text = display_name + "  " + str(current_health) + "/" + str(max_health)

func update_cast_bar():
	cast_bar.visible = true
	cast_bar.max_value = 100

	if unit == null or not is_instance_valid(unit):
		cast_bar.value = 0
		return

	if unit.has_method("is_casting_ability") and unit.is_casting_ability():
		if unit.has_method("get_cast_progress_percent"):
			cast_bar.value = unit.get_cast_progress_percent()
		else:
			cast_bar.value = 0
	else:
		cast_bar.value = 0

func update_status_label():
	if unit.has_method("get_status_text"):
		status_label.text = unit.get_status_text()
	else:
		status_label.text = "Idle"

func set_status_text(text: String):
	status_label.text = text

func get_unit_current_health() -> int:
	if unit.has_method("get_current_health"):
		return unit.get_current_health()

	var value = unit.get("health")

	if value == null:
		return 0

	return int(value)

func get_unit_max_health() -> int:
	if unit.has_method("get_max_health"):
		return unit.get_max_health()

	var value = unit.get("max_health")

	if value == null:
		return 1

	return int(value)

func _on_mouse_entered():
	modulate = Color(1.25, 1.25, 1.25, 1.0)

	if unit != null and is_instance_valid(unit):
		hovered.emit(unit)

func _on_mouse_exited():
	modulate = normal_modulate

	if unit != null and is_instance_valid(unit):
		unhovered.emit(unit)
