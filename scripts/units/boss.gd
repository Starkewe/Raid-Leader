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

@export var impact_effect_max_range_units: float = 50.0

var max_health: int = 3000
var speed: float = 140.0
var attack_range_units: float = 5.0
var combat_radius: float = 128.0
var attack_damage: int = 20
var attack_cooldown: float = 1.5
var special_cast_time: float = 2.5

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

func _ready():
	target_controller = BossTargetControllerScript.new()
	apply_selected_boss_profile()

	health = max_health
	update_current_phase(false)
	attack_timer = get_effective_attack_cooldown()

	if next_ability == null:
		next_ability = create_next_ability()

	special_timer = get_next_ability_cooldown()
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

func apply_selected_boss_profile() -> void:
	if not Engine.has_singleton("GameState") and not has_node("/root/GameState"):
		return

	encounter_definition = GameState.get_selected_encounter_definition()

	if encounter_definition == null:
		speed = CombatMeasurementsScript.get_base_movement_speed_pixels_per_second()
		return

	boss_display_name = encounter_definition.boss_display_name
	max_health = encounter_definition.max_health
	speed = CombatMeasurementsScript.range_units_to_pixels(
		encounter_definition.movement_speed_range_units_per_second
	)
	attack_range_units = encounter_definition.attack_range_units
	combat_radius = encounter_definition.combat_radius
	attack_damage = encounter_definition.attack_damage
	attack_cooldown = encounter_definition.attack_cooldown

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

	if not encounter_active:
		velocity = Vector2.ZERO
		return

	if is_casting:
		if current_ability != null and current_ability.requires_active_target and not has_valid_target():
			cancel_current_cast_due_to_missing_target()
			move_and_slide()
			return

		velocity = Vector2.ZERO
		update_special_cast(delta)
		move_and_slide()
		return

	attack_timer = max(attack_timer - delta, 0.0)
	special_timer = max(special_timer - delta, 0.0)

	if special_timer <= 0.0:
		start_special_cast()

		if is_casting:
			velocity = Vector2.ZERO
			move_and_slide()
			return

	var target := get_current_target()

	if target == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var distance_units: float = get_range_units_to_target(target)

	if distance_units > attack_range_units:
		chase_target()
	else:
		velocity = Vector2.ZERO
		auto_attack()

	move_and_slide()

func create_next_ability() -> BossAbility:
	if ability_definitions.is_empty():
		return BossAbilityFactoryScript.create_fallback_ability()

	var available_definitions: Array[BossAbilityDefinition] = []

	for definition in ability_definitions:
		if definition == null:
			continue

		if current_phase == null or current_phase.allows_ability(definition.ability_id):
			available_definitions.append(definition)

	if available_definitions.is_empty():
		return null

	var definition := available_definitions[next_ability_index % available_definitions.size()]
	next_ability_index = (next_ability_index + 1) % available_definitions.size()

	return BossAbilityFactoryScript.create_ability_from_definition(definition)
func get_combat_radius() -> float:
	return combat_radius

func get_distance_pixels_to_target_edge(target_node: Node2D) -> float:
	if target_node == null or not is_instance_valid(target_node):
		return 999999.0

	var center_distance: float = global_position.distance_to(target_node.global_position)
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
		print("Boss target set to:", new_target.name)

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
	if is_dead or target_controller == null:
		return false

	var success := target_controller.taunt(new_target)

	if success:
		velocity = Vector2.ZERO
		emit_combat_event("taunt", new_target, "taunt", 0)

	return success


func set_encounter_active(active: bool) -> void:
	encounter_active = active and not is_dead

	if not encounter_active:
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
		update_cast_bar()
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
	print("Boss auto attacks:", target.name)

	if target.has_method("take_damage"):
		target.take_damage(attack_damage, self, "boss_auto_attack")

func start_special_cast():
	if is_casting:
		return

	if next_ability == null:
		next_ability = create_next_ability()

	if next_ability == null:
		special_timer = 1.0
		return

	if not next_ability.can_cast(self, party_members):
		special_timer = get_next_ability_cooldown()
		return

	current_ability = next_ability
	next_ability = create_next_ability()

	is_casting = true
	current_cast_speed_multiplier = get_ability_speed_multiplier()
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

	if current_ability != null:
		special_timer = current_ability.cooldown / get_ability_speed_multiplier()
		print("Boss finishes", current_ability.get_cast_name())
		current_ability.resolve(self, party_members)
		emit_combat_event("cast_resolved", self, current_ability.ability_id, 0)
	else:
		special_timer = get_next_ability_cooldown()

	current_ability = null
	current_cast_elapsed = 0.0
	current_cast_speed_multiplier = 1.0
	update_cast_bar()
func cancel_current_cast_due_to_missing_target() -> void:
	if not is_casting:
		return

	is_casting = false
	cast_timer = 0.0
	current_cast_elapsed = 0.0

	if current_ability != null:
		current_ability.on_interrupted(self, party_members)
		special_timer = current_ability.cooldown / get_ability_speed_multiplier()
		emit_combat_event("cast_cancelled", self, current_ability.ability_id, 0, {
			"reason": "missing_target"
		})
	else:
		special_timer = get_next_ability_cooldown()

	current_ability = null
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
			current_ability.on_interrupted(self, party_members)
			special_timer = current_ability.cooldown / get_ability_speed_multiplier()
			emit_combat_event("cast_interrupted", source, current_ability.ability_id, 0, {
				"interrupt_ability_id": interrupt_ability_id
			})
		else:
			special_timer = get_next_ability_cooldown()

		current_ability = null
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
	if is_dead:
		return

	var previous_health := health
	health -= maxi(amount, 0)
	health = max(health, 0)
	var actual_amount := previous_health - health
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
	update_cast_bar()
	clear_target()

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
	is_dead = false
	encounter_active = false
	health = max_health
	clear_target()
	next_ability_index = 0
	next_ability = null
	current_phase = null
	update_current_phase(false)

	is_casting = false
	current_ability = null

	if next_ability == null:
		next_ability = create_next_ability()

	attack_timer = get_effective_attack_cooldown()
	special_timer = get_next_ability_cooldown()
	cast_timer = 0.0
	current_cast_elapsed = 0.0
	current_cast_speed_multiplier = 1.0

	global_position = new_position

	update_health_bar()
	update_cast_bar()
	visible = true
func get_status_text() -> String:
	if is_dead:
		return "Defeated"

	if is_casting and current_ability != null:
		return current_ability.get_status_text()

	if is_casting:
		return "Casting"

	var target := get_current_target()

	if target != null:
		return "Attacking " + target.name

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
		return next_ability.cooldown / get_ability_speed_multiplier()

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


func get_effective_attack_cooldown() -> float:
	var multiplier := 1.0

	if current_phase != null:
		multiplier = current_phase.attack_speed_multiplier

	return attack_cooldown / maxf(multiplier, 0.01)


func get_ability_speed_multiplier() -> float:
	if current_phase == null:
		return 1.0

	return maxf(current_phase.ability_speed_multiplier, 0.01)


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

	current_phase = next_phase
	next_ability_index = 0
	next_ability = create_next_ability()

	if not emit_change_event:
		return

	phase_changed.emit(current_phase.phase_id, current_phase.display_name)
	emit_combat_event(
		"phase_changed",
		self,
		current_phase.phase_id,
		int(round(health_percent)),
		{"display_name": current_phase.display_name}
	)


func get_current_phase_id() -> String:
	return "" if current_phase == null else current_phase.phase_id


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
