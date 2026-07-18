extends BaseCombatUnit

class_name Rogue

var attack_range_units: float = 5.0
var stop_distance_units: float = 5.0
var attack_damage: int = 8
var attack_cooldown: float = 0.8
var interrupt_range_units: float = 5.0
var interrupt_cooldown: float = 3.0

var attack_target_node: Node2D = null
var interrupt_target: Node2D = null

var attack_timer: float = 0.0
var interrupt_timer: float = 0.0
var attack_ability_id: String = "rogue_attack"
var interrupt_ability_id: String = "interrupt"


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
	print("Rogue ready. HP:", health)

func _physics_process(delta):
	if is_dead:
		stop_movement()
		move_and_slide()
		return

	update_cooldowns(delta)

	if update_forced_movement(delta):
		move_and_slide()
		return

	if update_manual_move_order():
		move_and_slide()
		return

	if not has_valid_attack_target():
		stop_attack_only()
		move_and_slide()
		return

	handle_attack_movement()

	move_and_slide()


func command_attack(new_target: Node2D):
	if is_dead:
		return

	if not can_damage_target(new_target):
		stop_action()
		return

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
	return can_damage_target(attack_target_node)


func handle_attack_movement():
	var distance_units: float = get_range_units_to_node(attack_target_node)

	if distance_units > stop_distance_units:
		move_toward_node(attack_target_node)
		return

	stop_movement()

	if distance_units <= attack_range_units:
		attack_target()


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


func get_status_text() -> String:
	var shared_status := get_shared_status_text()

	if shared_status != "":
		return shared_status

	if has_valid_attack_target():
		return "Attacking " + get_node_display_name(attack_target_node)

	return "Idle"
