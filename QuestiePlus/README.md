# QuestiePlus

Questie companion addon for testing a Journey batch tracker concept.

## Install

Copy the whole `QuestiePlus` folder into your Classic WoW AddOns folder, next to `Questie`.

Example:

```text
World of Warcraft\_classic_era_\Interface\AddOns\QuestiePlus
```

Then restart WoW or run `/reload`.

## Test

The addon adds a compact `Questie | Plus` toggle above the Questie tracker.

- `Questie` shows the normal Questie tracker.
- `Plus` replaces the Questie tracker content with the current Journey batch, grouped as `Finish prerequisite`, `Pick up`, `In Progress`, and `Turn In`.
- Click the batch title in Plus mode to open the QuestiePlus Journey panel.
- Use `Import Journey` in the panel to paste the compact `QPJ2` addon string copied from the web app.
- QuestiePlus records a per-character completion profile in
  `WTF/Account/<account>/<realm>/<character>/SavedVariables/QuestiePlus.lua`.
  Import that file with the web app's `Import Profile` button to display completed quests.
- The Journey panel can drag quests between batches and Hidden, and can search quests across those pools.
- The Journey panel can export the same compact `QPJ2` format for round-tripping edits back to the web app.
- Hidden quests suppress Questie pickup icons while Plus mode is active.

Slash commands:

```text
/qp plus
/qp questie
/qp panel
```
