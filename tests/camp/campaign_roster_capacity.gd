extends Node

const RaiderCatalogScript := preload("res://scripts/data/raider_catalog.gd")
const CampaignCastGeneratorScript := preload(
	"res://scripts/core/campaign_cast_generator.gd"
)
const CampScene := preload("res://scenes/camp/camp_scene.tscn")

const EXPECTED_AUTHORED_COUNTS := {
	"Warrior": 15,
	"Priest": 15,
	"Rogue": 15,
	"Mage": 16,
}
const EXPECTED_INITIAL_COUNTS := {
	"Warrior": 2,
	"Priest": 5,
	"Rogue": 6,
	"Mage": 7,
}
const EXPECTED_WRIT_COUNTS := {
	"Warrior": 15,
	"Priest": 15,
	"Rogue": 15,
	"Mage": 15,
}
const EXPECTED_NEW_RAIDERS := {
	"writ_053": ["Edda", "Warrior"],
	"writ_054": ["Garran", "Warrior"],
	"writ_055": ["Huld", "Warrior"],
	"writ_056": ["Kael", "Warrior"],
	"writ_057": ["Renna", "Warrior"],
	"writ_058": ["Sten", "Warrior"],
	"writ_059": ["Varda", "Warrior"],
	"writ_060": ["Aster", "Priest"],
	"writ_061": ["Maelin", "Priest"],
}

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var definitions := RaiderCatalogScript.get_all_definitions()
	var validation := RaiderCatalogScript.validate_all()
	_expect(bool(validation.get("valid", false)), "The master raider catalog is invalid.")
	_expect(
		Array(validation.get("warnings", [])).is_empty(),
		"The master raider catalog emitted authoring warnings."
	)
	_expect(
		int(validation.get("capacity_target", 0)) == 160,
		"The authored raider capacity target is not 160."
	)
	_expect(definitions.size() == 61, "The current authored raider pool is not 61.")
	_expect(
		_count_classes(definitions) == EXPECTED_AUTHORED_COUNTS,
		"The authored pool is not 15/15/15/16 by base class."
	)

	for raider_id in EXPECTED_NEW_RAIDERS:
		var expected: Array = EXPECTED_NEW_RAIDERS[raider_id]
		var definition := RaiderCatalogScript.get_definition(raider_id)
		_expect(
			String(definition.get("display_name", "")) == String(expected[0])
			and String(definition.get("default_class", "")) == String(expected[1]),
			"%s does not match its approved name and class." % raider_id
		)
		_expect(
			not String(definition.get("biography", "")).is_empty()
			and not String(definition.get("personality_description", "")).is_empty()
			and not Array(definition.get("personality_tags", [])).is_empty(),
			"%s is missing full authored profile fields." % raider_id
		)

	for seed_value in range(1, 33):
		var generation := CampaignCastGeneratorScript.generate(seed_value, definitions)
		var selected: Array = generation.get("selected_raider_ids", [])
		var initial: Array = generation.get("initial_raider_ids", [])
		var future: Array = generation.get("future_raider_ids", [])
		_expect(Array(generation.get("warnings", [])).is_empty(), "Cast generation emitted warnings.")
		_expect(selected.size() == 60, "A generated Writ did not contain 60 raiders.")
		_expect(initial.size() == 20, "A generated initial raid did not contain 20 raiders.")
		_expect(future.size() == 40, "A generated reserve did not contain 40 raiders.")
		_expect(
			_count_ids_by_class(selected) == EXPECTED_WRIT_COUNTS,
			"A generated Writ was not exactly 15 of each base class."
		)
		_expect(
			_count_ids_by_class(initial) == EXPECTED_INITIAL_COUNTS,
			"The initial raid was not 2 Warriors, 5 Priests, 6 Rogues, and 7 Mages."
		)

	CampaignState.reset_campaign(false, 61059)
	_expect(
		CampaignState.get_selected_cast_ids().size() == 60
		and CampaignState.get_future_recruit_ids().size() == 40,
		"Campaign state did not retain the 60-person Writ and 40-person reserve plan."
	)
	_expect(
		CampaignState.ACTIVE_RAID_SIZE == 20
		and GameState.MAX_RAID_SIZE == 20
		and CampaignState.get_active_member_ids().size() == 20,
		"Campaign state did not preserve the 20-person active raid cap."
	)

	var room_options := CampaignState.get_room_options()
	var assigned_count := 0
	var occupied_room_count := 0

	_expect(room_options.size() == 20, "Member quarters did not expose 20 rooms.")

	for room in room_options:
		var occupants: Array = room.get("occupant_ids", [])
		_expect(int(room.get("capacity", 0)) == 4, "A quarters room capacity is not four.")
		_expect(occupants.size() <= 4, "A quarters room exceeded four occupants.")
		assigned_count += occupants.size()

		if not occupants.is_empty():
			occupied_room_count += 1

	_expect(assigned_count == 20, "The initial raid was not fully assigned to quarters.")
	_expect(occupied_room_count == 5, "The initial raid did not fill five four-person rooms.")
	var first_initial_id := String(CampaignState.get_initial_cast_ids()[0])
	_expect(
		CampaignState.get_roommate_summary(first_initial_id).begins_with("Roommates:"),
		"Four-person rooms did not present all roommates as a group."
	)

	var camp := CampScene.instantiate()
	add_child(camp)
	await get_tree().process_frame
	await get_tree().process_frame
	var population := camp.get_node_or_null("CampPopulationController")
	_expect(population != null, "The camp population controller did not load.")

	if population != null:
		_expect(
			Dictionary(population.get("actors_by_id")).size() == 20,
			"The camp did not spawn the 20 recruited initial raiders."
		)

	camp.queue_free()
	await get_tree().process_frame
	var expanded_states: Dictionary = CampaignState.campaign.get("raider_states", {})

	for future_id in CampaignState.get_future_recruit_ids():
		var future_state: Dictionary = expanded_states[future_id]
		future_state["recruited"] = true
		expanded_states[future_id] = future_state

	CampaignState.campaign["raider_states"] = expanded_states
	CampaignState._ensure_valid_room_assignments(CampaignState.campaign)
	_expect(
		CampaignState.get_roster_members().size() == 60
		and CampaignState.get_reserve_members().size() == 40,
		"The fully recruited campaign did not cap at 20 active and 40 reserve raiders."
	)
	var fully_recruited_rooms := CampaignState.get_room_options()
	var fully_assigned := 0
	var fully_occupied_rooms := 0

	for room in fully_recruited_rooms:
		var occupants: Array = room.get("occupant_ids", [])
		fully_assigned += occupants.size()
		fully_occupied_rooms += 1 if not occupants.is_empty() else 0
		_expect(occupants.size() <= 4, "A fully recruited room exceeded four occupants.")

	_expect(
		fully_assigned == 60 and fully_occupied_rooms == 15,
		"The 60 recruited raiders did not fit into fifteen four-person rooms."
	)
	CampaignState.reset_campaign(false, 61059)

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)

		get_tree().quit(1)
		return

	print("Campaign roster capacity and camp smoke regressions passed.")
	get_tree().quit(0)


func _count_classes(definitions: Array[Dictionary]) -> Dictionary:
	var counts: Dictionary = {}

	for definition in definitions:
		var unit_class := String(definition.get("default_class", ""))
		counts[unit_class] = int(counts.get(unit_class, 0)) + 1

	return counts


func _count_ids_by_class(raider_ids: Array) -> Dictionary:
	var definitions: Array[Dictionary] = []

	for raider_id in raider_ids:
		definitions.append(RaiderCatalogScript.get_definition(String(raider_id)))

	return _count_classes(definitions)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
