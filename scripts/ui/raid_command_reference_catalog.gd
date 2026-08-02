extends RefCounted
class_name RaidCommandReferenceCatalog

const CommandSchemaScript := preload("res://scripts/commands/command_schema.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")
const VoiceCommandVocabularyScript := preload("res://scripts/voice/voice_command_vocabulary.gd")

const CLASS_ICONS := {
	"Warrior": preload("res://icons/Warrior (Small).png"),
	"Priest": preload("res://icons/Priest (Small).png"),
	"Rogue": preload("res://icons/Rogue (Small).png"),
	"Mage": preload("res://icons/Mage (Small).png")
}

const ACTION_ORDER: Array[String] = [
	CommandSchemaScript.ACTION_ATTACK,
	CommandSchemaScript.ACTION_MOVE,
	CommandSchemaScript.ACTION_DODGE,
	CommandSchemaScript.ACTION_ROTATE,
	CommandSchemaScript.ACTION_INTERRUPT,
	CommandSchemaScript.ACTION_HEAL,
	CommandSchemaScript.ACTION_CURE,
	CommandSchemaScript.ACTION_TAUNT
]


static func get_who_entries(
	party_members: Array,
	game_state: Node
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	entries.append(_entry(
		"Everyone",
		{
			"who_type": CommandSchemaScript.SELECTOR_EVERYONE,
			"who_value": ""
		},
		"General"
	))

	for unit_class_value in _get_available_classes(game_state):
		var unit_class := String(unit_class_value)
		entries.append(_entry(
			"Class: " + unit_class,
			{
				"who_type": CommandSchemaScript.SELECTOR_CLASS,
				"who_value": unit_class
			},
			"Classes"
		))

	for role_value in _get_role_options(game_state):
		var role_data: Dictionary = role_value
		entries.append(_entry(
			"Role: " + String(role_data.get("display_name", "Role")),
			{
				"who_type": CommandSchemaScript.SELECTOR_ROLE,
				"who_value": String(role_data.get("role", "")),
				"match_role": String(role_data.get(
					"match_role",
					role_data.get("role", "")
				)),
				"selection": String(role_data.get("selection", "all"))
			},
			"Roles"
		))

	var group_count := ceili(float(GameStateScript.MAX_RAID_SIZE) / 5.0)

	for group_number in range(1, group_count + 1):
		entries.append(_entry(
			"Group " + str(group_number),
			{
				"who_type": CommandSchemaScript.SELECTOR_GROUP,
				"who_value": group_number
			},
			"Groups"
		))

	var display_name_counts: Dictionary = {}

	for unit_value in party_members:
		var candidate := unit_value as Node

		if candidate == null or not is_instance_valid(candidate):
			continue

		var candidate_name := get_unit_display_name(candidate)
		display_name_counts[candidate_name] = int(display_name_counts.get(candidate_name, 0)) + 1

	var duplicate_indices: Dictionary = {}

	for unit_value in party_members:
		var unit := unit_value as Node

		if unit == null or not is_instance_valid(unit):
			continue

		var unit_label := get_unit_display_name(unit)
		var canonical_label := get_unit_canonical_name(unit)

		if int(display_name_counts.get(unit_label, 0)) > 1:
			var duplicate_index := int(duplicate_indices.get(unit_label, 0)) + 1
			duplicate_indices[unit_label] = duplicate_index
			unit_label += " - #" + str(duplicate_index)

		entries.append(_entry(
			unit_label,
			{
				"who_type": CommandSchemaScript.SELECTOR_UNIT,
				"who_value": canonical_label,
				"unit": unit
			},
			"Raiders",
			{
				"icon": CLASS_ICONS.get(_get_unit_class(unit)),
				"tooltip": _get_unit_tooltip(unit, canonical_label)
			}
		))

	return entries


static func get_what_entries(
	party_members: Array = [],
	browse_context: Dictionary = {}
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var has_browse_who := browse_context.get("who_metadata", {}) is Dictionary and not Dictionary(
		browse_context.get("who_metadata", {})
	).is_empty()
	var selected_units := _get_units_for_who_metadata(
		party_members,
		Dictionary(browse_context.get("who_metadata", {}))
	)

	for action in ACTION_ORDER:
		var unavailable := not has_browse_who
		var reason := "Select a Who target first." if unavailable else ""

		if not unavailable and not _any_unit_supports_action(selected_units, action):
			unavailable = true
			reason = "The selected raiders cannot use %s." % action.capitalize()

		entries.append(_entry(
			action.capitalize(),
			{"what": action},
			"Actions",
			{
				"requires_who": true,
				"unavailable": unavailable,
				"unavailable_reason": reason
			}
		))

	return entries


static func get_where_entries_for_action(
	action: String,
	party_members: Array,
	game_state: Node
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var section := action.capitalize() + " destinations"

	match action:
		CommandSchemaScript.ACTION_ATTACK:
			entries.append(_entry(
				"Boss",
				{"where": CommandSchemaScript.DESTINATION_BOSS},
				section
			))

		CommandSchemaScript.ACTION_MOVE, CommandSchemaScript.ACTION_DODGE:
			entries.append(_entry(
				"In one range",
				{
					"where": CommandSchemaScript.DESTINATION_MOVEMENT_RANGE_STEP,
					"movement_direction": "in"
				},
				section
			))
			entries.append(_entry(
				"Out one range",
				{
					"where": CommandSchemaScript.DESTINATION_MOVEMENT_RANGE_STEP,
					"movement_direction": "out"
				},
				section
			))

			entries.append_array(_get_compact_movement_rows(section))

		CommandSchemaScript.ACTION_ROTATE:
			entries.append_array(_get_rotation_entries(section))

		CommandSchemaScript.ACTION_INTERRUPT, CommandSchemaScript.ACTION_TAUNT:
			entries.append(_entry(
				"Boss",
				{"where": CommandSchemaScript.DESTINATION_BOSS},
				section
			))

		CommandSchemaScript.ACTION_HEAL:
			entries.append_array(_get_healing_entries(party_members, game_state, section))

		CommandSchemaScript.ACTION_CURE:
			entries.append(_entry(
				"Curable Allies",
				{"where": CommandSchemaScript.DESTINATION_CURABLE_ALLIES},
				section
			))

		_:
			entries.append(_entry("None", {"where": "none"}, section))

	return entries


static func get_when_entries() -> Array[Dictionary]:
	return [
		_entry(
			"Timing commands are not yet available.",
			{"when": "now"},
			"Availability",
			{"unavailable": true}
		)
	]


static func get_reference_sections(
	category: String,
	party_members: Array,
	game_state: Node,
	browse_context: Dictionary = {}
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	match category:
		"who":
			entries = get_who_entries(party_members, game_state)
		"what":
			entries = get_what_entries(party_members, browse_context)
		"where":
			var selected_action := String(browse_context.get("what", ""))
			var where_actions: Array[String] = []

			if not selected_action.is_empty():
				where_actions.append(selected_action)

			for action in where_actions:
				var action_entries := get_where_entries_for_action(
					action,
					party_members,
					game_state
				)

				for entry in action_entries:
					var reference_entry := entry.duplicate(true)
					reference_entry["required_action"] = action
					entries.append(reference_entry)
		"when":
			entries = get_when_entries()

	return _group_entries_by_section(entries)


static func get_where_display_label(command_data: Dictionary) -> String:
	match String(command_data.get("where", "")):
		CommandSchemaScript.DESTINATION_BOSS:
			return "Boss"
		CommandSchemaScript.DESTINATION_BOSS_TARGET:
			return "Boss Target"
		CommandSchemaScript.DESTINATION_HEALING_SCOPE:
			return _healing_scope_label(Dictionary(command_data.get("healing_scope", {})))
		CommandSchemaScript.DESTINATION_CURABLE_ALLIES:
			return "Curable Allies"
		CommandSchemaScript.DESTINATION_PLAYER:
			return "Me"
		CommandSchemaScript.DESTINATION_MOVEMENT_REGION, CommandSchemaScript.DESTINATION_MOVEMENT_ROTATE:
			return String(command_data.get("movement_region", "")).capitalize()
		CommandSchemaScript.DESTINATION_MOVEMENT_RANGE:
			return String(command_data.get("movement_range", "")).capitalize()
		CommandSchemaScript.DESTINATION_MOVEMENT_SLOT:
			return (
				String(command_data.get("movement_region", "")).capitalize()
				+ " — "
				+ String(command_data.get("movement_range", "")).capitalize()
			).strip_edges()
		CommandSchemaScript.DESTINATION_MOVEMENT_ROTATE_STEP, CommandSchemaScript.DESTINATION_MOVEMENT_RANGE_STEP:
			return String(command_data.get("movement_direction", "")).capitalize()

	return String(command_data.get("where", "")).capitalize()


static func get_unit_display_name(unit: Node) -> String:
	if unit == null or not is_instance_valid(unit):
		return "Unknown"

	var canonical := get_unit_canonical_name(unit)
	var unit_class := _get_unit_class(unit)
	var suffix := " (%s)" % unit_class

	if not unit_class.is_empty() and canonical.ends_with(suffix):
		return canonical.trim_suffix(suffix).strip_edges()

	return canonical


static func get_unit_canonical_name(unit: Node) -> String:
	if unit == null or not is_instance_valid(unit):
		return "Unknown"

	if unit.has_method("get_display_name"):
		return String(unit.get_display_name())

	return unit.name


static func _get_rotation_entries(section: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	entries.append(_entry(
		"Counterclockwise",
		{
			"where": CommandSchemaScript.DESTINATION_MOVEMENT_ROTATE_STEP,
			"movement_direction": "counterclockwise"
		},
		section
	))
	entries.append(_entry(
		"Clockwise",
		{
			"where": CommandSchemaScript.DESTINATION_MOVEMENT_ROTATE_STEP,
			"movement_direction": "clockwise"
		},
		section
	))

	for region_value in MovementSlotResolverScript.REGION_ORDER:
		var region := String(region_value)
		entries.append(_entry(
			region.capitalize(),
			{
				"where": CommandSchemaScript.DESTINATION_MOVEMENT_ROTATE,
				"movement_region": region
			},
			section
		))

	return entries


static func _get_compact_movement_rows(section: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	for region_value in MovementSlotResolverScript.REGION_ORDER:
		var region := String(region_value)

		var range_entries: Array[Dictionary] = []

		for range_value in MovementSlotResolverScript.RANGE_ORDER:
			var range_name := String(range_value)
			range_entries.append(_entry(
				range_name.capitalize(),
				{
					"where": CommandSchemaScript.DESTINATION_MOVEMENT_SLOT,
					"movement_region": region,
					"movement_range": range_name
				},
				section,
				{
					"selection_label": "%s - %s" % [
						region.capitalize(),
						range_name.capitalize()
					]
				}
			))

		entries.append(_entry(
			region.capitalize(),
			{},
			section,
			{
				"compact_range_row": true,
				"range_entries": range_entries
			}
		))

	return entries


static func _get_healing_entries(
	party_members: Array,
	game_state: Node,
	section: String
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	entries.append(_entry("Select Heal Target", {"where": "none"}, section))
	entries.append(_entry(
		"The Active Tank",
		{
			"where": CommandSchemaScript.DESTINATION_HEALING_SCOPE,
			"healing_scope": {"type": CommandSchemaScript.HEAL_SCOPE_ACTIVE_TANK}
		},
		section
	))
	entries.append(_entry(
		"The Raid",
		{
			"where": CommandSchemaScript.DESTINATION_HEALING_SCOPE,
			"healing_scope": {"type": CommandSchemaScript.HEAL_SCOPE_RAID}
		},
		section
	))

	for unit_class_value in _get_available_classes(game_state):
		var unit_class := String(unit_class_value)
		entries.append(_entry(
			"Class: " + unit_class,
			{
				"where": CommandSchemaScript.DESTINATION_HEALING_SCOPE,
				"healing_scope": {
					"type": CommandSchemaScript.SELECTOR_CLASS,
					"value": unit_class
				}
			},
			section
		))

	var group_count := ceili(float(GameStateScript.MAX_RAID_SIZE) / 5.0)

	for group_number in range(1, group_count + 1):
		entries.append(_entry(
			"Group " + str(group_number),
			{
				"where": CommandSchemaScript.DESTINATION_HEALING_SCOPE,
				"healing_scope": {
					"type": CommandSchemaScript.SELECTOR_GROUP,
					"value": group_number
				}
			},
			section
		))

	for unit_value in party_members:
		var unit := unit_value as Node

		if unit == null or not is_instance_valid(unit):
			continue

		var unit_label := get_unit_display_name(unit)
		var canonical_label := get_unit_canonical_name(unit)
		entries.append(_entry(
			unit_label,
			{
				"where": CommandSchemaScript.DESTINATION_HEALING_SCOPE,
				"healing_scope": {
					"type": CommandSchemaScript.SELECTOR_UNIT,
					"value": canonical_label,
					"unit": unit
				}
			},
			section,
			{
				"icon": CLASS_ICONS.get(_get_unit_class(unit)),
				"tooltip": _get_unit_tooltip(unit, canonical_label)
			}
		))

	return entries


static func _healing_scope_label(scope: Dictionary) -> String:
	match String(scope.get("type", "")):
		CommandSchemaScript.HEAL_SCOPE_ACTIVE_TANK:
			return "The Active Tank"
		CommandSchemaScript.HEAL_SCOPE_RAID:
			return "The Raid"
		CommandSchemaScript.SELECTOR_CLASS:
			return String(scope.get("value", "")).capitalize() + " Class"
		CommandSchemaScript.SELECTOR_GROUP:
			return "Group " + str(int(scope.get("value", 0)))
		CommandSchemaScript.SELECTOR_UNIT_IDENTITY:
			return (
				String(scope.get("class", ""))
				+ " "
				+ str(int(scope.get("number", 0)))
			)
		CommandSchemaScript.SELECTOR_UNIT:
			return String(scope.get("value", "Healing Target"))

	return String(scope.get("value", "Healing Target"))


static func _get_available_classes(game_state: Node) -> Array:
	if game_state == null or not game_state.has_method("get_available_classes"):
		return []

	return game_state.get_available_classes()


static func _get_role_options(game_state: Node) -> Array:
	if game_state == null or not game_state.has_method("get_role_options"):
		return []

	return game_state.get_role_options()


static func _get_unit_class(unit: Node) -> String:
	if unit == null or not is_instance_valid(unit):
		return ""

	var class_value = unit.get("unit_class")
	return String(class_value) if class_value != null else ""


static func _get_unit_tooltip(unit: Node, canonical_label: String) -> String:
	var roles: Array[String] = []

	if unit != null and is_instance_valid(unit) and unit.has_method("get_roles"):
		for role_value in unit.get_roles():
			roles.append(String(role_value).capitalize())

	var lines: Array[String] = [canonical_label, "Class: " + _get_unit_class(unit)]

	if not roles.is_empty():
		lines.append("Roles: " + ", ".join(roles))

	return "\n".join(lines)


static func _get_units_for_who_metadata(
	party_members: Array,
	metadata: Dictionary
) -> Array:
	var result: Array = []
	var who_type := String(metadata.get("who_type", ""))
	var who_value = metadata.get("who_value", "")

	for unit_value in party_members:
		var unit := unit_value as Node

		if unit == null or not is_instance_valid(unit):
			continue

		match who_type:
			CommandSchemaScript.SELECTOR_EVERYONE:
				result.append(unit)
			CommandSchemaScript.SELECTOR_CLASS:
				if _get_unit_class(unit) == String(who_value):
					result.append(unit)
			CommandSchemaScript.SELECTOR_ROLE:
				var match_role := String(metadata.get("match_role", who_value))

				if unit.has_method("has_role") and bool(unit.has_role(match_role)):
					result.append(unit)
			CommandSchemaScript.SELECTOR_GROUP:
				var unit_index := party_members.find(unit)
				var first_index := (int(who_value) - 1) * 5

				if unit_index >= first_index and unit_index < first_index + 5:
					result.append(unit)
			CommandSchemaScript.SELECTOR_UNIT:
				if metadata.get("unit", null) == unit:
					result.append(unit)

	if who_type == CommandSchemaScript.SELECTOR_ROLE:
		var selection := String(metadata.get("selection", "all"))

		if selection == "first" and result.size() > 1:
			return [result[0]]

		if selection == "second":
			return [result[1]] if result.size() > 1 else []

	return result


static func _any_unit_supports_action(units: Array, action: String) -> bool:
	if units.is_empty():
		return false

	var method_by_action := {
		CommandSchemaScript.ACTION_ATTACK: "command_attack",
		CommandSchemaScript.ACTION_MOVE: "command_move_to_position",
		CommandSchemaScript.ACTION_DODGE: "command_dodge_to_position",
		CommandSchemaScript.ACTION_ROTATE: "command_move_to_position",
		CommandSchemaScript.ACTION_INTERRUPT: "command_interrupt",
		CommandSchemaScript.ACTION_HEAL: "command_heal_scope",
		CommandSchemaScript.ACTION_CURE: "command_cure",
		CommandSchemaScript.ACTION_TAUNT: "command_taunt"
	}
	var required_method := String(method_by_action.get(action, ""))

	for unit_value in units:
		if unit_value is Node and (unit_value as Node).has_method(required_method):
			return true

	return false


static func _group_entries_by_section(entries: Array[Dictionary]) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	var section_indices: Dictionary = {}

	for entry in entries:
		var section_name := String(entry.get("section", "Options"))

		if not section_indices.has(section_name):
			section_indices[section_name] = sections.size()
			sections.append({"heading": section_name, "entries": []})

		var section_index := int(section_indices[section_name])
		var section_entries: Array = sections[section_index].get("entries", [])
		section_entries.append(entry)
		sections[section_index]["entries"] = section_entries

	return sections


static func _entry(
	label: String,
	metadata: Dictionary,
	section: String,
	extra: Dictionary = {}
) -> Dictionary:
	var entry := {
		"label": label,
		"metadata": metadata,
		"section": section
	}

	for key in extra.keys():
		entry[key] = extra[key]

	return entry
