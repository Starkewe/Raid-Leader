extends RefCounted

class_name CombatStatusPresenter

var ui: Node = null
var boss: Node = null
var is_unit_alive_callable: Callable = Callable()

var temporary_statuses: Dictionary = {}
var status_refresh_timer: float = 0.0
var status_refresh_interval: float = 0.15

func set_temporary_status(unit: Node, text: String, duration: float) -> void:
	if unit == null:
		return

	if not is_instance_valid(unit):
		return

	temporary_statuses[unit] = {
		"text": text,
		"time": duration
	}


func clear_temporary_status(unit: Node) -> void:
	if unit == null:
		return

	temporary_statuses.erase(unit)


func clear_all_temporary_statuses() -> void:
	temporary_statuses.clear()


func has_temporary_status(unit: Node) -> bool:
	return temporary_statuses.has(unit)


func get_status_for_unit(unit: Node) -> String:
	if temporary_statuses.has(unit):
		return String(temporary_statuses[unit].get("text", ""))

	if unit != null and is_instance_valid(unit) and unit.has_method("get_status_text"):
		return unit.get_status_text()

	return ""


func update_temporary_statuses(delta: float) -> bool:
	var changed := false
	var expired_units: Array = []

	for unit in temporary_statuses.keys():
		if unit == null or not is_instance_valid(unit):
			expired_units.append(unit)
			continue

		temporary_statuses[unit]["time"] -= delta

		if temporary_statuses[unit]["time"] <= 0.0:
			expired_units.append(unit)

	for unit in expired_units:
		temporary_statuses.erase(unit)
		changed = true

	return changed
func get_status_override_texts(is_unit_alive_callable: Callable = Callable()) -> Dictionary:
	var overrides: Dictionary = {}

	for unit in temporary_statuses.keys():
		if unit == null or not is_instance_valid(unit):
			continue

		if not is_unit_alive_callable.is_null():
			var alive_result = is_unit_alive_callable.call(unit)

			if alive_result != true:
				continue

		var data: Dictionary = temporary_statuses[unit]
		overrides[unit] = String(data.get("text", ""))

	return overrides
func should_refresh_statuses(delta: float) -> bool:
	status_refresh_timer += delta

	if status_refresh_timer < status_refresh_interval:
		return false

	status_refresh_timer = 0.0
	return true


func reset_status_refresh_timer() -> void:
	status_refresh_timer = 0.0
func setup(new_ui: Node, new_boss: Node, new_is_unit_alive_callable: Callable) -> void:
	ui = new_ui
	boss = new_boss
	is_unit_alive_callable = new_is_unit_alive_callable
func initialize_ui() -> void:
	if ui == null or not is_instance_valid(ui):
		return

	if ui.has_method("refresh_raid_frames"):
		ui.refresh_raid_frames({})

	if ui.has_method("set_boss_status"):
		ui.set_boss_status("Idle")


func refresh_all_statuses(encounter_state: String) -> void:
	if ui == null or not is_instance_valid(ui):
		return

	if ui.has_method("refresh_raid_frames"):
		ui.refresh_raid_frames(get_status_override_texts(is_unit_alive_callable))

	if ui.has_method("refresh_boss_frame"):
		ui.refresh_boss_frame(false)

	if not ui.has_method("set_boss_status"):
		return

	if encounter_state == "victory":
		ui.set_boss_status("Defeated")
	elif encounter_state == "wipe":
		ui.set_boss_status("Party Wiped")
	elif boss != null and is_instance_valid(boss) and boss.has_method("get_status_text"):
		ui.set_boss_status(boss.get_status_text())
	else:
		ui.set_boss_status("Idle")
