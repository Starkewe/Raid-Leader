extends Node
class_name EncounterRuntime

const EncounterTargetRegistryScript := preload(
	"res://scripts/combat/encounter_target_registry.gd"
)

## Base hook for encounter-specific mechanics. Keeping this as a Node lets a
## runtime own timers, visuals, and encounter objects without adding encounter
## branches to every generic Boss ability.
var boss: Node = null
var definition: EncounterDefinition = null
var party_members: Array = []
var session: EncounterSession = null
var target_registry: EncounterTargetRegistry = EncounterTargetRegistryScript.new()


func configure(
	new_boss: Node, new_definition: EncounterDefinition,
	new_session: EncounterSession = null
) -> void:
	boss = new_boss
	definition = new_definition
	if new_session != null:
		set_session(new_session)


func set_session(new_session: EncounterSession) -> void:
	if session == new_session:
		return
	var previous_registry := target_registry
	session = new_session
	if session == null:
		return
	if previous_registry != null:
		for target in previous_registry.targets:
			if target != null and is_instance_valid(target):
				session.register_target(
					target, previous_registry.get_target_descriptor(target)
				)
	target_registry = session.target_registry
	_on_target_registry_changed(previous_registry, target_registry)


func _on_target_registry_changed(
	_previous_registry: EncounterTargetRegistry,
	_new_registry: EncounterTargetRegistry
) -> void:
	pass


func set_party_members(new_party_members: Array) -> void:
	party_members = new_party_members


func set_encounter_active(_active: bool) -> void:
	pass


func tick(_delta: float) -> void:
	pass


func uses_custom_combat_loop() -> bool:
	return false


func blocks_boss_actions() -> bool:
	return false


func get_boss_damage_multiplier() -> float:
	return 1.0


func before_boss_damage(
	_amount: int,
	_source: Node,
	_ability_id: String,
	_metadata: Dictionary
) -> void:
	pass


func after_boss_damage(
	_amount: int,
	_source: Node,
	_ability_id: String,
	_metadata: Dictionary
) -> void:
	pass


func request_target_exhaustion(_target: Node) -> void:
	pass


func on_target_damage(
	_target: Node,
	_amount: int,
	_source: Node,
	_ability_id: String,
	_metadata: Dictionary
) -> void:
	pass


func on_command_issued(_command_data: Dictionary) -> void:
	pass


func get_status_text() -> String:
	return ""


func is_casting() -> bool:
	return false


func get_cast_progress_percent() -> float:
	return 0.0


func get_cast_name() -> String:
	return ""


func get_current_cast_time() -> float:
	return 0.0


func get_current_cast_bar_value() -> float:
	return 0.0


func get_target_registry() -> EncounterTargetRegistry:
	return target_registry


func get_presentation_state() -> Dictionary:
	return {}


func build_attempt_metrics(_events: Array[Dictionary]) -> Dictionary:
	return {}


## Encounter-owned primary targets. These are the targets that replace the
## canonical Boss target for commands and boss-frame presentation. Returning
## an empty array preserves the normal single-boss behavior.
func get_primary_encounter_targets(_include_defeated: bool = false) -> Array[Node]:
	return []


func reset_attempt() -> void:
	pass


func cleanup_encounter() -> void:
	pass
