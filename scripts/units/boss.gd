extends CharacterBody2D

const CombatMeasurementsScript := preload("res://scripts/combat/combat_measurements.gd")
const BossAbilityFactoryScript := preload("res://scripts/abilities/boss_ability_factory.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")
const CleaveImpactEffectScript := preload("res://scripts/effects/cleave_impact_effect.gd")

signal defeated

@export var show_debug_region_guides: bool = true
@export var show_debug_range_rings: bool = true
@export var debug_max_range_units: float = 50.0

@export var impact_effect_max_range_units: float = 50.0

@export var max_health: int = 3000
@export var speed: float = 140.0
@export var attack_range_units: float = 5.0
@export var combat_radius: float = 128.0
@export var attack_damage: int = 20
@export var attack_cooldown: float = 1.5
@export var special_cast_interval: float = 6.0
@export var special_cast_time: float = 2.5
@export var special_damage: int = 75

@onready var health_bar = get_node_or_null("HealthBar")
@onready var cast_bar = get_node_or_null("CastBar")
@export var show_world_cast_bar: bool = false

var health: int
var target: Node2D = null

var boss_display_name: String = "Boss"
var ability_ids: Array = []
var next_ability_index: int = 0

var party_members: Array = []
var current_ability: BossAbility = null
var next_ability: BossAbility = null

var attack_timer: float = 0.0
var special_timer: float = 0.0
var cast_timer: float = 0.0
var current_cast_elapsed: float = 0.0
var is_casting: bool = false
var is_dead: bool = false

func _ready():
	apply_selected_boss_profile()

	speed = CombatMeasurementsScript.get_base_movement_speed_pixels_per_second()
	health = max_health
	attack_timer = attack_cooldown
	next_ability = create_next_ability()
	special_timer = get_next_ability_cooldown()
	
func apply_selected_boss_profile() -> void:
	if not Engine.has_singleton("GameState") and not has_node("/root/GameState"):
		return

	var boss_data: Dictionary = GameState.get_selected_tutorial_boss_data()

	if boss_data.is_empty():
		return

	boss_display_name = String(boss_data.get("boss_display_name", boss_display_name))

	max_health = int(boss_data.get("max_health", max_health))
	attack_range_units = float(boss_data.get("attack_range_units", attack_range_units))
	combat_radius = float(boss_data.get("combat_radius", combat_radius))
	attack_damage = int(boss_data.get("attack_damage", attack_damage))
	attack_cooldown = float(boss_data.get("attack_cooldown", attack_cooldown))

	show_debug_region_guides = bool(boss_data.get("show_debug_region_guides", show_debug_region_guides))
	show_debug_range_rings = bool(boss_data.get("show_debug_range_rings", show_debug_range_rings))
	debug_max_range_units = float(boss_data.get("debug_max_range_units", debug_max_range_units))

	ability_ids = boss_data.get("ability_ids", []).duplicate()
	next_ability_index = 0
func _physics_process(delta):
	if is_dead:
		return

	if not has_valid_target():
		if is_casting:
			cancel_current_cast_due_to_missing_target()

		clear_target()
		move_and_slide()
		return

	if is_casting:
		velocity = Vector2.ZERO
		update_special_cast(delta)
		move_and_slide()
		return

	attack_timer = max(attack_timer - delta, 0.0)
	special_timer = max(special_timer - delta, 0.0)

	if special_timer <= 0.0:
		start_special_cast()
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
	if ability_ids.is_empty():
		return BossAbilityFactoryScript.create_fallback_ability()

	var ability_id: String = String(ability_ids[next_ability_index])
	next_ability_index = (next_ability_index + 1) % ability_ids.size()

	return BossAbilityFactoryScript.create_ability_from_id(ability_id)
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
	if target == null:
		return false

	if not is_instance_valid(target):
		return false

	if target.has_method("is_alive"):
		return target.is_alive()

	return true

func set_target(new_target: Node2D):
	if is_dead:
		return

	target = new_target

	if target != null:
		print("Boss target set to:", target.name)

func clear_target():
	target = null
	velocity = Vector2.ZERO

func get_current_target() -> Node2D:
	if has_valid_target():
		return target

	return null
func set_party_members(new_party_members: Array) -> void:
	party_members = new_party_members
func chase_target():
	if not has_valid_target():
		return

	var direction := global_position.direction_to(target.global_position)
	velocity = direction * speed

func auto_attack():
	if attack_timer > 0:
		return

	if not has_valid_target():
		return

	attack_timer = attack_cooldown
	print("Boss auto attacks:", target.name)

	if target.has_method("take_damage"):
		target.take_damage(attack_damage)

func start_special_cast():
	if is_casting:
		return

	if next_ability == null:
		next_ability = create_next_ability()

	if not next_ability.can_cast(self, party_members):
		special_timer = get_next_ability_cooldown()
		return

	current_ability = next_ability
	next_ability = create_next_ability()

	is_casting = true
	cast_timer = current_ability.cast_time
	current_cast_elapsed = 0.0

	current_ability.on_cast_start(self, party_members)

	update_cast_bar()

	if current_ability.interruptible:
		print("Boss begins casting", current_ability.get_cast_name(), "Interrupt now!")
	else:
		print("Boss begins casting", current_ability.get_cast_name(), "This cast cannot be interrupted.")

func update_special_cast(delta):
	cast_timer -= delta
	current_cast_elapsed += delta

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
		special_timer = current_ability.cooldown
		print("Boss finishes", current_ability.get_cast_name())
		current_ability.resolve(self, party_members)
	else:
		special_timer = get_next_ability_cooldown()

	current_ability = null
	current_cast_elapsed = 0.0
	update_cast_bar()
func cancel_current_cast_due_to_missing_target() -> void:
	if not is_casting:
		return

	is_casting = false
	cast_timer = 0.0
	current_cast_elapsed = 0.0

	if current_ability != null:
		current_ability.on_interrupted(self, party_members)
		special_timer = current_ability.cooldown
	else:
		special_timer = get_next_ability_cooldown()

	current_ability = null
	update_cast_bar()

	print("Boss cast cancelled because its target is no longer valid.")
func interrupt_cast() -> bool:
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
			special_timer = current_ability.cooldown
		else:
			special_timer = get_next_ability_cooldown()

		current_ability = null
		update_cast_bar()
		print("Boss cast interrupted!")
		return true

	print("Boss is not casting anything interruptible.")
	return false

func take_damage(amount: int):
	if is_dead:
		return

	health -= amount
	health = max(health, 0)
	update_health_bar()

	print("Boss took", amount, "damage. HP:", health)

	if health <= 0:
		die()

func die():
	if is_dead:
		return

	is_dead = true
	health = 0
	update_health_bar()

	is_casting = false
	cast_timer = 0.0
	current_cast_elapsed = 0.0
	current_ability = null
	update_cast_bar()
	clear_target()

	print("Boss defeated!")
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
	health = max_health
	clear_target()

	is_casting = false
	current_ability = null
	next_ability_index = 0
	next_ability = create_next_ability()

	attack_timer = attack_cooldown
	special_timer = get_next_ability_cooldown()
	cast_timer = 0.0
	current_cast_elapsed = 0.0

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

	if target != null and is_instance_valid(target):
		if target.has_method("is_alive") and target.is_alive():
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
		return next_ability.cooldown

	return special_cast_interval
func get_display_name() -> String:
	return boss_display_name
	
func get_current_cast_time() -> float:
	if current_ability != null:
		return current_ability.get_cast_bar_max_time(
			current_cast_elapsed,
			maxf(cast_timer, 0.0)
		)

	return special_cast_time
func get_current_cast_bar_value() -> float:
	if current_ability != null:
		return current_ability.get_cast_bar_value(
			current_cast_elapsed,
			maxf(cast_timer, 0.0)
		)

	return clampf(special_cast_time - cast_timer, 0.0, special_cast_time)	
func _draw() -> void:
	if show_debug_range_rings:
		draw_debug_range_boundaries()

	if show_debug_region_guides:
		draw_debug_region_boundaries()

func draw_debug_region_boundaries() -> void:
	var max_apothem: float = get_debug_max_range_apothem()

	# Extend slightly beyond the outer debug octagon for readability.
	var extended_apothem: float = max_apothem + 80.0
	var max_circumradius: float = get_octagon_circumradius_from_apothem(extended_apothem)

	for i in range(8):
		var boundary_direction: Vector2 = get_region_boundary_direction(i)

		draw_line(
			Vector2.ZERO,
			boundary_direction * max_circumradius,
			Color(1.0, 1.0, 1.0, 0.55),
			2.0
		)

func draw_debug_range_boundaries() -> void:
	var boss_apothem: float = combat_radius
	var close_mid_boundary_apothem: float = get_range_boundary_apothem(
		MovementSlotResolverScript.RANGE_CLOSE,
		MovementSlotResolverScript.RANGE_MID
	)
	var mid_far_boundary_apothem: float = get_range_boundary_apothem(
		MovementSlotResolverScript.RANGE_MID,
		MovementSlotResolverScript.RANGE_FAR
	)
	var debug_outer_apothem: float = get_debug_max_range_apothem()

	# Boss edge
	draw_octagon_outline(boss_apothem, Color(1, 1, 1, 0.45), 2.0)

	# Close / Mid boundary
	draw_octagon_outline(close_mid_boundary_apothem, Color(0.2, 1.0, 0.2, 0.55), 2.0)

	# Mid / Far boundary
	draw_octagon_outline(mid_far_boundary_apothem, Color(1.0, 1.0, 0.2, 0.55), 2.0)

	# Extra outer debug limit at 50 range units
	draw_octagon_outline(debug_outer_apothem, Color(0.2, 0.6, 1.0, 0.65), 2.0)
func get_range_boundary_apothem(range_a: String, range_b: String) -> float:
	var offset_a_units: float = MovementSlotResolverScript.get_range_offset_units(range_a)
	var offset_b_units: float = MovementSlotResolverScript.get_range_offset_units(range_b)

	var boundary_offset_units: float = (offset_a_units + offset_b_units) * 0.5
	var boundary_offset_pixels: float = CombatMeasurementsScript.range_units_to_pixels(boundary_offset_units)

	return combat_radius + boundary_offset_pixels


func draw_octagon_outline(apothem: float, color: Color, width: float = 2.0) -> void:
	var points: PackedVector2Array = get_octagon_points_from_apothem(apothem)

	if points.size() < 2:
		return

	var closed_points := PackedVector2Array(points)
	closed_points.append(points[0])

	draw_polyline(closed_points, color, width, true)


func get_octagon_points_from_apothem(apothem: float) -> PackedVector2Array:
	var points := PackedVector2Array()

	if apothem <= 0.0:
		return points

	var circumradius: float = get_octagon_circumradius_from_apothem(apothem)

	for i in range(8):
		var boundary_direction: Vector2 = get_region_boundary_direction(i)
		points.append(boundary_direction * circumradius)

	return points


func get_octagon_circumradius_from_apothem(apothem: float) -> float:
	return apothem / cos(PI / 8.0)


func get_region_boundary_direction(index: int) -> Vector2:
	var start_angle: float = -PI / 2.0 - PI / 8.0
	var step_angle: float = TAU / 8.0
	var angle: float = start_angle + step_angle * float(index)

	return Vector2.RIGHT.rotated(angle)
func get_debug_max_range_apothem() -> float:
	var debug_offset_pixels: float = CombatMeasurementsScript.range_units_to_pixels(debug_max_range_units)
	return combat_radius + debug_offset_pixels
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
