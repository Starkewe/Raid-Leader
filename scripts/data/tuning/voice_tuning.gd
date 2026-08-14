extends Resource
class_name VoiceTuning

const KNOWN_TARGET_TYPES: Array[String] = [
	"numbered_individual", "class_group", "role_group", "everyone", "row"
]

@export_group("Capture and transcription")
@export var hard_zero_threshold: float
@export var max_hard_zero_run_kept: int
@export var min_record_seconds: float
@export var max_record_seconds: float
@export var microphone_restart_delay_frames: int
@export var target_peak: float
@export var silence_threshold: float
@export var keep_silence_seconds: float
@export var max_queued_transcriptions: int
@export var transcription_ttl_seconds: float
@export var transcription_process_timeout_seconds: float

@export_group("Command decoder limits")
@export var max_action_span_tokens: int
@export var max_destination_span_tokens: int
@export var max_who_span_tokens: int
@export var max_canonical_terms_per_alignment: int
@export var decoder_beam_width: int
@export var top_diagnostic_candidates: int
@export var top_who_candidates_per_span: int

@export_group("Command decoder thresholds")
@export var min_action_similarity: float
@export var min_low_confidence_action_similarity: float
@export var min_destination_similarity: float
@export var min_merged_sequence_similarity: float
@export var min_exact_action_merged_similarity: float
@export var min_collapsed_term_similarity: float
@export var min_low_confidence_who_identity_score: float
@export var min_low_confidence_who_identity_margin: float
@export var max_action_capability_specificity_bonus: float
@export var min_low_confidence_distinct_command_margin: float

@export_group("Command decoder weights")
@export var decoder_weight_who_evidence: float
@export var decoder_weight_action_evidence: float
@export var decoder_weight_destination_evidence: float
@export var decoder_weight_grammar: float
@export var decoder_weight_alignment: float
@export var decoder_weight_validity: float
@export var exact_evidence_bonus: float
@export var contextual_semantic_bonus: float
@export var canonical_order_score: float
@export var omitted_who_grammar_score: float
@export var merged_alignment_score: float
@export var split_alignment_score: float
@export var implicit_default_cost: float
@export var filler_interpretation_cost: float
@export var extra_filler_token_cost: float
@export var fuzzy_action_cost: float
@export var fuzzy_destination_cost: float

@export_group("Who resolver")
@export var identity_text_similarity_weight: float
@export var identity_phonetic_similarity_weight: float
@export var identity_exact_evidence_weight: float
@export var identity_partial_evidence_weight: float
@export var structural_fit_weight: float
@export var number_agreement_weight: float
@export var plural_agreement_weight: float
@export var command_compatibility_weight: float
@export var target_category_priors: Dictionary = {}
@export var max_recent_use_prior: float
@export var recent_identity_tie_window: float
@export var recent_selection_limit: int
@export var row_competition_min_identity_score: float
@export var resolver_debug_top_candidate_count: int


func get_target_category_prior(target_type: String) -> float:
	return float(target_category_priors.get(target_type, 0.0))


func clamp_evidence(value: float) -> float:
	return clampf(value, 0.0, 1.0)


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in [
		["max_hard_zero_run_kept", max_hard_zero_run_kept],
		["microphone_restart_delay_frames", microphone_restart_delay_frames],
		["max_queued_transcriptions", max_queued_transcriptions],
		["max_action_span_tokens", max_action_span_tokens],
		["max_destination_span_tokens", max_destination_span_tokens],
		["max_who_span_tokens", max_who_span_tokens],
		["max_canonical_terms_per_alignment", max_canonical_terms_per_alignment],
		["decoder_beam_width", decoder_beam_width],
		["top_diagnostic_candidates", top_diagnostic_candidates],
		["top_who_candidates_per_span", top_who_candidates_per_span],
		["recent_selection_limit", recent_selection_limit],
		["resolver_debug_top_candidate_count", resolver_debug_top_candidate_count],
	]:
		if int(field[1]) <= 0:
			errors.append("%s must be greater than zero." % String(field[0]))
	for field in [
		["hard_zero_threshold", hard_zero_threshold],
		["min_record_seconds", min_record_seconds],
		["max_record_seconds", max_record_seconds],
		["silence_threshold", silence_threshold],
		["keep_silence_seconds", keep_silence_seconds],
		["transcription_ttl_seconds", transcription_ttl_seconds],
		["transcription_process_timeout_seconds", transcription_process_timeout_seconds],
	]:
		if float(field[1]) <= 0.0:
			errors.append("%s must be greater than zero." % String(field[0]))
	if min_record_seconds > max_record_seconds:
		errors.append("min_record_seconds must not exceed max_record_seconds.")
	_validate_probability(errors, "target_peak", target_peak)
	for field in [
		["min_action_similarity", min_action_similarity],
		["min_low_confidence_action_similarity", min_low_confidence_action_similarity],
		["min_destination_similarity", min_destination_similarity],
		["min_merged_sequence_similarity", min_merged_sequence_similarity],
		["min_exact_action_merged_similarity", min_exact_action_merged_similarity],
		["min_collapsed_term_similarity", min_collapsed_term_similarity],
		["min_low_confidence_who_identity_score", min_low_confidence_who_identity_score],
		["min_low_confidence_who_identity_margin", min_low_confidence_who_identity_margin],
		["max_action_capability_specificity_bonus", max_action_capability_specificity_bonus],
		["min_low_confidence_distinct_command_margin", min_low_confidence_distinct_command_margin],
		["exact_evidence_bonus", exact_evidence_bonus],
		["contextual_semantic_bonus", contextual_semantic_bonus],
		["canonical_order_score", canonical_order_score],
		["omitted_who_grammar_score", omitted_who_grammar_score],
		["merged_alignment_score", merged_alignment_score],
		["split_alignment_score", split_alignment_score],
		["implicit_default_cost", implicit_default_cost],
		["filler_interpretation_cost", filler_interpretation_cost],
		["extra_filler_token_cost", extra_filler_token_cost],
		["fuzzy_action_cost", fuzzy_action_cost],
		["fuzzy_destination_cost", fuzzy_destination_cost],
		["max_recent_use_prior", max_recent_use_prior],
		["recent_identity_tie_window", recent_identity_tie_window],
		["row_competition_min_identity_score", row_competition_min_identity_score],
	]:
		_validate_probability(errors, String(field[0]), float(field[1]))
	_validate_weight_total(
		errors,
		"decoder evidence weights",
		[
			decoder_weight_who_evidence,
			decoder_weight_action_evidence,
			decoder_weight_destination_evidence,
			decoder_weight_grammar,
			decoder_weight_alignment,
			decoder_weight_validity,
		]
	)
	_validate_weight_total(
		errors,
		"resolver identity weights",
		[
			identity_text_similarity_weight,
			identity_phonetic_similarity_weight,
			identity_exact_evidence_weight,
			identity_partial_evidence_weight,
		]
	)
	for field in [
		["structural_fit_weight", structural_fit_weight],
		["number_agreement_weight", number_agreement_weight],
		["plural_agreement_weight", plural_agreement_weight],
		["command_compatibility_weight", command_compatibility_weight],
	]:
		_validate_probability(errors, String(field[0]), float(field[1]))
	for target_type in KNOWN_TARGET_TYPES:
		if not target_category_priors.has(target_type):
			errors.append("target_category_priors is missing '%s'." % target_type)
	for target_type_value in target_category_priors:
		if String(target_type_value) not in KNOWN_TARGET_TYPES:
			errors.append(
				"target_category_priors contains unknown target type '%s'."
				% String(target_type_value)
			)
		var prior := float(target_category_priors[target_type_value])
		_validate_probability(errors, "target_category_priors[%s]" % target_type_value, prior)
	return errors


func _validate_probability(errors: PackedStringArray, field_name: String, value: float) -> void:
	if value < 0.0 or value > 1.0:
		errors.append("%s must be in [0, 1]." % field_name)


func _validate_weight_total(
	errors: PackedStringArray, field_name: String, weights: Array[float]
) -> void:
	var total := 0.0
	for weight in weights:
		if weight < 0.0 or weight > 1.0:
			errors.append("%s must each be in [0, 1]." % field_name)
		total += weight
	if not is_equal_approx(total, 1.0):
		errors.append("%s must total 1.0; they total %.6f." % [field_name, total])
