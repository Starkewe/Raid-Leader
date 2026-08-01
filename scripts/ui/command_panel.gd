extends PanelContainer

class_name CommandPanel

const RaidCommandReferenceCatalogScript := preload(
	"res://scripts/ui/raid_command_reference_catalog.gd"
)

signal command_submitted(command_data: Dictionary)

var who_dropdown: OptionButton = null
var what_dropdown: OptionButton = null
var where_dropdown: OptionButton = null
var when_dropdown: OptionButton = null
var execute_button: Button = null
var voice_status_label: Label = null

var party_members: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(300, 0)

	build_panel()
	populate_who_options()
	populate_what_options()
	populate_where_options_for_current_action()
	populate_when_options()

	if what_dropdown != null:
		what_dropdown.item_selected.connect(_on_what_selected)

	if execute_button != null:
		execute_button.pressed.connect(_on_execute_pressed)


func setup_units(new_party_members: Array) -> void:
	party_members = new_party_members

	if who_dropdown == null:
		return

	populate_who_options()


func build_panel() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	voice_status_label = Label.new()
	voice_status_label.text = "Voice: Ready (hold V)"
	voice_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voice_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(voice_status_label)

	add_separator(root)

	add_section_label(root, "Who")
	who_dropdown = OptionButton.new()
	root.add_child(who_dropdown)

	add_separator(root)

	add_section_label(root, "What")
	what_dropdown = OptionButton.new()
	root.add_child(what_dropdown)

	add_separator(root)

	add_section_label(root, "Where")
	where_dropdown = OptionButton.new()
	root.add_child(where_dropdown)

	add_separator(root)

	add_section_label(root, "When")
	when_dropdown = OptionButton.new()
	when_dropdown.disabled = true
	root.add_child(when_dropdown)

	add_separator(root)

	execute_button = Button.new()
	execute_button.text = "Execute Command"
	root.add_child(execute_button)


func add_section_label(parent: Node, label_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)


func add_separator(parent: Node) -> void:
	var separator := HSeparator.new()
	parent.add_child(separator)


func populate_who_options() -> void:
	if who_dropdown == null:
		return

	who_dropdown.clear()

	for entry in RaidCommandReferenceCatalogScript.get_who_entries(party_members, GameState):
		add_option(
			who_dropdown,
			String(entry.get("label", "")),
			Dictionary(entry.get("metadata", {}))
		)

	who_dropdown.select(0)


func populate_what_options() -> void:
	if what_dropdown == null:
		return

	what_dropdown.clear()

	for entry in RaidCommandReferenceCatalogScript.get_what_entries():
		add_option(
			what_dropdown,
			String(entry.get("label", "")),
			Dictionary(entry.get("metadata", {}))
		)

	what_dropdown.select(0)


func populate_where_options_for_current_action() -> void:
	if where_dropdown == null:
		return

	where_dropdown.clear()

	var selected_action := get_selected_what()

	for entry in RaidCommandReferenceCatalogScript.get_where_entries_for_action(
		selected_action,
		party_members,
		GameState
	):
		add_option(
			where_dropdown,
			String(entry.get("label", "")),
			Dictionary(entry.get("metadata", {}))
		)

	where_dropdown.select(0)


func populate_when_options() -> void:
	if when_dropdown == null:
		return

	when_dropdown.clear()

	for entry in RaidCommandReferenceCatalogScript.get_when_entries():
		var metadata: Dictionary = entry.get("metadata", {})
		add_option(when_dropdown, "Now", metadata)

	when_dropdown.select(0)


func add_option(dropdown: OptionButton, label_text: String, metadata: Dictionary) -> void:
	var index := dropdown.get_item_count()
	dropdown.add_item(label_text)
	dropdown.set_item_metadata(index, metadata)


func get_selected_metadata(dropdown: OptionButton) -> Dictionary:
	if dropdown == null:
		return {}

	if dropdown.get_item_count() == 0:
		return {}

	var selected_index := dropdown.selected

	if selected_index < 0:
		return {}

	var metadata = dropdown.get_item_metadata(selected_index)

	if metadata is Dictionary:
		return metadata

	return {}


func get_selected_what() -> String:
	if what_dropdown == null:
		return "attack"

	var metadata := get_selected_metadata(what_dropdown)

	return String(metadata.get("what", "attack"))


func build_command_data() -> Dictionary:
	var who_data := get_selected_metadata(who_dropdown)
	var what_data := get_selected_metadata(what_dropdown)
	var where_data := get_selected_metadata(where_dropdown)
	var when_data := get_selected_metadata(when_dropdown)

	var command_data := {
		"who_type": String(who_data.get("who_type", "everyone")),
		"who_value": who_data.get("who_value", ""),
		"unit": who_data.get("unit", null),
		"what": String(what_data.get("what", "attack")),
		"where": String(where_data.get("where", "none")),
		"when": String(when_data.get("when", "now"))
	}

	for key in where_data.keys():
		if not command_data.has(key):
			command_data[key] = where_data[key]

	return command_data

func _on_what_selected(_index: int) -> void:
	populate_where_options_for_current_action()


func _on_execute_pressed() -> void:
	var command_data := build_command_data()

	print("CommandPanel submitted:", command_data)

	command_submitted.emit(command_data)


func set_voice_status(text: String, is_error: bool = false) -> void:
	if voice_status_label == null:
		return

	voice_status_label.text = "Voice: " + text
	voice_status_label.modulate = Color(1.0, 0.55, 0.55) if is_error else Color.WHITE
