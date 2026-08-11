extends RefCounted
class_name VoiceTextSimilarity

const PUNCTUATION: Array[String] = [
	".", ",", "!", "?", ":", ";", "\"", "'", "(", ")", "[", "]",
	"-", "‐", "‑", "‒", "–", "—"
]


static func normalize(text: String, remove_punctuation: bool = true) -> String:
	var normalized := text.to_lower().strip_edges()
	if remove_punctuation:
		for character in PUNCTUATION:
			normalized = normalized.replace(character, " ")
	return collapse_spaces(normalized)


static func collapse_spaces(text: String) -> String:
	var output := text.strip_edges()
	while output.contains("  "):
		output = output.replace("  ", " ")
	return output


static func letters_only(text: String) -> String:
	var output := ""
	for index in range(text.length()):
		var character := text.substr(index, 1)
		if character >= "a" and character <= "z":
			output += character
	return output


static func phonetic_code(
	text: String, maximum_length: int = 6, remove_leading_th: bool = false
) -> String:
	var letters := letters_only(text)
	if letters.is_empty():
		return ""
	if remove_leading_th and letters.begins_with("th") and letters.length() > 3:
		letters = letters.substr(2)
	var output := letters.substr(0, 1).to_upper()
	var previous_code := phonetic_digit(letters.substr(0, 1))
	for index in range(1, letters.length()):
		var code := phonetic_digit(letters.substr(index, 1))
		if code != "0" and code != previous_code:
			output += code
		previous_code = code
		if output.length() >= maximum_length:
			break
	return output


static func phrase_phonetic_code(
	text: String, maximum_word_length: int = 8, remove_leading_th: bool = true
) -> String:
	var codes: Array[String] = []
	for token in normalize(text, false).split(" ", false):
		var code := phonetic_code(token, maximum_word_length, remove_leading_th)
		if not code.is_empty():
			codes.append(code)
	return "-".join(codes)


static func phonetic_similarity(left_code: String, right_code: String) -> float:
	if left_code.is_empty() or right_code.is_empty():
		return 0.0
	if left_code == right_code:
		return 1.0
	var initial := 1.0 if left_code.substr(0, 1) == right_code.substr(0, 1) else 0.0
	return initial * 0.35 + normalized_similarity(
		left_code.substr(1), right_code.substr(1)
	) * 0.65


static func phonetic_digit(character: String) -> String:
	if character in ["b", "f", "p", "v"]:
		return "1"
	if character in ["c", "g", "j", "k", "q", "s", "x", "z"]:
		return "2"
	if character in ["d", "t"]:
		return "3"
	if character == "l":
		return "4"
	if character in ["m", "n"]:
		return "5"
	if character == "r":
		return "6"
	return "0"


static func normalized_similarity(left: String, right: String) -> float:
	if left == right:
		return 1.0
	if left.is_empty() or right.is_empty():
		return 0.0
	return 1.0 - float(levenshtein_distance(left, right)) / float(
		maxi(left.length(), right.length())
	)


static func levenshtein_distance(left: String, right: String) -> int:
	var previous_row: Array[int] = []
	for column in range(right.length() + 1):
		previous_row.append(column)
	for row in range(1, left.length() + 1):
		var current_row: Array[int] = [row]
		for column in range(1, right.length() + 1):
			var substitution := 0 if left[row - 1] == right[column - 1] else 1
			current_row.append(mini(
				current_row[column - 1] + 1,
				mini(previous_row[column] + 1, previous_row[column - 1] + substitution)
			))
		previous_row = current_row
	return previous_row[right.length()]
