extends RefCounted
class_name RaidMemberRecord


static func create(
	member_id: String,
	display_name: String,
	unit_class: String,
	role: String,
	attributes: Array,
	description: String,
	recruit_order: int
) -> Dictionary:
	return {
		"member_id": member_id,
		"display_name": display_name,
		"unit_class": unit_class,
		"role": role,
		"attributes": attributes.duplicate(),
		"description": description,
		"recruit_order": recruit_order,
		"class_roles": [],
		"specialization_unlocked": false,
		"lineage_token_spent": false,
		"secondary_lineage_id": "",
		"advanced_class_id": "",
		"advanced_class_completed_id": "",
		"specialization_id": "",
		"lineage_progress_by_id": {},
		"source_id": "starting_writ",
		"debug_member": false
	}


static func sanitize(source: Dictionary) -> Dictionary:
	var member := source.duplicate(true)
	member["member_id"] = String(member.get("member_id", ""))
	member["display_name"] = String(member.get("display_name", "Unnamed"))
	member["unit_class"] = String(member.get("unit_class", "Mage"))
	member["role"] = String(member.get("role", "dps"))
	member["attributes"] = Array(member.get("attributes", []), TYPE_STRING, "", null)
	member["description"] = String(member.get("description", ""))
	member["recruit_order"] = int(member.get("recruit_order", 0))
	member["class_roles"] = _string_array(member.get("class_roles", []))
	member["specialization_unlocked"] = bool(
		member.get("specialization_unlocked", false)
	)
	member["lineage_token_spent"] = bool(
		member.get("lineage_token_spent", member["specialization_unlocked"])
	)
	member["secondary_lineage_id"] = String(member.get("secondary_lineage_id", ""))
	member["advanced_class_id"] = String(member.get("advanced_class_id", ""))
	member["advanced_class_completed_id"] = String(
		member.get("advanced_class_completed_id", "")
	)
	member["specialization_id"] = String(member.get("specialization_id", ""))
	var progress_value: Variant = member.get("lineage_progress_by_id", {})
	member["lineage_progress_by_id"] = (
		Dictionary(progress_value).duplicate(true) if progress_value is Dictionary else {}
	)
	member["source_id"] = String(member.get("source_id", "unknown"))
	member["debug_member"] = bool(member.get("debug_member", false))
	return member


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result
