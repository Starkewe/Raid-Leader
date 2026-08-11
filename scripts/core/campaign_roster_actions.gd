extends RefCounted
class_name CampaignRosterActions


static func add_active_member(member_id: String) -> bool:
	return CampaignState.add_active_member(member_id)


static func remove_active_member(member_id: String) -> bool:
	return CampaignState.remove_active_member(member_id)
