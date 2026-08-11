extends RefCounted
class_name EncounterSession

const EncounterTargetRegistryScript := preload(
	"res://scripts/combat/encounter_target_registry.gd"
)

signal lifecycle_changed(active: bool)
signal command_recorded(command: Dictionary)
signal telemetry_recorded(event: Dictionary)
signal presentation_changed

var boss: Node = null
var definition: EncounterDefinition = null
var runtime: EncounterRuntime = null
var target_registry: EncounterTargetRegistry = EncounterTargetRegistryScript.new()
var active: bool = false
var commands: Array[Dictionary] = []
var telemetry: Array[Dictionary] = []


func configure(
	new_boss: Node, new_definition: EncounterDefinition,
	new_runtime: EncounterRuntime = null
) -> void:
	boss = new_boss
	definition = new_definition
	runtime = new_runtime
	if not target_registry.targets_changed.is_connected(_on_targets_changed):
		target_registry.targets_changed.connect(_on_targets_changed)
	if runtime != null:
		runtime.set_session(self)
	if target_registry.get_primary_targets(true).is_empty() and boss != null:
		register_target(boss, {
			"target_id": definition.encounter_id if definition != null else "boss",
			"display_name": boss.get_display_name() if boss.has_method("get_display_name") else boss.name,
			"kind": "boss",
			"primary_boss_target": true,
		})


func register_target(target: Node, descriptor: Dictionary = {}) -> void:
	target_registry.register_target(target, descriptor)


func unregister_target(target: Node) -> void:
	target_registry.unregister_target(target)


func resolve_target(selector: Dictionary) -> Dictionary:
	return target_registry.resolve_selector(selector)


func get_primary_targets(include_defeated: bool = false) -> Array[Node]:
	return target_registry.get_primary_targets(include_defeated)


func get_target_entries(selector: Dictionary = {}) -> Array[Dictionary]:
	return target_registry.get_target_entries(selector)


func set_active(next_active: bool) -> void:
	active = next_active
	if runtime != null and is_instance_valid(runtime):
		runtime.set_encounter_active(next_active)
	lifecycle_changed.emit(active)
	presentation_changed.emit()


func record_command(command: Dictionary) -> void:
	var recorded := command.duplicate(true)
	commands.append(recorded)
	if runtime != null and is_instance_valid(runtime):
		runtime.on_command_issued(recorded)
	command_recorded.emit(recorded.duplicate(true))


func record_telemetry(event: Dictionary) -> void:
	var recorded := event.duplicate(true)
	telemetry.append(recorded)
	telemetry_recorded.emit(recorded.duplicate(true))


func get_presentation_data() -> Dictionary:
	var result := {
		"encounter_id": definition.encounter_id if definition != null else "",
		"active": active,
		"targets": get_target_entries(),
		"commands": commands.duplicate(true),
		"telemetry": telemetry.duplicate(true),
	}
	if runtime != null and is_instance_valid(runtime):
		result.merge(runtime.get_presentation_state(), true)
	return result


func build_attempt_metrics(events: Array[Dictionary]) -> Dictionary:
	if runtime == null or not is_instance_valid(runtime):
		return {}
	return runtime.build_attempt_metrics(events)


func reset_attempt() -> void:
	active = false
	commands.clear()
	telemetry.clear()
	if runtime != null and is_instance_valid(runtime):
		runtime.reset_attempt()
	_ensure_default_primary_target()
	lifecycle_changed.emit(false)
	presentation_changed.emit()


func cleanup() -> void:
	active = false
	if runtime != null and is_instance_valid(runtime):
		runtime.cleanup_encounter()
	target_registry.clear()
	commands.clear()
	telemetry.clear()


func _on_targets_changed() -> void:
	presentation_changed.emit()


func _ensure_default_primary_target() -> void:
	if not target_registry.get_primary_targets(true).is_empty() or boss == null:
		return
	register_target(boss, {
		"target_id": definition.encounter_id if definition != null else "boss",
		"display_name": boss.get_display_name() if boss.has_method("get_display_name") else boss.name,
		"kind": "boss",
		"primary_boss_target": true,
	})
