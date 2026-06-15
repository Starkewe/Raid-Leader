extends PanelContainer
class_name RaidMemberFrame

@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var health_bar: ProgressBar = $VBoxContainer/HealthBar
@onready var cast_bar: ProgressBar = $VBoxContainer/CastBar
@onready var status_label: Label = $VBoxContainer/StatusLabel

var unit: Node = null
var display_name: String = ""

func _ready():
	health_bar.show_percentage = false
	cast_bar.show_percentage = false
	cast_bar.visible = false

func setup(new_unit: Node, new_display_name: String):
	unit = new_unit
	display_name = new_display_name
	update_from_unit()

func update_from_unit(update_status: bool = true):
	if unit == null or not is_instance_valid(unit):
		name_label.text = display_name
		health_bar.value = 0
		cast_bar.visible = false

		if update_status:
			status_label.text = "Missing"

		return

	var current_health := get_unit_current_health()
	var max_health := get_unit_max_health()

	health_bar.max_value = max(max_health, 1)
	health_bar.value = clamp(current_health, 0, max_health)

	name_label.text = display_name + "  " + str(current_health) + "/" + str(max_health)

	update_cast_bar()

	if update_status:
		if unit.has_method("get_status_text"):
			status_label.text = unit.get_status_text()
		else:
			status_label.text = "Idle"

func set_status_text(text: String):
	status_label.text = text

func update_cast_bar():
	if cast_bar == null:
		return

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
