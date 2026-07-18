extends RefCounted
class_name BossTargetController

signal target_changed(target: Node)

var party_members: Array = []
var current_target: Node = null


func setup(new_party_members: Array) -> void:
	party_members = new_party_members

	if not is_valid_living_target(current_target):
		clear_target()


func set_target(new_target: Node) -> bool:
	if not is_valid_living_target(new_target):
		return false

	if current_target == new_target:
		return true

	current_target = new_target
	target_changed.emit(current_target)
	return true


func taunt(new_target: Node) -> bool:
	return set_target(new_target)


func clear_target() -> void:
	if current_target == null:
		return

	current_target = null
	target_changed.emit(null)


func get_target() -> Node:
	if is_valid_living_target(current_target):
		return current_target

	clear_target()
	return null


func acquire_fallback_target() -> Node:
	var target := get_target()

	if target != null:
		return target

	for party_member in party_members:
		if is_valid_living_target(party_member):
			set_target(party_member)
			return party_member

	return null


func is_valid_living_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	if target.has_method("is_alive"):
		return bool(target.is_alive())

	return true
