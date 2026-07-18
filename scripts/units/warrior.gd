extends BaseCombatUnit

class_name Warrior

var attack_range_units: float = 5.0
var stop_distance_units: float = 5.0
var attack_damage: int = 10
var attack_cooldown: float = 1.0

var target: Node2D = null
var cooldown_timer: float = 0.0
var attack_ability_id: String = "warrior_attack"


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
	print("Warrior ready. HP:", health)

func _physics_process(delta):
	if is_dead:
		stop_movement()
		move_and_slide()
		return

	update_cooldown(delta)

	if update_forced_movement(delta):
		move_and_slide()
		return

	if update_manual_move_order():
		move_and_slide()
		return

	if not has_valid_attack_target():
		stop_action()
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

	target = new_target

	print(get_display_name(), "attacking:", get_node_display_name(target))


func update_cooldown(delta: float):
	cooldown_timer = max(cooldown_timer - delta, 0.0)


func has_valid_attack_target() -> bool:
	return can_damage_target(target)


func handle_attack_movement():
	var distance_units: float = get_range_units_to_node(target)

	if distance_units > stop_distance_units:
		move_toward_node(target)
		return

	stop_movement()

	if distance_units <= attack_range_units:
		attack_target()

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

	if not new_target.has_method("taunt"):
		return false

	var success := bool(new_target.taunt(self))

	if success:
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
