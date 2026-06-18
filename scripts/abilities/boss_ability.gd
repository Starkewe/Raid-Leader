extends RefCounted
class_name BossAbility

var ability_name: String = "Unnamed Ability"
var cast_time: float = 1.0
var cooldown: float = 5.0
var damage: int = 0

var windup_text: String = ""
var impact_text: String = ""
var interruptible: bool = true


func can_cast(boss: Node, party_members: Array) -> bool:
	if boss == null:
		return false

	if not is_instance_valid(boss):
		return false

	return true


func on_cast_start(boss: Node, party_members: Array) -> void:
	if windup_text != "":
		print(ability_name, "windup:", windup_text)


func resolve(boss: Node, party_members: Array) -> void:
	print(ability_name, "resolved, but has no effect implemented.")


func on_interrupted(boss: Node, party_members: Array) -> void:
	print(ability_name, "was interrupted.")


func get_status_text() -> String:
	return "Casting " + ability_name


func get_cast_name() -> String:
	return ability_name
