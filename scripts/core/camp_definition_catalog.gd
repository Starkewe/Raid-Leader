extends RefCounted
class_name CampDefinitionCatalog

const RouteNodeScript := preload("res://scripts/data/camp_route_node_definition.gd")
const ACTIVITIES: Array[CampActivityDefinition] = [
	preload("res://data/camp/activities/prepare_plan.tres"),
	preload("res://data/camp/activities/rehearse.tres"),
	preload("res://data/camp/activities/study_target.tres"),
	preload("res://data/camp/activities/smith_work.tres"),
	preload("res://data/camp/activities/apothecary_work.tres"),
	preload("res://data/camp/activities/train.tres"),
	preload("res://data/camp/activities/socialize.tres"),
	preload("res://data/camp/activities/rest.tres"),
	preload("res://data/camp/activities/reflect.tres"),
	preload("res://data/camp/activities/victory_gather.tres"),
]
const STATIONS: Array[Resource] = [
	preload("res://data/camp/stations/command_strategy_table.tres"),
	preload("res://data/camp/stations/archive_reading_tables.tres"),
	preload("res://data/camp/stations/smith_shared_forge.tres"),
	preload("res://data/camp/stations/smith_work_benches.tres"),
	preload("res://data/camp/stations/apothecary_worktable.tres"),
	preload("res://data/camp/stations/formation_drill_markers.tres"),
	preload("res://data/camp/stations/quarters_rest_places.tres"),
	preload("res://data/camp/stations/quarters_reflection_bench.tres"),
	preload("res://data/camp/stations/communal_fire_ring.tres"),
	preload("res://data/camp/stations/training_practice_ring.tres"),
	preload("res://data/camp/stations/victory_spike_view.tres"),
]

const ROUTE_NODE_DATA := [
	["south_transition", Vector2(1500, 1410), "transition", ""],
	["central_crossroads", Vector2(1500, 1125), "crossroads", ""],
	["command_tent_approach", Vector2(1500, 690), "facility_approach", "command_tent"],
	["formation_yard_approach", Vector2(1030, 1080), "facility_approach", "formation_yard"],
	["archive_approach", Vector2(2010, 1080), "facility_approach", "archive"],
	["smith_approach", Vector2(760, 1160), "facility_approach", "smith"],
	["apothecary_approach", Vector2(2250, 1160), "facility_approach", "apothecary"],
	["communal_fire_approach", Vector2(1500, 1310), "facility_approach", "communal_fire"],
	["quarters_approach", Vector2(850, 1570), "facility_approach", "quarters"],
	["training_approach", Vector2(1110, 1280), "facility_approach", "training"],
	["liaison_approach", Vector2(2230, 1500), "facility_approach", "liaison"],
	["storage_approach", Vector2(1930, 1425), "facility_approach", "storage"],
]
const ROUTE_EDGES := [
	["south_transition", "central_crossroads"],
	["south_transition", "communal_fire_approach", false],
	["central_crossroads", "command_tent_approach"],
	["central_crossroads", "formation_yard_approach"],
	["central_crossroads", "archive_approach"],
	["central_crossroads", "smith_approach"],
	["central_crossroads", "apothecary_approach"],
	["central_crossroads", "communal_fire_approach"],
	["central_crossroads", "quarters_approach"],
	["central_crossroads", "training_approach"],
	["central_crossroads", "liaison_approach"],
	["central_crossroads", "storage_approach"],
]


static func get_route_node_definitions() -> Array[Resource]:
	var result: Array[Resource] = []
	for value in ROUTE_NODE_DATA:
		result.append(RouteNodeScript.create(
			String(value[0]), value[1], String(value[2]), String(value[3])
		))
	return result


static func get_route_edges() -> Array[Array]:
	var result: Array[Array] = []
	for value in ROUTE_EDGES:
		result.append(Array(value).duplicate())
	return result


static func get_activity_definitions() -> Array[CampActivityDefinition]:
	return ACTIVITIES.duplicate()


static func get_station_definitions() -> Array[Resource]:
	return STATIONS.duplicate()
