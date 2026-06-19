extends RefCounted
class_name CommandTargetResolver

const GROUP_SIZE: int = 5

var party_members: Array = []


func setup(new_party_members: Array) -> void:
	party_members = new_party_members


func get_units_for_command(command_data: Dictionary) -> Array:
	var who_type: String = String(command_data.get("who_type", "everyone"))
	var selected_units: Array = []

	match who_type:
		"everyone":
			selected_units = get_living_party_members()

		"class":
			var class_name_value: String = String(command_data.get("who_value", ""))
			selected_units = get_living_units_by_class(class_name_value)

		"group":
			var group_number: int = int(command_data.get("who_value", 0))
			selected_units = get_living_units_by_group(group_number)

		"unit":
			var unit_node = command_data.get("unit", null)

			if unit_node is Node and is_unit_alive(unit_node):
				selected_units.append(unit_node)

		_:
			print("Unknown who_type:", who_type)

	return selected_units


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
