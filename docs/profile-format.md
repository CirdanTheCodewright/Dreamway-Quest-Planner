# Character Profile Format

Dreamway stores one `DreamwayProfile` SavedVariables table per character. Schema version 2 adds a compact ordered replay event log alongside `completedQuestIds`.

```json
{
  "schemaVersion": 2,
  "eventSchemaVersion": 2,
  "kind": "CharacterProfile",
  "character": {
    "name": "Daddylow",
    "race": "Human",
    "class": "Warrior"
  },
  "completedQuestIds": [7, 18, 33],
  "events": [
    [1768496490, 1, 1429, 4870, 4280, 783]
  ]
}
```

Each event is a positional array:

1. Server epoch timestamp in seconds.
2. Event type code.
3. WoW UiMapID.
4. X coordinate from 0 to 10000.
5. Y coordinate from 0 to 10000.
6. Event-specific fields.

Event type fields:

| Code | Event | Additional fields |
| --- | --- | --- |
| 1 | Quest pickup | questID |
| 2 | Quest hand-in | questID |
| 3 | Mob killed | npcID |
| 4 | Player death | none |
| 5 | Objective progressed | questID, objective index, current count, required count |
| 6 | Quest objectives complete | questID |
| 7 | Level gained | new level |
| 8 | Character login | none |
| 9 | Character logout | none |

Events with the same timestamp remain ordered by their position in the array. Coordinates are integer-quantized to keep long, kill-heavy profiles compact.

Replay preserves the original server timestamps but uses a derived playback clock. Gaps of 30 minutes or less retain their real duration; any longer gap is compressed to five minutes. This keeps long offline or idle periods from dominating the replay while preserving the true dates in the event log.
