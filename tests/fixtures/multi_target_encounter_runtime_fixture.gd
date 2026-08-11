extends EncounterRuntime

var west_target: Node = null
var east_target: Node = null
var command_count: int = 0


func configure(
	new_boss: Node, new_definition: EncounterDefinition,
	new_session: EncounterSession = null
) -> void:
	super.configure(new_boss, new_definition, new_session)
	west_target = Node.new()
	west_target.name = "WestFixture"
	boss.add_child(west_target)
	east_target = Node.new()
	east_target.name = "EastFixture"
	boss.add_child(east_target)
	target_registry.register_target(west_target, {
		"target_id": "fixture_west",
		"display_name": "West Fixture",
		"kind": "fixture_target",
		"side": "west",
		"primary_boss_target": true,
	})
	target_registry.register_target(east_target, {
		"target_id": "fixture_east",
		"display_name": "East Fixture",
		"kind": "fixture_target",
		"side": "east",
		"primary_boss_target": true,
	})


func on_command_issued(_command_data: Dictionary) -> void:
	command_count += 1


func get_presentation_state() -> Dictionary:
	return {"fixture_runtime": true}
