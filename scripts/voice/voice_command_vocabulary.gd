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
	CommandSchemaScript.ACTION_ROTATE: ["rotate", "turn"],
	CommandSchemaScript.ACTION_MOVE: [
		"move", "moved", "moves", "moving", "go", "come", "spread", "stack"
	]
}

## "please" is intentionally ambiguous. It may be a distorted Priest target,
## so only the joint decoder may choose to treat it as filler.
const SAFE_FILLER_WORDS: Array[String] = [
	"a", "an", "can", "could", "hey", "kindly", "the", "you"
]
const AMBIGUOUS_FILLER_WORDS: Array[String] = ["please"]
const WHEN_ALIASES: Array[String] = ["now"]

const NUMBER_WORDS := {
	"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
	"six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
	"eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
	"fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
	"nineteen": 19, "twenty": 20
}
const TARGET_NUMBER_HOMOPHONES := {
	"to": 2,
	"too": 2
}
const ROMAN_NUMERALS := {
	"i": 1, "ii": 2, "iii": 3, "iv": 4, "v": 5,
	"vi": 6, "vii": 7, "viii": 8, "ix": 9, "x": 10,
	"xi": 11, "xii": 12, "xiii": 13, "xiv": 14, "xv": 15,
	"xvi": 16, "xvii": 17, "xviii": 18, "xix": 19, "xx": 20
}

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
		CommandSchemaScript.ACTION_MOVE, CommandSchemaScript.ACTION_DODGE, CommandSchemaScript.ACTION_ROTATE:
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
			return {"where": CommandSchemaScript.DESTINATION_HEALING_SCOPE}
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


static func get_target_number_aliases(value: int) -> Array[String]:
	var aliases: Array[String] = [str(value)]

	for word_value in NUMBER_WORDS.keys():
		if int(NUMBER_WORDS[word_value]) == value:
			aliases.append(String(word_value))

	for homophone_value in TARGET_NUMBER_HOMOPHONES.keys():
		if int(TARGET_NUMBER_HOMOPHONES[homophone_value]) == value:
			aliases.append(String(homophone_value))

	for roman_value in ROMAN_NUMERALS.keys():
		if int(ROMAN_NUMERALS[roman_value]) == value:
			aliases.append(String(roman_value))

	return aliases


static func target_number_from_token(token: String, include_roman: bool = true) -> int:
	var normalized := token.to_lower().strip_edges()

	if normalized.is_valid_int():
		return int(normalized)

	if NUMBER_WORDS.has(normalized):
		return int(NUMBER_WORDS[normalized])

	if TARGET_NUMBER_HOMOPHONES.has(normalized):
		return int(TARGET_NUMBER_HOMOPHONES[normalized])

	if include_roman and ROMAN_NUMERALS.has(normalized):
		return int(ROMAN_NUMERALS[normalized])

	return 0


static func is_roman_numeral(token: String) -> bool:
	return ROMAN_NUMERALS.has(token.to_lower().strip_edges())


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
