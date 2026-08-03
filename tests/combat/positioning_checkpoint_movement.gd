extends Node

const BossScript := preload("res://scripts/units/boss.gd")
const OGRE_ENCOUNTER: EncounterDefinition = preload("res://data/encounters/ogre.tres")


class CheckpointBoss:
	extends Node2D

	var combat_radius := 128.0
	var encounter_objects: Array[Node] = []
	var checkpoint := {
		"token": 17,
		"ability_id": "test_mechanic",
		"ability_name": "Test Mechanic",
		"locked": false
	}

	func get_active_positioning_checkpoint() -> Dictionary:
		return checkpoint.duplicate(true)

	func is_positioning_checkpoint_active(token: int) -> bool:
		return not checkpoint.is_empty() and int(checkpoint.get("token", 0)) == token

	func get_combat_radius() -> float:
		return combat_radius

	func is_alive() -> bool:
		return true

	func take_damage(_amount: int, _source = null, _ability_id = "") -> void:
		pass


var root: Window = null
var owned_nodes: Array[Node] = []


func _ready() -> void:
	root = get_tree().root
	call_deferred("_run")


func _run() -> void:
	if not _test_layered_raider_movement_intent():
		return

	if not _test_empowered_slam_checkpoint_contract():
		return

	print("Positioning checkpoint movement regressions passed.")
	get_tree().quit(0)


func _test_layered_raider_movement_intent() -> bool:
	var boss := CheckpointBoss.new()
	root.add_child(boss)
	owned_nodes.append(boss)
	var destination := MovementSlotResolver.get_slot_position(boss, "north", "far")
	_add_personal_hazard(boss, destination)
	var mage := Mage.new()
	root.add_child(mage)
	mage.set_process(false)
	mage.set_physics_process(false)
	mage.global_position = destination
	mage.set_combat_facing_target(boss)
	owned_nodes.append(mage)
	var executor := MovementCommandExecutor.new()
	executor.setup(boss, null, Callable())
	executor.issue_position_command(
		mage,
		destination,
		executor.build_destination_context("north", "far")
	)
	mage._physics_process(0.016)

	if not mage.is_positioning_checkpoint_bound() or not mage.velocity.is_zero_approx():
		return _fail("A checkpoint-bound destination yielded to personal hazard initiative.")

	if mage.get_status_text() != "Positioning for Test Mechanic":
		return _fail("Checkpoint-bound status was not exposed through the unit status API.")

	mage.command_attack(boss)
	mage._physics_process(0.016)

	if not mage.is_positioning_checkpoint_bound() or not mage.is_casting:
		return _fail("A compatible combat command erased or blocked tactical positioning.")

	mage.cancel_current_cast()
	mage.start_forced_movement(destination + Vector2.RIGHT * 240.0, 0.1)
	mage.finish_forced_movement()
	mage._physics_process(0.016)

	if mage.velocity.normalized().dot(mage.global_position.direction_to(destination)) < 0.999:
		return _fail("A checkpoint-bound raider did not return after forced displacement.")

	mage.global_position = destination
	boss.checkpoint.clear()
	mage._physics_process(0.016)

	if mage.is_positioning_checkpoint_bound() or mage.velocity.is_zero_approx():
		return _fail("Personal avoidance did not resume immediately after checkpoint release.")

	boss.checkpoint = {
		"token": 18,
		"ability_id": "replacement",
		"ability_name": "Replacement",
		"locked": false
	}
	executor.issue_position_command(
		mage,
		destination,
		executor.build_destination_context("north", "far")
	)
	mage.command_move_to_position(destination + Vector2.RIGHT * 500.0)

	if mage.is_positioning_checkpoint_bound():
		return _fail("A newer ordinary movement command did not replace tactical intent.")

	return true


func _test_empowered_slam_checkpoint_contract() -> bool:
	var boss = BossScript.new()
	root.add_child(boss)
	boss.set_process(false)
	boss.set_physics_process(false)
	owned_nodes.append(boss)
	boss.basic_attack_triggered_ability_definition = (
		OGRE_ENCOUNTER.basic_attack_triggered_ability
	)
	boss.basic_attack_trigger_threshold = 5
	boss.current_phase = null
	boss.encounter_origin_position = Vector2.ZERO
	boss.global_position = Vector2.ZERO
	var tank := Warrior.new()
	root.add_child(tank)
	tank.set_process(false)
	tank.set_physics_process(false)
	tank.unit_roles = ["tank"]
	tank.global_position = MovementSlotResolver.get_slot_position(
		boss,
		"north",
		"close"
	)
	tank.set_combat_facing_target(boss)
	owned_nodes.append(tank)
	boss.set_party_members([tank])
	boss.set_target(tank)

	for _attack in range(5):
		boss.advance_basic_attack_trigger_sequence()

	var checkpoint := boss.get_active_positioning_checkpoint()

	if (
		checkpoint.is_empty()
		or String(checkpoint.get("ability_id", "")) != "empowered_slam"
	):
		return _fail("Empowered Slam did not open its planning window at 5/5.")

	if not boss.start_basic_attack_triggered_cast("charge_threshold"):
		return _fail("Empowered Slam failed to begin from its ready checkpoint.")

	if not boss.get_active_positioning_checkpoint().is_empty():
		return _fail("Empowered Slam retained its checkpoint after lane lock.")

	if String(boss.current_ability.get("locked_region")) != "north":
		return _fail("Empowered Slam did not lock the commanded tank lane at cast start.")

	boss.finish_special_cast()
	var first_line_count := int(
		boss.get_mechanic_state(
			EmpoweredSlam.FISSURE_LINE_STATE_KEY,
			{}
		).get("north", 0)
	)

	if first_line_count != 1:
		return _fail("The first Empowered Slam did not create its fissure line.")

	var health_after_first_slam := tank.health
	if health_after_first_slam != tank.max_health - 40:
		return _fail("Empowered Slam did not deal its configured 40 base damage.")

	if tank.get_status_effect_stacks("slam_vulnerability") != 1:
		return _fail("Empowered Slam did not apply its first Slam Vulnerability stack.")

	var close_hazard: Node = null
	for encounter_object in boss.encounter_objects:
		if (
			encounter_object != null
			and is_instance_valid(encounter_object)
			and encounter_object.has_method("contains_world_position")
			and String(encounter_object.get("coverage_range")) == "close"
		):
			close_hazard = encounter_object
			break

	if close_hazard == null:
		return _fail("Empowered Slam did not retain a close-range Cracked Ground hazard.")

	var north_direction := MovementSlotResolver.get_region_direction("north")
	var off_center_position := boss.global_position + north_direction * 360.0
	var adjacent_region_position := (
		boss.global_position + north_direction.rotated(PI / 4.0) * 360.0
	)

	if not close_hazard.contains_world_position(off_center_position):
		return _fail(
			"Cracked Ground did not cover the off-center portion of its mini-region."
		)

	if close_hazard.contains_world_position(adjacent_region_position):
		return _fail("Cracked Ground leaked into an adjacent mini-region.")

	var active_hazards := CombatAutoPositioner.get_active_avoidable_hazards(boss)
	if CombatAutoPositioner.is_position_safe(
		off_center_position,
		boss,
		0.0,
		active_hazards
	):
		return _fail("Automatic hazard avoidance ignored off-center Cracked Ground coverage.")

	for _attack in range(5):
		boss.advance_basic_attack_trigger_sequence()

	var executor := MovementCommandExecutor.new()
	executor.setup(boss, null, Callable())
	var fissure_position := MovementSlotResolver.get_slot_position(
		boss,
		"north",
		"close"
	)
	tank.global_position = fissure_position
	executor.issue_position_command(
		tank,
		fissure_position,
		executor.build_destination_context("north", "close")
	)
	tank._physics_process(0.016)

	if not tank.is_positioning_checkpoint_bound():
		return _fail("The tank did not obey a checkpoint command onto an existing fissure.")

	boss.start_basic_attack_triggered_cast("charge_threshold")
	tank._physics_process(0.016)

	if tank.is_positioning_checkpoint_bound() or tank.velocity.is_zero_approx():
		return _fail("The tank did not resume Cracked Ground avoidance after lane lock.")

	boss.finish_special_cast()

	if int(boss.get_mechanic_state(
		EmpoweredSlam.FISSURE_LINE_STATE_KEY,
		{}
	).get("north", 0)) != 2:
		return _fail("Repeated Empowered Slam fissures did not stack in one lane.")

	if tank.health != health_after_first_slam - 42:
		return _fail("Slam Vulnerability did not increase the repeated Empowered Slam damage.")

	if tank.get_status_effect_stacks("slam_vulnerability") != 2:
		return _fail("Repeated Empowered Slam did not stack Slam Vulnerability.")

	for _attack in range(5):
		boss.advance_basic_attack_trigger_sequence()

	boss.set_encounter_active(false)

	if not boss.get_active_positioning_checkpoint().is_empty():
		return _fail("Encounter cancellation did not clear the open checkpoint.")

	for _attack in range(5):
		boss.advance_basic_attack_trigger_sequence()

	boss.reset_boss(Vector2.ZERO)

	if not boss.get_active_positioning_checkpoint().is_empty():
		return _fail("Boss reset did not clear the open checkpoint.")

	for _attack in range(5):
		boss.advance_basic_attack_trigger_sequence()

	boss.die()

	if not boss.get_active_positioning_checkpoint().is_empty():
		return _fail("Boss death did not clear the open checkpoint.")

	return true


func _add_personal_hazard(boss: Node, position: Vector2) -> void:
	var definition := HazardDefinition.new()
	definition.duration = 0.0
	definition.show_visual = false
	definition.reaction_owner = "raider_personal"
	definition.automatic_response = "avoid_area"
	var hazard := CombatHazard.new()
	boss.add_child(hazard)
	hazard.global_position = position
	hazard.configure(definition, boss, [])
	boss.encounter_objects.append(hazard)
	owned_nodes.append(hazard)


func _fail(message: String) -> bool:
	push_error(message)
	get_tree().quit(1)
	return false
