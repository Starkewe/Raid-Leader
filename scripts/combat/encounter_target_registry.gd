extends RefCounted
class_name EncounterTargetRegistry

signal targets_changed
signal target_defeated(target: Node)

var targets: Array[Node] = []
var descriptor_overrides: Dictionary = {}


func register_target(target: Node, descriptor: Dictionary = {}) -> void:
	if target == null or not is_instance_valid(target) or targets.has(target):
		return

	targets.append(target)
	if not descriptor.is_empty():
		descriptor_overrides[target] = descriptor.duplicate(true)
	var defeated_callback := Callable(self, "_on_target_defeated")
	if target.has_signal("defeated") and not target.is_connected("defeated", defeated_callback):
		target.connect("defeated", defeated_callback)
	targets_changed.emit()


func unregister_target(target: Node) -> void:
	if target == null:
		return

	if targets.has(target):
		var defeated_callback := Callable(self, "_on_target_defeated")
		if target.has_signal("defeated") and target.is_connected("defeated", defeated_callback):
			target.disconnect("defeated", defeated_callback)
		targets.erase(target)
		descriptor_overrides.erase(target)
		targets_changed.emit()


func clear() -> void:
	for target in targets:
		if target == null or not is_instance_valid(target):
			continue

		var defeated_callback := Callable(self, "_on_target_defeated")
		if target.has_signal("defeated") and target.is_connected("defeated", defeated_callback):
			target.disconnect("defeated", defeated_callback)

	targets.clear()
	descriptor_overrides.clear()
	targets_changed.emit()


func get_target_entries(selector: Dictionary = {}) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	for target in targets:
		if not _is_living_target(target):
			continue

		var descriptor := get_target_descriptor(target)
		if not _matches_selector(descriptor, selector):
			continue

		entries.append(descriptor)

	return entries


func get_living_targets(selector: Dictionary = {}) -> Array[Node]:
	var result: Array[Node] = []

	for entry in get_target_entries(selector):
		var target = entry.get("node", null)
		if target is Node and is_instance_valid(target):
			result.append(target)

	return result


func get_primary_targets(include_defeated: bool = false) -> Array[Node]:
	var result: Array[Node] = []

	for target in targets:
		if target == null or not is_instance_valid(target):
			continue

		if not include_defeated and not _is_living_target(target):
			continue

		var descriptor := get_target_descriptor(target)
		if not bool(descriptor.get("primary_boss_target", false)):
			continue

		result.append(target)

	return result


func resolve_selector(selector: Dictionary) -> Dictionary:
	var entries := get_target_entries(selector)

	if entries.is_empty():
		return {
			"ok": false,
			"reason": _missing_selector_reason(selector),
			"target": null,
			"entries": []
		}

	if entries.size() > 1 and String(selector.get("side", "")).is_empty():
		var sides: Array[String] = []
		for entry in entries:
			var entry_side := String(entry.get("side", ""))
			if not entry_side.is_empty() and not sides.has(entry_side):
				sides.append(entry_side)

		if sides.size() == 1:
			return {
				"ok": true,
				"reason": "",
				"target": entries[0].get("node", null),
				"entries": entries
			}

		return {
			"ok": false,
			"reason": "The encounter target is ambiguous; specify east or west.",
			"target": null,
			"entries": entries
		}

	return {
		"ok": true,
		"reason": "",
		"target": entries[0].get("node", null),
		"entries": entries
	}


func get_next_target(selector: Dictionary, defeated_target: Node = null) -> Node:
	var entries := get_target_entries(selector)

	for entry in entries:
		var candidate = entry.get("node", null)
		if candidate == defeated_target:
			continue

		if candidate is Node and is_instance_valid(candidate):
			return candidate

	return null


func get_target_descriptor(target: Node) -> Dictionary:
	if descriptor_overrides.has(target):
		var overridden: Dictionary = descriptor_overrides[target].duplicate(true)
		overridden["node"] = target
		return overridden

	if target != null and is_instance_valid(target) and target.has_method("get_encounter_target_descriptor"):
		var descriptor = target.get_encounter_target_descriptor()
		if descriptor is Dictionary:
			var result: Dictionary = descriptor.duplicate(true)
			result["node"] = target
			return result

	return {
		"target_id": target.name if target != null else "",
		"display_name": target.name if target != null else "Unknown",
		"kind": "encounter_target",
		"node": target
	}


func _on_target_defeated(target: Node) -> void:
	target_defeated.emit(target)
	targets_changed.emit()


func _matches_selector(descriptor: Dictionary, selector: Dictionary) -> bool:
	if selector.is_empty():
		return true

	var requested_kind := String(selector.get("kind", ""))
	if not requested_kind.is_empty() and String(descriptor.get("kind", "")) != requested_kind:
		return false

	var requested_side := String(selector.get("side", "")).to_lower().strip_edges()
	if not requested_side.is_empty() and String(descriptor.get("side", "")).to_lower() != requested_side:
		return false

	var requested_target_id := String(selector.get("target_id", ""))
	if not requested_target_id.is_empty() and String(descriptor.get("target_id", "")) != requested_target_id:
		return false

	return true


func _missing_selector_reason(selector: Dictionary) -> String:
	var side := String(selector.get("side", "")).capitalize()
	if not side.is_empty():
		return "There is no living %s encounter target." % side

	return "There is no living encounter target."


func _is_living_target(target: Node) -> bool:
	return (
		target != null
		and is_instance_valid(target)
		and (not target.has_method("is_alive") or bool(target.is_alive()))
	)
