extends RefCounted
class_name CampaignCastGenerator

const CAST_SIZE := 60
const INITIAL_SIZE := 20
const RESERVE_SIZE := CAST_SIZE - INITIAL_SIZE
const INITIAL_CLASS_ORDER := ["Warrior", "Priest", "Rogue", "Mage"]
const INITIAL_CLASS_REQUIREMENTS := {
	"Warrior": 2,
	"Priest": 5,
	"Rogue": 6,
	"Mage": 7,
}
const WRIT_CLASS_REQUIREMENTS := {
	"Warrior": 15,
	"Priest": 15,
	"Rogue": 15,
	"Mage": 15,
}


static func generate(campaign_seed: int, definitions: Array[Dictionary]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = campaign_seed
	var remaining := definitions.duplicate(true)
	var initial: Array[Dictionary] = []
	var future: Array[Dictionary] = []
	var warnings: Array[String] = []
	var tag_counts: Dictionary = {}
	var class_counts: Dictionary = {}

	for unit_class in INITIAL_CLASS_ORDER:
		var required := int(INITIAL_CLASS_REQUIREMENTS[unit_class])

		for _slot in range(required):
			var candidates := _initial_candidates(remaining, unit_class)

			if candidates.is_empty():
				warnings.append(
					"Initial cast is missing an eligible %s definition." % unit_class
				)
				break

			var selected := _weighted_pick(candidates, tag_counts, class_counts, rng)
			initial.append(selected)
			remaining.erase(selected)
			_record_diversity(selected, tag_counts, class_counts)

	for unit_class in INITIAL_CLASS_ORDER:
		var future_required := (
			int(WRIT_CLASS_REQUIREMENTS[unit_class])
			- int(INITIAL_CLASS_REQUIREMENTS[unit_class])
		)

		for _slot in range(future_required):
			var candidates := _future_candidates(remaining, unit_class)

			if candidates.is_empty():
				warnings.append(
					"Campaign cast is missing a future-eligible %s definition."
					% unit_class
				)
				break

			var selected := _weighted_pick(candidates, tag_counts, class_counts, rng)
			future.append(selected)
			remaining.erase(selected)
			_record_diversity(selected, tag_counts, class_counts)

	_sort_by_catalog_order(initial)
	_sort_by_catalog_order(future)
	var initial_ids := _ids(initial)
	var future_ids := _ids(future)
	var selected_ids := initial_ids.duplicate()
	selected_ids.append_array(future_ids)
	_validate_result(selected_ids, initial, future, warnings)
	return {
		"selected_raider_ids": selected_ids,
		"initial_raider_ids": initial_ids,
		"future_raider_ids": future_ids,
		"warnings": warnings,
	}


static func _initial_candidates(
	definitions: Array[Dictionary], unit_class: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for definition in definitions:
		var recruitment: Dictionary = definition.get("recruitment", {})

		if (
			String(definition.get("default_class", "")) == unit_class
			and bool(recruitment.get("initial_eligible", false))
		):
			result.append(definition)

	return result


static func _future_candidates(
	definitions: Array[Dictionary], unit_class: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for definition in definitions:
		var recruitment: Dictionary = definition.get("recruitment", {})

		if (
			String(definition.get("default_class", "")) == unit_class
			and bool(recruitment.get("future_eligible", true))
		):
			result.append(definition)

	return result


static func _weighted_pick(
	candidates: Array[Dictionary],
	tag_counts: Dictionary,
	class_counts: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var weights: Array[float] = []
	var total_weight := 0.0

	for candidate in candidates:
		var recruitment: Dictionary = candidate.get("recruitment", {})
		var weight := maxf(float(recruitment.get("selection_weight", 1.0)), 0.01)
		var unit_class := String(candidate.get("default_class", ""))
		weight /= 1.0 + float(class_counts.get(unit_class, 0)) * 0.08

		for tag in candidate.get("personality_tags", []):
			weight /= 1.0 + float(tag_counts.get(String(tag), 0)) * 0.16

		weights.append(weight)
		total_weight += weight

	var roll := rng.randf_range(0.0, total_weight)
	var running := 0.0

	for index in range(candidates.size()):
		running += weights[index]

		if roll <= running:
			return candidates[index]

	return candidates[-1]


static func _record_diversity(
	definition: Dictionary, tag_counts: Dictionary, class_counts: Dictionary
) -> void:
	var unit_class := String(definition.get("default_class", ""))
	class_counts[unit_class] = int(class_counts.get(unit_class, 0)) + 1

	for tag in definition.get("personality_tags", []):
		var tag_id := String(tag)
		tag_counts[tag_id] = int(tag_counts.get(tag_id, 0)) + 1


static func _sort_by_catalog_order(definitions: Array[Dictionary]) -> void:
	definitions.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_order := int(a.get("catalog_order", 0))
			var b_order := int(b.get("catalog_order", 0))
			return (
				String(a.get("raider_id", "")) < String(b.get("raider_id", ""))
				if a_order == b_order
				else a_order < b_order
			)
	)


static func _ids(definitions: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []

	for definition in definitions:
		result.append(String(definition.get("raider_id", "")))

	return result


static func _validate_result(
	selected_ids: Array[String],
	initial: Array[Dictionary],
	future: Array[Dictionary],
	warnings: Array[String]
) -> void:
	var unique_ids: Dictionary = {}

	for raider_id in selected_ids:
		if unique_ids.has(raider_id):
			warnings.append("Campaign cast contains duplicate raider_id: " + raider_id)
		unique_ids[raider_id] = true

	if selected_ids.size() != CAST_SIZE:
		warnings.append(
			"Campaign cast contains %d raiders instead of %d." % [selected_ids.size(), CAST_SIZE]
		)

	if initial.size() != INITIAL_SIZE:
		warnings.append(
			"Initial cast contains %d raiders instead of %d." % [initial.size(), INITIAL_SIZE]
		)

	if future.size() != RESERVE_SIZE:
		warnings.append(
			"Reserve cast contains %d raiders instead of %d."
			% [future.size(), RESERVE_SIZE]
		)

	var counts: Dictionary = {}

	for definition in initial:
		var unit_class := String(definition.get("default_class", ""))
		counts[unit_class] = int(counts.get(unit_class, 0)) + 1

	for unit_class in INITIAL_CLASS_ORDER:
		if int(counts.get(unit_class, 0)) != int(INITIAL_CLASS_REQUIREMENTS[unit_class]):
			warnings.append(
				"Initial %s count is %d; expected %d."
				% [
					unit_class,
					int(counts.get(unit_class, 0)),
					int(INITIAL_CLASS_REQUIREMENTS[unit_class]),
				]
			)

	var writ_counts := counts.duplicate()

	for definition in future:
		var unit_class := String(definition.get("default_class", ""))
		writ_counts[unit_class] = int(writ_counts.get(unit_class, 0)) + 1

	for unit_class in INITIAL_CLASS_ORDER:
		if int(writ_counts.get(unit_class, 0)) != int(WRIT_CLASS_REQUIREMENTS[unit_class]):
			warnings.append(
				"Writ %s count is %d; expected %d."
				% [
					unit_class,
					int(writ_counts.get(unit_class, 0)),
					int(WRIT_CLASS_REQUIREMENTS[unit_class]),
				]
			)
