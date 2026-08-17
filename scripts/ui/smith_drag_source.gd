extends PanelContainer
class_name SmithDragSource

var drag_payload: Dictionary = {}
var drag_label: String = ""
var drag_texture: Texture2D = null
var drag_enabled: bool = false


func configure_drag(
	payload: Dictionary, preview_label: String, preview_texture: Texture2D,
	enabled: bool
) -> void:
	drag_payload = payload.duplicate(true)
	drag_label = preview_label
	drag_texture = preview_texture
	drag_enabled = enabled
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = (
		Control.CURSOR_DRAG if enabled else Control.CURSOR_FORBIDDEN
	)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not drag_enabled or drag_payload.is_empty():
		return null
	set_drag_preview(build_drag_preview())
	return drag_payload.duplicate(true)


func build_drag_preview() -> Control:
	var preview := HBoxContainer.new()
	preview.z_as_relative = false
	preview.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_theme_constant_override("separation", 8)
	if drag_texture != null:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(44, 44)
		icon.texture = drag_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(icon)
	var label := Label.new()
	label.text = drag_label
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("f0e5c8"))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color("11171c"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(label)
	return preview
