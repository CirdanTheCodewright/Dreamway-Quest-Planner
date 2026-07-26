# Journey JSON Format

A Journey is a JSON plan for batching quests into ordered chunks of work.

The web app currently exports this shape:

```json
{
  "schemaVersion": 1,
  "app": "Dreamway",
  "kind": "Journey",
  "savedAt": "2026-07-07T00:00:00.000Z",
  "id": "darkshore-12-18",
  "name": "Darkshore 12-18",
  "character": {
    "race": "Night Elf",
    "raceMask": 8,
    "faction": "Alliance",
    "class": "Druid",
    "classMask": 1024
  },
  "hiddenQuestIds": [4681],
  "hiddenQuests": [
    {
      "id": 4681,
      "name": "Washed Ashore",
      "requiredLevel": 11,
      "questLevel": 13,
      "preQuestSingle": [],
      "preQuestGroup": [],
      "zones": ["Darkshore"],
      "hidden": true
    }
  ],
  "batches": [
    {
      "id": "batch-example",
      "name": "Auberdine north loop",
      "expectedLevel": 14,
      "expectedLevelManual": false,
      "expectedLevelOverride": null,
      "zones": ["Darkshore"],
      "questIds": [983, 947],
      "quests": [
        {
          "id": 983,
          "name": "Buzzbox 827",
          "requiredLevel": 10,
          "questLevel": 12,
          "preQuestSingle": [],
          "preQuestGroup": []
        }
      ]
    }
  ]
}
```

## Validation Rules

- A Journey must have a name, race, and class.
- A quest can only appear once, either assigned to a batch or in Hidden.
- A quest can only be placed in a batch if all required prerequisites appear in the same batch or an earlier batch.
- Alternative prerequisite groups require at least one listed prerequisite in the same or an earlier batch.
- Race and class restrictions are checked against the Journey character.

Journey imports are non-blocking for prerequisite failures. A quest whose prerequisites are not present in the same or an earlier batch, and are not completed in the active character profile, is marked with a warning icon. Importing a profile that satisfies those prerequisites removes the warning automatically. Existing warnings do not block unrelated edits, but an edit cannot introduce a new prerequisite warning.

## Notes

`expectedLevel` is computed from quest levels unless `expectedLevelManual` is true. `zones` is derived from all zones associated with the quests in that batch.

`hiddenQuestIds` / `hiddenQuests` represent quests the user intentionally removed from progression. While Dreamway mode is active, the addon hides Questie pickup icons for these quests. The export currently also includes legacy `unusedQuestIds` / `unusedQuests` aliases for backward compatibility.

Quests that are neither assigned to a batch nor hidden are omitted from the Journey export. The web app can always derive that ordinary unassigned state from the Questie dataset, which keeps addon import strings small enough for WoW's edit boxes.

The downloadable Journey file remains JSON. For transfer through WoW edit boxes, the web app and addon use the compact positional `DWJ2` string format instead of embedding quest names, zone names, or JSON property labels. New strings use colon-delimited top-level fields because WoW treats pipe characters as UI markup. Pipe-delimited strings and pre-rename `QPJ2` strings remain importable. The addon stores the imported Journey as Lua SavedVariables.

`preQuestSingle` means any one listed quest can satisfy the prerequisite; `preQuestGroup` means every listed quest must be complete.
