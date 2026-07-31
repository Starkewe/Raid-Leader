extends SceneTree

const RAID_MEMBER_FRAME_SCENE := preload("res://scenes/raid_member_frame.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var target := BaseCombatUnit.new()
	var frame := RAID_MEMBER_FRAME_SCENE.instantiate()
	root.add_child(target)
	root.add_child(frame)
	frame.setup(target, "Test Raider")

	var ordinary_harmful := StatusEffectDefinition.new()
	ordinary_harmful.effect_id = "ordinary_harmful"
	ordinary_harmful.display_name = "Ordinary Harmful"
	ordinary_harmful.is_harmful = true
	target.apply_status_effect(ordinary_harmful)
	frame.update_from_unit()

	if not frame.get_critical_debuff_display_state().is_empty():
		_fail("A harmful effect not marked critical displayed a raid-frame icon.")
		return

	var vulnerability := StatusEffectDefinition.new()
	vulnerability.effect_id = "slam_vulnerability"
	vulnerability.display_name = "Slam Vulnerability"
	vulnerability.is_harmful = true
	vulnerability.max_stacks = 100

	target.apply_status_effect(vulnerability)
	target.apply_status_effect(vulnerability)
	target.apply_status_effect(vulnerability)
	frame.update_from_unit()

	var displayed_debuffs: Array[Dictionary] = frame.get_critical_debuff_display_state()

	if displayed_debuffs.size() != 1:
		_fail("Slam Vulnerability did not display exactly one critical debuff icon.")
		return

	var displayed_vulnerability: Dictionary = displayed_debuffs[0]

	if int(displayed_vulnerability.get("stacks", 0)) != 3:
		_fail("The vulnerability icon did not reflect the live stack count.")
		return

	if not bool(displayed_vulnerability.get("show_stack_count", false)):
		_fail("Slam Vulnerability was not configured to show its stack count.")
		return

	if not bool(displayed_vulnerability.get("emphasize_stacking", false)):
		_fail("Slam Vulnerability was not configured as a prominent stacking debuff.")
		return

	if displayed_vulnerability.get("icon") == null:
		_fail("Slam Vulnerability did not resolve a debuff icon.")
		return

	target.remove_status_effect_stacks("slam_vulnerability", 2)
	frame.update_from_unit()
	displayed_debuffs = frame.get_critical_debuff_display_state()

	if (
		displayed_debuffs.size() != 1
		or int(displayed_debuffs[0].get("stacks", 0)) != 1
	):
		_fail("The vulnerability icon did not update after stacks were reduced.")
		return

	target.clear_status_effect("slam_vulnerability")
	frame.update_from_unit()

	if not frame.get_critical_debuff_display_state().is_empty():
		_fail("The vulnerability icon remained after the debuff was removed.")
		return

	print("Critical debuff icon regression test passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
