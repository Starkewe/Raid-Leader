extends RefCounted
class_name CommandDebugFormatter


static func build_data(
	source: String,
	command_data: Dictionary,
	debug_context: Dictionary,
	result_text: String
) -> Dictionary:
	return {
		"source": get_source_text(source),
		"transcript": String(debug_context.get("transcript", "-")),
		"normalized": String(debug_context.get("normalized_text", "-")),
		"who": get_who_text(command_data),
		"what": get_what_text(command_data),
		"where": get_where_text(command_data),
		"result": result_text,
		"command_data": get_command_data_text(command_data)
	}


static func get_source_text(source: String) -> String:
	match source:
		"voice":
			return "Voice"
		"command_panel":
			return "Command Panel"
		_:
			return source.capitalize()


static func get_who_text(command_data: Dictionary) -> String:
	var selectors: Array = command_data.get("who_selectors", [])
	var exclusions: Array = command_data.get("who_exclude_selectors", [])

	if not selectors.is_empty():
		var text := get_selector_list_text(selectors)

		if not exclusions.is_empty():
			text += " except " + get_selector_list_text(exclusions)

		return text

	return get_selector_text({
		"type": String(command_data.get("who_type", "")),
		"value": command_data.get("who_value", ""),
		"unit": command_data.get("unit", null)
	})


static func get_selector_list_text(selectors: Array) -> String:
	var parts: Array[String] = []

	for selector in selectors:
		if selector is Dictionary:
			parts.append(get_selector_text(selector))

	return " and ".join(parts)


static func get_selector_text(selector: Dictionary) -> String:
	var selector_type := String(selector.get("type", ""))
	var selector_value = selector.get("value", "")

	match selector_type:
		"everyone":
			return "Everyone"
		"class":
			return "Class: " + String(selector_value)
		"group":
			return "Group: " + str(selector_value)
		"role":
			return "Role: " + String(selector_value)
		"unit_identity":
			return "Unit: " + String(selector.get("class", "")) + " " + str(selector.get("number", ""))
		"unit":
			return _get_unit_text(selector.get("unit", null))
		_:
			return "Unknown"


static func get_what_text(command_data: Dictionary) -> String:
	var action := String(command_data.get("what", ""))
	return "-" if action.is_empty() else action.capitalize()


static func get_where_text(command_data: Dictionary) -> String:
	var destination := String(command_data.get("where", ""))

	match destination:
		"boss":
			return "Boss"
		"boss_target":
			return "Boss Target"
		"me":
			return "Me"
		"movement_range_step":
			return "Range Step: " + String(command_data.get("movement_direction", ""))
		"movement_range":
			return "Range: " + String(command_data.get("movement_range", ""))
		"movement_region":
			return "Region: " + String(command_data.get("movement_region", ""))
		"movement_slot":
			return "Slot: " + String(command_data.get("movement_region", "")) + " " + String(command_data.get("movement_range", ""))
		"movement_rotate_step":
			return "Rotate Step: " + String(command_data.get("movement_direction", ""))
		"movement_rotate":
			return "Rotate To: " + String(command_data.get("movement_region", ""))
		_:
			return "-" if destination.is_empty() else destination


static func get_command_data_text(command_data: Dictionary) -> String:
	if command_data.is_empty():
		return "-"

	var safe_data := {}

	for key in command_data.keys():
		var value = command_data[key]
		safe_data[key] = _get_node_name(value) if value is Node else value

	return str(safe_data)


static func _get_unit_text(unit: Node) -> String:
	return "Unit: " + _get_node_name(unit) if unit != null and is_instance_valid(unit) else "Unit: Missing"


static func _get_node_name(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return "Missing"

	if node.has_method("get_display_name"):
		return String(node.get_display_name())

	return node.name
