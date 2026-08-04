extends Node

const COMBAT_SCENE := preload("res://scenes/combat_scene.tscn")
const BaseCombatUnitScript := preload("res://scripts/units/base_combat_unit.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var combat_scene := COMBAT_SCENE.instantiate()
	get_tree().root.add_child(combat_scene)
	await get_tree().process_frame

	var ui := combat_scene.get_node("UI")
	var units: Array = []

	for index in range(20):
		var unit := BaseCombatUnitScript.new()
		unit.name = "LayoutTestUnit%d" % (index + 1)
		unit.unit_number = index + 1
		combat_scene.add_child(unit)
		units.append(unit)

	ui.setup_raid_frames(units)
	await get_tree().process_frame

	if not _validate_full_raid_layout(ui):
		combat_scene.queue_free()
		return

	var partial_units: Array = units.slice(0, 6)
	ui.setup_raid_frames(partial_units)
	await get_tree().process_frame

	if not _validate_partial_raid_layout(ui):
		combat_scene.queue_free()
		return

	combat_scene.queue_free()
	print("Raid frame layout regression test passed.")
	get_tree().quit(0)


func _validate_full_raid_layout(ui: Node) -> bool:
	var stack := ui.get_node_or_null("RaidFramesPanel/RaidFrameStack") as VBoxContainer

	if stack == null:
		return _fail("The raid frame stack is missing.")

	if stack.get_child_count() != 4:
		return _fail("A full raid did not produce exactly four group sections.")

	if not (ui.get_node("RaidFramesPanel") as Control).position.is_equal_approx(Vector2(12, 8)):
		return _fail("The raid frame panel is not anchored to the configured top-left margin.")

	for group_index in range(4):
		var group_section := stack.get_child(group_index) as VBoxContainer
		var expected_group_number := group_index + 1

		if group_section == null or group_section.name != "Group%dSection" % expected_group_number:
			return _fail("Raid group sections are not ordered from Group 1 through Group 4.")

		var group_label := group_section.get_node("GroupLabel") as Label

		if group_label == null or group_label.text != "Group %d" % expected_group_number:
			return _fail("A raid group label is missing or has the wrong number.")

		var member_stack := group_section.get_node("MemberFrames") as VBoxContainer

		if member_stack == null or member_stack.get_child_count() != 5:
			return _fail("A full raid group does not contain five member frames.")

		for frame_index in range(member_stack.get_child_count()):
			var frame := member_stack.get_child(frame_index) as Control

			if frame == null or not frame.size.is_equal_approx(Vector2(154, 50)):
				return _fail("A raid frame is not using the compact 154x50 footprint.")

			if absf(frame.position.x) > 0.1:
				return _fail("Raid frames in a group are not aligned to one vertical column.")

			if frame_index > 0:
				var previous_frame := member_stack.get_child(frame_index - 1) as Control

				if frame.position.y <= previous_frame.position.y:
					return _fail("Member frames within a group are not stacked vertically.")

	return true


func _validate_partial_raid_layout(ui: Node) -> bool:
	var stack := ui.get_node_or_null("RaidFramesPanel/RaidFrameStack") as VBoxContainer

	if stack == null or stack.get_child_count() != 2:
		return _fail("A six-member raid did not produce only Group 1 and Group 2 sections.")

	var first_label := stack.get_child(0).get_node("GroupLabel") as Label
	var second_label := stack.get_child(1).get_node("GroupLabel") as Label

	if first_label.text != "Group 1" or second_label.text != "Group 2":
		return _fail("Partial raid group labels are not ordered correctly.")

	var second_member_stack := stack.get_child(1).get_node("MemberFrames") as VBoxContainer

	if second_member_stack == null or second_member_stack.get_child_count() != 1:
		return _fail("The partial second group does not contain its single member.")

	var frame_map_value: Variant = ui.get("frame_by_unit")

	if not frame_map_value is Dictionary or Dictionary(frame_map_value).size() != 6:
		return _fail("The frame-to-unit mapping was not preserved for a partial raid.")

	return true


func _fail(message: String) -> bool:
	push_error(message)
	get_tree().quit(1)
	return false
