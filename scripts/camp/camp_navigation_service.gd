extends RefCounted
class_name CampNavigationService

var nodes: Dictionary = {}
var adjacency: Dictionary = {}
var hidden_edges: Dictionary = {}


func setup(
	node_definitions: Array[Resource], edge_definitions: Array[Array]
) -> void:
	nodes.clear()
	adjacency.clear()
	hidden_edges.clear()
	for definition in node_definitions:
		if definition == null or definition.node_id.is_empty() or nodes.has(definition.node_id):
			continue
		nodes[definition.node_id] = definition
		adjacency[definition.node_id] = []
	for edge in edge_definitions:
		if edge.size() < 2:
			continue
		var first := String(edge[0])
		var second := String(edge[1])
		if not nodes.has(first) or not nodes.has(second):
			continue
		_add_neighbor(first, second)
		_add_neighbor(second, first)
		if edge.size() >= 3 and not bool(edge[2]):
			hidden_edges[_edge_key(first, second)] = true


func get_node_catalog() -> Dictionary:
	var result: Dictionary = {}
	for node_id in nodes:
		var definition = nodes[node_id]
		result[node_id] = {
			"world_position": definition.world_position,
			"node_type": definition.node_type,
			"facility_id": definition.facility_id,
		}
	return result


func get_node_position(node_id: String) -> Vector2:
	var definition = nodes.get(node_id)
	return Vector2.ZERO if definition == null else definition.world_position


func get_approach_node_id(facility_id: String) -> String:
	for node_id in nodes:
		var definition = nodes[node_id]
		if definition.node_type == "facility_approach" and definition.facility_id == facility_id:
			return String(node_id)
	return ""


func get_segments() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for from_id in adjacency:
		for neighbor in adjacency[from_id]:
			var ordered := [String(from_id), String(neighbor)]
			ordered.sort()
			var key := "%s|%s" % ordered
			if seen.has(key):
				continue
			seen[key] = true
			if hidden_edges.has(key):
				continue
			result.append({
				"from_node_id": from_id,
				"to_node_id": neighbor,
				"start_node_id": from_id,
				"end_node_id": neighbor,
			})
	return result


func shortest_waypoint_chain(from_node_id: String, to_node_id: String) -> Array[Vector2]:
	if not nodes.has(from_node_id) or not nodes.has(to_node_id):
		return []
	var distances: Dictionary = {from_node_id: 0.0}
	var previous: Dictionary = {}
	var unvisited: Array[String] = []
	for node_id in nodes:
		unvisited.append(String(node_id))
	while not unvisited.is_empty():
		var current := ""
		var current_distance := INF
		for candidate in unvisited:
			var distance := float(distances.get(candidate, INF))
			if distance < current_distance:
				current = candidate
				current_distance = distance
		if current.is_empty() or current == to_node_id:
			break
		unvisited.erase(current)
		for neighbor_value in adjacency.get(current, []):
			var neighbor := String(neighbor_value)
			if not unvisited.has(neighbor):
				continue
			var candidate_distance := current_distance + get_node_position(current).distance_to(
				get_node_position(neighbor)
			)
			if candidate_distance < float(distances.get(neighbor, INF)):
				distances[neighbor] = candidate_distance
				previous[neighbor] = current
	if from_node_id != to_node_id and not previous.has(to_node_id):
		return []
	var ids: Array[String] = [to_node_id]
	var cursor := to_node_id
	while cursor != from_node_id:
		cursor = String(previous[cursor])
		ids.push_front(cursor)
	var result: Array[Vector2] = []
	for node_id in ids:
		result.append(get_node_position(node_id))
	return result


func build_route(
	from_position: Vector2, destination: Vector2, facility_id: String
) -> Array[Vector2]:
	var approach := get_approach_node_id(facility_id)
	if approach.is_empty():
		return [destination]
	var start := approach
	if from_position.y > 1420.0 and destination.y < 1380.0:
		start = "south_transition"
	elif (
		facility_id != "communal_fire"
		and (absf(from_position.x - destination.x) > 760.0 or destination.y < 1150.0)
	):
		start = "central_crossroads"
	var result := shortest_waypoint_chain(start, approach)
	result.append(destination)
	return _remove_redundant_waypoints(from_position, result)


func _add_neighbor(first: String, second: String) -> void:
	var neighbors: Array = adjacency[first]
	if not neighbors.has(second):
		neighbors.append(second)
	adjacency[first] = neighbors


func _edge_key(first: String, second: String) -> String:
	var ordered := [first, second]
	ordered.sort()
	return "%s|%s" % ordered


func _remove_redundant_waypoints(
	from_position: Vector2, source: Array[Vector2]
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var previous := from_position
	for waypoint in source:
		if previous.distance_to(waypoint) > 18.0:
			result.append(waypoint)
			previous = waypoint
	return result
