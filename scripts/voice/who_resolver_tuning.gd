extends RefCounted
class_name WhoResolverTuning

## Experimental Who-resolver weights.
##
## Text and phonetic evidence intentionally outweigh priors. Number agreement is
## strong because changing a spoken ordinal is especially costly during combat.
## These values should be calibrated against recorded transcripts rather than
## tuned to individual synthetic examples.

const WEIGHT_TEXT_SIMILARITY: float = 0.30
const WEIGHT_PHONETIC_SIMILARITY: float = 0.30
const WEIGHT_STRUCTURAL_FIT: float = 0.22
const WEIGHT_EXACT_EVIDENCE: float = 0.10
const WEIGHT_NUMBER_AGREEMENT: float = 0.35
const WEIGHT_PLURAL_AGREEMENT: float = 0.08
const WEIGHT_COMMAND_COMPATIBILITY: float = 0.04

const PRIOR_NUMBERED_INDIVIDUAL: float = 0.04
const PRIOR_CLASS_GROUP: float = 0.03
const PRIOR_ROLE_GROUP: float = 0.01
const PRIOR_EVERYONE: float = 0.00
const PRIOR_ROW: float = -0.03
const MAX_RECENT_USE_PRIOR: float = 0.025
const RECENT_SELECTION_LIMIT: int = 12

const DEBUG_TOP_CANDIDATE_COUNT: int = 3


static func get_category_prior(target_type: String) -> float:
	match target_type:
		"numbered_individual":
			return PRIOR_NUMBERED_INDIVIDUAL
		"class_group":
			return PRIOR_CLASS_GROUP
		"role_group":
			return PRIOR_ROLE_GROUP
		"row":
			return PRIOR_ROW
		"everyone":
			return PRIOR_EVERYONE
		_:
			return 0.0
