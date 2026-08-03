extends Node


class DummyBoss:
	extends Node2D

	var combat_radius: float = 128.0
	var encounter_objects: Array[Node] = []

	func get_combat_radius() -> float:
		return combat_radius

	func get_mini_region_for_position(position: Vector2) -> Dictionary:
		return MovementSlotResolver.get_mini_region_from_position(self, position)


class CountingAutoPositioner:
	extends CombatAutoPositioner

	var escape_plan_build_count: int = 0

	func _create_ground_hazard_escape_plan(
		unit: Node2D,
		boss_node: Node,
		clearance_pixels: float,
		hazards: Array,
		overlapping_hazards: Array,
		hazard_signature: String
	) -> Dictionary:
		escape_plan_build_count += 1
		return super._create_ground_hazard_escape_plan(
			unit,
			boss_node,
			clearance_pixels,
			hazards,
			overlapping_hazards,
			hazard_signature
		)


const CLEARANCE := 12.0 + MovementSlotResolver.MINI_REGION_ENTRY_MARGIN_PIXELS

var boss: DummyBoss = null
var owned_nodes: Array[Node] = []
var root: Window = null


func _ready() -> void:
	root = get_tree().root
	call_deferred("_run")


func _run() -> void:
	boss = DummyBoss.new()
	root.add_child(boss)
	owned_nodes.append(boss)

	if not _test_real_radius_and_all_role_escape():
		return

	if not _test_manual_priority_releases_on_arrival():
		return

	if not _test_safe_route_segments_and_overlap_escape():
		return

	if not _test_forced_movement_builds_one_cached_escape():
		return

	if not _test_cached_escape_replans_only_when_invalid():
		return

	if not _test_raid_forced_movement_searches_scale_per_raider():
		return

	if not _test_support_uses_safe_action_position():
		return

	if not _test_rogue_single_charge_escape():
		return

	if not _test_hazard_expiration_releases_constraint():
		return

	print("Automatic hazard positioning regressions passed.")
	get_tree().quit(0)


func _test_real_radius_and_all_role_escape() -> bool:
	_clear_hazards()
	var center := MovementSlotResolver.get_slot_position(boss, "north", "far")
	_add_coordinated_hazard(center)
	var coordinated := _new_mage(center)
	coordinated._physics_process(0.016)

	if not coordinated.velocity.is_zero_approx():
		return _fail("A player-coordinated hazard silently gained automatic avoidance.")

	_clear_hazards()
	_add_hazard(center, 72.0)

	var safe_same_region := _new_mage(center + Vector2.RIGHT * 100.0)
	safe_same_region._physics_process(0.016)

	if not safe_same_region.velocity.is_zero_approx():
		return _fail("A raider outside the expanded real hazard radius fled its mini-region.")

	var inside := _new_mage(center + Vector2.RIGHT * 80.0)
	inside._physics_process(0.016)

	if inside.velocity.is_zero_approx():
		return _fail("A raider overlapping the expanded hazard radius did not escape.")

	var tank := _new_mage(center)
	tank.unit_roles = ["tank"]
	tank._physics_process(0.016)

	if tank.velocity.is_zero_approx() or not tank.automatic_hazard_escape_active:
		return _fail("A tank did not use generic personal-hazard initiative.")

	return true


func _test_manual_priority_releases_on_arrival() -> bool:
	_clear_hazards()
	var center := MovementSlotResolver.get_slot_position(boss, "north", "far")
	_add_hazard(center)
	var mage := _new_mage(center)
	var explicit_destination := center + Vector2.RIGHT * 400.0
	mage.command_move_to_position(explicit_destination)
	mage._physics_process(0.016)

	if mage.velocity.normalized().dot(center.direction_to(explicit_destination)) < 0.999:
		return _fail("Personal avoidance overrode an active player movement path.")

	mage.global_position = explicit_destination
	mage._physics_process(0.016)

	if mage.has_manual_move_order:
		return _fail("Ordinary movement retained a hidden hold after arrival.")

	var arrival_in_hazard := _new_mage(center)
	arrival_in_hazard.command_move_to_position(center)
	arrival_in_hazard._physics_process(0.016)

	if arrival_in_hazard.velocity.is_zero_approx():
		return _fail("Personal avoidance did not resume when an ordinary move completed.")

	return true


func _test_safe_route_segments_and_overlap_escape() -> bool:
	_clear_hazards()
	var source := MovementSlotResolver.get_slot_position(boss, "north", "far")
	var target := MovementSlotResolver.get_slot_position(boss, "south", "mid")
	var midpoint := source.lerp(target, 0.5)
	_add_hazard(midpoint, 150.0)
	var hazards := CombatAutoPositioner.get_active_avoidable_hazards(boss)
	var route := CombatAutoPositioner.build_safe_route_to_position(
		boss,
		source,
		target,
		CLEARANCE,
		hazards
	)

	if not bool(route.get("found", false)):
		return _fail("Multi-step routing did not find a path around a personal hazard.")

	var previous := source

	for waypoint_value in route.get("waypoints", []):
		var waypoint := waypoint_value as Vector2

		if not CombatAutoPositioner.is_route_segment_safe(
			previous,
			waypoint,
			boss,
			CLEARANCE,
			hazards
		):
			return _fail("An automatic route segment intersected an avoidable hazard.")

		previous = waypoint

	_clear_hazards()
	var overlap_center := MovementSlotResolver.get_slot_position(boss, "east", "mid")
	_add_hazard(overlap_center + Vector2.LEFT * 35.0, 90.0)
	_add_hazard(overlap_center + Vector2.RIGHT * 35.0, 90.0)
	var unit := _new_mage(overlap_center)
	var escape := unit.combat_auto_positioner.get_ground_hazard_escape_step(
		unit,
		boss,
		CLEARANCE
	)

	if not bool(escape.get("handled", false)):
		return _fail("Overlapping personal hazards produced no safe escape route.")

	var destination_value: Variant = escape.get("destination", null)

	if not destination_value is Vector2:
		return _fail("Overlapping-hazard escape did not provide a destination.")

	return true


func _test_forced_movement_builds_one_cached_escape() -> bool:
	_clear_hazards()
	var center := MovementSlotResolver.get_slot_position(boss, "north", "far")
	_add_hazard(center, 72.0)
	var mage := _new_mage(center + Vector2.RIGHT * 300.0)
	var positioner := _install_counting_positioner(mage)
	mage.start_forced_movement(center, 0.04)
	mage._physics_process(0.02)

	if positioner.escape_plan_build_count != 0:
		return _fail("Hazard routing ran while forced movement was active.")

	mage._physics_process(0.02)

	if mage.is_forced_moving():
		return _fail("Forced movement did not finish at its authored duration.")

	if positioner.escape_plan_build_count != 0:
		return _fail("Hazard routing ran on the forced-movement completion frame.")

	mage._physics_process(0.016)

	if positioner.escape_plan_build_count != 1:
		return _fail("The first post-forced-movement hazard check did not build one route.")

	if positioner.escape_transition.is_empty():
		return _fail("The post-forced-movement escape route was not cached.")

	for frame in range(8):
		mage._physics_process(0.016)

	if positioner.escape_plan_build_count != 1:
		return _fail("A cached post-forced-movement escape was rebuilt every frame.")

	return true


func _test_cached_escape_replans_only_when_invalid() -> bool:
	_clear_hazards()
	var center := MovementSlotResolver.get_slot_position(boss, "east", "mid")
	_add_hazard(center, 72.0)
	var mage := _new_mage(center)
	var positioner := _install_counting_positioner(mage)
	var first_step := positioner.get_ground_hazard_escape_step(mage, boss, CLEARANCE)

	if (
		positioner.escape_plan_build_count != 1
		or not bool(first_step.get("handled", false))
	):
		return _fail("Initial hazard overlap did not create one cached escape plan.")

	_add_hazard(center + Vector2(3000.0, 3000.0), 16.0)
	positioner.get_ground_hazard_escape_step(mage, boss, CLEARANCE)

	if positioner.escape_plan_build_count != 1:
		return _fail("An unrelated hazard caused a valid cached route to be rebuilt.")

	var destination_value: Variant = positioner.escape_transition.get(
		"destination",
		null
	)

	if not destination_value is Vector2:
		return _fail("The cached route did not retain its current destination.")

	_add_hazard(mage.global_position.lerp(destination_value, 0.5), 8.0)
	positioner.get_ground_hazard_escape_step(mage, boss, CLEARANCE)

	if positioner.escape_plan_build_count != 2:
		return _fail("A hazard blocking the cached segment did not cause exactly one replan.")

	positioner.get_ground_hazard_escape_step(mage, boss, CLEARANCE)

	if positioner.escape_plan_build_count != 2:
		return _fail("The replacement escape route was rebuilt without invalidation.")

	return true


func _test_raid_forced_movement_searches_scale_per_raider() -> bool:
	_clear_hazards()
	var center := MovementSlotResolver.get_slot_position(boss, "south", "mid")
	_add_hazard(center, 72.0)
	var mages: Array[Mage] = []
	var positioners: Array[CountingAutoPositioner] = []
	var raider_count := 20

	for raider_index in range(raider_count):
		var angle := TAU * float(raider_index) / float(raider_count)
		var mage := _new_mage(center + Vector2.from_angle(angle) * 300.0)
		var positioner := _install_counting_positioner(mage)
		mages.append(mage)
		positioners.append(positioner)
		mage.start_forced_movement(center, 0.01)
		mage._physics_process(0.02)

	for positioner in positioners:
		if positioner.escape_plan_build_count != 0:
			return _fail("Raid-wide forced movement searched before displacement finished.")

	for mage in mages:
		mage._physics_process(0.016)

	for frame in range(5):
		for mage in mages:
			mage._physics_process(0.016)

	for positioner in positioners:
		if positioner.escape_plan_build_count != 1:
			return _fail("Raid hazard searches scaled with frames instead of raiders.")

	return true


func _test_support_uses_safe_action_position() -> bool:
	_clear_hazards()
	var target_position := MovementSlotResolver.get_slot_position(boss, "west", "mid")
	_add_hazard(target_position, 120.0)
	var source := MovementSlotResolver.get_slot_position(boss, "east", "far")
	var target := _new_target(target_position)
	var priest := _new_priest(source)

	if not priest.command_heal(target):
		return _fail("Priest rejected the support-routing test target.")

	priest._physics_process(0.016)

	if priest.velocity.is_zero_approx():
		return _fail("Healer waited despite an available safe in-range position.")

	var destination_value: Variant = priest.combat_auto_positioner.support_transition.get(
		"destination",
		null
	)

	if not destination_value is Vector2:
		return _fail("Healer support routing did not retain a safe route step.")

	if not CombatAutoPositioner.is_position_safe(
		destination_value,
		boss,
		CLEARANCE,
		CombatAutoPositioner.get_active_avoidable_hazards(boss)
	):
		return _fail("Healer routed into the avoidable area around its target.")

	_clear_hazards()
	_add_hazard(target_position, 600.0)
	var no_safe_step := priest.combat_auto_positioner.get_support_movement_step(
		priest,
		boss,
		target,
		CLEARANCE,
		200.0
	)

	if not bool(no_safe_step.get("wait_safe", false)):
		return _fail("A healer entered a hazard when no safe action position existed.")

	return true


func _test_rogue_single_charge_escape() -> bool:
	_clear_hazards()
	var center := MovementSlotResolver.get_slot_position(boss, "south", "far")
	_add_hazard(center)
	var rogue := _new_rogue(center)
	var full_charges := rogue.dodge_available_charges
	rogue._physics_process(0.016)

	if full_charges != 2 or rogue.dodge_available_charges != full_charges - 1:
		return _fail("A full-charge Rogue did not spend exactly one automatic escape charge.")

	if not rogue.is_automatic_hazard_dodge_active() or rogue.dodge_pending_second_burst:
		return _fail("Rogue automatic escape did not remain a single-burst dodge.")

	rogue.update_active_dodge(rogue.dodge_duration)
	rogue.global_position = center
	rogue._physics_process(0.016)

	if rogue.dodge_active or rogue.dodge_available_charges != full_charges - 1:
		return _fail("A below-full Rogue spent a second automatic dodge charge.")

	return true


func _test_hazard_expiration_releases_constraint() -> bool:
	_clear_hazards()
	var source := MovementSlotResolver.get_slot_position(boss, "north", "far")
	var target := MovementSlotResolver.get_slot_position(boss, "south", "far")
	var hazard := _add_hazard(source.lerp(target, 0.5), 140.0)
	var constrained := CombatAutoPositioner.build_safe_route_to_position(
		boss,
		source,
		target,
		CLEARANCE
	)
	hazard.cleaned_up = true
	var released := CombatAutoPositioner.build_safe_route_to_position(
		boss,
		source,
		target,
		CLEARANCE
	)

	if not bool(constrained.get("found", false)) or not bool(released.get("found", false)):
		return _fail("Hazard expiration route setup failed.")

	if released.get("waypoints", []).size() != 1:
		return _fail("An expired hazard remained an active routing constraint.")

	_clear_hazards()
	var escape_hazard := _add_hazard(source, 72.0)
	var unit := _new_mage(source)
	var positioner := _install_counting_positioner(unit)
	positioner.get_ground_hazard_escape_step(unit, boss, CLEARANCE)
	escape_hazard.cleaned_up = true
	var released_escape := positioner.get_ground_hazard_escape_step(
		unit,
		boss,
		CLEARANCE
	)

	if (
		bool(released_escape.get("hazard_active", true))
		or not positioner.escape_transition.is_empty()
	):
		return _fail("Hazard expiration did not clear the cached escape plan.")

	return true


func _new_priest(position: Vector2) -> Priest:
	var priest := Priest.new()
	root.add_child(priest)
	priest.set_process(false)
	priest.set_physics_process(false)
	priest.global_position = position
	priest.set_combat_facing_target(boss)
	owned_nodes.append(priest)
	return priest


func _new_mage(position: Vector2) -> Mage:
	var mage := Mage.new()
	root.add_child(mage)
	mage.set_process(false)
	mage.set_physics_process(false)
	mage.global_position = position
	mage.set_combat_facing_target(boss)
	owned_nodes.append(mage)
	return mage


func _install_counting_positioner(unit: BaseCombatUnit) -> CountingAutoPositioner:
	var positioner := CountingAutoPositioner.new()
	unit.combat_auto_positioner = positioner
	return positioner


func _new_rogue(position: Vector2) -> Rogue:
	var rogue := Rogue.new()
	root.add_child(rogue)
	rogue.set_process(false)
	rogue.set_physics_process(false)
	rogue.global_position = position
	rogue.set_combat_facing_target(boss)
	rogue.dodge_base_class = "rogue"
	rogue.initialize_dodge_profile()
	owned_nodes.append(rogue)
	return rogue


func _new_target(position: Vector2) -> BaseCombatUnit:
	var target := BaseCombatUnit.new()
	root.add_child(target)
	target.set_process(false)
	target.set_physics_process(false)
	target.global_position = position
	target.health = 50
	owned_nodes.append(target)
	return target


func _add_hazard(position: Vector2, radius: float = 72.0) -> CombatHazard:
	var definition := HazardDefinition.new()
	definition.duration = 0.0
	definition.affected_radius = radius
	definition.show_visual = false
	definition.reaction_owner = "raider_personal"
	definition.automatic_response = "avoid_area"
	var hazard := CombatHazard.new()
	boss.add_child(hazard)
	hazard.global_position = position
	hazard.configure(definition, boss, [])
	boss.encounter_objects.append(hazard)
	owned_nodes.append(hazard)
	return hazard


func _add_coordinated_hazard(position: Vector2) -> void:
	var definition := HazardDefinition.new()
	definition.duration = 0.0
	definition.show_visual = false
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
