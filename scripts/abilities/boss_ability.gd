extends RefCounted
class_name BossAbility

var ability_id: String = "unnamed_ability"
var ability_name: String = "Unnamed Ability"
var cast_time: float = 1.0
var cooldown: float = 5.0
var damage: int = 0

var windup_text: String = ""
var impact_text: String = ""
var interruptible: bool = true
var requires_active_target: bool = true


func configure(definition: BossAbilityDefinition) -> void:
	if definition == null:
		return

	ability_id = definition.ability_id
	ability_name = definition.display_name
	cast_time = definition.cast_time
	cooldown = definition.cooldown
	damage = definition.damage
	windup_text = definition.windup_text
	impact_text = definition.impact_text
	interruptible = definition.interruptible
	requires_active_target = definition.requires_active_target


func can_cast(boss: Node, party_members: Array) -> bool:
	if boss == null:
		return false

	if not is_instance_valid(boss):
		return false

	if requires_active_target:
		if not boss.has_method("get_current_target"):
			return false

		if boss.get_current_target() == null:
			return false

	return true


func on_cast_start(boss: Node, party_members: Array) -> void:
	if windup_text != "":
		print(ability_name, "windup:", windup_text)


func on_cast_update(
	boss: Node,
	party_members: Array,
	elapsed_time: float,
	remaining_time: float
) -> void:
	pass


func resolve(boss: Node, party_members: Array) -> void:
	print(ability_name, "resolved, but has no effect implemented.")


func on_interrupted(boss: Node, party_members: Array) -> void:
	print(ability_name, "was interrupted.")


func get_status_text() -> String:
	return "Casting " + ability_name


func get_cast_name() -> String:
	return ability_name


func get_cast_bar_max_time(elapsed_time: float, remaining_time: float) -> float:
	return maxf(cast_time, 0.01)


func get_cast_bar_value(elapsed_time: float, remaining_time: float) -> float:
	return clampf(elapsed_time, 0.0, get_cast_bar_max_time(elapsed_time, remaining_time))
