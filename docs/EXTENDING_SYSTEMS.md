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

## Boss rewards and equipment progression

`data/progression/catalog.tres` is the authoritative progression content root. The
`ProgressionCatalog` autoload loads and indexes it once. The root contains typed
regions/boss assignments, weapon families, tokens, material rarities and materials,
reward tables/layers, weapons/stat profiles, future weapon-trait hooks, recipes, and
raider-trait definitions.

To extend progression content:

1. Add or edit typed subresources in `catalog.tres`; never add an encounter-keyed
   counter or weapon-stat branch to `CampaignState` or a unit class.
2. Keep stable IDs lowercase snake case. Add every encounter, class, family,
   material, token, recipe, weapon, and trait reference to the same validated graph.
3. For a new boss, assign its region/archetype, token, reward table, and exactly two
   weapons. At least one weapon must use a family native to the boss archetype.
4. Ensure each recipe contains a rare component sourced by its boss and a component
   sourced by another boss. Initial Beast Crucible families may contain at most two
   weapons each.
5. When reward balance changes, increment that reward table's revision. New receipts
   include the revision in their deterministic seed; existing receipts remain the
   replay authority for already-processed attempts.
6. Add catalog, reward, crafting/equipment, stat-adapter, schema, and presentation
   contract coverage before enabling the content.

`CampaignRewardService` owns idempotent victory transactions and receipt generation.
`CampaignProgressionService` owns crafting, equipment, trait slots, recovery
diagnostics, and inventory reads. `CampaignState` remains their public facade.
Crafted weapon IDs represent reusable definitions rather than item instances, so one
owned weapon can be equipped by multiple compatible raiders.

Combat receives only the validated runtime weapon projection on a raid-member record.
`WeaponStatAdapter` is the common power/timing/range calculation seam for all four
base unit controllers. Weapon-trait hooks are descriptive metadata and have no combat
effect in this pass. Raider traits are a separate major/two-minor scaffold; the
production catalog intentionally authors none. `doctrine_id` is persistence-only.

Camp Stores presents progression through `StoragePagePresenter`. Production views are
read-only. Any fixture grant, seeded reward, craft, equip, or trait inspection control
must remain inside `OS.is_debug_build()` and the `storage_debug_mutation` group.

## Campaign state

`CampaignState` is the public facade. Read through snapshots/getters and mutate through explicit methods; never retain or modify its backing dictionary. Saves write one exact current schema. The immediately previous version may have an explicit in-memory migration; unsupported older, future, or corrupt saves start a fresh campaign in memory and remain preserved unchanged on disk.

Schema migrations must duplicate the loaded dictionary, preserve unrelated state,
record lossy/unknown input under migration diagnostics, and never manufacture random
historical outcomes. Unknown saved content IDs remain stored for recovery but are
inactive at runtime until their definitions return.
