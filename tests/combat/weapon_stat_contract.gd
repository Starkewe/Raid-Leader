extends Node

const AdapterScript := preload("res://scripts/combat/weapon_stat_adapter.gd")


func _ready() -> void:
	var failures: Array[String] = []
	_validate_warrior(failures)
	_validate_rogue(failures)
	_validate_mage(failures)
	_validate_priest(failures)
	_validate_identity_fallback(failures)
	_finish(failures)


func _validate_warrior(failures: Array[String]) -> void:
	var unit := Warrior.new()
	unit.configure_from_definition(GameState.get_unit_definition("Warrior"))
	unit.setup_campaign_identity(_member("Warrior", "earthgnasher_heartmaul"), 1)
	if unit.attack_damage != 12:
		failures.append("Warrior weapon power did not modify damage (expected 12).")
	if not is_equal_approx(unit.attack_cooldown, 1.0 / 0.9):
		failures.append("Warrior weapon speed did not modify attack cadence.")
	if not is_equal_approx(unit.attack_range_units, 5.5):
		failures.append("Warrior weapon range was not additive.")
	unit.free()


func _validate_rogue(failures: Array[String]) -> void:
	var unit := Rogue.new()
	unit.configure_from_definition(GameState.get_unit_definition("Rogue"))
	unit.setup_campaign_identity(_member("Rogue", "twin_fang_knives"), 1)
	if unit.attack_damage != 8:
		failures.append("Rogue weapon power rounding changed unexpectedly.")
	if not is_equal_approx(unit.attack_cooldown, 0.8 / 1.12):
		failures.append("Rogue weapon speed did not improve attack cadence.")
	unit.free()


func _validate_mage(failures: Array[String]) -> void:
	var unit := Mage.new()
	unit.configure_from_definition(GameState.get_unit_definition("Mage"))
	unit.setup_campaign_identity(_member("Mage", "carrion_resonator"), 1)
	if unit.spell_damage != 20:
		failures.append("Mage weapon power did not modify spell damage.")
	if not is_equal_approx(unit.spell_cast_time, 1.5):
		failures.append("Mage 1.00 speed profile did not preserve authored cast timing.")
	if not is_equal_approx(unit.cast_range_units, 42.0):
		failures.append("Mage weapon range was not additive.")
	unit.free()


func _validate_priest(failures: Array[String]) -> void:
	var unit := Priest.new()
	unit.configure_from_definition(GameState.get_unit_definition("Priest"))
	unit.setup_campaign_identity(_member("Priest", "litany_of_links"), 1)
	if unit.heal_amount != 20:
		failures.append("Priest weapon power did not modify healing.")
	if not is_equal_approx(unit.heal_cast_time, 2.0 / 0.95):
		failures.append("Priest weapon speed did not modify cast timing.")
	if not is_equal_approx(unit.cast_range_units, 42.0):
		failures.append("Priest weapon range was not additive.")
	unit.free()


func _validate_identity_fallback(failures: Array[String]) -> void:
	if AdapterScript.apply_power(10, {}) != 10:
		failures.append("No-weapon power fallback changed legacy combat.")
	if not is_equal_approx(AdapterScript.apply_timing(2.0, {}), 2.0):
		failures.append("No-weapon timing fallback changed legacy combat.")
	if not is_equal_approx(AdapterScript.apply_range(5.0, {}), 5.0):
		failures.append("No-weapon range fallback changed legacy combat.")
	var invalid := {"power_multiplier": 0.0, "speed_multiplier": -1.0, "range_additive": 9.0}
	if AdapterScript.apply_power(10, invalid) != 10:
		failures.append("Invalid saved profile did not fall back safely.")
	var warrior := Warrior.new()
	warrior.configure_from_definition(GameState.get_unit_definition("Warrior"))
	warrior.setup_unit_identity("Warrior", 1)
	if warrior.attack_damage != 10 or not is_equal_approx(warrior.attack_cooldown, 1.0):
		failures.append("Legacy Warrior combat changed without a weapon.")
	warrior.free()


func _member(unit_class: String, weapon_id: String) -> Dictionary:
	var weapon := ProgressionCatalog.get_weapon(weapon_id)
	return {
		"member_id": "contract_" + unit_class.to_lower(),
		"display_name": "Contract " + unit_class,
		"unit_class": unit_class,
		"role": "dps",
		"roles": ["dps"],
		"advanced_class_id": "",
		"description": "",
		"equipped_weapon_id": weapon_id,
		"weapon_runtime_active": true,
		"weapon_stat_profile": weapon.stat_profile.to_dictionary(),
	}


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("RAID_TEST_PASS:weapon_stat_contract | Weapon stat adapter contract passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

