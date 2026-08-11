extends Node
class_name AdvancedClassRuntime

var unit: BaseCombatUnit = null
var class_definition: Dictionary = {}


func configure(new_unit: BaseCombatUnit, definition: Dictionary) -> void:
	unit = new_unit
	class_definition = definition.duplicate(true)


func reset() -> void:
	pass


func tick(_delta: float) -> void:
	pass


func on_command(_command: Dictionary) -> void:
	pass


func on_combat_event(_event: Dictionary) -> void:
	pass


func cleanup() -> void:
	pass


func get_capabilities() -> Array[String]:
	return []
