import argparse
import csv
import html
import io
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "Questie" / "ExternalScripts(DONOTINCLUDEINRELEASE)" / "DBC - WoW.tools" / "worldmaparea_classic.csv"
ASSET_ROOT = ROOT / "assets" / "classic-maps"
ZONE_ASSET_DIR = ASSET_ROOT / "zones"
CONTINENT_ASSET_DIR = ASSET_ROOT / "continents"
METADATA_PATH = ASSET_ROOT / "manifest.json"

WAGO_PRODUCT = "wow_classic_era"
WAGO_VERSION = "1.13.0.28211"
USER_AGENT = "Mozilla/5.0 WoW Quest Mapping Prototype"
TILE_SIZE = 256
TILE_COLUMNS = 4
TILE_ROWS = 3
VISIBLE_MAP_WIDTH = 1002
VISIBLE_MAP_HEIGHT = 668
CONTINENT_CROPS = {
    0: (280, 0, 690, 668),
    1: (290, 0, 700, 668),
}
DB2_BASE_URL = "https://wago.tools/db2"

FILE_RE = re.compile(
    r'"fdid":(\d+),"filename":"(interface\\/worldmap\\/([^\\/"]+)\\/([^\\/"]+?)(\d+)\.blp)"',
    re.IGNORECASE,
)

CONTINENT_TEXTURES = {
    0: ("Azeroth", "azeroth"),
    1: ("Kalimdor", "kalimdor"),
}

_DB2_CACHE = {}
_UI_MAP_ART_BY_FILE_DATA_ID = None
_OVERLAYS_BY_UI_MAP_ART_ID = None
_OVERLAY_TILES_BY_OVERLAY_ID = None


def request_bytes(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=45) as response:
        return response.read()


def load_db2_csv(table_name):
    if table_name not in _DB2_CACHE:
        query = urllib.parse.urlencode({"product": WAGO_PRODUCT})
        data = request_bytes(f"{DB2_BASE_URL}/{table_name}/csv?{query}").decode("utf-8-sig")
        _DB2_CACHE[table_name] = list(csv.DictReader(io.StringIO(data)))
    return _DB2_CACHE[table_name]


def int_field(row, name, default=0):
    value = row.get(name)
    return int(value) if value not in (None, "") else default


def ui_map_art_by_file_data_id():
    global _UI_MAP_ART_BY_FILE_DATA_ID
    if _UI_MAP_ART_BY_FILE_DATA_ID is None:
        _UI_MAP_ART_BY_FILE_DATA_ID = {
            int_field(row, "FileDataID"): int_field(row, "UiMapArtID")
            for row in load_db2_csv("UiMapArtTile")
            if int_field(row, "FileDataID")
        }
    return _UI_MAP_ART_BY_FILE_DATA_ID


def overlays_by_ui_map_art_id():
    global _OVERLAYS_BY_UI_MAP_ART_ID
    if _OVERLAYS_BY_UI_MAP_ART_ID is None:
        overlays = {}
        for row in load_db2_csv("WorldMapOverlay"):
            overlays.setdefault(int_field(row, "UiMapArtID"), []).append(row)
        _OVERLAYS_BY_UI_MAP_ART_ID = overlays
    return _OVERLAYS_BY_UI_MAP_ART_ID


def overlay_tiles_by_overlay_id():
    global _OVERLAY_TILES_BY_OVERLAY_ID
    if _OVERLAY_TILES_BY_OVERLAY_ID is None:
        tiles = {}
        for row in load_db2_csv("WorldMapOverlayTile"):
            tiles.setdefault(int_field(row, "WorldMapOverlayID"), []).append(row)
        _OVERLAY_TILES_BY_OVERLAY_ID = tiles
    return _OVERLAY_TILES_BY_OVERLAY_ID


def wago_file_search(search):
    query = urllib.parse.urlencode({"product": WAGO_PRODUCT, "search": search})
    page = request_bytes(f"https://wago.tools/files?{query}").decode("utf-8")
    decoded = html.unescape(page)
    files = []
    for match in FILE_RE.finditer(decoded):
        path = match.group(2).replace("\\/", "/").lower()
        files.append(
            {
                "fdid": int(match.group(1)),
                "path": path,
                "folder": match.group(3).lower(),
                "basename": match.group(4).lower(),
                "tile": int(match.group(5)),
            }
        )
    return files


def load_zone_texture_names():
    zones = []
    with CSV_PATH.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            area_id = int(row["AreaID"])
            map_id = int(row["MapID"])
            if area_id > 0 and map_id in (0, 1):
                texture = row["AreaName"].lower()
                zones.append(
                    {
                        "areaId": area_id,
                        "mapId": map_id,
                        "areaName": row["AreaName"],
                        "texture": texture,
                    }
                )
    return zones


def find_tile_set(texture_name):
    search = f"interface/worldmap/{texture_name}/{texture_name}"
    tile_files = {}
    for file in wago_file_search(search):
        if file["folder"] != texture_name:
            continue
        if file["basename"] != texture_name:
            continue
        if 1 <= file["tile"] <= TILE_COLUMNS * TILE_ROWS:
            tile_files[file["tile"]] = file

    missing = sorted(set(range(1, TILE_COLUMNS * TILE_ROWS + 1)) - set(tile_files))
    if missing:
        raise RuntimeError(f"{texture_name}: missing map tiles {missing}")
    return tile_files


def download_blp(fdid):
    url = f"https://wago.tools/api/casc/{fdid}?version={urllib.parse.quote(WAGO_VERSION)}"
    return request_bytes(url)


def compose_tile_set(tile_files):
    canvas = Image.new("RGB", (TILE_COLUMNS * TILE_SIZE, TILE_ROWS * TILE_SIZE))
    for tile_number in range(1, TILE_COLUMNS * TILE_ROWS + 1):
        image = Image.open(io.BytesIO(download_blp(tile_files[tile_number]["fdid"]))).convert("RGB")
        x = ((tile_number - 1) % TILE_COLUMNS) * TILE_SIZE
        y = ((tile_number - 1) // TILE_COLUMNS) * TILE_SIZE
        canvas.paste(image, (x, y))
        time.sleep(0.03)
    return crop_visible_map(canvas)


def ui_map_art_id_for_tile_set(tile_files):
    art_by_fdid = ui_map_art_by_file_data_id()
    for tile_number in range(1, TILE_COLUMNS * TILE_ROWS + 1):
        art_id = art_by_fdid.get(tile_files[tile_number]["fdid"])
        if art_id:
            return art_id
    return None


def compose_overlay(overlay, tile_rows):
    width = int_field(overlay, "TextureWidth")
    height = int_field(overlay, "TextureHeight")
    if width <= 0 or height <= 0 or not tile_rows:
        return None

    grid_columns = max(int_field(row, "ColIndex") for row in tile_rows) + 1
    grid_rows = max(int_field(row, "RowIndex") for row in tile_rows) + 1
    canvas = Image.new("RGBA", (grid_columns * TILE_SIZE, grid_rows * TILE_SIZE), (0, 0, 0, 0))

    for row in sorted(tile_rows, key=lambda item: (int_field(item, "LayerIndex"), int_field(item, "RowIndex"), int_field(item, "ColIndex"))):
        image = Image.open(io.BytesIO(download_blp(int_field(row, "FileDataID")))).convert("RGBA")
        x = int_field(row, "ColIndex") * TILE_SIZE
        y = int_field(row, "RowIndex") * TILE_SIZE
        canvas.alpha_composite(image, (x, y))
        time.sleep(0.03)

    return canvas.crop((0, 0, width, height))


def alpha_composite_clipped(base, overlay, x, y):
    left = max(0, x)
    top = max(0, y)
    right = min(base.width, x + overlay.width)
    bottom = min(base.height, y + overlay.height)
    if right <= left or bottom <= top:
        return

    source = overlay.crop((left - x, top - y, right - x, bottom - y))
    base.alpha_composite(source, (left, top))


def crop_visible_map(image):
    if image.width >= VISIBLE_MAP_WIDTH and image.height >= VISIBLE_MAP_HEIGHT:
        return image.crop((0, 0, VISIBLE_MAP_WIDTH, VISIBLE_MAP_HEIGHT))
    mask = image.convert("L").point(lambda value: 255 if value > 8 else 0)
    box = mask.getbbox()
    if not box:
        return image
    return image.crop(box)


def save_map(texture_name, target, force=False):
    if target.exists() and not force:
        return {"texture": texture_name, "target": target.as_posix(), "status": "skipped"}

    tile_files = find_tile_set(texture_name)
    image = compose_tile_set(tile_files)
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, quality=94, optimize=True)
    return {
        "texture": texture_name,
        "target": target.as_posix(),
        "status": "written",
        "tiles": {str(tile): tile_files[tile]["fdid"] for tile in sorted(tile_files)},
    }


def save_classic_zone_map(zone, force=False):
    target = ZONE_ASSET_DIR / f"{zone['areaId']}.jpg"
    if target.exists() and not force:
        return {"target": target.as_posix(), "status": "skipped", "sourceKind": "classic-casc-overlays"}

    tile_files = find_tile_set(zone["texture"])
    art_id = ui_map_art_id_for_tile_set(tile_files)
    if not art_id:
        raise RuntimeError(f"{zone['texture']}: could not find UiMapArtID for base tiles")

    image = compose_tile_set(tile_files).convert("RGBA")
    overlay_rows = overlays_by_ui_map_art_id().get(art_id, [])
    tile_rows_by_overlay = overlay_tiles_by_overlay_id()
    overlay_count = 0
    overlay_tile_count = 0

    for overlay in overlay_rows:
        overlay_id = int_field(overlay, "ID")
        tile_rows = tile_rows_by_overlay.get(overlay_id, [])
        overlay_image = compose_overlay(overlay, tile_rows)
        if overlay_image is None:
            continue
        alpha_composite_clipped(image, overlay_image, int_field(overlay, "OffsetX"), int_field(overlay, "OffsetY"))
        overlay_count += 1
        overlay_tile_count += len(tile_rows)

    target.parent.mkdir(parents=True, exist_ok=True)
    image = image.convert("RGB")
    image.save(target, quality=94, optimize=True)
    return {
        "target": target.as_posix(),
        "status": "written",
        "sourceKind": "classic-casc-overlays",
        "uiMapArtID": art_id,
        "overlayCount": overlay_count,
        "overlayTileCount": overlay_tile_count,
        "width": image.width,
        "height": image.height,
        "tiles": {str(tile): tile_files[tile]["fdid"] for tile in sorted(tile_files)},
    }


def save_continent_map(continent_id, display_name, texture, force=False):
    target = CONTINENT_ASSET_DIR / f"{continent_id}.jpg"
    if target.exists() and not force:
        return {
            "texture": texture,
            "target": target.as_posix(),
            "status": "skipped",
            "crop": list(CONTINENT_CROPS[continent_id]),
        }

    tile_files = find_tile_set(texture)
    image = compose_tile_set(tile_files)
    crop = CONTINENT_CROPS[continent_id]
    image = image.crop(crop)
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, quality=94, optimize=True)
    return {
        "texture": texture,
        "target": target.as_posix(),
        "status": "written",
        "crop": list(crop),
        "width": image.width,
        "height": image.height,
        "tiles": {str(tile): tile_files[tile]["fdid"] for tile in sorted(tile_files)},
    }


def main():
    parser = argparse.ArgumentParser(description="Download and compose Classic Era WoW world map tiles.")
    parser.add_argument("--force", action="store_true", help="Regenerate images that already exist.")
    parser.add_argument("--zones-only", action="store_true", help="Only compose individual zone maps.")
    parser.add_argument("--continents-only", action="store_true", help="Only compose continent maps.")
    args = parser.parse_args()

    if args.zones_only and args.continents_only:
        raise SystemExit("--zones-only and --continents-only cannot be combined")

    manifest = {
        "source": "Wago.Tools Classic Era CASC files with UiMapArtTile, WorldMapOverlay, and WorldMapOverlayTile DB2 data",
        "product": WAGO_PRODUCT,
        "version": WAGO_VERSION,
        "tileSize": TILE_SIZE,
        "tileColumns": TILE_COLUMNS,
        "tileRows": TILE_ROWS,
        "visibleMapWidth": VISIBLE_MAP_WIDTH,
        "visibleMapHeight": VISIBLE_MAP_HEIGHT,
        "continentCrops": {str(key): list(value) for key, value in CONTINENT_CROPS.items()},
        "zones": [],
        "continents": [],
    }

    if not args.continents_only:
        for zone in load_zone_texture_names():
            result = save_classic_zone_map(zone, args.force)
            result.update(zone)
            manifest["zones"].append(result)
            print(f"{zone['areaId']:>4} {zone['areaName']:<24} {result['status']} {result.get('sourceKind', '')}")

    if not args.zones_only:
        for continent_id, (display_name, texture) in CONTINENT_TEXTURES.items():
            result = save_continent_map(continent_id, display_name, texture, args.force)
            result.update({"continentId": continent_id, "name": display_name})
            manifest["continents"].append(result)
            print(f"{continent_id:>4} {display_name:<24} {result['status']}")

    ASSET_ROOT.mkdir(parents=True, exist_ok=True)
    METADATA_PATH.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Wrote {METADATA_PATH}")


if __name__ == "__main__":
    main()
