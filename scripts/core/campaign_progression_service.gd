extends RefCounted
class_name CampaignProgressionService


func get_attempt_history(
	campaign: Dictionary, encounter_id: String, maximum_entries: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var stored: Array = campaign.get("attempt_history", {}).get(encounter_id, [])
	for value in stored.slice(maxi(stored.size() - maximum_entries, 0)):
		if value is Dictionary:
			result.append(Dictionary(value).duplicate(true))
	return result


func get_victory_count(campaign: Dictionary, encounter_id: String) -> int:
	return int(campaign.get("victories", {}).get(encounter_id, 0))
