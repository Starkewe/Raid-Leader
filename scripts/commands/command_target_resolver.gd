extends RefCounted
class_name CommandTargetResolver

const GROUP_SIZE: int = 5

const SELECTOR_EVERYONE := "everyone"
const SELECTOR_CLASS := "class"
const SELECTOR_GROUP := "group"
const SELECTOR_UNIT := "unit"
const SELECTOR_UNIT_IDENTITY := "unit_identity"
const SELECTOR_ROLE := "role"

const CLASS_WARRIOR := "Warrior"
const CLASS_ROGUE := "Rogue"
const CLASS_MAGE := "Mage"
const CLASS_PRIEST := "Priest"

const ROLE_TANK := "tank"
const ROLE_OFFTANK := "offtank"
const ROLE_TANK_GROUP := "tank_group"
const ROLE_MELEE := "melee"
const ROLE_MELEE_DPS := "melee_dps"
const ROLE_DPS := "dps"
const ROLE_RANGED_DPS := "ranged_dps"
const ROLE_CASTER := "caster"
const ROLE_HEALER := "healer"

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

	match normalized_role:
		ROLE_TANK:
			return get_single_unit_array(get_living_unit_by_identity(CLASS_WARRIOR, 1))

		ROLE_OFFTANK:
			return get_single_unit_array(get_living_unit_by_identity(CLASS_WARRIOR, 2))

		ROLE_TANK_GROUP:
			return get_living_units_by_class(CLASS_WARRIOR)

		ROLE_MELEE:
			var melee_units: Array = []
			append_unique_units(melee_units, get_living_units_by_class(CLASS_WARRIOR))
			append_unique_units(melee_units, get_living_units_by_class(CLASS_ROGUE))
			return melee_units

		ROLE_MELEE_DPS:
			return get_living_units_by_class(CLASS_ROGUE)

		ROLE_DPS:
			var dps_units: Array = []
			append_unique_units(dps_units, get_living_units_by_class(CLASS_ROGUE))
			append_unique_units(dps_units, get_living_units_by_class(CLASS_MAGE))
			return dps_units

		ROLE_RANGED_DPS:
			return get_living_units_by_class(CLASS_MAGE)

		ROLE_CASTER:
			return get_living_units_by_class(CLASS_MAGE)

		ROLE_HEALER:
			return get_living_units_by_class(CLASS_PRIEST)

		_:
			print("Unknown role:", role_name)
			return []

func normalize_role_name(role_name: String) -> String:
	var role := role_name.to_lower().strip_edges()
	role = role.replace(" ", "_")

	match role:
		"tank", "main_tank":
			return ROLE_TANK

		"off_tank", "offtank":
			return ROLE_OFFTANK

		"tanks", "tank_group":
			return ROLE_TANK_GROUP

		"melee":
			return ROLE_MELEE

		"melee_dps":
			return ROLE_MELEE_DPS

		"dps":
			return ROLE_DPS

		"ranged", "ranged_dps", "range_dps":
			return ROLE_RANGED_DPS

		"caster", "casters":
			return ROLE_CASTER

		"healer", "healers":
			return ROLE_HEALER

		_:
			return role


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
