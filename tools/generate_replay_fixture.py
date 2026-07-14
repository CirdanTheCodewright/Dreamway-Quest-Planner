import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "samples" / "daddylow-profile.json"
ELWYNN_UI_MAP_ID = 1429


def packed_event(timestamp, event_type, x, y, *fields):
    return [
        int(timestamp),
        int(event_type),
        ELWYNN_UI_MAP_ID,
        round(float(x) * 100),
        round(float(y) * 100),
        *[int(field) for field in fields],
    ]


def main():
    start = int(datetime(2026, 1, 15, 17, 0, tzinfo=timezone.utc).timestamp())
    events = []
    elapsed = 0

    def add(seconds, event_type, x, y, *fields):
        nonlocal elapsed
        elapsed += seconds
        events.append(packed_event(start + elapsed, event_type, x, y, *fields))

    stages = [
        (783, 6, (48.7, 42.8), (47.6, 35.8), 4),
        (7, 257, (48.9, 41.6), (49.8, 36.4), 5),
        (5261, 299, (47.8, 42.2), (45.5, 38.9), 4),
        (33, 299, (42.1, 65.9), (39.6, 60.7), 5),
        (3903, 30, (42.3, 65.7), (34.8, 69.4), 4),
        (3904, 118, (34.7, 84.3), (29.7, 80.4), 5),
        (18, 38, (42.2, 65.8), (45.9, 79.1), 6),
        (6, 327, (42.1, 65.9), (41.7, 78.1), 5),
        (54, 46, (42.2, 65.7), (27.3, 88.2), 5),
    ]

    add(1, 8, 48.7, 42.8)
    for stage_index, (quest_id, npc_id, pickup, objective, count) in enumerate(stages, start=1):
        add(90, 1, *pickup, quest_id)
        for progress in range(1, count + 1):
            offset_x = ((progress % 3) - 1) * 0.8
            offset_y = ((progress % 2) - 0.5) * 0.9
            add(48, 3, objective[0] + offset_x, objective[1] + offset_y, npc_id)
            add(6, 5, objective[0] + offset_x, objective[1] + offset_y, quest_id, 1, progress, count)
        add(20, 6, objective[0], objective[1], quest_id)
        if stage_index in (3, 6, 8):
            add(55, 4, objective[0] + 1.2, objective[1] + 0.7)
        add(150, 2, *pickup, quest_id)
        add(75, 7, *pickup, stage_index + 1)
        if stage_index == 3:
            add(20, 9, *pickup)
            add(7 * 24 * 60 * 60, 8, *pickup)
        elif stage_index == 6:
            add(20, 9, *pickup)
            add(3 * 60 * 60, 8, *pickup)

    add(20, 9, *stages[-1][2])

    profile = {
        "schemaVersion": 2,
        "eventSchemaVersion": 2,
        "app": "QuestiePlus",
        "kind": "CharacterProfile",
        "character": {
            "name": "Daddylow",
            "realm": "Dummy Realm",
            "race": "Human",
            "raceFile": "Human",
            "class": "Warrior",
            "classFile": "WARRIOR",
            "faction": "Alliance",
        },
        "updatedAt": datetime.fromtimestamp(events[-1][0], timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "completedQuestIds": [stage[0] for stage in stages],
        "events": events,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(profile, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT}")
    print(f"Events: {len(events)}")


if __name__ == "__main__":
    main()
