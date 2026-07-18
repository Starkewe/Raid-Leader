extends RefCounted
class_name BossAbilityFactory

const DirectionalRegionCleaveScript := preload("res://scripts/abilities/directional_region_cleave.gd")
const TwinSweepingPullScript := preload("res://scripts/abilities/twin_sweeping_pull.gd")

const CLOSE_CLEAVE_DEFINITION: BossAbilityDefinition = preload("res://data/abilities/close_region_cleave.tres")
const FULL_CONE_DEFINITION: BossAbilityDefinition = preload("res://data/abilities/full_region_cone.tres")
const TWIN_SWEEP_DEFINITION: BossAbilityDefinition = preload("res://data/abilities/twin_sweeping_pull.tres")

const ABILITY_TARGET_REGION_CLOSE_CLEAVE := "target_region_close_cleave"
const ABILITY_TARGET_REGION_FULL_CONE := "target_region_full_cone"
const ABILITY_TWIN_SWEEPING_PULL := "twin_sweeping_pull"


static func create_ability_from_id(ability_id: String) -> BossAbility:
	match ability_id:
		ABILITY_TARGET_REGION_CLOSE_CLEAVE:
			return create_ability_from_definition(CLOSE_CLEAVE_DEFINITION)

		ABILITY_TARGET_REGION_FULL_CONE:
			return create_ability_from_definition(FULL_CONE_DEFINITION)

		ABILITY_TWIN_SWEEPING_PULL:
			return create_ability_from_definition(TWIN_SWEEP_DEFINITION)

		_:
			print("Unknown boss ability id:", ability_id)
			return create_fallback_ability()


static func create_target_region_close_cleave() -> BossAbility:
	return create_ability_from_definition(CLOSE_CLEAVE_DEFINITION)


static func create_target_region_full_cone() -> BossAbility:
	return create_ability_from_definition(FULL_CONE_DEFINITION)


static func create_twin_sweeping_pull() -> BossAbility:
	return create_ability_from_definition(TWIN_SWEEP_DEFINITION)


static func create_fallback_ability() -> BossAbility:
	return create_target_region_close_cleave()


static func create_ability_from_definition(definition: BossAbilityDefinition) -> BossAbility:
	if definition == null:
		return null

	var ability: BossAbility = null

	if definition is TwinSweepingPullDefinition:
		ability = TwinSweepingPullScript.new()
	elif definition is DirectionalCleaveDefinition:
		ability = DirectionalRegionCleaveScript.new()

	if ability == null:
		push_warning("No runtime ability supports definition: " + definition.ability_id)
		return null

	ability.configure(definition)
	return ability
