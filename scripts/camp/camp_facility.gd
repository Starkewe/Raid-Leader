extends Node2D
class_name CampFacility

const FACILITY_ATLAS := preload("res://assets/camp/camp_facilities_atlas.png")
const ATLAS_CELL_SIZE := Vector2i(362, 362)
const ATLAS_INSET := 2

@export var facility_id: String = ""
@export var display_name: String = "Facility"
@export_multiline var responsibility: String = ""
@export var interactive: bool = false
@export var atlas_cell: Vector2i = Vector2i.ZERO
@export var sprite_scale: float = 1.0
@export var footprint: Vector2 = Vector2(220, 150)
@export var collision_offset: Vector2 = Vector2(0, -20)
@export var interaction_radius: float = 170.0
@export var activity_slot_offsets: Array[Vector2] = []

var reservations: Dictionary = {}
var sprite: Sprite2D = null
var title_label: Label = null


func _ready() -> void:
	add_to_group("camp_facility")
	z_index = clampi(int(global_position.y / 3.0), 0, 1000)
	_create_sprite()
	_create_collision()
	_create_title_label()


func get_interaction_text() -> String:
	return "E  %s" % display_name


func get_free_slot_count() -> int:
	return maxi(activity_slot_offsets.size() - reservations.size(), 0)


func reserve_activity_slot(member_id: String) -> Dictionary:
	if reservations.has(member_id):
		var existing_index := int(reservations[member_id])
		return {
			"ok": true,
			"slot_index": existing_index,
			"position": global_position + activity_slot_offsets[existing_index]
		}

	for slot_index in range(activity_slot_offsets.size()):
		if not reservations.values().has(slot_index):
			reservations[member_id] = slot_index
			return {
				"ok": true,
				"slot_index": slot_index,
				"position": global_position + activity_slot_offsets[slot_index]
			}

	return {"ok": false}


func release_activity_slot(member_id: String) -> void:
	reservations.erase(member_id)


func release_all_slots() -> void:
	reservations.clear()


func _create_sprite() -> void:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = FACILITY_ATLAS
	atlas_texture.region = Rect2(
		atlas_cell.x * ATLAS_CELL_SIZE.x + ATLAS_INSET,
		atlas_cell.y * ATLAS_CELL_SIZE.y + ATLAS_INSET,
		ATLAS_CELL_SIZE.x - ATLAS_INSET * 2,
		ATLAS_CELL_SIZE.y - ATLAS_INSET * 2
	)

	sprite = Sprite2D.new()
	sprite.name = "FacilitySprite"
	sprite.texture = atlas_texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.position.y = -22.0
	add_child(sprite)


func _create_collision() -> void:
	if footprint.x <= 0.0 or footprint.y <= 0.0:
		return

	var body := StaticBody2D.new()
	body.name = "FootprintCollision"
	body.position = collision_offset
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)

	var shape := RectangleShape2D.new()
	shape.size = footprint
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)


func _create_title_label() -> void:
	title_label = Label.new()
	title_label.name = "FacilityName"
	title_label.text = display_name
	var label_width := 300.0 if facility_id == "victory_spike" else 240.0
	var label_y := footprint.y * 0.5 + (48.0 if facility_id == "victory_spike" else 18.0)
	title_label.position = Vector2(-label_width * 0.5, label_y)
	title_label.size = Vector2(label_width, 34)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override(
		"font_size", 15 if facility_id == "victory_spike" else 18
	)
	title_label.add_theme_color_override("font_color", Color("d7d0bd"))
	title_label.add_theme_color_override("font_shadow_color", Color("101518"))
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(title_label)
