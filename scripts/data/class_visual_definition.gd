extends RefCounted
class_name ClassVisualDefinition


var class_id: String
var display_name: String
var primary_class: String
var secondary_class: String
var main_color: Color
var accent_color: Color
var icon_resource: Texture2D
var compact_icon_resource: Texture2D


func _init(
	new_class_id: String,
	new_display_name: String,
	new_primary_class: String,
	new_secondary_class: String,
	new_main_color: Color,
	new_accent_color: Color,
	new_icon_resource: Texture2D,
	new_compact_icon_resource: Texture2D
) -> void:
	class_id = new_class_id
	display_name = new_display_name
	primary_class = new_primary_class
	secondary_class = new_secondary_class
	main_color = new_main_color
	accent_color = new_accent_color
	icon_resource = new_icon_resource
	compact_icon_resource = new_compact_icon_resource


func has_complete_icon_set() -> bool:
	return icon_resource != null and compact_icon_resource != null


func to_dictionary() -> Dictionary:
	return {
		"class_id": class_id,
		"display_name": display_name,
		"primary_class": primary_class,
		"secondary_class": secondary_class,
		"main_color": main_color,
		"accent_color": accent_color,
		"icon_resource": icon_resource,
		"compact_icon_resource": compact_icon_resource
	}
