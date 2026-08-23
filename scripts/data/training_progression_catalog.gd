extends RefCounted
class_name TrainingProgressionCatalog

const RaiderClassCatalogScript := preload("res://scripts/data/raider_class_catalog.gd")

const ENTRY_NODE_ID := "entry"
const CAPSTONE_NODE_ID := "capstone"
const TIER_NODE_IDS: Array[Array] = [
	["tier_1_left", "tier_1_center", "tier_1_right"],
	["tier_2_left", "tier_2_center", "tier_2_right"],
	["tier_3_left", "tier_3_center", "tier_3_right"],
]
const ALL_NODE_IDS: Array[String] = [
	ENTRY_NODE_ID,
	"tier_1_left", "tier_1_center", "tier_1_right",
	"tier_2_left", "tier_2_center", "tier_2_right",
	"tier_3_left", "tier_3_center", "tier_3_right",
	CAPSTONE_NODE_ID,
]

const ROLE_QUESTS: Dictionary = {
	"warrior": {
		"credit_key": "successful_boss_taunt_swap",
		"description": "Successfully taunt a boss off another raider 30 times.",
		"target": 30,
	},
	"priest": {
		"credit_key": "low_health_ally_heal",
		"description": "Heal an ally below 50% health 30 times.",
		"target": 30,
	},
	"rogue": {
		"credit_key": "boss_damage_sequence_off_tank",
		"description": "Complete 50 boss damage sequences while another raider holds the boss's attention.",
		"target": 50,
	},
	"mage": {
		"credit_key": "boss_damage_sequence_off_tank",
		"description": "Complete 50 boss damage sequences while another raider holds the boss's attention.",
		"target": 50,
	},
}

const LINEAGE_QUESTS: Dictionary = {
	"hollow_anvil": {
		"credit_key": "planted_basic_attack",
		"description": "After remaining planted in a mini-region for more than 10 seconds, land 100 basic attacks on an enemy.",
		"target": 100,
	},
	"gravelord_proxy": {
		"credit_key": "shared_region_low_ally_direct_hit",
		"description": "Take 30 direct boss hits while an ally below 50% health remains in the same mini-region.",
		"target": 30,
	},
	"sunder_clerk": {
		"credit_key": "rear_boss_basic_attack",
		"description": "Land 100 basic attacks on a boss from behind.",
		"target": 100,
	},
	"lantern_warden": {
		"credit_key": "post_region_change_boss_taunt",
		"description": "Enter a different mini-region, then taunt the boss within 5 seconds — 20 times.",
		"target": 20,
	},
	"burden_courier": {
		"credit_key": "post_cleanse_same_ally_heal",
		"description": "Cleanse an ally, then heal that same ally within 5 seconds — 20 times.",
		"target": 20,
	},
	"memory_apothecary": {
		"credit_key": "post_damage_repeat_ally_heal",
		"description": "Heal an ally above 50% health, then heal that ally again after they take damage — 20 times.",
		"target": 20,
	},
	"scar_gardener": {
		"credit_key": "post_region_change_ally_heal",
		"description": "Move to a different mini-region, then heal an ally within 4 seconds — 25 times.",
		"target": 25,
	},
	"moth_surgeon": {
		"credit_key": "overheal_then_other_ally_heal",
		"description": "Overheal one ally, then heal a different injured ally within 4 seconds — 25 times.",
		"target": 25,
	},
	"echo_butcher": {
		"credit_key": "ten_hit_same_boss_sequence",
		"description": "Complete a ten-hit basic-attack sequence against the same boss without changing targets — 10 times.",
		"target": 10,
	},
	"ritebreaker": {
		"credit_key": "basic_attack_casting_enemy",
		"description": "Land 50 basic attacks against enemies while they are casting. Interrupts are not required.",
		"target": 50,
	},
	"drift_knife": {
		"credit_key": "leave_return_close_basic",
		"description": "Attack a boss from close range, leave close range, return, and land another basic attack within 5 seconds — 20 times.",
		"target": 20,
	},
	"phasehand": {
		"credit_key": "post_indirect_dodge_basic",
		"description": "Dodge an indirect attack, then land a basic attack within 4 seconds — 20 times.",
		"target": 20,
	},
	"hearth_corsair": {
		"credit_key": "mid_and_close_three_cast_sequence",
		"description": "Complete a three-cast sequence at mid range and a three-cast sequence at close range — 10 times.",
		"target": 10,
	},
	"rift_tailor": {
		"credit_key": "unique_regions_within_three_encounters",
		"description": "Cast spells from 15 unique mini-regions within 3 encounters.",
		"target": 15,
	},
	"rune_slinger": {
		"credit_key": "post_dodge_spell_begin",
		"description": "Dodge, then begin a spell within 4 seconds — 25 times.",
		"target": 25,
	},
	"orbit_scribe": {
		"credit_key": "three_range_band_spell_encounter",
		"description": "Cast spells from three different range bands during the same encounter — 10 times.",
		"target": 10,
	},
}


static func get_definition(lineage_id: String) -> Dictionary:
	var lineage := RaiderClassCatalogScript.get_lineage_definition(lineage_id)
	if lineage.is_empty():
		return {}
	var canonical := String(lineage.get("lineage_id", ""))
	var base_class_id := String(lineage.get("base_class_id", ""))
	var advanced_name := String(lineage.get("advanced_class_name", canonical.capitalize()))
	var nodes: Array[Dictionary] = []
	nodes.append({
		"node_id": ENTRY_NODE_ID,
		"title": "Claim the %s Title" % advanced_name,
		"tier": 0,
		"reward_summary": "Gain the class name, emblem, colors, and weapon eligibility.",
		"objectives": [
			{
				"objective_id": "unique_bosses",
				"credit_key": "unique_boss_victories",
				"description": "Defeat 3 unique bosses with this raider in the active raid.",
				"target": 3,
				"kind": "unique_set",
			},
			_objective("role_requirement", Dictionary(ROLE_QUESTS.get(base_class_id, {}))),
			_objective("lineage_requirement", Dictionary(LINEAGE_QUESTS.get(canonical, {}))),
		],
	})
	for tier_index in range(TIER_NODE_IDS.size()):
		for branch_index in range(TIER_NODE_IDS[tier_index].size()):
			var node_id := String(TIER_NODE_IDS[tier_index][branch_index])
			nodes.append({
				"node_id": node_id,
				"title": "Class Kit %d.%d" % [tier_index + 1, branch_index + 1],
				"tier": tier_index + 1,
				"reward_summary": "Placeholder: adds a fixed aspect of the %s class kit." % advanced_name,
				"objectives": [{
					"objective_id": "placeholder_quest",
					"credit_key": "%s_%s" % [canonical, node_id],
					"description": "Quest placeholder — requirement to be finalized.",
					"target": 1,
					"kind": "counter",
				}],
			})
	nodes.append({
		"node_id": CAPSTONE_NODE_ID,
		"title": "%s Capstone" % advanced_name,
		"tier": 4,
		"reward_summary": "Placeholder: grants the final kit component and completes the advanced class.",
		"objectives": [{
			"objective_id": "placeholder_quest",
			"credit_key": "%s_capstone" % canonical,
			"description": "Capstone quest placeholder — requirement to be finalized.",
			"target": 1,
			"kind": "counter",
		}],
	})
	return {
		"lineage_id": canonical,
		"advanced_class_id": canonical,
		"advanced_class_name": advanced_name,
		"base_class_id": base_class_id,
		"nodes": nodes,
	}


static func get_node(lineage_id: String, node_id: String) -> Dictionary:
	for node in get_definition(lineage_id).get("nodes", []):
		if String(node.get("node_id", "")) == node_id:
			return Dictionary(node).duplicate(true)
	return {}


static func get_available_node_ids(completed_node_ids_value: Variant) -> Array[String]:
	var completed := _string_array(completed_node_ids_value)
	if not completed.has(ENTRY_NODE_ID):
		var entry_result: Array[String] = [ENTRY_NODE_ID]
		return entry_result
	for tier_ids in TIER_NODE_IDS:
		var typed_tier: Array[String] = []
		for node_id in tier_ids:
			typed_tier.append(String(node_id))
		var tier_complete := true
		for node_id in typed_tier:
			if not completed.has(node_id):
				tier_complete = false
		if not tier_complete:
			return typed_tier
	var capstone_result: Array[String] = []
	if not completed.has(CAPSTONE_NODE_ID):
		capstone_result.append(CAPSTONE_NODE_ID)
	return capstone_result


static func validate_catalog() -> PackedStringArray:
	var errors := PackedStringArray()
	if LINEAGE_QUESTS.size() != 16:
		errors.append("Training progression must define 16 lineage requirements.")
	for lineage_id in RaiderClassCatalogScript.get_all_lineage_ids():
		var definition := get_definition(lineage_id)
		var nodes: Array = definition.get("nodes", [])
		if nodes.size() != 11:
			errors.append("Lineage '%s' must contain 11 progression nodes." % lineage_id)
		if not LINEAGE_QUESTS.has(lineage_id):
			errors.append("Lineage '%s' is missing its entry requirement." % lineage_id)
		var seen: Array[String] = []
		for node_value in nodes:
			var node: Dictionary = node_value
			var node_id := String(node.get("node_id", ""))
			if node_id.is_empty() or seen.has(node_id):
				errors.append("Lineage '%s' has an invalid or duplicate node ID." % lineage_id)
			seen.append(node_id)
			if Array(node.get("objectives", [])).is_empty():
				errors.append("Lineage '%s' node '%s' has no quest." % [lineage_id, node_id])
	return errors


static func _objective(objective_id: String, source: Dictionary) -> Dictionary:
	return {
		"objective_id": objective_id,
		"credit_key": String(source.get("credit_key", "")),
		"description": String(source.get("description", "Requirement not yet defined.")),
		"target": maxi(int(source.get("target", 1)), 1),
		"kind": "counter",
	}


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			var text := String(entry)
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result
