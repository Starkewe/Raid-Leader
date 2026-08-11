extends RefCounted
class_name CampActivityReservationService

const CampActivityStationScript := preload("res://scripts/data/camp_activity_station.gd")


func build_station_registry(definitions: Array[Resource]) -> Dictionary:
	var result: Dictionary = {}
	for definition in definitions:
		var station = CampActivityStationScript.create(definition)
		var station_id := station.get_station_id()
		if not station_id.is_empty():
			result[station_id] = station
	return result


func release_member(
	member_id: String, stations: Dictionary, reservations: Dictionary
) -> void:
	var station_id := String(reservations.get(member_id, ""))
	var station = stations.get(station_id)
	if station != null:
		station.release(member_id)
	reservations.erase(member_id)


func release_all(stations: Dictionary, reservations: Dictionary) -> void:
	for station in stations.values():
		if station != null:
			station.release_all()
	reservations.clear()
