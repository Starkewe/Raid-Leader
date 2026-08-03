extends BaseCombatUnit

class_name Warrior

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
const FACING_TEXTURE_PATHS := {
	FacingDirection.NORTH: "res://assets/units/warrior/warrior_north.png",
	FacingDirection.NORTHEAST: "res://assets/units/warrior/warrior_northeast.png",
	FacingDirection.EAST: "res://assets/units/warrior/warrior_east.png",
	FacingDirection.SOUTHEAST: "res://assets/units/warrior/warrior_southeast.png",
	FacingDirection.SOUTH: "res://assets/units/warrior/warrior_south.png",
	FacingDirection.SOUTHWEST: "res://assets/units/warrior/warrior_southwest.png",
	FacingDirection.WEST: "res://assets/units/warrior/warrior_west.png",
	FacingDirection.NORTHWEST: "res://assets/units/warrior/warrior_northwest.png",
}

var attack_range_units: float = 5.0
var stop_distance_units: float = 5.0
var attack_damage: int = 10
var attack_cooldown: float = 1.0

@onready var combat_sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

var target: Node2D = null
var combat_facing_target: Node2D = null

var cooldown_timer: float = 0.0
var attack_ability_id: String = "warrior_attack"
var facing_textures: Dictionary = {}
var current_facing_direction: int = FacingDirection.SOUTH
var last_movement_direction: int = FacingDirection.SOUTH
var was_moving_last_frame: bool = false


func configure_from_definition(definition: UnitDefinition) -> void:
	super.configure_from_definition(definition)

	if definition == null:
		return

	var action := definition.get_action(attack_ability_id)

	if action != null:
		attack_range_units = action.range_units
		stop_distance_units = action.stop_distance_units
		attack_damage = action.amount
		attack_cooldown = action.cooldown


func _ready():
	super._ready()
	_load_facing_textures()
	_set_facing_direction(FacingDirection.SOUTH)
	print("Warrior ready. HP:", health)

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

	if handle_automatic_ground_hazard_escape(combat_facing_target, delta):
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


func _load_facing_textures() -> void:
	facing_textures.clear()

	for direction in FACING_TEXTURE_PATHS:
		var texture_path: String = FACING_TEXTURE_PATHS[direction]

		if not ResourceLoader.exists(texture_path, "Texture2D"):
			push_warning("Warrior directional sprite is missing: " + texture_path)
			continue

		var texture := ResourceLoader.load(texture_path, "Texture2D") as Texture2D

		if texture == null:
			push_warning("Warrior directional sprite could not be loaded: " + texture_path)
			continue

		facing_textures[direction] = texture


func _set_facing_direction(direction: int) -> void:
	if combat_sprite == null:
		return

	var next_texture := facing_textures.get(direction) as Texture2D

	if next_texture == null:
		return

	if current_facing_direction == direction and combat_sprite.texture == next_texture:
		return

	current_facing_direction = direction
	combat_sprite.texture = next_texture


func get_facing_direction() -> int:
	return current_facing_direction


func get_facing_texture(direction: int) -> Texture2D:
	return facing_textures.get(direction) as Texture2D


func finish_forced_movement() -> void:
	var movement_start_position := global_position
	super.finish_forced_movement()
	_update_combat_facing_from_displacement(global_position - movement_start_position)


func command_attack(new_target: Node2D):
	if is_dead:
		return

	if not can_damage_target(new_target):
		stop_attack_only()
		return

	begin_attack_action()
	target = new_target

	print(get_display_name(), "attacking:", get_node_display_name(target))


func update_cooldown(delta: float):
	cooldown_timer = max(cooldown_timer - delta, 0.0)


func has_valid_attack_target() -> bool:
	return is_attack_action_active() and can_damage_target(target)


func handle_attack_movement():
	var distance_units: float = get_range_units_to_node(target)

	if distance_units > stop_distance_units:
		move_toward_action_target(
			combat_facing_target,
			target,
			stop_distance_units
		)
		return

	stop_movement()

	if distance_units <= attack_range_units:
		attack_target()


func on_forced_movement_finished() -> void:
	if has_valid_attack_target():
		handle_attack_movement()


func stop_attack_only() -> void:
	target = null
	clear_attack_action()

	if not has_manual_move_order and not is_positioning_checkpoint_bound():
		stop_movement()


func attack_target():
	if cooldown_timer > 0.0:
		return

	if not can_damage_target(target):
		return

	cooldown_timer = attack_cooldown

	print(get_display_name(), "attacks", get_node_display_name(target))

	target.take_damage(attack_damage, self, attack_ability_id)


func command_taunt(new_target: Node2D) -> bool:
	if is_dead or not is_valid_living_node(new_target):
		return false

	if not is_taunt_ready():
		print(
			get_display_name(),
			"taunt is on cooldown for",
			snappedf(get_taunt_cooldown_remaining(), 0.1),
			"more second(s)."
		)
		return false

	if not new_target.has_method("taunt"):
		return false

	var success := bool(new_target.taunt(self))

	if success:
		start_taunt_cooldown()
		print(get_display_name(), "taunts", get_node_display_name(new_target))

	return success


func stop_action():
	target = null
	super.stop_action()


func on_reset_unit():
	cooldown_timer = 0.0
	target = null


func get_status_text() -> String:
	var shared_status := get_shared_status_text()

	if shared_status != "":
		return shared_status

	if has_valid_attack_target():
		return "Attacking " + get_node_display_name(target)

	return "Idle"
