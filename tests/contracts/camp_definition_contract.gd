extends Node

const DefinitionCatalogScript := preload("res://scripts/core/camp_definition_catalog.gd")
const ContentCatalogScript := preload("res://scripts/core/camp_content_catalog.gd")
const NavigationServiceScript := preload("res://scripts/camp/camp_navigation_service.gd")
const RouteNodeScript := preload("res://scripts/data/camp_route_node_definition.gd")
const StationDefinitionScript := preload("res://scripts/data/camp_station_definition.gd")
const StationRuntimeScript := preload("res://scripts/data/camp_activity_station.gd")


func _ready() -> void:
	var failures: Array[String] = []
	if DefinitionCatalogScript.get_activity_definitions().size() != 10:
		failures.append("The typed activity catalog did not expose all activities.")
	if ContentCatalogScript.get_station_definitions().size() != 11:
		failures.append("The typed station catalog did not expose all stations.")
	if not ContentCatalogScript.get_validation_report().get("valid", false):
		failures.append("The camp content catalog failed cross-reference validation.")

	var custom_station = StationDefinitionScript.new()
	custom_station.station_id = "contract_station"
	custom_station.facility_id = "contract_facility"
	custom_station.supported_activity_ids.append("contract_activity")
	custom_station.participant_offsets.append(Vector2.ZERO)
	custom_station.capacity = 1
	var station_runtime = StationRuntimeScript.create(custom_station)
	if not station_runtime.supports_activity("contract_activity"):
		failures.append("A typed station could not be added without a population-controller edit.")

	var first = RouteNodeScript.create("contract_a", Vector2.ZERO, "crossroads")
	var second = RouteNodeScript.create("contract_b", Vector2(30, 40), "facility_approach", "contract")
	var navigation = NavigationServiceScript.new()
	navigation.setup([first, second], [["contract_a", "contract_b"]])
	var chain: Array[Vector2] = navigation.shortest_waypoint_chain("contract_a", "contract_b")
	if chain != [Vector2.ZERO, Vector2(30, 40)]:
		failures.append("The weighted route graph did not resolve an added route node.")

	if failures.is_empty():
		print("RAID_TEST_PASS:camp_definition_contract | Camp definition/navigation contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
