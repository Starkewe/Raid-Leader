# Camp V1 manual playtest

Run a Godot 4.6 development build at the project's normal 1920×1080 viewport. For a clean-campaign pass, back up and remove `user://raid_leader_campaign_v1.json` before launch. The campaign save is separate from the existing tutorial/voice settings file.

## 1. Arrival and orientation

1. From the main menu, choose **Enter Camp**.
2. Confirm the commander enters through the open southern gate.
3. Walk north past the empty/latest-victory spike to the communal fire and command tent.

Expected: the camp is continuous and larger than one screen; the fire sits below center, the command tent above it, and no loading screen divides facilities.

## 2. Travel budget and access

1. From the southern spawn, time normal `WASD` travel to the fire, command tent, formation yard, and archive.
2. Repeat for the smith, apothecary, liaison, quarters, and training area.
3. Try walking through facility footprints and along the central spine while members move nearby.

Expected: core facilities are comfortably within about 10 seconds, all others within about 15 seconds, structures collide, and NPCs never block the player.

## 3. Facility ownership and prompts

1. Approach the command tent, formation yard, and archive; press `E` at each.
2. Approach the smith, apothecary, liaison, quarters, training props, fire, storage, and trophy spike.

Expected: only the three functional facilities show interaction prompts. `Esc` closes an open journal before it returns to the main menu.

## 4. Starting Writ and Raid Plan

1. Open the command tent.
2. Count the active roster and role/class mix.
3. Inspect several members.

Expected: exactly 20 are active—2 Warrior tanks, 5 Priest healers, 6 Rogue DPS, and 7 Mage DPS. Names, attributes, descriptions, target, formation, placed count, support state, intel, latest attempt, and readiness are visible.

## 5. Targets and per-boss persistence

1. Select Ogre, then visit the formation yard and change one member's region/range.
2. Return to the command tent, select Chainmaster, and inspect its formation.
3. Change a different Chainmaster placement, switch back to Ogre, and inspect again.

Expected: both bosses are immediately available, neither is labeled apex, future regions remain visibly locked, and each boss retains its own formation without changing the active roster.

## 6. Formation ownership and launch

1. At the formation yard, select a member and verify the controls preload that member's saved region/range.
2. Assign several placements and observe the rehearsal markers outside.
3. Check the command-tent plan summary, then embark.

Expected: the summary reads **Custom**, all 20 remain valid, and combat units spawn in the saved regions/range rings around the selected boss.

## 7. Wipe review

1. Begin combat and allow the raid to wipe.
2. Open **Attempt Review**.
3. Compare duration, phase, boss progress, death time/cause, totals, detected mechanic failures, discoveries, and timeline with the attempt.

Expected: commands stop after the wipe; the review uses observed structured events and does not prescribe a composition.

## 8. Exact retry

1. On the wipe screen, choose **Retry Exact Raid Plan** without editing formation.
2. Compare boss, named active members, class ordinals, and starting positions with the previous pull.

Expected: the encounter resets in place with the identical plan and no camp visit or maintenance step.

## 9. Bounded post-wipe edit

1. Wipe again and open **Minor Formation Edit**.
2. Select a member and confirm its saved placement preloads.
3. Change only its region/range and retry.

Expected: roster, target, and support controls are absent; retry reloads combat so the changed placement is applied while the rest of the Raid Plan persists.

## 10. Camp return and roster-only-at-camp rule

1. From a wipe, choose **Return to Camp**.
2. Confirm arrival at the southern approach with wipe reactions.
3. In a development build, open the command tent and choose **Debug: Seed 20 Reserves** once.
4. Swap one active member with one reserve and embark.

Expected: the roster can change only at the command tent; the incoming member inherits the outgoing formation slots for both bosses; combat spawns the new active 20.

## 11. Living raid and forty-member stress pass

1. With debug reserves seeded, close the journal and observe camp for at least two minutes.
2. Compare active and reserve behavior across command, formation, archive, support, training, quarters, and fire areas.

Expected: all 40 appear; active members train/prepare/study more often in aggregate, reserves rest/support/socialize more often, individuals vary, and the frame rate remains acceptable.

## 12. Slot recovery and interruption

1. While many members are moving or performing activities, reopen a strategic facility and make a target, roster, or formation change that rebuilds the population.
2. Close the journal and continue observing several cycles.

Expected: facility reservations release during interruption; members resume choosing activities; no slot or actor remains permanently stuck.

## 13. Reaction scaling and readability

1. Make one roster swap and observe reactions.
2. Make roughly ten swaps in the same visit and walk around camp.

Expected: the larger change produces substantially more dispersed reactions, but no more than three bubbles are visible simultaneously and no dialogue is required for progress.

## 14. Victory state

1. Defeat either Ogre or Chainmaster.
2. Confirm the victory screen reports the immediate reward state, then return to camp.
3. Inspect the southern trophy spike and ambient reactions.
4. Defeat the other boss and return again; then repeat a victory once.

Expected: the first victory has the stronger reaction budget, repeats use the smaller response, the latest trophy replaces the previous one rather than accumulating, and attempt history retains older victories.

## 15. Save/reload and repeated round trips

1. Change target, active roster, and formations for both bosses; complete at least one attempt.
2. Quit and relaunch the project, re-enter camp, and inspect the command tent, formation yard, and archive.
3. Complete several camp → combat → retry/return cycles.

Expected: campaign state, per-boss formations, discoveries, and attempt history survive reload; transient visit reactions do not become permanent; no members duplicate; UI focus and prompts remain functional.

## Visual pass

During every scenario, flag any blurred pixel edges, fractional movement shimmer, incorrect depth overlap, overly dark path, hidden prompt, or facility art whose shallow facade perspective conflicts with strict overhead readability.
