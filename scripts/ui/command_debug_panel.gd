extends PanelContainer
class_name CommandDebugPanel

var source_value_label: Label = null
var transcript_value_label: Label = null
var normalized_value_label: Label = null
var who_value_label: Label = null
var what_value_label: Label = null
var where_value_label: Label = null
var result_value_label: Label = null
var command_data_value_label: Label = null


func _ready() -> void:
	build_panel()
	clear_debug_data()


func build_panel() -> void:
	custom_minimum_size = Vector2(460, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Command Debug"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	add_separator(root)

	source_value_label = add_debug_row(root, "Source")
	transcript_value_label = add_debug_row(root, "Transcript")
	normalized_value_label = add_debug_row(root, "Normalized")
	who_value_label = add_debug_row(root, "Who")
	what_value_label = add_debug_row(root, "What")
	where_value_label = add_debug_row(root, "Where")
	result_value_label = add_debug_row(root, "Result")

	add_separator(root)

	command_data_value_label = add_debug_row(root, "Command Data")


func add_separator(parent: Node) -> void:
	var separator := HSeparator.new()
	parent.add_child(separator)


func add_debug_row(parent: Node, label_text: String) -> Label:
	var header := Label.new()
	header.text = label_text + ":"
	parent.add_child(header)

	var value := Label.new()
	value.text = "-"
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.custom_minimum_size = Vector2(430, 0)
	parent.add_child(value)

	return value


func set_debug_data(data: Dictionary) -> void:
	set_label_text(source_value_label, String(data.get("source", "-")))
	set_label_text(transcript_value_label, String(data.get("transcript", "-")))
	set_label_text(normalized_value_label, String(data.get("normalized", "-")))
	set_label_text(who_value_label, String(data.get("who", "-")))
	set_label_text(what_value_label, String(data.get("what", "-")))
	set_label_text(where_value_label, String(data.get("where", "-")))
	set_label_text(result_value_label, String(data.get("result", "-")))
	set_label_text(command_data_value_label, String(data.get("command_data", "-")))


func clear_debug_data() -> void:
	set_debug_data({
		"source": "-",
		"transcript": "-",
		"normalized": "-",
		"who": "-",
		"what": "-",
		"where": "-",
		"result": "Waiting for command...",
		"command_data": "-"
	})


func set_label_text(label: Label, text: String) -> void:
	if label == null:
		return

	if text.strip_edges().is_empty():
		label.text = "-"
	else:
		label.text = text
