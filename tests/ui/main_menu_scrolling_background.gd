extends SceneTree

const ScrollingMapBackgroundScript := preload(
	"res://scripts/ui/scrolling_map_background.gd"
)
const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")
const SCROLLING_MAP_SCRIPT_PATH := "res://scripts/ui/scrolling_map_background.gd"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var script_source := FileAccess.get_file_as_string(SCROLLING_MAP_SCRIPT_PATH)
	if script_source.contains("const MAP_TEXTURE: Texture2D = preload"):
		_fail("The newly added map PNG must not be compile-time preloaded.")
		return

	if ScrollingMapBackgroundScript.PAN_PATHS.size() != 10:
		_fail("The main-menu map must define exactly ten pan paths.")
		return

	if not is_equal_approx(
		ScrollingMapBackgroundScript.PAN_SPEED_PIXELS_PER_SECOND,
		70.0
	):
		_fail("The main-menu map speed must remain at the reduced 70 px/s value.")
		return

	if not is_equal_approx(
		ScrollingMapBackgroundScript.FADE_PHASE_DURATION_SECONDS * 2.0,
		ScrollingMapBackgroundScript.TRANSITION_DURATION_SECONDS
	):
		_fail("The fade-out and fade-in phases must share the transition duration.")
		return

	var half_visible_source: Vector2 = (
		ScrollingMapBackgroundScript.REFERENCE_VIEWPORT_SIZE
		/ ScrollingMapBackgroundScript.MAP_ZOOM
		* 0.5
	)
	var map_size: Vector2 = ScrollingMapBackgroundScript.MAP_SOURCE_SIZE

	for path_index in range(ScrollingMapBackgroundScript.PAN_PATHS.size()):
		var path: Dictionary = ScrollingMapBackgroundScript.PAN_PATHS[path_index]
		var start: Vector2 = path["start"]
		var end: Vector2 = path["end"]
		var duration := ScrollingMapBackgroundScript.get_path_duration_seconds(path_index)

		if duration <= ScrollingMapBackgroundScript.TRANSITION_DURATION_SECONDS * 2.0:
			_fail("Pan path %d is too short for uninterrupted fades." % path_index)
			return

		if not _camera_center_is_safe(start, half_visible_source, map_size):
			_fail("Pan path %d starts outside the safe image bounds." % path_index)
			return

		if not _camera_center_is_safe(end, half_visible_source, map_size):
			_fail("Pan path %d ends outside the safe image bounds." % path_index)
			return

		var measured_speed := (
			start.distance_to(end)
			* ScrollingMapBackgroundScript.MAP_ZOOM
			/ duration
		)

		if not is_equal_approx(
			measured_speed,
			ScrollingMapBackgroundScript.PAN_SPEED_PIXELS_PER_SECOND
		):
			_fail("Pan path %d does not move at the configured speed." % path_index)
			return

	# Reproduce the real runtime construction path. The background starts at 0x0
	# and must expand itself after it is parented to a viewport-sized Control.
	var background_host := Control.new()
	background_host.size = ScrollingMapBackgroundScript.REFERENCE_VIEWPORT_SIZE
	root.add_child(background_host)

	var animated_background := ScrollingMapBackgroundScript.new()
	animated_background.process_mode = Node.PROCESS_MODE_DISABLED
	background_host.add_child(animated_background)

	if not animated_background.size.is_equal_approx(
		ScrollingMapBackgroundScript.REFERENCE_VIEWPORT_SIZE
	):
		_fail("The scrolling map did not expand to fill the main-menu viewport.")
		return

	if animated_background.get_child_count() != 2:
		_fail("The scrolling map did not create both rendered texture layers.")
		return

	var initial_layer := animated_background.get_child(0) as TextureRect
	if initial_layer.texture == null or not initial_layer.visible:
		_fail("The initial scrolling-map texture is not visible.")
		return

	if (
		initial_layer.size.x < animated_background.size.x
		or initial_layer.size.y < animated_background.size.y
	):
		_fail("The initial scrolling-map texture does not cover the viewport.")
		return

	var first_fade_start := (
		ScrollingMapBackgroundScript.get_path_duration_seconds(0)
		- ScrollingMapBackgroundScript.FADE_PHASE_DURATION_SECONDS
	)
	animated_background._process(first_fade_start + 0.75)
	var outgoing_layer := animated_background.get_child(0) as TextureRect
	var incoming_layer := animated_background.get_child(1) as TextureRect

	if not outgoing_layer.visible or outgoing_layer.modulate.a >= 1.0:
		_fail("The outgoing map did not begin fading toward black.")
		return

	if incoming_layer.visible or incoming_layer.modulate.a > 0.0:
		_fail("The incoming map became visible before the outgoing map reached black.")
		return

	animated_background._process(0.75)

	if outgoing_layer.visible or outgoing_layer.modulate.a > 0.0:
		_fail("The outgoing map was still visible when the transition reached black.")
		return

	if not incoming_layer.visible or incoming_layer.modulate.a > 0.0:
		_fail("The incoming map did not begin from fully black.")
		return

	var incoming_position_before := incoming_layer.position
	animated_background._process(0.5)
	var incoming_distance := incoming_position_before.distance_to(incoming_layer.position)
	if incoming_layer.modulate.a <= 0.0:
		_fail("The incoming map did not immediately begin fading in from black.")
		return

	if not is_equal_approx(
		incoming_distance,
		ScrollingMapBackgroundScript.PAN_SPEED_PIXELS_PER_SECOND * 0.5
	):
		_fail("The incoming pan stopped moving during its fade-in.")
		return

	background_host.queue_free()

	var menu := MAIN_MENU_SCENE.instantiate()
	root.add_child(menu)
	var background_layer := menu.get_node_or_null("BackgroundLayer") as CanvasLayer
	var background_root := menu.get_node_or_null("BackgroundLayer/BackgroundRoot") as Control
	var background := menu.get_node_or_null(
		"BackgroundLayer/BackgroundRoot/ScrollingMapBackground"
	)

	if background_layer == null or background_layer.layer >= 0:
		_fail("The animated background is not isolated below the menu canvas.")
		return

	if background_root == null or background == null:
		_fail("The scrolling map was not placed in the isolated background layer.")
		return

	if background_root.size.is_zero_approx():
		_fail("The isolated background layer did not fill the viewport.")
		return

	var fallback := menu.get_node_or_null(
		"BackgroundLayer/BackgroundRoot/FallbackBackground"
	) as ColorRect
	var map_tint := menu.get_node_or_null(
		"BackgroundLayer/BackgroundRoot/MapTint"
	) as ColorRect
	if fallback == null or fallback.color != Color.BLACK:
		_fail("The midpoint behind the map layers is not fully black.")
		return

	if map_tint == null or map_tint.color.r > 0.0 or map_tint.color.g > 0.0 or map_tint.color.b > 0.0:
		_fail("The map tint prevents the transition midpoint from reaching black.")
		return

	if background.get_child_count() != 2:
		_fail("The scrolling map needs two layers for alternating routes.")
		return

	var menu_panel := menu.get_node_or_null("MenuCenter/MenuPanel") as PanelContainer
	if menu_panel == null or background_root.is_ancestor_of(menu_panel):
		_fail("The menu controls were not kept separate from the background tree.")
		return

	var menu_modulate_before := menu_panel.modulate
	background._process(
		ScrollingMapBackgroundScript.get_path_duration_seconds(0)
		- ScrollingMapBackgroundScript.FADE_PHASE_DURATION_SECONDS
		+ 0.75
	)
	if menu_panel.modulate != menu_modulate_before:
		_fail("A background fade changed the menu panel opacity.")
		return

	print("Main-menu scrolling background regression test passed.")
	quit(0)


func _camera_center_is_safe(
	camera_center: Vector2,
	half_visible_source: Vector2,
	map_size: Vector2
) -> bool:
	return (
		camera_center.x >= half_visible_source.x
		and camera_center.y >= half_visible_source.y
		and camera_center.x <= map_size.x - half_visible_source.x
		and camera_center.y <= map_size.y - half_visible_source.y
	)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
