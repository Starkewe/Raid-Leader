extends Node

func _enter_tree() -> void:
	TuningCatalogAccess.get_validation_errors()


func get_raid_campaign() -> RaidCampaignTuning:
	return TuningCatalogAccess.get_raid_campaign()


func get_combat() -> CombatTuning:
	return TuningCatalogAccess.get_combat()


func get_dodge() -> DodgeTuningResource:
	return TuningCatalogAccess.get_dodge()


func get_camp() -> CampTuning:
	return TuningCatalogAccess.get_camp()


func get_voice() -> VoiceTuning:
	return TuningCatalogAccess.get_voice()


func get_runtime_limits() -> RuntimeLimitsTuning:
	return TuningCatalogAccess.get_runtime_limits()


func get_validation_errors() -> PackedStringArray:
	return TuningCatalogAccess.get_validation_errors()


func is_valid() -> bool:
	return TuningCatalogAccess.is_valid()
