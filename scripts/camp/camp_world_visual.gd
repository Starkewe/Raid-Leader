extends Node2D
class_name CampWorldVisual

const WORLD_RECT := Rect2(0, 0, 3000, 2100)
const TERRAIN_ATLAS := preload("res://assets/camp/camp_terrain_atlas.png")
const TERRAIN_SOURCE_CELL := 362
const TERRAIN_DRAW_CELL := 358

var formation_preview: Dictionary = {}


func _ready() -> void:
	z_index = -1000
	CampaignState.raid_plan_changed.connect(_refresh_formation)
	_refresh_formation()


func _refresh_formation() -> void:
	formation_preview = CampaignState.get_formation()
	queue_redraw()


func _draw() -> void:
	draw_rect(WORLD_RECT, Color("141d1c"))
	_draw_ground_tiles()
	_draw_paths()
	_draw_perimeter()
	_draw_crossroads()

	if CampaignState.get_latest_victory().is_empty():
		_draw_empty_victory_spike()

	_draw_formation_markers()


func _draw_ground_tiles() -> void:
	var columns := ceili(WORLD_RECT.size.x / float(TERRAIN_DRAW_CELL))
	var rows := ceili(WORLD_RECT.size.y / float(TERRAIN_DRAW_CELL))

	for tile_y in range(rows):
		for tile_x in range(columns):
			var atlas_cell := _terrain_cell_for(tile_x, tile_y, columns, rows)
			var destination := Rect2(
				tile_x * TERRAIN_DRAW_CELL,
				tile_y * TERRAIN_DRAW_CELL,
				TERRAIN_DRAW_CELL,
				TERRAIN_DRAW_CELL
			)
			var source := Rect2(
				atlas_cell.x * TERRAIN_SOURCE_CELL + 2,
				atlas_cell.y * TERRAIN_SOURCE_CELL + 2,
				TERRAIN_DRAW_CELL,
				TERRAIN_DRAW_CELL
			)
			draw_texture_rect_region(TERRAIN_ATLAS, destination, source)


func _terrain_cell_for(tile_x: int, tile_y: int, columns: int, rows: int) -> Vector2i:
	var perimeter := tile_x == 0 or tile_y == 0 or tile_x == columns - 1 or tile_y == rows - 1

	if perimeter:
		return [Vector2i(3, 0), Vector2i(0, 2), Vector2i(2, 2)][abs(tile_x * 3 + tile_y * 5) % 3]

	return [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(3, 2)][
		abs(tile_x * 7 + tile_y * 11) % 5
	]


func _draw_paths() -> void:
	var edge := Color("3a352dd9")
	var mud := Color("55483ac9")
	var packed := Color("655442b8")
	var spine := PackedVector2Array(
		[
			Vector2(1350, 2100),
			Vector2(1650, 2100),
			Vector2(1630, 1360),
			Vector2(1700, 1030),
			Vector2(1680, 300),
			Vector2(1320, 300),
			Vector2(1320, 1030),
			Vector2(1370, 1360)
		]
	)
	draw_colored_polygon(spine, edge)
	draw_rect(Rect2(1400, 250, 200, 1800), mud)
	draw_rect(Rect2(1445, 250, 110, 1800), packed)
	draw_rect(Rect2(430, 1000, 2140, 250), edge)
	draw_rect(Rect2(470, 1040, 2060, 170), mud)
	draw_rect(Rect2(470, 1085, 2060, 80), packed)
	draw_rect(Rect2(760, 720, 170, 480), mud)
	draw_rect(Rect2(2050, 680, 160, 470), mud)
	draw_rect(Rect2(610, 1160, 120, 520), mud)


func _draw_perimeter() -> void:
	var wood := Color("29241f")
	var point := Color("514536")

	for x in range(80, 2960, 56):
		_draw_stake(Vector2(x, 90), wood, point)
		_draw_stake(Vector2(x, 2010), wood, point)

	for y in range(130, 1980, 56):
		_draw_stake(Vector2(70, y), wood, point)
		_draw_stake(Vector2(2930, y), wood, point)

	draw_rect(Rect2(1330, 1975, 340, 130), Color("141d1c"))


func _draw_stake(position_value: Vector2, wood: Color, point: Color) -> void:
	draw_rect(Rect2(position_value.x - 4, position_value.y, 8, 26), wood)
	draw_colored_polygon(
		PackedVector2Array(
			[
				position_value + Vector2(-5, 0),
				position_value + Vector2(0, -10),
				position_value + Vector2(5, 0)
			]
		),
		point
	)


func _draw_crossroads() -> void:
	draw_circle(Vector2(1500, 1125), 265, Color("69442830"))
	draw_circle(Vector2(1500, 1125), 205, Color("9b5d2b26"))
	draw_circle(Vector2(1500, 1125), 172, Color("443b31"))
	draw_circle(Vector2(1500, 1125), 120, Color("5b4b3a"))

	for angle_index in range(12):
		var angle := TAU * float(angle_index) / 12.0
		var rock_position := Vector2(1500, 1125) + Vector2.from_angle(angle) * 142.0
		draw_rect(Rect2(rock_position - Vector2(7, 5), Vector2(14, 10)), Color("6a6658"))


func _draw_empty_victory_spike() -> void:
	var victory_spike := get_node_or_null("../VictorySpike") as Node2D

	if victory_spike == null:
		return

	var center := to_local(victory_spike.global_position)
	draw_rect(Rect2(center.x - 7, center.y - 95, 14, 115), Color("382b22"))
	draw_rect(Rect2(center.x - 56, center.y - 72, 112, 12), Color("47362a"))
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(center.x - 10, center.y - 95),
				Vector2(center.x, center.y - 116),
				Vector2(center.x + 10, center.y - 95),
			]
		),
		Color("67503b")
	)
	draw_rect(Rect2(center.x - 32, center.y + 16, 64, 12), Color("241d18"))


func _draw_formation_markers() -> void:
	var placements: Dictionary = formation_preview.get("placements", {})
	var active_ids := CampaignState.get_active_member_ids()
	var center := Vector2(870, 860)

	for index in range(active_ids.size()):
		var member_id := active_ids[index]
		var placement: Dictionary = placements.get(member_id, {})
		var region := String(placement.get("region", "south"))
		var range_name := String(placement.get("range", "mid"))
		var direction := _region_direction(region)
		var radius: float = float({"close": 42.0, "mid": 82.0, "far": 122.0}.get(range_name, 82.0))
		var tangent := Vector2(-direction.y, direction.x)
		var jitter := float((index % 3) - 1) * 12.0
		var marker_position := center + direction * radius + tangent * jitter
		draw_circle(marker_position, 6.0, Color("b29a5e"))
		draw_arc(marker_position, 8.0, 0.0, TAU, 12, Color("2a231b"), 2.0)


func _region_direction(region: String) -> Vector2:
	var directions := {
		"north": Vector2.UP,
		"northeast": Vector2(1, -1).normalized(),
		"east": Vector2.RIGHT,
		"southeast": Vector2(1, 1).normalized(),
		"south": Vector2.DOWN,
		"southwest": Vector2(-1, 1).normalized(),
		"west": Vector2.LEFT,
		"northwest": Vector2(-1, -1).normalized()
	}
	return directions.get(region, Vector2.DOWN)
