extends RefCounted
class_name CommandSchema

const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

const ACTION_ATTACK := "attack"
const ACTION_MOVE := "move"
const ACTION_DODGE := "dodge"
const ACTION_ROTATE := "rotate"
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
const DESTINATION_HEALING_SCOPE := "healing_scope"
const DESTINATION_CURABLE_ALLIES := "curable_allies"
const DESTINATION_PLAYER := "me"
const DESTINATION_MOVEMENT_SLOT := "movement_slot"
const DESTINATION_MOVEMENT_REGION := "movement_region"
const DESTINATION_MOVEMENT_ROTATE := "movement_rotate"
const DESTINATION_MOVEMENT_ROTATE_STEP := "movement_rotate_step"
const DESTINATION_MOVEMENT_RANGE := "movement_range"
const DESTINATION_MOVEMENT_RANGE_STEP := "movement_range_step"

const HEAL_SCOPE_ACTIVE_TANK := "active_tank"
const HEAL_SCOPE_RAID := "raid"

const HEAL_SCOPE_SELECTOR_TYPES: Array[String] = [
	SELECTOR_CLASS,
	SELECTOR_GROUP,
	SELECTOR_UNIT,
	SELECTOR_UNIT_IDENTITY
]

const ACTIONS: Array[String] = [
	ACTION_ATTACK,
	ACTION_MOVE,
	ACTION_DODGE,
	ACTION_ROTATE,
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
			if destination != DESTINATION_HEALING_SCOPE:
				return _failure("Heal requires an explicit healing target.")

			var healing_scope_result := _validate_healing_scope(command_data)

			if not bool(healing_scope_result.get("ok", false)):
				return healing_scope_result

		ACTION_CURE:
			if destination != DESTINATION_CURABLE_ALLIES:
				return _failure("Cure requires the curable-allies destination.")

		ACTION_MOVE, ACTION_DODGE:
			if not MOVEMENT_DESTINATIONS.has(destination):
				return _failure("Unsupported movement destination: " + destination)

		ACTION_ROTATE:
			if destination not in [
				DESTINATION_MOVEMENT_ROTATE,
				DESTINATION_MOVEMENT_ROTATE_STEP
			]:
				return _failure("Unsupported rotation destination: " + destination)

	var selector_result := _validate_selectors(command_data)

	if not bool(selector_result.get("ok", false)):
		return selector_result

	return _validate_movement_details(command_data)


static func _validate_healing_scope(command_data: Dictionary) -> Dictionary:
	var scope_value = command_data.get("healing_scope", null)

	if not scope_value is Dictionary:
		return _failure("Heal requires an explicit healing target.")

	var scope: Dictionary = scope_value
	var scope_type := String(scope.get("type", ""))

	if scope_type in [HEAL_SCOPE_ACTIVE_TANK, HEAL_SCOPE_RAID]:
		return _success()

	if not HEAL_SCOPE_SELECTOR_TYPES.has(scope_type):
		if scope_type == SELECTOR_EVERYONE:
			return _failure("Everyone is not a valid healing target.")

		return _failure("Unsupported healing target.")

	match scope_type:
		SELECTOR_CLASS:
			if String(scope.get("value", "")).is_empty():
				return _failure("Healing class target is empty.")

		SELECTOR_GROUP:
			if int(scope.get("value", 0)) <= 0:
				return _failure("Healing group target is invalid.")

		SELECTOR_UNIT:
			var unit_value = scope.get("unit", null)

			if not unit_value is Node or not is_instance_valid(unit_value):
				return _failure("Healing unit target is invalid.")

		SELECTOR_UNIT_IDENTITY:
			if (
				String(scope.get("class", "")).is_empty()
				or int(scope.get("number", 0)) <= 0
			):
				return _failure("Healing unit identity is invalid.")

	return _success()


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
	if String(command_data.get("what", "")) not in [ACTION_MOVE, ACTION_DODGE, ACTION_ROTATE]:
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
