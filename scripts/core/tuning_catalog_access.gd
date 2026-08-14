extends RefCounted
class_name TuningCatalogAccess

const CATALOG_PATH := "res://data/tuning/catalog.tres"

static var _catalog: TuningCatalogResource
static var _validation_errors := PackedStringArray()


static func get_raid_campaign() -> RaidCampaignTuning:
	_require_valid_catalog()
	return _catalog.raid_campaign


static func get_combat() -> CombatTuning:
	_require_valid_catalog()
	return _catalog.combat


static func get_dodge() -> DodgeTuningResource:
	_require_valid_catalog()
	return _catalog.dodge


static func get_camp() -> CampTuning:
	_require_valid_catalog()
	return _catalog.camp


static func get_voice() -> VoiceTuning:
	_require_valid_catalog()
	return _catalog.voice


static func get_runtime_limits() -> RuntimeLimitsTuning:
	_require_valid_catalog()
	return _catalog.runtime_limits


static func get_validation_errors() -> PackedStringArray:
	_load_once()
	return _validation_errors.duplicate()


static func is_valid() -> bool:
	return get_validation_errors().is_empty()


static func _load_once() -> void:
	if _catalog != null or not _validation_errors.is_empty():
		return
	var loaded := ResourceLoader.load(CATALOG_PATH, "TuningCatalogResource")
	if not loaded is TuningCatalogResource:
		_validation_errors.append(
			"Tuning catalog is missing or is not a TuningCatalogResource: %s" % CATALOG_PATH
		)
	else:
		_catalog = loaded as TuningCatalogResource
		_validation_errors = _catalog.get_validation_errors()
	if not _validation_errors.is_empty():
		for validation_error in _validation_errors:
			push_error("Invalid tuning catalog: %s" % validation_error)


static func _require_valid_catalog() -> void:
	_load_once()
	assert(_catalog != null, "Tuning catalog could not be loaded from %s." % CATALOG_PATH)
	assert(
		_validation_errors.is_empty(),
		"Tuning catalog is invalid: %s" % "; ".join(_validation_errors)
	)
