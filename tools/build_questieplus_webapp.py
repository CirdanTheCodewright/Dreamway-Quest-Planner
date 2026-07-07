import csv
import colorsys
import json
import math
import re
from collections import Counter, defaultdict, deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
QUESTIE = ROOT / "Questie" / "Database" / "Classic"
DUSKWOOD_ZONE_ID = 10
ALLIANCE_RACE_MASK = 77


class LuaTableParser:
    def __init__(self, text):
        self.text = text
        self.i = 0

    def parse(self):
        value = self.parse_value()
        self.skip_ws()
        return value

    def skip_ws(self):
        while self.i < len(self.text) and self.text[self.i].isspace():
            self.i += 1

    def parse_value(self):
        self.skip_ws()
        if self.i >= len(self.text):
            raise ValueError("Unexpected end of Lua table")
        char = self.text[self.i]
        if char == "{":
            return self.parse_table()
        if char in ("'", '"'):
            return self.parse_string()
        if char == "-" or char.isdigit():
            return self.parse_number()
        if self.text.startswith("nil", self.i):
            self.i += 3
            return None
        if self.text.startswith("true", self.i):
            self.i += 4
            return True
        if self.text.startswith("false", self.i):
            self.i += 5
            return False
        raise ValueError(f"Unexpected token at {self.i}: {self.text[self.i:self.i + 30]!r}")

    def parse_string(self):
        quote = self.text[self.i]
        self.i += 1
        out = []
        while self.i < len(self.text):
            char = self.text[self.i]
            self.i += 1
            if char == quote:
                return "".join(out)
            if char == "\\" and self.i < len(self.text):
                escaped = self.text[self.i]
                self.i += 1
                out.append({
                    "n": "\n",
                    "r": "\r",
                    "t": "\t",
                    "\\": "\\",
                    "'": "'",
                    '"': '"',
                }.get(escaped, escaped))
            else:
                out.append(char)
        raise ValueError("Unterminated string")

    def parse_number(self):
        start = self.i
        if self.text[self.i] == "-":
            self.i += 1
        while self.i < len(self.text) and self.text[self.i].isdigit():
            self.i += 1
        if self.i < len(self.text) and self.text[self.i] == ".":
            self.i += 1
            while self.i < len(self.text) and self.text[self.i].isdigit():
                self.i += 1
        raw = self.text[start:self.i]
        return float(raw) if "." in raw else int(raw)

    def parse_table(self):
        self.i += 1
        array_values = []
        keyed_values = {}
        has_keyed_values = False

        while True:
            self.skip_ws()
            if self.i >= len(self.text):
                raise ValueError("Unterminated table")
            if self.text[self.i] == "}":
                self.i += 1
                break

            if self.text[self.i] == "[":
                has_keyed_values = True
                self.i += 1
                key = self.parse_value()
                self.skip_ws()
                if self.text[self.i] != "]":
                    raise ValueError("Expected ] in keyed table")
                self.i += 1
                self.skip_ws()
                if self.text[self.i] != "=":
                    raise ValueError("Expected = in keyed table")
                self.i += 1
                keyed_values[key] = self.parse_value()
            else:
                array_values.append(self.parse_value())

            self.skip_ws()
            if self.i < len(self.text) and self.text[self.i] in ",;":
                self.i += 1

        if has_keyed_values:
            for index, value in enumerate(array_values, start=1):
                keyed_values[index] = value
            return keyed_values
        return array_values


def load_lua_data(path):
    text = path.read_text(encoding="utf-8")
    match = re.search(r"\[\[return\s*(\{.*?\})\]\]", text, flags=re.S)
    if not match:
        raise ValueError(f"Could not find Questie data table in {path}")
    return LuaTableParser(match.group(1)).parse()


def flatten_numbers(value):
    if value is None:
        return []
    if isinstance(value, (int, float)):
        return [int(value)]
    if isinstance(value, list):
        result = []
        for item in value:
            result.extend(flatten_numbers(item))
        return result
    if isinstance(value, dict):
        result = []
        for item in value.values():
            result.extend(flatten_numbers(item))
        return result
    return []


def flatten_strings(value):
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        result = []
        for item in value:
            result.extend(flatten_strings(item))
        return result
    if isinstance(value, dict):
        result = []
        for item in value.values():
            result.extend(flatten_strings(item))
        return result
    return []


def table_value(table, index):
    if not isinstance(table, list) or index >= len(table):
        return None
    return table[index]


def zone_points(spawn_table, zone_id=DUSKWOOD_ZONE_ID):
    if not isinstance(spawn_table, dict):
        return []
    points = spawn_table.get(zone_id) or spawn_table.get(str(zone_id))
    if not isinstance(points, list):
        return []
    return [
        {"x": float(point[0]), "y": float(point[1])}
        for point in points
        if isinstance(point, list) and len(point) >= 2 and point[0] is not None and point[1] is not None
    ]


def all_points(spawn_table):
    if not isinstance(spawn_table, dict):
        return []
    points = []
    for zone_id, zone_points_list in spawn_table.items():
        if not isinstance(zone_points_list, list):
            continue
        for point in zone_points_list:
            if isinstance(point, list) and len(point) >= 2 and point[0] is not None and point[1] is not None:
                points.append({"zone": zone_id, "x": float(point[0]), "y": float(point[1])})
    return points


def centroid(points):
    valid = [point for point in points if 0 <= point["x"] <= 100 and 0 <= point["y"] <= 100]
    if not valid:
        return None
    return {
        "x": round(sum(point["x"] for point in valid) / len(valid), 2),
        "y": round(sum(point["y"] for point in valid) / len(valid), 2),
    }


def sample_points(points, limit=140):
    valid = [
        {"x": round(point["x"], 2), "y": round(point["y"], 2), "kind": point.get("kind", "objective")}
        for point in points
        if 0 <= point["x"] <= 100 and 0 <= point["y"] <= 100
    ]
    if len(valid) <= limit:
        return valid
    step = len(valid) / limit
    return [valid[math.floor(i * step)] for i in range(limit)]


def source_refs(ref_table, source_index):
    if not isinstance(ref_table, list) or source_index >= len(ref_table):
        return []
    return flatten_numbers(ref_table[source_index])


def npc_name(npcs, npc_id):
    row = npcs.get(npc_id)
    return row[0] if isinstance(row, list) and row else f"NPC {npc_id}"


def object_name(objects, object_id):
    row = objects.get(object_id)
    return row[0] if isinstance(row, list) and row else f"Object {object_id}"


def item_name(items, item_id):
    row = items.get(item_id)
    return row[0] if isinstance(row, list) and row else f"Item {item_id}"


def source_zone_suffix(points, zones, subzones, limit=2):
    if not zones:
        return ""
    counts = Counter()
    for point in points:
        zone_id = resolve_zone_id(point.get("zoneId"), zones, subzones)
        if zone_id in zones:
            counts[zone_id] += 1
    if not counts:
        return ""

    zone_ids = sorted(counts, key=lambda zone_id: (-counts[zone_id], zones[zone_id]["name"]))
    names = [zones[zone_id]["name"] for zone_id in zone_ids]
    if len(names) <= limit:
        return f" [{', '.join(names)}]"
    return f" [{', '.join(names[:limit])} +{len(names) - limit}]"


def source_label(name, points, zones, subzones):
    return f"{name}{source_zone_suffix(points, zones, subzones)}"


def npc_spawn_points(npcs, npc_id, kind="objective"):
    row = npcs.get(npc_id)
    if not isinstance(row, list):
        return []
    return [dict(point, kind=kind) for point in zone_points(table_value(row, 6))]


def object_spawn_points(objects, object_id, kind="objective"):
    row = objects.get(object_id)
    if not isinstance(row, list):
        return []
    return [dict(point, kind=kind) for point in zone_points(table_value(row, 3))]


def item_source_points(items, npcs, objects, item_id, kind="objective"):
    row = items.get(item_id)
    if not isinstance(row, list):
        return []
    points = []
    for npc_id in flatten_numbers(table_value(row, 1)):
        points.extend(npc_spawn_points(npcs, npc_id, kind))
    for object_id in flatten_numbers(table_value(row, 2)):
        points.extend(object_spawn_points(objects, object_id, kind))
    return points


def describe_start(quest, items, npcs, objects, zones=None, subzones=None):
    starts = table_value(quest, 1)
    parts = []
    for npc_id in source_refs(starts, 0):
        parts.append(source_label(npc_name(npcs, npc_id), npc_all_spawn_points(npcs, npc_id), zones, subzones))
    for object_id in source_refs(starts, 1):
        parts.append(source_label(object_name(objects, object_id), object_all_spawn_points(objects, object_id), zones, subzones))
    for item_id in source_refs(starts, 2):
        parts.append(source_label(f"{item_name(items, item_id)} drop", item_all_source_points(items, npcs, objects, item_id), zones, subzones))
    return parts or ["Unknown starter"]


def describe_end(quest, npcs, objects, zones=None, subzones=None):
    ends = table_value(quest, 2)
    parts = []
    for npc_id in source_refs(ends, 0):
        parts.append(source_label(npc_name(npcs, npc_id), npc_all_spawn_points(npcs, npc_id), zones, subzones))
    for object_id in source_refs(ends, 1):
        parts.append(source_label(object_name(objects, object_id), object_all_spawn_points(objects, object_id), zones, subzones))
    return parts or ["Auto-complete / unknown"]


def start_points_for_quest(quest, items, npcs, objects):
    starts = table_value(quest, 1)
    points = []
    for npc_id in source_refs(starts, 0):
        points.extend(npc_spawn_points(npcs, npc_id, "start"))
    for object_id in source_refs(starts, 1):
        points.extend(object_spawn_points(objects, object_id, "start"))
    for item_id in source_refs(starts, 2):
        points.extend(item_source_points(items, npcs, objects, item_id, "start"))
    return points


def end_points_for_quest(quest, npcs, objects):
    ends = table_value(quest, 2)
    points = []
    for npc_id in source_refs(ends, 0):
        points.extend(npc_spawn_points(npcs, npc_id, "turn-in"))
    for object_id in source_refs(ends, 1):
        points.extend(object_spawn_points(objects, object_id, "turn-in"))
    return points


def objective_summary_and_points(quest, items, npcs, objects):
    objectives = table_value(quest, 9)
    trigger_end = table_value(quest, 8)
    extra_objectives = table_value(quest, 28)
    summary = []
    points = []

    if isinstance(objectives, list):
        creature_ids = objective_ids(objectives, 0)
        if creature_ids:
            summary.append("Kill: " + ", ".join(dict.fromkeys(npc_name(npcs, npc_id) for npc_id in creature_ids)))
            for npc_id in creature_ids:
                points.extend(npc_spawn_points(npcs, npc_id, "mob"))

        object_ids = objective_ids(objectives, 1)
        if object_ids:
            summary.append("Use/find: " + ", ".join(dict.fromkeys(object_name(objects, object_id) for object_id in object_ids)))
            for object_id in object_ids:
                points.extend(object_spawn_points(objects, object_id, "object"))

        item_ids = objective_ids(objectives, 2)
        if item_ids:
            summary.append("Collect: " + ", ".join(dict.fromkeys(item_name(items, item_id) for item_id in item_ids)))
            for item_id in item_ids:
                points.extend(item_source_points(items, npcs, objects, item_id, "item"))

        kill_credit_ids = objective_ids(objectives, 4)
        if kill_credit_ids:
            summary.append("Credit: " + ", ".join(dict.fromkeys(npc_name(npcs, npc_id) for npc_id in kill_credit_ids)))
            for npc_id in kill_credit_ids:
                points.extend(npc_spawn_points(npcs, npc_id, "mob"))

    if isinstance(trigger_end, list) and len(trigger_end) > 1:
        text = trigger_end[0] if isinstance(trigger_end[0], str) else "Trigger area"
        trigger_points = zone_points(trigger_end[1])
        if trigger_points:
            summary.append(text)
            points.extend(dict(point, kind="trigger") for point in trigger_points)

    if isinstance(extra_objectives, list):
        for extra in extra_objectives:
            if not isinstance(extra, list) or not extra:
                continue
            spawnlist = extra[0]
            extra_text = next((part for part in extra if isinstance(part, str)), "Extra objective")
            extra_points = zone_points(spawnlist)
            if extra_points:
                summary.append(extra_text)
                points.extend(dict(point, kind="extra") for point in extra_points)

    objectives_text = table_value(quest, 7)
    if not summary and isinstance(objectives_text, list):
        summary.extend(text for text in objectives_text if isinstance(text, str) and text.strip())

    return summary, sample_points(points)


def objective_ids(objectives, index):
    if not isinstance(objectives, list) or index >= len(objectives):
        return []
    entries = objectives[index]
    if not isinstance(entries, list):
        return []
    ids = []
    for entry in entries:
        if isinstance(entry, list) and entry:
            ids.extend(flatten_numbers(entry[0]))
        elif isinstance(entry, (int, float)):
            ids.append(int(entry))
    return ids


def is_alliance_compatible(quest):
    race_mask = table_value(quest, 5)
    return race_mask in (None, 0) or (isinstance(race_mask, int) and (race_mask & ALLIANCE_RACE_MASK) != 0)


def class_requirement_name(class_mask):
    classes = [
        (1, "Warrior"),
        (2, "Paladin"),
        (4, "Hunter"),
        (8, "Rogue"),
        (16, "Priest"),
        (64, "Shaman"),
        (128, "Mage"),
        (256, "Warlock"),
        (1024, "Druid"),
    ]
    if not class_mask:
        return "Any class"
    return ", ".join(name for bit, name in classes if class_mask & bit) or f"Class mask {class_mask}"


def chain_edges(quests):
    relevant_ids = set(quests)
    directed = defaultdict(set)
    undirected = defaultdict(set)

    def connect(a, b):
        if a in relevant_ids and b in relevant_ids:
            directed[a].add(b)
            undirected[a].add(b)
            undirected[b].add(a)

    for quest_id, quest in quests.items():
        for pre_id in flatten_numbers(table_value(quest, 11)):
            connect(pre_id, quest_id)
        for pre_id in flatten_numbers(table_value(quest, 12)):
            connect(pre_id, quest_id)
        for child_id in flatten_numbers(table_value(quest, 13)):
            connect(quest_id, child_id)
        next_id = table_value(quest, 21)
        if isinstance(next_id, int):
            connect(quest_id, next_id)
        breadcrumb_target = table_value(quest, 26)
        if isinstance(breadcrumb_target, int):
            connect(quest_id, breadcrumb_target)
        for breadcrumb_id in flatten_numbers(table_value(quest, 27)):
            connect(breadcrumb_id, quest_id)

    return directed, undirected


def display_group_edges(quests, ids):
    relevant_ids = set(ids)
    outgoing = defaultdict(set)
    incoming = defaultdict(set)

    def connect(a, b):
        if a in relevant_ids and b in relevant_ids:
            outgoing[a].add(b)
            incoming[b].add(a)

    for quest_id in ids:
        quest = quests[quest_id]
        for pre_id in flatten_numbers(table_value(quest, 11)):
            connect(pre_id, quest_id)
        for pre_id in flatten_numbers(table_value(quest, 12)):
            connect(pre_id, quest_id)
        next_id = table_value(quest, 21)
        if isinstance(next_id, int):
            connect(quest_id, next_id)
        parent_id = table_value(quest, 24)
        if isinstance(parent_id, int):
            connect(parent_id, quest_id)
        breadcrumb_target = table_value(quest, 26)
        if isinstance(breadcrumb_target, int):
            connect(quest_id, breadcrumb_target)
        for breadcrumb_id in flatten_numbers(table_value(quest, 27)):
            connect(breadcrumb_id, quest_id)

    return outgoing, incoming


def topological_display_order(quests, ids, outgoing, incoming, fallback_order):
    indegree = {qid: len(incoming[qid]) for qid in ids}
    queue = deque(sorted(
        [qid for qid in ids if indegree[qid] == 0],
        key=lambda qid: (fallback_order.get(qid, 9999), table_value(quests[qid], 4) or 0, qid),
    ))
    order = []
    while queue:
        current = queue.popleft()
        order.append(current)
        for child in sorted(outgoing[current], key=lambda qid: (fallback_order.get(qid, 9999), table_value(quests[qid], 4) or 0, qid)):
            indegree[child] -= 1
            if indegree[child] == 0:
                queue.append(child)

    if len(order) < len(ids):
        order.extend(qid for qid in sorted(ids, key=lambda qid: (fallback_order.get(qid, 9999), qid)) if qid not in set(order))
    return order


def derive_display_groups(quests, ids, order):
    fallback_order = {qid: index for index, qid in enumerate(order)}
    outgoing, incoming = display_group_edges(quests, ids)
    display_order = topological_display_order(quests, ids, outgoing, incoming, fallback_order)
    assigned = {}
    group_order = []
    group_members = defaultdict(list)

    def new_group(qid):
        group_id = len(group_order)
        group_order.append(group_id)
        assign(qid, group_id)
        return group_id

    def assign(qid, group_id):
        if qid in assigned:
            return
        assigned[qid] = group_id
        group_members[group_id].append(qid)

    def is_parent_bundle(qid, children):
        return len(children) > 1 and all(table_value(quests[child], 24) == qid for child in children)

    for quest_id in display_order:
        if quest_id not in assigned:
            new_group(quest_id)

        group_id = assigned[quest_id]
        children = sorted(outgoing[quest_id], key=lambda qid: (fallback_order.get(qid, 9999), table_value(quests[qid], 4) or 0, qid))
        if not children:
            continue

        if is_parent_bundle(quest_id, children):
            for child in children:
                assign(child, group_id)
        elif len(children) == 1:
            child = children[0]
            if child not in assigned and len(incoming[child]) <= 1:
                assign(child, group_id)
        else:
            for child in children:
                if child not in assigned and len(incoming[child]) <= 1:
                    new_group(child)

    metadata = {}
    display_step = 1
    for group_index, group_id in enumerate(group_order):
        members = sorted(group_members[group_id], key=lambda qid: (display_order.index(qid), fallback_order.get(qid, 9999), qid))
        for group_step, quest_id in enumerate(members, start=1):
            metadata[quest_id] = {
                "chainGroupId": group_index,
                "chainGroupStep": group_step,
                "chainGroupSize": len(members),
                "chainDisplayStep": display_step,
            }
            display_step += 1
    return metadata


def derive_chains(quests):
    directed, undirected = chain_edges(quests)
    seen = set()
    chains = {}
    components = []

    for quest_id in sorted(quests):
        if quest_id in seen:
            continue
        stack = [quest_id]
        component = []
        seen.add(quest_id)
        while stack:
            current = stack.pop()
            component.append(current)
            for neighbor in undirected[current]:
                if neighbor not in seen:
                    seen.add(neighbor)
                    stack.append(neighbor)

        component = sorted(component)
        name_counts = Counter(quests[qid][0] for qid in component)
        chain_name = name_counts.most_common(1)[0][0]
        components.append({"name": chain_name, "ids": component})

    components.sort(key=lambda comp: (min(table_value(quests[qid], 4) or 0 for qid in comp["ids"]), comp["name"], min(comp["ids"])))

    palette = [
        "#f5c542",
        "#6bd6ff",
        "#f2758a",
        "#86df6b",
        "#c89cff",
        "#ff9d45",
        "#63dec6",
        "#ff73d7",
        "#b8d957",
        "#8da2ff",
        "#e1a66a",
        "#79c47b",
        "#d66f6f",
        "#7ed4b7",
        "#e6df72",
        "#b892ff",
    ]

    chain_meta = []
    for chain_index, component in enumerate(components):
        ids = component["ids"]
        indegree = {qid: 0 for qid in ids}
        for qid in ids:
            for child in directed[qid]:
                if child in indegree:
                    indegree[child] += 1

        queue = deque(sorted([qid for qid in ids if indegree[qid] == 0], key=lambda qid: (table_value(quests[qid], 4) or 0, qid)))
        order = []
        while queue:
            current = queue.popleft()
            order.append(current)
            for child in sorted(directed[current], key=lambda qid: (table_value(quests[qid], 4) or 0, qid)):
                indegree[child] -= 1
                if indegree[child] == 0:
                    queue.append(child)

        if len(order) < len(ids):
            order.extend(qid for qid in ids if qid not in set(order))

        display_groups = derive_display_groups(quests, ids, order)

        color = palette[chain_index % len(palette)]
        for step, quest_id in enumerate(order, start=1):
            display_group = display_groups.get(quest_id, {
                "chainGroupId": 0,
                "chainGroupStep": step,
                "chainGroupSize": len(ids),
                "chainDisplayStep": step,
            })
            chains[quest_id] = {
                "chainId": chain_index,
                "chainName": component["name"],
                "chainColor": color,
                "chainStep": display_group["chainDisplayStep"],
                "chainLength": len(ids),
                **display_group,
            }
        chain_meta.append({
            "id": chain_index,
            "name": component["name"],
            "color": color,
            "count": len(ids),
        })

    return chains, chain_meta


def dedupe_points(points):
    seen = set()
    deduped = []
    for point in points:
        key = (round(point["x"], 2), round(point["y"], 2), point.get("kind", "objective"))
        if key not in seen:
            seen.add(key)
            deduped.append(point)
    return deduped


def build_records():
    quests = load_lua_data(QUESTIE / "classicQuestDB.lua")
    npcs = load_lua_data(QUESTIE / "classicNpcDB.lua")
    objects = load_lua_data(QUESTIE / "classicObjectDB.lua")
    items = load_lua_data(QUESTIE / "classicItemDB.lua")

    start_cache = {}
    end_cache = {}
    objective_cache = {}
    candidates = {}

    for quest_id, quest in quests.items():
        if not isinstance(quest, list) or not is_alliance_compatible(quest):
            continue

        start_points = start_points_for_quest(quest, items, npcs, objects)
        end_points = end_points_for_quest(quest, npcs, objects)
        objective_summary, objective_points = objective_summary_and_points(quest, items, npcs, objects)

        start_cache[quest_id] = start_points
        end_cache[quest_id] = end_points
        objective_cache[quest_id] = (objective_summary, objective_points)

        zone_or_sort = table_value(quest, 16)
        has_duskwood_start = bool(start_points)
        has_duskwood_turnin = bool(end_points)
        if zone_or_sort == DUSKWOOD_ZONE_ID or has_duskwood_start or has_duskwood_turnin:
            candidates[quest_id] = quest

    chains, chain_meta = derive_chains(candidates)
    records = []

    for quest_id in sorted(candidates, key=lambda qid: (table_value(candidates[qid], 4) or 0, qid)):
        quest = candidates[quest_id]
        start_points = start_cache[quest_id]
        end_points = end_cache[quest_id]
        objective_summary, objective_points = objective_cache[quest_id]

        start_position = centroid(start_points)
        location_note = "Questie starter coordinates in Duskwood"
        if start_position is None:
            start_position = centroid(end_points)
            location_note = "Acquired outside Duskwood; plotted at Duskwood turn-in"
        if start_position is None:
            start_position = centroid(objective_points)
            location_note = "Acquired outside Duskwood; plotted at objective area"
        if start_position is None:
            start_position = {"x": 50.0, "y": 50.0}
            location_note = "No Duskwood coordinate found; plotted at map center"

        pre_group = flatten_numbers(table_value(quest, 11))
        pre_single = flatten_numbers(table_value(quest, 12))
        next_id = table_value(quest, 21)
        objectives_text = table_value(quest, 7)
        text_lines = [line for line in objectives_text if isinstance(line, str) and line.strip()] if isinstance(objectives_text, list) else []
        chain = chains[quest_id]

        records.append({
            "id": quest_id,
            "name": table_value(quest, 0),
            "requiredLevel": table_value(quest, 3),
            "questLevel": table_value(quest, 4),
            "classRequirement": class_requirement_name(table_value(quest, 6)),
            "zoneOrSort": table_value(quest, 16),
            "start": start_position,
            "startPoints": dedupe_points(sample_points(start_points, 60)),
            "endPoints": dedupe_points(sample_points(end_points, 60)),
            "locationNote": location_note,
            "startSources": describe_start(quest, items, npcs, objects),
            "endSources": describe_end(quest, npcs, objects),
            "objectiveText": text_lines,
            "objectiveSummary": objective_summary,
            "objectivePoints": dedupe_points(objective_points),
            "preQuestGroup": pre_group,
            "preQuestSingle": pre_single,
            "nextQuestInChain": next_id if isinstance(next_id, int) else None,
            **chain,
        })

    plotted_chain_ids = {record["chainId"] for record in records}
    chain_meta = [chain for chain in chain_meta if chain["id"] in plotted_chain_ids]
    return records, chain_meta


def render_html(records, chains):
    payload = json.dumps({"quests": records, "chains": chains}, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    quest_count = len(records)
    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Duskwood Quest Progression</title>
  <style>
    :root {{
      color-scheme: dark;
      --bg: #11130f;
      --panel: #1b1e18;
      --panel-2: #24271f;
      --ink: #f7eed8;
      --muted: #c9baa0;
      --line: rgba(255, 235, 196, 0.2);
      --questie-gold: #ffd34f;
      font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
    }}

    * {{
      box-sizing: border-box;
    }}

    body {{
      margin: 0;
      min-height: 100vh;
      background:
        radial-gradient(circle at 20% 0%, rgba(89, 118, 74, 0.26), transparent 34rem),
        linear-gradient(180deg, #151712 0%, #0d0e0b 100%);
      color: var(--ink);
    }}

    main {{
      width: min(1200px, calc(100vw - 32px));
      margin: 0 auto;
      padding: 24px 0 40px;
    }}

    header {{
      display: flex;
      align-items: end;
      justify-content: space-between;
      gap: 16px;
      margin-bottom: 14px;
    }}

    h1 {{
      margin: 0;
      font-size: clamp(1.6rem, 2.6vw, 2.35rem);
      line-height: 1;
      letter-spacing: 0;
    }}

    .count {{
      color: var(--muted);
      font-size: 0.92rem;
      white-space: nowrap;
    }}

    .map-frame {{
      position: relative;
      width: 100%;
      border: 1px solid rgba(255, 225, 170, 0.26);
      border-radius: 8px;
      overflow: hidden;
      background: #0d100d;
      box-shadow: 0 22px 60px rgba(0, 0, 0, 0.45);
    }}

    .map {{
      position: relative;
      width: 100%;
      aspect-ratio: 488 / 300;
      overflow: hidden;
      background: #131711;
    }}

    .map > img {{
      position: absolute;
      inset: 0;
      width: 100%;
      height: 100%;
      object-fit: fill;
      filter: saturate(0.92) contrast(1.06) brightness(0.84);
      user-select: none;
      pointer-events: none;
    }}

    .veil {{
      position: absolute;
      inset: 0;
      background: linear-gradient(180deg, rgba(0,0,0,0.06), rgba(0,0,0,0.16));
      pointer-events: none;
    }}

    #highlight-layer,
    #quest-layer {{
      position: absolute;
      inset: 0;
    }}

    #highlight-layer {{
      pointer-events: none;
    }}

    .objective-dot {{
      position: absolute;
      width: 10px;
      height: 10px;
      border-radius: 999px;
      translate: -50% -50%;
      background: var(--chain-color);
      border: 1px solid rgba(255, 255, 255, 0.8);
      box-shadow: 0 0 14px var(--chain-color), 0 0 3px #000;
      opacity: 0.95;
    }}

    .objective-area {{
      position: absolute;
      border-radius: 999px;
      translate: -50% -50%;
      border: 2px solid var(--chain-color);
      background: color-mix(in srgb, var(--chain-color) 20%, transparent);
      box-shadow: 0 0 32px color-mix(in srgb, var(--chain-color) 68%, transparent);
    }}

    .quest-stack {{
      position: absolute;
      translate: -50% -50%;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 3px;
      padding: 3px;
      border-radius: 999px;
      background: rgba(13, 12, 9, 0.48);
      box-shadow: 0 8px 20px rgba(0, 0, 0, 0.38);
      z-index: 5;
    }}

    .quest-marker {{
      --size: 28px;
      position: relative;
      display: grid;
      place-items: center;
      width: var(--size);
      height: var(--size);
      border: 2px solid var(--chain-color);
      border-radius: 999px;
      padding: 0;
      background:
        linear-gradient(rgba(0, 0, 0, 0.12), rgba(0, 0, 0, 0.32)),
        url("Questie/Icons/available.png") center / 92% 92% no-repeat,
        #211909;
      color: #1a1205;
      cursor: pointer;
      box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.72), 0 0 16px color-mix(in srgb, var(--chain-color) 58%, transparent);
    }}

    .quest-marker::after {{
      content: "";
      position: absolute;
      inset: 3px;
      border-radius: inherit;
      background: rgba(255, 229, 121, 0.54);
      mix-blend-mode: screen;
    }}

    .quest-marker span {{
      position: relative;
      z-index: 1;
      display: grid;
      place-items: center;
      min-width: 17px;
      height: 17px;
      border-radius: 999px;
      background: rgba(255, 245, 208, 0.92);
      color: #1f1606;
      font-size: 0.72rem;
      line-height: 1;
      font-weight: 800;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.45);
    }}

    .quest-marker:hover,
    .quest-marker:focus-visible,
    .quest-marker.active {{
      outline: 2px solid #fff6cf;
      outline-offset: 2px;
      z-index: 20;
    }}

    .quest-marker.offmap {{
      border-style: dashed;
      filter: saturate(0.78);
    }}

    .quest-stack.dense {{
      gap: 2px;
      padding: 2px;
    }}

    .quest-stack.dense .quest-marker {{
      --size: 22px;
      border-width: 1px;
    }}

    .quest-stack.dense .quest-marker span {{
      min-width: 14px;
      height: 14px;
      font-size: 0.58rem;
    }}

    .quest-stack.very-dense {{
      gap: 1px;
      padding: 2px;
    }}

    .quest-stack.very-dense .quest-marker {{
      --size: 18px;
      border-width: 1px;
    }}

    .quest-stack.very-dense .quest-marker span {{
      min-width: 12px;
      height: 12px;
      font-size: 0.5rem;
    }}

    .legend {{
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      padding: 12px;
      border-top: 1px solid rgba(255, 235, 196, 0.18);
      background: rgba(12, 13, 10, 0.72);
    }}

    .legend-chip {{
      display: inline-flex;
      align-items: center;
      gap: 7px;
      min-height: 28px;
      padding: 4px 9px;
      border-radius: 999px;
      border: 1px solid rgba(255, 255, 255, 0.14);
      background: rgba(255, 255, 255, 0.055);
      color: var(--muted);
      font-size: 0.78rem;
    }}

    .legend-swatch {{
      width: 10px;
      height: 10px;
      border-radius: 999px;
      background: var(--chain-color);
      box-shadow: 0 0 12px var(--chain-color);
      flex: 0 0 auto;
    }}

    .details {{
      display: grid;
      grid-template-columns: minmax(0, 1.1fr) minmax(280px, 0.9fr);
      gap: 16px;
      margin-top: 16px;
      padding: 16px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: linear-gradient(180deg, rgba(36, 39, 31, 0.94), rgba(22, 24, 19, 0.96));
      box-shadow: 0 18px 48px rgba(0, 0, 0, 0.26);
    }}

    .details h2 {{
      margin: 0 0 8px;
      font-size: clamp(1.25rem, 2vw, 1.7rem);
      line-height: 1.1;
      letter-spacing: 0;
    }}

    .meta-grid {{
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
      margin-top: 12px;
    }}

    .meta {{
      min-height: 58px;
      padding: 9px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.055);
      border: 1px solid rgba(255, 255, 255, 0.08);
    }}

    .label {{
      display: block;
      margin-bottom: 3px;
      color: #a99b83;
      font-size: 0.72rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }}

    .value {{
      color: #fff3d4;
      font-size: 0.94rem;
      line-height: 1.28;
    }}

    .body-copy {{
      color: var(--muted);
      line-height: 1.5;
      margin: 10px 0 0;
    }}

    .objective-list {{
      display: grid;
      gap: 7px;
      margin: 0;
      padding: 0;
      list-style: none;
    }}

    .objective-list li {{
      padding: 8px 9px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.055);
      color: #eadfc9;
      line-height: 1.35;
    }}

    .chain-pill {{
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 5px 9px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.06);
      color: #fff1c9;
      border: 1px solid color-mix(in srgb, var(--chain-color) 54%, rgba(255,255,255,0.16));
    }}

    .chain-pill::before {{
      content: "";
      width: 10px;
      height: 10px;
      border-radius: 999px;
      background: var(--chain-color);
      box-shadow: 0 0 12px var(--chain-color);
    }}

    @media (max-width: 760px) {{
      main {{
        width: min(100vw - 18px, 1200px);
        padding-top: 12px;
      }}

      header {{
        display: block;
      }}

      .count {{
        margin-top: 6px;
      }}

      .quest-marker {{
        --size: 24px;
      }}

      .quest-marker span {{
        min-width: 15px;
        height: 15px;
        font-size: 0.65rem;
      }}

      .details {{
        grid-template-columns: 1fr;
      }}

      .meta-grid {{
        grid-template-columns: 1fr;
      }}
    }}
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Duskwood Quest Progression</h1>
      <div class="count">{quest_count} Classic Alliance quests from Questie data</div>
    </header>
    <section class="map-frame" aria-label="Duskwood quest map">
      <div class="map" id="map">
        <img src="assets/duskwood-map.jpg" alt="Duskwood zone map">
        <div class="veil"></div>
        <div id="highlight-layer"></div>
        <div id="quest-layer"></div>
      </div>
      <div class="legend" id="legend"></div>
    </section>
    <section class="details" id="details"></section>
  </main>
  <script>
    const DATA = {payload};
    const QUEST_TYPE_FILTERS = DATA.questTypeFilters;
    const DISPLAY_FILTERS = [
      {{ id: "available-pickups", label: "Available quest pickups", defaultEnabled: true }},
      {{ id: "quest-objectives", label: "All quest objectives", defaultEnabled: false }},
      {{ id: "quest-handins", label: "All quest hand-ins", defaultEnabled: false }},
    ];
    const RACES = [
      {{ label: "All races", mask: null, color: "#fff0ce" }},
      {{ label: "Human", mask: 1, faction: "Alliance", color: "#5aa9ff" }},
      {{ label: "Dwarf", mask: 4, faction: "Alliance", color: "#5aa9ff" }},
      {{ label: "Night Elf", mask: 8, faction: "Alliance", color: "#5aa9ff" }},
      {{ label: "Gnome", mask: 64, faction: "Alliance", color: "#5aa9ff" }},
      {{ label: "Orc", mask: 2, faction: "Horde", color: "#ff6b5f" }},
      {{ label: "Undead", mask: 16, faction: "Horde", color: "#ff6b5f" }},
      {{ label: "Tauren", mask: 32, faction: "Horde", color: "#ff6b5f" }},
      {{ label: "Troll", mask: 128, faction: "Horde", color: "#ff6b5f" }},
    ];
    const CLASSES = [
      {{ label: "All classes", mask: null, color: "#fff0ce" }},
      {{ label: "Warrior", mask: 1, color: "#C79C6E" }},
      {{ label: "Paladin", mask: 2, color: "#F58CBA" }},
      {{ label: "Hunter", mask: 4, color: "#ABD473" }},
      {{ label: "Rogue", mask: 8, color: "#FFF569" }},
      {{ label: "Priest", mask: 16, color: "#FFFFFF" }},
      {{ label: "Shaman", mask: 64, color: "#0070DE" }},
      {{ label: "Mage", mask: 128, color: "#69CCF0" }},
      {{ label: "Warlock", mask: 256, color: "#9482C9" }},
      {{ label: "Druid", mask: 1024, color: "#FF7D0A" }},
    ];
    const filters = {{
      raceMask: null,
      classMask: null,
      level: null,
      search: "",
      typeIds: new Set(QUEST_TYPE_FILTERS.filter((filter) => filter.defaultEnabled).map((filter) => filter.id)),
      zoneIds: new Set(DATA.zones.filter((zone) => zone.questCount > 0).map((zone) => zone.id)),
    }};
    const displayFilters = new Set(DISPLAY_FILTERS.filter((filter) => filter.defaultEnabled).map((filter) => filter.id));
    const displayFilters = new Set(DISPLAY_FILTERS.filter((filter) => filter.defaultEnabled).map((filter) => filter.id));
    const questsById = new Map(DATA.quests.map((quest) => [quest.id, quest]));
    const questLayer = document.querySelector("#quest-layer");
    const highlightLayer = document.querySelector("#highlight-layer");
    const details = document.querySelector("#details");
    const legend = document.querySelector("#legend");
    let activeId = null;

    function groupQuests(quests) {{
      const groups = new Map();
      quests.forEach((quest) => {{
        const gx = Math.round(quest.start.x / 3.7);
        const gy = Math.round(quest.start.y / 3.7);
        const key = `${{gx}}:${{gy}}`;
        if (!groups.has(key)) {{
          groups.set(key, {{ x: 0, y: 0, quests: [] }});
        }}
        const group = groups.get(key);
        group.x += quest.start.x;
        group.y += quest.start.y;
        group.quests.push(quest);
      }});
      return [...groups.values()].map((group) => {{
        group.x = group.x / group.quests.length;
        group.y = group.y / group.quests.length;
        group.quests.sort((a, b) => a.chainId - b.chainId || a.chainStep - b.chainStep || a.id - b.id);
        return group;
      }});
    }}

    function renderMarkers() {{
      const groups = groupQuests(DATA.quests);
      const fragment = document.createDocumentFragment();
      groups.forEach((group) => {{
        const stack = document.createElement("div");
        stack.className = "quest-stack";
        if (group.quests.length > 28) stack.classList.add("very-dense");
        else if (group.quests.length > 14) stack.classList.add("dense");
        stack.style.left = `${{group.x}}%`;
        stack.style.top = `${{group.y}}%`;
        group.quests.forEach((quest) => {{
          const marker = document.createElement("button");
          marker.type = "button";
          marker.className = "quest-marker";
          if (!quest.locationNote.startsWith("Questie starter")) marker.classList.add("offmap");
          marker.dataset.questId = quest.id;
          marker.style.setProperty("--chain-color", quest.chainColor);
          marker.title = `${{quest.name}} (#${{quest.id}})`;
          marker.innerHTML = `<span>${{quest.chainStep}}</span>`;
          marker.addEventListener("click", () => activateQuest(quest.id));
          stack.append(marker);
        }});
        fragment.append(stack);
      }});
      questLayer.append(fragment);
    }}

    function renderLegend() {{
      legend.innerHTML = DATA.chains.map((chain) => `
        <span class="legend-chip" style="--chain-color:${{chain.color}}">
          <span class="legend-swatch"></span>
          <span>${{escapeHtml(chain.name)}} - ${{chain.count}}</span>
        </span>
      `).join("");
    }}

    function activateQuest(id) {{
      activeId = id;
      document.querySelectorAll(".quest-marker").forEach((marker) => {{
        marker.classList.toggle("active", Number(marker.dataset.questId) === id);
      }});
      const quest = questsById.get(id);
      renderHighlights(quest);
      renderDetails(quest);
    }}

    function renderHighlights(quest) {{
      highlightLayer.innerHTML = "";
      highlightLayer.style.setProperty("--chain-color", quest.chainColor);
      const points = quest.objectivePoints || [];
      if (points.length) {{
        const bounds = points.reduce((box, point) => {{
          box.minX = Math.min(box.minX, point.x);
          box.maxX = Math.max(box.maxX, point.x);
          box.minY = Math.min(box.minY, point.y);
          box.maxY = Math.max(box.maxY, point.y);
          return box;
        }}, {{ minX: 100, maxX: 0, minY: 100, maxY: 0 }});
        const pad = points.length === 1 ? 4 : 2.8;
        const area = document.createElement("div");
        area.className = "objective-area";
        area.style.left = `${{(bounds.minX + bounds.maxX) / 2}}%`;
        area.style.top = `${{(bounds.minY + bounds.maxY) / 2}}%`;
        area.style.width = `${{Math.max(6, bounds.maxX - bounds.minX + pad * 2)}}%`;
        area.style.height = `${{Math.max(8, bounds.maxY - bounds.minY + pad * 2)}}%`;
        highlightLayer.append(area);
      }}
      points.forEach((point) => {{
        const dot = document.createElement("div");
        dot.className = "objective-dot";
        dot.style.left = `${{point.x}}%`;
        dot.style.top = `${{point.y}}%`;
        highlightLayer.append(dot);
      }});
    }}

    function questLinkList(ids) {{
      if (!ids || !ids.length) return "None";
      return ids.map((id) => {{
        const quest = questsById.get(id);
        return quest ? `${{escapeHtml(quest.name)}} (#${{id}})` : `#${{id}}`;
      }}).join(", ");
    }}

    function renderDetails(quest) {{
      const uniqueObjectives = questObjectiveLines(quest);
      details.style.setProperty("--chain-color", quest.chainColor);
      details.innerHTML = `
        <div>
          <h2>${{escapeHtml(quest.name)}} <span style="color:#a99b83">#${{quest.id}}</span></h2>
          <span class="chain-pill">${{escapeHtml(quest.chainName)}} - ${{quest.chainStep}}/${{quest.chainLength}}</span>
          <p class="body-copy">${{escapeHtml(quest.locationNote)}}</p>
          <div class="meta-grid">
            <div class="meta"><span class="label">Levels</span><span class="value">Requires ${{quest.requiredLevel ?? "?"}} - Quest ${{quest.questLevel ?? "?"}}</span></div>
            <div class="meta"><span class="label">Class</span><span class="value">${{escapeHtml(quest.classRequirement)}}</span></div>
            <div class="meta"><span class="label">Starts</span><span class="value">${{escapeHtml(quest.startSources.join(", "))}}</span></div>
            <div class="meta"><span class="label">Ends</span><span class="value">${{escapeHtml(quest.endSources.join(", "))}}</span></div>
            <div class="meta"><span class="label">Prerequisites</span><span class="value">All: ${{questLinkList(quest.preQuestGroup)}}<br>Any: ${{questLinkList(quest.preQuestSingle)}}</span></div>
            <div class="meta"><span class="label">Next</span><span class="value">${{quest.nextQuestInChain ? questLinkList([quest.nextQuestInChain]) : "None"}}</span></div>
          </div>
        </div>
        <div>
          <span class="label">Objectives</span>
          <ul class="objective-list">
            ${{uniqueObjectives.length ? uniqueObjectives.map((item) => `<li>${{escapeHtml(item)}}</li>`).join("") : "<li>No explicit objective text in Questie.</li>"}}
          </ul>
        </div>
      `;
    }}

    function updateFiltersFromControls() {{
      forcedCatalogueChainId = null;
      filters.raceMask = raceFilter.value === "all" ? null : Number(raceFilter.value);
      filters.classMask = classFilter.value === "all" ? null : Number(classFilter.value);
      filters.level = levelFilter.value === "all" ? null : Number(levelFilter.value);
      updateFilterSelectColors();
      renderCurrentView();
    }}

    function updateSearchClearButton() {{
      if (!questSearchClear) return;
      questSearchClear.hidden = !questSearch.value;
    }}

    function updateSearchFilterFromInput() {{
      forcedCatalogueChainId = null;
      filters.search = questSearch.value.trim().toLowerCase();
      updateSearchClearButton();
      renderCurrentView();
    }}

    function escapeHtml(value) {{
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
    }}

    renderMarkers();
    renderLegend();
    activateQuest(DATA.quests[0].id);
  </script>
</body>
</html>
"""
    return html


def render_inventory_html(records, chains):
    payload = json.dumps({"quests": records, "chains": chains}, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    quest_count = len(records)
    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Duskwood Quest Progression</title>
  <style>
    :root {{
      color-scheme: dark;
      --bg: #10120e;
      --panel: #1b1e18;
      --panel-2: #252921;
      --ink: #f7eed8;
      --muted: #c9baa0;
      --line: rgba(255, 235, 196, 0.2);
      --questie-gold: #ffd34f;
      font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
    }}

    * {{
      box-sizing: border-box;
    }}

    body {{
      margin: 0;
      min-height: 100vh;
      background:
        radial-gradient(circle at 12% 0%, rgba(93, 116, 70, 0.28), transparent 34rem),
        linear-gradient(180deg, #151712 0%, #0b0d0a 100%);
      color: var(--ink);
    }}

    main {{
      width: min(1500px, calc(100vw - 32px));
      margin: 0 auto;
      padding: 24px 0 40px;
    }}

    header {{
      display: flex;
      align-items: end;
      justify-content: space-between;
      gap: 16px;
      margin-bottom: 14px;
    }}

    h1 {{
      margin: 0;
      font-size: clamp(1.6rem, 2.45vw, 2.35rem);
      line-height: 1;
      letter-spacing: 0;
    }}

    .count {{
      color: var(--muted);
      font-size: 0.92rem;
      white-space: nowrap;
    }}

    .workbench {{
      display: grid;
      grid-template-columns: minmax(0, 1.55fr) minmax(360px, 0.85fr);
      gap: 16px;
      align-items: start;
    }}

    .map-frame,
    .inventory,
    .details {{
      border: 1px solid var(--line);
      border-radius: 8px;
      background: linear-gradient(180deg, rgba(36, 39, 31, 0.94), rgba(20, 22, 18, 0.97));
      box-shadow: 0 18px 48px rgba(0, 0, 0, 0.28);
    }}

    .map-frame {{
      overflow: hidden;
    }}

    .map {{
      position: relative;
      width: 100%;
      aspect-ratio: 488 / 300;
      overflow: hidden;
      background: #11150f;
    }}

    .map > img {{
      position: absolute;
      inset: 0;
      width: 100%;
      height: 100%;
      object-fit: fill;
      filter: saturate(0.92) contrast(1.06) brightness(0.84);
      user-select: none;
      pointer-events: none;
    }}

    .veil {{
      position: absolute;
      inset: 0;
      background: linear-gradient(180deg, rgba(0, 0, 0, 0.05), rgba(0, 0, 0, 0.18));
      pointer-events: none;
    }}

    #highlight-layer {{
      position: absolute;
      inset: 0;
      pointer-events: none;
    }}

    .objective-area {{
      position: absolute;
      border-radius: 999px;
      translate: -50% -50%;
      border: 2px solid var(--chain-color);
      background: color-mix(in srgb, var(--chain-color) 20%, transparent);
      box-shadow: 0 0 32px color-mix(in srgb, var(--chain-color) 68%, transparent);
    }}

    .objective-dot {{
      position: absolute;
      width: 10px;
      height: 10px;
      border-radius: 999px;
      translate: -50% -50%;
      background: var(--chain-color);
      border: 1px solid rgba(255, 255, 255, 0.8);
      box-shadow: 0 0 14px var(--chain-color), 0 0 3px #000;
      opacity: 0.95;
    }}

    .quest-pin {{
      position: absolute;
      z-index: 5;
      display: grid;
      place-items: center;
      width: 30px;
      height: 30px;
      border-radius: 999px;
      translate: -50% -50%;
      font-size: 1.02rem;
      font-weight: 900;
      line-height: 1;
      border: 2px solid rgba(255, 255, 255, 0.86);
      box-shadow: 0 4px 10px rgba(0, 0, 0, 0.62), 0 0 18px rgba(255, 224, 109, 0.48);
      text-shadow: 0 1px 0 rgba(255, 255, 255, 0.34);
    }}

    .quest-pin.pickup {{
      margin-left: -12px;
      background: #ffd34f;
      color: #241703;
    }}

    .quest-pin.turnin {{
      margin-left: 12px;
      background: #f3f8ff;
      color: #122034;
    }}

    .pickup-dot {{
      position: absolute;
      width: 10px;
      height: 10px;
      border-radius: 999px;
      translate: -50% -50%;
      background: #ffd34f;
      border: 1px solid rgba(38, 24, 6, 0.72);
      box-shadow: 0 1px 4px rgba(0, 0, 0, 0.62), 0 0 8px rgba(255, 211, 79, 0.44);
      pointer-events: none;
    }}

    .inventory {{
      max-height: min(72vh, 820px);
      overflow: hidden;
      display: grid;
      grid-template-rows: auto minmax(0, 1fr);
    }}

    .inventory-head {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      padding: 12px 14px;
      border-bottom: 1px solid rgba(255, 235, 196, 0.14);
      background: rgba(12, 13, 10, 0.52);
    }}

    .inventory-title {{
      font-size: 0.95rem;
      font-weight: 800;
      color: #fff2cf;
    }}

    .inventory-subtitle {{
      color: #a99b83;
      font-size: 0.78rem;
      white-space: nowrap;
    }}

    .chain-list {{
      overflow: auto;
      padding: 8px;
    }}

    .chain-row {{
      --row-color: var(--chain-color);
      display: grid;
      gap: 8px;
      margin-bottom: 8px;
      padding: 9px;
      border-left: 3px solid var(--chain-color);
      border-radius: 7px;
      background: rgba(255, 255, 255, 0.052);
      box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.055);
    }}

    .chain-row.active {{
      background: color-mix(in srgb, var(--chain-color) 13%, rgba(255, 255, 255, 0.055));
      box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--chain-color) 42%, transparent);
    }}

    .chain-meta {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      min-width: 0;
    }}

    .chain-name {{
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      color: #fff2cf;
      font-weight: 750;
      font-size: 0.88rem;
    }}

    .chain-level {{
      flex: 0 0 auto;
      padding: 3px 7px;
      border-radius: 999px;
      background: rgba(0, 0, 0, 0.25);
      color: #d9cbb2;
      border: 1px solid rgba(255, 255, 255, 0.11);
      font-size: 0.72rem;
    }}

    .chain-track {{
      display: flex;
      align-items: center;
      gap: 8px;
      min-height: 36px;
      overflow-x: auto;
      overflow-y: hidden;
      padding: 3px 1px 5px;
      scrollbar-color: rgba(255, 255, 255, 0.22) transparent;
      scrollbar-width: thin;
    }}

    .quest-icon {{
      --size: 30px;
      position: relative;
      display: grid;
      place-items: center;
      flex: 0 0 auto;
      width: var(--size);
      height: var(--size);
      border: 2px solid var(--chain-color);
      border-radius: 999px;
      padding: 0;
      background:
        linear-gradient(rgba(0, 0, 0, 0.12), rgba(0, 0, 0, 0.32)),
        url("Questie/Icons/available.png") center / 92% 92% no-repeat,
        #211909;
      color: #1a1205;
      cursor: pointer;
      box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.72), 0 0 16px color-mix(in srgb, var(--chain-color) 48%, transparent);
    }}

    .quest-icon::after {{
      content: "";
      position: absolute;
      inset: 3px;
      border-radius: inherit;
      background: rgba(255, 229, 121, 0.54);
      mix-blend-mode: screen;
    }}

    .quest-icon span {{
      position: relative;
      z-index: 1;
      display: grid;
      place-items: center;
      min-width: 17px;
      height: 17px;
      border-radius: 999px;
      background: rgba(255, 245, 208, 0.92);
      color: #1f1606;
      font-size: 0.72rem;
      line-height: 1;
      font-weight: 850;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.45);
    }}

    .quest-icon:hover,
    .quest-icon:focus-visible,
    .quest-icon.active {{
      outline: 2px solid #fff6cf;
      outline-offset: 2px;
      z-index: 20;
    }}

    .quest-icon.offmap {{
      border-style: dashed;
      filter: saturate(0.78);
    }}

    .details {{
      display: grid;
      grid-template-columns: minmax(0, 1.1fr) minmax(280px, 0.9fr);
      gap: 16px;
      margin-top: 16px;
      padding: 16px;
    }}

    .details h2 {{
      margin: 0 0 8px;
      font-size: clamp(1.25rem, 2vw, 1.7rem);
      line-height: 1.1;
      letter-spacing: 0;
    }}

    .meta-grid {{
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
      margin-top: 12px;
    }}

    .meta {{
      min-height: 58px;
      padding: 9px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.055);
      border: 1px solid rgba(255, 255, 255, 0.08);
    }}

    .label {{
      display: block;
      margin-bottom: 3px;
      color: #a99b83;
      font-size: 0.72rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }}

    .value {{
      color: #fff3d4;
      font-size: 0.94rem;
      line-height: 1.28;
    }}

    .body-copy {{
      color: var(--muted);
      line-height: 1.5;
      margin: 10px 0 0;
    }}

    .objective-list {{
      display: grid;
      gap: 7px;
      margin: 0;
      padding: 0;
      list-style: none;
    }}

    .objective-list li {{
      padding: 8px 9px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.055);
      color: #eadfc9;
      line-height: 1.35;
    }}

    .chain-pill {{
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 5px 9px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.06);
      color: #fff1c9;
      border: 1px solid color-mix(in srgb, var(--chain-color) 54%, rgba(255, 255, 255, 0.16));
    }}

    .chain-pill::before {{
      content: "";
      width: 10px;
      height: 10px;
      border-radius: 999px;
      background: var(--chain-color);
      box-shadow: 0 0 12px var(--chain-color);
    }}

    @media (max-width: 980px) {{
      main {{
        width: min(100vw - 18px, 1500px);
        padding-top: 12px;
      }}

      header {{
        display: block;
      }}

      .count {{
        margin-top: 6px;
      }}

      .workbench {{
        grid-template-columns: 1fr;
      }}

      .inventory {{
        max-height: 52vh;
      }}
    }}

    @media (max-width: 720px) {{
      .details {{
        grid-template-columns: 1fr;
      }}

      .meta-grid {{
        grid-template-columns: 1fr;
      }}
    }}
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Duskwood Quest Progression</h1>
      <div class="count">{quest_count} Classic Alliance quests from Questie data</div>
    </header>
    <section class="workbench">
      <section class="map-frame" aria-label="Duskwood quest map">
        <div class="map" id="map">
          <img src="assets/duskwood-map.jpg" alt="Duskwood zone map">
          <div class="veil"></div>
          <div id="highlight-layer"></div>
        </div>
      </section>
      <aside class="inventory" aria-label="Quest chain inventory">
        <div class="inventory-head">
          <div class="inventory-title">Quest Chains</div>
          <div class="inventory-subtitle" id="chain-count"></div>
        </div>
        <div class="chain-list" id="chain-list"></div>
      </aside>
    </section>
    <section class="details" id="details"></section>
  </main>
  <script>
    const DATA = {payload};
    const questsById = new Map(DATA.quests.map((quest) => [quest.id, quest]));
    const highlightLayer = document.querySelector("#highlight-layer");
    const details = document.querySelector("#details");
    const chainList = document.querySelector("#chain-list");
    const chainCount = document.querySelector("#chain-count");
    let activeId = null;

    function chainGroups() {{
      const byId = new Map(DATA.chains.map((chain) => [chain.id, {{ ...chain, quests: [] }}]));
      DATA.quests.forEach((quest) => {{
        if (!byId.has(quest.chainId)) {{
          byId.set(quest.chainId, {{
            id: quest.chainId,
            name: quest.chainName,
            color: quest.chainColor,
            count: 0,
            quests: [],
          }});
        }}
        byId.get(quest.chainId).quests.push(quest);
      }});
      return [...byId.values()]
        .filter((chain) => chain.quests.length)
        .map((chain) => {{
          chain.quests.sort((a, b) => a.chainStep - b.chainStep || a.requiredLevel - b.requiredLevel || a.id - b.id);
          chain.firstQuest = chain.quests[0];
          chain.startLevel = chain.firstQuest.requiredLevel ?? 0;
          return chain;
        }})
        .sort((a, b) => a.startLevel - b.startLevel || a.firstQuest.questLevel - b.firstQuest.questLevel || a.name.localeCompare(b.name));
    }}

    function renderInventory() {{
      const groups = chainGroups();
      chainCount.textContent = `${{groups.length}} rows`;
      const fragment = document.createDocumentFragment();
      groups.forEach((chain) => {{
        const row = document.createElement("section");
        row.className = "chain-row";
        row.dataset.chainId = chain.id;
        row.style.setProperty("--chain-color", chain.color);

        const meta = document.createElement("div");
        meta.className = "chain-meta";
        meta.innerHTML = `
          <div class="chain-name" title="${{escapeHtml(chain.name)}}">${{escapeHtml(chain.name)}}</div>
          <div class="chain-level">Req ${{chain.startLevel}}</div>
        `;

        const track = document.createElement("div");
        track.className = "chain-track";
        chain.quests.forEach((quest) => {{
          track.append(createQuestIcon(quest));
        }});

        row.append(meta, track);
        fragment.append(row);
      }});
      chainList.append(fragment);
    }}

    function createQuestIcon(quest) {{
      const icon = document.createElement("button");
      icon.type = "button";
      icon.className = "quest-icon";
      if (!quest.locationNote.startsWith("Questie starter")) icon.classList.add("offmap");
      icon.dataset.questId = quest.id;
      icon.dataset.chainId = quest.chainId;
      icon.style.setProperty("--chain-color", quest.chainColor);
      const difficulty = questDifficultyId(quest);
      icon.dataset.difficulty = difficulty || "none";
      if (difficulty) icon.style.setProperty("--quest-icon-ring", QUEST_DIFFICULTY_COLORS[difficulty]);
      icon.title = `${{quest.name}} (#${{quest.id}}) - requires ${{quest.requiredLevel}}, quest level ${{quest.questLevel}}`;
      icon.innerHTML = `<span>${{quest.chainStep}}</span>${{questTypeBadgesHtml(quest)}}`;
      icon.addEventListener("click", () => activateQuest(quest.id));
      return icon;
    }}

    function activateQuest(id) {{
      activeId = id;
      const quest = questsById.get(id);
      document.querySelectorAll(".quest-icon").forEach((icon) => {{
        icon.classList.toggle("active", Number(icon.dataset.questId) === id);
      }});
      document.querySelectorAll(".chain-row").forEach((row) => {{
        row.classList.toggle("active", Number(row.dataset.chainId) === quest.chainId);
      }});
      renderMapOverlay(quest);
      renderDetails(quest);
    }}

    function renderMapOverlay(quest) {{
      highlightLayer.innerHTML = "";
      highlightLayer.style.setProperty("--chain-color", quest.chainColor);
      renderObjectiveLayer(quest);
      renderPins(quest.startPoints || [], "pickup", "!", "Quest pickup");
      renderPins(quest.endPoints || [], "turnin", "?", "Quest turn-in");
    }}

    function renderObjectiveLayer(quest) {{
      const points = quest.objectivePoints || [];
      if (points.length) {{
        const bounds = points.reduce((box, point) => {{
          box.minX = Math.min(box.minX, point.x);
          box.maxX = Math.max(box.maxX, point.x);
          box.minY = Math.min(box.minY, point.y);
          box.maxY = Math.max(box.maxY, point.y);
          return box;
        }}, {{ minX: 100, maxX: 0, minY: 100, maxY: 0 }});
        const pad = points.length === 1 ? 4 : 2.8;
        const area = document.createElement("div");
        area.className = "objective-area";
        area.style.left = `${{(bounds.minX + bounds.maxX) / 2}}%`;
        area.style.top = `${{(bounds.minY + bounds.maxY) / 2}}%`;
        area.style.width = `${{Math.max(6, bounds.maxX - bounds.minX + pad * 2)}}%`;
        area.style.height = `${{Math.max(8, bounds.maxY - bounds.minY + pad * 2)}}%`;
        highlightLayer.append(area);
      }}
      points.forEach((point) => {{
        const dot = document.createElement("div");
        dot.className = "objective-dot";
        dot.style.left = `${{point.x}}%`;
        dot.style.top = `${{point.y}}%`;
        highlightLayer.append(dot);
      }});
    }}

    function renderPins(points, type, glyph, label) {{
      points.forEach((point, index) => {{
        const pin = document.createElement("div");
        pin.className = `quest-pin ${{type}}`;
        pin.style.left = `${{point.x}}%`;
        pin.style.top = `${{point.y}}%`;
        pin.textContent = glyph;
        pin.setAttribute("aria-label", `${{label}} ${{index + 1}}`);
        highlightLayer.append(pin);
      }});
    }}

    function questLinkList(ids) {{
      if (!ids || !ids.length) return "None";
      return ids.map((id) => {{
        const quest = questsById.get(id);
        return quest ? `${{escapeHtml(quest.name)}} (#${{id}})` : `#${{id}}`;
      }}).join(", ");
    }}

    function renderDetails(quest) {{
      const objectives = [
        ...(quest.objectiveSummary || []),
        ...(quest.objectiveText || []),
      ];
      const uniqueObjectives = [...new Set(objectives)].filter(Boolean);
      const startCount = (quest.startPoints || []).length;
      const endCount = (quest.endPoints || []).length;
      details.style.setProperty("--chain-color", quest.chainColor);
      details.innerHTML = `
        <div>
          <h2>${{escapeHtml(quest.name)}} <span style="color:#a99b83">#${{quest.id}}</span></h2>
          <span class="chain-pill">${{escapeHtml(quest.chainName)}} - ${{quest.chainStep}}/${{quest.chainLength}}</span>
          <p class="body-copy">${{escapeHtml(quest.locationNote)}}</p>
          <div class="meta-grid">
            <div class="meta"><span class="label">Levels</span><span class="value">Requires ${{quest.requiredLevel ?? "?"}} - Quest ${{quest.questLevel ?? "?"}}</span></div>
            <div class="meta"><span class="label">Class</span><span class="value">${{escapeHtml(quest.classRequirement)}}</span></div>
            <div class="meta"><span class="label">Starts</span><span class="value">${{escapeHtml(quest.startSources.join(", "))}}<br>${{startCount}} Duskwood map point${{startCount === 1 ? "" : "s"}}</span></div>
            <div class="meta"><span class="label">Ends</span><span class="value">${{escapeHtml(quest.endSources.join(", "))}}<br>${{endCount}} Duskwood map point${{endCount === 1 ? "" : "s"}}</span></div>
            <div class="meta"><span class="label">Prerequisites</span><span class="value">All: ${{questLinkList(quest.preQuestGroup)}}<br>Any: ${{questLinkList(quest.preQuestSingle)}}</span></div>
            <div class="meta"><span class="label">Next</span><span class="value">${{quest.nextQuestInChain ? questLinkList([quest.nextQuestInChain]) : "None"}}</span></div>
          </div>
        </div>
        <div>
          <span class="label">Objectives</span>
          <ul class="objective-list">
            ${{uniqueObjectives.length ? uniqueObjectives.map((item) => `<li>${{escapeHtml(item)}}</li>`).join("") : "<li>No explicit objective text in Questie.</li>"}}
          </ul>
        </div>
      `;
    }}

    function escapeHtml(value) {{
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
    }}

    renderInventory();
    const firstRealDuskwoodQuest = DATA.quests.find((quest) => quest.zoneOrSort === 10 && quest.requiredLevel >= 17) || DATA.quests[0];
    activateQuest(firstRealDuskwoodQuest.id);
  </script>
</body>
</html>
"""
    return html


CSV_DIR = ROOT / "Questie" / "ExternalScripts(DONOTINCLUDEINRELEASE)" / "DBC - WoW.tools"
WORLDMAPAREA_CLASSIC = CSV_DIR / "worldmaparea_classic.csv"
UIMAP_CLASSIC = CSV_DIR / "uimap_classic.csv"
QUESTSORT_CLASSIC = CSV_DIR / "questsort_classic.csv"
AREA_ID_TO_UI_MAP = ROOT / "Questie" / "Database" / "Zones" / "data" / "areaIdToUiMapId.lua"
SUBZONE_TO_PARENT = ROOT / "Questie" / "Database" / "Zones" / "data" / "subZoneToParentZone.lua"
QUEST_TAG_INFO_CORRECTIONS = ROOT / "Questie" / "Database" / "Corrections" / "questTagInfoCorrections.lua"
HOLIDAY_QUEST_DIR = ROOT / "Questie" / "Database" / "Corrections" / "Holidays" / "quests"
QUEST_BLACKLIST = ROOT / "Questie" / "Database" / "Corrections" / "QuestieQuestBlacklist.lua"
CLASSIC_QUEST_FIXES = ROOT / "Questie" / "Database" / "Corrections" / "classicQuestFixes.lua"
MAP_ASSET_DIR = ROOT / "assets" / "classic-maps" / "zones"
LEGACY_MAP_ASSET_DIR = ROOT / "assets" / "maps"
CONTINENT_MAP_ASSET_DIR = ROOT / "assets" / "classic-maps" / "continents"
CONTINENT_IMAGE_WIDTH = 1002
CONTINENT_IMAGE_HEIGHT = 668
CONTINENT_IMAGE_CROPS = {
    0: (280, 0, 690, 668),
    1: (290, 0, 700, 668),
}
WORLD_MAP_ASPECT = 3 / 2
WORLD_CONTINENT_PANEL_ASPECT = (CONTINENT_IMAGE_CROPS[0][2] - CONTINENT_IMAGE_CROPS[0][0]) / CONTINENT_IMAGE_HEIGHT
WORLD_CONTINENT_PANEL_WIDTH_PCT = WORLD_CONTINENT_PANEL_ASPECT / WORLD_MAP_ASPECT * 100
ZONE_HIT_GRID_WIDTH = 164
ZONE_HIT_GRID_HEIGHT = 267
ZONE_HIT_GRID_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
HORDE_RACE_MASK = 178
QUEST_FLAGS_RAID = 64
QUEST_FLAGS_DAILY = 4096
QUEST_FLAGS_WEEKLY = 32768
QUEST_FLAGS_MONTHLY = 65536
SPECIAL_FLAGS_REPEATABLE = 1
SPECIAL_FLAGS_MONTHLY = 4

QUEST_TYPE_FILTERS = [
    {"id": "general", "label": "General progression", "defaultEnabled": True},
    {"id": "elite", "label": "Elite / group", "defaultEnabled": True},
    {"id": "dungeon", "label": "Dungeon", "defaultEnabled": True},
    {"id": "class", "label": "Class quests", "defaultEnabled": True},
    {"id": "escort", "label": "Escort", "defaultEnabled": True},
    {"id": "breadcrumb", "label": "Breadcrumbs", "defaultEnabled": True},
    {"id": "city-donation", "label": "City cloth donations", "defaultEnabled": False},
    {"id": "profession", "label": "Profession quests", "defaultEnabled": False},
    {"id": "reputation", "label": "Reputation gates", "defaultEnabled": False},
    {"id": "repeatable", "label": "Repeatable / daily", "defaultEnabled": False},
    {"id": "seasonal", "label": "Holidays / seasonal", "defaultEnabled": False},
    {"id": "war-effort", "label": "AQ War Effort", "defaultEnabled": False},
    {"id": "invasion", "label": "Scourge Invasion", "defaultEnabled": False},
    {"id": "pvp", "label": "PvP", "defaultEnabled": False},
    {"id": "raid", "label": "Raid", "defaultEnabled": False},
    {"id": "special", "label": "Special / other", "defaultEnabled": False},
]
QUEST_TYPE_LABELS = {entry["id"]: entry["label"] for entry in QUEST_TYPE_FILTERS}
QUEST_TYPE_ORDER = {entry["id"]: index for index, entry in enumerate(QUEST_TYPE_FILTERS)}
QUEST_TAG_TO_TYPE = {
    1: "elite",
    21: "class",
    41: "pvp",
    62: "raid",
    81: "dungeon",
    82: "seasonal",
    83: "special",
    84: "escort",
    85: "dungeon",
    88: "raid",
    89: "raid",
    98: "special",
    102: "special",
    294: "special",
}
CLASS_SORT_NAMES = {"Warlock", "Warrior", "Shaman", "Paladin", "Mage", "Rogue", "Hunter", "Priest", "Druid"}
PROFESSION_SORT_NAMES = {
    "Herbalism",
    "Fishing",
    "Blacksmithing",
    "Alchemy",
    "Leatherworking",
    "Engineering",
    "Tailoring",
    "Cooking",
    "First Aid",
}
SEASONAL_SORT_NAMES = {"Seasonal", "Darkmoon Faire", "Lunar Festival", "Midsummer"}
SPECIAL_EVENT_SORT_NAMES = {"Ahn'Qiraj War": "war-effort", "Invasion": "invasion"}
SPECIAL_SORT_NAMES = {"Epic", "Treasure Map", "Special", "Legendary"}
REPUTATION_SORT_NAMES = {"Reputation"}
CITY_DONATION_QUEST_PATTERN = re.compile(r"^(A Donation of|Additional Runecloth\b)", re.I)
ESCORT_TEXT_PATTERN = re.compile(r"\bescort(?:ed|ing)?\b", re.I)
ZONE_RANGE_EXCLUDED_TYPES = {
    "city-donation",
    "profession",
    "reputation",
    "repeatable",
    "seasonal",
    "war-effort",
    "invasion",
    "pvp",
    "raid",
    "special",
}
CLASSIC_ZONE_LEVEL_RANGES = {
    1: (1, 10),       # Dun Morogh
    3: (35, 45),      # Badlands
    4: (45, 55),      # Blasted Lands
    8: (35, 45),      # Swamp of Sorrows
    10: (18, 30),     # Duskwood
    11: (20, 30),     # Wetlands
    12: (1, 10),      # Elwynn Forest
    14: (1, 10),      # Durotar
    15: (35, 45),     # Dustwallow Marsh
    16: (45, 55),     # Azshara
    17: (10, 25),     # The Barrens
    28: (50, 60),     # Western Plaguelands
    33: (30, 45),     # Stranglethorn Vale
    36: (30, 40),     # Alterac Mountains
    38: (10, 20),     # Loch Modan
    40: (10, 20),     # Westfall
    41: (55, 60),     # Deadwind Pass
    44: (15, 25),     # Redridge Mountains
    45: (30, 40),     # Arathi Highlands
    46: (50, 58),     # Burning Steppes
    47: (40, 50),     # The Hinterlands
    51: (45, 50),     # Searing Gorge
    85: (1, 10),      # Tirisfal Glades
    130: (10, 20),    # Silverpine Forest
    139: (53, 60),    # Eastern Plaguelands
    141: (1, 10),     # Teldrassil
    148: (10, 20),    # Darkshore
    215: (1, 10),     # Mulgore
    267: (20, 30),    # Hillsbrad Foothills
    331: (18, 30),    # Ashenvale
    357: (40, 50),    # Feralas
    361: (48, 55),    # Felwood
    400: (25, 35),    # Thousand Needles
    405: (30, 40),    # Desolace
    406: (15, 27),    # Stonetalon Mountains
    440: (40, 50),    # Tanaris
    490: (48, 55),    # Un'Goro Crater
    618: (55, 60),    # Winterspring
    1377: (55, 60),   # Silithus
    1497: (1, 60),    # Undercity
    1519: (1, 60),    # Stormwind City
    1537: (1, 60),    # Ironforge
    1637: (1, 60),    # Orgrimmar
    1638: (1, 60),    # Thunder Bluff
    1657: (1, 60),    # Darnassus
}


def load_lua_return_table_merge(path):
    text = path.read_text(encoding="utf-8")
    matches = re.findall(r"\[\[return\s*(\{.*?\})\]\]", text, flags=re.S)
    merged = {}
    for match in matches:
        stripped = re.sub(r"--.*", "", match)
        parsed = LuaTableParser(stripped).parse()
        if isinstance(parsed, dict):
            merged.update({int(k): int(v) for k, v in parsed.items()})
    return merged


def load_uimap_names():
    names = {}
    with UIMAP_CLASSIC.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            try:
                names[int(row["ID"])] = row["Name_lang"]
            except (TypeError, ValueError):
                continue
    return names


def load_quest_sort_names():
    names = {}
    with QUESTSORT_CLASSIC.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            try:
                names[-int(row["ID"])] = row["SortName_lang"]
            except (TypeError, ValueError):
                continue
    return names


def quest_tag_expression_applies_to_era(expression):
    if "Questie.IsSoD" in expression:
        return False
    if "Expansions.Current ~= Expansions.Era" in expression:
        return False
    if re.search(r"Expansions\.Current\s*>=\s*Expansions\.(Tbc|Wotlk|Cata|MoP)", expression):
        return False
    if re.search(r"Expansions\.Current\s*>\s*Expansions\.Era", expression):
        return False
    if re.search(r"Expansions\.Current\s*==\s*Expansions\.(Tbc|Wotlk|Cata|MoP)", expression):
        return False
    return True


def load_quest_tag_corrections():
    corrections = {}
    for raw_line in QUEST_TAG_INFO_CORRECTIONS.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("--", 1)[0].strip()
        match = re.match(r"\[(\d+)\]\s*=\s*(.+)", line)
        if not match:
            continue
        quest_id = int(match.group(1))
        expression = match.group(2)
        if not quest_tag_expression_applies_to_era(expression):
            continue
        tag = re.search(r"\{(\d+)\s*,\s*l10n\(\"([^\"]+)\"\)\}", expression)
        if tag:
            corrections[quest_id] = {"id": int(tag.group(1)), "name": tag.group(2)}
    return corrections


def load_holiday_event_quests():
    events = {}
    for path in HOLIDAY_QUEST_DIR.glob("*.lua"):
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if line.startswith("--"):
                continue
            match = re.search(r'tinsert\(eventQuests,\s*\{\s*"([^"]+)"\s*,\s*(\d+)', line)
            if match:
                events[int(match.group(2))] = match.group(1)
    return events


def load_quest_id_table(table_name):
    text = QUEST_BLACKLIST.read_text(encoding="utf-8")
    match = re.search(rf"QuestieQuestBlacklist\.{re.escape(table_name)}\s*=\s*\{{(.*?)\n\}}", text, flags=re.S)
    if not match:
        return set()
    return {int(quest_id) for quest_id in re.findall(r"\[(\d+)\]\s*=\s*true", match.group(1))}


def load_classic_quest_fix_category_ids():
    breadcrumb_ids = set()
    escort_ids = set()
    current_quest_id = None
    for raw_line in CLASSIC_QUEST_FIXES.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("--", 1)[0]
        quest_match = re.match(r"^        \[(\d+)\]\s*=\s*\{", line)
        if quest_match:
            current_quest_id = int(quest_match.group(1))
            continue
        if current_quest_id is None:
            continue
        if re.match(r"^        \},?", line):
            current_quest_id = None
            continue

        if "[questKeys.breadcrumbForQuestId]" in line:
            breadcrumb_ids.add(current_quest_id)
        if "[questKeys.breadcrumbs]" in line:
            breadcrumb_ids.update(int(quest_id) for quest_id in re.findall(r"\d+", line))
        if "[questKeys.triggerEnd]" in line and ESCORT_TEXT_PATTERN.search(line):
            escort_ids.add(current_quest_id)
        if "[questKeys.extraObjectives]" in line and ESCORT_TEXT_PATTERN.search(line):
            escort_ids.add(current_quest_id)

    return breadcrumb_ids, escort_ids


def derive_breadcrumb_ids(quests, fixed_breadcrumb_ids):
    breadcrumb_ids = set()
    for quest_id, quest in quests.items():
        breadcrumb_target = table_value(quest, 26)
        if isinstance(breadcrumb_target, int) and breadcrumb_target:
            breadcrumb_ids.add(quest_id)
        breadcrumb_ids.update(
            breadcrumb_id
            for breadcrumb_id in flatten_numbers(table_value(quest, 27))
            if breadcrumb_id
        )

    breadcrumb_ids.update(fixed_breadcrumb_ids)
    return breadcrumb_ids


def is_escort_quest(quest, tag, correction_escort_ids, quest_id):
    if tag and tag.get("id") == 84:
        return True
    if quest_id in correction_escort_ids:
        return True

    text_fragments = [
        str(table_value(quest, 0) or ""),
        *flatten_strings(table_value(quest, 7)),
        *flatten_strings(table_value(quest, 8)),
        *flatten_strings(table_value(quest, 9)),
        *flatten_strings(table_value(quest, 28)),
    ]
    return any(ESCORT_TEXT_PATTERN.search(fragment) for fragment in text_fragments)


def add_type_from_sort(type_ids, zone_or_sort, quest_sort_names):
    sort_name = quest_sort_names.get(zone_or_sort)
    if not sort_name:
        return None
    if sort_name in CLASS_SORT_NAMES:
        type_ids.add("class")
    elif sort_name in PROFESSION_SORT_NAMES:
        type_ids.add("profession")
    elif sort_name in SEASONAL_SORT_NAMES:
        type_ids.add("seasonal")
    elif sort_name in SPECIAL_EVENT_SORT_NAMES:
        type_ids.add(SPECIAL_EVENT_SORT_NAMES[sort_name])
    elif sort_name in REPUTATION_SORT_NAMES:
        type_ids.add("reputation")
    elif sort_name in SPECIAL_SORT_NAMES:
        type_ids.add("special")
    return sort_name


def derive_quest_type_ids(quest_id, quest, quest_sort_names, quest_tag_corrections, holiday_events, aq_war_effort, invasion_quests, breadcrumb_ids, escort_ids):
    type_ids = set()
    quest_name = str(table_value(quest, 0) or "")
    tag = quest_tag_corrections.get(quest_id)
    if tag:
        mapped_type = QUEST_TAG_TO_TYPE.get(tag["id"])
        if mapped_type:
            type_ids.add(mapped_type)

    zone_or_sort = table_value(quest, 16)
    quest_sort_name = add_type_from_sort(type_ids, zone_or_sort, quest_sort_names) if isinstance(zone_or_sort, int) and zone_or_sort < 0 else None

    if table_value(quest, 6):
        type_ids.add("class")
    if table_value(quest, 17) or table_value(quest, 30) or table_value(quest, 34):
        type_ids.add("profession")
    if table_value(quest, 18) or table_value(quest, 19):
        type_ids.add("reputation")
    if CITY_DONATION_QUEST_PATTERN.search(quest_name):
        type_ids.add("city-donation")
    if quest_id in breadcrumb_ids:
        type_ids.add("breadcrumb")
    if is_escort_quest(quest, tag, escort_ids, quest_id):
        type_ids.add("escort")

    quest_flags = table_value(quest, 22) or 0
    special_flags = table_value(quest, 23) or 0
    if quest_flags & QUEST_FLAGS_RAID:
        type_ids.add("raid")
    if quest_flags & (QUEST_FLAGS_DAILY | QUEST_FLAGS_WEEKLY | QUEST_FLAGS_MONTHLY):
        type_ids.add("repeatable")
    if special_flags & (SPECIAL_FLAGS_REPEATABLE | SPECIAL_FLAGS_MONTHLY):
        type_ids.add("repeatable")

    if quest_id in holiday_events:
        type_ids.add("seasonal")
    if quest_id in aq_war_effort:
        type_ids.add("war-effort")
    if quest_id in invasion_quests:
        type_ids.add("invasion")

    if not type_ids:
        type_ids.add("general")

    ordered_type_ids = sorted(type_ids, key=lambda type_id: QUEST_TYPE_ORDER.get(type_id, 999))
    return {
        "typeIds": ordered_type_ids,
        "typeLabels": [QUEST_TYPE_LABELS[type_id] for type_id in ordered_type_ids],
        "questTagId": tag["id"] if tag else None,
        "questTagName": tag["name"] if tag else None,
        "questSortName": quest_sort_name,
        "eventName": holiday_events.get(quest_id),
    }


def load_world_area_data():
    ui_names = load_uimap_names()
    area_to_ui = load_lua_return_table_merge(AREA_ID_TO_UI_MAP)
    zones = {}
    continents = {}

    with WORLDMAPAREA_CLASSIC.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            area_id = int(row["AreaID"])
            map_id = int(row["MapID"])
            data = {
                "areaName": row["AreaName"],
                "left": float(row["LocLeft"]),
                "right": float(row["LocRight"]),
                "top": float(row["LocTop"]),
                "bottom": float(row["LocBottom"]),
                "mapId": map_id,
                "areaId": area_id,
            }
            if area_id == 0 and map_id in (0, 1):
                continents[map_id] = data
                continue
            if area_id <= 0 or map_id not in (0, 1):
                continue

            ui_id = area_to_ui.get(area_id)
            display_name = ui_names.get(ui_id) or re.sub(r"(?<!^)([A-Z])", r" \1", row["AreaName"]).strip()
            asset_path = MAP_ASSET_DIR / f"{area_id}.jpg"
            if not asset_path.exists():
                asset_path = LEGACY_MAP_ASSET_DIR / f"{area_id}.jpg"
            if not asset_path.exists() and area_id == DUSKWOOD_ZONE_ID:
                asset_path = ROOT / "assets" / "duskwood-map.jpg"

            zones[area_id] = {
                **data,
                "id": area_id,
                "uiMapId": ui_id,
                "name": display_name,
                "continentId": map_id,
                "image": to_web_path(asset_path),
            }

    panel_width = WORLD_CONTINENT_PANEL_WIDTH_PCT
    outer_margin = 4.0
    middle_gap = 100 - panel_width * 2 - outer_margin * 2
    layout = {
        1: {
            "id": 1,
            "name": "Kalimdor",
            "x": outer_margin,
            "y": 0.0,
            "width": panel_width,
            "height": 100.0,
            "objectPosition": "50% 50%",
        },
        0: {
            "id": 0,
            "name": "Eastern Kingdoms",
            "x": outer_margin + panel_width + middle_gap,
            "y": 0.0,
            "width": panel_width,
            "height": 100.0,
            "objectPosition": "50% 50%",
        },
    }
    for continent_id, continent in continents.items():
        continent.update(layout[continent_id])
        continent["leftPct"] = layout[continent_id]["x"]
        continent["topPct"] = layout[continent_id]["y"]
        continent["widthPct"] = layout[continent_id]["width"]
        continent["heightPct"] = layout[continent_id]["height"]
        crop = CONTINENT_IMAGE_CROPS.get(continent_id, (0, 0, CONTINENT_IMAGE_WIDTH, CONTINENT_IMAGE_HEIGHT))
        continent["cropLeftPct"] = crop[0] / CONTINENT_IMAGE_WIDTH * 100
        continent["cropTopPct"] = crop[1] / CONTINENT_IMAGE_HEIGHT * 100
        continent["cropWidthPct"] = (crop[2] - crop[0]) / CONTINENT_IMAGE_WIDTH * 100
        continent["cropHeightPct"] = (crop[3] - crop[1]) / CONTINENT_IMAGE_HEIGHT * 100

    for zone in zones.values():
        continent = continents.get(zone["continentId"])
        if continent:
            zone["worldRect"] = zone_rect_in_continent(zone, continent)
    for continent_id, continent in continents.items():
        continent["zoneHitGrid"] = build_continent_zone_hit_grid(continent_id, zones.values())
    return zones, continents


def crop_continent_bounds_to_zones(zones, continents):
    for continent_id, continent in continents.items():
        continent_zones = [zone for zone in zones.values() if zone["continentId"] == continent_id]
        if not continent_zones:
            continue
        min_x = min(min(zone["left"], zone["right"]) for zone in continent_zones)
        max_x = max(max(zone["left"], zone["right"]) for zone in continent_zones)
        min_y = min(min(zone["top"], zone["bottom"]) for zone in continent_zones)
        max_y = max(max(zone["top"], zone["bottom"]) for zone in continent_zones)
        x_pad = (max_x - min_x) * 0.045
        y_pad = (max_y - min_y) * 0.045
        continent["left"] = max_x + x_pad
        continent["right"] = min_x - x_pad
        continent["top"] = max_y + y_pad
        continent["bottom"] = min_y - y_pad


def to_web_path(path):
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def percent_between(value, start, end):
    if start == end:
        return 0
    return (value - start) / (end - start) * 100


def probable_world_land_pixel(r, g, b):
    hue, saturation, value = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    hue *= 360
    yellowness = ((r + g) / 2) - b
    return (
        20 <= hue <= 110
        and saturation >= 0.35
        and value >= 0.22
        and yellowness >= 35
    )


def smooth_land_cells(cells, width, height):
    smoothed = [row[:] for row in cells]
    for y in range(height):
        for x in range(width):
            land_neighbors = 0
            total_neighbors = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx = x + dx
                    ny = y + dy
                    if 0 <= nx < width and 0 <= ny < height:
                        total_neighbors += 1
                        if cells[ny][nx]:
                            land_neighbors += 1
            if cells[y][x] or land_neighbors >= max(4, math.ceil(total_neighbors * 0.55)):
                smoothed[y][x] = True
    return smoothed


def zone_rect_contains(rect, x, y, padding=0):
    return (
        rect["left"] - padding <= x <= rect["left"] + rect["width"] + padding
        and rect["top"] - padding <= y <= rect["top"] + rect["height"] + padding
    )


def zone_rect_center(rect):
    return rect["left"] + rect["width"] / 2, rect["top"] + rect["height"] / 2


def choose_zone_for_world_cell(x, y, continent_zones):
    candidates = []
    for index, zone in enumerate(continent_zones, start=1):
        rect = zone.get("worldRect")
        if not rect or not zone_rect_contains(rect, x, y, 1.0):
            continue
        center_x, center_y = zone_rect_center(rect)
        width = max(rect["width"], 4)
        height = max(rect["height"], 4)
        strict_penalty = 0 if zone_rect_contains(rect, x, y) else 2.5
        score = strict_penalty + ((x - center_x) / width) ** 2 + ((y - center_y) / height) ** 2
        candidates.append((score, index))
    if not candidates:
        return 0
    return min(candidates, key=lambda item: item[0])[1]


def build_continent_zone_hit_grid(continent_id, zones):
    continent_zones = [
        zone
        for zone in sorted(zones, key=lambda item: (item["name"], item["id"]))
        if zone["continentId"] == continent_id and zone.get("worldRect") and zone.get("image")
    ]
    if not continent_zones or len(continent_zones) >= len(ZONE_HIT_GRID_ALPHABET):
        return None

    image_path = CONTINENT_MAP_ASSET_DIR / f"{continent_id}.jpg"
    if not image_path.exists():
        return None

    image = Image.open(image_path).convert("RGB").resize(
        (ZONE_HIT_GRID_WIDTH, ZONE_HIT_GRID_HEIGHT),
        Image.Resampling.BILINEAR,
    )
    land_cells = []
    for y in range(ZONE_HIT_GRID_HEIGHT):
        row = []
        for x in range(ZONE_HIT_GRID_WIDTH):
            row.append(probable_world_land_pixel(*image.getpixel((x, y))))
        land_cells.append(row)
    land_cells = smooth_land_cells(land_cells, ZONE_HIT_GRID_WIDTH, ZONE_HIT_GRID_HEIGHT)

    rows = []
    for y in range(ZONE_HIT_GRID_HEIGHT):
        encoded = []
        local_y = (y + 0.5) / ZONE_HIT_GRID_HEIGHT * 100
        for x in range(ZONE_HIT_GRID_WIDTH):
            if not land_cells[y][x]:
                encoded.append(ZONE_HIT_GRID_ALPHABET[0])
                continue
            local_x = (x + 0.5) / ZONE_HIT_GRID_WIDTH * 100
            encoded.append(ZONE_HIT_GRID_ALPHABET[choose_zone_for_world_cell(local_x, local_y, continent_zones)])
        rows.append("".join(encoded))

    return {
        "width": ZONE_HIT_GRID_WIDTH,
        "height": ZONE_HIT_GRID_HEIGHT,
        "alphabet": ZONE_HIT_GRID_ALPHABET,
        "zones": [0, *[zone["id"] for zone in continent_zones]],
        "rows": rows,
    }


def zone_rect_in_continent(zone, continent):
    x1 = percent_between(zone["left"], continent["left"], continent["right"])
    x2 = percent_between(zone["right"], continent["left"], continent["right"])
    y1 = percent_between(zone["top"], continent["top"], continent["bottom"])
    y2 = percent_between(zone["bottom"], continent["top"], continent["bottom"])
    x1 = percent_between(x1, continent.get("cropLeftPct", 0), continent.get("cropLeftPct", 0) + continent.get("cropWidthPct", 100))
    x2 = percent_between(x2, continent.get("cropLeftPct", 0), continent.get("cropLeftPct", 0) + continent.get("cropWidthPct", 100))
    y1 = percent_between(y1, continent.get("cropTopPct", 0), continent.get("cropTopPct", 0) + continent.get("cropHeightPct", 100))
    y2 = percent_between(y2, continent.get("cropTopPct", 0), continent.get("cropTopPct", 0) + continent.get("cropHeightPct", 100))
    return {
        "left": round(min(x1, x2), 4),
        "top": round(min(y1, y2), 4),
        "width": round(abs(x2 - x1), 4),
        "height": round(abs(y2 - y1), 4),
    }


def resolve_zone_id(zone_id, zones, subzones):
    if zone_id in zones:
        return zone_id
    seen = set()
    current = zone_id
    while current in subzones and current not in seen:
        seen.add(current)
        current = subzones[current]
        if current in zones:
            return current
    return zone_id


def all_spawn_points_from_table(spawn_table, kind):
    if not isinstance(spawn_table, dict):
        return []
    points = []
    for zone_id, zone_points_list in spawn_table.items():
        if not isinstance(zone_points_list, list):
            continue
        try:
            numeric_zone_id = int(zone_id)
        except (TypeError, ValueError):
            continue
        for point in zone_points_list:
            if isinstance(point, list) and len(point) >= 2 and point[0] is not None and point[1] is not None:
                if 0 <= float(point[0]) <= 100 and 0 <= float(point[1]) <= 100:
                    points.append({
                        "rawZoneId": numeric_zone_id,
                        "zoneId": numeric_zone_id,
                        "x": round(float(point[0]), 2),
                        "y": round(float(point[1]), 2),
                        "kind": kind,
                    })
    return points


def npc_all_spawn_points(npcs, npc_id, kind="objective"):
    row = npcs.get(npc_id)
    if not isinstance(row, list):
        return []
    return all_spawn_points_from_table(table_value(row, 6), kind)


def object_all_spawn_points(objects, object_id, kind="objective"):
    row = objects.get(object_id)
    if not isinstance(row, list):
        return []
    return all_spawn_points_from_table(table_value(row, 3), kind)


def item_all_source_points(items, npcs, objects, item_id, kind="objective"):
    row = items.get(item_id)
    if not isinstance(row, list):
        return []
    points = []
    for npc_id in flatten_numbers(table_value(row, 1)):
        points.extend(npc_all_spawn_points(npcs, npc_id, kind))
    for object_id in flatten_numbers(table_value(row, 2)):
        points.extend(object_all_spawn_points(objects, object_id, kind))
    return points


def source_points(points, source_name, source_type):
    return [
        {
            **point,
            "sourceName": source_name,
            "sourceType": source_type,
        }
        for point in points
    ]


def start_points_for_quest_all(quest, items, npcs, objects):
    starts = table_value(quest, 1)
    points = []
    for npc_id in source_refs(starts, 0):
        points.extend(source_points(npc_all_spawn_points(npcs, npc_id, "start"), npc_name(npcs, npc_id), "npc"))
    for object_id in source_refs(starts, 1):
        points.extend(source_points(object_all_spawn_points(objects, object_id, "start"), object_name(objects, object_id), "object"))
    for item_id in source_refs(starts, 2):
        points.extend(source_points(item_all_source_points(items, npcs, objects, item_id, "start"), f"{item_name(items, item_id)} drop", "item"))
    return points


def end_points_for_quest_all(quest, npcs, objects):
    ends = table_value(quest, 2)
    points = []
    for npc_id in source_refs(ends, 0):
        points.extend(source_points(npc_all_spawn_points(npcs, npc_id, "turn-in"), npc_name(npcs, npc_id), "npc"))
    for object_id in source_refs(ends, 1):
        points.extend(source_points(object_all_spawn_points(objects, object_id, "turn-in"), object_name(objects, object_id), "object"))
    return points


def objective_summary_and_points_all(quest, items, npcs, objects):
    objectives = table_value(quest, 9)
    trigger_end = table_value(quest, 8)
    extra_objectives = table_value(quest, 28)
    summary = []
    points = []

    if isinstance(objectives, list):
        creature_ids = objective_ids(objectives, 0)
        if creature_ids:
            summary.append("Kill: " + ", ".join(dict.fromkeys(npc_name(npcs, npc_id) for npc_id in creature_ids)))
            for npc_id in creature_ids:
                points.extend(source_points(npc_all_spawn_points(npcs, npc_id, "mob"), npc_name(npcs, npc_id), "npc"))

        object_ids = objective_ids(objectives, 1)
        if object_ids:
            summary.append("Use/find: " + ", ".join(dict.fromkeys(object_name(objects, object_id) for object_id in object_ids)))
            for object_id in object_ids:
                points.extend(source_points(object_all_spawn_points(objects, object_id, "object"), object_name(objects, object_id), "object"))

        item_ids = objective_ids(objectives, 2)
        if item_ids:
            summary.append("Collect: " + ", ".join(dict.fromkeys(item_name(items, item_id) for item_id in item_ids)))
            for item_id in item_ids:
                points.extend(source_points(item_all_source_points(items, npcs, objects, item_id, "item"), f"{item_name(items, item_id)} source", "item"))

        kill_credit_ids = objective_ids(objectives, 4)
        if kill_credit_ids:
            summary.append("Credit: " + ", ".join(dict.fromkeys(npc_name(npcs, npc_id) for npc_id in kill_credit_ids)))
            for npc_id in kill_credit_ids:
                points.extend(source_points(npc_all_spawn_points(npcs, npc_id, "mob"), npc_name(npcs, npc_id), "npc"))

    if isinstance(trigger_end, list) and len(trigger_end) > 1:
        text = trigger_end[0] if isinstance(trigger_end[0], str) else "Trigger area"
        trigger_points = all_spawn_points_from_table(trigger_end[1], "trigger")
        if trigger_points:
            summary.append(text)
            points.extend(source_points(trigger_points, text, "trigger"))

    if isinstance(extra_objectives, list):
        for extra in extra_objectives:
            if not isinstance(extra, list) or not extra:
                continue
            spawnlist = extra[0]
            extra_text = next((part for part in extra if isinstance(part, str)), "Extra objective")
            extra_points = all_spawn_points_from_table(spawnlist, "extra")
            if extra_points:
                summary.append(extra_text)
                points.extend(source_points(extra_points, extra_text, "extra"))

    objectives_text = table_value(quest, 7)
    if not summary and isinstance(objectives_text, list):
        summary.extend(text for text in objectives_text if isinstance(text, str) and text.strip())

    return summary, points


def project_point(point, zones, continents, subzones):
    zone_id = resolve_zone_id(point["zoneId"], zones, subzones)
    projected = {**point, "zoneId": zone_id}
    zone = zones.get(zone_id)
    if not zone:
        return projected
    continent = continents.get(zone["continentId"])
    if not continent:
        return projected

    world_x = zone["left"] + (zone["right"] - zone["left"]) * projected["x"] / 100
    world_y = zone["top"] + (zone["bottom"] - zone["top"]) * projected["y"] / 100
    local_x = percent_between(world_x, continent["left"], continent["right"])
    local_y = percent_between(world_y, continent["top"], continent["bottom"])
    local_x = percent_between(local_x, continent.get("cropLeftPct", 0), continent.get("cropLeftPct", 0) + continent.get("cropWidthPct", 100))
    local_y = percent_between(local_y, continent.get("cropTopPct", 0), continent.get("cropTopPct", 0) + continent.get("cropHeightPct", 100))
    projected["worldX"] = round(continent["x"] + local_x * continent["width"] / 100, 3)
    projected["worldY"] = round(continent["y"] + local_y * continent["height"] / 100, 3)
    projected["continentId"] = zone["continentId"]
    return projected


def normalize_project_sample(points, zones, continents, subzones, limit=140):
    projected = [project_point(point, zones, continents, subzones) for point in points]
    projected = [point for point in projected if point.get("zoneId") in zones]
    projected = dedupe_spatial_points(projected)
    if len(projected) <= limit:
        return projected
    step = len(projected) / limit
    return [projected[math.floor(i * step)] for i in range(limit)]


def zone_ids_from_points(points, zones, subzones):
    zone_ids = set()
    for point in points:
        raw_zone_id = point.get("zoneId")
        if not isinstance(raw_zone_id, int):
            continue
        zone_id = resolve_zone_id(raw_zone_id, zones, subzones)
        if zone_id in zones:
            zone_ids.add(zone_id)
    return sorted(zone_ids)


def objective_zone_ids_from_points(points, zones, subzones):
    zone_ids = zone_ids_from_points(points, zones, subzones)
    return zone_ids if len(zone_ids) == 1 else []


def dedupe_spatial_points(points):
    seen = set()
    deduped = []
    for point in points:
        key = (
            int(point.get("zoneId", 0)),
            round(point.get("x", 0), 2),
            round(point.get("y", 0), 2),
            point.get("kind", "objective"),
        )
        if key not in seen:
            seen.add(key)
            deduped.append(point)
    return deduped


def race_requirement_name(mask):
    if mask is None or mask == 0:
        return "Any race"
    alliance = bool(mask & ALLIANCE_RACE_MASK)
    horde = bool(mask & HORDE_RACE_MASK)
    if alliance and horde:
        return "Alliance or Horde"
    if alliance:
        return "Alliance"
    if horde:
        return "Horde"
    return f"Race mask {mask}"


def zone_level_ranges(records):
    buckets = defaultdict(lambda: {"lows": [], "highs": []})
    for record in records:
        type_ids = set(record.get("typeIds") or [])
        if type_ids and type_ids.issubset(ZONE_RANGE_EXCLUDED_TYPES):
            continue
        required_level = record.get("requiredLevel") or 0
        quest_level = record.get("questLevel") or required_level
        if quest_level < 0:
            quest_level = required_level
        if quest_level <= 0:
            continue

        low = required_level if required_level > 0 else 1
        high = max(low, quest_level)
        for zone_id in record.get("rangeZones", []):
            buckets[zone_id]["lows"].append(low)
            buckets[zone_id]["highs"].append(high)

    ranges = {}
    for zone_id, values in buckets.items():
        highs = sorted(values["highs"])
        if not highs:
            continue
        high = highs[-1] if len(highs) < 8 else highs[min(len(highs) - 1, math.ceil(len(highs) * 0.85) - 1)]
        low = min(values["lows"])
        ranges[zone_id] = (low, max(low, high))
    return ranges


def build_classic_records():
    quests = load_lua_data(QUESTIE / "classicQuestDB.lua")
    npcs = load_lua_data(QUESTIE / "classicNpcDB.lua")
    objects = load_lua_data(QUESTIE / "classicObjectDB.lua")
    items = load_lua_data(QUESTIE / "classicItemDB.lua")
    zones, continents = load_world_area_data()
    subzones = load_lua_return_table_merge(SUBZONE_TO_PARENT)
    quest_sort_names = load_quest_sort_names()
    quest_tag_corrections = load_quest_tag_corrections()
    holiday_events = load_holiday_event_quests()
    aq_war_effort = load_quest_id_table("AQWarEffortQuests")
    invasion_quests = load_quest_id_table("InvasionQuests")
    fixed_breadcrumb_ids, fixed_escort_ids = load_classic_quest_fix_category_ids()

    candidates = {
        quest_id: quest
        for quest_id, quest in quests.items()
        if isinstance(quest, list) and table_value(quest, 0) and not str(table_value(quest, 0)).startswith("DND ")
    }
    breadcrumb_ids = derive_breadcrumb_ids(candidates, fixed_breadcrumb_ids)
    chains, chain_meta = derive_chains(candidates)
    records = []

    for quest_id in sorted(candidates, key=lambda qid: (table_value(candidates[qid], 3) or 0, table_value(candidates[qid], 4) or 0, qid)):
        quest = candidates[quest_id]
        start_points = normalize_project_sample(start_points_for_quest_all(quest, items, npcs, objects), zones, continents, subzones, 80)
        end_points = normalize_project_sample(end_points_for_quest_all(quest, npcs, objects), zones, continents, subzones, 80)
        objective_summary, raw_objective_points = objective_summary_and_points_all(quest, items, npcs, objects)
        objective_points = normalize_project_sample(raw_objective_points, zones, continents, subzones, 140)
        zone_or_sort = table_value(quest, 16)
        start_zone_ids = zone_ids_from_points(start_points, zones, subzones)
        end_zone_ids = zone_ids_from_points(end_points, zones, subzones)
        objective_zone_ids = objective_zone_ids_from_points(raw_objective_points, zones, subzones)

        quest_zones = set([*start_zone_ids, *objective_zone_ids, *end_zone_ids])
        range_zones = set(quest_zones)
        if isinstance(zone_or_sort, int) and zone_or_sort > 0:
            normalized_zone = resolve_zone_id(zone_or_sort, zones, subzones)
            if normalized_zone in zones:
                quest_zones.add(normalized_zone)
                range_zones.add(normalized_zone)

        objectives_text = table_value(quest, 7)
        text_lines = [line for line in objectives_text if isinstance(line, str) and line.strip()] if isinstance(objectives_text, list) else []
        pre_group = flatten_numbers(table_value(quest, 11))
        pre_single = flatten_numbers(table_value(quest, 12))
        next_id = table_value(quest, 21)
        chain = chains[quest_id]
        type_metadata = derive_quest_type_ids(
            quest_id,
            quest,
            quest_sort_names,
            quest_tag_corrections,
            holiday_events,
            aq_war_effort,
            invasion_quests,
            breadcrumb_ids,
            fixed_escort_ids,
        )

        records.append({
            "id": quest_id,
            "name": table_value(quest, 0),
            "requiredLevel": table_value(quest, 3),
            "questLevel": table_value(quest, 4),
            "requiredRaceMask": table_value(quest, 5) or 0,
            "requiredClassMask": table_value(quest, 6) or 0,
            "raceRequirement": race_requirement_name(table_value(quest, 5)),
            "classRequirement": class_requirement_name(table_value(quest, 6)),
            "zoneOrSort": zone_or_sort,
            "zones": sorted(quest_zones),
            "rangeZones": sorted(range_zones),
            "startZoneIds": start_zone_ids,
            "objectiveZoneIds": objective_zone_ids,
            "endZoneIds": end_zone_ids,
            "startPoints": start_points,
            "endPoints": end_points,
            "objectivePoints": objective_points,
            "startSources": describe_start(quest, items, npcs, objects, zones, subzones),
            "endSources": describe_end(quest, npcs, objects, zones, subzones),
            "objectiveText": text_lines,
            "objectiveSummary": objective_summary,
            "preQuestGroup": pre_group,
            "preQuestSingle": pre_single,
            "nextQuestInChain": next_id if isinstance(next_id, int) else None,
            **type_metadata,
            **chain,
        })

    zone_counts = Counter()
    zone_chain_ids = defaultdict(set)
    for record in records:
        for zone_id in record["zones"]:
            zone_counts[zone_id] += 1
            zone_chain_ids[zone_id].add(record["chainId"])
    level_ranges = {
        **zone_level_ranges(records),
        **{zone_id: level_range for zone_id, level_range in CLASSIC_ZONE_LEVEL_RANGES.items() if zone_id in zones},
    }

    serializable_zones = []
    for zone_id, zone in sorted(zones.items(), key=lambda item: (
        level_ranges.get(item[0], (999, 999))[0],
        level_ranges.get(item[0], (999, 999))[1],
        item[1]["continentId"],
        item[1]["name"],
    )):
        level_range = level_ranges.get(zone_id)
        serializable_zones.append({
            "id": zone_id,
            "name": zone["name"],
            "continentId": zone["continentId"],
            "image": zone["image"],
            "worldRect": zone.get("worldRect"),
            "questCount": zone_counts[zone_id],
            "chainCount": len(zone_chain_ids[zone_id]),
            "minLevel": level_range[0] if level_range else None,
            "maxLevel": level_range[1] if level_range else None,
            "levelRange": (
                str(level_range[0])
                if level_range and level_range[0] == level_range[1]
                else f"{level_range[0]}-{level_range[1]}" if level_range else ""
            ),
        })

    serializable_continents = [
        {
            "id": continent_id,
            "name": continent["name"],
            "x": continent["x"],
            "y": continent["y"],
            "width": continent["width"],
            "height": continent["height"],
            "image": to_web_path(CONTINENT_MAP_ASSET_DIR / f"{continent_id}.jpg"),
            "crop": [
                round(continent.get("cropLeftPct", 0), 4),
                round(continent.get("cropTopPct", 0), 4),
                round(continent.get("cropWidthPct", 100), 4),
                round(continent.get("cropHeightPct", 100), 4),
            ],
            "zoneHitGrid": continent.get("zoneHitGrid"),
        }
        for continent_id, continent in sorted(continents.items(), key=lambda item: item[0], reverse=True)
    ]

    return records, chain_meta, serializable_zones, serializable_continents


def render_classic_html(records, chains, zones, continents):
    payload = json.dumps({
        "quests": records,
        "chains": chains,
        "zones": zones,
        "continents": continents,
        "questTypeFilters": QUEST_TYPE_FILTERS,
    }, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    quest_count = len(records)
    zone_count = len(zones)
    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>QuestiePlus</title>
  <style>
    :root {{
      color-scheme: dark;
      --bg: #0d0f0c;
      --panel: #191d17;
      --panel-2: #24291f;
      --ink: #f7eed8;
      --muted: #c9baa0;
      --line: rgba(255, 235, 196, 0.22);
      --gold: #ffd34f;
      font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
    }}

    * {{
      box-sizing: border-box;
    }}

    html,
    body {{
      height: 100%;
    }}

    body {{
      margin: 0;
      overflow: hidden;
      background: linear-gradient(180deg, #151711 0%, #080a08 100%);
      color: var(--ink);
    }}

    main {{
      height: 100vh;
      width: 100vw;
      padding: 12px;
      display: grid;
      grid-template-rows: auto minmax(0, 1fr);
      gap: 10px;
    }}

    header {{
      min-height: 42px;
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(380px, 25vw);
      align-items: center;
      gap: 10px;
    }}

    .header-main {{
      min-width: 0;
      display: flex;
      align-items: center;
      gap: 14px;
      flex-wrap: wrap;
    }}

    .header-side {{
      min-width: 0;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
    }}

    h1 {{
      margin: 0;
      font-size: clamp(1.35rem, 2.1vw, 2rem);
      line-height: 1;
      letter-spacing: 0;
      white-space: nowrap;
    }}

    .brand {{
      font-weight: 900;
      text-shadow: 0 1px 0 rgba(0, 0, 0, 0.55), 0 0 14px rgba(255, 211, 79, 0.16);
    }}

    .brand-questie {{
      color: #fffaf0;
    }}

    .brand-plus {{
      color: var(--gold);
    }}

    .view-toggle {{
      display: inline-flex;
      align-items: center;
      gap: 0;
      padding: 3px;
      border: 1px solid rgba(255, 235, 196, 0.24);
      border-radius: 999px;
      background: rgba(7, 9, 7, 0.48);
      box-shadow: inset 0 1px 3px rgba(0, 0, 0, 0.34);
    }}

    .toolbar .view-toggle button {{
      min-height: 28px;
      padding: 0 12px;
      border: 0;
      border-radius: 999px;
      background: transparent;
      color: #c9baa0;
      font-size: 0.78rem;
      font-weight: 850;
      box-shadow: none;
    }}

    .toolbar .view-toggle button.active,
    .toolbar .view-toggle button[aria-pressed="true"] {{
      background: rgba(255, 211, 79, 0.18);
      color: #fff8dc;
      box-shadow: inset 0 0 0 1px rgba(255, 211, 79, 0.34), 0 0 14px rgba(255, 211, 79, 0.12);
    }}

    .toolbar {{
      min-width: 0;
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
    }}

    .toolbar button,
    .toolbar select {{
      min-height: 34px;
      border: 1px solid rgba(255, 235, 196, 0.24);
      border-radius: 7px;
      background: rgba(255, 255, 255, 0.07);
      color: #fff0ce;
      font: inherit;
      font-size: 0.88rem;
    }}

    .toolbar button {{
      padding: 0 12px;
      cursor: pointer;
    }}

    .options-filter-button {{
      min-height: 34px;
      padding: 0 12px;
      border: 1px solid rgba(255, 235, 196, 0.24);
      border-radius: 7px;
      background: rgba(255, 255, 255, 0.07);
      color: #fff0ce;
      font: inherit;
      font-size: 0.88rem;
      cursor: pointer;
    }}

    .toolbar button.active {{
      border-color: var(--gold);
      background: rgba(255, 211, 79, 0.16);
      color: #fff8dc;
    }}

    .options-filter-button.active {{
      border-color: var(--gold);
      background: rgba(255, 211, 79, 0.16);
      color: #fff8dc;
    }}

    .toolbar select {{
      min-width: min(380px, 44vw);
      padding: 0 8px;
    }}

    .toolbar select.filter-select {{
      min-width: 132px;
      font-weight: 700;
    }}

    .toolbar select.level-select {{
      min-width: 106px;
    }}

    .toolbar-separator {{
      flex: 0 0 auto;
      width: 1px;
      height: 28px;
      margin: 0 3px;
      border-radius: 999px;
      background: rgba(210, 202, 186, 0.34);
    }}

    .quest-filter-wrap,
    .zone-filter-wrap,
    .display-filter-wrap,
    .options-filter-wrap {{
      position: relative;
    }}

    .quest-filter-button,
    .zone-filter-button,
    .display-filter-button,
    .options-filter-button {{
      display: inline-flex;
      align-items: center;
      gap: 8px;
      font-weight: 800;
    }}

    .quest-filter-button .filter-count,
    .zone-filter-button .filter-count,
    .display-filter-button .filter-count,
    .options-filter-button .filter-count {{
      display: inline-grid;
      place-items: center;
      min-width: 18px;
      height: 18px;
      padding: 0 5px;
      border-radius: 999px;
      background: rgba(255, 211, 79, 0.18);
      color: #ffe28a;
      font-size: 0.72rem;
      line-height: 1;
    }}

    .quest-filter-menu,
    .zone-filter-menu,
    .display-filter-menu,
    .options-filter-menu {{
      position: absolute;
      z-index: 80;
      top: calc(100% + 7px);
      left: 0;
      right: auto;
      width: 280px;
      max-height: min(520px, calc(100vh - 84px));
      overflow: auto;
      padding: 8px;
      border: 1px solid rgba(255, 235, 196, 0.24);
      border-radius: 8px;
      background: rgba(21, 24, 19, 0.98);
      box-shadow: 0 18px 40px rgba(0, 0, 0, 0.42);
    }}

    .quest-filter-menu[hidden],
    .zone-filter-menu[hidden],
    .display-filter-menu[hidden],
    .options-filter-menu[hidden] {{
      display: none;
    }}

    .zone-filter-menu {{
      width: 340px;
    }}

    .quest-filter-title,
    .zone-filter-title,
    .display-filter-title,
    .options-filter-title {{
      padding: 4px 6px 8px;
      margin-bottom: 5px;
      border-bottom: 1px solid rgba(255, 235, 196, 0.14);
      color: #fff2cf;
      font-size: 0.8rem;
      font-weight: 850;
    }}

    .filter-actions {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 6px;
      margin: 0 0 8px;
      padding: 0 0 8px;
      border-bottom: 1px solid rgba(255, 235, 196, 0.14);
    }}

    .filter-actions button {{
      min-height: 28px;
      padding: 0 8px;
      font-size: 0.76rem;
    }}

    .quest-type-option {{
      display: grid;
      grid-template-columns: 18px minmax(0, 1fr) auto;
      align-items: center;
      gap: 8px;
      min-height: 30px;
      padding: 5px 6px;
      border-radius: 6px;
      color: #eadfc9;
      font-size: 0.82rem;
      cursor: pointer;
    }}

    .quest-type-option:hover,
    .quest-type-option:focus-within {{
      background: rgba(255, 255, 255, 0.07);
    }}

    .quest-type-option input {{
      width: 16px;
      height: 16px;
      accent-color: #ffd34f;
    }}

    .quest-type-option .type-count {{
      color: #a99b83;
      font-size: 0.72rem;
      font-variant-numeric: tabular-nums;
    }}

    .count {{
      color: var(--muted);
      font-size: 0.86rem;
      white-space: nowrap;
    }}

    .workbench {{
      min-height: 0;
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(380px, 25vw);
      gap: 10px;
    }}

    .map-frame,
    .inventory {{
      border: 1px solid var(--line);
      border-radius: 8px;
      background: linear-gradient(180deg, rgba(35, 39, 31, 0.95), rgba(18, 21, 17, 0.98));
      box-shadow: 0 18px 48px rgba(0, 0, 0, 0.28);
      min-height: 0;
    }}

    .map-frame {{
      position: relative;
      display: grid;
      place-items: center;
      overflow: hidden;
    }}

    .map-mode-panel,
    .sequencer-panel {{
      position: absolute;
      inset: 0;
    }}

    .map-mode-panel {{
      display: grid;
      place-items: center;
    }}

    .map-mode-panel[hidden],
    .sequencer-panel[hidden] {{
      display: none;
    }}

    .sequencer-panel {{
      display: grid;
      min-height: 0;
      padding: 16px;
      overflow: hidden;
      background:
        radial-gradient(circle at 28% 22%, rgba(255, 211, 79, 0.12), transparent 34%),
        linear-gradient(135deg, rgba(18, 23, 18, 0.98), rgba(31, 35, 28, 0.96));
    }}

    .journey-setup {{
      place-self: center;
      width: min(520px, 92%);
      display: grid;
      gap: 12px;
      padding: 18px;
      border: 1px solid rgba(255, 235, 196, 0.2);
      border-radius: 8px;
      background: rgba(7, 9, 7, 0.48);
      box-shadow: 0 18px 44px rgba(0, 0, 0, 0.3);
    }}

    .journey-setup[hidden],
    .journey-workspace[hidden] {{
      display: none;
    }}

    .journey-setup h2 {{
      margin: 0;
      color: #fff6d8;
      font-size: clamp(1.25rem, 2vw, 1.85rem);
      line-height: 1.08;
      letter-spacing: 0;
    }}

    .journey-setup p {{
      margin: 0;
      color: #bfae91;
      font-size: 0.88rem;
      line-height: 1.42;
    }}

    .journey-setup-grid {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }}

    .journey-field {{
      display: grid;
      gap: 5px;
      min-width: 0;
    }}

    .journey-field.full {{
      grid-column: 1 / -1;
    }}

    .journey-field label {{
      color: #d8cab1;
      font-size: 0.72rem;
      font-weight: 850;
      text-transform: uppercase;
      letter-spacing: 0;
    }}

    .journey-field input,
    .journey-field select,
    .batch-name-input,
    .batch-level-input {{
      min-width: 0;
      min-height: 34px;
      border: 1px solid rgba(255, 235, 196, 0.22);
      border-radius: 7px;
      background: rgba(0, 0, 0, 0.24);
      color: #fff0ce;
      font: inherit;
      font-size: 0.86rem;
      outline: none;
    }}

    .journey-field input,
    .journey-field select {{
      padding: 0 9px;
    }}

    .journey-field input:focus,
    .journey-field select:focus,
    .batch-name-input:focus,
    .batch-level-input:focus {{
      border-color: rgba(255, 211, 79, 0.62);
      box-shadow: 0 0 0 2px rgba(255, 211, 79, 0.14);
    }}

    .journey-start-button,
    .journey-save-button,
    .journey-import-button {{
      justify-self: start;
      min-height: 34px;
      padding: 0 12px;
      border: 1px solid rgba(255, 211, 79, 0.5);
      border-radius: 7px;
      background: rgba(255, 211, 79, 0.16);
      color: #fff8dc;
      font: inherit;
      font-size: 0.82rem;
      font-weight: 850;
      cursor: pointer;
    }}

    .journey-start-button:disabled,
    .journey-save-button:disabled,
    .journey-import-button:disabled {{
      cursor: not-allowed;
      opacity: 0.48;
    }}

    .journey-import-input {{
      display: none;
    }}

    .journey-workspace {{
      min-height: 0;
      display: grid;
      grid-template-rows: auto auto minmax(0, 1fr);
      gap: 10px;
    }}

    .journey-head {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      min-width: 0;
    }}

    .journey-title-tools {{
      min-width: 0;
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
    }}

    .journey-global-actions {{
      position: absolute;
      top: 16px;
      right: 16px;
      z-index: 3;
      display: flex;
      align-items: center;
      gap: 8px;
    }}

    .journey-name-editor {{
      width: min(340px, 38vw);
      min-height: 34px;
      padding: 0 9px;
      border: 1px solid rgba(255, 235, 196, 0.22);
      border-radius: 7px;
      background: rgba(0, 0, 0, 0.24);
      color: #fff6d8;
      font: inherit;
      font-size: 1rem;
      font-weight: 850;
      outline: none;
    }}

    .journey-character-summary {{
      color: #a99b83;
      font-size: 0.78rem;
      font-weight: 750;
      white-space: nowrap;
    }}

    .journey-message {{
      min-height: 28px;
      padding: 7px 10px;
      border-radius: 7px;
      border: 1px solid rgba(255, 91, 91, 0.34);
      background: rgba(88, 16, 16, 0.34);
      color: #ffb0a8;
      font-size: 0.8rem;
      font-weight: 750;
    }}

    .journey-message.ok {{
      border-color: rgba(113, 214, 124, 0.34);
      background: rgba(20, 78, 35, 0.28);
      color: #b7f2bc;
    }}

    .journey-message[hidden] {{
      display: none;
    }}

    .sequencer-board {{
      min-height: 0;
      display: flex;
      align-items: stretch;
      gap: 10px;
      overflow: auto;
      padding: 2px 3px 8px;
      scrollbar-color: rgba(255, 255, 255, 0.24) transparent;
      scrollbar-width: thin;
    }}

    .journey-batch {{
      flex: 0 0 min(286px, 38vw);
      min-height: 0;
      display: grid;
      grid-template-rows: auto minmax(0, 1fr);
      border: 1px solid rgba(255, 235, 196, 0.2);
      border-radius: 8px;
      background: rgba(6, 8, 6, 0.34);
      box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.04);
      overflow: hidden;
    }}

    .journey-batch.selected {{
      border-color: rgba(255, 211, 79, 0.65);
      box-shadow: inset 0 0 0 1px rgba(255, 211, 79, 0.42), 0 0 22px rgba(255, 211, 79, 0.12);
    }}

    .journey-batch.unused {{
      border-color: rgba(234, 83, 83, 0.68);
      background: rgba(76, 13, 13, 0.28);
      box-shadow: inset 0 0 0 1px rgba(255, 116, 116, 0.18);
    }}

    .journey-batch-head {{
      display: grid;
      gap: 6px;
      padding: 8px 9px 9px;
      border-bottom: 1px solid rgba(255, 235, 196, 0.16);
      background: rgba(255, 255, 255, 0.045);
      cursor: pointer;
    }}

    .journey-batch.selected .journey-batch-head {{
      background: rgba(255, 211, 79, 0.1);
    }}

    .journey-batch.unused .journey-batch-head {{
      border-bottom-color: rgba(255, 116, 116, 0.24);
      background: rgba(129, 24, 24, 0.34);
      cursor: default;
    }}

    .batch-title-row {{
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      align-items: center;
      gap: 8px;
    }}

    .batch-name-input {{
      width: 100%;
      min-height: 30px;
      padding: 0 8px;
      color: #fff1cd;
      font-weight: 850;
    }}

    .batch-level-control {{
      display: inline-flex;
      align-items: center;
      gap: 4px;
      color: #a99b83;
      font-size: 0.7rem;
      font-weight: 850;
      white-space: nowrap;
    }}

    .batch-level-input {{
      width: 54px;
      min-height: 30px;
      padding: 0 6px;
      color: #ffe28a;
      font-weight: 850;
      text-align: center;
    }}

    .batch-zone-summary {{
      min-height: 18px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      color: #a99b83;
      font-size: 0.72rem;
      font-weight: 700;
    }}

    .journey-batch-drop {{
      min-height: 0;
      display: grid;
      align-content: start;
      gap: 8px;
      padding: 10px;
      overflow: auto;
    }}

    .journey-batch-drop.drag-over {{
      background: rgba(255, 211, 79, 0.08);
      box-shadow: inset 0 0 0 2px rgba(255, 211, 79, 0.36);
    }}

    .journey-batch.unused .journey-batch-drop.drag-over {{
      background: rgba(234, 83, 83, 0.12);
      box-shadow: inset 0 0 0 2px rgba(255, 116, 116, 0.5);
    }}

    .batch-empty {{
      display: grid;
      place-items: center;
      min-height: 110px;
      padding: 16px;
      border: 1px dashed rgba(255, 235, 196, 0.2);
      border-radius: 7px;
      color: #a99b83;
      font-size: 0.8rem;
      text-align: center;
    }}

    .journey-insert-slot {{
      flex: 0 0 62px;
      display: grid;
      place-items: center;
      padding: 0 2px;
    }}

    .journey-insert-target {{
      display: grid;
      place-items: center;
      width: 54px;
      height: 54px;
      border: 1px dashed rgba(255, 235, 196, 0.34);
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.045);
      color: #ffd34f;
      font-size: 1.6rem;
      font-weight: 850;
      cursor: pointer;
    }}

    .journey-insert-target.drag-over,
    body.dragging-quest .journey-insert-target {{
      border-color: rgba(255, 211, 79, 0.9);
      background: rgba(255, 211, 79, 0.13);
      box-shadow: 0 0 18px rgba(255, 211, 79, 0.22);
    }}

    .journey-quest {{
      display: grid;
      grid-template-columns: 26px minmax(0, 1fr) auto minmax(22px, auto);
      align-items: center;
      gap: 8px;
      min-height: 38px;
      padding: 6px 7px;
      border-radius: 7px;
      border: 1px solid rgba(255, 235, 196, 0.14);
      background: rgba(255, 255, 255, 0.06);
      cursor: grab;
    }}

    .journey-quest.unused {{
      border-color: rgba(255, 116, 116, 0.2);
      background: rgba(255, 116, 116, 0.08);
    }}

    .journey-quest.dragging {{
      opacity: 0.55;
      cursor: grabbing;
    }}

    .journey-quest.active,
    .journey-quest.selected {{
      outline: 2px solid #fff6cf;
      outline-offset: 1px;
      background: color-mix(in srgb, var(--chain-color) 14%, rgba(255, 255, 255, 0.055));
    }}

    .journey-quest-step {{
      display: grid;
      place-items: center;
      width: 22px;
      height: 22px;
      border-radius: 999px;
      border: 2px solid var(--chain-color);
      background: rgba(255, 245, 208, 0.92);
      color: #1f1606;
      font-size: 0.7rem;
      font-weight: 850;
    }}

    .journey-quest-name {{
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      color: var(--quest-difficulty-color, #fff2cf);
      font-size: 0.82rem;
      font-weight: 780;
    }}

    .journey-quest-level {{
      color: #a99b83;
      font-size: 0.72rem;
      font-weight: 750;
      white-space: nowrap;
    }}

    .journey-quest-remove,
    .journey-quest-unhide {{
      display: grid;
      place-items: center;
      min-width: 21px;
      height: 21px;
      padding: 0 7px;
      border: 0;
      border-radius: 999px;
      background: rgba(112, 20, 20, 0.68);
      color: #ffb0a8;
      font-size: 0.88rem;
      font-weight: 900;
      line-height: 1;
      cursor: pointer;
    }}

    .journey-quest-unhide {{
      background: rgba(255, 211, 79, 0.16);
      color: #ffe28a;
      font-size: 0.68rem;
      text-transform: uppercase;
      letter-spacing: 0;
    }}

    .journey-quest-remove:hover,
    .journey-quest-remove:focus-visible {{
      outline: 2px solid rgba(255, 91, 91, 0.52);
      outline-offset: 1px;
      background: rgba(150, 28, 28, 0.82);
      color: #fff0ed;
    }}

    .map-title {{
      position: absolute;
      left: 12px;
      top: 10px;
      z-index: 30;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      max-width: calc(100% - 24px);
      padding: 6px 10px;
      border-radius: 999px;
      background: rgba(9, 10, 8, 0.72);
      border: 1px solid rgba(255, 235, 196, 0.18);
      color: #fff2cf;
      font-size: 0.82rem;
      box-shadow: 0 8px 20px rgba(0, 0, 0, 0.32);
    }}

    .map {{
      position: relative;
      width: 100%;
      height: 100%;
      aspect-ratio: 3 / 2;
      overflow: hidden;
      background: #10140f;
    }}

    .zone-image {{
      position: absolute;
      inset: 0;
      width: 100%;
      height: 100%;
      object-fit: fill;
      filter: saturate(0.9) contrast(1.06) brightness(0.82);
      user-select: none;
      pointer-events: none;
    }}

    .world-layer {{
      position: absolute;
      inset: 0;
      background:
        radial-gradient(circle at 50% 50%, rgba(59, 77, 60, 0.34), transparent 42%),
        linear-gradient(180deg, #273125 0%, #11170f 100%);
    }}

    .continent {{
      position: absolute;
      border-radius: 8px;
      border: 1px solid rgba(255, 235, 196, 0.16);
      overflow: hidden;
      background: rgba(0, 0, 0, 0.2);
      box-shadow: inset 0 0 40px rgba(0, 0, 0, 0.5), 0 16px 36px rgba(0, 0, 0, 0.26);
    }}

    .continent-map {{
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
      opacity: 0.92;
      filter: saturate(0.92) contrast(1.06) brightness(0.82);
      user-select: none;
      pointer-events: none;
    }}

    .continent-label {{
      position: absolute;
      left: 8px;
      top: 7px;
      z-index: 3;
      padding: 3px 7px;
      border-radius: 999px;
      background: rgba(0, 0, 0, 0.55);
      color: #eadfc9;
      font-size: 0.72rem;
    }}

    .world-zone-tooltip {{
      position: absolute;
      z-index: 70;
      min-width: 132px;
      max-width: min(260px, 30vw);
      padding: 8px 10px;
      border-radius: 8px;
      border: 1px solid rgba(255, 235, 196, 0.24);
      background: rgba(21, 24, 19, 0.98);
      color: #fff2cf;
      font-size: 0.78rem;
      font-weight: 850;
      box-shadow: 0 18px 40px rgba(0, 0, 0, 0.46);
      pointer-events: none;
    }}

    .world-zone-tooltip[hidden] {{
      display: none;
    }}

    .veil {{
      position: absolute;
      inset: 0;
      background: linear-gradient(180deg, rgba(0, 0, 0, 0.03), rgba(0, 0, 0, 0.18));
      pointer-events: none;
    }}

    #map-marker-layer,
    #highlight-layer {{
      position: absolute;
      inset: 0;
    }}

    #highlight-layer {{
      pointer-events: none;
      z-index: 20;
    }}

    #map-marker-layer {{
      z-index: 35;
      pointer-events: none;
    }}

    .objective-area {{
      position: absolute;
      border-radius: 999px;
      translate: -50% -50%;
      border: 2px solid var(--chain-color);
      background: color-mix(in srgb, var(--chain-color) 20%, transparent);
      box-shadow: 0 0 32px color-mix(in srgb, var(--chain-color) 68%, transparent);
    }}

    .objective-dot {{
      position: absolute;
      width: 8px;
      height: 8px;
      border-radius: 999px;
      translate: -50% -50%;
      background: var(--chain-color);
      border: 1px solid rgba(255, 255, 255, 0.82);
      box-shadow: 0 0 12px var(--chain-color), 0 0 3px #000;
      opacity: 0.95;
    }}

    .quest-pin {{
      position: absolute;
      z-index: 5;
      display: grid;
      place-items: center;
      width: 28px;
      height: 28px;
      border-radius: 999px;
      translate: -50% -50%;
      font-size: 1rem;
      font-weight: 900;
      line-height: 1;
      border: 2px solid rgba(255, 255, 255, 0.86);
      box-shadow: 0 4px 10px rgba(0, 0, 0, 0.62), 0 0 18px rgba(255, 224, 109, 0.48);
      text-shadow: 0 1px 0 rgba(255, 255, 255, 0.34);
    }}

    .quest-pin.pickup {{
      margin-left: -12px;
      background: #ffd34f;
      color: #241703;
    }}

    .quest-pin.turnin {{
      margin-left: 12px;
      background: #f3f8ff;
      color: #122034;
    }}

    .pickup-dot {{
      position: absolute;
      width: 10px;
      height: 10px;
      border-radius: 999px;
      translate: -50% -50%;
      background: #ffd34f;
      border: 1px solid rgba(38, 24, 6, 0.72);
      box-shadow: 0 1px 4px rgba(0, 0, 0, 0.62), 0 0 8px rgba(255, 211, 79, 0.44);
      pointer-events: none;
    }}

    .map-marker {{
      position: absolute;
      display: grid;
      place-items: center;
      min-width: 22px;
      height: 22px;
      padding: 0 5px;
      border-radius: 999px;
      translate: -50% -50%;
      border: 1px solid rgba(255, 250, 220, 0.82);
      background: rgba(255, 211, 79, 0.86);
      color: #261806;
      font-size: 0.68rem;
      font-weight: 850;
      cursor: pointer;
      box-shadow: 0 2px 7px rgba(0, 0, 0, 0.58), 0 0 12px rgba(255, 211, 79, 0.48);
      pointer-events: auto;
    }}

    .map-marker.cluster {{
      background: rgba(255, 245, 208, 0.86);
      color: #281c0a;
    }}

    .map-marker.available-pickup {{
      width: 28px;
      min-width: 28px;
      height: 28px;
      padding: 0;
      overflow: visible;
      background:
        linear-gradient(#ffd34f, #ffd34f) padding-box,
        var(--pickup-ring, rgba(255, 255, 255, 0.86)) border-box;
      color: #241703;
      border: 2px solid transparent;
      font-size: 1rem;
      font-weight: 900;
    }}

    .map-marker.available-pickup.single-pickup {{
      --pickup-ring: var(--quest-difficulty-color, rgba(255, 255, 255, 0.86));
      box-shadow: 0 2px 7px rgba(0, 0, 0, 0.58), 0 0 13px color-mix(in srgb, var(--quest-difficulty-color, #ffd34f) 60%, transparent);
    }}

    .map-marker.available-objective {{
      width: 8px;
      min-width: 8px;
      height: 8px;
      padding: 0;
      border: 1px solid rgba(255, 255, 255, 0.82);
      background: var(--chain-color);
      color: transparent;
      font-size: 0;
      box-shadow: 0 0 12px var(--chain-color), 0 0 3px #000;
      opacity: 0.95;
    }}

    .map-marker.available-objective .display-marker-glyph {{
      display: none;
    }}

    .map-marker.available-handin {{
      width: 24px;
      min-width: 24px;
      height: 24px;
      padding: 0;
      border: 2px solid rgba(255, 255, 255, 0.88);
      background: #f3f8ff;
      color: #122034;
      font-size: 0.92rem;
      font-weight: 950;
      box-shadow: 0 2px 7px rgba(0, 0, 0, 0.58), 0 0 12px rgba(220, 237, 255, 0.46);
    }}

    .quest-type-badge {{
      position: absolute;
      z-index: 3;
      display: grid;
      place-items: center;
      width: 15px;
      height: 15px;
      border-radius: 999px;
      border: 1px solid rgba(255, 255, 255, 0.84);
      color: #fff7e6;
      font-size: 0.58rem;
      line-height: 1;
      font-weight: 900;
      box-shadow: 0 1px 4px rgba(0, 0, 0, 0.6);
      pointer-events: none;
    }}

    .quest-type-badge.dungeon {{
      top: -6px;
      left: -6px;
      background: #b31f1f;
    }}

    .quest-type-badge.elite {{
      top: -6px;
      right: -6px;
      background: #d56b19;
    }}

    .quest-type-text-badges {{
      display: inline-flex;
      align-items: center;
      gap: 3px;
      flex: 0 0 auto;
    }}

    .quest-type-text-badge {{
      color: #d7cab2;
      font-size: 0.72rem;
      font-weight: 850;
      white-space: nowrap;
    }}

    .pickup-count {{
      position: absolute;
      right: -7px;
      bottom: -7px;
      display: grid;
      place-items: center;
      min-width: 16px;
      height: 16px;
      padding: 0 4px;
      border-radius: 999px;
      border: 1px solid rgba(255, 255, 255, 0.86);
      background: #1d251a;
      color: #fff2cf;
      font-size: 0.62rem;
      line-height: 1;
      box-shadow: 0 2px 6px rgba(0, 0, 0, 0.55);
    }}

    .pickup-choice-popover {{
      position: absolute;
      z-index: 80;
      min-width: 220px;
      max-width: min(320px, 36vw);
      max-height: min(560px, 72vh);
      overflow: auto;
      translate: 14px -50%;
      padding: 7px;
      border-radius: 8px;
      border: 1px solid rgba(255, 235, 196, 0.24);
      background: rgba(21, 24, 19, 0.98);
      box-shadow: 0 18px 40px rgba(0, 0, 0, 0.46);
      pointer-events: auto;
    }}

    .pickup-choice-title {{
      margin: 0 0 6px;
      padding: 2px 4px 6px;
      border-bottom: 1px solid rgba(255, 235, 196, 0.14);
      color: #fff2cf;
      font-size: 0.76rem;
      font-weight: 850;
    }}

    .pickup-choice-note {{
      margin: -2px 2px 5px;
      color: #b7aa91;
      font-size: 0.68rem;
      line-height: 1.25;
    }}

    .pickup-choice-section {{
      padding: 4px 0 6px;
    }}

    .pickup-choice-section + .pickup-choice-section {{
      margin-top: 5px;
      border-top: 1px solid rgba(255, 235, 196, 0.12);
    }}

    .pickup-choice-chain-break {{
      height: 1px;
      margin: 4px 8px;
      background: linear-gradient(90deg, transparent, rgba(210, 202, 186, 0.34), transparent);
    }}

    .pickup-choice-heading {{
      padding: 3px 6px 4px;
      color: #ffd34f;
      font-size: 0.72rem;
      font-weight: 850;
      text-transform: none;
    }}

    .pickup-choice-item {{
      display: grid;
      width: 100%;
      gap: 2px;
      min-height: 34px;
      padding: 6px 7px;
      border: 0;
      border-radius: 6px;
      background: transparent;
      color: #eadfc9;
      font: inherit;
      text-align: left;
      cursor: pointer;
    }}

    .pickup-choice-item:hover,
    .pickup-choice-item:focus-visible {{
      outline: 2px solid #fff6cf;
      outline-offset: 1px;
      background: rgba(255, 255, 255, 0.075);
    }}

    .pickup-choice-name-row {{
      min-width: 0;
      display: flex;
      align-items: baseline;
      gap: 4px;
      overflow: hidden;
    }}

    .pickup-choice-name {{
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      color: var(--quest-difficulty-color, #fff2cf);
      font-size: 0.8rem;
      font-weight: 780;
    }}

    .pickup-choice-meta {{
      color: #a99b83;
      font-size: 0.7rem;
    }}

    .map-marker.active,
    .map-marker.selected,
    .map-marker:hover,
    .map-marker:focus-visible {{
      outline: 2px solid #fff6cf;
      outline-offset: 2px;
      z-index: 40;
    }}

    .inventory {{
      display: grid;
      grid-template-rows: auto minmax(0, 1fr);
      overflow: hidden;
    }}

    .inventory-head {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      padding: 10px 12px;
      border-bottom: 1px solid rgba(255, 235, 196, 0.14);
      background: rgba(12, 13, 10, 0.52);
    }}

    .inventory-subtitle {{
      color: #a99b83;
      font-size: 0.78rem;
      white-space: nowrap;
    }}

    .inventory-actions {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
      flex: 0 0 auto;
    }}

    .inventory-action {{
      display: grid;
      place-items: center;
      width: 30px;
      height: 30px;
      padding: 0;
      border-radius: 7px;
      font-size: 1rem;
      font-weight: 900;
      line-height: 1;
    }}

    .inventory-search {{
      position: relative;
      flex: 1 1 auto;
      min-width: 0;
    }}

    .quest-search-input {{
      width: 100%;
      min-width: 0;
      height: 34px;
      padding: 0 34px 0 11px;
      border-radius: 7px;
      border: 1px solid rgba(255, 235, 196, 0.18);
      background: rgba(8, 10, 8, 0.72);
      color: #fff2cf;
      font-size: 0.82rem;
      outline: none;
      box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.28);
    }}

    .quest-search-input::placeholder {{
      color: #8f826f;
    }}

    .quest-search-input:focus {{
      border-color: rgba(255, 211, 79, 0.55);
      box-shadow: 0 0 0 2px rgba(255, 211, 79, 0.16), inset 0 1px 2px rgba(0, 0, 0, 0.28);
    }}

    .quest-search-clear {{
      position: absolute;
      right: 6px;
      top: 50%;
      display: grid;
      place-items: center;
      width: 22px;
      height: 22px;
      border: 0;
      border-radius: 999px;
      translate: 0 -50%;
      background: rgba(90, 18, 18, 0.5);
      color: #ff5b5b;
      font-size: 0.9rem;
      font-weight: 900;
      line-height: 1;
      cursor: pointer;
    }}

    .quest-search-clear:hover,
    .quest-search-clear:focus-visible {{
      outline: 2px solid rgba(255, 91, 91, 0.55);
      outline-offset: 1px;
      background: rgba(124, 24, 24, 0.78);
      color: #ff9a9a;
    }}

    .quest-search-clear[hidden] {{
      display: none;
    }}

    .chain-list {{
      overflow: auto;
      padding: 8px;
      scrollbar-color: rgba(255, 255, 255, 0.24) transparent;
      scrollbar-width: thin;
    }}

    .chain-row {{
      display: grid;
      gap: 8px;
      margin-bottom: 8px;
      padding: 9px;
      border-left: 3px solid var(--chain-color);
      border-radius: 7px;
      background: rgba(255, 255, 255, 0.052);
      box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.055);
      cursor: pointer;
    }}

    .chain-row.active,
    .chain-row.expanded {{
      background: color-mix(in srgb, var(--chain-color) 13%, rgba(255, 255, 255, 0.055));
      box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--chain-color) 42%, transparent);
    }}

    .chain-meta {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      min-width: 0;
    }}

    .chain-summary {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
      flex: 0 0 auto;
    }}

    .chain-name {{
      min-width: 0;
      display: flex;
      align-items: baseline;
      gap: 6px;
      overflow: hidden;
      white-space: nowrap;
      color: #fff2cf;
      font-weight: 750;
      font-size: 0.86rem;
    }}

    .chain-name-text {{
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      color: var(--quest-difficulty-color, #fff2cf);
    }}

    .chain-zone-summary,
    .quest-zone-summary {{
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      color: #a99b83;
      font-size: 0.72rem;
      font-weight: 650;
    }}

    .chain-zone-summary {{
      flex: 1 10 auto;
    }}

    .chain-level {{
      flex: 0 0 auto;
      padding: 3px 7px;
      border-radius: 999px;
      background: rgba(0, 0, 0, 0.25);
      color: #d9cbb2;
      border: 1px solid rgba(255, 255, 255, 0.11);
      font-size: 0.7rem;
    }}

    .chain-expander {{
      color: #a99b83;
      font-size: 0.7rem;
      font-weight: 750;
    }}

    .chain-track {{
      display: flex;
      align-items: center;
      gap: 8px;
      min-height: 34px;
      overflow-x: auto;
      overflow-y: hidden;
      padding: 3px 1px 5px;
      scrollbar-color: rgba(255, 255, 255, 0.22) transparent;
      scrollbar-width: thin;
    }}

    .chain-row.expanded .chain-track {{
      display: none;
    }}

    .chain-expanded {{
      display: grid;
      gap: 6px;
      padding-top: 7px;
      border-top: 1px solid rgba(255, 235, 196, 0.12);
    }}

    .chain-group-break {{
      height: 1px;
      margin: 5px 4px 4px 32px;
      background: linear-gradient(90deg, transparent, rgba(210, 202, 186, 0.32), transparent);
    }}

    .chain-quest-item {{
      display: grid;
      grid-template-columns: 28px minmax(0, 1fr) auto 20px;
      align-items: center;
      gap: 8px;
      width: 100%;
      min-height: 38px;
      padding: 5px 7px;
      border-radius: 6px;
      border: 1px solid rgba(255, 255, 255, 0.08);
      background: rgba(255, 255, 255, 0.045);
      color: #eadfc9;
      text-align: left;
      font: inherit;
      cursor: pointer;
    }}

    .chain-quest-item[role="button"] {{
      user-select: none;
    }}

    .chain-quest-item:hover,
    .chain-quest-item:focus-visible,
    .chain-quest-item.active {{
      outline: 2px solid #fff6cf;
      outline-offset: 1px;
      background: color-mix(in srgb, var(--chain-color) 14%, rgba(255, 255, 255, 0.055));
    }}

    .chain-quest-item.selected {{
      border-color: #ffd34f;
      box-shadow: inset 0 0 0 1px rgba(255, 211, 79, 0.5), 0 0 16px color-mix(in srgb, var(--chain-color) 34%, transparent);
    }}

    .chain-quest-item.outside-zone {{
      opacity: 0.48;
    }}

    .chain-quest-item.has-detail {{
      align-items: start;
    }}

    .chain-quest-step {{
      position: relative;
      display: grid;
      place-items: center;
      width: 24px;
      height: 24px;
      border-radius: 999px;
      border: 2px solid var(--chain-color);
      background: rgba(255, 245, 208, 0.9);
      color: #1f1606;
      font-size: 0.72rem;
      font-weight: 850;
    }}

    .chain-quest-main {{
      min-width: 0;
      display: grid;
      gap: 5px;
    }}

    .chain-quest-title {{
      min-width: 0;
      flex: 0 1 auto;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      color: var(--quest-difficulty-color, #fff2cf);
      font-size: 0.82rem;
      font-weight: 750;
    }}

    .chain-quest-title-row {{
      display: flex;
      align-items: baseline;
      gap: 6px;
      min-width: 0;
      overflow: hidden;
    }}

    .quest-wowhead-link {{
      display: inline-grid;
      place-items: center;
      width: 17px;
      height: 17px;
      align-self: center;
      justify-self: center;
      border-radius: 4px;
      color: #cdbf9f;
      opacity: 0.82;
      text-decoration: none;
    }}

    .quest-wowhead-link:hover,
    .quest-wowhead-link:focus-visible {{
      color: #fff2cf;
      opacity: 1;
      outline: 1px solid rgba(255, 211, 79, 0.5);
      outline-offset: 1px;
      background: rgba(255, 211, 79, 0.1);
    }}

    .quest-wowhead-link svg {{
      width: 13px;
      height: 13px;
      display: block;
      stroke: currentColor;
    }}

    .chain-quest-meta {{
      align-self: center;
      color: #a99b83;
      font-size: 0.72rem;
      white-space: nowrap;
    }}

    .chain-quest-detail {{
      grid-column: 2 / 5;
      display: grid;
      gap: 6px;
      margin-top: 3px;
      padding-top: 7px;
      border-top: 1px solid rgba(255, 235, 196, 0.13);
      color: #d9cbb2;
      font-size: 0.78rem;
      line-height: 1.35;
    }}

    .catalogue-detail-row {{
      display: grid;
      grid-template-columns: 94px minmax(0, 1fr);
      gap: 8px;
    }}

    .catalogue-detail-label {{
      color: #a99b83;
      font-size: 0.62rem;
      font-weight: 850;
      text-transform: uppercase;
      letter-spacing: 0;
      white-space: nowrap;
    }}

    .catalogue-objectives {{
      display: grid;
      gap: 4px;
      margin: 0;
      padding: 0;
      list-style: none;
    }}

    .catalogue-objectives li {{
      min-width: 0;
    }}

    .zone-link {{
      display: inline;
      min-height: 0;
      padding: 0;
      border: 0;
      border-radius: 0;
      background: transparent;
      color: #8fc7ff;
      font: inherit;
      font-weight: 800;
      text-decoration: underline;
      text-underline-offset: 2px;
      cursor: pointer;
    }}

    .zone-link:hover,
    .zone-link:focus-visible {{
      color: #d3ecff;
      outline: none;
    }}

    .quest-icon {{
      --size: 29px;
      position: relative;
      display: grid;
      place-items: center;
      flex: 0 0 auto;
      width: var(--size);
      height: var(--size);
      border: 2px solid var(--quest-icon-ring, var(--chain-color));
      border-radius: 999px;
      padding: 0;
      background:
        linear-gradient(rgba(0, 0, 0, 0.12), rgba(0, 0, 0, 0.32)),
        url("Questie/Icons/available.png") center / 92% 92% no-repeat,
        #211909;
      color: #1a1205;
      cursor: pointer;
      box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.72), 0 0 16px color-mix(in srgb, var(--quest-icon-ring, var(--chain-color)) 42%, transparent);
    }}

    .quest-icon::after {{
      content: "";
      position: absolute;
      inset: 3px;
      border-radius: inherit;
      background: rgba(255, 229, 121, 0.54);
      mix-blend-mode: screen;
    }}

    .quest-icon-step {{
      position: relative;
      z-index: 1;
      display: grid;
      place-items: center;
      min-width: 17px;
      height: 17px;
      border-radius: 999px;
      background: rgba(255, 245, 208, 0.92);
      color: #1f1606;
      font-size: 0.72rem;
      line-height: 1;
      font-weight: 850;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.45);
    }}

    .quest-icon:hover,
    .quest-icon:focus-visible,
    .quest-icon.active {{
      outline: 2px solid #fff6cf;
      outline-offset: 2px;
      z-index: 20;
    }}

    .quest-icon.selected {{
      outline-color: #ffd34f;
      box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.72), 0 0 20px rgba(255, 211, 79, 0.52);
    }}

    .quest-icon.outside-zone {{
      opacity: 0.38;
      filter: grayscale(0.45);
    }}

    .quest-icon.no-map {{
      border-style: dashed;
    }}

    .quest-icon[draggable="true"],
    .chain-quest-item[draggable="true"] {{
      cursor: grab;
    }}

    .quest-icon.dragging,
    .chain-quest-item.dragging {{
      opacity: 0.55;
      cursor: grabbing;
    }}

    .details {{
      min-height: 0;
      display: grid;
      grid-template-columns: minmax(320px, 0.56fr) minmax(360px, 0.74fr) minmax(0, 1.35fr);
      gap: 12px;
      padding: 12px 14px;
      overflow: hidden;
    }}

    .details h2 {{
      margin: 0 0 7px;
      font-size: clamp(1.15rem, 1.8vw, 1.55rem);
      line-height: 1.08;
      letter-spacing: 0;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }}

    .chain-pill {{
      display: inline-flex;
      align-items: center;
      gap: 8px;
      max-width: 100%;
      padding: 5px 9px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.06);
      color: #fff1c9;
      border: 1px solid color-mix(in srgb, var(--chain-color) 54%, rgba(255, 255, 255, 0.16));
      font-size: 0.86rem;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }}

    .chain-pill::before {{
      content: "";
      width: 10px;
      height: 10px;
      flex: 0 0 auto;
      border-radius: 999px;
      background: var(--chain-color);
      box-shadow: 0 0 12px var(--chain-color);
    }}

    .type-pills {{
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: 5px;
      margin-top: 7px;
    }}

    .type-pill {{
      display: inline-flex;
      align-items: center;
      min-height: 20px;
      padding: 2px 7px;
      border-radius: 999px;
      border: 1px solid rgba(255, 235, 196, 0.22);
      background: rgba(255, 255, 255, 0.06);
      color: #eadfc9;
      font-size: 0.72rem;
      line-height: 1;
    }}

    .body-copy {{
      color: var(--muted);
      line-height: 1.35;
      margin: 8px 0 0;
      font-size: 0.88rem;
    }}

    .meta-grid {{
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 7px;
      height: 100%;
      min-height: 0;
    }}

    .meta {{
      min-height: 0;
      padding: 8px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.055);
      border: 1px solid rgba(255, 255, 255, 0.08);
      overflow: hidden;
    }}

    .label {{
      display: block;
      margin-bottom: 3px;
      color: #a99b83;
      font-size: 0.66rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }}

    .value {{
      color: #fff3d4;
      font-size: 0.84rem;
      line-height: 1.28;
    }}

    .objective-panel {{
      min-height: 0;
      overflow: hidden;
    }}

    .objective-list {{
      height: 100%;
      overflow: auto;
      display: grid;
      align-content: start;
      gap: 6px;
      margin: 0;
      padding: 0;
      list-style: none;
    }}

    .objective-list li {{
      padding: 8px 10px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.055);
      color: #eadfc9;
      line-height: 1.34;
      font-size: 1rem;
      font-weight: 720;
    }}

    @media (max-width: 1100px) {{
      body {{
        overflow: auto;
      }}

      main {{
        height: auto;
        min-height: 100vh;
        grid-template-rows: auto minmax(660px, 1fr);
      }}

      header {{
        grid-template-columns: 1fr;
      }}

      .workbench {{
        grid-template-columns: 1fr;
      }}

      .meta-grid {{
        grid-template-columns: 1fr;
      }}
    }}
  </style>
</head>
<body>
  <main>
    <header>
      <div class="header-main">
        <h1 class="brand"><span class="brand-questie">Questie</span><span class="brand-plus">Plus</span></h1>
        <div class="toolbar">
          <div class="view-toggle" role="group" aria-label="Workspace view">
            <button type="button" id="map-view-button" class="active" aria-pressed="true">Map</button>
            <button type="button" id="sequencer-view-button" aria-pressed="false">Sequencer</button>
          </div>
          <button type="button" id="world-button">World</button>
          <select id="zone-select" aria-label="Zone"></select>
          <span class="toolbar-separator" aria-hidden="true"></span>
          <select id="race-filter" class="filter-select" aria-label="Race"></select>
          <select id="class-filter" class="filter-select" aria-label="Class"></select>
          <select id="level-filter" class="filter-select level-select" aria-label="Current level"></select>
          <span class="toolbar-separator" aria-hidden="true"></span>
          <div class="quest-filter-wrap" id="quest-filter-wrap">
            <button type="button" id="quest-filter-button" class="quest-filter-button" aria-expanded="false" aria-controls="quest-filter-menu">
              Quest filter <span class="filter-count" id="quest-filter-count"></span>
            </button>
            <div class="quest-filter-menu" id="quest-filter-menu" hidden></div>
          </div>
          <div class="zone-filter-wrap" id="zone-filter-wrap">
            <button type="button" id="zone-filter-button" class="zone-filter-button" aria-expanded="false" aria-controls="zone-filter-menu">
              Zone filter <span class="filter-count" id="zone-filter-count"></span>
            </button>
            <div class="zone-filter-menu" id="zone-filter-menu" hidden></div>
          </div>
          <div class="display-filter-wrap" id="display-filter-wrap">
            <button type="button" id="display-filter-button" class="display-filter-button" aria-expanded="false" aria-controls="display-filter-menu">
              Display <span class="filter-count" id="display-filter-count"></span>
            </button>
            <div class="display-filter-menu" id="display-filter-menu" hidden></div>
          </div>
        </div>
      </div>
      <div class="header-side">
        <div class="options-filter-wrap" id="options-filter-wrap">
          <button type="button" id="options-filter-button" class="options-filter-button" aria-expanded="false" aria-controls="options-filter-menu">
            Options <span class="filter-count" id="options-filter-count"></span>
          </button>
          <div class="options-filter-menu" id="options-filter-menu" hidden></div>
        </div>
        <div class="count">{quest_count} quests - {zone_count} zone maps</div>
      </div>
    </header>
    <section class="workbench">
      <section class="map-frame" aria-label="Quest map">
        <div class="map-mode-panel" id="map-mode-panel">
          <div class="map" id="map">
            <div class="map-title" id="map-title"></div>
            <div class="world-layer" id="world-layer"></div>
            <img class="zone-image" id="zone-image" alt="">
            <div class="veil"></div>
            <div id="map-marker-layer"></div>
            <div id="highlight-layer"></div>
            <div class="world-zone-tooltip" id="world-zone-tooltip" hidden></div>
          </div>
        </div>
        <div class="sequencer-panel" id="sequencer-panel" hidden>
          <div class="journey-global-actions">
            <button class="journey-import-button" id="journey-import-button" type="button">Import Journey</button>
            <input class="journey-import-input" id="journey-import-input" type="file" accept="application/json,.json">
          </div>
          <form class="journey-setup" id="journey-setup">
            <h2>Create a Journey</h2>
            <p>Name the plan and lock in the character race and class before sequencing quests.</p>
            <div class="journey-setup-grid">
              <div class="journey-field full">
                <label for="journey-name-input">Journey name</label>
                <input id="journey-name-input" type="text" autocomplete="off" placeholder="Darkshore 12-18">
              </div>
              <div class="journey-field">
                <label for="journey-race-select">Race</label>
                <select id="journey-race-select"></select>
              </div>
              <div class="journey-field">
                <label for="journey-class-select">Class</label>
                <select id="journey-class-select"></select>
              </div>
            </div>
            <button class="journey-start-button" id="journey-start-button" type="submit" disabled>Start Journey</button>
          </form>
          <div class="journey-workspace" id="journey-workspace" hidden>
            <div class="journey-head">
              <div class="journey-title-tools">
                <input class="journey-name-editor" id="journey-name-editor" type="text" aria-label="Journey name">
                <button class="journey-save-button" id="journey-save-button" type="button">Save Journey</button>
                <span class="journey-character-summary" id="journey-character-summary"></span>
              </div>
            </div>
            <div class="journey-message" id="journey-message" hidden></div>
            <div class="sequencer-board" id="sequencer-board" aria-label="Journey batches"></div>
          </div>
        </div>
      </section>
      <aside class="inventory" aria-label="Quest chain inventory">
        <div class="inventory-head">
          <div class="inventory-search">
            <input class="quest-search-input" id="quest-search" type="search" placeholder="Search quests" aria-label="Search quests">
            <button class="quest-search-clear" id="quest-search-clear" type="button" aria-label="Clear quest search" hidden>x</button>
          </div>
          <div class="inventory-actions" aria-label="Quest catalogue view controls">
            <button type="button" class="inventory-action" id="collapse-all-chains" aria-label="Collapse all quest chains" title="Collapse all quest chains">-</button>
            <button type="button" class="inventory-action" id="expand-all-chains" aria-label="Expand all quest chains" title="Expand all quest chains">+</button>
          </div>
        </div>
        <div class="chain-list" id="chain-list"></div>
      </aside>
    </section>
  </main>
  <script>
    const DATA = {payload};
    const QUEST_TYPE_FILTERS = DATA.questTypeFilters;
    const RACES = [
      {{ label: "All races", mask: null, color: "#fff0ce" }},
      {{ label: "Human", mask: 1, faction: "Alliance", color: "#5aa9ff" }},
      {{ label: "Dwarf", mask: 4, faction: "Alliance", color: "#5aa9ff" }},
      {{ label: "Night Elf", mask: 8, faction: "Alliance", color: "#5aa9ff" }},
      {{ label: "Gnome", mask: 64, faction: "Alliance", color: "#5aa9ff" }},
      {{ label: "Orc", mask: 2, faction: "Horde", color: "#ff6b5f" }},
      {{ label: "Undead", mask: 16, faction: "Horde", color: "#ff6b5f" }},
      {{ label: "Tauren", mask: 32, faction: "Horde", color: "#ff6b5f" }},
      {{ label: "Troll", mask: 128, faction: "Horde", color: "#ff6b5f" }},
    ];
    const CLASSES = [
      {{ label: "All classes", mask: null, color: "#fff0ce" }},
      {{ label: "Warrior", mask: 1, color: "#C79C6E" }},
      {{ label: "Paladin", mask: 2, color: "#F58CBA" }},
      {{ label: "Hunter", mask: 4, color: "#ABD473" }},
      {{ label: "Rogue", mask: 8, color: "#FFF569" }},
      {{ label: "Priest", mask: 16, color: "#FFFFFF" }},
      {{ label: "Shaman", mask: 64, color: "#0070DE" }},
      {{ label: "Mage", mask: 128, color: "#69CCF0" }},
      {{ label: "Warlock", mask: 256, color: "#9482C9" }},
      {{ label: "Druid", mask: 1024, color: "#FF7D0A" }},
    ];
    const filters = {{
      raceMask: null,
      classMask: null,
      level: null,
      search: "",
      typeIds: new Set(QUEST_TYPE_FILTERS.filter((filter) => filter.defaultEnabled).map((filter) => filter.id)),
      zoneIds: new Set(DATA.zones.filter((zone) => zone.questCount > 0).map((zone) => zone.id)),
    }};
    const DISPLAY_FILTERS = [
      {{ id: "available-pickups", label: "Available quest pickups", defaultEnabled: true }},
      {{ id: "quest-objectives", label: "All quest objectives", defaultEnabled: false }},
      {{ id: "quest-handins", label: "All quest hand-ins", defaultEnabled: false }},
    ];
    const displayFilters = new Set(DISPLAY_FILTERS.filter((filter) => filter.defaultEnabled).map((filter) => filter.id));
    const CATALOGUE_OPTIONS = [
      {{ id: "show-unused", label: "Show Unused quests", defaultEnabled: false }},
      {{ id: "show-assigned", label: "Show Assigned quests", defaultEnabled: true }},
    ];
    const catalogueOptions = new Set(CATALOGUE_OPTIONS.filter((option) => option.defaultEnabled).map((option) => option.id));
    const questsById = new Map(DATA.quests.map((quest) => [quest.id, quest]));
    const zonesById = new Map(DATA.zones.map((zone) => [zone.id, zone]));
    const zonesByName = new Map(DATA.zones.map((zone) => [zone.name, zone]));
    const chainsById = new Map(DATA.chains.map((chain) => [chain.id, {{ ...chain, quests: [] }}]));
    DATA.quests.forEach((quest) => {{
      if (!chainsById.has(quest.chainId)) {{
        chainsById.set(quest.chainId, {{
          id: quest.chainId,
          name: quest.chainName,
          color: quest.chainColor,
          count: 0,
          quests: [],
        }});
      }}
      chainsById.get(quest.chainId).quests.push(quest);
    }});
    chainsById.forEach((chain) => {{
      chain.quests.sort((a, b) => a.chainStep - b.chainStep || a.requiredLevel - b.requiredLevel || a.id - b.id);
      chain.firstQuest = chain.quests[0];
      chain.startLevel = chain.firstQuest?.requiredLevel ?? 0;
    }});

    const worldButton = document.querySelector("#world-button");
    const zoneSelect = document.querySelector("#zone-select");
    const raceFilter = document.querySelector("#race-filter");
    const classFilter = document.querySelector("#class-filter");
    const levelFilter = document.querySelector("#level-filter");
    const questFilterWrap = document.querySelector("#quest-filter-wrap");
    const questFilterButton = document.querySelector("#quest-filter-button");
    const questFilterCount = document.querySelector("#quest-filter-count");
    const questFilterMenu = document.querySelector("#quest-filter-menu");
    const zoneFilterWrap = document.querySelector("#zone-filter-wrap");
    const zoneFilterButton = document.querySelector("#zone-filter-button");
    const zoneFilterCount = document.querySelector("#zone-filter-count");
    const zoneFilterMenu = document.querySelector("#zone-filter-menu");
    const displayFilterWrap = document.querySelector("#display-filter-wrap");
    const displayFilterButton = document.querySelector("#display-filter-button");
    const displayFilterCount = document.querySelector("#display-filter-count");
    const displayFilterMenu = document.querySelector("#display-filter-menu");
    const optionsFilterWrap = document.querySelector("#options-filter-wrap");
    const optionsFilterButton = document.querySelector("#options-filter-button");
    const optionsFilterCount = document.querySelector("#options-filter-count");
    const optionsFilterMenu = document.querySelector("#options-filter-menu");
    const mapViewButton = document.querySelector("#map-view-button");
    const sequencerViewButton = document.querySelector("#sequencer-view-button");
    const mapFrame = document.querySelector(".map-frame");
    const mapModePanel = document.querySelector("#map-mode-panel");
    const sequencerPanel = document.querySelector("#sequencer-panel");
    const journeySetup = document.querySelector("#journey-setup");
    const journeyNameInput = document.querySelector("#journey-name-input");
    const journeyRaceSelect = document.querySelector("#journey-race-select");
    const journeyClassSelect = document.querySelector("#journey-class-select");
    const journeyStartButton = document.querySelector("#journey-start-button");
    const journeyWorkspace = document.querySelector("#journey-workspace");
    const journeyNameEditor = document.querySelector("#journey-name-editor");
    const journeySaveButton = document.querySelector("#journey-save-button");
    const journeyImportButton = document.querySelector("#journey-import-button");
    const journeyImportInput = document.querySelector("#journey-import-input");
    const journeyCharacterSummary = document.querySelector("#journey-character-summary");
    const journeyMessage = document.querySelector("#journey-message");
    const sequencerBoard = document.querySelector("#sequencer-board");
    const mapEl = document.querySelector("#map");
    const worldLayer = document.querySelector("#world-layer");
    const zoneImage = document.querySelector("#zone-image");
    const mapTitle = document.querySelector("#map-title");
    const markerLayer = document.querySelector("#map-marker-layer");
    const highlightLayer = document.querySelector("#highlight-layer");
    const worldZoneTooltip = document.querySelector("#world-zone-tooltip");
    const chainList = document.querySelector("#chain-list");
    const inventoryTitle = document.querySelector("#inventory-title");
    const questSearch = document.querySelector("#quest-search");
    const questSearchClear = document.querySelector("#quest-search-clear");
    const collapseAllChainsButton = document.querySelector("#collapse-all-chains");
    const expandAllChainsButton = document.querySelector("#expand-all-chains");
    const details = document.querySelector("#details");

    let currentView = {{ type: "world", zoneId: null }};
    let currentAppMode = "map";
    let activeId = null;
    let selectedId = null;
    let mapFitFrame = 0;
    let pickupPopoverCloseTimer = 0;
    let preDragAppMode = "map";
    let draggingQuestId = null;
    let draggingJourneyQuestId = null;
    const expandedChainIds = new Set();
    let activeJourney = null;
    let journeyBatchCounter = 0;
    let selectedBatchId = null;
    let preBatchLevelValue = null;
    let forcedCatalogueChainId = null;

    function fitMapToFrame() {{
      if (currentAppMode !== "map" || mapModePanel.hidden) return;
      const frame = mapFrame.getBoundingClientRect();
      const aspect = 3 / 2;
      if (!frame.width || !frame.height) return;
      let width = frame.width;
      let height = width / aspect;
      if (height > frame.height) {{
        height = frame.height;
        width = height * aspect;
      }}
      mapEl.style.width = `${{Math.floor(width)}}px`;
      mapEl.style.height = `${{Math.floor(height)}}px`;
      renderAvailablePickupMarkers();
      const quest = activeId == null ? null : questsById.get(activeId);
      if (quest) renderOverlay(quest);
    }}

    function scheduleMapFit() {{
      cancelAnimationFrame(mapFitFrame);
      mapFitFrame = requestAnimationFrame(fitMapToFrame);
    }}

    function setAppMode(mode) {{
      const normalized = mode === "sequencer" ? "sequencer" : "map";
      currentAppMode = normalized;
      const isMap = normalized === "map";
      mapViewButton.classList.toggle("active", isMap);
      sequencerViewButton.classList.toggle("active", !isMap);
      mapViewButton.setAttribute("aria-pressed", String(isMap));
      sequencerViewButton.setAttribute("aria-pressed", String(!isMap));
      mapModePanel.hidden = !isMap;
      sequencerPanel.hidden = isMap;
      mapFrame.setAttribute("aria-label", isMap ? "Quest map" : "Quest sequencer");
      if (isMap) {{
        scheduleMapFit();
      }} else {{
        closePickupQuestList();
        hideWorldZoneTooltip();
      }}
    }}

    function journeyRaceOptions() {{
      return RACES.filter((race) => race.mask != null);
    }}

    function journeyClassOptions() {{
      return CLASSES.filter((klass) => klass.mask != null);
    }}

    function populateJourneySetupControls() {{
      journeyRaceSelect.innerHTML = '<option value="">Select race</option>' + journeyRaceOptions().map((race) => `
        <option value="${{race.mask}}" style="color:${{race.color}}">${{escapeHtml(race.label)}}</option>
      `).join("");
      journeyClassSelect.innerHTML = '<option value="">Select class</option>' + journeyClassOptions().map((klass) => `
        <option value="${{klass.mask}}" style="color:${{klass.color}}">${{escapeHtml(klass.label)}}</option>
      `).join("");
      updateJourneyStartButton();
    }}

    function updateJourneyStartButton() {{
      journeyStartButton.disabled = !journeyNameInput.value.trim() || !journeyRaceSelect.value || !journeyClassSelect.value;
    }}

    function newBatch(name = null, questIds = [], options = {{}}) {{
      journeyBatchCounter += 1;
      const override = options.expectedLevelOverride ?? options.levelOverride ?? null;
      return {{
        id: options.id || `batch-${{Date.now().toString(36)}}-${{journeyBatchCounter.toString(36)}}`,
        name: name ?? String(journeyBatchCounter),
        questIds: [...questIds],
        expectedLevelOverride: override == null || override === "" ? null : Number(override),
      }};
    }}

    function selectedJourneyRace() {{
      return journeyRaceOptions().find((race) => String(race.mask) === String(activeJourney?.raceMask));
    }}

    function selectedJourneyClass() {{
      return journeyClassOptions().find((klass) => String(klass.mask) === String(activeJourney?.classMask));
    }}

    function createJourneyFromSetup() {{
      const race = journeyRaceOptions().find((item) => String(item.mask) === journeyRaceSelect.value);
      const klass = journeyClassOptions().find((item) => String(item.mask) === journeyClassSelect.value);
      const name = journeyNameInput.value.trim();
      if (!name || !race || !klass) return;
      journeyBatchCounter = 0;
      activeJourney = {{
        schemaVersion: 1,
        id: slugify(name) || `journey-${{Date.now().toString(36)}}`,
        name,
        race: race.label,
        raceMask: race.mask,
        faction: race.faction,
        class: klass.label,
        classMask: klass.mask,
        batches: [newBatch("1")],
        unusedQuestIds: [],
      }};
      selectedBatchId = null;
      preBatchLevelValue = null;
      forcedCatalogueChainId = null;
      raceFilter.value = String(race.mask);
      classFilter.value = String(klass.mask);
      updateFiltersFromControls();
      renderJourney();
      showJourneyMessage("Journey created. Drag quests into Batch 1 to begin.", "ok");
    }}

    function slugify(value) {{
      return String(value || "")
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "");
    }}

    function cloneBatches(batches = activeJourney?.batches || []) {{
      return batches.map((batch) => ({{
        ...batch,
        questIds: [...batch.questIds],
        expectedLevelOverride: batch.expectedLevelOverride == null ? null : Number(batch.expectedLevelOverride),
      }}));
    }}

    function cloneUnusedQuestIds(ids = activeJourney?.unusedQuestIds || []) {{
      return [...new Set((ids || [])
        .map((id) => Number(id))
        .filter((id) => Number.isFinite(id) && questsById.has(id)))];
    }}

    function batchQuests(batch) {{
      return (batch?.questIds || []).map((id) => questsById.get(Number(id))).filter(Boolean);
    }}

    function computedBatchExpectedLevel(batch) {{
      const override = Number(batch?.expectedLevelOverride);
      if (Number.isFinite(override) && override > 0) return Math.max(1, Math.min(60, Math.round(override)));
      const levels = batchQuests(batch)
        .map((quest) => Number(quest.questLevel ?? quest.requiredLevel))
        .filter((level) => Number.isFinite(level) && level > 0);
      if (!levels.length) return null;
      return Math.max(1, Math.min(60, Math.round(levels.reduce((sum, level) => sum + level, 0) / levels.length)));
    }}

    function batchZoneNames(batch) {{
      const names = [];
      batchQuests(batch).forEach((quest) => {{
        questInvolvedZoneNames(quest).forEach((zoneName) => {{
          if (!names.includes(zoneName)) names.push(zoneName);
        }});
      }});
      return names;
    }}

    function batchZoneSummary(batch) {{
      const zones = batchZoneNames(batch);
      return zones.length ? zones.join(", ") : "No zones yet";
    }}

    function normalizeExpectedLevel(value) {{
      const level = Number(value);
      if (!Number.isFinite(level) || level <= 0) return null;
      return Math.max(1, Math.min(60, Math.round(level)));
    }}

    function renumberNumericBatches(batches) {{
      batches.forEach((batch, index) => {{
        if (!batch.name || /^\\d+$/.test(String(batch.name))) batch.name = String(index + 1);
      }});
    }}

    function allJourneyQuestIds(batches = activeJourney?.batches || []) {{
      const ids = new Set();
      batches.forEach((batch) => batch.questIds.forEach((id) => ids.add(Number(id))));
      return ids;
    }}

    function assignedJourneyQuestIds() {{
      return allJourneyQuestIds();
    }}

    function unusedJourneyQuestIds() {{
      return new Set(cloneUnusedQuestIds(activeJourney?.unusedQuestIds || []));
    }}

    function findQuestBatchIndex(questId, batches = activeJourney?.batches || []) {{
      const id = Number(questId);
      return batches.findIndex((batch) => batch.questIds.some((item) => Number(item) === id));
    }}

    function removeQuestFromBatchCopies(batches, questId) {{
      const id = Number(questId);
      batches.forEach((batch) => {{
        batch.questIds = batch.questIds.filter((item) => Number(item) !== id);
      }});
    }}

    function removeQuestFromUnusedCopies(unusedQuestIds, questId) {{
      const id = Number(questId);
      return cloneUnusedQuestIds(unusedQuestIds).filter((item) => Number(item) !== id);
    }}

    function questAllowedForJourney(quest) {{
      if (!activeJourney) return {{ ok: false, message: "Create a Journey before adding quests." }};
      if (!quest) return {{ ok: false, message: "Unknown quest." }};
      if (quest.requiredRaceMask && !(quest.requiredRaceMask & activeJourney.raceMask)) {{
        return {{ ok: false, message: `${{quest.name}} is not available to a ${{activeJourney.race}}.` }};
      }}
      if (quest.requiredClassMask && !(quest.requiredClassMask & activeJourney.classMask)) {{
        return {{ ok: false, message: `${{quest.name}} is not available to a ${{activeJourney.class}}.` }};
      }}
      return {{ ok: true }};
    }}

    function questName(id) {{
      const quest = questsById.get(Number(id));
      return quest ? `${{quest.name}} (#${{quest.id}})` : `#${{id}}`;
    }}

    function questNames(ids) {{
      return ids.map(questName).join(", ");
    }}

    function questPrerequisiteFailure(quest, availableIds) {{
      const groupPrereqs = (quest.preQuestGroup || []).map(Number).filter(Boolean);
      const singlePrereqs = (quest.preQuestSingle || []).map(Number).filter(Boolean);
      const missingGroup = groupPrereqs.filter((id) => !availableIds.has(id));
      if (missingGroup.length) {{
        return `${{quest.name}} requires ${{questNames(missingGroup)}} in the same or an earlier batch.`;
      }}
      if (singlePrereqs.length && !singlePrereqs.some((id) => availableIds.has(id))) {{
        if (singlePrereqs.length === 1) {{
          return `${{quest.name}} requires ${{questName(singlePrereqs[0])}} in the same or an earlier batch.`;
        }}
        return `${{quest.name}} requires one of: ${{questNames(singlePrereqs)}} in the same or an earlier batch.`;
      }}
      return "";
    }}

    function validateJourneyBatches(batches) {{
      for (const batch of batches) {{
        const seen = new Set();
        for (const questId of batch.questIds) {{
          if (seen.has(Number(questId))) {{
            return {{ ok: false, message: `Batch "${{batch.name}}" contains a duplicate quest.` }};
          }}
          seen.add(Number(questId));
        }}
      }}
      const allIds = allJourneyQuestIds(batches);
      if (allIds.size !== batches.reduce((sum, batch) => sum + batch.questIds.length, 0)) {{
        return {{ ok: false, message: "That quest is already in this Journey. Drag it from its current batch to move it." }};
      }}
      for (let index = 0; index < batches.length; index += 1) {{
        const availableIds = new Set();
        for (let batchIndex = 0; batchIndex <= index; batchIndex += 1) {{
          batches[batchIndex].questIds.forEach((questId) => availableIds.add(Number(questId)));
        }}
        for (const questId of batches[index].questIds) {{
          const quest = questsById.get(Number(questId));
          if (!quest) return {{ ok: false, message: `Unknown quest #${{questId}} in Batch ${{index + 1}}.` }};
          const availability = questAllowedForJourney(quest);
          if (!availability.ok) return availability;
          const prerequisiteMessage = questPrerequisiteFailure(quest, availableIds);
          if (prerequisiteMessage) return {{ ok: false, message: prerequisiteMessage }};
        }}
      }}
      return {{ ok: true }};
    }}

    function renderJourney() {{
      const hasJourney = Boolean(activeJourney);
      journeySetup.hidden = hasJourney;
      journeyWorkspace.hidden = !hasJourney;
      journeySaveButton.disabled = !hasJourney;
      journeyImportButton.disabled = false;
      if (!hasJourney) return;
      journeyNameEditor.value = activeJourney.name;
      const race = selectedJourneyRace();
      const klass = selectedJourneyClass();
      journeyCharacterSummary.textContent = [race?.label, klass?.label].filter(Boolean).join(" ");
      sequencerBoard.innerHTML = "";
      activeJourney.batches.forEach((batch, index) => {{
        sequencerBoard.append(createJourneyBatchElement(batch, index));
        sequencerBoard.append(createJourneyInsertElement(index + 1));
      }});
      sequencerBoard.append(createUnusedColumnElement());
    }}

    function createJourneyBatchElement(batch, index) {{
      const batchEl = document.createElement("section");
      batchEl.className = "journey-batch";
      if (selectedBatchId === batch.id) batchEl.classList.add("selected");
      batchEl.dataset.batchId = batch.id;
      batchEl.dataset.batchIndex = index;
      const expectedLevel = computedBatchExpectedLevel(batch);
      batchEl.innerHTML = `
        <div class="journey-batch-head" data-batch-id="${{escapeHtml(batch.id)}}" data-batch-index="${{index}}">
          <div class="batch-title-row">
            <input class="batch-name-input" value="${{escapeHtml(batch.name || String(index + 1))}}" aria-label="Batch ${{index + 1}} name">
            <label class="batch-level-control">
              <span>Lv</span>
              <input class="batch-level-input" type="number" min="1" max="60" value="${{expectedLevel ?? ""}}" placeholder="-" aria-label="Batch ${{index + 1}} expected level">
            </label>
          </div>
          <div class="batch-zone-summary" title="${{escapeHtml(batchZoneSummary(batch))}}">${{escapeHtml(batchZoneSummary(batch))}}</div>
        </div>
        <div class="journey-batch-drop" data-batch-index="${{index}}" aria-label="Batch ${{index + 1}} quest drop area"></div>
      `;
      const input = batchEl.querySelector(".batch-name-input");
      input.addEventListener("input", () => {{
        batch.name = input.value || String(index + 1);
      }});
      const levelInput = batchEl.querySelector(".batch-level-input");
      levelInput.addEventListener("input", () => {{
        batch.expectedLevelOverride = normalizeExpectedLevel(levelInput.value);
        if (selectedBatchId === batch.id) applySelectedBatchLevel();
      }});
      const drop = batchEl.querySelector(".journey-batch-drop");
      if (!batch.questIds.length) {{
        const empty = document.createElement("div");
        empty.className = "batch-empty";
        empty.textContent = "Drop quests into this batch.";
        drop.append(empty);
      }} else {{
        batch.questIds.forEach((questId) => {{
          const quest = questsById.get(Number(questId));
          if (quest) drop.append(createJourneyQuestElement(quest, batch.id));
        }});
      }}
      return batchEl;
    }}

    function createUnusedColumnElement() {{
      const unusedIds = cloneUnusedQuestIds(activeJourney?.unusedQuestIds || []);
      const batchEl = document.createElement("section");
      batchEl.className = "journey-batch unused";
      batchEl.dataset.batchId = "unused";
      const unusedBatch = {{ id: "unused", name: "Unused", questIds: unusedIds }};
      batchEl.innerHTML = `
        <div class="journey-batch-head">
          <div class="batch-title-row">
            <div class="batch-name-input" role="heading" aria-level="3">Unused</div>
          </div>
          <div class="batch-zone-summary" title="${{escapeHtml(batchZoneSummary(unusedBatch))}}">${{escapeHtml(batchZoneSummary(unusedBatch))}}</div>
        </div>
        <div class="journey-batch-drop journey-unused-drop" aria-label="Unused quest drop area"></div>
      `;
      const drop = batchEl.querySelector(".journey-unused-drop");
      if (!unusedIds.length) {{
        const empty = document.createElement("div");
        empty.className = "batch-empty";
        empty.textContent = "Drop quests here to mark them Unused.";
        drop.append(empty);
      }} else {{
        unusedIds.forEach((questId) => {{
          const quest = questsById.get(Number(questId));
          if (quest) drop.append(createJourneyQuestElement(quest, "unused", {{ unused: true }}));
        }});
      }}
      return batchEl;
    }}

    function createJourneyInsertElement(insertIndex) {{
      const slot = document.createElement("div");
      slot.className = "journey-insert-slot";
      slot.innerHTML = `
        <button class="journey-insert-target" type="button" data-insert-index="${{insertIndex}}" aria-label="Insert batch at position ${{insertIndex + 1}}">+</button>
      `;
      return slot;
    }}

    function createJourneyQuestElement(quest, batchId, options = {{}}) {{
      const item = document.createElement("div");
      item.className = "journey-quest";
      if (options.unused) item.classList.add("unused");
      if (selectedId === quest.id) item.classList.add("selected");
      if (activeId === quest.id) item.classList.add("active");
      item.draggable = true;
      item.dataset.questId = quest.id;
      item.dataset.batchId = batchId;
      item.style.setProperty("--chain-color", quest.chainColor);
      item.innerHTML = `
        <span class="journey-quest-step">${{quest.chainStep}}</span>
        <span class="journey-quest-name" ${{questDifficultyAttrs(quest)}}>${{escapeHtml(quest.name)}}</span>
        <span class="journey-quest-level">${{quest.requiredLevel ?? "?"}} / ${{quest.questLevel ?? "?"}}</span>
        ${{options.unused
          ? `<button class="journey-quest-unhide" type="button" aria-label="Unhide ${{escapeHtml(quest.name)}}">Unhide</button>`
          : `<button class="journey-quest-remove" type="button" aria-label="Remove ${{escapeHtml(quest.name)}} from Journey">x</button>`}}
      `;
      return item;
    }}

    function selectedBatch() {{
      if (!activeJourney || !selectedBatchId) return null;
      return activeJourney.batches.find((batch) => batch.id === selectedBatchId) || null;
    }}

    function applyLevelFilterValue(value) {{
      levelFilter.value = value == null ? "all" : String(value);
      filters.level = levelFilter.value === "all" ? null : Number(levelFilter.value);
      updateFilterSelectColors();
      renderCurrentView();
    }}

    function applySelectedBatchLevel() {{
      const batch = selectedBatch();
      if (!batch) return;
      const level = computedBatchExpectedLevel(batch);
      applyLevelFilterValue(level ?? "all");
    }}

    function selectJourneyBatch(batchId) {{
      if (!activeJourney) return;
      const batch = activeJourney.batches.find((item) => item.id === batchId);
      if (!batch) return;
      if (selectedBatchId == null) preBatchLevelValue = levelFilter.value;
      selectedBatchId = batch.id;
      renderJourney();
      applySelectedBatchLevel();
    }}

    function deselectJourneyBatch(options = {{}}) {{
      if (selectedBatchId == null) return;
      const restoreLevel = options.restoreLevel !== false;
      const previousLevel = preBatchLevelValue;
      selectedBatchId = null;
      preBatchLevelValue = null;
      renderJourney();
      if (restoreLevel) applyLevelFilterValue(previousLevel || "all");
    }}

    function showJourneyMessage(message, type = "error") {{
      if (!message) {{
        journeyMessage.hidden = true;
        journeyMessage.textContent = "";
        journeyMessage.className = "journey-message";
        return;
      }}
      journeyMessage.hidden = false;
      journeyMessage.textContent = message;
      journeyMessage.className = `journey-message ${{type === "ok" ? "ok" : ""}}`;
    }}

    function commitJourneyBatches(candidateBatches, successMessage = "") {{
      const validation = validateJourneyBatches(candidateBatches);
      if (!validation.ok) {{
        showJourneyMessage(validation.message);
        return false;
      }}
      activeJourney.batches = candidateBatches;
      renumberNumericBatches(activeJourney.batches);
      renderJourney();
      if (selectedBatchId != null) applySelectedBatchLevel();
      else renderCurrentView();
      showJourneyMessage(successMessage, successMessage ? "ok" : "error");
      if (!successMessage) showJourneyMessage("");
      return true;
    }}

    function moveQuestToBatch(questId, targetBatchIndex) {{
      if (!activeJourney) {{
        showJourneyMessage("Create a Journey before adding quests.");
        return false;
      }}
      const quest = questsById.get(Number(questId));
      const availability = questAllowedForJourney(quest);
      if (!availability.ok) {{
        showJourneyMessage(availability.message);
        return false;
      }}
      const candidate = cloneBatches();
      const existingIndex = findQuestBatchIndex(questId, candidate);
      if (existingIndex >= 0 && draggingJourneyQuestId == null) {{
        showJourneyMessage(`${{quest.name}} is already in Batch ${{existingIndex + 1}}. Drag it from that batch to move it.`);
        return false;
      }}
      removeQuestFromBatchCopies(candidate, questId);
      const target = candidate[targetBatchIndex];
      if (!target) return false;
      target.questIds.push(Number(questId));
      const moved = commitJourneyBatches(candidate, `${{quest.name}} added to Batch ${{targetBatchIndex + 1}}.`);
      if (moved) {{
        activeJourney.unusedQuestIds = removeQuestFromUnusedCopies(activeJourney.unusedQuestIds, questId);
        renderJourney();
        renderCurrentView();
      }}
      return moved;
    }}

    function insertBatchAt(insertIndex, questId = null) {{
      if (!activeJourney) {{
        showJourneyMessage("Create a Journey before adding batches.");
        return false;
      }}
      const candidate = cloneBatches();
      const batch = newBatch(String(insertIndex + 1), []);
      if (questId != null) {{
        const quest = questsById.get(Number(questId));
        const availability = questAllowedForJourney(quest);
        if (!availability.ok) {{
          showJourneyMessage(availability.message);
          return false;
        }}
        const existingIndex = findQuestBatchIndex(questId, candidate);
        if (existingIndex >= 0 && draggingJourneyQuestId == null) {{
          showJourneyMessage(`${{quest.name}} is already in Batch ${{existingIndex + 1}}. Drag it from that batch to move it.`);
          return false;
        }}
        removeQuestFromBatchCopies(candidate, questId);
        batch.questIds.push(Number(questId));
      }}
      candidate.splice(insertIndex, 0, batch);
      const inserted = commitJourneyBatches(candidate, questId == null ? `Batch ${{insertIndex + 1}} created.` : `Batch ${{insertIndex + 1}} created.`);
      if (inserted && questId != null) {{
        activeJourney.unusedQuestIds = removeQuestFromUnusedCopies(activeJourney.unusedQuestIds, questId);
        renderJourney();
        renderCurrentView();
      }}
      return inserted;
    }}

    function removeQuestFromJourney(questId) {{
      if (!activeJourney) return;
      const quest = questsById.get(Number(questId));
      const candidate = cloneBatches();
      removeQuestFromBatchCopies(candidate, questId);
      const validation = validateJourneyBatches(candidate);
      if (!validation.ok) {{
        showJourneyMessage(`Cannot remove ${{questName(questId)}}. ${{validation.message}}`);
        return;
      }}
      activeJourney.batches = candidate;
      renderJourney();
      if (selectedBatchId != null) applySelectedBatchLevel();
      else renderCurrentView();
      showJourneyMessage(`${{quest?.name || questName(questId)}} removed from Journey.`, "ok");
    }}

    function moveQuestToUnused(questId) {{
      if (!activeJourney) {{
        showJourneyMessage("Create a Journey before marking quests Unused.");
        return false;
      }}
      const quest = questsById.get(Number(questId));
      if (!quest) {{
        showJourneyMessage("Unknown quest.");
        return false;
      }}
      const candidate = cloneBatches();
      removeQuestFromBatchCopies(candidate, questId);
      const validation = validateJourneyBatches(candidate);
      if (!validation.ok) {{
        showJourneyMessage(`Cannot mark ${{quest.name}} Unused. ${{validation.message}}`);
        return false;
      }}
      activeJourney.batches = candidate;
      const unused = removeQuestFromUnusedCopies(activeJourney.unusedQuestIds, questId);
      unused.push(Number(questId));
      activeJourney.unusedQuestIds = unused;
      renumberNumericBatches(activeJourney.batches);
      renderJourney();
      if (selectedBatchId != null) applySelectedBatchLevel();
      else renderCurrentView();
      showJourneyMessage(`${{quest.name}} marked Unused.`, "ok");
      return true;
    }}

    function restoreUnusedQuest(questId) {{
      if (!activeJourney) return;
      const quest = questsById.get(Number(questId));
      activeJourney.unusedQuestIds = removeQuestFromUnusedCopies(activeJourney.unusedQuestIds, questId);
      renderJourney();
      renderCurrentView();
      showJourneyMessage(`${{quest?.name || questName(questId)}} restored to the catalogue.`, "ok");
    }}

    function journeyExportData() {{
      if (!activeJourney) return null;
      return {{
        schemaVersion: 1,
        app: "QuestiePlus",
        kind: "Journey",
        savedAt: new Date().toISOString(),
        id: activeJourney.id,
        name: activeJourney.name,
        character: {{
          race: activeJourney.race,
          raceMask: activeJourney.raceMask,
          faction: activeJourney.faction,
          class: activeJourney.class,
          classMask: activeJourney.classMask,
        }},
        unusedQuestIds: cloneUnusedQuestIds(activeJourney.unusedQuestIds),
        unusedQuests: cloneUnusedQuestIds(activeJourney.unusedQuestIds).map((questId) => {{
          const quest = questsById.get(Number(questId));
          return {{
            id: Number(questId),
            name: quest?.name || "",
            requiredLevel: quest?.requiredLevel ?? null,
            questLevel: quest?.questLevel ?? null,
            unused: true,
          }};
        }}),
        batches: activeJourney.batches.map((batch, index) => ({{
          id: batch.id,
          name: batch.name || String(index + 1),
          expectedLevel: computedBatchExpectedLevel(batch),
          expectedLevelManual: batch.expectedLevelOverride != null,
          expectedLevelOverride: batch.expectedLevelOverride ?? null,
          zones: batchZoneNames(batch),
          questIds: batch.questIds.map(Number),
          quests: batch.questIds.map((questId) => {{
            const quest = questsById.get(Number(questId));
            return {{
              id: Number(questId),
              name: quest?.name || "",
              requiredLevel: quest?.requiredLevel ?? null,
              questLevel: quest?.questLevel ?? null,
            }};
          }}),
        }})),
      }};
    }}

    function saveJourneyJson() {{
      if (!activeJourney) return;
      activeJourney.name = journeyNameEditor.value.trim() || activeJourney.name;
      renderJourney();
      const data = journeyExportData();
      const blob = new Blob([JSON.stringify(data, null, 2)], {{ type: "application/json" }});
      const link = document.createElement("a");
      const url = URL.createObjectURL(blob);
      link.href = url;
      link.download = `${{slugify(activeJourney.name) || "questieplus-journey"}}.json`;
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      showJourneyMessage("Journey JSON exported.", "ok");
    }}

    function raceFromImportedJourney(data) {{
      const character = data.character || {{}};
      const raceMask = Number(character.raceMask ?? data.raceMask);
      const byMask = journeyRaceOptions().find((race) => race.mask === raceMask);
      if (byMask) return byMask;
      const raceName = String(character.race || data.race || "").toLowerCase();
      return journeyRaceOptions().find((race) => race.label.toLowerCase() === raceName) || null;
    }}

    function classFromImportedJourney(data) {{
      const character = data.character || {{}};
      const classMask = Number(character.classMask ?? data.classMask);
      const byMask = journeyClassOptions().find((klass) => klass.mask === classMask);
      if (byMask) return byMask;
      const className = String(character.class || data.class || "").toLowerCase();
      return journeyClassOptions().find((klass) => klass.label.toLowerCase() === className) || null;
    }}

    function questIdsFromImportedBatch(batch) {{
      const ids = Array.isArray(batch.questIds)
        ? batch.questIds
        : Array.isArray(batch.quests)
          ? batch.quests.map((quest) => typeof quest === "number" ? quest : quest?.id)
          : [];
      return ids
        .map((id) => Number(id))
        .filter((id, index, list) => Number.isFinite(id) && questsById.has(id) && list.indexOf(id) === index);
    }}

    function questIdsFromImportedUnused(data) {{
      const ids = Array.isArray(data.unusedQuestIds)
        ? data.unusedQuestIds
        : Array.isArray(data.unused?.questIds)
          ? data.unused.questIds
          : Array.isArray(data.unusedQuests)
            ? data.unusedQuests.map((quest) => typeof quest === "number" ? quest : quest?.id)
            : [];
      return ids
        .map((id) => Number(id))
        .filter((id, index, list) => Number.isFinite(id) && questsById.has(id) && list.indexOf(id) === index);
    }}

    function importedBatchLevelOverride(batch) {{
      if (batch.expectedLevelManual === false) return null;
      return normalizeExpectedLevel(batch.expectedLevelOverride ?? batch.levelOverride ?? (batch.expectedLevelManual ? batch.expectedLevel : null));
    }}

    function importJourneyData(data) {{
      if (!data || typeof data !== "object") {{
        showJourneyMessage("Import failed: invalid Journey JSON.");
        return false;
      }}
      const name = String(data.name || "").trim();
      const race = raceFromImportedJourney(data);
      const klass = classFromImportedJourney(data);
      if (!name || !race || !klass) {{
        showJourneyMessage("Import failed: Journey must include a name, race, and class.");
        return false;
      }}
      const rawBatches = Array.isArray(data.batches) && data.batches.length ? data.batches : [{{ name: "1", questIds: [] }}];
      const unusedQuestIds = questIdsFromImportedUnused(data);
      journeyBatchCounter = 0;
      const importedJourney = {{
        schemaVersion: Number(data.schemaVersion) || 1,
        id: String(data.id || slugify(name) || `journey-${{Date.now().toString(36)}}`),
        name,
        race: race.label,
        raceMask: race.mask,
        faction: race.faction,
        class: klass.label,
        classMask: klass.mask,
        batches: rawBatches.map((batch, index) => newBatch(
          String(batch.name || index + 1),
          questIdsFromImportedBatch(batch).filter((questId) => !unusedQuestIds.includes(Number(questId))),
          {{
            id: batch.id ? String(batch.id) : null,
            expectedLevelOverride: importedBatchLevelOverride(batch),
          }},
        )),
        unusedQuestIds,
      }};
      const previousJourney = activeJourney;
      activeJourney = importedJourney;
      const validation = validateJourneyBatches(importedJourney.batches);
      if (!validation.ok) {{
        activeJourney = previousJourney;
        renderJourney();
        showJourneyMessage(`Import failed: ${{validation.message}}`);
        return false;
      }}
      selectedBatchId = null;
      preBatchLevelValue = null;
      forcedCatalogueChainId = null;
      raceFilter.value = String(race.mask);
      classFilter.value = String(klass.mask);
      updateFiltersFromControls();
      renderJourney();
      showJourneyMessage(`Imported Journey "${{name}}".`, "ok");
      return true;
    }}

    async function importJourneyFile(file) {{
      if (!file) return;
      try {{
        const text = await file.text();
        importJourneyData(JSON.parse(text));
      }} catch (error) {{
        showJourneyMessage(`Import failed: ${{error.message}}`);
      }}
    }}

    function handleCatalogueDragStart(event) {{
      const questNode = event.target.closest(".quest-icon, .chain-quest-item");
      if (!questNode || !chainList.contains(questNode)) return;
      if (event.target.closest(".zone-link, .quest-wowhead-link")) {{
        event.preventDefault();
        return;
      }}
      const quest = questsById.get(Number(questNode.dataset.questId));
      if (!quest || !event.dataTransfer) return;
      preDragAppMode = currentAppMode;
      if (!activeJourney) {{
        if (currentAppMode === "map") setAppMode("sequencer");
        showJourneyMessage("Create a Journey before adding quests.");
        event.preventDefault();
        return;
      }}
      draggingQuestId = quest.id;
      draggingJourneyQuestId = null;
      event.dataTransfer.effectAllowed = "copy";
      event.dataTransfer.setData("text/plain", String(quest.id));
      event.dataTransfer.setData("application/x-questieplus-quest", String(quest.id));
      event.dataTransfer.setData("application/x-questieplus-source", "catalogue");
      questNode.classList.add("dragging");
      document.body.classList.add("dragging-quest");
      if (currentAppMode === "map") setAppMode("sequencer");
    }}

    function handleJourneyDragStart(event) {{
      const questNode = event.target.closest(".journey-quest");
      if (!questNode || !sequencerBoard.contains(questNode)) return;
      if (event.target.closest(".journey-quest-remove, .journey-quest-unhide")) {{
        event.preventDefault();
        return;
      }}
      const quest = questsById.get(Number(questNode.dataset.questId));
      if (!quest || !event.dataTransfer) return;
      preDragAppMode = currentAppMode;
      draggingQuestId = quest.id;
      draggingJourneyQuestId = quest.id;
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", String(quest.id));
      event.dataTransfer.setData("application/x-questieplus-quest", String(quest.id));
      event.dataTransfer.setData("application/x-questieplus-source", "journey");
      questNode.classList.add("dragging");
      document.body.classList.add("dragging-quest");
    }}

    function handleCatalogueDragEnd() {{
      document.querySelectorAll(".quest-icon.dragging, .chain-quest-item.dragging, .journey-quest.dragging").forEach((element) => element.classList.remove("dragging"));
      document.body.classList.remove("dragging-quest");
      clearSequencerDragTargets();
      const shouldRestoreMap = preDragAppMode === "map";
      draggingQuestId = null;
      draggingJourneyQuestId = null;
      preDragAppMode = currentAppMode;
      if (shouldRestoreMap) setAppMode("map");
    }}

    function activeSequencerDropTarget(event) {{
      return event.target.closest(".journey-batch-drop, .journey-insert-target, .journey-unused-drop");
    }}

    function clearSequencerDragTargets() {{
      sequencerBoard.querySelectorAll(".drag-over").forEach((element) => element.classList.remove("drag-over"));
    }}

    function handleSequencerDragOver(event) {{
      if (draggingQuestId == null) return;
      const target = activeSequencerDropTarget(event);
      if (!target) return;
      event.preventDefault();
      clearSequencerDragTargets();
      if (event.dataTransfer) event.dataTransfer.dropEffect = draggingJourneyQuestId == null ? "copy" : "move";
      target.classList.add("drag-over");
    }}

    function handleSequencerDragLeave(event) {{
      const target = activeSequencerDropTarget(event);
      if (!target) return;
      if (event.relatedTarget && target.contains(event.relatedTarget)) return;
      target.classList.remove("drag-over");
    }}

    function handleSequencerDrop(event) {{
      if (draggingQuestId == null && !event.dataTransfer) return;
      const target = activeSequencerDropTarget(event);
      if (!target) return;
      event.preventDefault();
      const rawQuestId = event.dataTransfer?.getData("application/x-questieplus-quest")
        || event.dataTransfer?.getData("text/plain")
        || String(draggingQuestId ?? "");
      clearSequencerDragTargets();
      if (target.classList.contains("journey-insert-target")) {{
        insertBatchAt(Number(target.dataset.insertIndex), Number(rawQuestId));
      }} else if (target.classList.contains("journey-unused-drop")) {{
        moveQuestToUnused(Number(rawQuestId));
      }} else {{
        moveQuestToBatch(Number(rawQuestId), Number(target.dataset.batchIndex));
      }}
    }}

    function zoneSort(a, b) {{
      return (a.minLevel ?? 999) - (b.minLevel ?? 999) || (a.maxLevel ?? 999) - (b.maxLevel ?? 999) || a.name.localeCompare(b.name);
    }}

    function filterableZones() {{
      return DATA.zones
        .filter((zone) => zone.questCount > 0)
        .sort(zoneSort);
    }}

    function zoneOptionLabel(zone) {{
      const rangeLabel = zone.levelRange ? ` [${{escapeHtml(zone.levelRange)}}]` : "";
      return `${{escapeHtml(zone.name)}}${{rangeLabel}}`;
    }}

    function populateZoneSelect() {{
      zoneSelect.innerHTML = '<option value="">Select zone</option>' + filterableZones()
        .map((zone) => {{
          return `<option value="${{zone.id}}">${{zoneOptionLabel(zone)}}</option>`;
        }})
        .join("");
    }}

    function populateFilters() {{
      raceFilter.innerHTML = RACES.map((race) => `
        <option value="${{race.mask ?? "all"}}" style="color:${{race.color}}">${{escapeHtml(race.label)}}</option>
      `).join("");
      classFilter.innerHTML = CLASSES.map((klass) => `
        <option value="${{klass.mask ?? "all"}}" style="color:${{klass.color}}">${{escapeHtml(klass.label)}}</option>
      `).join("");
      levelFilter.innerHTML = '<option value="all">All levels</option>' + Array.from({{ length: 60 }}, (_, index) => {{
        const level = index + 1;
        return `<option value="${{level}}">Level ${{level}}</option>`;
      }}).join("");
      updateFilterSelectColors();
    }}

    function populateQuestFilters() {{
      const counts = new Map();
      DATA.quests.forEach((quest) => {{
        (quest.typeIds || ["general"]).forEach((typeId) => {{
          counts.set(typeId, (counts.get(typeId) || 0) + 1);
        }});
      }});
      questFilterMenu.innerHTML = `
        <div class="quest-filter-title">Quest Types</div>
        ${{QUEST_TYPE_FILTERS.map((filter) => `
          <label class="quest-type-option">
            <input type="checkbox" value="${{filter.id}}" ${{filters.typeIds.has(filter.id) ? "checked" : ""}}>
            <span>${{escapeHtml(filter.label)}}</span>
            <span class="type-count">${{counts.get(filter.id) || 0}}</span>
          </label>
        `).join("")}}
      `;
      questFilterMenu.querySelectorAll('input[type="checkbox"]').forEach((input) => {{
        input.addEventListener("change", updateQuestTypeFiltersFromMenu);
      }});
      updateQuestFilterButton();
    }}

    function populateZoneFilters() {{
      const zones = filterableZones();
      zoneFilterMenu.innerHTML = `
        <div class="zone-filter-title">Zones</div>
        <div class="filter-actions">
          <button type="button" data-zone-action="check-all">Check all</button>
          <button type="button" data-zone-action="uncheck-all">Uncheck all</button>
        </div>
        ${{zones.map((zone) => `
          <label class="quest-type-option">
            <input type="checkbox" value="${{zone.id}}" ${{filters.zoneIds.has(zone.id) ? "checked" : ""}}>
            <span>${{zoneOptionLabel(zone)}}</span>
          </label>
        `).join("")}}
      `;
      zoneFilterMenu.querySelector('[data-zone-action="check-all"]').addEventListener("click", () => {{
        filters.zoneIds = new Set(filterableZones().map((zone) => zone.id));
        zoneFilterMenu.querySelectorAll('input[type="checkbox"]').forEach((input) => input.checked = true);
        updateZoneFilterButton();
        renderCurrentView();
      }});
      zoneFilterMenu.querySelector('[data-zone-action="uncheck-all"]').addEventListener("click", () => {{
        filters.zoneIds = new Set();
        zoneFilterMenu.querySelectorAll('input[type="checkbox"]').forEach((input) => input.checked = false);
        updateZoneFilterButton();
        renderCurrentView();
      }});
      zoneFilterMenu.querySelectorAll('input[type="checkbox"]').forEach((input) => {{
        input.addEventListener("change", updateZoneFiltersFromMenu);
      }});
      updateZoneFilterButton();
    }}

    function populateDisplayFilters() {{
      displayFilterMenu.innerHTML = `
        <div class="display-filter-title">Map Display</div>
        ${{DISPLAY_FILTERS.map((filter) => `
          <label class="quest-type-option">
            <input type="checkbox" value="${{filter.id}}" ${{displayFilters.has(filter.id) ? "checked" : ""}}>
            <span>${{escapeHtml(filter.label)}}</span>
          </label>
        `).join("")}}
      `;
      displayFilterMenu.querySelectorAll('input[type="checkbox"]').forEach((input) => {{
        input.addEventListener("change", updateDisplayFiltersFromMenu);
      }});
      updateDisplayFilterButton();
    }}

    function populateOptionsFilters() {{
      optionsFilterMenu.innerHTML = `
        <div class="options-filter-title">Catalogue Options</div>
        ${{CATALOGUE_OPTIONS.map((option) => `
          <label class="quest-type-option">
            <input type="checkbox" value="${{option.id}}" ${{catalogueOptions.has(option.id) ? "checked" : ""}}>
            <span>${{escapeHtml(option.label)}}</span>
          </label>
        `).join("")}}
      `;
      optionsFilterMenu.querySelectorAll('input[type="checkbox"]').forEach((input) => {{
        input.addEventListener("change", updateOptionsFiltersFromMenu);
      }});
      updateOptionsFilterButton();
    }}

    function updateQuestTypeFiltersFromMenu() {{
      forcedCatalogueChainId = null;
      filters.typeIds = new Set([...questFilterMenu.querySelectorAll('input[type="checkbox"]:checked')].map((input) => input.value));
      updateQuestFilterButton();
      renderCurrentView();
    }}

    function updateZoneFiltersFromMenu() {{
      forcedCatalogueChainId = null;
      filters.zoneIds = new Set([...zoneFilterMenu.querySelectorAll('input[type="checkbox"]:checked')].map((input) => Number(input.value)));
      updateZoneFilterButton();
      renderCurrentView();
    }}

    function updateDisplayFiltersFromMenu() {{
      displayFilters.clear();
      displayFilterMenu.querySelectorAll('input[type="checkbox"]:checked').forEach((input) => {{
        displayFilters.add(input.value);
      }});
      updateDisplayFilterButton();
      renderCurrentView();
    }}

    function updateOptionsFiltersFromMenu() {{
      forcedCatalogueChainId = null;
      catalogueOptions.clear();
      optionsFilterMenu.querySelectorAll('input[type="checkbox"]:checked').forEach((input) => {{
        catalogueOptions.add(input.value);
      }});
      updateOptionsFilterButton();
      renderCurrentView();
    }}

    function updateQuestFilterButton() {{
      const enabledLabels = QUEST_TYPE_FILTERS
        .filter((filter) => filters.typeIds.has(filter.id))
        .map((filter) => filter.label);
      questFilterCount.textContent = String(enabledLabels.length);
      questFilterButton.title = enabledLabels.length ? enabledLabels.join(", ") : "No quest types selected";
      questFilterButton.classList.toggle("active", enabledLabels.length !== 1 || !filters.typeIds.has("general"));
    }}

    function updateZoneFilterButton() {{
      const zones = filterableZones();
      const selectedZones = zones.filter((zone) => filters.zoneIds.has(zone.id));
      zoneFilterCount.textContent = String(selectedZones.length);
      zoneFilterButton.title = selectedZones.length === zones.length
        ? "All zones"
        : selectedZones.length
          ? selectedZones.map((zone) => zone.name).join(", ")
          : "No zones selected";
      zoneFilterButton.classList.toggle("active", selectedZones.length !== zones.length);
    }}

    function updateDisplayFilterButton() {{
      const enabledLabels = DISPLAY_FILTERS
        .filter((filter) => displayFilters.has(filter.id))
        .map((filter) => filter.label);
      displayFilterCount.textContent = String(enabledLabels.length);
      displayFilterButton.title = enabledLabels.length ? enabledLabels.join(", ") : "No display overlays selected";
      displayFilterButton.classList.toggle("active", enabledLabels.length > 0);
    }}

    function updateOptionsFilterButton() {{
      const enabledLabels = CATALOGUE_OPTIONS
        .filter((option) => catalogueOptions.has(option.id))
        .map((option) => option.label);
      optionsFilterCount.textContent = String(enabledLabels.length);
      optionsFilterButton.title = enabledLabels.length ? enabledLabels.join(", ") : "No catalogue options selected";
      optionsFilterButton.classList.toggle("active", enabledLabels.length !== CATALOGUE_OPTIONS.length);
    }}

    function setQuestFilterMenuOpen(open) {{
      questFilterMenu.hidden = !open;
      questFilterButton.setAttribute("aria-expanded", String(open));
    }}

    function setZoneFilterMenuOpen(open) {{
      zoneFilterMenu.hidden = !open;
      zoneFilterButton.setAttribute("aria-expanded", String(open));
    }}

    function setDisplayFilterMenuOpen(open) {{
      displayFilterMenu.hidden = !open;
      displayFilterButton.setAttribute("aria-expanded", String(open));
    }}

    function setOptionsFilterMenuOpen(open) {{
      optionsFilterMenu.hidden = !open;
      optionsFilterButton.setAttribute("aria-expanded", String(open));
    }}

    function updateFilterSelectColors() {{
      const race = RACES.find((item) => String(item.mask ?? "all") === raceFilter.value) || RACES[0];
      const klass = CLASSES.find((item) => String(item.mask ?? "all") === classFilter.value) || CLASSES[0];
      tintSelect(raceFilter, race.color);
      tintSelect(classFilter, klass.color);
      tintSelect(levelFilter, levelFilter.value === "all" ? "#fff0ce" : "#40c040");
    }}

    function tintSelect(select, color) {{
      select.style.color = color;
      select.style.borderColor = color === "#fff0ce" ? "rgba(255, 235, 196, 0.24)" : color;
    }}

    function updateFiltersFromControls() {{
      filters.raceMask = raceFilter.value === "all" ? null : Number(raceFilter.value);
      filters.classMask = classFilter.value === "all" ? null : Number(classFilter.value);
      filters.level = levelFilter.value === "all" ? null : Number(levelFilter.value);
      updateFilterSelectColors();
      renderCurrentView();
    }}

    function updateSearchClearButton() {{
      if (!questSearchClear) return;
      questSearchClear.hidden = !questSearch.value;
    }}

    function updateSearchFilterFromInput() {{
      filters.search = questSearch.value.trim().toLowerCase();
      updateSearchClearButton();
      renderCurrentView();
    }}

    function renderWorldTiles() {{
      worldLayer.innerHTML = "";
      DATA.continents.forEach((continent) => {{
        const continentEl = document.createElement("div");
        continentEl.className = "continent";
        continentEl.style.left = `${{continent.x}}%`;
        continentEl.style.top = `${{continent.y}}%`;
        continentEl.style.width = `${{continent.width}}%`;
        continentEl.style.height = `${{continent.height}}%`;
        continentEl.innerHTML = `
          <img class="continent-map" src="${{continent.image}}" alt="" style="object-position: ${{continent.objectPosition || "50% 50%"}}">
          <span class="continent-label">${{escapeHtml(continent.name)}}</span>
        `;
        continentEl.querySelector("img").addEventListener("error", (event) => event.currentTarget.remove());
        worldLayer.append(continentEl);
      }});
    }}

    function mapPointFromEvent(event) {{
      const rect = mapEl.getBoundingClientRect();
      if (!rect.width || !rect.height) return null;
      return {{
        x: (event.clientX - rect.left) / rect.width * 100,
        y: (event.clientY - rect.top) / rect.height * 100,
        pixelX: event.clientX - rect.left,
        pixelY: event.clientY - rect.top,
      }};
    }}

    function continentLocalPoint(point) {{
      const continent = DATA.continents.find((item) => (
        point.x >= item.x &&
        point.x <= item.x + item.width &&
        point.y >= item.y &&
        point.y <= item.y + item.height
      ));
      if (!continent) return null;
      return {{
        continent,
        x: (point.x - continent.x) / continent.width * 100,
        y: (point.y - continent.y) / continent.height * 100,
      }};
    }}

    function zoneIdFromHitGrid(continent, localPoint) {{
      const grid = continent.zoneHitGrid;
      if (!grid?.rows?.length) return null;
      const col = Math.max(0, Math.min(grid.width - 1, Math.floor(localPoint.x / 100 * grid.width)));
      const row = Math.max(0, Math.min(grid.height - 1, Math.floor(localPoint.y / 100 * grid.height)));
      const code = grid.rows[row]?.[col];
      const index = grid.alphabet.indexOf(code);
      return index > 0 ? grid.zones[index] : null;
    }}

    function worldZoneHitFromEvent(event) {{
      if (currentView.type !== "world") return null;
      if (event.target.closest(".map-marker, .pickup-choice-popover")) return null;
      const point = mapPointFromEvent(event);
      if (!point) return null;
      const localPoint = continentLocalPoint(point);
      if (!localPoint) return null;
      const zoneId = zoneIdFromHitGrid(localPoint.continent, localPoint);
      const zone = zoneId ? zonesById.get(zoneId) : null;
      return zone ? {{ zone, point }} : null;
    }}

    function hideWorldZoneTooltip() {{
      worldZoneTooltip.hidden = true;
      worldZoneTooltip.dataset.zoneId = "";
    }}

    function showWorldZoneTooltip(hit) {{
      if (!hit?.zone) {{
        hideWorldZoneTooltip();
        return;
      }}
      worldZoneTooltip.hidden = false;
      worldZoneTooltip.dataset.zoneId = hit.zone.id;
      worldZoneTooltip.textContent = hit.zone.name;
      const margin = 8;
      const gap = 14;
      const width = worldZoneTooltip.offsetWidth || 150;
      const height = worldZoneTooltip.offsetHeight || 38;
      const layerWidth = Math.max(1, mapEl.clientWidth);
      const layerHeight = Math.max(1, mapEl.clientHeight);
      let left = hit.point.pixelX + gap;
      if (left + width > layerWidth - margin) left = hit.point.pixelX - width - gap;
      left = clampNumber(left, margin, Math.max(margin, layerWidth - width - margin));
      const top = clampNumber(hit.point.pixelY - height / 2, margin, Math.max(margin, layerHeight - height - margin));
      worldZoneTooltip.style.left = `${{left}}px`;
      worldZoneTooltip.style.top = `${{top}}px`;
    }}

    function handleWorldZonePointerMove(event) {{
      const hit = worldZoneHitFromEvent(event);
      if (hit) showWorldZoneTooltip(hit);
      else hideWorldZoneTooltip();
    }}

    function handleWorldZoneClick(event) {{
      const hit = worldZoneHitFromEvent(event);
      if (!hit) return;
      event.preventDefault();
      event.stopPropagation();
      setZoneView(hit.zone.id);
    }}

    function setWorldView() {{
      currentView = {{ type: "world", zoneId: null }};
      zoneSelect.value = "";
      renderCurrentView();
    }}

    function setZoneView(zoneId) {{
      const zone = zonesById.get(Number(zoneId));
      if (!zone) return;
      hideWorldZoneTooltip();
      currentView = {{ type: "zone", zoneId: zone.id }};
      zoneSelect.value = String(zone.id);
      renderCurrentView();
    }}

    function questPassesRaceClass(quest) {{
      const raceMask = quest.requiredRaceMask || 0;
      const classMask = quest.requiredClassMask || 0;
      const raceOk = filters.raceMask == null || raceMask === 0 || (raceMask & filters.raceMask) !== 0;
      const classOk = filters.classMask == null || classMask === 0 || (classMask & filters.classMask) !== 0;
      return raceOk && classOk;
    }}

    function questPassesType(quest) {{
      const typeIds = quest.typeIds?.length ? quest.typeIds : ["general"];
      return typeIds.some((typeId) => filters.typeIds.has(typeId));
    }}

    function questPassesSearch(quest) {{
      if (!filters.search) return true;
      return String(quest.name || "").toLowerCase().includes(filters.search);
    }}

    function questIsInCurrentView(quest) {{
      return currentView.type === "world" || quest.zones.includes(currentView.zoneId);
    }}

    function questGrayMaxLevel(questLevel) {{
      if (questLevel == null || questLevel < 0) return Infinity;
      if (questLevel <= 5) return questLevel + 5;
      if (questLevel <= 39) return questLevel + Math.ceil(questLevel / 10) + 5;
      return questLevel + Math.ceil(questLevel / 5) + 1;
    }}

    const QUEST_DIFFICULTY_COLORS = {{
      grey: "#c0c0c0",
      green: "#40c040",
      yellow: "#ffff00",
      orange: "#ff8040",
      red: "#ff1a1a",
    }};

    function questDifficultyId(quest) {{
      if (!quest || filters.level == null) return null;
      const questLevel = Number(quest.questLevel ?? quest.requiredLevel ?? 0);
      if (!Number.isFinite(questLevel)) return null;
      const levelDiff = questLevel - filters.level;
      if (levelDiff >= 5) return "red";
      if (levelDiff >= 3) return "orange";
      if (levelDiff >= -2) return "yellow";
      return filters.level <= questGrayMaxLevel(questLevel) ? "green" : "grey";
    }}

    function questDifficultyColor(quest) {{
      const difficulty = questDifficultyId(quest);
      return difficulty ? QUEST_DIFFICULTY_COLORS[difficulty] : null;
    }}

    function questDifficultyAttrs(quest) {{
      const difficulty = questDifficultyId(quest);
      if (!difficulty) return `data-difficulty="none"`;
      return `data-difficulty="${{difficulty}}" style="--quest-difficulty-color: ${{QUEST_DIFFICULTY_COLORS[difficulty]}}"`;
    }}

    function questObjectiveColor(quest) {{
      const id = Number(quest?.id ?? 0);
      const hue = ((id * 137.508) % 360 + 360) % 360;
      return `hsl(${{hue.toFixed(1)}} 74% 64%)`;
    }}

    function questHasType(quest, typeId) {{
      return (quest?.typeIds || []).includes(typeId);
    }}

    function questTypeBadgesHtml(questOrQuests) {{
      const quests = Array.isArray(questOrQuests) ? questOrQuests : [questOrQuests];
      const hasDungeon = quests.some((quest) => questHasType(quest, "dungeon"));
      const hasElite = quests.some((quest) => questHasType(quest, "elite"));
      return [
        hasDungeon ? '<span class="quest-type-badge dungeon" aria-label="Dungeon quest">D</span>' : "",
        hasElite ? '<span class="quest-type-badge elite" aria-label="Elite or group quest">E</span>' : "",
      ].join("");
    }}

    function questTypeTextBadgesHtml(quest) {{
      const badges = [];
      if (questHasType(quest, "elite")) badges.push('<span class="quest-type-text-badge">[E]</span>');
      if (questHasType(quest, "dungeon")) badges.push('<span class="quest-type-text-badge">[D]</span>');
      return badges.length ? `<span class="quest-type-text-badges">${{badges.join("")}}</span>` : "";
    }}

    function questWowheadSlug(name) {{
      return String(name || "")
        .normalize("NFKD")
        .replace(/[\\u0300-\\u036f]/g, "")
        .toLowerCase()
        .replace(/&/g, " and ")
        .replace(/['\\u2019]/g, "")
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "");
    }}

    function questWowheadUrl(quest) {{
      const slug = questWowheadSlug(quest.name);
      return `https://www.wowhead.com/classic/quest=${{quest.id}}${{slug ? `/${{slug}}` : ""}}`;
    }}

    function questWowheadLinkHtml(quest) {{
      return `
        <a class="quest-wowhead-link" href="${{escapeHtml(questWowheadUrl(quest))}}" target="_blank" rel="noopener noreferrer" aria-label="Open ${{escapeHtml(quest.name)}} on Wowhead" title="Open on Wowhead">
          <svg viewBox="0 0 24 24" fill="none" stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M15 3h6v6"></path>
            <path d="M10 14 21 3"></path>
            <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path>
          </svg>
        </a>
      `;
    }}

    function pickupRingGradient(quests) {{
      if (!quests.length || filters.level == null) return null;
      const counts = new Map();
      quests.forEach((quest) => {{
        const difficulty = questDifficultyId(quest);
        if (!difficulty) return;
        counts.set(difficulty, (counts.get(difficulty) || 0) + 1);
      }});
      const total = [...counts.values()].reduce((sum, count) => sum + count, 0);
      if (!total) return null;
      const segments = [];
      let cursor = 0;
      ["grey", "green", "yellow", "orange", "red"].forEach((difficulty) => {{
        const count = counts.get(difficulty) || 0;
        if (!count) return;
        const start = (cursor / total) * 360;
        cursor += count;
        const end = (cursor / total) * 360;
        segments.push(`${{QUEST_DIFFICULTY_COLORS[difficulty]}} ${{start.toFixed(2)}}deg ${{end.toFixed(2)}}deg`);
      }});
      return segments.length === 1 ? segments[0].split(" ")[0] : `conic-gradient(${{segments.join(", ")}})`;
    }}

    function questPassesLevel(quest) {{
      if (filters.level == null) return true;
      if (!quest) return false;
      const requiredLevel = quest.requiredLevel ?? 0;
      const questLevel = quest.questLevel ?? requiredLevel;
      return requiredLevel <= filters.level && filters.level <= questGrayMaxLevel(questLevel);
    }}

    function chainPassesLevel(chain) {{
      if (filters.level == null) return true;
      return chain.visibleQuests.some(questPassesLevel);
    }}

    function chainPassesSearch(chain) {{
      if (!filters.search) return true;
      return chain.visibleQuests.some(questPassesSearch);
    }}

    function questPassesCatalogueOptions(quest) {{
      if (!activeJourney || !quest) return true;
      const id = Number(quest.id);
      if (!catalogueOptions.has("show-assigned") && assignedJourneyQuestIds().has(id)) return false;
      if (!catalogueOptions.has("show-unused") && unusedJourneyQuestIds().has(id)) return false;
      return true;
    }}

    function currentChains() {{
      const chains = [...chainsById.values()];
      const zones = filterableZones();
      const zoneFiltered = filters.zoneIds.size !== zones.length;
      const selectedZoneNames = zoneFiltered ? selectedZoneNameSet() : null;
      return chains
        .map((chain) => {{
          const forceVisible = forcedCatalogueChainId != null && chain.id === forcedCatalogueChainId;
          const visibleQuests = forceVisible
            ? chain.quests
            : chain.quests.filter((quest) => questPassesRaceClass(quest) && questPassesType(quest) && questPassesCatalogueOptions(quest));
          const visibleStartQuest = visibleQuests[0] || null;
          const zoneNames = chainZoneNamesFromQuests(visibleQuests);
          return {{
            ...chain,
            visibleQuests,
            visibleStartQuest,
            visibleStartLevel: visibleStartQuest?.requiredLevel ?? 0,
            zoneNames,
            forceVisible,
          }};
        }})
        .filter((chain) => chain.visibleQuests.length > 0)
        .filter((chain) => chain.forceVisible || !zoneFiltered || chain.zoneNames.some((zoneName) => selectedZoneNames.has(zoneName)))
        .filter((chain) => chain.forceVisible || chainPassesLevel(chain))
        .filter((chain) => chain.forceVisible || chainPassesSearch(chain))
        .sort((a, b) => a.visibleStartLevel - b.visibleStartLevel || (a.visibleStartQuest?.questLevel ?? 0) - (b.visibleStartQuest?.questLevel ?? 0) || a.name.localeCompare(b.name));
    }}

    function currentQuests() {{
      const questIds = new Set();
      currentChains().forEach((chain) => {{
        chain.visibleQuests.forEach((quest) => questIds.add(quest.id));
      }});
      return DATA.quests.filter((quest) => questIds.has(quest.id));
    }}

    function currentMapQuests() {{
      return currentQuests().filter(questIsInCurrentView);
    }}

    function renderCurrentView() {{
      const isWorld = currentView.type === "world";
      const zone = isWorld ? null : zonesById.get(currentView.zoneId);
      worldButton.classList.toggle("active", isWorld);
      worldLayer.style.display = isWorld ? "block" : "none";
      zoneImage.style.display = isWorld ? "none" : "block";
      if (zone) {{
        zoneImage.src = zone.image;
        zoneImage.alt = zone.name;
      }}
      mapTitle.hidden = isWorld;
      mapTitle.textContent = isWorld ? "" : zone.name;
      const catalogueScrollTop = chainList.scrollTop;
      renderInventory();
      chainList.scrollTop = catalogueScrollTop;
      renderAvailablePickupMarkers();
      const targetQuest = selectedId ? questsById.get(selectedId) : activeId ? questsById.get(activeId) : null;
      if (targetQuest && visibleInInventory(targetQuest)) {{
        activateQuest(targetQuest.id, false);
      }} else {{
        activeId = null;
        selectedId = null;
        clearTarget();
      }}
      scheduleMapFit();
    }}

    function visibleInInventory(quest) {{
      if (!quest) return false;
      return currentChains().some((chain) => (
        chain.id === quest.chainId && chain.visibleQuests.some((item) => item.id === quest.id)
      ));
    }}

    function catalogueQuestOrder() {{
      return currentChains().flatMap((chain) => chain.visibleQuests);
    }}

    function canUseCatalogueArrowKeys(target) {{
      const element = target instanceof Element ? target : null;
      if (!element) return true;
      if (element.closest("input, textarea, select, [contenteditable='true']")) return false;
      return Boolean(element.closest("#chain-list") || element.closest(".map-frame") || element === document.body);
    }}

    function scrollQuestIntoCatalogueView(id) {{
      const target = document.querySelector(`.chain-quest-item[data-quest-id="${{id}}"]`) || document.querySelector(`.quest-icon[data-quest-id="${{id}}"]`);
      if (!target) return;
      const listRect = chainList.getBoundingClientRect();
      const targetRect = target.getBoundingClientRect();
      const margin = 14;
      if (targetRect.top < listRect.top + margin) {{
        chainList.scrollTop += targetRect.top - listRect.top - margin;
      }} else if (targetRect.bottom > listRect.bottom - margin) {{
        chainList.scrollTop += targetRect.bottom - listRect.bottom + margin;
      }}
    }}

    function focusCatalogueQuest(id) {{
      const target = document.querySelector(`.chain-quest-item[data-quest-id="${{id}}"]`) || document.querySelector(`.quest-icon[data-quest-id="${{id}}"]`);
      try {{
        target?.focus({{ preventScroll: true }});
      }} catch {{
        target?.focus();
      }}
    }}

    function moveCatalogueSelection(delta) {{
      const order = catalogueQuestOrder();
      if (!order.length) return false;
      const currentId = selectedId ?? activeId;
      let index = order.findIndex((quest) => quest.id === currentId);
      if (index < 0) index = delta > 0 ? -1 : order.length;
      const nextIndex = Math.max(0, Math.min(order.length - 1, index + delta));
      if (nextIndex === index) return false;
      const nextQuest = order[nextIndex];
      if (!nextQuest) return false;
      selectQuest(nextQuest.id, {{ scrollQuestIntoView: true, focusQuest: true }});
      return true;
    }}

    function firstVisibleQuest() {{
      const chain = currentChains()[0];
      if (!chain) return null;
      if (currentView.type === "world") return chain.visibleQuests[0];
      return chain.visibleQuests.find((quest) => quest.zones.includes(currentView.zoneId)) || chain.visibleQuests[0];
    }}

    function clearTarget() {{
      highlightLayer.innerHTML = "";
      closePickupQuestList();
      document.querySelectorAll(".quest-icon.active, .quest-icon.selected, .chain-row.active, .map-marker.active, .map-marker.selected, .chain-quest-item.active, .chain-quest-item.selected, .journey-quest.active, .journey-quest.selected").forEach((element) => {{
        element.classList.remove("active", "selected");
      }});
      if (!details) return;
      const visibleChains = currentChains();
      const visibleQuestCount = new Set(visibleChains.flatMap((chain) => chain.visibleQuests.map((quest) => quest.id))).size;
      const visibleChainCount = visibleChains.length;
      const viewName = currentView.type === "world" ? "World Map" : zonesById.get(currentView.zoneId)?.name;
      details.innerHTML = `
        <div>
          <h2>No Quest Selected</h2>
          <p class="body-copy">${{escapeHtml(viewName)}} - ${{visibleQuestCount}} quests across ${{visibleChainCount}} chains</p>
        </div>
        <div class="objective-panel">
          <span class="label">Objectives</span>
          <ul class="objective-list"><li>-</li></ul>
        </div>
        <div class="meta-grid">
          <div class="meta"><span class="label">Pickup</span><span class="value">-</span></div>
          <div class="meta"><span class="label">Turn-in</span><span class="value">-</span></div>
          <div class="meta"><span class="label">Objectives</span><span class="value">-</span></div>
        </div>
      `;
    }}

    function zonesFromSources(sources) {{
      const zones = [];
      (sources || []).forEach((source) => {{
        const raw = String(source ?? "");
        const match = raw.match(/\\[([^\\]]+)\\]/);
        if (!match) return;
        match[1].split(",").forEach((part) => {{
          const zoneName = part.trim().replace(/\\s+\\+\\d+$/, "");
          if (zoneName && !zones.includes(zoneName)) zones.push(zoneName);
        }});
      }});
      return zones;
    }}

    function zoneNamesFromIds(zoneIds) {{
      const names = [];
      (zoneIds || []).forEach((zoneId) => {{
        const zone = zonesById.get(Number(zoneId));
        if (zone?.name && !names.includes(zone.name)) names.push(zone.name);
      }});
      return names;
    }}

    function questInvolvedZoneNames(quest) {{
      const names = [];
      [
        ...(quest.startZoneIds || []),
        ...(quest.objectiveZoneIds || []),
        ...(quest.endZoneIds || []),
      ].forEach((zoneId) => {{
        const zone = zonesById.get(Number(zoneId));
        if (zone?.name && !names.includes(zone.name)) names.push(zone.name);
      }});
      if (!names.length) {{
        [...zonesFromSources(quest.startSources), ...zonesFromSources(quest.endSources)].forEach((zoneName) => {{
          if (!names.includes(zoneName)) names.push(zoneName);
        }});
      }}
      return names;
    }}

    function chainZoneNamesFromQuests(quests) {{
      const zones = [];
      quests.forEach((quest) => {{
        questInvolvedZoneNames(quest).forEach((zoneName) => {{
          if (!zones.includes(zoneName)) zones.push(zoneName);
        }});
      }});
      return zones;
    }}

    function chainZoneNames(chain) {{
      return chain.zoneNames || chainZoneNamesFromQuests(chain.visibleQuests || chain.quests || []);
    }}

    function selectedZoneNameSet() {{
      return new Set(filterableZones()
        .filter((zone) => filters.zoneIds.has(zone.id))
        .map((zone) => zone.name));
    }}

    function zoneSummaryText(zoneNames) {{
      return zoneNames.length ? `[${{zoneNames.join(", ")}}]` : "";
    }}

    function questZoneSummaryText(quest) {{
      const segments = [
        zoneNamesFromIds(quest.startZoneIds).join(", "),
        zoneNamesFromIds(quest.objectiveZoneIds).join(", "),
        zoneNamesFromIds(quest.endZoneIds).join(", "),
      ].filter(Boolean);
      if (!segments.length) {{
        const startZones = zonesFromSources(quest.startSources);
        const endZones = zonesFromSources(quest.endSources);
        if (!startZones.length && !endZones.length) return "";
        segments.push(startZones.length ? startZones.join(", ") : "?");
        segments.push(endZones.length ? endZones.join(", ") : "?");
      }}
      const compactSegments = [];
      segments.forEach((segment) => {{
        if (compactSegments[compactSegments.length - 1] !== segment) compactSegments.push(segment);
      }});
      return `[${{compactSegments.join(" -> ")}}]`;
    }}

    function renderInventory() {{
      const chains = currentChains();
      chainList.innerHTML = "";
      if (inventoryTitle) inventoryTitle.textContent = "Quest Catalogue";

      const fragment = document.createDocumentFragment();
      chains.forEach((chain) => {{
        const isExpanded = expandedChainIds.has(chain.id);
        const row = document.createElement("section");
        row.className = "chain-row";
        if (isExpanded) row.classList.add("expanded");
        row.dataset.chainId = chain.id;
        row.tabIndex = 0;
        row.setAttribute("aria-expanded", String(isExpanded));
        row.style.setProperty("--chain-color", chain.color);
        row.addEventListener("click", (event) => {{
          if (event.target.closest(".quest-icon, .chain-quest-item")) return;
          toggleChainExpanded(chain.id);
        }});
        row.addEventListener("keydown", (event) => {{
          if (event.key !== "Enter" && event.key !== " ") return;
          if (event.target !== row) return;
          event.preventDefault();
          toggleChainExpanded(chain.id);
        }});

        const meta = document.createElement("div");
        meta.className = "chain-meta";
        const chainZones = zoneSummaryText(chainZoneNames(chain));
        const chainTitle = chainZones ? `${{chain.name}} ${{chainZones}}` : chain.name;
        meta.innerHTML = `
          <div class="chain-name" title="${{escapeHtml(chainTitle)}}">
            <span class="chain-name-text" ${{questDifficultyAttrs(chain.visibleStartQuest)}}>${{escapeHtml(chain.name)}}</span>
            ${{chainZones ? `<span class="chain-zone-summary">${{escapeHtml(chainZones)}}</span>` : ""}}
          </div>
          <div class="chain-summary">
            <span class="chain-level">${{chain.visibleStartLevel}}</span>
            <span class="chain-expander">${{isExpanded ? "Collapse" : "Expand"}}</span>
          </div>
        `;

        const track = document.createElement("div");
        track.className = "chain-track";
        chain.visibleQuests.forEach((quest) => track.append(createQuestIcon(quest)));

        row.append(meta, track);
        if (isExpanded) {{
          const expanded = document.createElement("div");
          expanded.className = "chain-expanded";
          let previousGroupId = null;
          chain.visibleQuests.forEach((quest) => {{
            const groupId = quest.chainGroupId ?? 0;
            if (previousGroupId !== null && groupId !== previousGroupId) expanded.append(createChainGroupBreak());
            expanded.append(createChainQuestItem(quest));
            previousGroupId = groupId;
          }});
          row.append(expanded);
        }}
        fragment.append(row);
      }});
      chainList.append(fragment);
    }}

    function createChainGroupBreak() {{
      const divider = document.createElement("div");
      divider.className = "chain-group-break";
      divider.setAttribute("aria-hidden", "true");
      return divider;
    }}

    function toggleChainExpanded(chainId) {{
      if (expandedChainIds.has(chainId)) {{
        expandedChainIds.delete(chainId);
      }} else {{
        expandedChainIds.add(chainId);
      }}
      renderInventory();
      const targetQuest = selectedId ? questsById.get(selectedId) : activeId ? questsById.get(activeId) : null;
      if (targetQuest && visibleInInventory(targetQuest)) activateQuest(targetQuest.id, false);
    }}

    function collapseAllChains() {{
      currentChains().forEach((chain) => expandedChainIds.delete(chain.id));
      renderInventory();
      const targetQuest = selectedId ? questsById.get(selectedId) : activeId ? questsById.get(activeId) : null;
      if (targetQuest && visibleInInventory(targetQuest)) activateQuest(targetQuest.id, false);
    }}

    function expandAllChains() {{
      currentChains().forEach((chain) => expandedChainIds.add(chain.id));
      renderInventory();
      const targetQuest = selectedId ? questsById.get(selectedId) : activeId ? questsById.get(activeId) : null;
      if (targetQuest && visibleInInventory(targetQuest)) activateQuest(targetQuest.id, false);
    }}

    function createQuestIcon(quest) {{
      const icon = document.createElement("button");
      icon.type = "button";
      icon.className = "quest-icon";
      if (!quest.startPoints.length && !quest.endPoints.length && !quest.objectivePoints.length) icon.classList.add("no-map");
      icon.dataset.questId = quest.id;
      icon.dataset.chainId = quest.chainId;
      icon.draggable = true;
      icon.style.setProperty("--chain-color", quest.chainColor);
      const difficulty = questDifficultyId(quest);
      icon.dataset.difficulty = difficulty || "none";
      if (difficulty) icon.style.setProperty("--quest-icon-ring", QUEST_DIFFICULTY_COLORS[difficulty]);
      icon.title = `${{quest.name}} (#${{quest.id}}) - requires ${{quest.requiredLevel}}, quest level ${{quest.questLevel}}`;
      icon.innerHTML = `<span class="quest-icon-step">${{quest.chainStep}}</span>${{questTypeBadgesHtml(quest)}}`;
      icon.addEventListener("click", (event) => {{
        event.stopPropagation();
        selectQuest(quest.id);
      }});
      return icon;
    }}

    function createChainQuestItem(quest) {{
      const isSelected = selectedId === quest.id;
      const item = document.createElement("div");
      item.className = "chain-quest-item";
      if (isSelected) item.classList.add("has-detail");
      item.dataset.questId = quest.id;
      item.dataset.chainId = quest.chainId;
      item.tabIndex = 0;
      item.draggable = true;
      item.setAttribute("role", "button");
      item.setAttribute("aria-pressed", String(isSelected));
      item.style.setProperty("--chain-color", quest.chainColor);
      item.title = `${{quest.name}} (#${{quest.id}})`;
      const questZones = isSelected ? "" : questZoneSummaryText(quest);
      item.innerHTML = `
        <span class="chain-quest-step"><span>${{quest.chainStep}}</span>${{questTypeBadgesHtml(quest)}}</span>
        <span class="chain-quest-main">
          <span class="chain-quest-title-row">
            <span class="chain-quest-title" ${{questDifficultyAttrs(quest)}}>${{escapeHtml(quest.name)}}</span>
            ${{questTypeTextBadgesHtml(quest)}}
            ${{questZones ? `<span class="quest-zone-summary">${{escapeHtml(questZones)}}</span>` : ""}}
          </span>
        </span>
        <span class="chain-quest-meta">${{quest.requiredLevel ?? "?"}} / ${{quest.questLevel ?? "?"}}</span>
        ${{questWowheadLinkHtml(quest)}}
        ${{isSelected ? catalogueQuestDetailHtml(quest) : ""}}
      `;
      item.addEventListener("click", (event) => {{
        if (event.target.closest(".zone-link, .quest-wowhead-link")) return;
        event.stopPropagation();
        selectQuest(quest.id);
      }});
      item.addEventListener("keydown", (event) => {{
        if (event.target.closest(".zone-link, .quest-wowhead-link")) return;
        if (event.key !== "Enter" && event.key !== " ") return;
        event.preventDefault();
        selectQuest(quest.id);
      }});
      return item;
    }}

    function questObjectiveLines(quest) {{
      const objectives = [
        ...(quest.objectiveSummary || []),
        ...(quest.objectiveText || []),
      ];
      return [...new Set(objectives)].filter(Boolean);
    }}

    function catalogueQuestDetailHtml(quest) {{
      const objectives = questObjectiveLines(quest);
      const objectiveZoneSuffix = objectiveZoneSuffixHtml(quest);
      const objectiveItems = objectives.length
        ? objectives.map((item, index) => `<li>${{escapeHtml(item)}}${{index === objectives.length - 1 ? objectiveZoneSuffix : ""}}</li>`).join("")
        : `<li>No explicit objective text in Questie.${{objectiveZoneSuffix}}</li>`;
      return `
        <div class="chain-quest-detail">
          <div class="catalogue-detail-row">
            <span class="catalogue-detail-label">Objectives</span>
            <ul class="catalogue-objectives">
              ${{objectiveItems}}
            </ul>
          </div>
          <div class="catalogue-detail-row">
            <span class="catalogue-detail-label">Starts</span>
            <span>${{sourceListHtml(quest.startSources)}}</span>
          </div>
          <div class="catalogue-detail-row">
            <span class="catalogue-detail-label">Ends</span>
            <span>${{sourceListHtml(quest.endSources)}}</span>
          </div>
          <div class="catalogue-detail-row">
            <span class="catalogue-detail-label">Prerequisites</span>
            <span>${{questPrerequisiteHtml(quest)}}</span>
          </div>
        </div>
      `;
    }}

    function questPrerequisiteHtml(quest) {{
      const lines = [];
      const groupPrereqs = quest.preQuestGroup || [];
      const singlePrereqs = quest.preQuestSingle || [];
      if (groupPrereqs.length + singlePrereqs.length === 1) return questLinkList([...groupPrereqs, ...singlePrereqs]);
      if (groupPrereqs.length) {{
        lines.push(`<span>All required: ${{questLinkList(groupPrereqs)}}</span>`);
      }}
      if (singlePrereqs.length) {{
        lines.push(`<span>Any one of: ${{questLinkList(singlePrereqs)}}</span>`);
      }}
      return lines.length ? lines.join("<br>") : "None";
    }}

    function sourceListHtml(sources) {{
      if (!sources || !sources.length) return "None";
      return sources.map(sourceWithZoneLinks).join(", ");
    }}

    function zoneLinkListHtml(zoneIds) {{
      const linkedZones = (zoneIds || [])
        .map((zoneId) => zonesById.get(Number(zoneId)))
        .filter(Boolean)
        .map((zone) => `<button type="button" class="zone-link" data-zone-id="${{zone.id}}">${{escapeHtml(zone.name)}}</button>`);
      return linkedZones.join(", ");
    }}

    function objectiveZoneSuffixHtml(quest) {{
      const zoneLinks = zoneLinkListHtml(quest.objectiveZoneIds);
      return zoneLinks ? ` [${{zoneLinks}}]` : "";
    }}

    function sourceWithZoneLinks(source) {{
      const raw = String(source ?? "");
      const match = raw.match(/^(.*?)\\s*\\[([^\\]]+)\\](.*)$/);
      if (!match) return escapeHtml(raw);
      const prefix = escapeHtml(match[1]);
      const suffix = escapeHtml(match[3]);
      const zonePieces = match[2].split(",").map((part) => part.trim()).filter(Boolean);
      const linkedZones = zonePieces.map((part) => {{
        const extra = part.match(/^(.*?)(\\s+\\+\\d+)$/);
        const zoneName = extra ? extra[1].trim() : part;
        const tail = extra ? extra[2] : "";
        const zone = zonesByName.get(zoneName);
        if (!zone) return escapeHtml(part);
        return `<button type="button" class="zone-link" data-zone-id="${{zone.id}}">${{escapeHtml(zoneName)}}</button>${{escapeHtml(tail)}}`;
      }}).join(", ");
      return `${{prefix}} [${{linkedZones}}]${{suffix}}`;
    }}

    function viewPoint(point) {{
      if (currentView.type === "world" && Number.isFinite(point.worldX) && Number.isFinite(point.worldY)) {{
        return {{ x: point.worldX, y: point.worldY }};
      }}
      if (currentView.type === "zone" && point.zoneId === currentView.zoneId) {{
        return {{ x: point.x, y: point.y }};
      }}
      return null;
    }}

    function visibleStartPoints(quest) {{
      return (quest.startPoints || [])
        .map((point) => ({{ point, plotted: viewPoint(point) }}))
        .filter((item) => item.plotted);
    }}

    function representativeStartPoint(points) {{
      if (!points.length) return null;
      if (points.length === 1) return points[0];
      const center = points.reduce((sum, item) => {{
        sum.x += item.plotted.x;
        sum.y += item.plotted.y;
        return sum;
      }}, {{ x: 0, y: 0 }});
      center.x /= points.length;
      center.y /= points.length;
      return points
        .slice()
        .sort((a, b) => {{
          const driftA = Math.hypot(a.plotted.x - center.x, a.plotted.y - center.y);
          const driftB = Math.hypot(b.plotted.x - center.x, b.plotted.y - center.y);
          return driftA - driftB || a.plotted.y - b.plotted.y || a.plotted.x - b.plotted.x;
        }})[0];
    }}

    function sourceNameFromLabel(source) {{
      const raw = String(source ?? "").trim();
      return raw.replace(/\\s*\\[[^\\]]+\\].*$/, "").trim() || raw;
    }}

    function pointSourceName(point, quest) {{
      return point?.sourceName || sourceNameFromLabel(quest?.startSources?.[0]) || "Quest pickup";
    }}

    function pickupGroupTitle(group) {{
      const names = [...(group.sourceNames || [])].filter(Boolean);
      if (names.length === 1) return names[0];
      if (names.length > 1) return `${{names.slice(0, 2).join(", ")}}${{names.length > 2 ? ` +${{names.length - 2}}` : ""}}`;
      return "Quest pickup";
    }}

    function sortedQuestList(quests) {{
      return [...quests].sort((a, b) => a.requiredLevel - b.requiredLevel || a.questLevel - b.questLevel || a.id - b.id);
    }}

    function absorbPickupGroup(cluster, pickupGroup) {{
      cluster.pickupGroups.push(pickupGroup);
      pickupGroup.quests.forEach((quest, questId) => cluster.quests.set(questId, quest));
      pickupGroup.sourceNames.forEach((name) => cluster.sourceNames.add(name));
      pickupGroup.alternateCounts.forEach((count, questId) => cluster.alternateCounts.set(questId, count));
      cluster.key = `${{cluster.key}}+${{pickupGroup.key}}`;
      const weight = cluster.pickupGroups.length;
      cluster.x = ((cluster.x * (weight - 1)) + pickupGroup.x) / weight;
      cluster.y = ((cluster.y * (weight - 1)) + pickupGroup.y) / weight;
    }}

    function pickupClusterFromGroup(pickupGroup) {{
      return {{
        key: pickupGroup.key,
        x: pickupGroup.x,
        y: pickupGroup.y,
        quests: new Map(pickupGroup.quests),
        sourceNames: new Set(pickupGroup.sourceNames),
        alternateCounts: new Map(pickupGroup.alternateCounts),
        pickupGroups: [pickupGroup],
      }};
    }}

    function pickupSections(group) {{
      const sections = [];
      (group.pickupGroups || [group]).forEach((pickupGroup) => {{
        const quests = sortedQuestList(pickupGroup.quests.values());
        sections.push({{
          title: pickupGroupTitle(pickupGroup),
          quests,
          minRequiredLevel: Math.min(...quests.map((quest) => quest.requiredLevel ?? 0)),
          minQuestLevel: Math.min(...quests.map((quest) => quest.questLevel ?? quest.requiredLevel ?? 0)),
          x: pickupGroup.x,
          y: pickupGroup.y,
        }});
      }});
      return sections.sort((a, b) => (
        a.minRequiredLevel - b.minRequiredLevel ||
        a.minQuestLevel - b.minQuestLevel ||
        a.title.localeCompare(b.title) ||
        a.y - b.y ||
        a.x - b.x
      ));
    }}

    function pickupPopoverTitle(group) {{
      const pickupGroupCount = (group.pickupGroups || [group]).length;
      return pickupGroupCount > 1 ? "Nearby quest pickups" : pickupGroupTitle(group);
    }}

    function visibleQuestDisplayPoints(quest, pointField) {{
      return (quest[pointField] || [])
        .map((point) => ({{ point, plotted: viewPoint(point) }}))
        .filter((item) => item.plotted);
    }}

    function displayPointSourceName(point, quest, role) {{
      if (point?.sourceName) return point.sourceName;
      if (role === "handin") return sourceNameFromLabel(quest?.endSources?.[0]) || "Quest hand-in";
      return (quest?.objectiveSummary || [])[0] || (quest?.objectiveText || [])[0] || "Quest objective";
    }}

    function displayPointGroups(pointField, role) {{
      const groups = new Map();
      currentQuests().forEach((quest) => {{
        visibleQuestDisplayPoints(quest, pointField).forEach(({{ point, plotted }}) => {{
          const key = `${{role}}:${{currentView.type}}:${{point.zoneId ?? "world"}}:${{plotted.x.toFixed(2)}}:${{plotted.y.toFixed(2)}}`;
          if (!groups.has(key)) {{
            groups.set(key, {{
              key,
              role,
              x: plotted.x,
              y: plotted.y,
              quests: new Map(),
              sourceNames: new Set(),
              pointCount: 0,
            }});
          }}
          const group = groups.get(key);
          group.quests.set(quest.id, quest);
          group.sourceNames.add(displayPointSourceName(point, quest, role));
          group.pointCount += 1;
        }});
      }});
      return [...groups.values()].sort((a, b) => a.y - b.y || a.x - b.x || a.key.localeCompare(b.key));
    }}

    function displayPointRoleText(role) {{
      return role === "handin" ? "Quest hand-in" : "Quest objective";
    }}

    function displayPointPopoverTitle(group) {{
      const roleText = displayPointRoleText(group.role);
      const names = [...(group.sourceNames || [])].filter(Boolean);
      if (names.length === 1 && names[0] !== roleText) return `${{roleText}}: ${{names[0]}}`;
      if (names.length > 1) return `${{roleText}}: ${{names.slice(0, 2).join(", ")}}${{names.length > 2 ? ` +${{names.length - 2}}` : ""}}`;
      return roleText;
    }}

    function displayPointPopoverNote(group) {{
      return group.role === "handin"
        ? "Turn-in location for visible catalogue quests."
        : "Objective location for visible catalogue quests.";
    }}

    function renderObjectivePointMarkers() {{
      currentQuests().forEach((quest) => {{
        visibleQuestDisplayPoints(quest, "objectivePoints").forEach(({{ point, plotted }}) => {{
          const group = {{
            key: `objective:${{quest.id}}:${{point.zoneId ?? "world"}}:${{plotted.x.toFixed(2)}}:${{plotted.y.toFixed(2)}}`,
            role: "objective",
            x: plotted.x,
            y: plotted.y,
            quests: new Map([[quest.id, quest]]),
            sourceNames: new Set([displayPointSourceName(point, quest, "objective")]),
            pointCount: 1,
          }};
          const marker = document.createElement("button");
          marker.type = "button";
          marker.className = "map-marker available-objective";
          marker.dataset.questId = quest.id;
          marker.dataset.questIds = `|${{quest.id}}|`;
          marker.dataset.displayRole = "objective";
          marker.style.left = `${{plotted.x}}%`;
          marker.style.top = `${{plotted.y}}%`;
          marker.style.setProperty("--chain-color", questObjectiveColor(quest));
          marker.innerHTML = '<span class="display-marker-glyph"></span>';
          marker.setAttribute("aria-label", `${{displayPointPopoverTitle(group)}}, ${{quest.name}}`);
          marker.addEventListener("mouseenter", () => showDisplayPointTooltip(group));
          marker.addEventListener("mouseleave", schedulePickupPopoverClose);
          marker.addEventListener("focus", () => showDisplayPointTooltip(group));
          marker.addEventListener("blur", schedulePickupPopoverClose);
          marker.addEventListener("click", (event) => {{
            event.stopPropagation();
            closePickupQuestList();
            selectQuest(quest.id, {{ scrollChainToTop: true }});
          }});
          markerLayer.append(marker);
        }});
      }});
    }}

    function renderDisplayPointMarkers(role, pointField) {{
      displayPointGroups(pointField, role).forEach((group) => {{
        const uniqueQuests = sortedQuestList(group.quests.values());
        const marker = document.createElement("button");
        marker.type = "button";
        marker.className = `map-marker available-${{role === "handin" ? "handin" : "objective"}}`;
        marker.dataset.questId = uniqueQuests[0].id;
        marker.dataset.questIds = `|${{uniqueQuests.map((quest) => quest.id).join("|")}}|`;
        marker.dataset.displayRole = role;
        marker.style.left = `${{group.x}}%`;
        marker.style.top = `${{group.y}}%`;
        marker.innerHTML = `
          <span class="display-marker-glyph">${{role === "handin" ? "?" : ""}}</span>
          ${{uniqueQuests.length > 1 ? `<span class="pickup-count">${{uniqueQuests.length}}</span>` : ""}}
        `;
        marker.setAttribute("aria-label", [displayPointPopoverTitle(group), ...uniqueQuests.slice(0, 6).map((quest) => quest.name)].join(", "));
        marker.addEventListener("mouseenter", () => showDisplayPointTooltip(group));
        marker.addEventListener("mouseleave", schedulePickupPopoverClose);
        marker.addEventListener("focus", () => showDisplayPointTooltip(group));
        marker.addEventListener("blur", schedulePickupPopoverClose);
        marker.addEventListener("click", (event) => {{
          event.stopPropagation();
          if (uniqueQuests.length === 1) {{
            closePickupQuestList();
            selectQuest(uniqueQuests[0].id, {{ scrollChainToTop: true }});
          }} else {{
            showDisplayPointTooltip(group);
          }}
        }});
        markerLayer.append(marker);
      }});
    }}

    function renderAvailablePickupMarkers() {{
      markerLayer.innerHTML = "";
      if (displayFilters.has("available-pickups")) {{
        const groups = new Map();
        currentQuests().forEach((quest) => {{
          const starts = visibleStartPoints(quest);
          const representative = representativeStartPoint(starts);
          if (!representative) return;
          const {{ point, plotted }} = representative;
          const key = `${{currentView.type}}:${{point.zoneId ?? "world"}}:${{plotted.x.toFixed(2)}}:${{plotted.y.toFixed(2)}}`;
          if (!groups.has(key)) {{
            groups.set(key, {{
              key,
              x: plotted.x,
              y: plotted.y,
              quests: new Map(),
              sourceNames: new Set(),
              alternateCounts: new Map(),
            }});
          }}
          const group = groups.get(key);
          group.quests.set(quest.id, quest);
          group.alternateCounts.set(quest.id, starts.length);
          group.sourceNames.add(pointSourceName(point, quest));
        }});

        const laidOutGroups = layoutPickupGroups([...groups.values()]);
        laidOutGroups.forEach((group) => {{
          const uniqueQuests = sortedQuestList(group.quests.values());
          const pickupGroupCount = (group.pickupGroups || [group]).length;
          const marker = document.createElement("button");
          marker.type = "button";
          marker.className = "map-marker available-pickup";
          marker.dataset.questId = uniqueQuests[0].id;
          marker.dataset.questIds = `|${{uniqueQuests.map((quest) => quest.id).join("|")}}|`;
          marker.dataset.pickupGroupCount = pickupGroupCount;
          marker.dataset.originX = group.x.toFixed(3);
          marker.dataset.originY = group.y.toFixed(3);
          marker.dataset.displayX = (group.displayX ?? group.x).toFixed(3);
          marker.dataset.displayY = (group.displayY ?? group.y).toFixed(3);
          marker.style.left = `${{group.displayX ?? group.x}}%`;
          marker.style.top = `${{group.displayY ?? group.y}}%`;
          const ringGradient = pickupRingGradient(uniqueQuests);
          const markerDifficulty = uniqueQuests.length === 1 && pickupGroupCount === 1 ? questDifficultyId(uniqueQuests[0]) : null;
          marker.dataset.difficulty = markerDifficulty || (uniqueQuests.length > 1 ? "multi" : "none");
          marker.dataset.ring = ringGradient ? "difficulty" : "plain";
          if (ringGradient) marker.style.setProperty("--pickup-ring", ringGradient);
          if (markerDifficulty) {{
            marker.classList.add("single-pickup");
            marker.style.setProperty("--quest-difficulty-color", questDifficultyColor(uniqueQuests[0]));
          }}
          marker.innerHTML = `
            <span class="pickup-glyph">!</span>
            ${{uniqueQuests.length > 1 ? `<span class="pickup-count">${{uniqueQuests.length}}</span>` : ""}}
            ${{questTypeBadgesHtml(uniqueQuests)}}
          `;
          marker.setAttribute("aria-label", [pickupPopoverTitle(group), ...uniqueQuests.slice(0, 6).map((quest) => quest.name)].join(", "));
          marker.addEventListener("mouseenter", () => showPickupQuestList(group));
          marker.addEventListener("mouseleave", schedulePickupPopoverClose);
          marker.addEventListener("focus", () => showPickupQuestList(group));
          marker.addEventListener("blur", schedulePickupPopoverClose);
          marker.addEventListener("click", (event) => {{
            event.stopPropagation();
            if (uniqueQuests.length === 1 && pickupGroupCount === 1) {{
              closePickupQuestList();
              selectQuest(uniqueQuests[0].id, {{ scrollChainToTop: true }});
            }} else {{
              showPickupQuestList(group);
            }}
          }});
          markerLayer.append(marker);
        }});
      }}
      if (displayFilters.has("quest-objectives")) renderObjectivePointMarkers();
      if (displayFilters.has("quest-handins")) renderDisplayPointMarkers("handin", "endPoints");
    }}

    function layoutPickupGroups(groups) {{
      const rect = markerLayer.getBoundingClientRect();
      const width = Math.max(1, rect.width);
      const height = Math.max(1, rect.height);
      const minSeparation = currentView.type === "world" ? 30 : 36;
      const maxDrift = currentView.type === "world" ? 18 : 86;
      const mergeRadius = minSeparation + maxDrift + 8;
      const pad = minSeparation / 2 + 5;
      const maxRadius = currentView.type === "world" ? 74 : 190;
      const cellSize = minSeparation;
      const cells = new Map();
      const placedClusters = [];

      const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
      const cellKey = (x, y) => `${{Math.floor(x / cellSize)}}:${{Math.floor(y / cellSize)}}`;
      const addToGrid = (node) => {{
        const key = cellKey(node.x, node.y);
        if (!cells.has(key)) cells.set(key, []);
        cells.get(key).push(node);
      }};
      const nearbyNodes = (x, y) => {{
        const cellX = Math.floor(x / cellSize);
        const cellY = Math.floor(y / cellSize);
        const nodes = [];
        for (let dx = -1; dx <= 1; dx += 1) {{
          for (let dy = -1; dy <= 1; dy += 1) {{
            const bucket = cells.get(`${{cellX + dx}}:${{cellY + dy}}`);
            if (bucket) nodes.push(...bucket);
          }}
        }}
        return nodes;
      }};
      const overlapScore = (x, y) => nearbyNodes(x, y).reduce((score, node) => {{
        const distance = Math.hypot(node.x - x, node.y - y);
        return score + Math.max(0, minSeparation - distance);
      }}, 0);
      const hasRoom = (x, y) => overlapScore(x, y) === 0;
      const chooseSpot = (originX, originY, index) => {{
        const startX = clamp(originX, pad, width - pad);
        const startY = clamp(originY, pad, height - pad);
        const startDrift = Math.hypot(startX - originX, startY - originY);
        if (hasRoom(startX, startY)) return {{ x: startX, y: startY, drift: startDrift, overlap: 0, atStart: true }};

        let best = {{ x: startX, y: startY, score: overlapScore(startX, startY) * 1000 + startDrift, drift: startDrift, overlap: overlapScore(startX, startY), atStart: true }};
        for (let radius = minSeparation; radius <= maxRadius; radius += minSeparation * 0.6) {{
          const steps = Math.max(12, Math.ceil((Math.PI * 2 * radius) / (minSeparation * 0.72)));
          let bestAtRadius = null;
          for (let step = 0; step < steps; step += 1) {{
            const angle = ((Math.PI * 2) * step) / steps + index * 0.43;
            const x = clamp(startX + Math.cos(angle) * radius, pad, width - pad);
            const y = clamp(startY + Math.sin(angle) * radius, pad, height - pad);
            const overlap = overlapScore(x, y);
            const drift = Math.hypot(x - originX, y - originY);
            const score = overlap * 1000 + drift;
            if (!bestAtRadius || score < bestAtRadius.score) bestAtRadius = {{ x, y, score, overlap, drift, atStart: false }};
            if (score < best.score) best = {{ x, y, score, overlap, drift, atStart: false }};
          }}
          if (bestAtRadius && bestAtRadius.overlap === 0 && bestAtRadius.drift <= maxDrift) return bestAtRadius;
        }}
        return best;
      }};
      const nearestMergeTarget = (originX, originY) => {{
        const candidates = new Map();
        nearbyNodes(originX, originY).forEach((node) => candidates.set(node.cluster.key, node.cluster));
        placedClusters.forEach((cluster) => {{
          const distance = Math.hypot(cluster.pixelX - originX, cluster.pixelY - originY);
          if (distance <= mergeRadius) candidates.set(cluster.key, cluster);
        }});
        return [...candidates.values()]
          .map((cluster) => ({{ cluster, distance: Math.hypot(cluster.pixelX - originX, cluster.pixelY - originY) }}))
          .filter((item) => item.distance <= mergeRadius)
          .sort((a, b) => a.distance - b.distance || b.cluster.quests.size - a.cluster.quests.size)[0]?.cluster || null;
      }};

      groups
        .sort((a, b) => b.quests.size - a.quests.size || a.y - b.y || a.x - b.x || a.key.localeCompare(b.key))
        .forEach((group, index) => {{
          const originX = (group.x / 100) * width;
          const originY = (group.y / 100) * height;
          const spot = chooseSpot(originX, originY, index);
          const mergeTarget = spot.overlap === 0 && (spot.atStart || spot.drift <= maxDrift)
            ? null
            : nearestMergeTarget(originX, originY);
          if (mergeTarget) {{
            absorbPickupGroup(mergeTarget, group);
            return;
          }}

          const cluster = pickupClusterFromGroup(group);
          cluster.pixelX = spot.x;
          cluster.pixelY = spot.y;
          cluster.displayX = (spot.x / width) * 100;
          cluster.displayY = (spot.y / height) * 100;
          placedClusters.push(cluster);
          addToGrid({{ x: spot.x, y: spot.y, cluster }});
        }});
      return placedClusters;
    }}

    function clearPickupPopoverCloseTimer() {{
      if (!pickupPopoverCloseTimer) return;
      window.clearTimeout(pickupPopoverCloseTimer);
      pickupPopoverCloseTimer = 0;
    }}

    function schedulePickupPopoverClose() {{
      clearPickupPopoverCloseTimer();
      pickupPopoverCloseTimer = window.setTimeout(() => {{
        pickupPopoverCloseTimer = 0;
        closePickupQuestList();
      }}, 220);
    }}

    function closePickupQuestList() {{
      clearPickupPopoverCloseTimer();
      markerLayer.querySelector(".pickup-choice-popover")?.remove();
    }}

    function clampNumber(value, min, max) {{
      return Math.min(max, Math.max(min, value));
    }}

    function positionPickupPopover(popover, group) {{
      const margin = 8;
      const gap = 14;
      const layerWidth = Math.max(1, markerLayer.clientWidth);
      const layerHeight = Math.max(1, markerLayer.clientHeight);
      const anchorX = ((group.displayX ?? group.x) / 100) * layerWidth;
      const anchorY = ((group.displayY ?? group.y) / 100) * layerHeight;
      popover.style.maxHeight = `${{Math.max(120, Math.min(560, window.innerHeight * 0.72, layerHeight - margin * 2))}}px`;
      const width = popover.offsetWidth;
      const height = popover.offsetHeight;
      const maxLeft = Math.max(margin, layerWidth - width - margin);
      const maxTop = Math.max(margin, layerHeight - height - margin);
      let left = anchorX + gap;
      if (left + width > layerWidth - margin) left = anchorX - width - gap;
      if (left < margin) left = clampNumber(anchorX - width / 2, margin, maxLeft);
      const top = clampNumber(anchorY - height / 2, margin, maxTop);
      popover.style.left = `${{left}}px`;
      popover.style.top = `${{top}}px`;
      popover.style.translate = "0 0";
    }}

    function sortedPickupChoiceQuests(quests) {{
      const chains = new Map();
      quests.forEach((quest) => {{
        const chain = chains.get(quest.chainId) || {{
          minRequiredLevel: Infinity,
          minQuestLevel: Infinity,
          name: quest.chainName || "",
        }};
        chain.minRequiredLevel = Math.min(chain.minRequiredLevel, quest.requiredLevel ?? 0);
        chain.minQuestLevel = Math.min(chain.minQuestLevel, quest.questLevel ?? quest.requiredLevel ?? 0);
        chains.set(quest.chainId, chain);
      }});
      return quests.slice().sort((a, b) => {{
        const chainA = chains.get(a.chainId);
        const chainB = chains.get(b.chainId);
        return chainA.minRequiredLevel - chainB.minRequiredLevel ||
          chainA.minQuestLevel - chainB.minQuestLevel ||
          chainA.name.localeCompare(chainB.name) ||
          a.chainId - b.chainId ||
          a.chainStep - b.chainStep ||
          (a.requiredLevel ?? 0) - (b.requiredLevel ?? 0) ||
          (a.questLevel ?? a.requiredLevel ?? 0) - (b.questLevel ?? b.requiredLevel ?? 0) ||
          a.id - b.id;
      }});
    }}

    function pickupChoiceItemsHtml(quests) {{
      let previousChainId = null;
      return sortedPickupChoiceQuests(quests).map((quest) => {{
        const divider = previousChainId !== null && previousChainId !== quest.chainId
          ? '<div class="pickup-choice-chain-break" aria-hidden="true"></div>'
          : "";
        previousChainId = quest.chainId;
        return `${{divider}}
          <button type="button" class="pickup-choice-item" data-quest-id="${{quest.id}}">
            <span class="pickup-choice-name-row">
              <span class="pickup-choice-name" ${{questDifficultyAttrs(quest)}}>${{escapeHtml(quest.name)}}</span>
              ${{questTypeTextBadgesHtml(quest)}}
            </span>
            <span class="pickup-choice-meta">${{quest.requiredLevel ?? "?"}} / ${{quest.questLevel ?? "?"}} - ${{escapeHtml(quest.chainName)}}</span>
          </button>`;
      }}).join("");
    }}

    function showPickupQuestList(group) {{
      clearPickupPopoverCloseTimer();
      closePickupQuestList();
      const popover = document.createElement("div");
      popover.className = "pickup-choice-popover";
      const sections = pickupSections(group);
      const title = pickupPopoverTitle(group);
      const showSectionHeadings = sections.length > 1 || (sections[0]?.title ?? "") !== title;
      popover.style.left = "0px";
      popover.style.top = "0px";
      popover.innerHTML = `
        <div class="pickup-choice-title">${{escapeHtml(title)}}</div>
        ${{sections.map((section) => `
          <div class="pickup-choice-section">
            ${{showSectionHeadings ? `<div class="pickup-choice-heading">${{escapeHtml(section.title)}}</div>` : ""}}
            ${{pickupChoiceItemsHtml(section.quests)}}
          </div>
        `).join("")}}
      `;
      popover.addEventListener("click", (event) => {{
        event.stopPropagation();
        const item = event.target.closest(".pickup-choice-item");
        if (!item) return;
        closePickupQuestList();
        selectQuest(Number(item.dataset.questId), {{ scrollChainToTop: true }});
      }});
      popover.addEventListener("mouseenter", clearPickupPopoverCloseTimer);
      popover.addEventListener("mouseleave", schedulePickupPopoverClose);
      markerLayer.append(popover);
      positionPickupPopover(popover, group);
    }}

    function showDisplayPointTooltip(group) {{
      clearPickupPopoverCloseTimer();
      closePickupQuestList();
      const popover = document.createElement("div");
      popover.className = "pickup-choice-popover display-marker-popover";
      popover.style.left = "0px";
      popover.style.top = "0px";
      popover.innerHTML = `
        <div class="pickup-choice-title">${{escapeHtml(displayPointPopoverTitle(group))}}</div>
        <div class="pickup-choice-note">${{escapeHtml(displayPointPopoverNote(group))}}</div>
        <div class="pickup-choice-section">
          ${{pickupChoiceItemsHtml(sortedQuestList(group.quests.values()))}}
        </div>
      `;
      popover.addEventListener("click", (event) => {{
        event.stopPropagation();
        const item = event.target.closest(".pickup-choice-item");
        if (!item) return;
        closePickupQuestList();
        selectQuest(Number(item.dataset.questId), {{ scrollChainToTop: true }});
      }});
      popover.addEventListener("mouseenter", clearPickupPopoverCloseTimer);
      popover.addEventListener("mouseleave", schedulePickupPopoverClose);
      markerLayer.append(popover);
      positionPickupPopover(popover, group);
    }}

    function selectQuest(id, options = {{}}) {{
      selectedId = id;
      const quest = questsById.get(id);
      if (quest) {{
        const previousScrollTop = chainList.scrollTop;
        expandedChainIds.add(quest.chainId);
        renderInventory();
        if (options.scrollChainToTop) {{
          scrollChainToTop(quest.chainId);
        }} else if (options.scrollQuestIntoView) {{
          scrollQuestIntoCatalogueView(id);
        }} else {{
          chainList.scrollTop = previousScrollTop;
        }}
        if (options.focusQuest) focusCatalogueQuest(id);
      }}
      activateQuest(id, false);
    }}

    function openJourneyQuestInCatalogue(id) {{
      const quest = questsById.get(Number(id));
      if (!quest) return;
      forcedCatalogueChainId = quest.chainId;
      expandedChainIds.add(quest.chainId);
      selectQuest(quest.id, {{ scrollChainToTop: true, focusQuest: true }});
      showJourneyMessage(`Showing ${{quest.chainName}} in the Quest Catalogue.`, "ok");
    }}

    function scrollChainToTop(chainId) {{
      const row = document.querySelector(`.chain-row[data-chain-id="${{chainId}}"]`);
      if (!row) return;
      const listRect = chainList.getBoundingClientRect();
      const rowRect = row.getBoundingClientRect();
      chainList.scrollTop += rowRect.top - listRect.top - 8;
    }}

    function activateQuest(id, scrollIntoView = true) {{
      activeId = id;
      const quest = questsById.get(id);
      if (!quest) return;

      document.querySelectorAll(".quest-icon").forEach((icon) => {{
        const questId = Number(icon.dataset.questId);
        icon.classList.toggle("active", questId === id);
        icon.classList.toggle("selected", selectedId !== null && questId === selectedId);
      }});
      document.querySelectorAll(".chain-quest-item").forEach((item) => {{
        const questId = Number(item.dataset.questId);
        item.classList.toggle("active", questId === id);
        item.classList.toggle("selected", selectedId !== null && questId === selectedId);
      }});
      document.querySelectorAll(".journey-quest").forEach((item) => {{
        const questId = Number(item.dataset.questId);
        item.classList.toggle("active", questId === id);
        item.classList.toggle("selected", selectedId !== null && questId === selectedId);
      }});
      document.querySelectorAll(".chain-row").forEach((row) => {{
        row.classList.toggle("active", Number(row.dataset.chainId) === quest.chainId);
      }});
      document.querySelectorAll(".map-marker").forEach((marker) => {{
        const questId = Number(marker.dataset.questId);
        const questIds = marker.dataset.questIds || `|${{questId}}|`;
        marker.classList.toggle("active", questIds.includes(`|${{id}}|`));
        marker.classList.toggle("selected", selectedId !== null && questIds.includes(`|${{selectedId}}|`));
      }});
      if (scrollIntoView) {{
        const target = document.querySelector(`.chain-quest-item[data-quest-id="${{id}}"]`) || document.querySelector(`.quest-icon[data-quest-id="${{id}}"]`);
        target?.scrollIntoView({{ block: "start", inline: "nearest" }});
      }}
      renderOverlay(quest);
      renderDetails(quest);
    }}

    function renderOverlay(quest) {{
      highlightLayer.innerHTML = "";
      highlightLayer.style.setProperty("--chain-color", questObjectiveColor(quest));
      const objectivePoints = relevantPoints(quest.objectivePoints);
      renderObjectiveLayer(objectivePoints);
      const startPoints = relevantPoints(quest.startPoints);
      if (startPoints.length > 1) {{
        renderPickupDots(startPoints);
      }} else if (!displayFilters.has("available-pickups")) {{
        renderPins(startPoints, "pickup", "!", "Quest pickup");
      }}
      renderPins(relevantPoints(quest.endPoints), "turnin", "?", "Quest turn-in");
    }}

    function relevantPoints(points) {{
      return points.map(viewPoint).filter(Boolean);
    }}

    function renderObjectiveLayer(points) {{
      if (points.length) {{
        const bounds = points.reduce((box, point) => {{
          box.minX = Math.min(box.minX, point.x);
          box.maxX = Math.max(box.maxX, point.x);
          box.minY = Math.min(box.minY, point.y);
          box.maxY = Math.max(box.maxY, point.y);
          return box;
        }}, {{ minX: 100, maxX: 0, minY: 100, maxY: 0 }});
        const spreadX = bounds.maxX - bounds.minX;
        const spreadY = bounds.maxY - bounds.minY;
        if (currentView.type === "zone" || (spreadX <= 24 && spreadY <= 30)) {{
          const pad = points.length === 1 ? 4 : 2.8;
          const area = document.createElement("div");
          area.className = "objective-area";
          area.style.left = `${{(bounds.minX + bounds.maxX) / 2}}%`;
          area.style.top = `${{(bounds.minY + bounds.maxY) / 2}}%`;
          area.style.width = `${{Math.max(5, spreadX + pad * 2)}}%`;
          area.style.height = `${{Math.max(7, spreadY + pad * 2)}}%`;
          highlightLayer.append(area);
        }}
      }}
      points.forEach((point) => {{
        const dot = document.createElement("div");
        dot.className = "objective-dot";
        dot.style.left = `${{point.x}}%`;
        dot.style.top = `${{point.y}}%`;
        highlightLayer.append(dot);
      }});
    }}

    function renderPins(points, type, glyph, label) {{
      points.forEach((point, index) => {{
        const pin = document.createElement("div");
        pin.className = `quest-pin ${{type}}`;
        pin.style.left = `${{point.x}}%`;
        pin.style.top = `${{point.y}}%`;
        pin.textContent = glyph;
        pin.setAttribute("aria-label", `${{label}} ${{index + 1}}`);
        highlightLayer.append(pin);
      }});
    }}

    function renderPickupDots(points) {{
      points.forEach((point) => {{
        const dot = document.createElement("span");
        dot.className = "pickup-dot";
        dot.style.left = `${{point.x}}%`;
        dot.style.top = `${{point.y}}%`;
        dot.setAttribute("aria-label", "Alternate quest pickup");
        highlightLayer.append(dot);
      }});
    }}

    function questLinkList(ids) {{
      if (!ids || !ids.length) return "None";
      return ids.map((id) => {{
        const quest = questsById.get(id);
        return quest ? `${{escapeHtml(quest.name)}} (#${{id}})` : `#${{id}}`;
      }}).join(", ");
    }}

    function zoneList(quest) {{
      if (!quest.zones.length) return "No mapped zone";
      return quest.zones.slice(0, 5).map((zoneId) => zonesById.get(zoneId)?.name || `Zone ${{zoneId}}`).join(", ") + (quest.zones.length > 5 ? "..." : "");
    }}

    function renderDetails(quest) {{
      if (!details) return;
      const objectives = [
        ...(quest.objectiveSummary || []),
        ...(quest.objectiveText || []),
      ];
      const uniqueObjectives = [...new Set(objectives)].filter(Boolean);
      const startCount = relevantPoints(quest.startPoints).length;
      const endCount = relevantPoints(quest.endPoints).length;
      const objectiveCount = relevantPoints(quest.objectivePoints).length;
      const typePills = (quest.typeLabels || ["General progression"])
        .map((label) => `<span class="type-pill">${{escapeHtml(label)}}</span>`)
        .join("");
      details.style.setProperty("--chain-color", quest.chainColor);
      details.innerHTML = `
        <div>
          <h2>${{escapeHtml(quest.name)}} <span style="color:#a99b83">#${{quest.id}}</span></h2>
          <span class="chain-pill">${{escapeHtml(quest.chainName)}} - ${{quest.chainStep}}/${{quest.chainLength}}</span>
          <div class="type-pills">${{typePills}}</div>
          <p class="body-copy">${{escapeHtml(zoneList(quest))}}</p>
        </div>
        <div class="objective-panel">
          <span class="label">Objectives</span>
          <ul class="objective-list">
            ${{uniqueObjectives.length ? uniqueObjectives.map((item) => `<li>${{escapeHtml(item)}}</li>`).join("") : "<li>No explicit objective text in Questie.</li>"}}
          </ul>
        </div>
        <div class="meta-grid">
          <div class="meta"><span class="label">Levels</span><span class="value">Requires ${{quest.requiredLevel ?? "?"}}<br>Quest ${{quest.questLevel ?? "?"}}</span></div>
          <div class="meta"><span class="label">Availability</span><span class="value">${{escapeHtml(quest.raceRequirement)}}<br>${{escapeHtml(quest.classRequirement)}}</span></div>
          <div class="meta"><span class="label">Map Points</span><span class="value">${{startCount}} pickup - ${{endCount}} turn-in<br>${{objectiveCount}} objective</span></div>
          <div class="meta"><span class="label">Starts</span><span class="value">${{sourceListHtml(quest.startSources)}}</span></div>
          <div class="meta"><span class="label">Ends</span><span class="value">${{sourceListHtml(quest.endSources)}}</span></div>
          <div class="meta"><span class="label">Prerequisites</span><span class="value">${{questPrerequisiteHtml(quest)}}</span></div>
          <div class="meta"><span class="label">Chain</span><span class="value">Prev: ${{questLinkList([...quest.preQuestGroup, ...quest.preQuestSingle])}}<br>Next: ${{quest.nextQuestInChain ? questLinkList([quest.nextQuestInChain]) : "None"}}</span></div>
        </div>
      `;
    }}

    function escapeHtml(value) {{
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
    }}

    worldButton.addEventListener("click", setWorldView);
    mapViewButton.addEventListener("click", () => setAppMode("map"));
    sequencerViewButton.addEventListener("click", () => setAppMode("sequencer"));
    zoneSelect.addEventListener("change", (event) => {{
      if (event.target.value) setZoneView(event.target.value);
      else setWorldView();
    }});
    raceFilter.addEventListener("change", updateFiltersFromControls);
    classFilter.addEventListener("change", updateFiltersFromControls);
    levelFilter.addEventListener("change", () => {{
      if (selectedBatchId != null) deselectJourneyBatch({{ restoreLevel: false }});
      updateFiltersFromControls();
    }});
    questSearch.addEventListener("input", updateSearchFilterFromInput);
    questSearchClear.addEventListener("click", () => {{
      questSearch.value = "";
      updateSearchFilterFromInput();
      questSearch.focus();
    }});
    mapEl.addEventListener("mousemove", handleWorldZonePointerMove);
    mapEl.addEventListener("mouseleave", hideWorldZoneTooltip);
    mapEl.addEventListener("click", handleWorldZoneClick);
    collapseAllChainsButton.addEventListener("click", collapseAllChains);
    expandAllChainsButton.addEventListener("click", expandAllChains);
    chainList.addEventListener("dragstart", handleCatalogueDragStart);
    chainList.addEventListener("dragend", handleCatalogueDragEnd);
    journeySetup.addEventListener("submit", (event) => {{
      event.preventDefault();
      createJourneyFromSetup();
    }});
    journeyNameInput.addEventListener("input", updateJourneyStartButton);
    journeyRaceSelect.addEventListener("change", updateJourneyStartButton);
    journeyClassSelect.addEventListener("change", updateJourneyStartButton);
    journeyNameEditor.addEventListener("input", () => {{
      if (!activeJourney) return;
      activeJourney.name = journeyNameEditor.value.trim() || activeJourney.name;
    }});
    journeySaveButton.addEventListener("click", saveJourneyJson);
    journeyImportButton.addEventListener("click", () => journeyImportInput.click());
    journeyImportInput.addEventListener("change", () => {{
      importJourneyFile(journeyImportInput.files?.[0]);
      journeyImportInput.value = "";
    }});
    sequencerBoard.addEventListener("dragstart", handleJourneyDragStart);
    sequencerBoard.addEventListener("dragend", handleCatalogueDragEnd);
    sequencerBoard.addEventListener("dragenter", handleSequencerDragOver);
    sequencerBoard.addEventListener("dragover", handleSequencerDragOver);
    sequencerBoard.addEventListener("dragleave", handleSequencerDragLeave);
    sequencerBoard.addEventListener("drop", handleSequencerDrop);
    sequencerBoard.addEventListener("click", (event) => {{
      const insertTarget = event.target.closest(".journey-insert-target");
      if (insertTarget) {{
        insertBatchAt(Number(insertTarget.dataset.insertIndex));
        return;
      }}
      const removeButton = event.target.closest(".journey-quest-remove");
      if (removeButton) {{
        const questNode = removeButton.closest(".journey-quest");
        if (questNode) removeQuestFromJourney(Number(questNode.dataset.questId));
        return;
      }}
      const unhideButton = event.target.closest(".journey-quest-unhide");
      if (unhideButton) {{
        const questNode = unhideButton.closest(".journey-quest");
        if (questNode) restoreUnusedQuest(Number(questNode.dataset.questId));
        return;
      }}
      const questNode = event.target.closest(".journey-quest");
      if (questNode) {{
        openJourneyQuestInCatalogue(Number(questNode.dataset.questId));
        return;
      }}
      const batchHead = event.target.closest(".journey-batch-head");
      if (batchHead) {{
        selectJourneyBatch(batchHead.dataset.batchId);
      }}
    }});
    sequencerPanel.addEventListener("click", (event) => {{
      if (!activeJourney || journeyWorkspace.hidden) return;
      if (event.target.closest(".journey-batch, .journey-head, .journey-message, .journey-insert-target")) return;
      deselectJourneyBatch();
    }});
    questFilterButton.addEventListener("click", () => {{
      setQuestFilterMenuOpen(questFilterMenu.hidden);
      setZoneFilterMenuOpen(false);
      setDisplayFilterMenuOpen(false);
      setOptionsFilterMenuOpen(false);
    }});
    zoneFilterButton.addEventListener("click", () => {{
      setZoneFilterMenuOpen(zoneFilterMenu.hidden);
      setQuestFilterMenuOpen(false);
      setDisplayFilterMenuOpen(false);
      setOptionsFilterMenuOpen(false);
    }});
    displayFilterButton.addEventListener("click", () => {{
      setDisplayFilterMenuOpen(displayFilterMenu.hidden);
      setQuestFilterMenuOpen(false);
      setZoneFilterMenuOpen(false);
      setOptionsFilterMenuOpen(false);
    }});
    optionsFilterButton.addEventListener("click", () => {{
      setOptionsFilterMenuOpen(optionsFilterMenu.hidden);
      setQuestFilterMenuOpen(false);
      setZoneFilterMenuOpen(false);
      setDisplayFilterMenuOpen(false);
    }});
    document.addEventListener("click", (event) => {{
      const zoneLink = event.target.closest(".zone-link");
      if (!zoneLink) return;
      event.preventDefault();
      event.stopPropagation();
      setZoneView(zoneLink.dataset.zoneId);
    }});
    document.addEventListener("click", (event) => {{
      if (!event.target.closest(".pickup-choice-popover, .available-pickup")) {{
        closePickupQuestList();
      }}
      if (!questFilterWrap.contains(event.target)) {{
        setQuestFilterMenuOpen(false);
      }}
      if (!zoneFilterWrap.contains(event.target)) {{
        setZoneFilterMenuOpen(false);
      }}
      if (!displayFilterWrap.contains(event.target)) {{
        setDisplayFilterMenuOpen(false);
      }}
      if (!optionsFilterWrap.contains(event.target)) {{
        setOptionsFilterMenuOpen(false);
      }}
    }});
    document.addEventListener("keydown", (event) => {{
      if ((event.key === "ArrowDown" || event.key === "ArrowUp") && canUseCatalogueArrowKeys(event.target)) {{
        if (moveCatalogueSelection(event.key === "ArrowDown" ? 1 : -1)) {{
          event.preventDefault();
          closePickupQuestList();
        }}
      }}
      if (event.key === "Escape") {{
        setQuestFilterMenuOpen(false);
        setZoneFilterMenuOpen(false);
        setDisplayFilterMenuOpen(false);
        setOptionsFilterMenuOpen(false);
        closePickupQuestList();
      }}
    }});

    populateZoneSelect();
    populateFilters();
    populateQuestFilters();
    populateZoneFilters();
    populateDisplayFilters();
    populateOptionsFilters();
    populateJourneySetupControls();
    renderWorldTiles();
    renderJourney();
    setAppMode("map");
    updateSearchClearButton();
    new ResizeObserver(scheduleMapFit).observe(mapFrame);
    window.addEventListener("resize", scheduleMapFit);
    setWorldView();
  </script>
</body>
</html>
"""
    return html


def main():
    records, chains, zones, continents = build_classic_records()
    output = ROOT / "questieplus.html"
    output.write_text(render_classic_html(records, chains, zones, continents), encoding="utf-8")
    print(f"Wrote {output}")
    print(f"Quest records: {len(records)}")
    print(f"Chains: {len(chains)}")
    print(f"Zone maps: {len(zones)}")


if __name__ == "__main__":
    main()
