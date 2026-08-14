extends Resource
class_name RaiderTraitDefinition

@export var trait_id: String = ""
@export var display_name: String = ""
@export_enum("major", "minor") var tier: String = "minor"
@export_multiline var description: String = ""
@export var hook_id: String = ""

