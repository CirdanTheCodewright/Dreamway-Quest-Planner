"""Compose fully explored Forever maps from version-pinned native CASC textures.

All base tiles and every unconditional exploration overlay come from the same build.
Composition happens offline; Dreamway only loads the resulting compressed images.
"""
import argparse
import csv
import hashlib
import io
import json
import math
import time
import urllib.error
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/forever-maps"
CACHE = ROOT / "tools/.runtime/forever-textures"
TABLES = ("UiMapXMapArt", "UiMapArt", "UiMapArtStyleLayer", "UiMapArtTile",
          "WorldMapOverlay", "WorldMapOverlayTile")
HOST = "https://wago.tools"


def fetch(url, referer):
    # Use normal browser request headers; the file service rejects urllib's default UA.
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Referer": referer})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError):
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def build(build):
    manifest_path = ASSETS / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest["build"] != build:
        raise ValueError("Base-map relationships and exploration textures must use the same build")
    metadata_dir = ASSETS / "metadata" / build
    metadata_dir.mkdir(parents=True, exist_ok=True)
    tables = {}
    sources = {}
    for name in TABLES:
        path = metadata_dir / f"{name}.csv"
        url = f"{HOST}/db2/{name}/csv?build={build}"
        data = path.read_bytes() if path.exists() else fetch(url, f"{HOST}/db2/{name}")
        rows = list(csv.DictReader(io.StringIO(data.decode("utf-8-sig"))))
        if not rows or "ID" not in rows[0]:
            raise ValueError(f"Invalid native {name} table")
        tables[name] = [{key: int(value or 0) for key, value in row.items()
                         if key not in ("MinScale", "MaxScale")} for row in rows]
        path.write_bytes(data)
        sources[name] = {"url": url, "sha256": hashlib.sha256(data).hexdigest(),
                         "path": path.relative_to(ROOT).as_posix()}
    map_arts = {row["UiMapID"]: row["UiMapArtID"] for row in tables["UiMapXMapArt"] if row["PhaseID"] == 0}
    arts = {row["ID"]: row for row in tables["UiMapArt"]}
    styles = {(row["UiMapArtStyleID"], row["LayerIndex"]): row for row in tables["UiMapArtStyleLayer"]}
    base_tiles = defaultdict(list)
    overlay_tiles = defaultdict(list)
    overlays = defaultdict(list)
    for row in tables["UiMapArtTile"]:
        if row["LayerIndex"] == 0:
            base_tiles[row["UiMapArtID"]].append(row)
    for row in tables["WorldMapOverlayTile"]:
        if row["LayerIndex"] == 0:
            overlay_tiles[row["WorldMapOverlayID"]].append(row)
    for row in tables["WorldMapOverlay"]:
        overlays[row["UiMapArtID"]].append(row)

    plans = []
    files = set()
    for entry in manifest["maps"]:
        art_id = map_arts[entry["id"]]
        style = styles[(arts[art_id]["UiMapArtStyleID"], 0)]
        if (style["LayerWidth"], style["LayerHeight"]) != (entry["w"], entry["h"]):
            raise ValueError(f"Map {entry['id']}: native layer size differs from its coordinate frame")
        # Native tables retain discovery rectangles without artwork (e.g. STV's
        # Zul'Gurub rectangle). The client has no texture to draw for those rows.
        tileless = [row["ID"] for row in overlays[art_id] if not overlay_tiles[row["ID"]]]
        selected = [row for row in overlays[art_id] if overlay_tiles[row["ID"]]]
        if any(row["PlayerConditionID"] for row in selected):
            raise ValueError(f"Map {entry['id']}: conditional overlay requires separate review")
        groups = [(entry["w"], entry["h"], base_tiles[art_id])]
        groups.extend((row["TextureWidth"], row["TextureHeight"], overlay_tiles[row["ID"]]) for row in selected)
        for width, height, tiles in groups:
            expected = {(r, c) for r in range(math.ceil(height / style["TileHeight"]))
                        for c in range(math.ceil(width / style["TileWidth"]))}
            actual = {(row["RowIndex"], row["ColIndex"]) for row in tiles}
            if actual != expected or len(tiles) != len(expected):
                raise ValueError(f"Map {entry['id']}: missing or duplicate native tiles")
            files.update(row["FileDataID"] for row in tiles)
        plans.append((entry, art_id, style, selected, tileless))

    tile_dir = CACHE / build
    tile_dir.mkdir(parents=True, exist_ok=True)

    def download(file_id):
        path = tile_dir / f"{file_id}.blp"
        if not path.exists():
            data = fetch(f"{HOST}/api/casc/{file_id}?version={build}", f"{HOST}/files")
            image = Image.open(io.BytesIO(data))
            image.load()  # Reject error documents or corrupt textures before caching.
            path.write_bytes(data)
        return file_id, hashlib.sha256(path.read_bytes()).hexdigest()

    print(f"Fetching {len(files)} versioned native textures for {len(plans)} maps...", flush=True)
    with ThreadPoolExecutor(max_workers=6) as pool:
        hashes = dict(pool.map(download, sorted(files)))

    def canvas(width, height, tiles, style):
        result = Image.new("RGBA", (math.ceil(width / style["TileWidth"]) * style["TileWidth"],
                                    math.ceil(height / style["TileHeight"]) * style["TileHeight"]))
        for row in tiles:
            with Image.open(tile_dir / f"{row['FileDataID']}.blp") as image:
                if image.width > style["TileWidth"] or image.height > style["TileHeight"]:
                    raise ValueError("Unexpected texture dimensions")
                result.alpha_composite(image.convert("RGBA"),
                                       (row["ColIndex"] * style["TileWidth"], row["RowIndex"] * style["TileHeight"]))
        return result.crop((0, 0, width, height))

    staging = ASSETS / ".explored-build"
    staging.mkdir(exist_ok=True)
    records = []
    for entry, art_id, style, selected, tileless in plans:
        image = canvas(entry["w"], entry["h"], base_tiles[art_id], style)
        for overlay in sorted(selected, key=lambda row: row["ID"]):
            patch = canvas(overlay["TextureWidth"], overlay["TextureHeight"], overlay_tiles[overlay["ID"]], style)
            image.alpha_composite(patch, (overlay["OffsetX"], overlay["OffsetY"]))
        image = image.crop(entry["crop"]).convert("RGB")
        path = staging / f"{entry['id']}.jpg"
        image.save(path, quality=94, optimize=True)
        tile_ids = sorted({row["FileDataID"] for row in base_tiles[art_id]} |
                          {row["FileDataID"] for overlay in selected for row in overlay_tiles[overlay["ID"]]})
        records.append({**entry, "artworkState": "fully-explored", "uiMapArtId": art_id,
                        "overlayCount": len(selected), "overlayIds": [row["ID"] for row in selected],
                        "texturelessDiscoveryIds": tileless,
                        "textureIds": tile_ids, "composedSha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    # Do not replace usable maps until every native map and overlay has been validated.
    for entry in records:
        (staging / f"{entry['id']}.jpg").replace(ROOT / entry["image"])
    staging.rmdir()
    manifest.update(maps=records, artworkState="fully-explored", overlaySource=sources,
                    textureHashes={str(key): value for key, value in hashes.items()})
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8", newline="\n")
    print(f"Composed {len(records)} fully explored maps with {sum(row['overlayCount'] for row in records)} native overlays")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", required=True)
    build(parser.parse_args().build)
