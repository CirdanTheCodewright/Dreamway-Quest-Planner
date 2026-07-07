# Journey JSON Format

A Journey is a JSON plan for batching quests into ordered chunks of work.

The web app currently exports this shape:

```json
{
  "schemaVersion": 1,
  "app": "QuestiePlus",
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
          "questLevel": 12
        }
      ]
    }
  ]
}
```

## Validation Rules

- A Journey must have a name, race, and class.
- A quest can only appear once in a Journey.
- A quest can only be placed in a batch if all required prerequisites appear in the same batch or an earlier batch.
- Alternative prerequisite groups require at least one listed prerequisite in the same or an earlier batch.
- Race and class restrictions are checked against the Journey character.

## Notes

`expectedLevel` is computed from quest levels unless `expectedLevelManual` is true. `zones` is derived from all zones associated with the quests in that batch.
