extends BaseCombatUnit

class_name Mage

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
	FacingDirection.NORTH: preload("res://assets/units/mage/mage_north.png"),
	FacingDirection.NORTHEAST: preload("res://assets/units/mage/mage_northeast.png"),
	FacingDirection.EAST: preload("res://assets/units/mage/mage_east.png"),
	FacingDirection.SOUTHEAST: preload("res://assets/units/mage/mage_southeast.png"),
	FacingDirection.SOUTH: preload("res://assets/units/mage/mage_south.png"),
	FacingDirection.SOUTHWEST: preload("res://assets/units/mage/mage_southwest.png"),
	FacingDirection.WEST: preload("res://assets/units/mage/mage_west.png"),
	FacingDirection.NORTHWEST: preload("res://assets/units/mage/mage_northwest.png"),
}

var cast_range_units: float = 40.0

var spell_damage: int = 18
var spell_cooldown: float = 1.0
var spell_cast_time: float = 1.5
@export var show_world_cast_bar: bool = false

@onready var combat_sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var cast_bar = get_node_or_null("CastBar")

var target: Node2D = null
var combat_facing_target: Node2D = null

var cooldown_timer: float = 0.0
var cast_timer: float = 0.0
var is_casting: bool = false
var spell_ability_id: String = "fireball"
var spell_display_name: String = "Fireball"
var current_facing_direction: int = FacingDirection.SOUTH
var last_movement_direction: int = FacingDirection.SOUTH
var was_moving_last_frame: bool = false


func configure_from_definition(definition: UnitDefinition) -> void:
	super.configure_from_definition(definition)

	if definition == null:
		return

	var action := definition.get_action(spell_ability_id)

	if action != null:
		spell_display_name = action.display_name
		cast_range_units = action.range_units
		spell_damage = action.amount
		spell_cooldown = action.cooldown
		spell_cast_time = action.cast_time


func _ready():
	super._ready()
	_set_facing_direction(FacingDirection.SOUTH)
	update_cast_bar()
	print("Mage ready. HP:", health)

func _physics_process(delta):
	var step_start_position := global_position

	if is_dead:
		stop_movement()
		move_and_slide()
		return

	update_cooldown(delta)

	if update_forced_movement(delta):
		_finish_movement_step(step_start_position)
		return

	if update_manual_move_order(delta):
		_finish_movement_step(step_start_position)
		return

	if is_casting:
		handle_active_cast(delta)
		_finish_movement_step(step_start_position)
		return

	if not has_valid_cast_target():
		stop_action()
		_finish_movement_step(step_start_position)
		return

	handle_cast_positioning()

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


func command_dodge_to_position(
	destination: Vector2,
	command_context: Dictionary = {}
) -> void:
	var movement_start_position := global_position
	super.command_dodge_to_position(destination, command_context)
	_update_combat_facing_from_displacement(global_position - movement_start_position)


func command_dodge_through_positions(
	destinations: Array[Vector2],
	command_context: Dictionary = {}
) -> void:
	var movement_start_position := global_position
	super.command_dodge_through_positions(destinations, command_context)
	_update_combat_facing_from_displacement(global_position - movement_start_position)


func command_attack(new_target: Node2D):
	if is_dead:
		return

	if not can_damage_target(new_target):
		stop_action()
		return

	begin_attack_action()
	target = new_target

	print(get_display_name(), "ordered to cast at:", get_node_display_name(target))


func update_cooldown(delta: float):
	cooldown_timer = max(cooldown_timer - delta, 0.0)


func has_valid_cast_target() -> bool:
	return is_attack_action_active() and can_damage_target(target)


func handle_active_cast(delta: float):
	stop_movement()

	if not has_valid_cast_target():
		cancel_current_cast()
		return

	update_cast(delta)


func handle_cast_positioning() -> void:
	if not is_valid_node(target):
		stop_movement()
		return

	var distance_units: float = get_range_units_to_node(target)

	if distance_units > cast_range_units:
		move_toward_node(target)
		return

	stop_movement()
	try_start_cast()


func on_forced_movement_finished() -> void:
	if has_valid_cast_target():
		handle_cast_positioning()


func try_start_cast():
	if cooldown_timer > 0.0:
		return

	if not has_valid_cast_target():
		return

	is_casting = true
	cast_timer = spell_cast_time

	update_cast_bar()

	print(get_display_name(), "begins casting ", spell_display_name)


func update_cast(delta: float):
	cast_timer = max(cast_timer - delta, 0.0)

	update_cast_bar()

	if cast_timer <= 0.0:
		finish_cast()


func finish_cast():
	is_casting = false
	cooldown_timer = spell_cooldown

	update_cast_bar()

	if not has_valid_cast_target():
		print(get_display_name(), "finishes ", spell_display_name, ", but the target is no longer valid.")
		return

	print(get_display_name(), "finishes ", spell_display_name, " and deals damage to ", get_node_display_name(target))

	target.take_damage(spell_damage, self, spell_ability_id)


func cancel_current_cast():
	if not is_casting and cast_timer <= 0.0:
		return

	is_casting = false
	cast_timer = 0.0

	update_cast_bar()

	print(get_display_name(), "cancels ", spell_display_name)


func on_manual_move_started():
	cancel_current_cast()


func stop_action():
	target = null
	cancel_current_cast()
	super.stop_action()


func on_reset_unit():
	target = null
	cooldown_timer = 0.0
	cast_timer = 0.0
	is_casting = false

	update_cast_bar()


func update_cast_bar():
	if cast_bar == null:
		return

	if not show_world_cast_bar:
		cast_bar.visible = false
		cast_bar.value = 0
		return

	cast_bar.max_value = spell_cast_time

	if is_casting:
		cast_bar.visible = true
		cast_bar.value = spell_cast_time - cast_timer
	else:
		cast_bar.visible = false
		cast_bar.value = 0


func is_casting_ability() -> bool:
	return is_casting


func get_cast_progress_percent() -> float:
	if not is_casting:
		return 0.0

	if spell_cast_time <= 0.0:
		return 0.0

	return clamp(((spell_cast_time - cast_timer) / spell_cast_time) * 100.0, 0.0, 100.0)


func get_cast_name() -> String:
	if is_casting:
		return spell_display_name

	return ""


func get_status_text() -> String:
	var shared_status := get_shared_status_text()

	if shared_status != "":
		return shared_status

	if is_casting:
		return "Casting " + spell_display_name

	if has_valid_cast_target():
		var distance_units: float = get_range_units_to_node(target)

		if distance_units > cast_range_units:
			return "Moving to " + get_node_display_name(target)

		if cooldown_timer > 0.0:
			return "Recovering"

		return "Ready to Cast"

	return "Idle"
