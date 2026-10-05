"""Offline regression checks; run after building the web app. Requires lupa."""
import base64
import gzip
import hashlib
import json
import re
import time
from pathlib import Path
from questiedb_source import LuaRuntime, load_flavor, load_questie_categories

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "DreamwayQuestPlanner/Dreamway.lua").read_text(encoding="utf-8")
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("function(s) local f,e=loadstring(s); assert(f,e); return true end")
for file in (ROOT / "DreamwayQuestPlanner").glob("*.lua"):
    compile_lua(file.read_text(encoding="utf-8"))
print("Lua 5.1: all addon files compile (including the 200-local limit)")

prefix = source[:source.index("local SECTION_ORDER")]
# Trailing client build metadata must not become tonumber's optional base argument.
lua.execute("GetBuildInfo=function() return '1.60.1','69913','',16001,'Forever' end")
lua.execute(prefix + "\nTestBand=DreamwayBitBand; TestVersion=CurrentDreamwayGameVersion; TestNormalize=NormalizeDreamwayGameVersion; _G.ProfileRecorder=ProfileRecorder")
assert lua.globals().TestVersion() == "forever"
assert lua.globals().TestNormalize("Camelot") == "forever"
# Force a truncating 32-bit library to ensure high masks bypass it.
lua.execute("bit={band=function(a,b) return 0 end}")
for a, b in ((4294967373, 4294967296), (8589934770, 8589934592),
             (12884902143, 4294967296), (4294967373, 8589934592)):
    assert lua.globals().TestBand(a, b) == a & b
print("Forever detection and 64-bit-safe race-mask intersections: pass")

start = source.index("function ProfileRecorder.AcceptedQuestId(")
end = source.index("function ProfileRecorder.NpcIdFromGuid(", start)
lua.execute(source[start:end])
assert lua.globals().ProfileRecorder.AcceptedQuestId(7, None) == 7
lua.execute("ProfileRecorder.isForeverClient=false")
assert lua.globals().ProfileRecorder.AcceptedQuestId(2, 7) == 7
lua.execute("ProfileRecorder.client={GetQuestLogTitle=function() return 'Quest',1,nil,false,false,nil,nil,42 end}")
assert lua.globals().ProfileRecorder.AcceptedQuestId(2, None) == 42
start = source.index("function DreamwayRefreshTrackerItemButtonState(")
end = source.index("function DreamwayRefreshVisibleTrackerItemButtonStates(", start)
lua.execute(source[start:end])
lua.execute('''
    C_Item={GetItemCount=function() return 2 end}
    ProfileRecorder.compat={GetItemCooldown=function() return 10,20,true end}
    button={itemId=6948, cooldown={
        SetCooldown=function(_,start,duration) assert(start==10 and duration==20) end,
        Show=function(self) self.shown=true end,
        Hide=function(self) self.shown=false end}}
    DreamwayRefreshTrackerItemButtonState(button)
    assert(button.cooldown.shown)
    ProfileRecorder.compat.GetItemCooldown=function() return 10,20,1 end
    DreamwayRefreshTrackerItemButtonState(button)
    assert(button.cooldown.shown)
    ProfileRecorder.compat.GetItemCooldown=function() return 10,20,false end
    DreamwayRefreshTrackerItemButtonState(button)
    assert(not button.cooldown.shown)
''')
print("Modern/legacy quest acceptance and boolean/numeric item cooldowns: pass")

packs = {}
for name in ("classic", "sod", "forever", "tbc", "wotlk"):
    text = (ROOT / f"data/dreamway-{name}.data.js").read_text()
    encoded = re.search(r'\]="([^"]+)"', text).group(1)
    packs[name] = json.loads(gzip.decompress(base64.b64decode(encoded)))
    quests = packs[name]["quests"]
    assert quests and len({q["id"] for q in quests}) == len(quests)
    assert all(all(v in ("era", "sod", "forever", "tbc", "wotlk") for v in q["gameVersions"]) for q in quests)
    assert all(q["name"] for q in quests)
    print(f"{name}: {len(quests)} unique quest records; valid version membership")
forever = load_flavor("Forever")
era = load_flavor("Vanilla")
assert 4294967296 & forever["Quest"][7][5]
assert era["Quest"][7][5] < 4294967296
assert all(isinstance(row[6], dict) for row in forever["Npc"].values() if row[6])
assert all(isinstance(row[3], dict) for row in forever["Object"].values() if row[3])
assert 76156 not in {q["id"] for q in packs["classic"]["quests"]}
assert 76156 in {q["id"] for q in packs["sod"]["quests"]}
print("Owned corrected data: high race bits, keyed spawn maps, SoD isolation: pass")

# Category membership is owned by Questie's Journey, not inferred from quest titles.
for name, corrected in (("classic", era), ("forever", forever)):
    _, groups = load_questie_categories(name)
    for quest in packs[name]["quests"]:
        sort = corrected["Quest"][quest["id"]][16]
        assert ("profession" in quest["typeIds"]) == (sort in groups[12]), quest["id"]
    writs = [quest for quest in packs[name]["quests"] if quest["name"].startswith("Craftsman's Writ")]
    assert writs and all("profession" not in quest["typeIds"] for quest in writs)
print("Profession categories and Craftsman's Writs match Questie's Journey: pass")

native = packs["forever"]
assert native["mapCoordinateFrame"] == "native" and "mapCoordinateTransforms" not in native
manifest = json.loads((ROOT / "assets/forever-maps/manifest.json").read_text())
assert native["mapBuild"] == manifest["build"]
assert len(manifest["maps"]) == 57
assert manifest["artworkState"] == "fully-explored"
for map_source in manifest["overlaySource"].values():
    assert hashlib.sha256((ROOT / map_source["path"]).read_bytes()).hexdigest() == map_source["sha256"]
for entry in manifest["maps"]:
    raw = (ROOT / f"assets/forever-maps/source/{entry['id']}.webp").read_bytes()
    assert hashlib.sha256(raw).hexdigest() == entry["sha256"]
    assert entry["artworkState"] == "fully-explored"
    assert hashlib.sha256((ROOT / entry["image"]).read_bytes()).hexdigest() == entry["composedSha256"]
    assert entry["overlayCount"] == len(entry["overlayIds"])
    assert all(str(file_id) in manifest["textureHashes"] for file_id in entry["textureIds"])
    if entry["id"] in (1412, 1433, 1434, 2521):
        assert entry["overlayCount"] > 0
native_zones = {zone["id"]: zone for zone in native["zones"]}
for zone_id in (215, 139, 44, 1519, 616, 16593, 16591, 16651):
    assert native_zones[zone_id]["image"] and native_zones[zone_id]["worldRect"]
    assert (ROOT / native_zones[zone_id]["image"]).exists()
assert any(group["continentIds"] == [2521] for group in native["worldGroups"])
# A known pickup in a changed map must keep the upstream native coordinates.
writ = next(quest for quest in native["quests"] if quest["id"] == 9178)
spawn = forever["Npc"][16283][6][139][0]
assert any(point["zoneId"] == 139 and abs(point["x"] - spawn[0]) < .002 and abs(point["y"] - spawn[1]) < .002
           for point in writ["endPoints"])
for quest in native["quests"]:
    for point in quest["startPoints"] + quest["endPoints"]:
        zone = native_zones.get(point["zoneId"])
        if zone and not zone["isInstance"] and zone.get("worldRect"):
            assert "worldX" in point and "worldY" in point
print("57 versioned map assets, new zones and unchanged native pickup coordinates: pass")

# Exercise the real catalogue builder and scrolling renderer with the largest shipped
# dataset. Frame mocks implement layout only; forbidden DB/state calls fail immediately.
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute((ROOT / "DreamwayQuestPlanner/DreamwayQuestZones-WOTLKC.lua").read_text())
lua.execute('''
    ProfileRecorder={}
    ImportQuestieModule=function() error("unexpected database hydration") end
    QuestChainName=function(id) return "Chain " .. tostring(id) end
''')
start = source.index("local function BuildAllQuestSearchCache()")
end = source.index("\nlocal function ", start + 10)
builder = source[start:end].replace('local QuestieDB = ImportQuestieModule("QuestieDB")', 'local QuestieDB = {}')
lua.execute(builder + "\nSearchCache=BuildAllQuestSearchCache()")
lua.execute('''
    assert(#SearchCache > 9000)
    panelSearchResultRows={}
    for _,quest in ipairs(SearchCache) do
        local record=DreamwayQuestZones.quests[quest.id]
        assert(quest._dreamwayCanonical and quest.zoneIds == record.a)
        assert(quest.preQuestGroup == (record.pg or ProfileRecorder.emptyQuestMetadataArray))
        panelSearchResultRows[#panelSearchResultRows+1]={kind="quest", quest=quest,
            renderText=quest.name, isComplete=false, location=""}
    end
    local function forbidden() error("scroll performed model/database work") end
    RefreshPanelSearchResults=forbidden
    ColoredQuestSearchDisplayName=forbidden
    IsJourneyComplete=forbidden
    DreamwayPanelQuestIsSelected=function() return false end
    DreamwayPanelAllQuestIdsSelected=function() return false end
    PANEL_SEARCH_ROW_HEIGHT=22
    PANEL_SEARCH_ROW_TOP_PAD=6
    PANEL_SEARCH_ROW_POOL_EXTRA=3
    panelSearchResultsContent={}
    scrollOffset=0
    panelSearchResultsScroll={GetVerticalScroll=function() return scrollOffset end,
        GetHeight=function() return 390 end}
    panelSearchResultButtons={}
    local function widget()
        return setmetatable({}, {__index=function(_,name)
            return function() end
        end})
    end
    EnsurePanelSearchButton=function(index)
        if not panelSearchResultButtons[index] then
            local button=widget()
            for _,key in ipairs({"label","location","completeMark","requirementHighlight",
                                  "selectionHighlight","disclosure"}) do button[key]=widget() end
            panelSearchResultButtons[index]=button
        end
        return panelSearchResultButtons[index]
    end
    callbacks={}
    C_Timer={After=function(_,fn) callbacks[#callbacks+1]=fn end}
''')
start = source.index("UpdatePanelSearchVisibleRows = function(force)")
end = source.index("RefreshPanelSearchResults = function", start)
lua.execute(source[start:end])
t0 = time.perf_counter()
lua.execute('''
    UpdatePanelSearchVisibleRows(true)
    for index=1,#panelSearchResultRows-18 do
        scrollOffset=(index-1)*22
        UpdatePanelSearchVisibleRows()
        assert(#panelSearchResultButtons==21)
    end
    for index=1000,1,-1 do
        scrollOffset=(index-1)*22
        UpdatePanelSearchVisibleRows()
    end
    for index=1,100 do SchedulePanelSearchVisibleRowsUpdate() end
    assert(#callbacks==1)
    callbacks[1]()
    assert(not ProfileRecorder.searchScrollRefreshPending)
''')
print(f"Empty-search model: {len(lua.globals().SearchCache)} quests; 21 recycled frames; "
      f"forward/back scrolling and 100-event coalescing passed in {time.perf_counter()-t0:.3f}s")
print("Offline checks passed. Live client/combat/persistence testing remains separate.")
