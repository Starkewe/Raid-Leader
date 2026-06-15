extends CanvasLayer

@export var raid_member_frame_scene: PackedScene

@onready var raid_frame_list: VBoxContainer = $RaidFramesPanel/RaidFrameList
@onready var boss_status = get_node_or_null("StatusPanel/StatusList/BossStatus")

var frame_by_unit: Dictionary = {}

func setup_raid_frames(units: Array):
	clear_raid_frames()

	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue

		var frame = raid_member_frame_scene.instantiate()
		raid_frame_list.add_child(frame)

		var display_name = get_unit_display_name(unit)
		frame.setup(unit, display_name)

		frame_by_unit[unit] = frame

func clear_raid_frames():
	for child in raid_frame_list.get_children():
		child.queue_free()

	frame_by_unit.clear()

func refresh_raid_frames(status_overrides: Dictionary = {}):
	for unit in frame_by_unit.keys():
		if unit == null or not is_instance_valid(unit):
			continue

		var frame = frame_by_unit[unit]

		var use_status_override = status_overrides.has(unit)

		frame.update_from_unit(not use_status_override)

		if use_status_override:
			frame.set_status_text(status_overrides[unit])

func set_unit_status(unit: Node, text: String):
	if unit == null:
		return

	if not frame_by_unit.has(unit):
		return

	frame_by_unit[unit].set_status_text(text)

func set_boss_status(text: String):
	if boss_status != null:
		boss_status.text = "Boss: " + text

func get_unit_display_name(unit: Node) -> String:
	if unit.has_method("get_display_name"):
		return unit.get_display_name()

	return unit.name
