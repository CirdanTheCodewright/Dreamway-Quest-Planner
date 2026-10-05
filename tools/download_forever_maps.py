"""Import versioned Forever client artwork and normalized UiMap relationships.

The mirror supplies client art, not NPC/quest positions; those remain QuestieDB-owned.
Run with --build matching the installed beta to refresh deliberately.
"""
import argparse
import hashlib
import io
import json
import re
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/forever-maps"
SOURCE = "https://theforeverera.com/en/map/"
HOST = "https://theforeverera.com"
CROPS = {1414: (244, 0, 745, 668), 1415: (234, 0, 735, 668)}


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Dreamway map importer"})
    with urllib.request.urlopen(request, timeout=45) as response:
        return response.read()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", required=True)
    args = parser.parse_args()
    page = fetch(SOURCE).decode("utf-8")
    match = re.search(r'<script type="application/json" id="wm-data">(.*?)</script>', page, re.S)
    if not match:
        raise ValueError("Versioned map manifest missing")
    data = json.loads(match.group(1))
    if data["build"] != args.build:
        raise ValueError(f"Mirror build {data['build']} differs from requested {args.build}")
    maps = data["maps"]
    if len({m["id"] for m in maps}) != len(maps):
        raise ValueError("Duplicate map IDs")

    def download(record):
        # Restrict imports to declared map assets; never follow arbitrary page URLs.
        map_id = int(record["id"])
        if record["img"] != f"/maps/{map_id}.webp":
            raise ValueError(f"Unexpected map asset path: {record['img']}")
        raw = fetch(HOST + record["img"])
        image = Image.open(io.BytesIO(raw)).convert("RGB")
        if image.size != (record["w"], record["h"]):
            raise ValueError(f"Map {map_id}: image dimensions differ from manifest")
        source_dir = ASSETS / "source"
        source_dir.mkdir(parents=True, exist_ok=True)
        (source_dir / f"{map_id}.webp").write_bytes(raw)
        if map_id in CROPS:
            image = image.crop(CROPS[map_id])
        target = ASSETS / "maps" / f"{map_id}.jpg"
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target, quality=94, optimize=True)
        return {**record, "sourceUrl": HOST + record["img"],
                "sha256": hashlib.sha256(raw).hexdigest(),
                "image": target.relative_to(ROOT).as_posix(),
                "crop": list(CROPS.get(map_id, (0, 0, record["w"], record["h"])))}

    with ThreadPoolExecutor(max_workers=4) as pool:
        imported = list(pool.map(download, maps))
    manifest = {"build": data["build"], "source": SOURCE,
                "artworkOwner": "Blizzard Entertainment", "maps": imported}
    (ASSETS / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8", newline="\n")
    print(f"Imported {len(imported)} native Forever maps from build {data['build']}")
    from build_forever_explored_maps import build
    build(args.build)


if __name__ == "__main__":
    main()
