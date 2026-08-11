extends RefCounted
class_name DirectionalSpriteController

const DIRECTION_COUNT := 8
const DIRECTION_STEP_RADIANS := PI / 4.0
const DIRECTION_HALF_STEP_RADIANS := DIRECTION_STEP_RADIANS / 2.0
const DIRECTION_HYSTERESIS_RADIANS := 4.0 * PI / 180.0
const MIN_MOVEMENT_DISPLACEMENT_SQUARED := 0.01

var sprite: Sprite2D = null
var textures: Dictionary = {}
var current_direction: int = 2
var last_movement_direction: int = 2
var was_moving_last_frame: bool = false


func configure_textures(
	new_sprite: Sprite2D, source: Dictionary, initial_direction: int = 2
) -> void:
	sprite = new_sprite
	textures = source.duplicate()
	current_direction = initial_direction
	last_movement_direction = initial_direction
	set_direction(initial_direction)


func configure_texture_paths(
	new_sprite: Sprite2D, paths: Dictionary, profile_name: String,
	initial_direction: int = 2
) -> void:
	var loaded: Dictionary = {}
	for direction in paths:
		var texture_path := String(paths[direction])
		if not ResourceLoader.exists(texture_path, "Texture2D"):
			push_warning(profile_name + " directional sprite is missing: " + texture_path)
			continue
		var texture := ResourceLoader.load(texture_path, "Texture2D") as Texture2D
		if texture == null:
			push_warning(profile_name + " directional sprite could not be loaded: " + texture_path)
			continue
		loaded[direction] = texture
	configure_textures(new_sprite, loaded, initial_direction)


func update(
	owner_position: Vector2, facing_target: Node2D, displacement: Vector2
) -> void:
	if displacement.length_squared() >= MIN_MOVEMENT_DISPLACEMENT_SQUARED:
		last_movement_direction = resolve_direction(
			displacement, last_movement_direction, true
		)
		was_moving_last_frame = true
		set_direction(last_movement_direction)
		return

	if facing_target == null or not is_instance_valid(facing_target):
		was_moving_last_frame = false
		return

	var target_direction := facing_target.global_position - owner_position
	if target_direction.is_zero_approx():
		was_moving_last_frame = false
		return

	var idle_direction := resolve_direction(
		target_direction, current_direction, not was_moving_last_frame
	)
	was_moving_last_frame = false
	set_direction(idle_direction)


func set_direction(direction: int) -> void:
	if sprite == null:
		return
	var next_texture := textures.get(direction) as Texture2D
	if next_texture == null:
		return
	if current_direction == direction and sprite.texture == next_texture:
		return
	current_direction = direction
	sprite.texture = next_texture


func get_texture(direction: int) -> Texture2D:
	return textures.get(direction) as Texture2D


static func resolve_direction(
	direction_vector: Vector2, previous_direction: int, apply_hysteresis: bool
) -> int:
	if direction_vector.is_zero_approx():
		return previous_direction
	var vector_angle := direction_vector.angle()
	var direction := wrapi(
		floori((vector_angle + DIRECTION_HALF_STEP_RADIANS) / DIRECTION_STEP_RADIANS),
		0, DIRECTION_COUNT
	)
	if apply_hysteresis and direction != previous_direction:
		var previous_angle := float(previous_direction) * DIRECTION_STEP_RADIANS
		var angle_from_previous := absf(wrapf(vector_angle - previous_angle, -PI, PI))
		if angle_from_previous <= DIRECTION_HALF_STEP_RADIANS + DIRECTION_HYSTERESIS_RADIANS:
			return previous_direction
	return direction
