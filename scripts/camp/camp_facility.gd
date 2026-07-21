extends Node2D
class_name CampFacility

const FACILITY_ATLAS := preload("res://assets/camp/camp_facilities_atlas.png")
const ATLAS_CELL_SIZE := Vector2i(362, 362)
const CELL_PADDING := 8
const MIN_ART_GUTTER := 8

static var _cell_texture_cache: Dictionary = {}

@export var facility_id: String = ""
@export var display_name: String = "Facility"
@export_multiline var responsibility: String = ""
@export var interactive: bool = false
@export var atlas_cell: Vector2i = Vector2i.ZERO
@export var sprite_scale: float = 1.0
@export var visual_offset: Vector2 = Vector2.ZERO
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
	sprite = Sprite2D.new()
	sprite.name = "FacilitySprite"
	sprite.texture = _get_padded_cell_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.position = visual_offset + Vector2(0.0, -22.0)
	add_child(sprite)


func _get_padded_cell_texture() -> Texture2D:
	var cache_key := "%d:%d" % [atlas_cell.x, atlas_cell.y]

	if _cell_texture_cache.has(cache_key):
		return _cell_texture_cache[cache_key] as Texture2D

	var atlas_image := FACILITY_ATLAS.get_image()

	if atlas_image == null or atlas_image.is_empty():
		return _make_fallback_atlas_texture()

	if atlas_image.is_compressed() and atlas_image.decompress() != OK:
		push_warning("Camp facility atlas could not be decompressed.")
		return _make_fallback_atlas_texture()

	var source_position := Vector2i(
		atlas_cell.x * ATLAS_CELL_SIZE.x, atlas_cell.y * ATLAS_CELL_SIZE.y
	)

	if (
		source_position.x < 0
		or source_position.y < 0
		or source_position.x + ATLAS_CELL_SIZE.x > atlas_image.get_width()
		or source_position.y + ATLAS_CELL_SIZE.y > atlas_image.get_height()
	):
		push_warning("Camp facility atlas cell is outside the source image: " + cache_key)
		return _make_fallback_atlas_texture()

	var cell_image := atlas_image.get_region(Rect2i(source_position, ATLAS_CELL_SIZE))
	_validate_cell_gutter(cell_image, cache_key)
	var padded_size := ATLAS_CELL_SIZE + Vector2i.ONE * CELL_PADDING * 2
	var padded := Image.create(padded_size.x, padded_size.y, false, cell_image.get_format())
	padded.fill(Color.TRANSPARENT)
	padded.blit_rect(
		cell_image,
		Rect2i(Vector2i.ZERO, ATLAS_CELL_SIZE),
		Vector2i.ONE * CELL_PADDING
	)
	var texture := ImageTexture.create_from_image(padded)
	_cell_texture_cache[cache_key] = texture
	return texture


func _validate_cell_gutter(cell_image: Image, cache_key: String) -> void:
	if not OS.is_debug_build():
		return

	var size := cell_image.get_size()
	for y in range(size.y):
		for x in range(size.x):
			if (
				x >= MIN_ART_GUTTER
				and x < size.x - MIN_ART_GUTTER
				and y >= MIN_ART_GUTTER
				and y < size.y - MIN_ART_GUTTER
			):
				continue
			if cell_image.get_pixel(x, y).a > 0.0:
				push_warning(
					"Camp facility art reaches the %dpx safety gutter in atlas cell %s."
					% [MIN_ART_GUTTER, cache_key]
				)
				return


func _make_fallback_atlas_texture() -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = FACILITY_ATLAS
	var source_position := Vector2i(
		atlas_cell.x * ATLAS_CELL_SIZE.x, atlas_cell.y * ATLAS_CELL_SIZE.y
	)
	atlas_texture.region = Rect2(Vector2(source_position), Vector2(ATLAS_CELL_SIZE))
	return atlas_texture


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
	# Trophy identity is conveyed by the sprite and camp reactions, never visible text.
	if facility_id == "victory_spike":
		return

	title_label = Label.new()
	title_label.name = "FacilityName"
	title_label.text = display_name
	var label_width := 240.0
	var label_y := footprint.y * 0.5 + 18.0
	title_label.position = Vector2(-label_width * 0.5, label_y)
	title_label.size = Vector2(label_width, 34)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color("d7d0bd"))
	title_label.add_theme_color_override("font_shadow_color", Color("101518"))
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(title_label)
