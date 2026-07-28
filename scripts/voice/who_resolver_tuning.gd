extends RefCounted
class_name WhoResolverTuning

## Experimental Who-resolver weights.
##
## Identity evidence ranks candidates after structure and a recognized number
## have filtered the eligible target family and index. Text, phonetic, exact,
## and partial evidence are intentionally separate so the same spoken token is
## not rewarded through multiple structural components.
##
## Structural and number weights are deliberately small: matching structure and
## index is primarily an eligibility requirement, not evidence that one class is
## more likely than another. Static and recent-use priors are tie-breakers only.
## These values should be calibrated against recorded transcripts rather than
## tuned to individual synthetic examples.

const WEIGHT_IDENTITY_TEXT_SIMILARITY: float = 0.44
const WEIGHT_IDENTITY_PHONETIC_SIMILARITY: float = 0.34
const WEIGHT_IDENTITY_EXACT_EVIDENCE: float = 0.14
const WEIGHT_IDENTITY_PARTIAL_EVIDENCE: float = 0.08

const WEIGHT_STRUCTURAL_FIT: float = 0.04
const WEIGHT_NUMBER_AGREEMENT: float = 0.02
const WEIGHT_PLURAL_AGREEMENT: float = 0.04
const WEIGHT_COMMAND_COMPATIBILITY: float = 0.02

const PRIOR_NUMBERED_INDIVIDUAL: float = 0.010
const PRIOR_CLASS_GROUP: float = 0.008
const PRIOR_ROLE_GROUP: float = 0.004
const PRIOR_EVERYONE: float = 0.00
const PRIOR_ROW: float = 0.00
const MAX_RECENT_USE_PRIOR: float = 0.008
const RECENT_IDENTITY_TIE_WINDOW: float = 0.025
const RECENT_SELECTION_LIMIT: int = 12
const ROW_COMPETITION_MIN_IDENTITY_SCORE: float = 0.40

const DEBUG_TOP_CANDIDATE_COUNT: int = 5


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
