extends Resource
class_name TuningCatalogResource

@export var raid_campaign: RaidCampaignTuning
@export var combat: CombatTuning
@export var dodge: DodgeTuningResource
@export var camp: CampTuning
@export var voice: VoiceTuning
@export var runtime_limits: RuntimeLimitsTuning


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	_validate_domain(errors, "raid_campaign", raid_campaign)
	_validate_domain(errors, "combat", combat)
	_validate_domain(errors, "dodge", dodge)
	_validate_domain(errors, "camp", camp)
	_validate_domain(errors, "voice", voice)
	_validate_domain(errors, "runtime_limits", runtime_limits)
	return errors


func _validate_domain(errors: PackedStringArray, domain_name: String, domain: Resource) -> void:
	if domain == null:
		errors.append("%s tuning resource is missing." % domain_name)
		return
	for domain_error in domain.call("get_validation_errors"):
		errors.append("%s.%s" % [domain_name, domain_error])
