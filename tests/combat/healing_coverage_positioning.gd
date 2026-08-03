extends Node


class CoverageBoss:
	extends Node2D

	var combat_radius := 128.0
	var party_members: Array = []
	var encounter_objects: Array[Node] = []
	var current_target: Node2D = null
	var coordinator := HealingCoverageCoordinator.new()

	func get_combat_radius() -> float:
		return combat_radius

	func get_current_target() -> Node2D:
		return current_target

	func get_healing_coverage_anchor(healer: Node2D) -> Dictionary:
		return coordinator.get_anchor_for_healer(self, healer)

	func get_mini_region_for_position(position: Vector2) -> Dictionary:
		return MovementSlotResolver.get_mini_region_from_position(self, position)


var root: Window = null
var boss: CoverageBoss = null
var owned_nodes: Array[Node] = []


func _ready() -> void:
	root = get_tree().root
	call_deferred("_run")


func _run() -> void:
	boss = CoverageBoss.new()
	root.add_child(boss)
	owned_nodes.append(boss)

	if not _test_healthy_direct_and_active_tank_prepositioning():
		return

	if not _test_broad_scope_distinct_stable_coverage():
		return

	print("Healing coverage positioning regressions passed.")
	get_tree().quit(0)


func _test_healthy_direct_and_active_tank_prepositioning() -> bool:
	var direct_target := _new_unit(
		MovementSlotResolver.get_slot_position(boss, "west", "far"),
		"Warrior",
		1
	)
	var direct_healer := _new_priest(
		MovementSlotResolver.get_slot_position(boss, "east", "far"),
		1
	)
	var direct_party: Array = [direct_healer, direct_target]
	var direct_selector := HealingTargetSelector.new()
	direct_selector.setup(direct_party, [boss])
	boss.party_members = direct_party

	if not direct_healer.command_heal_scope(
		{"type": "unit", "value": "Warrior 1", "unit": direct_target},
		direct_selector
	):
		return _fail("A healthy direct-unit healing assignment was rejected.")

	direct_healer._physics_process(0.016)

	if direct_healer.velocity.is_zero_approx() or direct_healer.heal_target != null:
		return _fail("A direct healer did not pre-position for its healthy assignment target.")

	var tank := _new_unit(
		MovementSlotResolver.get_slot_position(boss, "north", "far"),
		"Warrior",
		2
	)
	tank.unit_roles = ["tank"]
	var tank_healer := _new_priest(
		MovementSlotResolver.get_slot_position(boss, "south", "far"),
		2
	)
	var tank_party: Array = [tank_healer, tank]
	var tank_selector := HealingTargetSelector.new()
	boss.current_target = tank
	boss.party_members = tank_party
	tank_selector.setup(tank_party, [boss])

	if not tank_healer.command_heal_scope(
		{"type": "active_tank"},
		tank_selector
	):
		return _fail("A healthy active-tank healing assignment was rejected.")

	tank_healer._physics_process(0.016)

	if tank_healer.velocity.is_zero_approx() or tank_healer.heal_target != null:
		return _fail("An active-tank healer did not pre-position before damage arrived.")

	boss.current_target = null
	return true


func _test_broad_scope_distinct_stable_coverage() -> bool:
	_clear_hazards()
	var healers: Array = [
		_new_priest(MovementSlotResolver.get_slot_position(boss, "east", "far"), 3),
		_new_priest(MovementSlotResolver.get_slot_position(boss, "south", "far"), 4),
		_new_priest(MovementSlotResolver.get_slot_position(boss, "west", "far"), 5)
	]
	var raid: Array = healers.duplicate()
	var regions := ["north", "northeast", "southeast", "south", "southwest", "northwest"]
	var unit_index := 10

	for region_value in regions:
		raid.append(_new_unit(
			MovementSlotResolver.get_slot_position(
				boss,
				String(region_value),
				"far"
			),
			"Rogue",
			unit_index
		))
		unit_index += 1

	boss.party_members = raid
	var selector := HealingTargetSelector.new()
	selector.setup(raid, [boss])

	for healer in healers:
		if not healer.command_heal_scope({"type": "raid"}, selector):
			return _fail("A valid broad raid healing assignment was rejected.")

	var anchors: Array[Dictionary] = []
	var anchor_keys: Array[String] = []

	for healer in healers:
		var anchor: Dictionary = boss.get_healing_coverage_anchor(healer)

		if anchor.is_empty():
			return _fail("A broad-scope healer did not receive a coverage anchor.")

		anchors.append(anchor)
		anchor_keys.append(String(anchor.get("key", "")))

	var distinct_keys := anchor_keys.duplicate()
	distinct_keys.sort()
	var unique_keys: Array[String] = []

	for key in distinct_keys:
		if not unique_keys.has(key):
			unique_keys.append(key)

	if unique_keys.size() != healers.size():
		return _fail("Broad-scope healers shared a mini-region despite safe alternatives.")

	var covered: Dictionary = {}

	for healer_index in range(healers.size()):
		var healer: Priest = healers[healer_index]
		var anchor_position: Vector2 = anchors[healer_index]["position"]
		var range_pixels := CombatMeasurements.range_units_to_pixels(
			healer.cast_range_units
		)

		for unit in raid:
			if anchor_position.distance_to((unit as Node2D).global_position) <= range_pixels:
				covered[unit.get_instance_id()] = true

	if covered.size() < raid.size() - 1:
		return _fail("Coverage anchors left avoidable raid-wide healing gaps.")

	for healer_index in range(healers.size()):
		var stable := boss.get_healing_coverage_anchor(healers[healer_index])

		if (
			String(stable.get("key", "")) != String(anchors[healer_index].get("key", ""))
			or not (stable.get("position") as Vector2).is_equal_approx(
				anchors[healer_index]["position"]
			)
		):
			return _fail("A valid healer coverage anchor changed without a material event.")

	var blocked_anchor: Vector2 = anchors[0]["position"]
	_add_hazard(blocked_anchor, 110.0)
	var replanned := boss.get_healing_coverage_anchor(healers[0])
	var clearance: float = (healers[0] as Priest).mini_region_footprint_radius
	clearance += MovementSlotResolver.MINI_REGION_ENTRY_MARGIN_PIXELS

	if (
		replanned.is_empty()
		or not CombatAutoPositioner.is_position_safe(
			replanned["position"],
			boss,
			clearance,
			CombatAutoPositioner.get_active_avoidable_hazards(boss)
		)
	):
		return _fail("Healing coverage did not replan around a personal hazard.")

	var signature_before_death := boss.coordinator.last_material_signature
	(raid[raid.size() - 1] as BaseCombatUnit).die()
	boss.get_healing_coverage_anchor(healers[0])

	if boss.coordinator.last_material_signature == signature_before_death:
		return _fail("Healing coverage did not recompute after a raid death.")

	return true


func _new_priest(position: Vector2, number: int) -> Priest:
	var priest := Priest.new()
	root.add_child(priest)
	priest.set_process(false)
	priest.set_physics_process(false)
	priest.global_position = position
	priest.setup_unit_identity("Priest", number)
	priest.set_combat_facing_target(boss)
	owned_nodes.append(priest)
	return priest


func _new_unit(position: Vector2, unit_class: String, number: int) -> BaseCombatUnit:
	var unit := BaseCombatUnit.new()
	root.add_child(unit)
	unit.set_process(false)
	unit.set_physics_process(false)
	unit.global_position = position
	unit.setup_unit_identity(unit_class, number)
	owned_nodes.append(unit)
	return unit


func _add_hazard(position: Vector2, radius: float) -> void:
	var definition := HazardDefinition.new()
	definition.duration = 0.0
	definition.show_visual = false
	definition.affected_radius = radius
	definition.reaction_owner = "raider_personal"
	definition.automatic_response = "avoid_area"
	var hazard := CombatHazard.new()
	boss.add_child(hazard)
	hazard.global_position = position
	hazard.configure(definition, boss, [])
	boss.encounter_objects.append(hazard)
	owned_nodes.append(hazard)


func _clear_hazards() -> void:
	for encounter_object in boss.encounter_objects:
		if encounter_object != null and is_instance_valid(encounter_object):
			encounter_object.queue_free()

	boss.encounter_objects.clear()


func _fail(message: String) -> bool:
	push_error(message)
	get_tree().quit(1)
	return false
