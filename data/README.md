# Gameplay and system data

`data/` is the project's single authoring root. Unit, action, ability, encounter,
healing, phase, and camp-content resources remain in their domain folders. Narrative
content remains JSON. Cross-system numeric tuning lives in `data/tuning/` so a value
has one authored source.

## Tuning catalog

`data/tuning/catalog.tres` is the root resource loaded once by the `TuningCatalog`
autoload. It references these resources:

| Resource | What it controls | Units and constraints |
| --- | --- | --- |
| `raid_campaign.tres` | Active raid limits, group size, campaign cast and initial roster, class composition, attempt history, and quarters capacity | Counts are positive integers. The raid size must divide evenly into groups, the initial class counts must total the initial roster, campaign class counts must total the cast, initial counts cannot exceed campaign counts, and quarters must hold the cast. |
| `combat.tres` | Range-unit conversion, boss radius, close/mid/far bands, formation spacing, manual and automatic movement safety, player movement, threat, taunt, and healing interruption timing | Distances are pixels unless named `*_range_units`; speeds are per second; angles are radians; durations are seconds; multipliers are positive. Range bands must increase from close to far. Safety margins may be zero, but not negative. |
| `dodge.tres` | Per-class charges, movement type, distance, duration, recharge, physical-dash easing, and the Rogue's second-dash threshold | Distances are formation spacings; durations/recharges are seconds. Charges and all measurements are positive. Exactly one profile is required for Warrior, Priest, Rogue, and Mage. Movement type is `physical` or `teleport`. |
| `camp.tres` | Event history, memory lifecycles, relationships, conversations, activity scheduling, navigation tolerances, camp movement, population clearance, and interactive-facility radii | Durations are seconds, distances/speeds are pixels or pixels per second, probabilities are in `[0, 1]`, capacities are positive, and every minimum must be no greater than its maximum. Memory category keys and relationship thresholds are validated. Facility radii must reference the known interactive camp facilities. |
| `voice.tres` | Audio capture cleanup, recording/transcription limits, command-decoder spans, beams, evidence thresholds and weights, Who-resolver weights, category priors, and recency rules | Durations are seconds, queue/beam/token values are positive counts, and scores/probabilities/priors are in `[0, 1]`. Minimum recording time cannot exceed the maximum. Decoder evidence weights and resolver identity weights must each total `1.0`. |
| `runtime_limits.tres` | Combat-log retention, combat-event queue compaction, and projectile/impact pool capacities | Positive integer capacities or thresholds. |

Presentation-only animation, VFX, and drawing values stay beside their renderer and
use names ending in `PRESENTATION_*`. Encounter-specific balance remains in the
typed encounter resources. Mathematical identities, enum values, sentinels,
correctness tolerances, route topology, scene transforms, collision geometry, and UI
layout are not tuning-catalog values.

## Editing workflow

1. Open the appropriate `.tres` in Godot's Inspector, or edit it as text.
2. Change the existing property in its owning resource. Do not add a second default to
   a consumer script.
3. If a new cross-system knob is needed, add a typed exported property to the matching
   resource class under `scripts/data/tuning/`, author it in the `.tres`, add validation,
   and read it through `TuningCatalog`.
4. Run the catalog contract, then the complete regression gate:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File ./tools/run_regressions.ps1 -GodotPath <path-to-godot> -Filter tuning_catalog_contract
   powershell -NoProfile -ExecutionPolicy Bypass -File ./tools/verify_regression_runner.ps1 -GodotPath <path-to-godot>
   powershell -NoProfile -ExecutionPolicy Bypass -File ./tools/run_regressions.ps1 -GodotPath <path-to-godot>
   ```

Invalid or missing catalog data reports the complete property path during startup and
the contract test. Runtime consumers do not substitute hardcoded tuning fallbacks.

Tuning is not hot-reloaded. Restart the running game or test process after editing a
tuning resource.

## Progression catalog

`data/progression/catalog.tres` is the typed root for boss/archetype assignments,
weapon-family compatibility, first-clear tokens, material rarity/source metadata,
layered reward tables, weapons and stat profiles, future weapon-trait hooks, crafting
recipes, and raider-trait scaffolding. It is loaded once by `ProgressionCatalog`.

Progression validation is cross-resource: errors identify the complete
`catalog.<collection>[index].property` path and reject unknown or duplicate stable IDs,
compatibility drift, invalid roll weights/counts, invalid reward sources, incomplete
boss weapon sets, and recipes without both a rare source-boss primary and a cross-boss
component. Restart the process after catalog edits; progression content is not
hot-reloaded.

The extension and reward-revision workflow is documented in
`docs/EXTENDING_SYSTEMS.md`.
