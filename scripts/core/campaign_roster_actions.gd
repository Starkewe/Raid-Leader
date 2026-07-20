extends RefCounted
class_name CampaignRosterActions


static func add_active_member(member_id: String) -> bool:
	var active_ids := CampaignState.get_active_member_ids()

	if member_id.is_empty() or active_ids.has(member_id):
		return false

	if active_ids.size() >= CampaignState.ACTIVE_RAID_SIZE:
		return false

	if CampaignState.get_member(member_id).is_empty():
		return false

	active_ids.append(member_id)
	CampaignState.campaign["raid_plan"]["active_member_ids"] = active_ids
	_sanitize_formations()
	_commit_change()
	return true


static func remove_active_member(member_id: String) -> bool:
	var active_ids := CampaignState.get_active_member_ids()

	if active_ids.size() <= 1 or not active_ids.has(member_id):
		return false

	active_ids.erase(member_id)
	CampaignState.campaign["raid_plan"]["active_member_ids"] = active_ids
	_sanitize_formations()
	_commit_change()
	return true


static func _sanitize_formations() -> void:
	CampaignState._ensure_formation()
	var raid_plan: Dictionary = CampaignState.campaign.get("raid_plan", {})
	var saved_value: Variant = raid_plan.get("saved_formations", {})
	var saved_formations: Dictionary = (
		Dictionary(saved_value).duplicate(true) if saved_value is Dictionary else {}
	)

	for formation_name in saved_formations.keys():
		var formation_value: Variant = saved_formations[formation_name]

		if formation_value is Dictionary:
			saved_formations[formation_name] = CampaignState._sanitize_formation_for_active(
				Dictionary(formation_value)
			)

	raid_plan["saved_formations"] = saved_formations
	CampaignState.campaign["raid_plan"] = raid_plan


static func _commit_change() -> void:
	CampaignState._augment_visit_reactions("roster_change", 1)
	CampaignState.save_campaign()
	CampaignState.roster_changed.emit()
	CampaignState.raid_plan_changed.emit()
	CampaignState.state_changed.emit()
