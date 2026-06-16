extends CharacterBody2D
class_name BaseCombatUnit

const CombatMeasurementsScript := preload("res://scripts/combat/combat_measurements.gd")

signal defeated(unit)

@export var max_health: int = 100
@export var speed: float = 140.0
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
var manual_move_waypoints: Array[Vector2] = []

func _ready():
	speed = CombatMeasurementsScript.get_base_movement_speed_pixels_per_second()
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


func clear_manual_move_order() -> void:
	has_manual_move_order = false
	manual_move_destination = Vector2.ZERO
	manual_move_waypoints.clear()


func command_move_to_position(destination: Vector2) -> void:
	if is_dead:
		return

	has_manual_move_order = true
	manual_move_waypoints.clear()
	manual_move_waypoints.append(destination)
	manual_move_destination = destination

	on_manual_move_started()
	print(get_display_name(), "moving to position:", destination)
func command_move_through_positions(destinations: Array[Vector2]) -> void:
	if is_dead:
		return

	if destinations.is_empty():
		return

	has_manual_move_order = true
	manual_move_waypoints.clear()

	for destination in destinations:
		manual_move_waypoints.append(destination)

	manual_move_destination = manual_move_waypoints[0]

	on_manual_move_started()
	print(get_display_name(), "moving through", manual_move_waypoints.size(), "waypoints.")

func on_manual_move_started():
	pass


func update_manual_move_order() -> bool:
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
