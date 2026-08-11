# Extending Raid Leader

Core controllers consume catalogs and typed runtime contracts. New content should enter through these seams rather than adding encounter/class/facility branches to combat, UI, voice, or campaign autoloads.

## Advanced classes

1. Add metadata to `RaiderClassCatalog`, including the stable ID, parent base class, roles, voice aliases, and visual definition.
2. Keep metadata-only classes without a runtime script. To add gameplay later, extend `AdvancedClassRuntime` and implement only the required command/event hooks.
3. Assign the runtime in catalog metadata or register it through `RaiderClassCatalog.register_runtime_script` for tools/tests.

Spawning, raid frames, class visuals, `GameState`, and voice resolution all read the same catalog. The four base combat-unit scenes remain the rendering/combat controllers.

## Encounters and targets

1. Create an `EncounterDefinition` resource and add it to `EncounterCatalog` in the desired order.
2. Ordinary single-boss encounters need no runtime. Specialized mechanics extend `EncounterRuntime` and use its typed lifecycle, command, damage, presentation, reset, cleanup, and attempt-metric hooks.
3. Register bosses, adds, or spawned objectives with `EncounterSession.register_target`, including a stable selector descriptor and `primary_boss_target` when appropriate.
4. Put command-target labels and aliases in the encounter catalog target metadata.

Commands, boss frames, lifecycle coordination, and attempt recording consume `EncounterSession`; they do not require encounter-specific branches.

## Camp definitions

- Activities are `CampActivityDefinition` resources listed by `CampDefinitionCatalog`.
- Stations are validated `CampStationDefinition` resources under `data/camp/stations`.
- Route landmarks are typed `CampRouteNodeDefinition` objects connected by weighted edges and resolved by `CampNavigationService`.
- Conversation frames, raider identity, and lore remain JSON because they are bulk narrative content.

Adding a station or route node does not require editing `CampPopulationController`. Actor lifecycle, reservations/activity scheduling, and conversation coordination are separate services while the controller retains its existing debug facade.

## Campaign state

`CampaignState` is the public facade. Read through snapshots/getters and mutate through explicit methods; never retain or modify its backing dictionary. Saves use one exact schema. An incompatible save starts a fresh campaign in memory and the incompatible file is preserved unchanged.
