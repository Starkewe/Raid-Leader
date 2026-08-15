extends Node

const ProgressionServiceScript := preload(
	"res://scripts/core/campaign_progression_service.gd"
)
const RaiderStateScript := preload("res://scripts/data/campaign_raider_state.gd")
const SAVE_PATH := "user://progression_crafting_equipment_contract.json"


func _ready() -> void:
	var failures: Array[String] = []
	CampaignState.reset_campaign(false, 737373)
	var class_members := _members_by_class()
	_validate_crafting(class_members, failures)
	_validate_equipment(class_members, failures)
	_validate_traits(failures)
	_validate_persistence(class_members, failures)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_finish(failures)


func _validate_crafting(
	_class_members: Dictionary, failures: Array[String]
) -> void:
	var locked := CampaignState.check_craft("craft_litany_of_links")
	if locked.get("status") != "locked_recipe":
		failures.append("Locked recipe did not report locked_recipe.")
	var first_clear := CampaignState.debug_process_seeded_reward("ogre", "crafting_first_clear")
	if not bool(first_clear.get("ok", false)):
		failures.append("Could not unlock Earthgnasher recipes: %s" % first_clear)
	var insufficient := CampaignState.check_craft("craft_earthgnasher_heartmaul")
	if insufficient.get("status") != "insufficient_materials":
		failures.append("Underfunded recipe did not report insufficient_materials.")
	var grants := {
		"earthgnasher_heartstone": 1,
		"quake_marrow": 2,
		"tempered_chainlink": 2,
	}
	var grant_result := CampaignState.debug_grant_progression_materials(grants)
	if not bool(grant_result.get("ok", false)):
		failures.append("Fixture materials could not be granted: %s" % grant_result)
	var before_counts: Dictionary = {}
	for material_id in grants:
		before_counts[material_id] = CampaignState.get_material_count(material_id)
	var craft_result := CampaignState.craft("craft_earthgnasher_heartmaul")
	if craft_result.get("status") != "crafted":
		failures.append("Atomic craft did not succeed: %s" % craft_result)
	if not CampaignState.owns_crafted_weapon("earthgnasher_heartmaul"):
		failures.append("Crafted weapon ownership was not persisted in campaign state.")
	for material_id in grants:
		var consumed := int(grants[material_id])
		if CampaignState.get_material_count(material_id) != int(before_counts[material_id]) - consumed:
			failures.append("Craft did not consume exact quantity for '%s'." % material_id)
	var duplicate := CampaignState.craft("craft_earthgnasher_heartmaul")
	if duplicate.get("status") != "already_owned":
		failures.append("Duplicate craft did not report already_owned.")
	if CampaignState.check_craft("unknown_recipe").get("status") != "unknown_definition":
		failures.append("Unknown recipe did not report unknown_definition.")


func _validate_equipment(
	class_members: Dictionary, failures: Array[String]
) -> void:
	var warriors: Array = class_members.get("Warrior", [])
	var mages: Array = class_members.get("Mage", [])
	var rogues: Array = class_members.get("Rogue", [])
	if warriors.size() < 2 or mages.is_empty() or rogues.is_empty():
		failures.append("Fixture campaign did not contain required class representatives.")
		return
	var warrior_a := String(warriors[0])
	var warrior_b := String(warriors[1])
	var mage_id := String(mages[0])
	var rogue_id := String(rogues[0])
	if CampaignState.check_equip_weapon(warrior_a, "faultline_cudgel").get("status") != "not_crafted":
		failures.append("Uncrafted weapon did not report not_crafted.")
	if CampaignState.check_equip_weapon(mage_id, "earthgnasher_heartmaul").get("status") != "incompatible_family":
		failures.append("Incompatible base class did not report incompatible_family.")
	var equipped := CampaignState.equip_weapon(warrior_a, "earthgnasher_heartmaul")
	if equipped.get("status") != "equipped":
		failures.append("Unique weapon could not equip its first compatible warrior.")
	var already := CampaignState.check_equip_weapon(warrior_a, "earthgnasher_heartmaul")
	if already.get("status") != "already_equipped" or already.get("holder_id") != warrior_a:
		failures.append("Current holder did not report already_equipped with its holder ID.")
	var assigned := CampaignState.check_equip_weapon(warrior_b, "earthgnasher_heartmaul")
	if assigned.get("status") != "assigned_elsewhere" or assigned.get("holder_id") != warrior_a:
		failures.append("Second raider did not see assigned_elsewhere with the current holder ID.")
	if CampaignState.equip_weapon(warrior_b, "earthgnasher_heartmaul").get("status") != "assigned_elsewhere":
		failures.append("A unique weapon was reused without manual unequip.")
	if CampaignState.get_weapon_holder_id("earthgnasher_heartmaul") != warrior_a:
		failures.append("Unique weapon holder lookup returned the wrong raider.")
	if CampaignState.get_equipped_raider_ids("earthgnasher_heartmaul") != [warrior_a]:
		failures.append("Compatibility getter exposed more than the unique holder.")

	var projected := CampaignState.get_member(warrior_a)
	if not bool(projected.get("weapon_runtime_active", false)):
		failures.append("Equipped weapon was not projected into combat member data.")
	if projected.get("weapon_stat_profile", {}).is_empty():
		failures.append("Combat member projection omitted weapon stats.")
	if CampaignState.unequip_weapon(warrior_a).get("status") != "unequipped":
		failures.append("Current holder could not manually unequip the weapon.")

	if CampaignState.check_equip_weapon(rogue_id, "earthgnasher_heartmaul").get("status") != "incompatible_family":
		failures.append("Base Rogue incorrectly equipped Heavy Arms.")
	if not CampaignState.advance_raider_class(rogue_id, "echo_butcher"):
		failures.append("Could not exercise independent advanced-class seam.")
	elif CampaignState.equip_weapon(rogue_id, "earthgnasher_heartmaul").get("status") != "equipped":
		failures.append("Echo Butcher did not receive Heavy Arms compatibility.")
	if not CampaignState.owns_advancement_token("earthgnasher_warrior_token"):
		failures.append("Equipment/class seam unexpectedly consumed the boss token.")
	CampaignState.unequip_weapon(rogue_id)
	if CampaignState.equip_weapon(warrior_b, "earthgnasher_heartmaul").get("status") != "equipped":
		failures.append("Weapon did not become available after its holder manually unequipped it.")

	CampaignState.debug_grant_progression_materials({
		"earthgnasher_heartstone": 1, "quake_marrow": 2, "rage_slick_hide": 2,
	})
	if CampaignState.craft("craft_faultline_cudgel").get("status") != "crafted":
		failures.append("Replacement-weapon fixture could not be crafted.")
	else:
		var replacement := CampaignState.equip_weapon(warrior_b, "faultline_cudgel")
		if replacement.get("status") != "equipped":
			failures.append("Compatible replacement weapon could not be equipped.")
		elif replacement.get("previous_weapon_id") != "earthgnasher_heartmaul":
			failures.append("Replacement result omitted the released previous weapon ID.")
		if not CampaignState.get_weapon_holder_id("earthgnasher_heartmaul").is_empty():
			failures.append("Replacing equipment did not return the previous weapon to the armory.")
		if CampaignState.equip_weapon(warrior_a, "earthgnasher_heartmaul").get("status") != "equipped":
			failures.append("Released previous weapon could not be assigned to another raider.")

	var swap_check := CampaignState.check_move_or_swap_equipped_weapon(warrior_a, warrior_b)
	if swap_check.get("status") != "swappable":
		failures.append("Two compatible equipped raid frames did not report swappable.")
	else:
		var swapped := CampaignState.move_or_swap_equipped_weapon(warrior_a, warrior_b)
		if swapped.get("status") != "swapped":
			failures.append("Compatible raid-frame weapons did not swap atomically.")
		elif (
			CampaignState.get_weapon_holder_id("earthgnasher_heartmaul") != warrior_b
			or CampaignState.get_weapon_holder_id("faultline_cudgel") != warrior_a
		):
			failures.append("Atomic swap wrote the wrong weapon holders.")
		if CampaignState.move_or_swap_equipped_weapon(warrior_b, warrior_a).get("status") != "swapped":
			failures.append("The compatible swap could not be reversed for persistence coverage.")

	var before_incompatible: Dictionary = Dictionary(
		CampaignState.get_campaign_snapshot().get("raider_states", {})
	).duplicate(true)
	var incompatible_move := CampaignState.move_or_swap_equipped_weapon(warrior_a, mage_id)
	if incompatible_move.get("status") != "source_incompatible_with_destination":
		failures.append("Frame transfer to an incompatible raider did not report its source incompatibility.")
	if CampaignState.get_campaign_snapshot().get("raider_states", {}) != before_incompatible:
		failures.append("Rejected frame transfer partially mutated raider equipment.")

	if CampaignState.unequip_weapon(warrior_b).get("status") != "unequipped":
		failures.append("Move fixture could not clear the destination frame.")
	elif CampaignState.move_or_swap_equipped_weapon(warrior_a, warrior_b).get("status") != "moved":
		failures.append("Equipped weapon did not move atomically to an empty compatible frame.")
	elif not String(CampaignState.get_member(warrior_a).get("equipped_weapon_id", "")).is_empty():
		failures.append("Atomic move did not clear its source frame.")
	elif CampaignState.move_or_swap_equipped_weapon(warrior_b, warrior_a).get("status") != "moved":
		failures.append("Moved weapon could not be returned to its original holder.")
	if CampaignState.equip_weapon(warrior_b, "faultline_cudgel").get("status") != "equipped":
		failures.append("Move/swap contract could not restore the replacement weapon fixture.")

	var states: Dictionary = CampaignState.get_campaign_snapshot().get("raider_states", {})
	states[warrior_b]["equipped_weapon_id"] = "returning_content_weapon"
	if not CampaignState.debug_replace_raider_states(states):
		failures.append("Could not install missing-content recovery fixture.")
	else:
		var missing_projection := CampaignState.get_member(warrior_b)
		if missing_projection.get("equipped_weapon_id") != "returning_content_weapon":
			failures.append("Unknown saved weapon ID was not retained.")
		if bool(missing_projection.get("weapon_runtime_active", true)):
			failures.append("Unknown saved weapon remained active at runtime.")
		var found_diagnostic := false
		for diagnostic in CampaignState.get_progression_diagnostics():
			if diagnostic.get("stable_id") == "returning_content_weapon":
				found_diagnostic = true
		if not found_diagnostic:
			failures.append("Unknown saved weapon did not report missing-content diagnostics.")
		if CampaignState.unequip_weapon(warrior_b).get("status") != "unequipped":
			failures.append("Missing-content weapon could not be unequipped for recovery.")
		if not String(CampaignState.get_member(warrior_b).get("equipped_weapon_id", "")).is_empty():
			failures.append("Missing-content unequip did not clear the saved slot.")


func _validate_traits(failures: Array[String]) -> void:
	var campaign := CampaignState.get_campaign_snapshot()
	var raider_ids: Array = campaign.get("raider_states", {}).keys()
	if raider_ids.is_empty():
		return
	var raider_id := String(raider_ids[0])
	var catalog := ProgressionCatalog.get_catalog().duplicate(true) as ProgressionCatalogResource
	var major := _trait("fixture_major", "major")
	var minor_a := _trait("fixture_minor_a", "minor")
	var minor_b := _trait("fixture_minor_b", "minor")
	catalog.raider_traits = [major, minor_a, minor_b]
	var service = ProgressionServiceScript.new()
	if service.assign_major_trait(campaign, raider_id, major.trait_id, catalog).get("status") != "assigned":
		failures.append("Major trait could not be assigned.")
	if service.assign_major_trait(campaign, raider_id, minor_a.trait_id, catalog).get("status") != "incompatible_tier":
		failures.append("Minor trait entered the major slot.")
	if service.assign_minor_trait(campaign, raider_id, 0, minor_a.trait_id, catalog).get("status") != "assigned":
		failures.append("First minor trait could not be assigned.")
	if service.assign_minor_trait(campaign, raider_id, 1, minor_b.trait_id, catalog).get("status") != "assigned":
		failures.append("Second minor trait could not be assigned.")
	if service.assign_minor_trait(campaign, raider_id, 1, minor_a.trait_id, catalog).get("status") != "duplicate_trait":
		failures.append("Duplicate raider trait was not rejected.")
	if service.assign_minor_trait(campaign, raider_id, 2, minor_b.trait_id, catalog).get("status") != "invalid_slot":
		failures.append("Third minor trait slot was accepted.")
	if service.assign_major_trait(campaign, raider_id, "", catalog).get("status") != "cleared":
		failures.append("Major trait slot could not be cleared.")
	if service.assign_minor_trait(campaign, raider_id, 0, "", catalog).get("status") != "cleared":
		failures.append("Minor trait slot could not be cleared.")
	var trait_state := service.get_raider_traits(campaign, raider_id)
	if not String(trait_state.get("major_trait_id", "")).is_empty():
		failures.append("Cleared major trait persisted.")
	if Array(trait_state.get("minor_trait_ids", [])).size() != 2:
		failures.append("Trait scaffold did not retain exactly two minor slots.")
	var encoded := JSON.stringify(campaign["raider_states"][raider_id])
	var parsed: Dictionary = JSON.parse_string(encoded)
	var sanitized := RaiderStateScript.sanitize(parsed, raider_id, "Warrior")
	if sanitized.get("minor_trait_ids", []).size() > 2:
		failures.append("Trait slots did not survive persistence sanitization.")
	if not String(sanitized.get("doctrine_id", "")).is_empty():
		failures.append("Doctrine placeholder acquired behavior/content unexpectedly.")
	if CampaignState.assign_raider_major_trait(raider_id, "fixture_major").get("status") != "unknown_definition":
		failures.append("Production catalog unexpectedly exposed fixture traits.")


func _validate_persistence(
	class_members: Dictionary, failures: Array[String]
) -> void:
	var warriors: Array = class_members.get("Warrior", [])
	if warriors.is_empty():
		return
	var warrior_id := String(warriors[0])
	if not CampaignState.write_campaign(SAVE_PATH, {"kind": "contract"}):
		failures.append("Crafting/equipment save could not be written.")
		return
	if not CampaignState.load_campaign(SAVE_PATH):
		failures.append("Crafting/equipment save could not be loaded.")
		return
	if not CampaignState.owns_crafted_weapon("earthgnasher_heartmaul"):
		failures.append("Crafted ownership did not survive save/load.")
	if CampaignState.get_member(warrior_id).get("equipped_weapon_id") != "earthgnasher_heartmaul":
		failures.append("Equipped weapon did not survive save/load.")


func _members_by_class() -> Dictionary:
	var result: Dictionary = {}
	for member in CampaignState.get_roster_members():
		var unit_class := String(member.get("unit_class", ""))
		var ids: Array = result.get(unit_class, [])
		ids.append(String(member.get("member_id", "")))
		result[unit_class] = ids
	return result


func _trait(trait_id: String, tier: String) -> RaiderTraitDefinition:
	var result := RaiderTraitDefinition.new()
	result.trait_id = trait_id
	result.display_name = trait_id.capitalize()
	result.tier = tier
	result.description = "Contract fixture."
	result.hook_id = trait_id + "_hook"
	return result


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("RAID_TEST_PASS:progression_crafting_equipment_contract | Crafting, equipment, and trait contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
