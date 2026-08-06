extends Node

var failures: Array[String] = []
var raid_plan_signal_count: int = 0
var state_signal_count: int = 0


func _ready() -> void:
	CampaignState.raid_plan_changed.connect(_on_raid_plan_changed)
	CampaignState.state_changed.connect(_on_state_changed)
	call_deferred("_run")


func _run() -> void:
	CampaignState.reset_campaign(false, 61059)
	var active_ids := CampaignState.get_active_member_ids()
	_expect(active_ids.size() >= 4, "The seeded campaign did not create enough active members.")

	if active_ids.size() < 4:
		_finish()
		return

	var formation := CampaignState.get_formation()
	var placements: Dictionary = {}
	var slot_assignments: Array[Dictionary] = [
		{"region": "north", "range": "far"},
		{"region": "north", "range": "far"},
		{"region": "south", "range": "close"},
		{"region": "east", "range": "close"},
		{"region": "southeast", "range": "close"},
		{"region": "southwest", "range": "close"},
		{"region": "west", "range": "close"},
		{"region": "northwest", "range": "close"},
		{"region": "northeast", "range": "close"},
		{"region": "north", "range": "close"},
		{"region": "east", "range": "mid"},
		{"region": "southeast", "range": "mid"},
		{"region": "south", "range": "mid"},
		{"region": "southwest", "range": "mid"},
		{"region": "west", "range": "mid"},
		{"region": "northwest", "range": "mid"},
		{"region": "northeast", "range": "mid"},
		{"region": "north", "range": "mid"},
		{"region": "east", "range": "far"},
		{"region": "southeast", "range": "far"},
	]

	for index in range(active_ids.size()):
		placements[active_ids[index]] = slot_assignments[index].duplicate(true)

	formation["preset_name"] = "Saved Draft"
	formation["placements"] = placements
	CampaignState.replace_current_formation(formation)
	_expect(
		CampaignState.save_current_formation("Saved Draft"),
		"The controlled formation preset could not be saved."
	)

	raid_plan_signal_count = 0
	state_signal_count = 0
	_expect(
		CampaignState.move_formation_mini_region(
			"north", "far", "south", "close", true
		),
		"The occupied source group could not move into an occupied destination."
	)
	_expect(
		_member_ids_in_slot("north", "far").is_empty(),
		"The source mini-region still contains members after a group move."
	)
	_expect(
		_member_ids_in_slot("south", "close").size() == 3,
		"The occupied destination did not preserve and merge its members."
	)
	_expect(
		_all_active_members_appear_once(),
		"The group move duplicated or lost an active member."
	)
	_expect(
		String(CampaignState.get_formation().get("preset_name", "")) == "Saved Draft",
		"A Formation Yard-style group move did not preserve the preset name."
	)
	_expect(
		raid_plan_signal_count == 1 and state_signal_count == 1,
		"A successful group move did not emit each formation/state signal exactly once."
	)

	var pause_snapshot := CampaignState.get_formation()
	_expect(
		CampaignState.move_formation_mini_region(
			"south", "close", "southwest", "far"
		),
		"The pause-menu-style group move failed."
	)
	_expect(
		String(CampaignState.get_formation().get("preset_name", "")) == "Custom",
		"A pause-menu-style group move did not become Custom."
	)
	CampaignState.replace_current_formation(pause_snapshot)

	var individually_moved_id := active_ids[0]
	_expect(
		CampaignState.set_member_placement(individually_moved_id, "west", "mid", "", true),
		"The existing individual member reassignment path stopped working."
	)
	_expect(
		_member_ids_in_slot("west", "mid").has(individually_moved_id),
		"The individually reassigned member did not reach its destination."
	)

	var stable_formation := CampaignState.get_formation()
	_expect(
		not CampaignState.move_formation_mini_region(
			"northeast", "far", "west", "mid", true
		),
		"An empty source mini-region was accepted."
	)
	_expect(
		not CampaignState.move_formation_mini_region(
			"south", "close", "south", "close", true
		),
		"A group move onto its own source mini-region was accepted."
	)
	_expect(
		not CampaignState.move_formation_mini_region(
			"invalid", "far", "west", "mid", true
		),
		"An invalid source mini-region was accepted."
	)
	_expect(
		not CampaignState.move_formation_mini_region(
			"south", "close", "west", "invalid", true
		),
		"An invalid destination mini-region was accepted."
	)
	_expect(
		CampaignState.get_formation() == stable_formation,
		"A rejected group move mutated the current formation."
	)

	var snapshot := CampaignState.get_formation()
	_expect(
		CampaignState.move_formation_mini_region(
			"south", "close", "southwest", "far", true
		),
		"The snapshot cancellation setup group move failed."
	)
	CampaignState.replace_current_formation(snapshot)
	_expect(
		CampaignState.get_formation() == snapshot,
		"Restoring a formation snapshot did not cancel the complete group move."
	)

	CampaignState.reset_campaign(false, 61059)
	_finish()


func _member_ids_in_slot(region: String, range_name: String) -> Array[String]:
	var result: Array[String] = []
	var formation := CampaignState.get_formation()
	var placements_value: Variant = formation.get("placements", {})
	if not placements_value is Dictionary:
		return result

	var placements: Dictionary = placements_value
	for member_id in CampaignState.get_active_member_ids():
		var placement_value: Variant = placements.get(member_id, {})
		if not placement_value is Dictionary:
			continue

		var placement: Dictionary = placement_value
		if (
			String(placement.get("region", "")) == region
			and String(placement.get("range", "")) == range_name
		):
			result.append(member_id)

	return result


func _all_active_members_appear_once() -> bool:
	var seen: Array[String] = []
	var formation := CampaignState.get_formation()
	var placements_value: Variant = formation.get("placements", {})
	if not placements_value is Dictionary:
		return false

	var placements: Dictionary = placements_value
	for member_id in CampaignState.get_active_member_ids():
		if not placements.has(member_id):
			return false
		if seen.has(member_id):
			return false
		seen.append(member_id)

	return seen.size() == CampaignState.get_active_member_ids().size()


func _finish() -> void:
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
		return

	print("Formation group state regressions passed.")
	get_tree().quit(0)


func _on_raid_plan_changed() -> void:
	raid_plan_signal_count += 1


func _on_state_changed() -> void:
	state_signal_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
