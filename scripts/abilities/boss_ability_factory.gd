extends RefCounted
class_name BossAbilityFactory

const DirectionalRegionCleaveScript := preload("res://scripts/abilities/directional_region_cleave.gd")

const ABILITY_TARGET_REGION_CLOSE_CLEAVE := "target_region_close_cleave"


static func create_ability_from_id(ability_id: String) -> BossAbility:
	match ability_id:
		ABILITY_TARGET_REGION_CLOSE_CLEAVE:
			return create_target_region_close_cleave()

		_:
			print("Unknown boss ability id:", ability_id)
			return create_fallback_ability()


static func create_target_region_close_cleave() -> BossAbility:
	var ability := DirectionalRegionCleaveScript.new()

	ability.region_span_steps = 0
	ability.affected_ranges = ["close"]

	return ability


static func create_fallback_ability() -> BossAbility:
	return create_target_region_close_cleave()
