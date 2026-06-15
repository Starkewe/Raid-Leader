extends CharacterBody2D
class_name BaseCombatUnit

signal defeated(unit)

@export var max_health: int = 100

@onready var health_bar = get_node_or_null("HealthBar")

var health: int = 0
var is_dead: bool = false

func _ready():
	health = max_health
	update_health_bar()

func take_damage(amount: int):
	if is_dead:
		return

	health -= amount
	health = max(health, 0)
	update_health_bar()

	print(name, "took", amount, "damage. HP:", health)

	if health <= 0:
		die()

func receive_heal(amount: int):
	if is_dead:
		return

	health += amount
	health = min(health, max_health)
	update_health_bar()

	print(name, "healed for", amount, ". HP:", health)

func die():
	if is_dead:
		return

	is_dead = true
	health = 0
	update_health_bar()
	stop_action()

	print(name, "defeated!")
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

func stop_action():
	velocity = Vector2.ZERO

func is_alive() -> bool:
	return not is_dead

func is_full_health() -> bool:
	return health >= max_health

func update_health_bar():
	if health_bar == null:
		return

	health_bar.max_value = max_health
	health_bar.value = health

func get_status_text() -> String:
	if is_dead:
		return "Dead"

	return "Idle"
