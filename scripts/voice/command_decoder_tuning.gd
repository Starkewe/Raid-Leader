extends RefCounted
class_name CommandDecoderTuning

## Experimental complete-command decoder configuration.
##
## Scores are rankings, not probabilities. Transcript evidence carries most of
## the weight. Grammar and validity distinguish legal complete interpretations,
## while filler, defaults, and recent use remain bounded secondary evidence.
## Tune these values against recorded transcripts rather than isolated examples.

const MAX_ACTION_SPAN_TOKENS: int = 3
const MAX_DESTINATION_SPAN_TOKENS: int = 3
const MAX_WHO_SPAN_TOKENS: int = 4
const MAX_CANONICAL_TERMS_PER_ALIGNMENT: int = 2
const BEAM_WIDTH: int = 12
const TOP_DIAGNOSTIC_CANDIDATES: int = 5
const TOP_WHO_CANDIDATES_PER_SPAN: int = 5

const MIN_ACTION_SIMILARITY: float = 0.48
const MIN_DESTINATION_SIMILARITY: float = 0.46
const MIN_MERGED_SEQUENCE_SIMILARITY: float = 0.50

const WEIGHT_WHO_EVIDENCE: float = 0.34
const WEIGHT_ACTION_EVIDENCE: float = 0.25
const WEIGHT_DESTINATION_EVIDENCE: float = 0.22
const WEIGHT_GRAMMAR: float = 0.10
const WEIGHT_ALIGNMENT: float = 0.06
const WEIGHT_VALIDITY: float = 0.03

const EXACT_EVIDENCE_BONUS: float = 0.08
const CONTEXTUAL_SEMANTIC_BONUS: float = 0.02
const CANONICAL_ORDER_SCORE: float = 1.0
const OMITTED_WHO_GRAMMAR_SCORE: float = 1.0
const MERGED_ALIGNMENT_SCORE: float = 0.88
const SPLIT_ALIGNMENT_SCORE: float = 0.92

const IMPLICIT_DEFAULT_COST: float = 0.035
const FILLER_INTERPRETATION_COST: float = 0.055
const EXTRA_FILLER_TOKEN_COST: float = 0.010
const FUZZY_ACTION_COST: float = 0.015
const FUZZY_DESTINATION_COST: float = 0.015


static func clamp_evidence(value: float) -> float:
	return clampf(value, 0.0, 1.0)
