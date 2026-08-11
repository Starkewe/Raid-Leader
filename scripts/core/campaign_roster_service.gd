extends RefCounted
class_name CampaignRosterService


static func format_member_label(member: Dictionary) -> String:
	var member_name := String(member.get("display_name", "Unknown")).strip_edges()
	var unit_class := String(member.get("unit_class", "")).strip_edges()
	if unit_class.is_empty():
		return member_name
	var class_suffix := " (%s)" % unit_class
	return member_name if member_name.ends_with(class_suffix) else member_name + class_suffix


func add_active_member(
	campaign: Dictionary, member_id: String, valid_member_ids: Array[String], maximum: int
) -> bool:
	var active_ids: Array = campaign.get("raid_plan", {}).get("active_member_ids", [])
	if member_id.is_empty() or active_ids.has(member_id):
		return false
	if active_ids.size() >= maximum or not valid_member_ids.has(member_id):
		return false
	active_ids.append(member_id)
	campaign["raid_plan"]["active_member_ids"] = active_ids
	return true


func remove_active_member(campaign: Dictionary, member_id: String) -> bool:
	var active_ids: Array = campaign.get("raid_plan", {}).get("active_member_ids", [])
	if active_ids.size() <= 1 or not active_ids.has(member_id):
		return false
	active_ids.erase(member_id)
	campaign["raid_plan"]["active_member_ids"] = active_ids
	return true
