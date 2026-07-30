# Raid Leader

**Raid Leader** is a single-player tactical raid-management game built in Godot. Instead of controlling one character directly, the player leads an entire twenty-person raid through positioning, targeting, healing, interrupts, tank swaps, and boss mechanics.

Commands can be issued through the game interface or spoken aloud. Both methods feed into the same command system, allowing the player to direct individuals, classes, roles, groups, or the entire raid while combat continues in real time.

> **Development status:** Raid Leader is an actively developed prototype. Core combat, voice-command parsing, raid management, persistent campaign systems, and the first set of encounters are playable, but the project is not yet a finished release.

## Core Gameplay

Raid Leader is built around the pressure of coordinating a full raid team rather than performing individual attacks.

During an encounter, the player must:

* Position raiders across directional and distance-based regions
* Assign attack, healing, interrupt, and taunt commands
* React to boss casts, hazards, forced movement, and debuffs
* Manage threat and tank swaps
* Preserve raid formations while adapting to changing mechanics
* Recover from mistakes without losing control of the larger strategy

The active raid can contain up to twenty Warriors, Priests, Rogues, and Mages. Each class has a different combat role, movement profile, and set of responsibilities.

## Command System

Commands follow a flexible **Who, What, and Where** structure.

Examples include:

```text
Everyone attack
Melee move close east
Ranged move far south
Healers rotate west
Everyone except tank move out
Rogue two interrupt
Tank taunt
```

The command system supports:

* Individual raiders
* Classes and combat roles
* Groups of raiders
* Numbered targets
* Exclusion-based commands
* Directional and distance-based movement
* Keyboard, interface, and local voice input

The voice parser is designed to handle imperfect speech recognition while still rejecting commands that are incomplete or unsafe to execute.

## Strategic Camp

Between encounters, the player returns to a persistent camp where the raid can be prepared for its next attempt.

Current camp features include:

* A persistent campaign roster
* Raid-member selection and role management
* Boss-specific starting formations
* Encounter and attempt history
* Observed boss-mechanic records
* Immediate encounter retries
* Camp facilities and ambient member activities
* Persistent raider memories and relationships

The long-term goal is for the raid to feel like a developing organization rather than a collection of interchangeable combat units.

## Encounters

The current build includes tutorial content and the first encounters from the **Beast Crucible** region.

### Earthgnasher

A tank-swap encounter centered on stacking attacks, displacement, directional pressure, ground hazards, and raid-wide damage.

### Chainwarden

A mid-range melee encounter built around chained attacks, target positioning, forced movement, and escalating phase pressure.

Each boss is designed to test raid-level decision-making rather than individual mechanical execution.

## Project Goals

Raid Leader explores several design and engineering problems:

* Translating natural-language commands into deterministic game actions
* Controlling many autonomous units without overwhelming the player
* Communicating complex combat information clearly
* Balancing real-time pressure with strategic decision-making
* Maintaining persistent characters and campaign state across encounters
* Building reusable encounter systems for future bosses and regions

The project combines game design, artificial intelligence, command parsing, data-driven architecture, and user-interface development.

## Built With

* **Godot 4.7**
* **GDScript**
* **whisper.cpp** for optional local speech transcription
* Data-driven resources for units, abilities, encounters, and phases

Voice transcription runs locally and does not require a hosted speech service.

## Running the Project

Raid Leader is currently intended to be run from the Godot editor.

1. Install Godot 4.7 or a compatible Godot 4 release.
2. Clone this repository.
3. Import `project.godot` into Godot.
4. Run the main project scene.

The interface and keyboard controls can be used without installing the optional voice-transcription components.

## Current Development Focus

Current work is focused on:

* Improving raid-combat readability
* Expanding boss mechanics and encounter variety
* Refining voice-command accuracy
* Developing threat, targeting, and tank behavior
* Expanding persistent raider progression and relationships
* Building additional regions and advanced classes

## About the Project

Raid Leader is an independent portfolio project created to explore large-group tactical control and voice-assisted gameplay.

It is under active development, so systems, balance, visuals, and content may change substantially as the project evolves.
