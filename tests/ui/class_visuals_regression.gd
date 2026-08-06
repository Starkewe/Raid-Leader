extends Node


const CLASS_VISUAL_CATALOG := preload("res://scripts/ui/class_visual_catalog.gd")
const CLASS_VISUAL_FRAME_SCENE := preload("res://scenes/raid_member_frame.tscn")
const BASE_COMBAT_UNIT := preload("res://scripts/units/base_combat_unit.gd")
const COMMAND_REFERENCE_CATALOG := preload(
	"res://scripts/ui/raid_command_reference_catalog.gd"
)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _validate_catalog():
		return

	var unit := BASE_COMBAT_UNIT.new()
	unit.name = "ClassVisualRegressionUnit"
	add_child(unit)
	unit.setup_unit_identity("Warrior", 1)

	var frame := CLASS_VISUAL_FRAME_SCENE.instantiate() as Control
	add_child(frame)
	frame.size = Vector2(154, 50)
	frame.setup(unit, "Class Visual Regression Unit (Warrior)")
	await get_tree().process_frame

	if not _validate_frame(frame, unit):
		return

	var available_classes := GameState.get_available_classes()
	if available_classes != ["Warrior", "Rogue", "Mage", "Priest"]:
		_fail("Visual-only advanced classes leaked into GameState playable classes.")
		return

	var reference_entries := COMMAND_REFERENCE_CATALOG.get_who_entries([unit], GameState)
	var base_icon := CLASS_VISUAL_CATALOG.get_base_definition("warrior").compact_icon_resource
	var found_compact_icon := false

	for entry in reference_entries:
		var metadata: Dictionary = entry.get("metadata", {})

		if metadata.get("unit", null) == unit:
			found_compact_icon = entry.get("icon", null) == base_icon
			break

	if not found_compact_icon:
		_fail("The command reference did not use the new base compact class icon.")
		return

	var original_frame_id := frame.get_instance_id()
	unit.set_advanced_class_id("hollow_anvil")
	await get_tree().process_frame
	frame.update_from_unit()

	if frame.get_instance_id() != original_frame_id:
		_fail("Changing a visual class reconstructed the raid frame.")
		return

	if frame.get_active_visual_class_id() != "hollow_anvil":
		_fail("The frame did not pick up the advanced visual class ID.")
		return

	var advanced_definition := CLASS_VISUAL_CATALOG.get_definition("hollow_anvil")
	if frame.visual_definition != advanced_definition:
		_fail("The frame did not resolve the advanced class definition.")
		return

	if not frame.get_health_fill_color().is_equal_approx(advanced_definition.main_color):
		_fail("The advanced class main color was not applied to the health fill.")
		return

	if frame.get_node("ClassIconFrame/ClassIcon").texture != advanced_definition.icon_resource:
		_fail("The advanced class icon was not updated at runtime.")
		return

	unit.set_advanced_class_id("not_a_catalog_class")
	await get_tree().process_frame
	frame.update_from_unit()

	if frame.visual_definition.class_id != "warrior":
		_fail("An unknown advanced class did not fall back to the base visual.")
		return

	unit.setup_campaign_identity(
		{
			"member_id": "campaign_visual_member",
			"display_name": "Campaign Visual Member",
			"unit_class": "Mage",
			"advanced_class_id": "orbit_scribe",
			"description": "",
			"roles": ["dps"]
		},
		1
	)

	if unit.get_advanced_class_id() != "orbit_scribe":
		_fail("Campaign spawning did not copy the stored advanced visual class ID.")
		return

	unit.queue_free()
	frame.queue_free()
	print("Class visual catalog and raid-frame regressions passed.")
	get_tree().quit(0)


func _validate_catalog() -> bool:
	var definitions := CLASS_VISUAL_CATALOG.get_all_definitions()

	if definitions.size() != 20:
		return _fail("The class visual catalog does not contain exactly 20 entries.")

	for definition in definitions:
		if definition.class_id.is_empty() or definition.display_name.is_empty():
			return _fail("A class visual definition is missing its identity fields.")

		if definition.icon_resource == null or definition.compact_icon_resource == null:
			return _fail("A class visual definition is missing an icon resource.")

		if definition.icon_resource.get_width() != 128 or definition.icon_resource.get_height() != 128:
			return _fail("A raid-frame class master is not 128x128.")

		if definition.compact_icon_resource.get_width() != 16 or definition.compact_icon_resource.get_height() != 16:
			return _fail("A compact class icon is not 16x16.")

		if definition.main_color.a <= 0.0:
			return _fail("A class visual definition has an invalid main color.")

	for base_id in ["warrior", "rogue", "mage", "priest"]:
		var base := CLASS_VISUAL_CATALOG.get_definition(base_id)

		if base == null or base.accent_color.a > 0.0:
			return _fail("Base class colors or transparent accents are invalid.")

	if CLASS_VISUAL_CATALOG.resolve_for_unit("Warrior", "Hollow Anvil").class_id != "hollow_anvil":
		return _fail("Advanced visual precedence is invalid.")

	if CLASS_VISUAL_CATALOG.resolve_for_unit("Warrior", "unknown").class_id != "warrior":
		return _fail("Base visual fallback is invalid.")

	return true


func _validate_frame(frame: Control, unit: Node) -> bool:
	if not frame.size.is_equal_approx(Vector2(154, 50)):
		return _fail("The raid frame footprint changed.")

	if frame.get_node_or_null("NumberLabel") != null or frame.get_node_or_null("RoleIcon") != null:
		return _fail("The obsolete number or role compartment remains in the raid frame.")

	var icon_frame := frame.get_node("ClassIconFrame") as Control
	if icon_frame == null or not icon_frame.size.is_equal_approx(Vector2(44, 44)):
		return _fail("The class icon block is not approximately 44x44.")

	var health_rect: Rect2 = frame.get_health_region_rect()
	if not health_rect.position.is_equal_approx(Vector2(48, 2)):
		return _fail("The health region does not begin after the class icon block.")

	if health_rect.size.x <= 100.0 or health_rect.size.y <= 40.0:
		return _fail("The health region lost its recovered width or height.")

	if frame.get_node("NameLabel").horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
		return _fail("The raid-frame name is not centered inside the health region.")

	if not unit.has_method("get_dodge_charge_display"):
		return _fail("The dodge-charge state accessor is unavailable.")

	return true


func _fail(message: String) -> bool:
	push_error(message)
	get_tree().quit(1)
	return false
