extends CharacterBody2D
class_name BaseCombatUnit

const CombatMeasurementsScript := preload("res://scripts/combat/combat_measurements.gd")
const DodgeTuningScript := preload("res://scripts/combat/dodge_tuning.gd")
const ForcedMovementControllerScript := preload("res://scripts/combat/forced_movement_controller.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")
const StatusEffectControllerScript := preload("res://scripts/combat/status_effect_controller.gd")

signal defeated(unit)
signal combat_event(event: Dictionary)

const ACTION_NONE := ""
const ACTION_ATTACK := "attack"
const ACTION_MOVE := "move"

var max_health: int = 100
var speed: float = 140.0
@export var show_world_health_bar: bool = false
@export var manual_move_stop_distance: float = 12.0

@onready var health_bar = get_node_or_null("HealthBar")

var health: int = 0
var is_dead: bool = false
var unit_definition: UnitDefinition = null
var unit_roles: Array[String] = []

var unit_class: String = ""
var unit_number: int = 0
var display_name: String = ""
var member_id: String = ""
var member_description: String = ""

var has_manual_move_order: bool = false
var manual_move_destination: Vector2 = Vector2.ZERO
var manual_move_waypoints: Array[Vector2] = []
var movement_command_id: int = 0

var active_action_kind: String = ACTION_NONE
var action_command_id: int = 0
var forced_movement_action_kind: String = ACTION_NONE
var forced_movement_action_command_id: int = -1
var commanded_hold_active: bool = false
var command_destination_boss: Node = null
var command_destination_region: String = ""
var command_destination_range: String = ""
var command_destination_key: String = ""
var command_destination_flag_position: Vector2 = Vector2.ZERO
var command_path_active: bool = false

var dodge_profile: Dictionary = {}
var dodge_base_class: String = ""
var dodge_charge_capacity: int = 0
var dodge_available_charges: int = 0
var dodge_recharge_remaining: float = 0.0
var dodge_flash_remaining: float = 0.0
var dodge_flash_segment: int = -1

var dodge_active: bool = false
var dodge_kind: String = ""
var dodge_elapsed: float = 0.0
var dodge_duration: float = 0.0
var dodge_start_position: Vector2 = Vector2.ZERO
var dodge_end_position: Vector2 = Vector2.ZERO
var dodge_source_command_id: int = -1
var dodge_pending_second_burst: bool = false
var dodge_trail: Line2D = null
var dodge_visual_node: CanvasItem = null
var dodge_visual_original_modulate: Color = Color.WHITE

var forced_movement_controller: ForcedMovementController = ForcedMovementControllerScript.new()
var status_effect_controller: StatusEffectController = StatusEffectControllerScript.new()

func _ready():
	forced_movement_controller.setup(self)
	status_effect_controller.setup(self)
	initialize_dodge_profile()

	if unit_definition == null:
		speed = CombatMeasurementsScript.get_base_movement_speed_pixels_per_second()

	health = max_health
	update_health_bar()


func _process(delta: float) -> void:
	update_status_effects(delta)

	if not is_dead:
		update_dodge_recharge(delta)


func configure_from_definition(definition: UnitDefinition) -> void:
	if definition == null:
		return

	unit_definition = definition
	max_health = definition.max_health
	speed = CombatMeasurementsScript.range_units_to_pixels(
		definition.movement_speed_range_units_per_second
	)
	unit_roles = definition.roles.duplicate()
	dodge_base_class = definition.get_base_class()


# -------------------------------------------------------------------
# Health / death
# -------------------------------------------------------------------

func take_damage(
	amount: int,
	source: Node = null,
	ability_id: String = "",
	metadata: Dictionary = {}
) -> void:
	if is_dead:
		return

	var incoming_multiplier := status_effect_controller.get_incoming_damage_multiplier()
	var adjusted_amount := int(round(float(maxi(amount, 0)) * incoming_multiplier))
	var event_metadata := metadata.duplicate(true)

	if not is_equal_approx(incoming_multiplier, 1.0):
		event_metadata["base_amount"] = maxi(amount, 0)
		event_metadata["incoming_damage_multiplier"] = incoming_multiplier

	var previous_health := health
	health -= adjusted_amount
	health = max(health, 0)
	var actual_amount := previous_health - health

	update_health_bar()
	emit_combat_event("damage", source, ability_id, actual_amount, event_metadata)

	print(get_display_name(), "took", actual_amount, "damage. HP:", health)

	if health <= 0:
		die()


func receive_heal(
	amount: int,
	source: Node = null,
	ability_id: String = "",
	metadata: Dictionary = {}
) -> void:
	if is_dead:
		return

	var previous_health := health
	health += maxi(amount, 0)
	health = min(health, max_health)
	var actual_amount := health - previous_health
	var event_metadata := metadata.duplicate(true)
	var previous_health_percent := (
		float(previous_health) / float(max_health) if max_health > 0 else 0.0
	)
	var restored_percent := float(actual_amount) / float(max_health) if max_health > 0 else 0.0
	event_metadata["previous_health"] = previous_health
	event_metadata["resulting_health"] = health
	event_metadata["max_health"] = max_health
	event_metadata["previous_health_percent"] = previous_health_percent
	event_metadata["restored_health_percent"] = restored_percent
	event_metadata["exceptional_heal"] = (
		previous_health_percent <= 0.35 and restored_percent >= 0.25
	)
	event_metadata["rescue"] = previous_health_percent <= 0.20 and health > previous_health

	update_health_bar()
	emit_combat_event("healing", source, ability_id, actual_amount, event_metadata)

	print(get_display_name(), "healed for", actual_amount, ". HP:", health)


func die():
	if is_dead:
		return

	is_dead = true
	health = 0

	update_health_bar()
	cancel_forced_movement()
	clear_all_status_effects()
	stop_action()
	clear_commanded_hold()
	cancel_active_dodge()

	print(get_display_name(), "defeated!")

	emit_combat_event("unit_defeated", null, "", 0)
	defeated.emit(self)


func reset_unit(new_position: Vector2):
	is_dead = false
	health = max_health
	velocity = Vector2.ZERO
	global_position = new_position
	visible = true

	cancel_forced_movement()
	clear_all_status_effects()
	stop_action()
	clear_commanded_hold()
	reset_dodge_state()
	on_reset_unit()
	update_health_bar()


func on_reset_unit():
	pass


# -------------------------------------------------------------------
# Action / movement control
# -------------------------------------------------------------------

func stop_action():
	if active_action_kind != ACTION_NONE or has_manual_move_order:
		action_command_id += 1

	active_action_kind = ACTION_NONE
	clear_manual_move_order()
	stop_movement()


func stop_movement():
	velocity = Vector2.ZERO


func begin_attack_action() -> void:
	action_command_id += 1
	active_action_kind = ACTION_ATTACK
	clear_manual_move_order()
	clear_commanded_hold()


func is_attack_action_active() -> bool:
	return active_action_kind == ACTION_ATTACK


func clear_attack_action() -> void:
	if is_attack_action_active():
		action_command_id += 1
		active_action_kind = ACTION_NONE


func clear_manual_move_order() -> void:
	has_manual_move_order = false
	manual_move_destination = Vector2.ZERO
	manual_move_waypoints.clear()
	clear_command_path_visual()


func command_move_to_position(
	destination: Vector2,
	command_context: Dictionary = {}
) -> void:
	if is_dead:
		return

	replace_manual_move_order([destination], command_context)
	print(get_display_name(), "moving to position:", destination)


func command_move_through_positions(
	destinations: Array[Vector2],
	command_context: Dictionary = {}
) -> void:
	if is_dead:
		return

	if destinations.is_empty():
		return

	replace_manual_move_order(destinations, command_context)
	print(get_display_name(), "moving through", manual_move_waypoints.size(), "waypoints.")


func command_dodge_to_position(
	destination: Vector2,
	command_context: Dictionary = {}
) -> void:
	if is_dead or is_forced_moving():
		return

	replace_manual_move_order([destination], command_context)
	try_start_commanded_dodge()


func command_dodge_through_positions(
	destinations: Array[Vector2],
	command_context: Dictionary = {}
) -> void:
	if is_dead or is_forced_moving() or destinations.is_empty():
		return

	replace_manual_move_order(destinations, command_context)
	try_start_commanded_dodge()


func replace_manual_move_order(
	destinations: Array[Vector2],
	command_context: Dictionary
) -> void:
	action_command_id += 1

	if is_forced_moving() or not is_attack_action_active():
		active_action_kind = ACTION_MOVE

	movement_command_id += 1
	has_manual_move_order = not destinations.is_empty()
	manual_move_waypoints.clear()

	for destination in destinations:
		manual_move_waypoints.append(destination)

	manual_move_destination = (
		manual_move_waypoints[0] if not manual_move_waypoints.is_empty() else Vector2.ZERO
	)
	commanded_hold_active = has_manual_move_order
	set_command_destination_context(command_context)
	on_manual_move_started()

func on_manual_move_started():
	pass


func update_manual_move_order(delta: float) -> bool:
	update_command_destination_arrival()

	if dodge_active:
		update_active_dodge(delta)
		update_command_destination_arrival()

		if dodge_active:
			stop_movement()
			return true

	if not has_manual_move_order:
		return false

	if manual_move_waypoints.is_empty():
		clear_manual_move_order()
		stop_movement()
		return false

	var current_destination: Vector2 = manual_move_waypoints[0]
	manual_move_destination = current_destination

	var distance: float = global_position.distance_to(current_destination)

	if distance <= manual_move_stop_distance:
		manual_move_waypoints.remove_at(0)

		if manual_move_waypoints.is_empty():
			clear_manual_move_order()
			stop_movement()
			return false

		current_destination = manual_move_waypoints[0]
		manual_move_destination = current_destination

	move_toward_position(current_destination)
	return true


func move_toward_position(destination: Vector2, move_speed: float = -1.0):
	var active_speed := get_effective_movement_speed()

	if move_speed > 0.0:
		active_speed = move_speed * get_status_movement_multiplier()

	var direction := global_position.direction_to(destination)
	velocity = direction * active_speed


func move_toward_node(target_node: Node2D, move_speed: float = -1.0):
	if not is_valid_node(target_node):
		stop_movement()
		return

	if (
		commanded_hold_active
		and not has_manual_move_order
		and not is_attack_action_active()
	):
		stop_movement()
		return

	move_toward_position(target_node.global_position, move_speed)


func move_away_from_node(target_node: Node2D, move_speed: float = -1.0):
	if not is_valid_node(target_node):
		stop_movement()
		return

	var active_speed := get_effective_movement_speed()

	if move_speed > 0.0:
		active_speed = move_speed * get_status_movement_multiplier()

	var direction := target_node.global_position.direction_to(global_position)
	velocity = direction * active_speed


func initialize_dodge_profile() -> void:
	if dodge_base_class.is_empty() and unit_definition != null:
		dodge_base_class = unit_definition.get_base_class()

	dodge_profile = DodgeTuningScript.get_profile(dodge_base_class)
	dodge_charge_capacity = int(dodge_profile.get("charges", 0))
	dodge_available_charges = dodge_charge_capacity
	dodge_recharge_remaining = 0.0
	dodge_flash_remaining = 0.0
	dodge_flash_segment = -1


func reset_dodge_state() -> void:
	cancel_active_dodge()

	if dodge_profile.is_empty():
		initialize_dodge_profile()
	else:
		dodge_available_charges = dodge_charge_capacity
		dodge_recharge_remaining = 0.0
		dodge_flash_remaining = 0.0
		dodge_flash_segment = -1


func try_start_commanded_dodge() -> bool:
	if dodge_active or not has_manual_move_order:
		return false

	if dodge_available_charges <= 0 or dodge_profile.is_empty():
		return false

	var final_destination := manual_move_waypoints[manual_move_waypoints.size() - 1]
	var initial_distance := global_position.distance_to(final_destination)
	var second_dash_threshold := (
		DodgeTuningScript.get_mini_region_spacing_pixels()
		* DodgeTuningScript.ROGUE_SECOND_DASH_THRESHOLD_SPACINGS
	)
	var should_double_dash := (
		dodge_base_class.to_lower() == "rogue"
		and dodge_available_charges >= 2
		and initial_distance > second_dash_threshold
	)

	return start_dodge_burst(movement_command_id, should_double_dash)


func start_dodge_burst(source_command_id: int, allow_second_burst: bool) -> bool:
	if dodge_available_charges <= 0 or manual_move_waypoints.is_empty():
		return false

	var current_destination := manual_move_waypoints[0]
	var remaining_distance := global_position.distance_to(current_destination)

	if remaining_distance <= 0.01:
		return false

	spend_dodge_charge()
	dodge_active = true
	dodge_kind = String(dodge_profile.get("movement_type", DodgeTuningScript.MOVEMENT_PHYSICAL))
	dodge_elapsed = 0.0
	dodge_duration = maxf(float(dodge_profile.get("duration", 0.0)), 0.001)
	dodge_start_position = global_position
	dodge_source_command_id = source_command_id
	dodge_pending_second_burst = allow_second_burst
	stop_movement()

	var maximum_distance := (
		DodgeTuningScript.get_mini_region_spacing_pixels()
		* float(dodge_profile.get("distance_spacings", 0.0))
	)
	var requested_distance := minf(maximum_distance, remaining_distance)
	var requested_motion := global_position.direction_to(current_destination) * requested_distance
	dodge_end_position = resolve_valid_burst_endpoint(requested_motion)

	if dodge_kind == DodgeTuningScript.MOVEMENT_TELEPORT:
		begin_teleport_visual()
		global_position = dodge_end_position
		spawn_teleport_pulse(global_position)
	else:
		begin_dash_trail()

	print(
		get_display_name(),
		" uses dodge. Charges remaining: ",
		dodge_available_charges
	)
	return true


func update_active_dodge(delta: float) -> void:
	if not dodge_active:
		return

	dodge_elapsed = minf(dodge_elapsed + delta, dodge_duration)
	var normalized_time := clampf(dodge_elapsed / dodge_duration, 0.0, 1.0)

	if dodge_kind == DodgeTuningScript.MOVEMENT_TELEPORT:
		update_teleport_visual(normalized_time)
	else:
		var eased_time: float = 1.0 - pow(
			1.0 - normalized_time,
			DodgeTuningScript.PHYSICAL_DASH_EASING_STRENGTH
		)
		var intended_position := dodge_start_position.lerp(dodge_end_position, eased_time)
		var motion := intended_position - global_position

		if not motion.is_zero_approx():
			var collision := move_and_collide(motion)

			if collision != null:
				dodge_end_position = global_position
				dodge_elapsed = dodge_duration
				normalized_time = 1.0

		update_dash_trail()

	if normalized_time < 1.0:
		return

	finish_active_dodge()


func finish_active_dodge() -> void:
	var completed_command_id := dodge_source_command_id
	var should_use_second := (
		dodge_pending_second_burst
		and completed_command_id == movement_command_id
		and dodge_available_charges > 0
	)

	finish_dodge_visual()
	dodge_active = false
	dodge_pending_second_burst = false

	if should_use_second:
		start_dodge_burst(completed_command_id, false)


func cancel_active_dodge() -> void:
	if dodge_trail != null and is_instance_valid(dodge_trail):
		dodge_trail.queue_free()

	dodge_trail = null
	restore_dodge_visual()
	dodge_active = false
	dodge_kind = ""
	dodge_elapsed = 0.0
	dodge_duration = 0.0
	dodge_source_command_id = -1
	dodge_pending_second_burst = false


func spend_dodge_charge() -> void:
	if dodge_available_charges <= 0:
		return

	dodge_available_charges -= 1

	if dodge_recharge_remaining <= 0.0:
		dodge_recharge_remaining = get_dodge_recharge_duration()


func update_dodge_recharge(delta: float) -> void:
	if dodge_charge_capacity <= 0:
		return

	if dodge_flash_remaining > 0.0:
		dodge_flash_remaining = maxf(dodge_flash_remaining - delta, 0.0)

		if dodge_flash_remaining <= 0.0:
			dodge_flash_segment = -1

	if dodge_available_charges >= dodge_charge_capacity:
		dodge_recharge_remaining = 0.0
		return

	if dodge_recharge_remaining <= 0.0:
		dodge_recharge_remaining = get_dodge_recharge_duration()

	dodge_recharge_remaining = maxf(dodge_recharge_remaining - delta, 0.0)

	if dodge_recharge_remaining > 0.0:
		return

	dodge_available_charges = mini(dodge_available_charges + 1, dodge_charge_capacity)
	dodge_flash_segment = maxi(dodge_available_charges - 1, 0)
	dodge_flash_remaining = DodgeTuningScript.RAID_FRAME_FLASH_DURATION

	if dodge_available_charges < dodge_charge_capacity:
		dodge_recharge_remaining = get_dodge_recharge_duration()


func get_dodge_recharge_duration() -> float:
	return maxf(float(dodge_profile.get("recharge", 0.0)), 0.001)


func get_dodge_charge_display() -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var recharge_progress := 0.0

	if dodge_available_charges < dodge_charge_capacity and dodge_recharge_remaining > 0.0:
		recharge_progress = clampf(
			1.0 - dodge_recharge_remaining / get_dodge_recharge_duration(),
			0.0,
			1.0
		)

	for segment_index in range(dodge_charge_capacity):
		var is_ready := segment_index < dodge_available_charges
		var fill := 1.0 if is_ready else 0.0

		if not is_ready and segment_index == dodge_available_charges:
			fill = recharge_progress

		segments.append({
			"ready": is_ready,
			"fill": fill,
			"flash": (
				segment_index == dodge_flash_segment
				and dodge_flash_remaining > 0.0
			),
			"flash_strength": (
				clampf(
					dodge_flash_remaining / DodgeTuningScript.RAID_FRAME_FLASH_DURATION,
					0.0,
					1.0
				) * DodgeTuningScript.RAID_FRAME_FLASH_STRENGTH
			)
		})

	return segments


func resolve_valid_burst_endpoint(requested_motion: Vector2) -> Vector2:
	if requested_motion.is_zero_approx():
		return global_position

	if not test_move(global_transform, requested_motion):
		return global_position + requested_motion

	var valid_fraction := 0.0
	var blocked_fraction := 1.0

	for _iteration in range(10):
		var check_fraction := (valid_fraction + blocked_fraction) * 0.5

		if test_move(global_transform, requested_motion * check_fraction):
			blocked_fraction = check_fraction
		else:
			valid_fraction = check_fraction

	return global_position + requested_motion * valid_fraction


func begin_dash_trail() -> void:
	var parent_node := get_parent()

	if not parent_node is Node2D:
		return

	dodge_trail = Line2D.new()
	dodge_trail.width = DodgeTuningScript.DASH_TRAIL_WIDTH
	dodge_trail.default_color = Color(
		1.0,
		0.9,
		0.48,
		DodgeTuningScript.DASH_TRAIL_OPACITY
	)
	dodge_trail.z_index = z_index - 1
	(parent_node as Node2D).add_child(dodge_trail)
	dodge_trail.add_point((parent_node as Node2D).to_local(dodge_start_position))
	dodge_trail.add_point((parent_node as Node2D).to_local(global_position))


func update_dash_trail() -> void:
	if dodge_trail == null or not is_instance_valid(dodge_trail):
		return

	var parent_node := dodge_trail.get_parent()

	if parent_node is Node2D:
		dodge_trail.set_point_position(1, (parent_node as Node2D).to_local(global_position))


func finish_dodge_visual() -> void:
	if dodge_kind == DodgeTuningScript.MOVEMENT_TELEPORT:
		restore_dodge_visual()
		return

	if dodge_trail == null or not is_instance_valid(dodge_trail):
		return

	var trail_to_fade := dodge_trail
	dodge_trail = null
	var tween := trail_to_fade.create_tween()
	tween.tween_property(
		trail_to_fade,
		"modulate:a",
		0.0,
		DodgeTuningScript.DASH_TRAIL_LIFETIME
	)
	tween.finished.connect(Callable(trail_to_fade, "queue_free"))


func begin_teleport_visual() -> void:
	spawn_teleport_pulse(dodge_start_position)
	dodge_visual_node = get_node_or_null("Sprite2D") as CanvasItem

	if dodge_visual_node != null:
		dodge_visual_original_modulate = dodge_visual_node.modulate
		var hidden_color := dodge_visual_original_modulate
		hidden_color.a = 0.08
		dodge_visual_node.modulate = hidden_color


func update_teleport_visual(normalized_time: float) -> void:
	if dodge_visual_node == null or not is_instance_valid(dodge_visual_node):
		return

	var visual_color := dodge_visual_original_modulate
	visual_color.a *= clampf(normalized_time, 0.08, 1.0)
	dodge_visual_node.modulate = visual_color


func restore_dodge_visual() -> void:
	if dodge_visual_node != null and is_instance_valid(dodge_visual_node):
		dodge_visual_node.modulate = dodge_visual_original_modulate

	dodge_visual_node = null


func spawn_teleport_pulse(world_position: Vector2) -> void:
	var parent_node := get_parent()

	if not parent_node is Node2D:
		return

	var pulse := Polygon2D.new()
	var points := PackedVector2Array()
	var point_count := 18

	for point_index in range(point_count):
		var angle := TAU * float(point_index) / float(point_count)
		points.append(Vector2.from_angle(angle) * DodgeTuningScript.TELEPORT_PULSE_SCALE)

	pulse.polygon = points
	pulse.color = Color(
		0.58,
		0.78,
		1.0,
		DodgeTuningScript.TELEPORT_PULSE_OPACITY
	)
	pulse.global_position = world_position
	pulse.z_index = z_index - 1
	(parent_node as Node2D).add_child(pulse)

	var tween := pulse.create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		pulse,
		"scale",
		Vector2.ONE,
		DodgeTuningScript.TELEPORT_PULSE_LIFETIME
	).from(Vector2.ONE * 0.35)
	tween.tween_property(
		pulse,
		"modulate:a",
		0.0,
		DodgeTuningScript.TELEPORT_PULSE_LIFETIME
	)
	tween.finished.connect(Callable(pulse, "queue_free"))


func set_command_destination_context(command_context: Dictionary) -> void:
	command_destination_boss = command_context.get("boss", null) as Node
	command_destination_region = String(command_context.get("destination_region", ""))
	command_destination_range = String(command_context.get("destination_range", ""))
	command_destination_key = String(command_context.get("destination_key", ""))
	var flag_position_value: Variant = command_context.get(
		"flag_position",
		manual_move_destination
	)
	command_destination_flag_position = (
		flag_position_value if flag_position_value is Vector2 else manual_move_destination
	)
	command_path_active = (
		has_manual_move_order
		and not command_destination_key.is_empty()
	)
	update_command_destination_arrival()


func update_command_destination_arrival() -> void:
	if not command_path_active or command_destination_boss == null:
		return

	if not is_instance_valid(command_destination_boss):
		clear_command_path_visual()
		return

	var current_mini_region := MovementSlotResolverScript.get_mini_region_from_position(
		command_destination_boss,
		global_position
	)

	if String(current_mini_region.get("key", "")) == command_destination_key:
		clear_command_path_visual()


func clear_command_path_visual() -> void:
	command_path_active = false


func clear_commanded_hold() -> void:
	commanded_hold_active = false
	command_destination_boss = null
	command_destination_region = ""
	command_destination_range = ""
	command_destination_key = ""
	command_destination_flag_position = Vector2.ZERO
	clear_command_path_visual()


func has_active_command_path() -> bool:
	return command_path_active and has_manual_move_order and not is_dead


func get_command_path_points() -> Array:
	var points: Array = []

	if not has_active_command_path():
		return points

	for waypoint in manual_move_waypoints:
		points.append(waypoint)

	return points


func get_command_destination_key() -> String:
	return command_destination_key


func get_command_destination_flag_position() -> Vector2:
	return command_destination_flag_position


# -------------------------------------------------------------------
# Target validation helpers
# -------------------------------------------------------------------

func is_valid_node(target_node: Node) -> bool:
	return target_node != null and is_instance_valid(target_node)


func is_valid_living_node(target_node: Node) -> bool:
	if not is_valid_node(target_node):
		return false

	if target_node.has_method("is_alive"):
		return target_node.is_alive()

	return true


func can_damage_target(target_node: Node) -> bool:
	if not is_valid_living_node(target_node):
		return false

	return target_node.has_method("take_damage")


func can_heal_target(target_node: Node) -> bool:
	if not is_valid_living_node(target_node):
		return false

	return target_node.has_method("receive_heal")


func can_interrupt_target(target_node: Node) -> bool:
	if not is_valid_living_node(target_node):
		return false

	return target_node.has_method("interrupt_cast")


func get_distance_to_node(target_node: Node2D) -> float:
	if not is_valid_node(target_node):
		return 999999.0

	var center_distance: float = global_position.distance_to(target_node.global_position)
	var target_radius: float = get_target_combat_radius(target_node)

	return maxf(center_distance - target_radius, 0.0)
func get_range_units_to_node(target_node: Node2D) -> float:
	var distance_pixels: float = get_distance_to_node(target_node)
	return CombatMeasurementsScript.pixels_to_range_units(distance_pixels)


func is_node_in_range_units(target_node: Node2D, check_range_units: float) -> bool:
	return get_range_units_to_node(target_node) <= check_range_units


func get_target_combat_radius(target_node: Node) -> float:
	if not is_valid_node(target_node):
		return 0.0

	if target_node.has_method("get_combat_radius"):
		var radius_value: Variant = target_node.get_combat_radius()
		return maxf(float(radius_value), 0.0)

	var property_value: Variant = target_node.get("combat_radius")

	if property_value == null:
		return 0.0

	return maxf(float(property_value), 0.0)
func get_node_display_name(target_node: Node) -> String:
	if not is_valid_node(target_node):
		return "Invalid Target"

	if target_node.has_method("get_display_name"):
		return target_node.get_display_name()

	return target_node.name


# -------------------------------------------------------------------
# Identity / display
# -------------------------------------------------------------------

func setup_unit_identity(new_unit_class: String, new_unit_number: int):
	unit_class = new_unit_class
	unit_number = new_unit_number
	display_name = new_unit_class + " " + str(new_unit_number)
	member_id = ""
	member_description = ""


func setup_campaign_identity(member_data: Dictionary, class_ordinal: int) -> void:
	setup_unit_identity(String(member_data.get("unit_class", "")), class_ordinal)
	member_id = String(member_data.get("member_id", ""))
	display_name = CampaignState.format_member_label(member_data)
	member_description = String(member_data.get("description", ""))


func get_member_id() -> String:
	return member_id


func get_class_ordinal() -> int:
	return unit_number


func has_role(role_name: String) -> bool:
	return unit_roles.has(role_name.to_lower().strip_edges())


func get_roles() -> Array[String]:
	return unit_roles.duplicate()


func get_display_name() -> String:
	if display_name != "":
		return display_name

	return name


func is_alive() -> bool:
	return not is_dead


func is_full_health() -> bool:
	return health >= max_health


func get_current_health() -> int:
	return health


func get_max_health() -> int:
	return max_health


# -------------------------------------------------------------------
# Cast/status hooks
# -------------------------------------------------------------------

func is_casting_ability() -> bool:
	return false


func get_cast_progress_percent() -> float:
	return 0.0


func get_cast_name() -> String:
	return ""


func get_shared_status_text() -> String:
	if is_dead:
		return "Dead"

	if is_forced_moving():
		return "Forced Movement"

	var active_status_text := status_effect_controller.get_display_text()

	if not active_status_text.is_empty():
		return active_status_text

	if has_manual_move_order:
		return "Moving"

	return ""


func get_status_text() -> String:
	var shared_status := get_shared_status_text()

	if shared_status != "":
		return shared_status

	return "Idle"


# -------------------------------------------------------------------
# Health bar
# -------------------------------------------------------------------

func update_health_bar():
	if health_bar == null:
		return

	if not show_world_health_bar:
		health_bar.visible = false
		return

	health_bar.visible = true
	health_bar.max_value = max_health
	health_bar.value = health


# -------------------------------------------------------------------
# Forced movement
# -------------------------------------------------------------------

func start_forced_movement(destination: Vector2, duration: float) -> void:
	if is_dead:
		return

	if not is_forced_moving():
		forced_movement_action_kind = active_action_kind
		forced_movement_action_command_id = action_command_id

	clear_manual_move_order()
	stop_movement()
	on_forced_movement_started()
	forced_movement_controller.start(destination, duration)


func update_forced_movement(delta: float) -> bool:
	var was_forced_moving := is_forced_moving()
	var handled_forced_movement := forced_movement_controller.update(delta)

	if was_forced_moving and not is_forced_moving():
		complete_forced_movement()

	return handled_forced_movement


func finish_forced_movement() -> void:
	var was_forced_moving := is_forced_moving()
	forced_movement_controller.finish()

	if was_forced_moving:
		complete_forced_movement()


func cancel_forced_movement() -> void:
	forced_movement_controller.cancel()
	clear_forced_movement_action()


func is_forced_moving() -> bool:
	return forced_movement_controller.active


func on_forced_movement_started() -> void:
	on_manual_move_started()


func complete_forced_movement() -> void:
	var should_restore_attack := (
		forced_movement_action_kind == ACTION_ATTACK
		and forced_movement_action_command_id == action_command_id
	)

	if should_restore_attack:
		active_action_kind = ACTION_ATTACK
		clear_commanded_hold()

	clear_forced_movement_action()
	on_forced_movement_finished()


func clear_forced_movement_action() -> void:
	forced_movement_action_kind = ACTION_NONE
	forced_movement_action_command_id = -1


func on_forced_movement_finished() -> void:
	pass


# -------------------------------------------------------------------
# Status effects
# -------------------------------------------------------------------

func apply_status_effect(definition: StatusEffectDefinition, source: Node = null) -> void:
	status_effect_controller.apply(definition, source)


func clear_status_effect(effect_id: String) -> void:
	status_effect_controller.clear(effect_id)


func clear_status_effect_from_source(effect_id: String, source: Node) -> void:
	status_effect_controller.clear_from_source(effect_id, source)


func clear_all_status_effects() -> void:
	status_effect_controller.clear_all()


func get_status_effect_stacks(effect_id: String) -> int:
	return status_effect_controller.get_stacks(effect_id)


func has_dispellable_status(dispel_category: String = "") -> bool:
	return status_effect_controller.has_dispellable(dispel_category)


func clear_dispellable_statuses(
	dispel_category: String = "",
	maximum_effects: int = 1
) -> Array[String]:
	return status_effect_controller.clear_dispellable(dispel_category, maximum_effects)


func update_status_effects(delta: float) -> void:
	status_effect_controller.update(delta)


func get_status_movement_multiplier() -> float:
	return status_effect_controller.get_movement_multiplier()


func get_effective_movement_speed() -> float:
	return speed * get_status_movement_multiplier()


# -------------------------------------------------------------------
# Combat events
# -------------------------------------------------------------------

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
