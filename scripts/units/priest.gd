extends BaseCombatUnit

class_name Priest

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
	FacingDirection.NORTH: "res://assets/units/priest/priest_north.png",
	FacingDirection.NORTHEAST: "res://assets/units/priest/priest_northeast.png",
	FacingDirection.EAST: "res://assets/units/priest/priest_east.png",
	FacingDirection.SOUTHEAST: "res://assets/units/priest/priest_southeast.png",
	FacingDirection.SOUTH: "res://assets/units/priest/priest_south.png",
	FacingDirection.SOUTHWEST: "res://assets/units/priest/priest_southwest.png",
	FacingDirection.WEST: "res://assets/units/priest/priest_west.png",
	FacingDirection.NORTHWEST: "res://assets/units/priest/priest_northwest.png",
}

const HealingTargetSelectorScript := preload(
	"res://scripts/combat/healing_target_selector.gd"
)

var cast_range_units: float = 40.0

var heal_amount: int = 15
var heal_cooldown: float = 1.0
var heal_cast_time: float = 1.5
var cure_range_units: float = 40.0
var cure_cooldown: float = 0.5
var cure_cast_time: float = 1.0
@export var show_world_cast_bar: bool = false

@onready var combat_sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var cast_bar = get_node_or_null("CastBar")

var heal_target: Node2D = null
var cure_target: Node2D = null
var combat_facing_target: Node2D = null
var healing_scope: Dictionary = {}
var healing_target_selector = null
var heal_target_is_fallback: bool = false

var cooldown_timer: float = 0.0
var cure_cooldown_timer: float = 0.0
var cast_timer: float = 0.0
var is_casting: bool = false
var active_cast_kind: String = ""
var pending_heal_id: String = ""
var pending_heal_target: Node = null
var heal_cast_sequence: int = 0
var heal_ability_id: String = "heal"
var heal_display_name: String = "Heal"
var cure_ability_id: String = "cure"
var cure_display_name: String = "Cure"
var facing_textures: Dictionary = {}
var current_facing_direction: int = FacingDirection.SOUTH
var last_movement_direction: int = FacingDirection.SOUTH
var was_moving_last_frame: bool = false


func configure_from_definition(definition: UnitDefinition) -> void:
	super.configure_from_definition(definition)

	if definition == null:
		return

	var action := definition.get_action(heal_ability_id)
	var cure_action := definition.get_action(cure_ability_id)

	if action != null:
		heal_display_name = action.display_name
		cast_range_units = action.range_units
		heal_amount = action.amount
		heal_cooldown = action.cooldown
		heal_cast_time = action.cast_time

	if cure_action != null:
		cure_display_name = cure_action.display_name
		cure_range_units = cure_action.range_units
		cure_cooldown = cure_action.cooldown
		cure_cast_time = cure_action.cast_time


func _ready():
	super._ready()
	_load_facing_textures()
	_set_facing_direction(FacingDirection.SOUTH)
	update_cast_bar()
	print("Priest ready. HP:", health)


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

	if cure_target != null and not has_valid_cure_target():
		cure_target = null

	if has_valid_cure_target():
		handle_cure_positioning()
		_finish_movement_step(step_start_position)
		return

	refresh_heal_target_for_assignment()

	if not has_valid_heal_target():
		stop_movement()
		_finish_movement_step(step_start_position)
		return

	handle_heal_positioning()

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
			push_warning("Priest directional sprite is missing: " + texture_path)
			continue

		var texture := ResourceLoader.load(texture_path, "Texture2D") as Texture2D

		if texture == null:
			push_warning("Priest directional sprite could not be loaded: " + texture_path)
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


func command_heal(new_target: Node2D) -> bool:
	if is_dead:
		return false

	if not can_heal_target(new_target):
		stop_action()
		print(get_display_name(), "received invalid heal target.")
		return false

	var direct_selector = HealingTargetSelectorScript.new()
	direct_selector.setup([new_target], [])
	return command_heal_scope(
		{
			"type": "unit",
			"value": get_node_display_name(new_target),
			"unit": new_target
		},
		direct_selector
	)


func command_heal_scope(new_scope: Dictionary, new_target_selector) -> bool:
	if is_dead or new_scope.is_empty() or new_target_selector == null:
		return false

	if not new_target_selector.is_valid_scope(new_scope):
		return false

	if active_cast_kind != "cure":
		cancel_current_cast()

	super.stop_action()
	healing_scope = new_scope.duplicate(true)
	healing_target_selector = new_target_selector
	heal_target = null
	heal_target_is_fallback = false
	refresh_heal_target_for_assignment(true)

	print(
		get_display_name(),
		"assigned to heal ",
		healing_target_selector.get_scope_label(healing_scope)
	)
	return true


func command_cure(new_target: Node2D) -> bool:
	if is_dead or not is_valid_living_node(new_target):
		return false

	if not new_target.has_method("has_dispellable_status"):
		return false

	if not bool(new_target.has_dispellable_status("cure")):
		return false

	cancel_current_cast()
	cure_target = new_target
	print(get_display_name(), "ordered to cure:", get_node_display_name(cure_target))
	return true


func update_cooldown(delta: float):
	cooldown_timer = max(cooldown_timer - delta, 0.0)
	cure_cooldown_timer = max(cure_cooldown_timer - delta, 0.0)


func has_valid_heal_target() -> bool:
	return can_heal_target(heal_target)


func has_healing_assignment() -> bool:
	return not healing_scope.is_empty() and healing_target_selector != null


func refresh_heal_target_for_assignment(force_reselect: bool = false) -> void:
	if not has_healing_assignment():
		heal_target = null
		heal_target_is_fallback = false
		return

	if (
		not force_reselect
		and has_valid_heal_target()
		and healing_target_selector.is_target_eligible(
			healing_scope,
			heal_target,
			self,
			heal_target_is_fallback,
			cast_range_units
		)
	):
		return

	var selection: Dictionary = healing_target_selector.select_target(
		healing_scope,
		self,
		true,
		cast_range_units
	)
	var selected_target = selection.get("target", null)
	heal_target = selected_target as Node2D if selected_target is Node2D else null
	heal_target_is_fallback = bool(selection.get("is_fallback", false))


func has_valid_cure_target() -> bool:
	if not is_valid_living_node(cure_target):
		return false

	if not cure_target.has_method("has_dispellable_status"):
		return false

	return bool(cure_target.has_dispellable_status("cure"))


func handle_active_cast(delta: float):
	stop_movement()

	if active_cast_kind == "cure" and not has_valid_cure_target():
		cure_target = null
		cancel_current_cast()
		return

	if active_cast_kind != "cure" and not has_valid_heal_target():
		cancel_current_cast()
		return

	update_cast(delta)


func handle_heal_positioning() -> void:
	if not is_valid_node(heal_target):
		stop_movement()
		return

	if heal_target == self:
		stop_movement()
		try_start_cast()
		return

	var distance_units: float = get_range_units_to_node(heal_target)

	if distance_units > cast_range_units:
		move_toward_node(heal_target)
		return

	stop_movement()
	try_start_cast()


func handle_cure_positioning() -> void:
	if not is_valid_node(cure_target):
		cure_target = null
		stop_movement()
		return

	if cure_target != self and get_range_units_to_node(cure_target) > cure_range_units:
		move_toward_node(cure_target)
		return

	stop_movement()
	try_start_cure_cast()

func try_start_cast():
	if cooldown_timer > 0.0:
		return

	var previous_target := heal_target
	refresh_heal_target_for_assignment(true)

	if heal_target != previous_target:
		return

	if not has_valid_heal_target():
		return

	if not healing_target_selector.is_target_eligible(
		healing_scope,
		heal_target,
		self,
		heal_target_is_fallback,
		cast_range_units
	):
		heal_target = null
		heal_target_is_fallback = false
		return

	is_casting = true
	active_cast_kind = "heal"
	cast_timer = heal_cast_time
	register_pending_heal_prediction()

	update_cast_bar()

	print(get_display_name(), "begins casting ", heal_display_name)


func try_start_cure_cast() -> void:
	if cure_cooldown_timer > 0.0 or not has_valid_cure_target():
		return

	is_casting = true
	active_cast_kind = "cure"
	cast_timer = cure_cast_time
	update_cast_bar()
	print(get_display_name(), "begins casting ", cure_display_name)


func update_cast(delta: float):
	cast_timer = max(cast_timer - delta, 0.0)

	update_cast_bar()

	if cast_timer <= 0.0:
		finish_cast()


func finish_cast():
	is_casting = false

	if active_cast_kind == "cure":
		finish_cure_cast()
		return

	var completed_target := heal_target
	clear_pending_heal_prediction()
	cooldown_timer = heal_cooldown

	update_cast_bar()

	print(get_display_name(), "finishes ", heal_display_name)

	if not can_heal_target(completed_target):
		print(get_display_name(), "finished ", heal_display_name, ", but the target is no longer valid.")
		active_cast_kind = ""
		return

	completed_target.receive_heal(heal_amount, self, heal_ability_id)
	heal_target = null
	heal_target_is_fallback = false
	active_cast_kind = ""


func finish_cure_cast() -> void:
	cure_cooldown_timer = cure_cooldown
	update_cast_bar()

	if not has_valid_cure_target():
		print(get_display_name(), "finished ", cure_display_name, ", but the target is no longer curable.")
		cure_target = null
		active_cast_kind = ""
		return

	var completed_target := cure_target
	var removed_effects: Array[String] = completed_target.clear_dispellable_statuses("cure", 1)
	print(
		get_display_name(),
		"cures ",
		get_node_display_name(completed_target),
		" of ",
		removed_effects
	)

	if completed_target.has_method("emit_combat_event"):
		completed_target.emit_combat_event(
			"dispel",
			self,
			cure_ability_id,
			removed_effects.size(),
			{"removed_effects": removed_effects}
		)

	cure_target = null
	active_cast_kind = ""


func cancel_current_cast():
	if not is_casting and cast_timer <= 0.0:
		clear_pending_heal_prediction()
		return

	is_casting = false
	cast_timer = 0.0
	clear_pending_heal_prediction()

	update_cast_bar()

	var cancelled_name := cure_display_name if active_cast_kind == "cure" else heal_display_name
	active_cast_kind = ""
	print(get_display_name(), "cancels ", cancelled_name)


func on_manual_move_started():
	cancel_current_cast()


func stop_action():
	healing_scope.clear()
	healing_target_selector = null
	heal_target_is_fallback = false
	heal_target = null
	cure_target = null
	cancel_current_cast()
	super.stop_action()


func on_reset_unit():
	clear_pending_heal_prediction()
	healing_scope.clear()
	healing_target_selector = null
	heal_target_is_fallback = false
	heal_target = null
	cure_target = null
	cooldown_timer = 0.0
	cure_cooldown_timer = 0.0
	cast_timer = 0.0
	is_casting = false
	active_cast_kind = ""

	update_cast_bar()


func register_pending_heal_prediction() -> void:
	clear_pending_heal_prediction()

	if active_cast_kind != "heal" or not can_heal_target(heal_target):
		return

	heal_cast_sequence += 1
	pending_heal_id = (
		"heal:"
		+ str(get_instance_id())
		+ ":"
		+ str(heal_cast_sequence)
	)
	pending_heal_target = heal_target

	if pending_heal_target.has_method("register_pending_heal"):
		pending_heal_target.register_pending_heal(
			pending_heal_id,
			self,
			heal_amount
		)


func clear_pending_heal_prediction() -> void:
	if (
		not pending_heal_id.is_empty()
		and pending_heal_target != null
		and is_instance_valid(pending_heal_target)
		and pending_heal_target.has_method("remove_pending_heal")
	):
		pending_heal_target.remove_pending_heal(pending_heal_id)

	pending_heal_id = ""
	pending_heal_target = null


func update_cast_bar():
	if cast_bar == null:
		return

	if not show_world_cast_bar:
		cast_bar.visible = false
		cast_bar.value = 0
		return

	var active_cast_time := cure_cast_time if active_cast_kind == "cure" else heal_cast_time
	cast_bar.max_value = active_cast_time

	if is_casting:
		cast_bar.visible = true
		cast_bar.value = active_cast_time - cast_timer
	else:
		cast_bar.visible = false
		cast_bar.value = 0


func is_casting_ability() -> bool:
	return is_casting


func get_cast_progress_percent() -> float:
	if not is_casting:
		return 0.0

	var active_cast_time := cure_cast_time if active_cast_kind == "cure" else heal_cast_time

	if active_cast_time <= 0.0:
		return 0.0

	return clamp(((active_cast_time - cast_timer) / active_cast_time) * 100.0, 0.0, 100.0)


func get_cast_name() -> String:
	if is_casting:
		return cure_display_name if active_cast_kind == "cure" else heal_display_name

	return ""


func get_status_text() -> String:
	var shared_status := get_shared_status_text()

	if shared_status != "":
		return shared_status

	if is_casting:
		return "Casting " + get_cast_name()

	if has_valid_cure_target():
		return "Curing " + get_node_display_name(cure_target)

	if has_valid_heal_target():
		if heal_target.has_method("is_full_health") and heal_target.is_full_health():
			return "Watching " + get_node_display_name(heal_target)

		if heal_target == self:
			return "Healing Self"

		var distance_units: float = get_range_units_to_node(heal_target)

		if distance_units > cast_range_units:
			return "Moving to " + get_node_display_name(heal_target)

		if cooldown_timer > 0.0:
			return "Recovering"

		return "Healing " + get_node_display_name(heal_target)

	if has_healing_assignment():
		return (
			"Watching "
			+ healing_target_selector.get_scope_label(healing_scope)
		)

	return "Idle"
