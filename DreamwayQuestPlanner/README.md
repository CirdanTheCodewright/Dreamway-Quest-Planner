# Dreamway

Questie companion addon for planning and following Dreamway Journeys in game.

Dreamway ships flavor-specific metadata for Classic Era/Season of Discovery,
Burning Crusade Classic, and Wrath of the Lich King Classic. Only the database
for the running client is loaded.

## Install

Copy the whole `DreamwayQuestPlanner` folder into your Classic WoW AddOns folder, next to `Questie`.

Example:

```text
World of Warcraft\_classic_era_\Interface\AddOns\DreamwayQuestPlanner
```

Then restart WoW or run `/reload`.

Release packages also include the companion web app in `WebApp`. Open
`WebApp/dreamway.html` in a browser; keep the HTML, `data`, `assets`, and icon
files together so its lazy-loaded quest databases and maps remain available.

## Test

The addon adds a compact `Questie | Dreamway` toggle above the Questie tracker.

- `Questie` shows the normal Questie tracker.
- `Dreamway` replaces the Questie tracker content with the current Journey batch, grouped as `Finish prerequisite`, `Pick up`, `In Progress`, and `Complete`.
- Click the batch title in Dreamway mode to open the Dreamway Journey panel.
- Use `Manage Journeys` to create, import, export, inspect, edit, activate, or delete account-wide Journeys.
- Journey game version is fixed, while faction, race, and class metadata can be edited in game.
- Dreamway records a per-character completion profile in
  `WTF/Account/<account>/<realm>/<character>/SavedVariables/DreamwayQuestPlanner.lua`.
  Import that file with the web app's `Import Profile` button to display completed quests.
- The Journey panel can drag quests between batches and Hidden, and can search quests across those pools.
- Quest Search groups related quests into collapsible chains, labels each chain
  with its quest count, and provides `-` / `+` controls to collapse or expand
  every visible chain. Standalone quests remain at the top-level indentation.
  Complex chains are
  divided into stable subchains with prerequisite labels before each dependent
  section; hovering a label highlights its visible prerequisite quests.
- Search filters cover character, zone, and quest-type choices. All zones begin
  enabled, while character filters default to the logged-in character.
  Quest Search only lists currently available quests that are green or harder.
  Season of Discovery adds its independent content filter.
- `Hide assigned` is enabled by default so assigned, completed, and Hidden quests stay out of search results.
- The header-level `Hidden` target remains available while browsing any batch.
- The Journey panel can export the same compact `DWJ2` format for round-tripping edits back to the web app.
- Hidden quests suppress Questie pickup icons while Dreamway mode is active.

Slash commands:

```text
/dw dreamway
/dw questie
/dw panel
```
