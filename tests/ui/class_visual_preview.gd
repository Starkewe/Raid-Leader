extends Control


const ClassVisualCatalogScript := preload("res://scripts/ui/class_visual_catalog.gd")

const PREVIEW_SIZE := Vector2(1920, 1080)
const CARD_SIZE := Vector2(460, 184)
const CARD_GAP := Vector2(12, 10)
const GRID_COLUMNS := 4
const OUTER_MARGIN := Vector2(24, 22)


func _ready() -> void:
	custom_minimum_size = PREVIEW_SIZE
	size = PREVIEW_SIZE
	_build_preview()

	if OS.get_environment("RAID_CLASS_VISUAL_CAPTURE") == "1":
		await get_tree().process_frame
		await get_tree().process_frame
		var viewport_texture := get_viewport().get_texture()

		if viewport_texture != null:
			var image := viewport_texture.get_image()
			image.save_png("res://tests/ui/class_visual_preview_capture.png")

		get_tree().quit(0)


func _build_preview() -> void:
	var background := ColorRect.new()
	background.color = Color("101419")
	background.position = Vector2.ZERO
	background.size = PREVIEW_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var title := Label.new()
	title.text = "Class Visual Catalog — 1254px masters / 44px raid tile / 16px command icon"
	title.position = OUTER_MARGIN
	title.size = Vector2(1700, 30)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("ded4bc"))
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Supplied opaque artwork is shown without chroma-keying or recoloring."
	subtitle.position = OUTER_MARGIN + Vector2(0, 29)
	subtitle.size = Vector2(1700, 22)
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color("8f9aa8"))
	add_child(subtitle)

	var definitions := ClassVisualCatalogScript.get_all_definitions()

	for index in range(definitions.size()):
		var definition := definitions[index]
		var column := index % GRID_COLUMNS
		var row := floori(float(index) / float(GRID_COLUMNS))
		var card_position := OUTER_MARGIN + Vector2(
			float(column) * (CARD_SIZE.x + CARD_GAP.x),
			72.0 + float(row) * (CARD_SIZE.y + CARD_GAP.y)
		)
		_add_card(definition, card_position)


func _add_card(definition, card_position: Vector2) -> void:
	var card := Panel.new()
	card.position = card_position
	card.size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("171d24")
	card_style.border_color = definition.main_color
	card_style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", card_style)
	add_child(card)

	var name_label := Label.new()
	name_label.text = "%s  [%s]" % [definition.display_name, definition.class_id]
	name_label.position = Vector2(10, 8)
	name_label.size = Vector2(440, 22)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color("f1eadb"))
	card.add_child(name_label)

	_add_caption(card, "MASTER 1254", Vector2(10, 34), Vector2(128, 16))
	_add_caption(card, "RAID 44", Vector2(156, 34), Vector2(78, 16))
	_add_caption(card, "COMPACT 16", Vector2(260, 34), Vector2(90, 16))
	_add_caption(card, "COLORS", Vector2(360, 34), Vector2(70, 16))

	var master := TextureRect.new()
	master.texture = definition.icon_resource
	master.position = Vector2(10, 52)
	master.size = Vector2(128, 128)
	master.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	master.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	master.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(master)

	var raid_backing := Panel.new()
	raid_backing.position = Vector2(156, 52)
	raid_backing.size = Vector2(48, 48)
	raid_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var raid_style := StyleBoxFlat.new()
	raid_style.bg_color = Color("0b0e12")
	raid_style.border_color = definition.main_color
	raid_style.set_border_width_all(1)
	raid_backing.add_theme_stylebox_override("panel", raid_style)
	card.add_child(raid_backing)

	var raid_icon := TextureRect.new()
	raid_icon.texture = definition.icon_resource
	raid_icon.position = Vector2(158, 54)
	raid_icon.size = Vector2(44, 44)
	raid_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	raid_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	raid_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(raid_icon)

	var compact := TextureRect.new()
	compact.texture = definition.compact_icon_resource
	compact.position = Vector2(260, 54)
	compact.size = Vector2(64, 64)
	compact.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	compact.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	compact.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(compact)

	_add_swatch(card, definition.main_color, "Main  %s" % _color_hex(definition.main_color), Vector2(360, 58))
	_add_swatch(card, definition.accent_color, "Accent %s" % _color_hex(definition.accent_color), Vector2(360, 96))


func _add_caption(parent: Control, text: String, position: Vector2, label_size: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.size = label_size
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color("8f9aa8"))
	parent.add_child(label)


func _add_swatch(parent: Control, color: Color, text: String, position: Vector2) -> void:
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.position = position
	swatch.size = Vector2(24, 24)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(swatch)

	var label := Label.new()
	label.text = text
	label.position = position + Vector2(30, 2)
	label.size = Vector2(90, 20)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color("c8d0dc"))
	parent.add_child(label)


func _color_hex(color: Color) -> String:
	if color.a <= 0.0:
		return "transparent"

	return "#%s" % color.to_html(false).to_upper()
