extends Control
class_name RaidMemberFrame

signal hovered(unit)
signal unhovered(unit)

const CriticalDebuffCatalogScript := preload(
	"res://scripts/ui/critical_debuff_catalog.gd"
)
const ROLE_TEXTURES := {
	"tank": preload("res://icons/Warrior (Small).png"),
	"healer": preload("res://icons/Priest (Small).png"),
	"rogue": preload("res://icons/Rogue (Small).png"),
	"mage": preload("res://icons/Mage (Small).png"),
	"warrior": preload("res://icons/Warrior (Small).png"),
	"priest": preload("res://icons/Priest (Small).png")
}

const FRAME_MARGIN := 2.0
const HEADER_HEIGHT := 20.0
const COOLDOWN_STRIP_HEIGHT := 2.0
const CRITICAL_DEBUFF_ICON_SIZE := 22.0
const STACKING_DEBUFF_ICON_SIZE := 28.0
const CRITICAL_DEBUFF_ICON_GAP := 4.0
const CRITICAL_DEBUFF_BOTTOM_MARGIN := 11.0
const CRITICAL_DEBUFF_STACK_FONT_SIZE := 13
const MAX_CRITICAL_DEBUFF_ICONS := 5

const HEALTH_COLOR := Color(0.12, 0.52, 0.20, 1.0)
const MISSING_HEALTH_COLOR := Color(0.48, 0.08, 0.08, 1.0)
const INCOMING_HEAL_COLOR := Color(0.40, 0.95, 0.52, 0.48)
const ABSORB_COLOR := Color(0.32, 0.78, 0.94, 0.62)
const CURABLE_OVERLAY_COLOR := Color(0.52, 0.22, 0.72, 0.22)
const HARMFUL_OVERLAY_COLOR := Color(0.75, 0.08, 0.08, 0.18)
const ABSORB_OVERLAY_COLOR := Color(0.20, 0.60, 0.72, 0.07)
const DEAD_OVERLAY_COLOR := Color(0.05, 0.05, 0.06, 0.82)

@onready var role_icon: TextureRect = $RoleIcon
@onready var name_label: Label = $NameLabel
@onready var number_label: Label = $NumberLabel
@onready var cast_bar: ProgressBar = $CastBar
@onready var transient_status_label: Label = $TransientStatusLabel

var unit: Node = null
var display_name: String = ""
var is_boss_target: bool = false
var is_hovered: bool = false

var current_health: int = 0
var maximum_health: int = 1
var incoming_healing: int = 0
var absorb_amount: int = 0
var harmful_overlay_kind: String = ""
var critical_debuffs: Array[Dictionary] = []
var unit_is_dead: bool = false
var state_initialized: bool = false

var damage_flash_remaining: float = 0.0
var healing_flash_remaining: float = 0.0
var transient_status_remaining: float = 0.0
var visual_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	for child in get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	cast_bar.show_percentage = false
	cast_bar.visible = false
	cast_bar.value = 0.0

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


func _process(delta: float) -> void:
	visual_time += delta
	damage_flash_remaining = maxf(damage_flash_remaining - delta, 0.0)
	healing_flash_remaining = maxf(healing_flash_remaining - delta, 0.0)
	transient_status_remaining = maxf(transient_status_remaining - delta, 0.0)

	if transient_status_remaining <= 0.0:
		transient_status_label.visible = false

	sync_visual_state(true)
	update_cast_bar()
	queue_redraw()


func _draw() -> void:
	var inner_rect := Rect2(
		Vector2(FRAME_MARGIN, FRAME_MARGIN),
		Vector2(
			maxf(size.x - FRAME_MARGIN * 2.0, 1.0),
			maxf(size.y - FRAME_MARGIN * 2.0 - COOLDOWN_STRIP_HEIGHT, 1.0)
		)
	)
	var fill_width := inner_rect.size.x * get_health_ratio()

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.03, 0.035, 0.98))
	draw_rect(inner_rect, MISSING_HEALTH_COLOR)
	draw_rect(
		Rect2(inner_rect.position, Vector2(fill_width, inner_rect.size.y)),
		HEALTH_COLOR
	)

	draw_incoming_heal(inner_rect, fill_width)
	draw_absorb_layer(inner_rect, fill_width)
	draw_condition_overlay(inner_rect)
	draw_header_plates(inner_rect)
	draw_transient_flash(inner_rect)

	if unit_is_dead:
		draw_rect(inner_rect, DEAD_OVERLAY_COLOR)

	if is_hovered:
		draw_rect(inner_rect, Color(1.0, 1.0, 1.0, 0.09))

	draw_critical_debuff_icons()
	draw_rect(
		Rect2(Vector2(0.5, 0.5), size - Vector2.ONE),
		Color(0.02, 0.02, 0.025, 0.96),
		false,
		1.0
	)
	draw_threat_indicator()
	draw_dodge_cooldown_strip()


func draw_critical_debuff_icons() -> void:
	if critical_debuffs.is_empty() or unit_is_dead:
		return

	var icon_right := size.x - FRAME_MARGIN - 2.0
	var icon_bottom := size.y - COOLDOWN_STRIP_HEIGHT - CRITICAL_DEBUFF_BOTTOM_MARGIN
	var fallback_font := ThemeDB.fallback_font
	var visible_count := mini(critical_debuffs.size(), MAX_CRITICAL_DEBUFF_ICONS)

	for debuff_index in range(visible_count):
		var debuff: Dictionary = critical_debuffs[debuff_index]
		var show_stack_count := bool(debuff.get("show_stack_count", false))
		var emphasize_stacking := bool(debuff.get("emphasize_stacking", false))
		var icon_size := (
			STACKING_DEBUFF_ICON_SIZE
			if emphasize_stacking
			else CRITICAL_DEBUFF_ICON_SIZE
		)
		var icon_rect := Rect2(
			Vector2(icon_right - icon_size, icon_bottom - icon_size),
			Vector2.ONE * icon_size
		)
		var accent_color: Color = debuff.get(
			"accent_color",
			Color(0.95, 0.26, 0.18, 1.0)
		)

		draw_rect(icon_rect.grow(2.0), Color(0.02, 0.02, 0.025, 0.94))
		draw_rect(
			icon_rect.grow(1.0),
			accent_color if emphasize_stacking else accent_color.darkened(0.25),
			false,
			2.0 if emphasize_stacking else 1.0
		)

		var icon := debuff.get("icon") as Texture2D

		if icon != null:
			draw_texture_rect(icon, icon_rect, false)

		if show_stack_count:
			draw_debuff_stack_count(
				icon_rect,
				maxi(int(debuff.get("stacks", 1)), 1),
				fallback_font
			)

		icon_right = icon_rect.position.x - CRITICAL_DEBUFF_ICON_GAP


func draw_debuff_stack_count(icon_rect: Rect2, stacks: int, font: Font) -> void:
	var stack_text := str(stacks)
	var text_size := font.get_string_size(
		stack_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		CRITICAL_DEBUFF_STACK_FONT_SIZE
	)
	var badge_size := Vector2(maxf(text_size.x + 6.0, 15.0), 16.0)
	var badge_rect := Rect2(icon_rect.end - badge_size, badge_size)

	draw_rect(badge_rect, Color(0.025, 0.02, 0.02, 0.96))
	draw_rect(badge_rect, Color(1.0, 0.72, 0.30, 0.94), false, 1.0)
	draw_string(
		font,
		Vector2(
			badge_rect.position.x + (badge_size.x - text_size.x) * 0.5,
			badge_rect.end.y - 3.0
		),
		stack_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		CRITICAL_DEBUFF_STACK_FONT_SIZE,
		Color.WHITE
	)


func draw_incoming_heal(inner_rect: Rect2, fill_width: float) -> void:
	if incoming_healing <= 0 or maximum_health <= 0 or unit_is_dead:
		return

	var predicted_width := (
		inner_rect.size.x
		* minf(float(incoming_healing) / float(maximum_health), 1.0)
	)
	predicted_width = minf(predicted_width, inner_rect.size.x - fill_width)

	if predicted_width <= 0.0:
		return

	draw_rect(
		Rect2(
			inner_rect.position + Vector2(fill_width, 0.0),
			Vector2(predicted_width, inner_rect.size.y)
		),
		INCOMING_HEAL_COLOR
	)
	draw_line(
		inner_rect.position + Vector2(fill_width + predicted_width, 1.0),
		inner_rect.position + Vector2(
			fill_width + predicted_width,
			inner_rect.size.y - 1.0
		),
		Color(0.72, 1.0, 0.76, 0.72),
		1.0
	)


func draw_absorb_layer(inner_rect: Rect2, fill_width: float) -> void:
	if absorb_amount <= 0 or maximum_health <= 0 or unit_is_dead:
		return

	var absorb_width := (
		inner_rect.size.x
		* minf(float(absorb_amount) / float(maximum_health), 1.0)
	)
	var start_x := minf(
		fill_width,
		maxf(inner_rect.size.x - absorb_width, 0.0)
	)
	var layer_rect := Rect2(
		inner_rect.position + Vector2(start_x, inner_rect.size.y - 10.0),
		Vector2(absorb_width, 7.0)
	)

	draw_rect(layer_rect, ABSORB_COLOR)
	draw_line(
		layer_rect.position + Vector2(0.0, 1.0),
		layer_rect.position + Vector2(layer_rect.size.x, 1.0),
		Color(0.75, 0.96, 1.0, 0.82),
		1.0
	)


func draw_condition_overlay(inner_rect: Rect2) -> void:
	if harmful_overlay_kind == "curable":
		draw_rect(inner_rect, CURABLE_OVERLAY_COLOR)
	elif harmful_overlay_kind == "harmful":
		draw_rect(inner_rect, HARMFUL_OVERLAY_COLOR)
	elif absorb_amount > 0:
		draw_rect(inner_rect, ABSORB_OVERLAY_COLOR)


func draw_header_plates(inner_rect: Rect2) -> void:
	var plate_color := Color(0.025, 0.03, 0.04, 0.72)
	draw_rect(
		Rect2(
			Vector2(28.0, inner_rect.position.y),
			Vector2(maxf(size.x - 62.0, 1.0), HEADER_HEIGHT)
		),
		plate_color
	)
	draw_rect(
		Rect2(Vector2(2.0, 2.0), Vector2(24.0, HEADER_HEIGHT)),
		plate_color
	)
	draw_rect(
		Rect2(Vector2(size.x - 31.0, 2.0), Vector2(29.0, HEADER_HEIGHT)),
		plate_color
	)

	if transient_status_label.visible:
		draw_rect(
			Rect2(
				Vector2(27.0, 43.0),
				Vector2(maxf(size.x - 54.0, 1.0), 18.0)
			),
			Color(0.025, 0.03, 0.04, 0.78)
		)


func draw_transient_flash(inner_rect: Rect2) -> void:
	if damage_flash_remaining > 0.0:
		var strength := damage_flash_remaining / 0.18
		draw_rect(inner_rect, Color(1.0, 0.20, 0.12, 0.16 * strength))

	if healing_flash_remaining > 0.0:
		var strength := healing_flash_remaining / 0.22
		draw_rect(inner_rect, Color(0.55, 1.0, 0.62, 0.14 * strength))


func draw_threat_indicator() -> void:
	if not is_boss_target or unit_is_dead:
		return

	var pulse := 0.5 + 0.5 * sin(visual_time * 8.0)
	var color := Color(1.0, 0.10, 0.08, 0.66 + pulse * 0.28)
	var bracket_length := 10.0
	var inset := 1.5
	var maximum := size - Vector2(inset, inset)

	draw_rect(
		Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0)),
		Color(color.r, color.g, color.b, 0.12 + pulse * 0.10),
		false,
		2.0
	)

	draw_line(Vector2(inset, inset), Vector2(inset + bracket_length, inset), color, 3.0)
	draw_line(Vector2(inset, inset), Vector2(inset, inset + bracket_length), color, 3.0)
	draw_line(
		Vector2(maximum.x, inset),
		Vector2(maximum.x - bracket_length, inset),
		color,
		3.0
	)
	draw_line(
		Vector2(maximum.x, inset),
		Vector2(maximum.x, inset + bracket_length),
		color,
		3.0
	)
	draw_line(
		Vector2(inset, maximum.y),
		Vector2(inset + bracket_length, maximum.y),
		color,
		3.0
	)
	draw_line(
		Vector2(inset, maximum.y),
		Vector2(inset, maximum.y - bracket_length),
		color,
		3.0
	)
	draw_line(
		Vector2(maximum.x, maximum.y),
		Vector2(maximum.x - bracket_length, maximum.y),
		color,
		3.0
	)
	draw_line(
		Vector2(maximum.x, maximum.y),
		Vector2(maximum.x, maximum.y - bracket_length),
		color,
		3.0
	)


func draw_dodge_cooldown_strip() -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if not unit.has_method("get_dodge_charge_display"):
		return

	var segments: Array = unit.get_dodge_charge_display()

	if segments.is_empty():
		return

	var gap := 2.0 if segments.size() > 1 else 0.0
	var total_width := maxf(size.x - 4.0, 1.0)
	var segment_width := (
		(total_width - gap * float(segments.size() - 1))
		/ float(segments.size())
	)
	var bar_y := size.y - COOLDOWN_STRIP_HEIGHT
	var empty_color := Color(0.32, 0.28, 0.12, 0.28)
	var charging_color := Color(0.82, 0.66, 0.12, 0.78)
	var ready_color := Color(1.0, 0.84, 0.12, 1.0)

	for segment_index in range(segments.size()):
		var segment: Dictionary = segments[segment_index]
		var x := 2.0 + float(segment_index) * (segment_width + gap)
		var segment_rect := Rect2(
			Vector2(x, bar_y),
			Vector2(segment_width, COOLDOWN_STRIP_HEIGHT)
		)
		draw_rect(segment_rect, empty_color)

		var fill := clampf(float(segment.get("fill", 0.0)), 0.0, 1.0)

		if fill <= 0.0:
			continue

		var fill_color := (
			ready_color
			if bool(segment.get("ready", false))
			else charging_color
		)

		if bool(segment.get("flash", false)):
			fill_color = fill_color.lightened(
				float(segment.get("flash_strength", 0.0))
			)

		draw_rect(
			Rect2(
				segment_rect.position,
				Vector2(segment_width * fill, COOLDOWN_STRIP_HEIGHT)
			),
			fill_color
		)


func setup(new_unit: Node, new_display_name: String) -> void:
	unit = new_unit
	display_name = new_display_name
	name_label.text = display_name
	name_label.tooltip_text = display_name
	number_label.text = get_character_number()
	role_icon.texture = get_role_texture()
	role_icon.tooltip_text = get_role_label()
	sync_visual_state(false)
	update_cast_bar()
	queue_redraw()


func update_from_unit(_update_status: bool = true) -> void:
	sync_visual_state(true)
	update_cast_bar()
	queue_redraw()


func sync_visual_state(show_flash: bool) -> void:
	if unit == null or not is_instance_valid(unit):
		current_health = 0
		maximum_health = 1
		incoming_healing = 0
		absorb_amount = 0
		harmful_overlay_kind = ""
		critical_debuffs.clear()
		unit_is_dead = true
		name_label.text = display_name
		return

	var previous_health := current_health
	current_health = get_unit_current_health()
	maximum_health = maxi(get_unit_max_health(), 1)
	incoming_healing = get_unit_incoming_healing()
	absorb_amount = get_unit_absorb_amount()
	harmful_overlay_kind = get_unit_harmful_overlay_kind()
	critical_debuffs = get_unit_critical_debuffs()
	unit_is_dead = not get_unit_is_alive()

	if show_flash and state_initialized:
		if current_health < previous_health:
			damage_flash_remaining = 0.18
		elif current_health > previous_health:
			healing_flash_remaining = 0.22

	state_initialized = true
	name_label.modulate = Color(0.68, 0.68, 0.70, 1.0) if unit_is_dead else Color.WHITE
	number_label.modulate = name_label.modulate
	role_icon.modulate = name_label.modulate
	var tooltip_lines: Array[String] = [
		display_name,
		str(current_health) + " / " + str(maximum_health)
	]

	for debuff in critical_debuffs:
		var debuff_label := String(debuff.get(
			"display_name",
			debuff.get("effect_id", "Critical Debuff")
		))

		if bool(debuff.get("show_stack_count", false)):
			debuff_label += " x" + str(int(debuff.get("stacks", 1)))

		tooltip_lines.append(debuff_label)

	tooltip_text = "\n".join(tooltip_lines)


func update_cast_bar() -> void:
	cast_bar.max_value = 100.0

	if unit == null or not is_instance_valid(unit):
		cast_bar.visible = false
		cast_bar.value = 0.0
		return

	var casting := (
		unit.has_method("is_casting_ability")
		and bool(unit.is_casting_ability())
	)
	cast_bar.visible = casting

	if casting and unit.has_method("get_cast_progress_percent"):
		cast_bar.value = float(unit.get_cast_progress_percent())
	else:
		cast_bar.value = 0.0


func set_status_text(text: String) -> void:
	if text.is_empty():
		transient_status_label.visible = false
		transient_status_remaining = 0.0
		return

	transient_status_label.text = text
	transient_status_label.visible = true
	transient_status_remaining = 0.24
	queue_redraw()


func set_boss_target(active: bool) -> void:
	if is_boss_target == active:
		return

	is_boss_target = active
	queue_redraw()


func get_health_ratio() -> float:
	if maximum_health <= 0:
		return 0.0

	return clampf(float(current_health) / float(maximum_health), 0.0, 1.0)


func get_unit_current_health() -> int:
	if unit.has_method("get_current_health"):
		return int(unit.get_current_health())

	var value = unit.get("health")
	return 0 if value == null else int(value)


func get_unit_max_health() -> int:
	if unit.has_method("get_max_health"):
		return int(unit.get_max_health())

	var value = unit.get("max_health")
	return 1 if value == null else int(value)


func get_unit_incoming_healing() -> int:
	if unit.has_method("get_incoming_healing_total"):
		return maxi(int(unit.get_incoming_healing_total()), 0)

	return 0


func get_unit_absorb_amount() -> int:
	if unit.has_method("get_damage_absorb"):
		return maxi(int(unit.get_damage_absorb()), 0)

	return 0


func get_unit_harmful_overlay_kind() -> String:
	if unit.has_method("get_raid_frame_overlay_kind"):
		return String(unit.get_raid_frame_overlay_kind())

	return ""


func get_unit_critical_debuffs() -> Array[Dictionary]:
	if not unit.has_method("get_active_status_effects"):
		return []

	var active_status_effects: Array = unit.get_active_status_effects()
	return CriticalDebuffCatalogScript.get_critical_debuffs(active_status_effects)


func get_critical_debuff_display_state() -> Array[Dictionary]:
	return critical_debuffs.duplicate(true)


func get_unit_is_alive() -> bool:
	if unit.has_method("is_alive"):
		return bool(unit.is_alive())

	var dead_value = unit.get("is_dead")
	return dead_value == null or not bool(dead_value)


func get_character_number() -> String:
	if unit != null and is_instance_valid(unit):
		if unit.has_method("get_class_ordinal"):
			return str(unit.get_class_ordinal())

		var number_value = unit.get("unit_number")

		if number_value != null:
			return str(number_value)

	return "-"


func get_role_texture() -> Texture2D:
	var role_key := get_role_key()
	return ROLE_TEXTURES.get(role_key) as Texture2D


func get_role_label() -> String:
	var role_key := get_role_key()

	match role_key:
		"tank":
			return "Tank"
		"healer":
			return "Healer"
		_:
			return "Damage"


func get_role_key() -> String:
	if unit != null and is_instance_valid(unit) and unit.has_method("get_roles"):
		var roles: Array[String] = unit.get_roles()

		if roles.has("tank"):
			return "tank"

		if roles.has("healer"):
			return "healer"

	var class_value = (
		unit.get("unit_class")
		if unit != null and is_instance_valid(unit)
		else null
	)
	var class_key := "" if class_value == null else String(class_value).to_lower()

	if ROLE_TEXTURES.has(class_key):
		return class_key

	return "rogue"


func _on_mouse_entered() -> void:
	is_hovered = true
	queue_redraw()

	if unit != null and is_instance_valid(unit):
		hovered.emit(unit)


func _on_mouse_exited() -> void:
	is_hovered = false
	queue_redraw()

	if unit != null and is_instance_valid(unit):
		unhovered.emit(unit)
