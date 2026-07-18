# Raid Leader

**Raid Leader** is an experimental real-time strategy / raid-command prototype built in Godot. The project explores how voice input, local speech-to-text, command parsing, and encounter design can be combined to let a player control a party of units through natural-language style commands.

The long-term goal is to create a game where the player acts as the raid leader instead of directly controlling a single character. The player issues commands such as moving roles, repositioning groups, reacting to boss mechanics, and coordinating unit behavior during encounters.

## Project Goals

* Build a real-time command system for controlling multiple combat units.
* Convert voice input into structured command data.
* Support role-based, class-based, group-based, and individual unit targeting.
* Design boss encounters that teach strategic gameplay.
* Explore local AI/NLP systems for responsive, privacy-friendly gameplay.

## Current Features

* Local voice command pipeline using `whisper.cpp`.
* Push-to-talk audio capture inside Godot.
* Speech-to-text transcription routed into a command parser.
* Command parsing for unit, role, class, and group targeting.
* Movement commands based on combat regions around the boss.
* Support for directional regions such as north, south, east, west, and diagonals.
* Support for close, mid, and far movement ranges.
* Exception-based commands such as “everyone except tank.”
* Debug tools for reviewing transcripts, normalized text, parsed command data, and command results.

## Technical Focus

This project is not just a game prototype. It is also a practical AI/NLP systems project focused on turning noisy voice input into reliable structured actions.

Key technical areas include:

* **Speech-to-text integration** using local Whisper models.
* **Natural language command parsing** for real-time gameplay.
* **Data normalization** to clean and standardize inconsistent transcripts.
* **Fuzzy matching** to handle speech recognition errors.
* **Structured command output** for downstream execution.
* **Debug instrumentation** to inspect parser behavior and failure cases.
* **Modular gameplay systems** for movement, target resolution, and boss abilities.

## Tech Stack

* **Engine:** Godot
* **Languages:** GDScript, Python
* **AI / NLP:** whisper.cpp, local Whisper models, speech-to-text parsing
* **Tools:** GitHub, Godot editor, local model files
* **Design Focus:** Real-time command systems, multi-agent control, boss encounter mechanics

## Voice Command Pipeline

The current voice command flow is:

```text
Push-to-talk input
→ Microphone capture
→ WAV processing
→ Local whisper.cpp transcription
→ Transcript normalization
→ Command parsing
→ Target resolution
→ Command execution
```

The parser converts player speech into structured command data that can be used by the game systems. Example command categories include:

* Who should act: individual units, roles, classes, groups, or everyone.
* What action should happen: move, rotate, interrupt, heal, or future abilities.
* Where the action should apply: directional regions and range-based positions.
* Exceptions: commands such as “everyone except tank.”

## Example Commands

```text
Everyone move north
Melee move close east
Ranged move far south
Healers rotate west
Everyone except tank move out
Tank interrupt
```

## Encounter Design

Boss encounters are currently being designed as tutorial-style encounters. Each boss is intended to teach/test one major concept before adding complexity to dedicated bosses.

Current encounter work includes:

* Region-based boss attacks.
* Windup feedback through boss behavior, cast bars, text, or sound.
* Impact feedback when an ability resolves.
* Movement mechanics that interact with the existing combat-region system.

### Twin Sweeping Pull

The Twin Sweeping Pull tutorial boss runs a seven-second scripted mechanic:

1. Pull the living raid into a random close-range region over one second.
2. Telegraph for two seconds, then sweep the pull region and the next two counterclockwise regions.
3. Telegraph for four seconds, then sweep the pull region and the next two clockwise regions.

Both sweeps damage close and mid range; far range remains safe. The boss status and cast name expose the active phase and sweep direction, while impact effects resolve once per affected region.

Run the focused mechanic and boss-lifecycle checks with Godot 4.6:

```text
godot --headless --path . res://tests/twin_sweeping_pull_test.tscn
```

## Current Status

Raid Leader is an active prototype. Core systems are being developed iteratively, with a focus on clean command architecture before expanding encounter complexity.

Current development priorities:

* Improve command parser reliability.
* Expand tutorial boss mechanics.
* Refactor boss ability architecture for reusable mechanics.
* Improve visual and audio feedback for encounter abilities.
* Continue testing voice input latency and transcription accuracy.

## Resume-Relevant Highlights

This project demonstrates practical experience with:

* AI speech-to-text integration.
* NLP command parsing.
* Real-time input processing.
* Data cleaning and transcript normalization.
* Debugging noisy model output.
* Modular software design.
* Multi-agent command execution.
* Gameplay systems architecture.

## Project Notes

This repository is under active development. Some systems, assets, and documentation may change as the prototype evolves.

Local model files and generated audio files may not be included in the repository.
