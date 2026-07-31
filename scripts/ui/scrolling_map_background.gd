extends Control

const MAP_TEXTURE_PATH := "res://assets/ui/main_menu_beast_crucible_map.png"
const MAP_SOURCE_SIZE := Vector2(2048.0, 1152.0)
const REFERENCE_VIEWPORT_SIZE := Vector2(1920.0, 1080.0)
const MAP_ZOOM: float = 2.0
const PAN_SPEED_PIXELS_PER_SECOND: float = 70.0
const TRANSITION_DURATION_SECONDS: float = 3.0
const FADE_PHASE_DURATION_SECONDS: float = TRANSITION_DURATION_SECONDS * 0.5

enum FadePhase {
	NONE,
	OUT,
	IN,
}

# Camera centers are authored in source-image pixels. At the fixed 2x zoom, each
# route stays safely inside the map while showcasing a different landmark pair.
const PAN_PATHS: Array[Dictionary] = [
	{
		"name": "Northern coast to central war camp",
		"start": Vector2(500.0, 285.0),
		"end": Vector2(1070.0, 580.0),
	},
	{
		"name": "Northern citadel to eastern skull furnace",
		"start": Vector2(1050.0, 285.0),
		"end": Vector2(1550.0, 500.0),
	},
	{
		"name": "Eastern mountains to southern stronghold",
		"start": Vector2(1545.0, 285.0),
		"end": Vector2(1430.0, 835.0),
	},
	{
		"name": "Southern stronghold to skull gate",
		"start": Vector2(1545.0, 830.0),
		"end": Vector2(990.0, 825.0),
	},
	{
		"name": "Southwestern outpost to beast graveyard",
		"start": Vector2(500.0, 830.0),
		"end": Vector2(1060.0, 825.0),
	},
	{
		"name": "Western peaks to central war camp",
		"start": Vector2(500.0, 690.0),
		"end": Vector2(1070.0, 560.0),
	},
	{
		"name": "Standing stones across the northern plains",
		"start": Vector2(500.0, 390.0),
		"end": Vector2(1120.0, 300.0),
	},
	{
		"name": "Southern rift road to eastern river crossing",
		"start": Vector2(820.0, 825.0),
		"end": Vector2(1460.0, 480.0),
	},
	{
		"name": "Eastern fortress to central war camp",
		"start": Vector2(1545.0, 780.0),
		"end": Vector2(1010.0, 540.0),
	},
	{
		"name": "Skull gate to northern citadel",
		"start": Vector2(1060.0, 835.0),
		"end": Vector2(1200.0, 285.0),
	},
]

var _layers: Array[TextureRect] = []
var _path_indices: Array[int] = [-1, -1]
var _path_elapsed_seconds: Array[float] = [0.0, 0.0]
var _path_durations_seconds: Array[float] = [0.0, 0.0]
var _active_layers: Array[bool] = [false, false]
var _current_layer_index: int = 0
var _next_path_index: int = 0
var _fade_phase: FadePhase = FadePhase.NONE
var _fade_elapsed_seconds: float = 0.0
var _map_texture: Texture2D = null


func _ready() -> void:
	# This node is created at runtime with an initial size of zero. Setting only
	# its anchors after it enters the tree preserves that zero-sized rectangle by
	# adding compensating offsets, which clips every map layer. Reset both the
	# anchors and offsets so this control actually fills the main-menu viewport.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_map_texture = _load_map_texture()

	if _map_texture == null:
		push_error("Main-menu scrolling map could not be loaded: %s" % MAP_TEXTURE_PATH)
		set_process(false)
		return

	for _layer_index in range(2):
		var map_layer := TextureRect.new()
		map_layer.texture = _map_texture
		map_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		map_layer.stretch_mode = TextureRect.STRETCH_SCALE
		map_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		map_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_layer.modulate = Color(1.0, 1.0, 1.0, 0.0)
		map_layer.visible = false
		add_child(map_layer)
		_layers.append(map_layer)

	_start_path(0, 0)
	_layers[0].modulate.a = 1.0
	_current_layer_index = 0
	_next_path_index = 1
	resized.connect(_on_background_resized)


func _process(delta: float) -> void:
	var remaining_delta := delta

	while remaining_delta > 0.0:
		if _fade_phase != FadePhase.NONE:
			var fade_time_remaining := (
				FADE_PHASE_DURATION_SECONDS - _fade_elapsed_seconds
			)
			var fade_step := minf(remaining_delta, fade_time_remaining)
			_advance_active_paths(fade_step)
			_update_fade(fade_step)
			remaining_delta -= fade_step
			continue

		var fade_start_time := (
			_path_durations_seconds[_current_layer_index]
			- FADE_PHASE_DURATION_SECONDS
		)
		var time_until_fade := maxf(
			fade_start_time - _path_elapsed_seconds[_current_layer_index],
			0.0
		)

		if remaining_delta < time_until_fade:
			_advance_active_paths(remaining_delta)
			remaining_delta = 0.0
			continue

		_advance_active_paths(time_until_fade)
		remaining_delta -= time_until_fade
		_begin_fade_out()


func _advance_active_paths(delta: float) -> void:
	for layer_index in range(_layers.size()):
		if not _active_layers[layer_index]:
			continue

		_path_elapsed_seconds[layer_index] = minf(
			_path_elapsed_seconds[layer_index] + delta,
			_path_durations_seconds[layer_index]
		)
		_update_layer_position(layer_index)


func _begin_fade_out() -> void:
	# Do not start or reveal the next route until the current one has completely
	# faded to black. This prevents both map shots from ever being visible at once.
	_fade_elapsed_seconds = 0.0
	_fade_phase = FadePhase.OUT


func _update_fade(delta: float) -> void:
	_fade_elapsed_seconds += delta
	var fade_progress := clampf(
		_fade_elapsed_seconds / FADE_PHASE_DURATION_SECONDS,
		0.0,
		1.0
	)
	var eased_progress := fade_progress * fade_progress * (3.0 - 2.0 * fade_progress)

	if _fade_phase == FadePhase.OUT:
		_layers[_current_layer_index].modulate.a = 1.0 - eased_progress
	else:
		_layers[_current_layer_index].modulate.a = eased_progress

	if fade_progress < 1.0:
		return

	if _fade_phase == FadePhase.OUT:
		_switch_to_next_path_at_black()
		return

	_layers[_current_layer_index].modulate.a = 1.0
	_fade_phase = FadePhase.NONE
	_fade_elapsed_seconds = 0.0


func _switch_to_next_path_at_black() -> void:
	_active_layers[_current_layer_index] = false
	_layers[_current_layer_index].visible = false
	_layers[_current_layer_index].modulate.a = 0.0

	var incoming_layer_index := 1 - _current_layer_index
	_start_path(incoming_layer_index, _next_path_index)
	_next_path_index = (_next_path_index + 1) % PAN_PATHS.size()
	_current_layer_index = incoming_layer_index
	_fade_phase = FadePhase.IN
	_fade_elapsed_seconds = 0.0


func _start_path(layer_index: int, path_index: int) -> void:
	_path_indices[layer_index] = path_index
	_path_elapsed_seconds[layer_index] = 0.0
	_path_durations_seconds[layer_index] = get_path_duration_seconds(path_index)
	_active_layers[layer_index] = true
	_layers[layer_index].visible = true
	_layers[layer_index].modulate.a = 0.0
	_update_layer_position(layer_index)


func _update_layer_position(layer_index: int) -> void:
	var path_index := _path_indices[layer_index]
	var path: Dictionary = PAN_PATHS[path_index]
	var path_progress := clampf(
		_path_elapsed_seconds[layer_index] / _path_durations_seconds[layer_index],
		0.0,
		1.0
	)
	var start: Vector2 = path["start"]
	var end: Vector2 = path["end"]
	var camera_center := start.lerp(end, path_progress)
	var viewport_size := size

	if viewport_size.is_zero_approx():
		viewport_size = REFERENCE_VIEWPORT_SIZE

	var scaled_map_size := _map_texture.get_size() * MAP_ZOOM
	var target_position := viewport_size * 0.5 - camera_center * MAP_ZOOM
	target_position.x = _clamp_axis_to_viewport(
		target_position.x,
		viewport_size.x,
		scaled_map_size.x
	)
	target_position.y = _clamp_axis_to_viewport(
		target_position.y,
		viewport_size.y,
		scaled_map_size.y
	)

	_layers[layer_index].size = scaled_map_size
	_layers[layer_index].position = target_position


func _on_background_resized() -> void:
	for layer_index in range(_layers.size()):
		if _active_layers[layer_index]:
			_update_layer_position(layer_index)


func _load_map_texture() -> Texture2D:
	# A patch can add the script and image during the same editor session. Avoid a
	# compile-time preload so the menu remains parseable until Godot imports the PNG.
	if ResourceLoader.exists(MAP_TEXTURE_PATH, "Texture2D"):
		var imported_texture := ResourceLoader.load(MAP_TEXTURE_PATH) as Texture2D
		if imported_texture != null:
			return imported_texture

	# The editor may not have generated its import cache yet. Loading the source
	# image directly keeps the first run functional; exported builds use the
	# imported Texture2D path above.
	var source_image := Image.load_from_file(MAP_TEXTURE_PATH)
	if source_image == null or source_image.is_empty():
		return null

	return ImageTexture.create_from_image(source_image)


func _clamp_axis_to_viewport(
	desired_position: float,
	viewport_length: float,
	map_length: float
) -> float:
	if map_length < viewport_length:
		return (viewport_length - map_length) * 0.5

	return clampf(desired_position, viewport_length - map_length, 0.0)


static func get_path_duration_seconds(path_index: int) -> float:
	var path: Dictionary = PAN_PATHS[path_index]
	var start: Vector2 = path["start"]
	var end: Vector2 = path["end"]
	return start.distance_to(end) * MAP_ZOOM / PAN_SPEED_PIXELS_PER_SECOND
