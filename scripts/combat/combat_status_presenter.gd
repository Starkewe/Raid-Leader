extends RefCounted

class_name CombatStatusPresenter

var temporary_statuses: Dictionary = {}


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
