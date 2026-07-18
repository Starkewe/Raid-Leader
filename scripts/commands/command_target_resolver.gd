extends RefCounted
class_name CommandTargetResolver

const CommandSchemaScript := preload("res://scripts/commands/command_schema.gd")

const GROUP_SIZE: int = 5

const SELECTOR_EVERYONE := CommandSchemaScript.SELECTOR_EVERYONE
const SELECTOR_CLASS := CommandSchemaScript.SELECTOR_CLASS
const SELECTOR_GROUP := CommandSchemaScript.SELECTOR_GROUP
const SELECTOR_UNIT := CommandSchemaScript.SELECTOR_UNIT
const SELECTOR_UNIT_IDENTITY := CommandSchemaScript.SELECTOR_UNIT_IDENTITY
const SELECTOR_ROLE := CommandSchemaScript.SELECTOR_ROLE

var party_members: Array = []


func setup(new_party_members: Array) -> void:
	party_members = new_party_members


func get_units_for_command(command_data: Dictionary) -> Array:
	var selected_units: Array = []

	var include_selectors := get_include_selectors(command_data)
	var exclude_selectors := get_exclude_selectors(command_data)

	for selector in include_selectors:
		append_unique_units(selected_units, get_units_for_selector(selector))

	if selected_units.is_empty():
		selected_units = get_units_from_legacy_command_data(command_data)

	if not exclude_selectors.is_empty():
		var excluded_units: Array = []

		for selector in exclude_selectors:
			append_unique_units(excluded_units, get_units_for_selector(selector))

		selected_units = remove_units(selected_units, excluded_units)

	return selected_units


func get_include_selectors(command_data: Dictionary) -> Array:
	var selectors_value = command_data.get("who_selectors", [])

	if selectors_value is Array and not selectors_value.is_empty():
		return selectors_value

	return [
		{
			"type": String(command_data.get("who_type", SELECTOR_EVERYONE)),
			"value": command_data.get("who_value", ""),
			"unit": command_data.get("unit", null)
		}
	]


func get_exclude_selectors(command_data: Dictionary) -> Array:
	var selectors_value = command_data.get("who_exclude_selectors", [])

	if selectors_value is Array:
		return selectors_value

	return []


func get_units_from_legacy_command_data(command_data: Dictionary) -> Array:
	return get_units_for_selector({
		"type": String(command_data.get("who_type", SELECTOR_EVERYONE)),
		"value": command_data.get("who_value", ""),
		"unit": command_data.get("unit", null)
	})


func get_units_for_selector(selector: Dictionary) -> Array:
	var selector_type := String(selector.get("type", SELECTOR_EVERYONE))
	var selector_value = selector.get("value", "")

	match selector_type:
		SELECTOR_EVERYONE:
			return get_living_party_members()

		SELECTOR_CLASS:
			return get_living_units_by_class(String(selector_value))

		SELECTOR_GROUP:
			return get_living_units_by_group(int(selector_value))

		SELECTOR_UNIT:
			var selected_units: Array = []
			var unit_node = selector.get("unit", null)

			if unit_node is Node and is_unit_alive(unit_node):
				selected_units.append(unit_node)

			return selected_units

		SELECTOR_UNIT_IDENTITY:
			return get_single_unit_array(
				get_living_unit_by_identity(
					String(selector.get("class", "")),
					int(selector.get("number", 0))
				)
			)

		SELECTOR_ROLE:
			return get_living_units_by_role(String(selector_value))

		_:
			print("Unknown selector type:", selector_type)
			return []


func get_living_party_members() -> Array:
	var living_members: Array = []

	for unit in party_members:
		if is_unit_alive(unit):
			living_members.append(unit)

	return living_members


func get_living_units_by_class(class_name_value: String) -> Array:
	var matching_units: Array = []

	for unit in party_members:
		if not is_unit_alive(unit):
			continue

		if get_unit_class_name(unit) == class_name_value:
			matching_units.append(unit)

	return matching_units


func get_living_units_by_group(group_number: int) -> Array:
	var matching_units: Array = []

	if group_number <= 0:
		return matching_units

	var start_index: int = (group_number - 1) * GROUP_SIZE
	var end_index: int = start_index + GROUP_SIZE

	for index in range(start_index, end_index):
		if index < 0 or index >= party_members.size():
			continue

		var unit = party_members[index]

		if is_unit_alive(unit):
			matching_units.append(unit)

	return matching_units


func get_living_units_by_role(role_name: String) -> Array:
	var normalized_role := normalize_role_name(role_name)
	var role_data := GameState.get_role_data(normalized_role)

	if role_data.is_empty():
		print("Unknown role:", role_name)
		return []

	var match_role := String(role_data.get("match_role", normalized_role))
	var matching_units: Array = []

	for unit in party_members:
		if not is_unit_alive(unit):
			continue

		if unit_has_role(unit, match_role):
			matching_units.append(unit)

	match String(role_data.get("selection", "all")):
		"first":
			return get_single_unit_array(
				matching_units[0] if matching_units.size() >= 1 else null
			)

		"second":
			return get_single_unit_array(
				matching_units[1] if matching_units.size() >= 2 else null
			)

		_:
			return matching_units

func normalize_role_name(role_name: String) -> String:
	return GameState.normalize_role_name(role_name)


func unit_has_role(unit: Node, role_name: String) -> bool:
	if unit.has_method("has_role"):
		return bool(unit.has_role(role_name))

	var definition := GameState.get_unit_definition(get_unit_class_name(unit))
	return definition != null and definition.has_role(role_name)


func get_living_unit_by_identity(class_name_value: String, unit_number_value: int) -> Node:
	if class_name_value.is_empty() or unit_number_value <= 0:
		return null

	for unit in party_members:
		if not is_unit_alive(unit):
			continue

		if get_unit_class_name(unit) != class_name_value:
			continue

		var actual_unit_number = unit.get("unit_number")

		if actual_unit_number != null and int(actual_unit_number) == unit_number_value:
			return unit

	var matching_class_units := get_living_units_by_class(class_name_value)
	var fallback_index := unit_number_value - 1

	if fallback_index >= 0 and fallback_index < matching_class_units.size():
		return matching_class_units[fallback_index]

	return null


func get_single_unit_array(unit: Node) -> Array:
	var units: Array = []

	if is_unit_alive(unit):
		units.append(unit)

	return units


func append_unique_units(target_units: Array, source_units: Array) -> void:
	for unit in source_units:
		if unit == null:
			continue

		if not target_units.has(unit):
			target_units.append(unit)


func remove_units(source_units: Array, units_to_remove: Array) -> Array:
	var remaining_units: Array = []

	for unit in source_units:
		if units_to_remove.has(unit):
			continue

		remaining_units.append(unit)

	return remaining_units


func get_unit_class_name(unit: Node) -> String:
	if not is_valid_node(unit):
		return ""

	var unit_class_value = unit.get("unit_class")

	if unit_class_value != null and String(unit_class_value) != "":
		return String(unit_class_value)

	return unit.get_class()


func is_unit_alive(unit: Node) -> bool:
	if unit == null:
		return false

	if not is_instance_valid(unit):
		return false

	if unit.has_method("is_alive"):
		return unit.is_alive()

	return true


func is_valid_node(node: Node) -> bool:
	return node != null and is_instance_valid(node)
