extends RefCounted
class_name CommandSchema

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

const ACTION_ATTACK := "attack"
const ACTION_MOVE := "move"
const ACTION_INTERRUPT := "interrupt"
const ACTION_HEAL := "heal"
const ACTION_TAUNT := "taunt"
const ACTION_CURE := "cure"

const SELECTOR_EVERYONE := "everyone"
const SELECTOR_CLASS := "class"
const SELECTOR_GROUP := "group"
const SELECTOR_UNIT := "unit"
const SELECTOR_UNIT_IDENTITY := "unit_identity"
const SELECTOR_ROLE := "role"

const DESTINATION_BOSS := "boss"
const DESTINATION_BOSS_TARGET := "boss_target"
const DESTINATION_CURABLE_ALLIES := "curable_allies"
const DESTINATION_PLAYER := "me"
const DESTINATION_MOVEMENT_SLOT := "movement_slot"
const DESTINATION_MOVEMENT_REGION := "movement_region"
const DESTINATION_MOVEMENT_ROTATE := "movement_rotate"
const DESTINATION_MOVEMENT_ROTATE_STEP := "movement_rotate_step"
const DESTINATION_MOVEMENT_RANGE := "movement_range"
const DESTINATION_MOVEMENT_RANGE_STEP := "movement_range_step"

const ACTIONS: Array[String] = [
	ACTION_ATTACK,
	ACTION_MOVE,
	ACTION_INTERRUPT,
	ACTION_HEAL,
	ACTION_TAUNT,
	ACTION_CURE
]

const SELECTOR_TYPES: Array[String] = [
	SELECTOR_EVERYONE,
	SELECTOR_CLASS,
	SELECTOR_GROUP,
	SELECTOR_UNIT,
	SELECTOR_UNIT_IDENTITY,
	SELECTOR_ROLE
]

const MOVEMENT_DESTINATIONS: Array[String] = [
	DESTINATION_PLAYER,
	DESTINATION_MOVEMENT_SLOT,
	DESTINATION_MOVEMENT_REGION,
	DESTINATION_MOVEMENT_ROTATE,
	DESTINATION_MOVEMENT_ROTATE_STEP,
	DESTINATION_MOVEMENT_RANGE,
	DESTINATION_MOVEMENT_RANGE_STEP
]


static func validate(command_data: Dictionary) -> Dictionary:
	var required_keys: Array[String] = ["who_type", "who_value", "unit", "what", "where", "when"]

	for key in required_keys:
		if not command_data.has(key):
			return _failure("Missing required key: " + key)

	var action := String(command_data.get("what", "")).strip_edges()
	var destination := String(command_data.get("where", "")).strip_edges()

	if not ACTIONS.has(action):
		return _failure("Unsupported command action: " + action)

	if destination.is_empty():
		return _failure("Command destination is empty.")

	match action:
		ACTION_ATTACK, ACTION_INTERRUPT, ACTION_TAUNT:
			if destination != DESTINATION_BOSS:
				return _failure(action.capitalize() + " requires the boss destination.")

		ACTION_HEAL:
			if destination != DESTINATION_BOSS_TARGET:
				return _failure("Heal requires the boss-target destination.")

		ACTION_CURE:
			if destination != DESTINATION_CURABLE_ALLIES:
				return _failure("Cure requires the curable-allies destination.")

		ACTION_MOVE:
			if not MOVEMENT_DESTINATIONS.has(destination):
				return _failure("Unsupported movement destination: " + destination)

	var selector_result := _validate_selectors(command_data)

	if not bool(selector_result.get("ok", false)):
		return selector_result

	return _validate_movement_details(command_data)


static func _validate_selectors(command_data: Dictionary) -> Dictionary:
	var selectors: Array = command_data.get("who_selectors", [])

	if selectors.is_empty():
		selectors = [{"type": String(command_data.get("who_type", SELECTOR_EVERYONE))}]

	for selector_value in selectors:
		if not selector_value is Dictionary:
			return _failure("Command selector must be a dictionary.")

		var selector: Dictionary = selector_value
		var selector_type := String(selector.get("type", ""))

		if not SELECTOR_TYPES.has(selector_type):
			return _failure("Unsupported selector type: " + selector_type)

	return _success()


static func _validate_movement_details(command_data: Dictionary) -> Dictionary:
	if String(command_data.get("what", "")) != ACTION_MOVE:
		return _success()

	var destination := String(command_data.get("where", ""))
	var region := String(command_data.get("movement_region", ""))
	var range_name := String(command_data.get("movement_range", ""))
	var direction := String(command_data.get("movement_direction", ""))

	if destination in [DESTINATION_MOVEMENT_SLOT, DESTINATION_MOVEMENT_REGION, DESTINATION_MOVEMENT_ROTATE]:
		if not MovementSlotResolverScript.REGION_ORDER.has(region):
			return _failure("Unknown movement region: " + region)

	if destination in [DESTINATION_MOVEMENT_SLOT, DESTINATION_MOVEMENT_RANGE]:
		if not MovementSlotResolverScript.RANGE_ORDER.has(range_name):
			return _failure("Unknown movement range: " + range_name)

	if destination == DESTINATION_MOVEMENT_ROTATE_STEP:
		if direction not in [
			MovementSlotResolverScript.ROTATION_COUNTERCLOCKWISE,
			MovementSlotResolverScript.ROTATION_CLOCKWISE
		]:
			return _failure("Unknown rotation direction: " + direction)

	if destination == DESTINATION_MOVEMENT_RANGE_STEP:
		if direction not in [
			MovementSlotResolverScript.RANGE_DIRECTION_IN,
			MovementSlotResolverScript.RANGE_DIRECTION_OUT
		]:
			return _failure("Unknown range direction: " + direction)

	return _success()


static func _success() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
