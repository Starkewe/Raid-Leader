# Camp V1 Bug-Fix Playtest

## Main menu and saves

- New Game enters a fresh Camp campaign and preserves the prior campaign as an older save snapshot.
- Continue opens the current campaign.
- Load Game lists older snapshots and loads the selected one.
- Tutorial uses the default 2 Warrior / 5 Priest / 6 Rogue / 7 Mage composition.
- The old Tutorial Test Roster button is absent.
- Settings still changes and persists the speech-to-text model.

## Escape menus

- Escape in Camp opens the Camp Menu instead of returning directly to the main menu.
- Escape during a normal campaign raid opens the Raid Menu.
- Escape during a tutorial opens the Tutorial Menu.
- Resume unpauses cleanly.
- Return to Camp, Return to Main Menu, restart, and quit actions route correctly.

## Command Tent roster

- Seed debug reserves in a debug build if reserves are needed for testing.
- Drag an active member into Reserves and confirm the active count decreases.
- Drag a reserve onto an active card or Active empty space and confirm the member is added.
- Drag active rows onto one another and confirm active order changes.
- Confirm a raid with 1-19 members validates with a below-full-strength warning.
- Confirm removing the final active member is blocked.
- Confirm adding a 21st active member is blocked.
- Confirm formation placements remain valid after add/remove operations.

## Formation editing

- Formation Yard shows the full radial 24-mini-region editor.
- Drag members to multiple regions/rings and confirm saved placements.
- Reorder active members from the Formation Yard.
- Save, load, and delete custom formations.
- After a wipe, Formation Edit shows the same radial editor rather than dropdowns.
- Changing a post-wipe formation and retrying respawns the raid in the new positions.
- During campaign combat, Escape > Edit Formation saves changes for the restarted attempt.

## Archive and review

- Attempt Review scrolls without expanding beyond the failure screen.
- Archive target switching does not crash.
- Archive keeps target tabs and intelligence anchored.
- Only the history area scrolls.
- The newest five attempts appear as detailed bordered cards.
- Older attempts remain collapsed until expanded.
- Timeline chips have distinct colors and useful hover tooltips.

## Camp visuals

- Facility sprites no longer show atlas-edge clipping or neighboring-cell bleed.
- Formation Yard markers are centered on the yard.
- Empty victory spike appears without a trophy.
- After victory, the trophy display does not overlap a second procedural spike.
- Trophy label remains readable and clear of the sprite.
