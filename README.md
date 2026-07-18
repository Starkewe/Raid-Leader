# Raid Leader

Raid Leader is a Godot 4.6 prototype in which the player coordinates a raid rather than directly controlling one combatant. Keyboard, panel, and local voice commands are converted into the same validated command structure before they reach combat units.

## Current foundation

- Configurable raids of up to 20 Warriors, Rogues, Mages, and Priests.
- Class, role, group, individual, and exclusion-based targeting.
- Attack, heal, interrupt, taunt, and formation-preserving movement commands.
- Eight directional regions with close, mid, and far ranges.
- Resource-driven unit, encounter, phase, and boss-ability tuning.
- Structured combat events containing timestamps, source, target, ability ID, amount, and metadata.
- Reusable foundations for status effects, hazards, forced movement, targeting, and tank swaps.
- Local push-to-talk transcription through `whisper.cpp`.

## Project structure

```text
data/
  abilities/       Boss ability tuning
  encounters/      Boss stats, loadouts, phases, and debug display
  phases/          Health thresholds and pacing rules
  units/           Unit stats, roles, scenes, and voice aliases
scripts/
  abilities/       Runtime boss ability behavior
  combat/          Encounter orchestration and shared combat systems
  commands/        Command validation, targeting, and movement
  data/            Resource schemas
  units/           Combatant behavior
  voice/           Capture, transcription, and parsing
```

Gameplay values belong in `.tres` resources under `data/`. Runtime scripts should implement behavior without replacing those values in `_ready()`.

## Commands

Examples accepted by the voice parser include:

```text
Everyone attack
Melee move close east
Ranged move far south
Healers rotate west
Everyone except tank move out
Rogue two interrupt
Tank taunt
```

The parser rejects transcripts with multiple actions, missing destinations, unknown selectors, or ambiguous fuzzy matches. Unit identities support numbers 1 through 20, and class and role vocabulary comes from `GameState` and the unit resources rather than a second hard-coded catalog.

## Encounters

The menu currently exposes three tutorial encounters:

- Close-region directional cleave.
- Full-region cone across close, mid, and far range.
- Twin Sweeping Pull: a 1.5-second random close-range pull, a 2.5-second counterclockwise sweep, and a four-second clockwise sweep (eight seconds total).

Twin Sweeping Pull is target-independent and continues if the boss's current target dies. Directional cleaves require an active target and lock their region when the cast starts.

## Local voice setup

The default paths are project-relative:

```text
tools/whisper.cpp/build/bin/whisper-cli
tools/whisper.cpp/build/bin/Release/whisper-cli.exe
tools/whisper.cpp/models/
```

The platform-specific CLI path and selected model are resolved by `GameState`. Local binaries, models, generated WAV files, build outputs, and editor state are intentionally ignored by Git.

Hold `V` to record a command. Recordings are trimmed only at their edges, queued with a short lifetime, and discarded if transcription finishes too late to be safe for real-time combat.

## Manual verification

This prototype currently uses manual encounter testing rather than an automated gameplay test suite. Before merging gameplay changes, verify at minimum:

1. Build a 20-member roster and confirm frames, formations, roles, and identities remain distinct.
2. Exercise every panel action and representative voice commands, including rejected ambiguous input.
3. Kill the current boss target during both a target-locked cleave and Twin Sweeping Pull.
4. Taunt between two Warriors and confirm boss-target healing follows the new target.
5. Reset after a wipe and victory and confirm health, casts, movement, statuses, targets, and the combat log are cleared.
6. Run each tutorial at multiple window sizes and confirm the raid frames, boss frame, and command panel remain usable.

## Status

The repository is a pre-v1 gameplay foundation. The next design work can build encounter mechanics on the resource schemas and shared primitives without expanding hard-coded catalogs or duplicating combat state.
