extends BaseCombatUnit

@export var speed: float = 220.0

@export var attack_range: float = 85.0
@export var stop_distance: float = 75.0
@export var attack_damage: int = 8
@export var attack_cooldown: float = 0.8

@export var interrupt_range: float = 120.0
@export var interrupt_cooldown: float = 3.0

@export var manual_move_stop_distance: float = 12.0

var has_manual_move_order: bool = false
var manual_move_destination: Vector2 = Vector2.ZERO

var attack_target_node: Node2D = null
var interrupt_target: Node2D = null

var attack_timer: float = 0.0
var interrupt_timer: float = 0.0

var unit_class: String = ""
var unit_number: int = 0
var display_name: String = ""

func _ready():
	max_health = 85
	super._ready()
	print("Rogue ready. HP:", health)

func _physics_process(delta):
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if update_manual_move_order():
		move_and_slide()
		return
	attack_timer = max(attack_timer - delta, 0)
	interrupt_timer = max(interrupt_timer - delta, 0)

	if attack_target_node == null or not is_instance_valid(attack_target_node):
		stop_attack_only()
		move_and_slide()
		return

	if attack_target_node.has_method("is_alive") and not attack_target_node.is_alive():
		stop_attack_only()
		move_and_slide()
		return

	var distance := global_position.distance_to(attack_target_node.global_position)

	if distance > stop_distance:
		var direction := global_position.direction_to(attack_target_node.global_position)
		velocity = direction * speed
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

	attack_target_node = new_target
	interrupt_target = new_target
	print("Rogue attacking:", new_target.name)

func command_interrupt(new_target: Node2D):
	if is_dead:
		return

	if new_target == null or not is_instance_valid(new_target):
		interrupt_target = null
		print("Rogue received invalid interrupt target.")
		return

	interrupt_target = new_target
	print("Rogue ordered to interrupt:", new_target.name)

	var distance := global_position.distance_to(new_target.global_position)

	if distance > interrupt_range:
		print("Rogue is too far to interrupt.")
		return

	try_interrupt()

func try_interrupt():
	if is_dead:
		return

	if interrupt_timer > 0:
		print("Rogue interrupt is on cooldown.")
		return

	if interrupt_target == null or not is_instance_valid(interrupt_target):
		interrupt_target = null
		print("No valid interrupt target.")
		return

	if interrupt_target.has_method("is_alive") and not interrupt_target.is_alive():
		print("Interrupt target is dead.")
		return

	if not interrupt_target.has_method("interrupt_cast"):
		print("Target cannot be interrupted.")
		return

	interrupt_timer = interrupt_cooldown

	var success = interrupt_target.interrupt_cast()

	if success:
		print("Rogue successfully interrupted the cast!")
	else:
		print("Rogue used interrupt, but there was nothing to stop.")

func attack_target():
	if attack_timer > 0:
		return

	if attack_target_node == null or not is_instance_valid(attack_target_node):
		return

	attack_timer = attack_cooldown
	print("Rogue attacks target")

	if attack_target_node.has_method("take_damage"):
		attack_target_node.take_damage(attack_damage)

func stop_attack_only():
	attack_target_node = null
	velocity = Vector2.ZERO

func stop_action():
	has_manual_move_order = false
	attack_target_node = null
	interrupt_target = null
	velocity = Vector2.ZERO

func on_reset_unit():
	attack_timer = 0.0
	interrupt_timer = 0.0

func get_status_text() -> String:
	if is_dead:
		return "Dead"
	if has_manual_move_order:
		return "Moving"
	if attack_target_node != null and is_instance_valid(attack_target_node):
		if attack_target_node.has_method("is_alive") and attack_target_node.is_alive():
			return "Attacking " + attack_target_node.name

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
