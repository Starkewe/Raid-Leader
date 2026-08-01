extends CharacterBody2D

const CombatMeasurementsScript := preload("res://scripts/combat/combat_measurements.gd")
const BossAbilityFactoryScript := preload("res://scripts/abilities/boss_ability_factory.gd")
const BossTargetControllerScript := preload("res://scripts/combat/boss_target_controller.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")
const CleaveImpactEffectScript := preload("res://scripts/effects/cleave_impact_effect.gd")
const BossDebugVisualsScript := preload("res://scripts/effects/boss_debug_visuals.gd")

signal defeated
signal combat_event(event: Dictionary)
signal phase_changed(phase_id: String, display_name: String)

var show_debug_region_guides: bool = true
var show_debug_range_rings: bool = true
var debug_max_range_units: float = 50.0
var debug_logging_enabled: bool = true

@export var impact_effect_max_range_units: float = 50.0

var max_health: int = 3000
var speed: float = 140.0
var attack_range_units: float = 5.0
var movement_stop_range_units: float = -1.0
var combat_radius: float = 128.0
var attack_damage: int = 20
var attack_cooldown: float = 1.5
var special_cast_time: float = 2.5
var movement_mode: String = "mobile"
var basic_attack_id: String = "boss_auto_attack"
var basic_attack_display_name: String = "Attack"
var basic_attack_status_effect: StatusEffectDefinition = null
var basic_attack_damage_type: String = "physical"
var basic_attack_targeting_mode: String = "single_target"
var basic_attack_secondary_damage: int = 0
var basic_attack_secondary_target_count: int = 0
var basic_attack_secondary_damage_multiplier: float = 1.0
var basic_attack_secondary_closest_to_primary: bool = true
var basic_attack_raidwide_every_n_attacks: int = 0
var basic_attack_raidwide_damage: int = 0
var basic_attack_raidwide_ability_id: String = ""
var basic_attack_raidwide_display_name: String = ""
var basic_attack_raidwide_damage_type: String = "physical"
var basic_attack_raidwide_delay: float = 0.0
var basic_attack_triggered_ability_definition: BossAbilityDefinition = null
var basic_attack_trigger_threshold: int = 0
var basic_attack_trigger_when_target_outside_required_range: bool = false
var basic_attack_required_range: String = "close"
var initial_ability_delay: float = -1.0

@onready var health_bar = get_node_or_null("HealthBar")
@onready var cast_bar = get_node_or_null("CastBar")
@export var show_world_cast_bar: bool = false

var health: int
var encounter_definition: EncounterDefinition = null
var target_controller: BossTargetController = null

var boss_display_name: String = "Boss"
var ability_definitions: Array[BossAbilityDefinition] = []
var phase_definitions: Array[BossPhaseDefinition] = []
var current_phase: BossPhaseDefinition = null
var next_ability_index: int = 0

var party_members: Array = []
var current_ability: BossAbility = null
var next_ability: BossAbility = null

var attack_timer: float = 0.0
var special_timer: float = 0.0
var cast_timer: float = 0.0
var current_cast_elapsed: float = 0.0
var current_cast_speed_multiplier: float = 1.0
var is_casting: bool = false
var is_dead: bool = false
var encounter_active: bool = false
var encounter_objects: Array[Node] = []
var mechanic_state: Dictionary = {}
var encounter_origin_position: Vector2 = Vector2.ZERO
var basic_attack_sequence_count: int = 0
var basic_attack_trigger_count: int = 0
var pending_basic_raidwide_timer: float = -1.0
var pending_phase_transition_definition: BossAbilityDefinition = null
var phase_transition_pending: bool = false
var current_ability_is_phase_transition: bool = false
var current_ability_is_basic_attack_trigger: bool = false

func _ready():
	encounter_origin_position = global_position
	target_controller = BossTargetControllerScript.new()
	apply_selected_boss_profile()

	health = max_health
	update_current_phase(false)
	attack_timer = get_effective_attack_cooldown()

	if next_ability == null:
		next_ability = create_next_ability()

	special_timer = get_initial_ability_delay()
	setup_debug_visuals()


func setup_debug_visuals() -> void:
	var visuals := BossDebugVisualsScript.new()
	visuals.name = "DebugVisuals"
	visuals.z_index = -1
	add_child(visuals)
	visuals.setup(
		self,
		combat_radius,
		debug_max_range_units,
		show_debug_region_guides,
		show_debug_range_rings
	)
	GameState.register_raid_debug_content(
		visuals,
		show_debug_region_guides or show_debug_range_rings
	)

func apply_selected_boss_profile() -> void:
	if not Engine.has_singleton("GameState") and not has_node("/root/GameState"):
		return

	encounter_definition = GameState.get_selected_encounter_definition()

	if encounter_definition == null:
		speed = CombatMeasurementsScript.get_base_movement_speed_pixels_per_second()
		return

	boss_display_name = encounter_definition.boss_display_name
	max_health = encounter_definition.max_health
	movement_mode = encounter_definition.movement_mode
	speed = CombatMeasurementsScript.range_units_to_pixels(
		encounter_definition.movement_speed_range_units_per_second
	)
	attack_range_units = encounter_definition.attack_range_units
	movement_stop_range_units = encounter_definition.movement_stop_range_units
	combat_radius = encounter_definition.combat_radius
	attack_damage = encounter_definition.attack_damage
	attack_cooldown = encounter_definition.attack_cooldown
	basic_attack_id = encounter_definition.basic_attack_id
	basic_attack_display_name = encounter_definition.basic_attack_display_name
	basic_attack_status_effect = encounter_definition.basic_attack_status_effect
	basic_attack_damage_type = encounter_definition.basic_attack_damage_type
	basic_attack_targeting_mode = encounter_definition.basic_attack_targeting_mode
	basic_attack_secondary_damage = encounter_definition.basic_attack_secondary_damage
	basic_attack_secondary_target_count = encounter_definition.basic_attack_secondary_target_count
	basic_attack_secondary_damage_multiplier = encounter_definition.basic_attack_secondary_damage_multiplier
	basic_attack_secondary_closest_to_primary = encounter_definition.basic_attack_secondary_closest_to_primary
	basic_attack_raidwide_every_n_attacks = encounter_definition.basic_attack_raidwide_every_n_attacks
	basic_attack_raidwide_damage = encounter_definition.basic_attack_raidwide_damage
	basic_attack_raidwide_ability_id = encounter_definition.basic_attack_raidwide_ability_id
	basic_attack_raidwide_display_name = encounter_definition.basic_attack_raidwide_display_name
	basic_attack_raidwide_damage_type = encounter_definition.basic_attack_raidwide_damage_type
	basic_attack_raidwide_delay = encounter_definition.basic_attack_raidwide_delay
	basic_attack_triggered_ability_definition = encounter_definition.basic_attack_triggered_ability
	basic_attack_trigger_threshold = encounter_definition.basic_attack_trigger_threshold
	basic_attack_trigger_when_target_outside_required_range = (
		encounter_definition.basic_attack_trigger_when_target_outside_required_range
	)
	basic_attack_required_range = encounter_definition.basic_attack_required_range
	initial_ability_delay = encounter_definition.initial_ability_delay
	debug_logging_enabled = encounter_definition.debug_logging_enabled

	show_debug_region_guides = encounter_definition.show_debug_region_guides and OS.is_debug_build()
	show_debug_range_rings = encounter_definition.show_debug_range_rings and OS.is_debug_build()
	debug_max_range_units = encounter_definition.debug_max_range_units

	ability_definitions = encounter_definition.abilities.duplicate()
	phase_definitions = encounter_definition.phases.duplicate()
	phase_definitions.sort_custom(func(a: BossPhaseDefinition, b: BossPhaseDefinition):
		return a.starts_at_health_percent > b.starts_at_health_percent
	)
	next_ability_index = 0
func _physics_process(delta):
	if is_dead:
		return

	if target_controller != null:
		target_controller.update(delta)

	enforce_movement_mode()

	if not encounter_active:
		velocity = Vector2.ZERO
		return

	update_pending_basic_raidwide(delta)

	if is_casting:
		if current_ability != null and current_ability.requires_active_target and not has_valid_target():
			cancel_current_cast_due_to_missing_target()
			move_and_slide()
			enforce_movement_mode()
			return

		velocity = Vector2.ZERO
		update_special_cast(delta)
		move_and_slide()
		enforce_movement_mode()
		return

	attack_timer = max(attack_timer - delta, 0.0)
	special_timer = max(special_timer - delta, 0.0)

	if special_timer <= 0.0:
		start_special_cast()

		if is_casting:
			velocity = Vector2.ZERO
			move_and_slide()
			enforce_movement_mode()
			return

	var target := get_current_target()

	if target == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var distance_units: float = get_range_units_to_target(target)

	if movement_mode == "anchored":
		velocity = Vector2.ZERO
	elif distance_units > get_movement_stop_range_units():
		chase_target()
	else:
		velocity = Vector2.ZERO

	if movement_mode == "anchored" or distance_units <= attack_range_units:
		auto_attack()

	move_and_slide()
	enforce_movement_mode()

func create_next_ability() -> BossAbility:
	if ability_definitions.is_empty():
		return BossAbilityFactoryScript.create_fallback_ability()

	var ability_count := ability_definitions.size()
	var starting_index := posmod(next_ability_index, ability_count)

	for offset in range(ability_count):
		var definition_index := (starting_index + offset) % ability_count
		var definition := ability_definitions[definition_index]

		if definition == null:
			continue

		if current_phase != null and not current_phase.allows_ability(definition.ability_id):
			continue

		next_ability_index = (definition_index + 1) % ability_count
		return BossAbilityFactoryScript.create_ability_from_definition(definition)

	return null
func get_combat_radius() -> float:
	return combat_radius

func get_distance_pixels_to_target_edge(target_node: Node2D) -> float:
	if target_node == null or not is_instance_valid(target_node):
		return 999999.0

	var center_distance: float = get_combat_origin_position().distance_to(
		target_node.global_position
	)
	return maxf(center_distance - combat_radius, 0.0)


func get_range_units_to_target(target_node: Node2D) -> float:
	var distance_pixels: float = get_distance_pixels_to_target_edge(target_node)
	return CombatMeasurementsScript.pixels_to_range_units(distance_pixels)

func has_valid_target() -> bool:
	return get_current_target() != null

func set_target(new_target: Node2D):
	if is_dead:
		return

	if target_controller != null and target_controller.set_target(new_target):
		print("Boss target set to:", get_unit_debug_name(new_target))

func clear_target():
	if target_controller != null:
		target_controller.clear_target()

	velocity = Vector2.ZERO

func get_current_target() -> Node2D:
	if target_controller == null:
		return null

	var current_target := target_controller.get_target()

	if current_target is Node2D:
		return current_target as Node2D

	return null
func set_party_members(new_party_members: Array) -> void:
	party_members = new_party_members

	if target_controller == null:
		target_controller = BossTargetControllerScript.new()

	target_controller.setup(party_members)


func taunt(new_target: Node) -> bool:
	if (
		is_dead
		or phase_transition_pending
		or current_ability_is_phase_transition
		or target_controller == null
	):
		return false

	var success := target_controller.taunt(new_target)

	if success:
		velocity = Vector2.ZERO
		emit_combat_event("taunt", new_target, "taunt", 0)

	return success


func set_encounter_active(active: bool) -> void:
	encounter_active = active and not is_dead

	if not encounter_active:
		if target_controller != null:
			target_controller.reset_threat()

		velocity = Vector2.ZERO

		if is_casting and current_ability != null:
			current_ability.on_interrupted(self, party_members)
			emit_combat_event("cast_cancelled", self, current_ability.ability_id, 0, {
				"reason": "encounter_stopped"
			})

		is_casting = false
		current_ability = null
		cast_timer = 0.0
		current_cast_elapsed = 0.0
		current_cast_speed_multiplier = 1.0
		pending_phase_transition_definition = null
		phase_transition_pending = false
		current_ability_is_phase_transition = false
		current_ability_is_basic_attack_trigger = false
		reset_basic_attack_sequence(false)
		reset_basic_attack_trigger_sequence(false)
		update_cast_bar()
		clear_encounter_objects()
func chase_target():
	var target := get_current_target()

	if target == null:
		return

	var direction := global_position.direction_to(target.global_position)
	velocity = direction * speed

func auto_attack():
	if attack_timer > 0:
		return

	var target := get_current_target()

	if target == null:
		return

	attack_timer = get_effective_attack_cooldown()

	var trigger_reason := get_basic_attack_trigger_reason(target)

	if trigger_reason != "":
		if start_basic_attack_triggered_cast(trigger_reason):
			return

	var secondary_targets := get_basic_attack_secondary_targets(target)
	var resolved_damage := maxi(
		int(round(float(attack_damage) * get_attack_damage_multiplier())),
		0
	)
	var target_mini_region := get_mini_region_for_position(target.global_position)
	var target_mini_region_key := String(target_mini_region.get("key", ""))
	var hit_targets: Array = [target]
	hit_targets.append_array(secondary_targets)
	var status_targets: Array = (
		hit_targets
		if basic_attack_targeting_mode == "exact_mini_region"
		else [target]
	)
	var existing_stacks_by_target: Dictionary = {}

	for hit_target in status_targets:
		if (
			basic_attack_status_effect != null
			and hit_target.has_method("get_status_effect_stacks")
		):
			existing_stacks_by_target[hit_target] = int(
				hit_target.get_status_effect_stacks(basic_attack_status_effect.effect_id)
			)

	if target.has_method("take_damage"):
		target.take_damage(
			resolved_damage,
			self,
			basic_attack_id,
			{
				"repeated_target_stacks": int(existing_stacks_by_target.get(target, 0)),
				"damage_type": basic_attack_damage_type,
				"chain_index": 0,
				"mini_region": target_mini_region_key
			}
		)

	var secondary_damage := get_resolved_basic_attack_secondary_damage(resolved_damage)
	var secondary_labels: Array[String] = []

	for secondary_index in range(secondary_targets.size()):
		var secondary_target = secondary_targets[secondary_index]

		if not is_valid_living_party_member(secondary_target):
			continue

		if secondary_target.has_method("take_damage"):
			secondary_target.take_damage(
				secondary_damage,
				self,
				basic_attack_id,
				{
					"damage_type": basic_attack_damage_type,
					"chain_index": secondary_index + 1,
					"primary_target": target,
					"mini_region": target_mini_region_key
				}
			)
			secondary_labels.append(get_unit_debug_name(secondary_target))

	var stack_change_labels: Array[String] = []

	if basic_attack_status_effect != null:
		for hit_target in status_targets:
			if hit_target.has_method("apply_status_effect"):
				hit_target.apply_status_effect(basic_attack_status_effect, self)

			if hit_target.has_method("get_status_effect_stacks"):
				var previous_stacks := int(existing_stacks_by_target.get(hit_target, 0))
				var updated_stacks := int(
					hit_target.get_status_effect_stacks(basic_attack_status_effect.effect_id)
				)
				stack_change_labels.append(
					get_unit_debug_name(hit_target) + " "
					+ str(previous_stacks) + " -> " + str(updated_stacks)
				)

	var attack_message := (
		basic_attack_display_name + " primary " + get_unit_debug_name(target)
		+ " in " + target_mini_region_key + " for " + str(resolved_damage)
	)

	if basic_attack_targeting_mode == "exact_mini_region":
		attack_message += (
			"; cleaved [" + ", ".join(secondary_labels)
			+ "] for " + str(secondary_damage)
		)
	elif not secondary_labels.is_empty():
		attack_message += (
			"; chained for " + str(secondary_damage) + " to "
			+ ", ".join(secondary_labels)
		)

	if not stack_change_labels.is_empty():
		attack_message += "; vulnerability stacks [" + ", ".join(stack_change_labels) + "]"

	debug_log(attack_message + ".")

	advance_basic_attack_sequence()
	advance_basic_attack_trigger_sequence()


func get_basic_attack_secondary_targets(primary_target: Node2D) -> Array:
	if basic_attack_targeting_mode == "exact_mini_region":
		return get_exact_mini_region_cleave_targets(primary_target)

	if basic_attack_secondary_target_count <= 0 or primary_target == null:
		return []

	var candidates: Array = []

	for party_member in party_members:
		if party_member == primary_target or not is_valid_living_party_member(party_member):
			continue

		if party_member is Node2D:
			candidates.append(party_member)

	var distance_origin: Vector2 = (
		primary_target.global_position
		if basic_attack_secondary_closest_to_primary
		else global_position
	)
	candidates.sort_custom(func(a: Node2D, b: Node2D):
		return distance_origin.distance_squared_to(a.global_position) < distance_origin.distance_squared_to(b.global_position)
	)

	return candidates.slice(0, mini(basic_attack_secondary_target_count, candidates.size()))


func get_exact_mini_region_cleave_targets(primary_target: Node2D) -> Array:
	if primary_target == null:
		return []

	var primary_mini_region := get_mini_region_for_position(primary_target.global_position)
	var primary_key := String(primary_mini_region.get("key", ""))
	var targets: Array = []

	for party_member in party_members:
		if party_member == primary_target or not is_valid_living_party_member(party_member):
			continue

		if not party_member is Node2D:
			continue

		var candidate_mini_region := get_mini_region_for_position(
			(party_member as Node2D).global_position
		)

		if String(candidate_mini_region.get("key", "")) == primary_key:
			targets.append(party_member)

	return targets


func get_resolved_basic_attack_secondary_damage(resolved_primary_damage: int) -> int:
	if (
		basic_attack_targeting_mode == "exact_mini_region"
		and basic_attack_secondary_damage > 0
	):
		return maxi(
			int(round(
				float(basic_attack_secondary_damage) * get_attack_damage_multiplier()
			)),
			0
		)

	return maxi(
		int(round(float(resolved_primary_damage) * basic_attack_secondary_damage_multiplier)),
		0
	)


func get_basic_attack_trigger_reason(target: Node2D) -> String:
	if basic_attack_triggered_ability_definition == null:
		return ""

	if (
		basic_attack_trigger_when_target_outside_required_range
		and not is_target_in_required_basic_attack_range(target)
	):
		return "target_outside_required_range"

	var threshold := get_current_basic_attack_trigger_threshold()

	if threshold > 0 and basic_attack_trigger_count >= threshold:
		return "charge_threshold"

	return ""


func is_target_in_required_basic_attack_range(target: Node2D) -> bool:
	if target == null:
		return false

	var target_range := MovementSlotResolverScript.get_nearest_range_from_origin(
		self,
		get_combat_origin_position(),
		target.global_position
	)
	return target_range == basic_attack_required_range


func start_basic_attack_triggered_cast(trigger_reason: String) -> bool:
	if is_casting or basic_attack_triggered_ability_definition == null:
		return false

	var ability_to_cast := BossAbilityFactoryScript.create_ability_from_definition(
		basic_attack_triggered_ability_definition
	)

	if ability_to_cast == null or not ability_to_cast.can_cast(self, party_members):
		return false

	var charges_consumed := basic_attack_trigger_count
	var threshold := get_current_basic_attack_trigger_threshold()
	var target := get_current_target()
	var locked_region := ""

	if target != null:
		locked_region = MovementSlotResolverScript.get_nearest_region_from_position(
			get_combat_origin_position(),
			target.global_position
		)

	basic_attack_trigger_count = 0
	current_ability = ability_to_cast
	current_ability_is_phase_transition = false
	current_ability_is_basic_attack_trigger = true
	is_casting = true
	current_cast_speed_multiplier = get_ability_speed_multiplier()
	cast_timer = current_ability.cast_time / current_cast_speed_multiplier
	current_cast_elapsed = 0.0

	current_ability.on_cast_start(self, party_members)
	emit_combat_event("cast_started", self, current_ability.ability_id, 0, {
		"cast_name": current_ability.get_cast_name(),
		"cast_time": cast_timer,
		"interruptible": current_ability.interruptible,
		"trigger_source": trigger_reason,
		"charges_consumed": charges_consumed,
		"phase_threshold": threshold,
		"locked_region": locked_region
	})

	debug_log(
		current_ability.get_cast_name() + " triggered by "
		+ (
			"current target outside " + basic_attack_required_range + " range"
			if trigger_reason == "target_outside_required_range"
			else "charge threshold"
		)
		+ "; consumed " + str(charges_consumed) + " charge(s); locked "
		+ locked_region + "; phase threshold " + str(threshold) + "."
	)

	update_cast_bar()

	if current_ability.interruptible:
		print("Boss begins casting", current_ability.get_cast_name(), "Interrupt now!")
	else:
		print("Boss begins casting", current_ability.get_cast_name(), "This cast cannot be interrupted.")

	return true


func advance_basic_attack_trigger_sequence() -> void:
	if basic_attack_triggered_ability_definition == null:
		return

	basic_attack_trigger_count += 1
	var threshold := get_current_basic_attack_trigger_threshold()
	debug_log(
		basic_attack_display_name + " charge count is now "
		+ str(basic_attack_trigger_count) + "/" + str(threshold) + "."
	)


func reset_basic_attack_trigger_sequence(should_log: bool = true) -> void:
	basic_attack_trigger_count = 0

	if should_log and basic_attack_triggered_ability_definition != null:
		debug_log("Reset the basic-attack triggered-ability counter.")


func advance_basic_attack_sequence() -> void:
	if basic_attack_raidwide_every_n_attacks <= 0 or basic_attack_raidwide_damage <= 0:
		return

	basic_attack_sequence_count += 1

	if basic_attack_sequence_count < basic_attack_raidwide_every_n_attacks:
		return

	basic_attack_sequence_count = 0
	pending_basic_raidwide_timer = maxf(basic_attack_raidwide_delay, 0.0)
	debug_log(
		basic_attack_raidwide_display_name + " primed after "
		+ str(basic_attack_raidwide_every_n_attacks) + " attacks."
	)

	if pending_basic_raidwide_timer <= 0.0:
		resolve_basic_attack_raidwide()


func update_pending_basic_raidwide(delta: float) -> void:
	if pending_basic_raidwide_timer < 0.0:
		return

	pending_basic_raidwide_timer = maxf(pending_basic_raidwide_timer - delta, 0.0)

	if pending_basic_raidwide_timer <= 0.0:
		resolve_basic_attack_raidwide()


func resolve_basic_attack_raidwide() -> void:
	pending_basic_raidwide_timer = -1.0
	var resolved_damage := maxi(
		int(round(float(basic_attack_raidwide_damage) * get_attack_damage_multiplier())),
		0
	)
	var hit_count := 0

	for party_member in party_members:
		if not is_valid_living_party_member(party_member):
			continue

		if party_member.has_method("take_damage"):
			party_member.take_damage(
				resolved_damage,
				self,
				basic_attack_raidwide_ability_id,
				{"damage_type": basic_attack_raidwide_damage_type, "raid_wide": true}
			)
			hit_count += 1

	debug_log(
		basic_attack_raidwide_display_name + " dealt " + str(resolved_damage)
		+ " " + basic_attack_raidwide_damage_type + " damage to "
		+ str(hit_count) + " unit(s)."
	)


func reset_basic_attack_sequence(should_log: bool = true) -> void:
	basic_attack_sequence_count = 0
	pending_basic_raidwide_timer = -1.0

	if should_log and basic_attack_raidwide_every_n_attacks > 0:
		debug_log("Reset the basic-attack raid-pulse counter.")

func start_special_cast():
	if is_casting:
		return

	var ability_to_cast: BossAbility = null
	var starts_phase_transition := pending_phase_transition_definition != null

	if starts_phase_transition:
		ability_to_cast = BossAbilityFactoryScript.create_ability_from_definition(
			pending_phase_transition_definition
		)
	else:
		if next_ability == null:
			next_ability = create_next_ability()

		ability_to_cast = next_ability

	if ability_to_cast == null:
		pending_phase_transition_definition = null
		phase_transition_pending = false
		special_timer = 1.0
		return

	if not ability_to_cast.can_cast(self, party_members):
		if starts_phase_transition:
			pending_phase_transition_definition = null
			phase_transition_pending = false
		special_timer = get_next_ability_cooldown()
		return

	current_ability = ability_to_cast
	current_ability_is_phase_transition = starts_phase_transition
	current_ability_is_basic_attack_trigger = false

	if starts_phase_transition:
		pending_phase_transition_definition = null
		phase_transition_pending = false
		reset_basic_attack_sequence(false)
	else:
		next_ability = create_next_ability()

	is_casting = true
	current_cast_speed_multiplier = 1.0 if starts_phase_transition else get_ability_speed_multiplier()
	cast_timer = current_ability.cast_time / current_cast_speed_multiplier
	current_cast_elapsed = 0.0

	current_ability.on_cast_start(self, party_members)
	emit_combat_event("cast_started", self, current_ability.ability_id, 0, {
		"cast_name": current_ability.get_cast_name(),
		"cast_time": cast_timer,
		"interruptible": current_ability.interruptible
	})

	update_cast_bar()

	if current_ability.interruptible:
		print("Boss begins casting", current_ability.get_cast_name(), "Interrupt now!")
	else:
		print("Boss begins casting", current_ability.get_cast_name(), "This cast cannot be interrupted.")

func update_special_cast(delta):
	cast_timer -= delta
	current_cast_elapsed += delta * current_cast_speed_multiplier

	if current_ability != null:
		current_ability.on_cast_update(
			self,
			party_members,
			current_cast_elapsed,
			maxf(cast_timer, 0.0)
		)

	update_cast_bar()

	if cast_timer <= 0:
		finish_special_cast()

func finish_special_cast():
	is_casting = false
	var finished_phase_transition := current_ability_is_phase_transition
	var finished_basic_attack_trigger := current_ability_is_basic_attack_trigger

	if current_ability != null:
		if finished_phase_transition:
			special_timer = maxf(current_ability.cooldown, 0.0)
		elif not finished_basic_attack_trigger:
			special_timer = get_ability_recovery_time(current_ability)

		print("Boss finishes", current_ability.get_cast_name())
		current_ability.resolve(self, party_members)
		emit_combat_event("cast_resolved", self, current_ability.ability_id, 0)
	else:
		special_timer = get_next_ability_cooldown()

	current_ability = null
	current_ability_is_phase_transition = false
	current_ability_is_basic_attack_trigger = false

	if finished_phase_transition:
		attack_timer = get_effective_attack_cooldown()
		reset_basic_attack_sequence(false)
		debug_log("Phase transition complete; normal attack rhythm resumed.")
	current_cast_elapsed = 0.0
	current_cast_speed_multiplier = 1.0
	update_cast_bar()
func cancel_current_cast_due_to_missing_target() -> void:
	if not is_casting:
		return

	is_casting = false
	cast_timer = 0.0
	current_cast_elapsed = 0.0

	var cancelled_basic_attack_trigger := current_ability_is_basic_attack_trigger

	if current_ability != null:
		current_ability.on_interrupted(self, party_members)

		if not cancelled_basic_attack_trigger:
			special_timer = get_ability_recovery_time(current_ability)

		emit_combat_event("cast_cancelled", self, current_ability.ability_id, 0, {
			"reason": "missing_target"
		})
	else:
		special_timer = get_next_ability_cooldown()

	current_ability = null
	current_ability_is_phase_transition = false
	current_ability_is_basic_attack_trigger = false
	current_cast_speed_multiplier = 1.0
	update_cast_bar()

	print("Boss cast cancelled because its target is no longer valid.")
func interrupt_cast(source: Node = null, interrupt_ability_id: String = "interrupt") -> bool:
	if is_dead:
		return false

	if is_casting:
		if current_ability != null and not current_ability.interruptible:
			print("Boss cast cannot be interrupted.")
			return false

		is_casting = false
		cast_timer = 0.0
		current_cast_elapsed = 0.0

		if current_ability != null:
			var interrupted_basic_attack_trigger := current_ability_is_basic_attack_trigger
			current_ability.on_interrupted(self, party_members)

			if not interrupted_basic_attack_trigger:
				special_timer = get_ability_recovery_time(current_ability)

			emit_combat_event("cast_interrupted", source, current_ability.ability_id, 0, {
				"interrupt_ability_id": interrupt_ability_id
			})
		else:
			special_timer = get_next_ability_cooldown()

		current_ability = null
		current_ability_is_phase_transition = false
		current_ability_is_basic_attack_trigger = false
		current_cast_speed_multiplier = 1.0
		update_cast_bar()
		print("Boss cast interrupted!")
		return true

	print("Boss is not casting anything interruptible.")
	return false

func take_damage(
	amount: int,
	source: Node = null,
	ability_id: String = "",
	metadata: Dictionary = {}
) -> void:
	if is_dead or phase_transition_pending or current_ability_is_phase_transition:
		return

	var previous_health := health
	health -= maxi(amount, 0)
	health = max(health, 0)
	var actual_amount := previous_health - health

	if actual_amount > 0 and target_controller != null:
		target_controller.record_damage_threat(source, actual_amount)

	update_health_bar()
	emit_combat_event("damage", source, ability_id, actual_amount, metadata)
	update_current_phase()

	print("Boss took", actual_amount, "damage. HP:", health)

	if health <= 0:
		die()

func die():
	if is_dead:
		return

	is_dead = true
	encounter_active = false
	health = 0
	update_health_bar()

	if current_ability != null:
		current_ability.on_interrupted(self, party_members)
		emit_combat_event("cast_cancelled", self, current_ability.ability_id, 0, {
			"reason": "boss_defeated"
		})

	is_casting = false
	cast_timer = 0.0
	current_cast_elapsed = 0.0
	current_cast_speed_multiplier = 1.0
	current_ability = null
	current_ability_is_phase_transition = false
	current_ability_is_basic_attack_trigger = false
	phase_transition_pending = false
	pending_phase_transition_definition = null
	reset_basic_attack_sequence(false)
	reset_basic_attack_trigger_sequence(false)
	update_cast_bar()
	clear_encounter_objects()
	reset_threat()

	print("Boss defeated!")
	emit_combat_event("boss_defeated", null, "", 0)
	defeated.emit()

func is_alive() -> bool:
	return not is_dead

func update_health_bar():
	if health_bar == null:
		return

	health_bar.max_value = max_health
	health_bar.value = health

func update_cast_bar():
	if cast_bar == null:
		return

	if not show_world_cast_bar:
		cast_bar.visible = false
		cast_bar.value = 0
		return

	var active_cast_time := get_current_cast_time()

	cast_bar.max_value = active_cast_time

	if is_casting:
		cast_bar.visible = true
		cast_bar.value = get_current_cast_bar_value()
	else:
		cast_bar.visible = false
		cast_bar.value = 0
func reset_boss(new_position: Vector2):
	clear_encounter_objects()
	mechanic_state.clear()
	is_dead = false
	encounter_active = false
	health = max_health
	reset_threat()
	next_ability_index = 0
	next_ability = null
	current_phase = null
	update_current_phase(false)

	is_casting = false
	current_ability = null
	current_ability_is_phase_transition = false
	current_ability_is_basic_attack_trigger = false
	phase_transition_pending = false
	pending_phase_transition_definition = null
	reset_basic_attack_sequence(false)
	reset_basic_attack_trigger_sequence(false)

	if next_ability == null:
		next_ability = create_next_ability()

	attack_timer = get_effective_attack_cooldown()
	special_timer = get_initial_ability_delay()
	cast_timer = 0.0
	current_cast_elapsed = 0.0
	current_cast_speed_multiplier = 1.0

	global_position = new_position
	encounter_origin_position = new_position

	update_health_bar()
	update_cast_bar()
	visible = true


func remove_threat(source: Node) -> void:
	if target_controller != null:
		target_controller.remove_threat(source)


func reset_threat() -> void:
	if target_controller != null:
		target_controller.reset_threat()


func get_threat_for(source: Node) -> float:
	if target_controller == null:
		return 0.0

	return target_controller.get_threat_for(source)


func get_threat_table_snapshot() -> Dictionary:
	if target_controller == null:
		return {}

	return target_controller.get_threat_table_snapshot()
func get_status_text() -> String:
	if is_dead:
		return "Defeated"

	if is_casting and current_ability != null:
		return current_ability.get_status_text()

	if is_casting:
		return "Casting"

	var target := get_current_target()

	if target != null:
		var attack_status := "Attacking " + get_unit_debug_name(target)

		if basic_attack_raidwide_every_n_attacks > 0:
			attack_status += " | " + basic_attack_raidwide_display_name + " "
			attack_status += str(basic_attack_sequence_count) + "/"
			attack_status += str(basic_attack_raidwide_every_n_attacks)

		if basic_attack_triggered_ability_definition != null:
			attack_status += " | " + basic_attack_triggered_ability_definition.display_name + " "
			attack_status += str(basic_attack_trigger_count) + "/"
			attack_status += str(get_current_basic_attack_trigger_threshold())

		return attack_status

	return "Idle"
func get_current_health() -> int:
	return health

func get_max_health() -> int:
	return max_health

func is_casting_ability() -> bool:
	return is_casting

func get_cast_progress_percent() -> float:
	if not is_casting:
		return 0.0

	var active_cast_time := get_current_cast_time()

	if active_cast_time <= 0:
		return 0.0

	return clamp((get_current_cast_bar_value() / active_cast_time) * 100.0, 0.0, 100.0)

func get_cast_name() -> String:
	if is_casting and current_ability != null:
		return current_ability.get_cast_name()

	return ""
func get_next_ability_cooldown() -> float:
	if next_ability != null:
		return get_ability_recovery_time(next_ability)

	return 6.0
func get_display_name() -> String:
	return boss_display_name

func get_current_cast_time() -> float:
	if current_ability != null:
		return current_ability.get_cast_bar_max_time(
			current_cast_elapsed,
			maxf(cast_timer, 0.0)
		) / current_cast_speed_multiplier

	return special_cast_time
func get_current_cast_bar_value() -> float:
	if current_ability != null:
		return current_ability.get_cast_bar_value(
			current_cast_elapsed,
			maxf(cast_timer, 0.0)
		) / current_cast_speed_multiplier

	return clampf(special_cast_time - cast_timer, 0.0, special_cast_time)


func play_region_impact_effect(region: String, ranges: Array[String]) -> void:
	var effect := CleaveImpactEffectScript.new()

	effect.z_index = 100

	add_child(effect)

	effect.setup(
		region,
		ranges,
		combat_radius,
		impact_effect_max_range_units
	)
	register_encounter_object(effect)


func play_region_telegraph(
	region: String,
	ranges: Array[String],
	duration: float,
	fill_color: Color = Color(0.75, 0.08, 0.04, 0.28),
	edge_color: Color = Color(1.0, 0.25, 0.08, 0.95)
) -> void:
	var effect := CleaveImpactEffectScript.new()
	effect.z_index = 80
	effect.duration = maxf(duration, 0.05)
	effect.particle_count = 0
	effect.fill_color = fill_color
	effect.edge_color = edge_color
	add_child(effect)
	effect.setup(region, ranges, combat_radius, impact_effect_max_range_units)
	register_encounter_object(effect)


func get_effective_attack_cooldown() -> float:
	var multiplier := 1.0

	if current_phase != null:
		multiplier = current_phase.attack_speed_multiplier

	return attack_cooldown / maxf(multiplier, 0.01)


func begin_full_basic_attack_recovery() -> void:
	attack_timer = get_effective_attack_cooldown()


func get_movement_stop_range_units() -> float:
	if movement_stop_range_units < 0.0:
		return attack_range_units

	return minf(movement_stop_range_units, attack_range_units)


func get_current_basic_attack_trigger_threshold() -> int:
	if (
		current_phase != null
		and current_phase.basic_attack_trigger_threshold_override >= 0
	):
		return current_phase.basic_attack_trigger_threshold_override

	return maxi(basic_attack_trigger_threshold, 0)


func get_ability_speed_multiplier() -> float:
	if current_phase == null:
		return 1.0

	return maxf(current_phase.ability_speed_multiplier, 0.01)


func get_ability_cooldown_multiplier() -> float:
	if current_phase == null:
		return 1.0

	return maxf(current_phase.ability_cooldown_multiplier, 0.01)


func get_attack_damage_multiplier() -> float:
	if current_phase == null:
		return 1.0

	return maxf(current_phase.attack_damage_multiplier, 0.0)


func get_ability_damage_multiplier() -> float:
	if current_phase == null:
		return 1.0

	return maxf(current_phase.ability_damage_multiplier, 0.0)


func get_ability_target_count_bonus() -> int:
	if current_phase == null:
		return 0

	return current_phase.ability_target_count_bonus


func get_ability_recovery_time(ability: BossAbility) -> float:
	if ability == null:
		return 1.0

	return (
		ability.cooldown
		* get_ability_cooldown_multiplier()
		/ get_ability_speed_multiplier()
	)


func get_initial_ability_delay() -> float:
	if initial_ability_delay >= 0.0:
		return initial_ability_delay

	return get_next_ability_cooldown()


func update_current_phase(emit_change_event: bool = true) -> void:
	if phase_definitions.is_empty() or max_health <= 0:
		return

	var health_percent := (float(health) / float(max_health)) * 100.0
	var next_phase: BossPhaseDefinition = null

	for phase in phase_definitions:
		if phase != null and health_percent <= phase.starts_at_health_percent:
			next_phase = phase

	if next_phase == null or next_phase == current_phase:
		return

	var previous_trigger_threshold := get_current_basic_attack_trigger_threshold()
	current_phase = next_phase
	var updated_trigger_threshold := get_current_basic_attack_trigger_threshold()
	var has_explicit_phase_transition := (
		health > 0 and current_phase.transition_ability != null
	)

	if has_explicit_phase_transition:
		next_ability_index = 0
		next_ability = create_next_ability()
	elif (
		next_ability == null
		or not current_phase.allows_ability(next_ability.ability_id)
	):
		next_ability = create_next_ability()

	if not emit_change_event:
		return

	debug_log(
		"Phase changed to " + current_phase.display_name
		+ " at " + str(snappedf(health_percent, 0.1)) + "% health."
	)

	if previous_trigger_threshold != updated_trigger_threshold:
		debug_log(
			"Basic-attack trigger threshold changed "
			+ str(previous_trigger_threshold) + " -> " + str(updated_trigger_threshold)
			+ "; preserved " + str(basic_attack_trigger_count) + " charge(s); next "
			+ basic_attack_display_name + " opportunity "
			+ (
				"will trigger " + basic_attack_triggered_ability_definition.display_name
				if (
					basic_attack_triggered_ability_definition != null
					and updated_trigger_threshold > 0
					and basic_attack_trigger_count >= updated_trigger_threshold
				)
				else "is not yet at the trigger threshold"
			)
			+ "."
		)

	phase_changed.emit(current_phase.phase_id, current_phase.display_name)
	emit_combat_event(
		"phase_changed",
		self,
		current_phase.phase_id,
		int(round(health_percent)),
		{"display_name": current_phase.display_name}
	)

	if has_explicit_phase_transition:
		queue_phase_transition(current_phase.transition_ability)


func queue_phase_transition(transition_definition: BossAbilityDefinition) -> void:
	if transition_definition == null or is_dead:
		return

	if is_casting and current_ability != null:
		current_ability.on_interrupted(self, party_members)
		emit_combat_event("cast_cancelled", self, current_ability.ability_id, 0, {
			"reason": "phase_transition"
		})

	is_casting = false
	current_ability = null
	current_ability_is_phase_transition = false
	current_ability_is_basic_attack_trigger = false
	cast_timer = 0.0
	current_cast_elapsed = 0.0
	current_cast_speed_multiplier = 1.0
	pending_phase_transition_definition = transition_definition
	phase_transition_pending = true
	special_timer = 0.0
	velocity = Vector2.ZERO
	reset_basic_attack_sequence(false)
	update_cast_bar()
	debug_log("Queued phase transition: " + transition_definition.display_name + ".")


func get_current_phase_id() -> String:
	return "" if current_phase == null else current_phase.phase_id


func get_current_phase_name() -> String:
	return "" if current_phase == null else current_phase.display_name


func get_encounter_origin_position() -> Vector2:
	return encounter_origin_position


func get_combat_origin_position() -> Vector2:
	if movement_mode == "anchored":
		return encounter_origin_position

	return global_position


func get_mini_region_for_position(unit_position: Vector2) -> Dictionary:
	return MovementSlotResolverScript.get_mini_region_from_origin(
		self,
		get_combat_origin_position(),
		unit_position
	)


func enforce_movement_mode() -> void:
	if movement_mode != "anchored":
		return

	global_position = encounter_origin_position
	velocity = Vector2.ZERO


func move_to_encounter_origin() -> void:
	global_position = encounter_origin_position
	velocity = Vector2.ZERO


func is_valid_living_party_member(party_member: Node) -> bool:
	if party_member == null or not is_instance_valid(party_member):
		return false

	if party_member.has_method("is_alive"):
		return bool(party_member.is_alive())

	return true


func get_unit_debug_name(unit: Node) -> String:
	if unit == null or not is_instance_valid(unit):
		return "Invalid target"

	if unit.has_method("get_display_name"):
		return String(unit.get_display_name())

	return String(unit.name)


func register_encounter_object(encounter_object: Node) -> void:
	if encounter_object == null or not is_instance_valid(encounter_object):
		return

	if not encounter_objects.has(encounter_object):
		encounter_objects.append(encounter_object)


func clear_encounter_objects() -> void:
	var cleaned_count := 0

	for encounter_object in encounter_objects:
		if encounter_object == null or not is_instance_valid(encounter_object):
			continue

		if encounter_object.has_method("cleanup"):
			encounter_object.cleanup()
		else:
			encounter_object.queue_free()

		cleaned_count += 1

	encounter_objects.clear()
	mechanic_state.clear()

	if cleaned_count > 0:
		debug_log("Cleaned up " + str(cleaned_count) + " encounter object(s).")


func get_mechanic_state(state_key: String, default_value: Variant = null) -> Variant:
	return mechanic_state.get(state_key, default_value)


func set_mechanic_state(state_key: String, value: Variant) -> void:
	mechanic_state[state_key] = value


func debug_log(message: String) -> void:
	if not debug_logging_enabled:
		return

	print("[Boss: " + boss_display_name + "] " + message)


func emit_combat_event(
	event_type: String,
	source: Node,
	ability_id: String,
	amount: int,
	metadata: Dictionary = {}
) -> void:
	combat_event.emit({
		"type": event_type,
		"source": source,
		"target": self,
		"ability_id": ability_id,
		"amount": amount,
		"metadata": metadata.duplicate(true)
	})
