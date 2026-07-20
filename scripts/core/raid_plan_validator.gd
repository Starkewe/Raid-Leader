extends RefCounted
class_name RaidPlanValidator

const ACTIVE_RAID_SIZE := 20
const VALID_REGIONS := [
	"north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"
]
const VALID_RANGES := ["close", "mid", "far"]


static func validate(
	plan: Dictionary, roster_by_id: Dictionary, available_encounter_ids: Array[String]
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var encounter_id := String(plan.get("encounter_id", ""))
	var active_ids: Array = plan.get("active_member_ids", [])

	if String(plan.get("region_id", "")).is_empty():
		errors.append("No region is selected.")

	if not available_encounter_ids.has(encounter_id):
		errors.append("The selected boss is not available in this region.")

	if active_ids.size() != ACTIVE_RAID_SIZE:
		errors.append(
			(
				"The active raid must contain exactly %d members; it currently contains %d."
				% [ACTIVE_RAID_SIZE, active_ids.size()]
			)
		)

	var seen_ids: Dictionary = {}

	for member_id_value in active_ids:
		var member_id := String(member_id_value)

		if seen_ids.has(member_id):
			errors.append("Active member %s appears more than once." % member_id)
			continue

		seen_ids[member_id] = true

		if not roster_by_id.has(member_id):
			errors.append("Active member %s is missing from the campaign roster." % member_id)

	var formations: Dictionary = plan.get("formations", {})
	var encounter_formation: Dictionary = formations.get(encounter_id, {})
	var placements: Dictionary = encounter_formation.get("placements", {})

	for member_id_value in active_ids:
		var member_id := String(member_id_value)

		if not placements.has(member_id):
			errors.append("%s has no starting placement." % _member_name(roster_by_id, member_id))
			continue

		var placement: Dictionary = placements[member_id]
		var region := String(placement.get("region", ""))
		var range_name := String(placement.get("range", ""))

		if not VALID_REGIONS.has(region):
			errors.append(
				"%s has an invalid starting region." % _member_name(roster_by_id, member_id)
			)

		if not VALID_RANGES.has(range_name):
			errors.append(
				"%s has an invalid starting range." % _member_name(roster_by_id, member_id)
			)

	for placed_member_id in placements.keys():
		if not active_ids.has(String(placed_member_id)):
			warnings.append(
				"The saved formation contains a reserve member; that placement is ignored."
			)
			break

	return {"valid": errors.is_empty(), "errors": errors, "warnings": warnings}


static func _member_name(roster_by_id: Dictionary, member_id: String) -> String:
	if not roster_by_id.has(member_id):
		return member_id

	return String(roster_by_id[member_id].get("display_name", member_id))
