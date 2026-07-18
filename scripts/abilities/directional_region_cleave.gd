extends BossAbility
class_name DirectionalRegionCleave

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

var target_region: String = MovementSlotResolverScript.REGION_NORTH
var locked_region: String = ""
var region_span_steps: int = 0

var affected_ranges: Array[String] = [
	MovementSlotResolverScript.RANGE_CLOSE
]


func _init() -> void:
	ability_id = "target_region_close_cleave"
	ability_name = "Northern Cleave"
	cast_time = 2.5
	cooldown = 6.0
	damage = 75

	windup_text = "Face me!"
	impact_text = "Cleave!"
	interruptible = true


func configure(definition: BossAbilityDefinition) -> void:
	super.configure(definition)

	if definition is DirectionalCleaveDefinition:
		var cleave_definition := definition as DirectionalCleaveDefinition
		region_span_steps = cleave_definition.region_span_steps
		affected_ranges = cleave_definition.affected_ranges.duplicate()

func on_cast_start(boss: Node, party_members: Array) -> void:
	locked_region = get_target_region_from_boss(boss)

	if locked_region != "":
		target_region = locked_region

	if windup_text != "":
		print(ability_name, "windup:", windup_text, "Locked region:", target_region)
func resolve(boss: Node, party_members: Array) -> void:
	if boss == null:
		return

	if not is_instance_valid(boss):
		return

	if not boss is Node2D:
		return

	var boss_2d := boss as Node2D
	var affected_regions := get_affected_regions()
	var hit_count: int = 0

	if boss.has_method("play_region_impact_effect"):
		boss.play_region_impact_effect(target_region, affected_ranges)

	if impact_text != "":
		print(ability_name, "impact:", impact_text)

	for unit in party_members:
		if not is_valid_living_damageable_unit(unit):
			continue

		if not unit is Node2D:
			continue

		var unit_2d := unit as Node2D

		var unit_region: String = MovementSlotResolverScript.get_nearest_region_from_position(
			boss_2d.global_position,
			unit_2d.global_position
		)

		var unit_range: String = MovementSlotResolverScript.get_nearest_range_from_position(
			boss,
			unit_2d.global_position
		)

		if not affected_regions.has(unit_region):
			continue

		if not affected_ranges.has(unit_range):
			continue

		unit.take_damage(damage, boss, ability_id)
		hit_count += 1

	print(
		ability_name,
		"hit",
		hit_count,
		"unit(s) in regions:",
		affected_regions,
		"and ranges:",
		affected_ranges
	)


func get_affected_regions() -> Array[String]:
	var affected_regions: Array[String] = []
	var region_order: Array = MovementSlotResolverScript.REGION_ORDER
	var center_index: int = region_order.find(target_region)

	if center_index == -1:
		affected_regions.append(target_region)
		return affected_regions

	var region_count: int = region_order.size()
	var span: int = maxi(region_span_steps, 0)

	for step in range(-span, span + 1):
		var region_index: int = (center_index + step + region_count) % region_count
		affected_regions.append(String(region_order[region_index]))

	return affected_regions


func is_valid_living_damageable_unit(unit: Node) -> bool:
	if unit == null:
		return false

	if not is_instance_valid(unit):
		return false

	if unit.has_method("is_alive"):
		if not unit.is_alive():
			return false

	if not unit.has_method("take_damage"):
		return false

	return true
func get_target_region_from_boss(boss: Node) -> String:
	if boss == null:
		return target_region

	if not is_instance_valid(boss):
		return target_region

	if not boss is Node2D:
		return target_region

	if not boss.has_method("get_current_target"):
		return target_region

	var current_target = boss.get_current_target()

	if current_target == null:
		return target_region

	if not is_instance_valid(current_target):
		return target_region

	if not current_target is Node2D:
		return target_region

	var boss_2d := boss as Node2D
	var target_2d := current_target as Node2D

	return MovementSlotResolverScript.get_nearest_region_from_position(
		boss_2d.global_position,
		target_2d.global_position
	)
func get_status_text() -> String:
	return "Casting " + get_cast_name()
func get_cast_name() -> String:
	return target_region.capitalize() + " Cleave"
