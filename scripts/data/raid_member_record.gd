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
		"advanced_class_id": "",
		"specialization_id": "",
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
	member["advanced_class_id"] = String(member.get("advanced_class_id", ""))
	member["specialization_id"] = String(member.get("specialization_id", ""))
	member["source_id"] = String(member.get("source_id", "unknown"))
	member["debug_member"] = bool(member.get("debug_member", false))
	return member
