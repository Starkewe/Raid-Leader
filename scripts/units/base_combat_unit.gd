extends CharacterBody2D

class_name BaseCombatUnit

signal defeated(unit)

@export var max_health: int = 100
@export var speed: float = 160.0
@export var show_world_health_bar: bool = false
@export var manual_move_stop_distance: float = 12.0

@onready var health_bar = get_node_or_null("HealthBar")

var health: int = 0
var is_dead: bool = false

var unit_class: String = ""
var unit_number: int = 0
var display_name: String = ""

var has_manual_move_order: bool = false
var manual_move_destination: Vector2 = Vector2.ZERO


func _ready():
	health = max_health
	update_health_bar()


# -------------------------------------------------------------------
# Health / death
# -------------------------------------------------------------------

func take_damage(amount: int):
	if is_dead:
		return

	health -= amount
	health = max(health, 0)

	update_health_bar()

	print(get_display_name(), "took", amount, "damage. HP:", health)

	if health <= 0:
		die()


func receive_heal(amount: int):
	if is_dead:
		return

	health += amount
	health = min(health, max_health)

	update_health_bar()

	print(get_display_name(), "healed for", amount, ". HP:", health)


func die():
	if is_dead:
		return

	is_dead = true
	health = 0

	update_health_bar()
	stop_action()

	print(get_display_name(), "defeated!")

	defeated.emit(self)


func reset_unit(new_position: Vector2):
	is_dead = false
	health = max_health
	velocity = Vector2.ZERO
	global_position = new_position
	visible = true

	stop_action()
	on_reset_unit()
	update_health_bar()


func on_reset_unit():
	pass


# -------------------------------------------------------------------
# Action / movement control
# -------------------------------------------------------------------

func stop_action():
	clear_manual_move_order()
	stop_movement()


func stop_movement():
	velocity = Vector2.ZERO


func clear_manual_move_order():
	has_manual_move_order = false
	manual_move_destination = Vector2.ZERO


func command_move_to_position(destination: Vector2):
	if is_dead:
		return

	has_manual_move_order = true
	manual_move_destination = destination

	on_manual_move_started()

	print(get_display_name(), "moving to position:", destination)


func on_manual_move_started():
	pass


func update_manual_move_order() -> bool:
	if not has_manual_move_order:
		return false

	var distance := global_position.distance_to(manual_move_destination)

	if distance <= manual_move_stop_distance:
		clear_manual_move_order()
		stop_movement()
		return false

	move_toward_position(manual_move_destination)
	return true


func move_toward_position(destination: Vector2, move_speed: float = -1.0):
	var active_speed := speed

	if move_speed > 0.0:
		active_speed = move_speed

	var direction := global_position.direction_to(destination)
	velocity = direction * active_speed


func move_toward_node(target_node: Node2D, move_speed: float = -1.0):
	if not is_valid_node(target_node):
		stop_movement()
		return

	move_toward_position(target_node.global_position, move_speed)


func move_away_from_node(target_node: Node2D, move_speed: float = -1.0):
	if not is_valid_node(target_node):
		stop_movement()
		return

	var active_speed := speed

	if move_speed > 0.0:
		active_speed = move_speed

	var direction := target_node.global_position.direction_to(global_position)
	velocity = direction * active_speed


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

	return global_position.distance_to(target_node.global_position)


func is_node_in_range(target_node: Node2D, check_range: float) -> bool:
	return get_distance_to_node(target_node) <= check_range


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
