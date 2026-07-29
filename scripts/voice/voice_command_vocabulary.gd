extends RefCounted
class_name VoiceCommandVocabulary

const CommandSchemaScript := preload("res://scripts/commands/command_schema.gd")
const MovementSlotResolverScript := preload("res://scripts/combat/movement_slot_resolver.gd")

const ACTION_ALIASES := {
	CommandSchemaScript.ACTION_INTERRUPT: ["interrupt", "kick"],
	CommandSchemaScript.ACTION_TAUNT: ["taunt", "provoke"],
	CommandSchemaScript.ACTION_ATTACK: ["attack", "damage", "burn", "focus", "engage"],
	CommandSchemaScript.ACTION_HEAL: ["heal", "healing"],
	CommandSchemaScript.ACTION_CURE: ["cure", "dispel", "cleanse"],
	CommandSchemaScript.ACTION_DODGE: ["dodge", "dodged", "dash", "blink"],
	CommandSchemaScript.ACTION_MOVE: [
		"move", "moved", "moves", "moving", "go", "come", "rotate", "turn", "spread", "stack"
	]
}

## "please" is intentionally ambiguous. It may be a distorted Priest target,
## so only the joint decoder may choose to treat it as filler.
const SAFE_FILLER_WORDS: Array[String] = [
	"a", "an", "can", "could", "hey", "kindly", "the", "you"
]
const AMBIGUOUS_FILLER_WORDS: Array[String] = ["please"]
const WHEN_ALIASES: Array[String] = ["now"]

const MOVEMENT_SEMANTIC_REGIONS := {
	"left": "west",
	"right": "east",
	"up": "north",
	"down": "south"
}


static func get_action_aliases(action: String) -> Array:
	return ACTION_ALIASES.get(action, [])


static func get_action_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	for action_value in ACTION_ALIASES.keys():
		var action := String(action_value)

		for alias_value in ACTION_ALIASES[action]:
			entries.append({
				"action": action,
				"alias": String(alias_value)
			})

	return entries


static func get_default_selector_for_action(action: String) -> Dictionary:
	match action:
		CommandSchemaScript.ACTION_MOVE, CommandSchemaScript.ACTION_DODGE:
			return {
				"selector": {"type": CommandSchemaScript.SELECTOR_EVERYONE, "value": ""},
				"reason": "movement_default_everyone"
			}
		CommandSchemaScript.ACTION_INTERRUPT:
			return {
				"selector": {"type": CommandSchemaScript.SELECTOR_EVERYONE, "value": ""},
				"reason": "interrupt_default_everyone"
			}
		CommandSchemaScript.ACTION_TAUNT:
			return {
				"selector": {"type": CommandSchemaScript.SELECTOR_ROLE, "value": "tank"},
				"reason": "taunt_default_tanks"
			}
		CommandSchemaScript.ACTION_CURE:
			return {
				"selector": {"type": CommandSchemaScript.SELECTOR_ROLE, "value": "healer"},
				"reason": "cure_default_healers"
			}
		_:
			return {}


static func get_action_destination(action: String) -> Dictionary:
	match action:
		CommandSchemaScript.ACTION_ATTACK, CommandSchemaScript.ACTION_INTERRUPT, CommandSchemaScript.ACTION_TAUNT:
			return {"where": CommandSchemaScript.DESTINATION_BOSS}
		CommandSchemaScript.ACTION_HEAL:
			return {"where": CommandSchemaScript.DESTINATION_BOSS_TARGET}
		CommandSchemaScript.ACTION_CURE:
			return {"where": CommandSchemaScript.DESTINATION_CURABLE_ALLIES}
		_:
			return {}


static func get_region_entries(include_semantic: bool = false) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	for region_value in MovementSlotResolverScript.REGION_ORDER:
		var region := String(region_value)
		entries.append({
			"alias": region,
			"region": region,
			"semantic": false
		})

	if include_semantic:
		for alias_value in MOVEMENT_SEMANTIC_REGIONS.keys():
			entries.append({
				"alias": String(alias_value),
				"region": String(MOVEMENT_SEMANTIC_REGIONS[alias_value]),
				"semantic": true
			})

	return entries


static func get_range_entries() -> Array[Dictionary]:
	return [
		{"alias": "close", "range": MovementSlotResolverScript.RANGE_CLOSE},
		{"alias": "mid", "range": MovementSlotResolverScript.RANGE_MID},
		{"alias": "middle", "range": MovementSlotResolverScript.RANGE_MID},
		{"alias": "midrange", "range": MovementSlotResolverScript.RANGE_MID},
		{"alias": "far", "range": MovementSlotResolverScript.RANGE_FAR}
	]


static func is_filler_token(token: String, include_ambiguous: bool = true) -> bool:
	if SAFE_FILLER_WORDS.has(token):
		return true

	return include_ambiguous and AMBIGUOUS_FILLER_WORDS.has(token)


static func tokens_are_fillers(tokens: Array, include_ambiguous: bool = true) -> bool:
	if tokens.is_empty():
		return false

	for token_value in tokens:
		if not is_filler_token(String(token_value), include_ambiguous):
			return false

	return true
