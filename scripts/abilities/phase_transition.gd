extends BossAbility
class_name PhaseTransition


func resolve(_boss: Node, _party_members: Array) -> void:
	# The boss applies the pending phase after this no-op cast resolves.
	pass


func on_interrupted(_boss: Node, _party_members: Array) -> void:
	# A phase transition has no mechanic state to clean up.
	pass


func get_status_text() -> String:
	if not windup_text.is_empty():
		return windup_text

	if not impact_text.is_empty():
		return impact_text

	return "Casting " + ability_name
