extends BaseCombatUnit

@export var speed: float = 180.0
@export var attack_range: float = 95.0
@export var stop_distance: float = 85.0
@export var attack_damage: int = 10
@export var attack_cooldown: float = 1.0

@export var manual_move_stop_distance: float = 12.0

var has_manual_move_order: bool = false
var manual_move_destination: Vector2 = Vector2.ZERO

var target: Node2D = null
var cooldown_timer: float = 0.0

var unit_class: String = ""
var unit_number: int = 0
var display_name: String = ""

func _ready():
	max_health = 100
	super._ready()
	print("Warrior ready. HP:", health)

func _physics_process(delta):
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if update_manual_move_order():
		move_and_slide()
		return
	cooldown_timer = max(cooldown_timer - delta, 0)

	if target == null or not is_instance_valid(target):
		stop_action()
		move_and_slide()
		return

	if target.has_method("is_alive") and not target.is_alive():
		stop_action()
		move_and_slide()
		return

	var distance := global_position.distance_to(target.global_position)

	if distance > stop_distance:
		move_toward_target(target)
	else:
		velocity = Vector2.ZERO

	if distance <= attack_range:
		attack_target()

	move_and_slide()

func command_attack(new_target: Node2D):
	if is_dead:
		return

	if new_target == null or not is_instance_valid(new_target):
		stop_action()
		return

	target = new_target
	print("Warrior attacking:", new_target.name)

func move_toward_target(target_node: Node2D):
	var direction := global_position.direction_to(target_node.global_position)
	velocity = direction * speed

func attack_target():
	if cooldown_timer > 0:
		return

	if target == null or not is_instance_valid(target):
		return

	cooldown_timer = attack_cooldown
	print("Warrior attacks target")

	if target.has_method("take_damage"):
		target.take_damage(attack_damage)

func stop_action():
	has_manual_move_order = false
	target = null
	velocity = Vector2.ZERO

func on_reset_unit():
	cooldown_timer = 0.0

func get_status_text() -> String:
	if is_dead:
		return "Dead"
	if has_manual_move_order:
		return "Moving"

	if target != null and is_instance_valid(target):
		if target.has_method("is_alive") and target.is_alive():
			return "Attacking " + target.name

	return "Idle"
func command_move_to_position(destination: Vector2):
	if is_dead:
		return

	has_manual_move_order = true
	manual_move_destination = destination

	print(get_display_name(), "moving to position:", destination)
func update_manual_move_order() -> bool:
	if not has_manual_move_order:
		return false

	var distance := global_position.distance_to(manual_move_destination)

	if distance <= manual_move_stop_distance:
		has_manual_move_order = false
		velocity = Vector2.ZERO
		return false

	var direction := global_position.direction_to(manual_move_destination)
	velocity = direction * speed
	return true
func setup_unit_identity(new_unit_class: String, new_unit_number: int):
	unit_class = new_unit_class
	unit_number = new_unit_number
	display_name = new_unit_class + " " + str(new_unit_number)

func get_display_name() -> String:
	if display_name != "":
		return display_name

	return name
