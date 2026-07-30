extends BaseCombatUnit

class_name Rogue

enum FacingDirection {
	EAST,
	SOUTHEAST,
	SOUTH,
	SOUTHWEST,
	WEST,
	NORTHWEST,
	NORTH,
	NORTHEAST,
}

const DIRECTION_STEP_RADIANS := PI / 4.0
const DIRECTION_HALF_STEP_RADIANS := DIRECTION_STEP_RADIANS / 2.0
const DIRECTION_HYSTERESIS_RADIANS := 4.0 * PI / 180.0
const MIN_MOVEMENT_DISPLACEMENT := 0.1
const MIN_MOVEMENT_DISPLACEMENT_SQUARED := (
	MIN_MOVEMENT_DISPLACEMENT * MIN_MOVEMENT_DISPLACEMENT
)
const FACING_TEXTURES := {
	FacingDirection.NORTH: preload("res://assets/units/rogue/rogue_north.png"),
	FacingDirection.NORTHEAST: preload("res://assets/units/rogue/rogue_northeast.png"),
	FacingDirection.EAST: preload("res://assets/units/rogue/rogue_east.png"),
	FacingDirection.SOUTHEAST: preload("res://assets/units/rogue/rogue_southeast.png"),
	FacingDirection.SOUTH: preload("res://assets/units/rogue/rogue_south.png"),
	FacingDirection.SOUTHWEST: preload("res://assets/units/rogue/rogue_southwest.png"),
	FacingDirection.WEST: preload("res://assets/units/rogue/rogue_west.png"),
	FacingDirection.NORTHWEST: preload("res://assets/units/rogue/rogue_northwest.png"),
}

var attack_range_units: float = 5.0
var stop_distance_units: float = 5.0
var attack_damage: int = 8
var attack_cooldown: float = 0.8
var interrupt_range_units: float = 5.0
var interrupt_cooldown: float = 3.0

@onready var combat_sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

var attack_target_node: Node2D = null
var interrupt_target: Node2D = null
var combat_facing_target: Node2D = null

var attack_timer: float = 0.0
var interrupt_timer: float = 0.0
var attack_ability_id: String = "rogue_attack"
var interrupt_ability_id: String = "interrupt"
var current_facing_direction: int = FacingDirection.SOUTH
var last_movement_direction: int = FacingDirection.SOUTH
var was_moving_last_frame: bool = false


func configure_from_definition(definition: UnitDefinition) -> void:
	super.configure_from_definition(definition)

	if definition == null:
		return

	var attack_action := definition.get_action(attack_ability_id)
	var interrupt_action := definition.get_action(interrupt_ability_id)

	if attack_action != null:
		attack_range_units = attack_action.range_units
		stop_distance_units = attack_action.stop_distance_units
		attack_damage = attack_action.amount
		attack_cooldown = attack_action.cooldown

	if interrupt_action != null:
		interrupt_range_units = interrupt_action.range_units
		interrupt_cooldown = interrupt_action.cooldown


func _ready():
	super._ready()
	_set_facing_direction(FacingDirection.SOUTH)
	print("Rogue ready. HP:", health)


func _physics_process(delta):
	var step_start_position := global_position

	if is_dead:
		stop_movement()
		move_and_slide()
		return

	update_cooldowns(delta)

	if update_forced_movement(delta):
		_finish_movement_step(step_start_position)
		return

	if update_manual_move_order(delta):
		_finish_movement_step(step_start_position)
		return

	if not has_valid_attack_target():
		stop_attack_only()
		_finish_movement_step(step_start_position)
		return

	handle_attack_movement()

	_finish_movement_step(step_start_position)


func _finish_movement_step(step_start_position: Vector2) -> void:
	move_and_slide()
	_update_combat_facing_from_displacement(global_position - step_start_position)


func set_combat_facing_target(new_target: Node2D) -> void:
	combat_facing_target = new_target
	_update_combat_facing_from_displacement(Vector2.ZERO)


func _update_combat_facing_from_displacement(displacement: Vector2) -> void:
	if displacement.length_squared() >= MIN_MOVEMENT_DISPLACEMENT_SQUARED:
		var movement_direction := _resolve_facing_direction(
			displacement,
			last_movement_direction,
			true
		)
		last_movement_direction = movement_direction
		was_moving_last_frame = true
		_set_facing_direction(movement_direction)
		return

	if not is_valid_node(combat_facing_target):
		was_moving_last_frame = false
		return

	var boss_direction := (
		combat_facing_target.global_position
		- global_position
	)

	if boss_direction.is_zero_approx():
		was_moving_last_frame = false
		return

	var idle_direction := _resolve_facing_direction(
		boss_direction,
		current_facing_direction,
		not was_moving_last_frame
	)
	was_moving_last_frame = false
	_set_facing_direction(idle_direction)


func _resolve_facing_direction(
	direction_vector: Vector2,
	previous_direction: int,
	apply_hysteresis: bool
) -> int:
	if direction_vector.is_zero_approx():
		return previous_direction

	var vector_angle := direction_vector.angle()
	var direction := wrapi(
		floori(
			(vector_angle + DIRECTION_HALF_STEP_RADIANS)
			/ DIRECTION_STEP_RADIANS
		),
		0,
		FacingDirection.size()
	)

	if apply_hysteresis and direction != previous_direction:
		var previous_angle := float(previous_direction) * DIRECTION_STEP_RADIANS
		var angle_from_previous := absf(
			wrapf(vector_angle - previous_angle, -PI, PI)
		)

		if angle_from_previous <= (
			DIRECTION_HALF_STEP_RADIANS
			+ DIRECTION_HYSTERESIS_RADIANS
		):
			return previous_direction

	return direction


func _set_facing_direction(direction: int) -> void:
	if combat_sprite == null:
		return

	var next_texture := FACING_TEXTURES.get(direction) as Texture2D

	if next_texture == null:
		return

	if current_facing_direction == direction and combat_sprite.texture == next_texture:
		return

	current_facing_direction = direction
	combat_sprite.texture = next_texture


func get_facing_direction() -> int:
	return current_facing_direction


func finish_forced_movement() -> void:
	var movement_start_position := global_position
	super.finish_forced_movement()
	_update_combat_facing_from_displacement(global_position - movement_start_position)


func command_attack(new_target: Node2D):
	if is_dead:
		return

	if not can_damage_target(new_target):
		stop_action()
		return

	begin_attack_action()
	attack_target_node = new_target
	interrupt_target = new_target

	print(get_display_name(), "attacking:", get_node_display_name(attack_target_node))


func command_interrupt(new_target: Node2D):
	if is_dead:
		return

	if not can_interrupt_target(new_target):
		interrupt_target = null
		print(get_display_name(), "received invalid interrupt target.")
		return

	interrupt_target = new_target

	print(get_display_name(), "ordered to interrupt:", get_node_display_name(interrupt_target))

	if not is_node_in_range_units(interrupt_target, interrupt_range_units):
		print(get_display_name(), " is too far to interrupt.")
		return

	try_interrupt()


func update_cooldowns(delta: float):
	attack_timer = max(attack_timer - delta, 0.0)
	interrupt_timer = max(interrupt_timer - delta, 0.0)


func has_valid_attack_target() -> bool:
	return is_attack_action_active() and can_damage_target(attack_target_node)


func handle_attack_movement():
	var distance_units: float = get_range_units_to_node(attack_target_node)

	if distance_units > stop_distance_units:
		move_toward_node(attack_target_node)
		return

	stop_movement()

	if distance_units <= attack_range_units:
		attack_target()


func on_forced_movement_finished() -> void:
	if has_valid_attack_target():
		handle_attack_movement()


func attack_target():
	if attack_timer > 0.0:
		return

	if not can_damage_target(attack_target_node):
		return

	attack_timer = attack_cooldown

	print(get_display_name(), "attacks", get_node_display_name(attack_target_node))

	attack_target_node.take_damage(attack_damage, self, attack_ability_id)


func try_interrupt():
	if is_dead:
		return

	if interrupt_timer > 0.0:
		print(get_display_name(), "interrupt is on cooldown.")
		return

	if not can_interrupt_target(interrupt_target):
		interrupt_target = null
		print(get_display_name(), "has no valid interrupt target.")
		return

	if not is_node_in_range_units(interrupt_target, interrupt_range_units):
		print(get_display_name(), "is too far to interrupt.")
		return

	interrupt_timer = interrupt_cooldown

	var success: bool = interrupt_target.interrupt_cast(self, interrupt_ability_id)

	if success:
		print(get_display_name(), "successfully interrupted the cast!")
	else:
		print(get_display_name(), "used interrupt, but there was nothing to stop.")


func stop_attack_only():
	attack_target_node = null
	clear_attack_action()
	stop_movement()


func stop_action():
	attack_target_node = null
	interrupt_target = null
	super.stop_action()


func on_reset_unit():
	attack_target_node = null
	interrupt_target = null
	attack_timer = 0.0
	interrupt_timer = 0.0
	was_moving_last_frame = false
	_update_combat_facing_from_displacement(Vector2.ZERO)


func get_status_text() -> String:
	var shared_status := get_shared_status_text()

	if shared_status != "":
		return shared_status

	if has_valid_attack_target():
		return "Attacking " + get_node_display_name(attack_target_node)

	return "Idle"
