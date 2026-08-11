extends RefCounted
class_name CampaignRaidPlanService


func get_plan(campaign: Dictionary) -> Dictionary:
	return Dictionary(campaign.get("raid_plan", {})).duplicate(true)


func set_encounter(campaign: Dictionary, encounter_id: String) -> void:
	campaign["raid_plan"]["encounter_id"] = encounter_id


func get_encounter(campaign: Dictionary, default_id: String) -> String:
	return String(campaign.get("raid_plan", {}).get("encounter_id", default_id))
