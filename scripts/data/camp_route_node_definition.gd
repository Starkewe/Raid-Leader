extends Resource
class_name CampRouteNodeDefinition

@export var node_id: String = ""
@export var world_position: Vector2 = Vector2.ZERO
@export_enum("transition", "crossroads", "facility_approach") var node_type := "crossroads"
@export var facility_id: String = ""


static func create(
	id: String, position: Vector2, type: String, facility: String = ""
) -> CampRouteNodeDefinition:
	var definition := CampRouteNodeDefinition.new()
	definition.node_id = id
	definition.world_position = position
	definition.node_type = type
	definition.facility_id = facility
	return definition
