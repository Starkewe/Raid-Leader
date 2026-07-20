extends Node2D

@onready var player: CampPlayer = $CampPlayer
@onready var journal: CampJournal = $CampHUD/CampJournal
@onready var interaction_prompt: Label = $CampHUD/InteractionPrompt
@onready var visit_label: Label = $CampHUD/VisitPanel/Margin/VisitLabel
@onready var population_controller: CampPopulationController = $CampPopulationController

var facilities_by_id: Dictionary = {}
var nearest_facility: CampFacility = null


func _ready() -> void:
	_build_facility_catalog()
	journal.journal_visibility_changed.connect(_on_journal_visibility_changed)
	journal.embark_requested.connect(_on_embark_requested)
	_update_visit_label()
	_update_victory_spike()
	interaction_prompt.visible = false

	if OS.is_debug_build():
		_run_travel_budget_audit()


func _process(_delta: float) -> void:
	if journal.is_open():
		nearest_facility = null
		interaction_prompt.visible = false
		return

	nearest_facility = _find_nearest_interactive_facility()
	interaction_prompt.visible = nearest_facility != null

	if nearest_facility != null:
		interaction_prompt.text = nearest_facility.get_interaction_text()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("camp_interact")
		and nearest_facility != null
		and not journal.is_open()
	):
		journal.open_facility(nearest_facility.facility_id)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel") and not journal.is_open():
		SceneFlow.go_to_main_menu()
		get_viewport().set_input_as_handled()


func get_facility(facility_id: String) -> CampFacility:
	return facilities_by_id.get(facility_id) as CampFacility


func build_camp_path(
	from_position: Vector2, destination: Vector2, facility_id: String
) -> Array[Vector2]:
	var path: Array[Vector2] = []
	var approaches := {
		"command_tent": Vector2(1500, 690),
		"formation_yard": Vector2(1030, 1080),
		"archive": Vector2(2010, 1080),
		"smith": Vector2(760, 1160),
		"apothecary": Vector2(2250, 1160),
		"communal_fire": Vector2(1500, 1310),
		"quarters": Vector2(850, 1570),
		"training": Vector2(1110, 1280),
		"liaison": Vector2(2230, 1500)
	}

	if from_position.y > 1420.0 and destination.y < 1380.0:
		path.append(Vector2(1500, 1410))

	if (
		facility_id != "communal_fire"
		and (absf(from_position.x - destination.x) > 760.0 or destination.y < 1150.0)
	):
		path.append(Vector2(1500, 1125))

	if approaches.has(facility_id):
		path.append(approaches[facility_id])

	path.append(destination)
	return _remove_redundant_waypoints(from_position, path)


func _build_facility_catalog() -> void:
	facilities_by_id.clear()

	for node in get_tree().get_nodes_in_group("camp_facility"):
		var facility := node as CampFacility

		if facility != null and not facility.facility_id.is_empty():
			facilities_by_id[facility.facility_id] = facility


func _find_nearest_interactive_facility() -> CampFacility:
	var best: CampFacility = null
	var best_distance := INF

	for facility_value in facilities_by_id.values():
		var facility := facility_value as CampFacility

		if facility == null or not facility.interactive:
			continue

		var distance := player.global_position.distance_to(facility.global_position)

		if distance <= facility.interaction_radius and distance < best_distance:
			best = facility
			best_distance = distance

	return best


func _on_journal_visibility_changed(visible_now: bool) -> void:
	player.set_movement_enabled(not visible_now)


func _on_embark_requested() -> void:
	if SceneFlow.launch_campaign_combat():
		return

	journal.open_facility("command_tent")


func _update_visit_label() -> void:
	var context := CampaignState.get_visit_context()
	var context_type := String(context.get("type", "normal"))
	var headline := (
		{
			"normal": "The Writ makes ready.",
			"wipe": "The raid has returned from a failed attempt.",
			"first_victory": "A first victory has come home.",
			"repeat_victory": "The raid has defeated familiar prey again.",
			"recruitment": "New recruits are settling into camp.",
			"roster_change": "A changed active roster moves through camp.",
			"apex_victory": "An apex victory has opened new roads."
		}
		. get(context_type, "The Writ makes ready.")
	)
	visit_label.text = "%s\nWASD move · E interact · Esc main menu" % headline


func _update_victory_spike() -> void:
	var spike := get_facility("victory_spike")

	if spike == null:
		return

	var latest := CampaignState.get_latest_victory()

	if latest.is_empty():
		spike.display_name = "Empty Victory Spike"

		if spike.sprite != null:
			spike.sprite.visible = false
	else:
		spike.display_name = "Latest Trophy · %s" % String(latest.get("display_name", "Unknown"))

		if spike.sprite != null:
			spike.sprite.visible = true
			spike.sprite.modulate = (
				Color("a88b70")
				if String(latest.get("encounter_id", "")) == GameState.ENCOUNTER_OGRE
				else Color("93a2aa")
			)

	if spike.title_label != null:
		spike.title_label.text = spike.display_name


func _remove_redundant_waypoints(from_position: Vector2, source: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var previous := from_position

	for waypoint in source:
		if previous.distance_to(waypoint) > 18.0:
			result.append(waypoint)
			previous = waypoint

	return result


func _run_travel_budget_audit() -> void:
	var start := player.global_position
	var essential := ["command_tent", "formation_yard", "archive", "communal_fire"]

	for facility_id in facilities_by_id.keys():
		if facility_id in ["storage", "victory_spike"]:
			continue

		var facility := get_facility(String(facility_id))

		if facility == null:
			continue

		var path := build_camp_path(start, facility.global_position, String(facility_id))
		var distance := 0.0
		var previous := start

		for waypoint in path:
			distance += previous.distance_to(waypoint)
			previous = waypoint

		var seconds := distance / maxf(player.speed, 1.0)
		var budget := 10.0 if essential.has(facility_id) else 15.0
		print(
			(
				"[CampTravel] %s estimated %.1fs (budget %.0fs)"
				% [facility.display_name, seconds, budget]
			)
		)

		if seconds > budget:
			push_warning("Camp travel estimate exceeds budget for " + facility.display_name)
