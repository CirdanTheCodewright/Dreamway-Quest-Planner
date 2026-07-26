local ADDON_NAME = ...

local CONTINENTS = {
    { mapID = 1414, name = "Kalimdor" },
    { mapID = 1415, name = "Eastern Kingdoms" },
}

local DEFAULT_WIDTH = 1002
local DEFAULT_HEIGHT = 668
local CELLS_PER_FRAME = 1200
local ZONE_MAP_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3

local exporter = CreateFrame("Frame")
local scan

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Dreamway Map Export:|r " .. tostring(message))
end

local function IsCityMap(mapID)
    if not C_Map.IsCityMap then
        return false
    end
    local ok, result = pcall(C_Map.IsCityMap, mapID)
    return ok and result or false
end

local function IsExportableMap(info, continentMapID)
    if not info or not info.mapID or info.mapID == continentMapID then
        return false
    end
    return info.mapType == ZONE_MAP_TYPE or IsCityMap(info.mapID)
end

local function GetArtDimensions(mapID)
    if C_Map.GetMapArtLayers then
        local layers = C_Map.GetMapArtLayers(mapID)
        if layers then
            for _, layer in ipairs(layers) do
                local width = tonumber(layer.layerWidth)
                local height = tonumber(layer.layerHeight)
                if width and height and width > 0 and height > 0 and width <= 2048 and height <= 2048 then
                    return math.floor(width + 0.5), math.floor(height + 0.5)
                end
            end
        end
    end
    return DEFAULT_WIDTH, DEFAULT_HEIGHT
end

local function AddMapRecord(result, mapID, suppliedInfo)
    if result.maps[mapID] then
        return result.maps[mapID]
    end

    local info = suppliedInfo or C_Map.GetMapInfo(mapID)
    if not info then
        return nil
    end

    local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(mapID, result.mapID)
    local record = {
        mapID = mapID,
        name = info.name,
        mapType = info.mapType,
        parentMapID = info.parentMapID,
        flags = info.flags,
        isCity = IsCityMap(mapID),
    }
    if minX then
        record.rect = { minX, maxX, minY, maxY }
    end
    result.maps[mapID] = record
    return record
end

local function CollectDescendants(result)
    local children = C_Map.GetMapChildrenInfo(result.mapID, nil, true) or {}
    for _, info in ipairs(children) do
        if IsExportableMap(info, result.mapID) then
            AddMapRecord(result, info.mapID, info)
            result.allowedMapIDs[info.mapID] = true
        end
    end
end

local function RecordHighlight(result, mapID, x, y)
    if result.highlights[mapID] or result.highlightAttempts[mapID] == false then
        return
    end

    local attempts = (result.highlightAttempts[mapID] or 0) + 1
    result.highlightAttempts[mapID] = attempts
    local fileDataID, atlasID, percentageX, percentageY, textureX, textureY, scrollX, scrollY =
        C_Map.GetMapHighlightInfoAtPosition(result.mapID, x, y)

    if fileDataID or atlasID then
        result.highlights[mapID] = {
            fileDataID = fileDataID,
            atlasID = atlasID,
            texturePercentageX = percentageX,
            texturePercentageY = percentageY,
            textureX = textureX,
            textureY = textureY,
            scrollChildX = scrollX,
            scrollChildY = scrollY,
            sampleX = x,
            sampleY = y,
        }
    elseif attempts >= 32 then
        result.highlightAttempts[mapID] = false
    end
end

local function AppendRun(state, mapID)
    if state.runMapID == mapID then
        state.runLength = state.runLength + 1
        return
    end
    if state.runLength > 0 then
        state.rowParts[#state.rowParts + 1] = state.runMapID .. ":" .. state.runLength
    end
    state.runMapID = mapID
    state.runLength = 1
end

local function FinishRow(state)
    if state.runLength > 0 then
        state.rowParts[#state.rowParts + 1] = state.runMapID .. ":" .. state.runLength
    end
    state.result.rows[state.y] = table.concat(state.rowParts, ",")
    state.x = 1
    state.y = state.y + 1
    state.rowParts = {}
    state.runMapID = 0
    state.runLength = 0
end

local function PrepareContinent(continent)
    local width, height = GetArtDimensions(continent.mapID)
    local result = {
        mapID = continent.mapID,
        name = continent.name,
        width = width,
        height = height,
        rows = {},
        maps = {},
        highlights = {},
        allowedMapIDs = {},
        highlightAttempts = {},
    }
    CollectDescendants(result)
    return {
        result = result,
        x = 1,
        y = 1,
        rowParts = {},
        runMapID = 0,
        runLength = 0,
        nextProgress = 10,
    }
end

local function CleanResult(result)
    result.allowedMapIDs = nil
    result.highlightAttempts = nil
end

local function CompleteScan()
    DreamwayMapExportDB.completed = true
    DreamwayMapExportDB.completedAt = date("!%Y-%m-%dT%H:%M:%SZ")
    scan = nil
    exporter:SetScript("OnUpdate", nil)
    Print("Export complete. Run |cffffffff/reload|r or log out to write the SavedVariables file to disk.")
end

local function AdvanceContinent()
    CleanResult(scan.current.result)
    DreamwayMapExportDB.continents[scan.current.result.mapID] = scan.current.result
    Print(scan.current.result.name .. " complete.")

    scan.continentIndex = scan.continentIndex + 1
    local continent = CONTINENTS[scan.continentIndex]
    if not continent then
        CompleteScan()
        return
    end
    scan.current = PrepareContinent(continent)
    Print("Scanning " .. continent.name .. " at " .. scan.current.result.width .. "x" .. scan.current.result.height .. ".")
end

local function ProcessCell(state)
    local result = state.result
    local normalizedX = (state.x - 0.5) / result.width
    local normalizedY = (state.y - 0.5) / result.height
    local info = C_Map.GetMapInfoAtPosition(result.mapID, normalizedX, normalizedY)
    local mapID = 0

    if IsExportableMap(info, result.mapID) then
        mapID = info.mapID
        if not result.allowedMapIDs[mapID] then
            result.allowedMapIDs[mapID] = true
            AddMapRecord(result, mapID, info)
        end
        RecordHighlight(result, mapID, normalizedX, normalizedY)
    end

    AppendRun(state, mapID)
    state.x = state.x + 1
    if state.x > result.width then
        FinishRow(state)
    end
end

local function OnUpdate()
    if not scan or not scan.current then
        return
    end

    local state = scan.current
    for _ = 1, CELLS_PER_FRAME do
        if state.y > state.result.height then
            AdvanceContinent()
            return
        end
        ProcessCell(state)
    end

    local completed = ((state.y - 1) * state.result.width + state.x - 1)
    local total = state.result.width * state.result.height
    local percent = math.floor(completed / total * 100)
    if percent >= state.nextProgress then
        Print(state.result.name .. ": " .. percent .. "%")
        state.nextProgress = state.nextProgress + 10
    end
end

local function StartScan()
    if scan then
        Print("A scan is already in progress.")
        return
    end
    if not C_Map.GetMapInfoAtPosition or not C_Map.GetMapHighlightInfoAtPosition or not C_Map.GetMapRectOnMap then
        Print("This client does not expose all required map APIs.")
        return
    end

    local _, build, _, interfaceVersion = GetBuildInfo()
    DreamwayMapExportDB = {
        schema = "QPHIT1",
        generatedBy = ADDON_NAME,
        clientBuild = build,
        interfaceVersion = interfaceVersion,
        startedAt = date("!%Y-%m-%dT%H:%M:%SZ"),
        completed = false,
        continentOrder = { 1414, 1415 },
        continents = {},
    }

    for _, continent in ipairs(CONTINENTS) do
        if C_Map.RequestPreloadMap then
            C_Map.RequestPreloadMap(continent.mapID)
        end
    end

    scan = {
        continentIndex = 1,
        current = PrepareContinent(CONTINENTS[1]),
    }
    Print("Scanning Kalimdor at " .. scan.current.result.width .. "x" .. scan.current.result.height .. ".")
    exporter:SetScript("OnUpdate", OnUpdate)
end

local function ShowStatus()
    if scan then
        local state = scan.current
        local completed = ((state.y - 1) * state.result.width + state.x - 1)
        local total = state.result.width * state.result.height
        Print(string.format("Scanning %s: %.1f%%", state.result.name, completed / total * 100))
    elseif DreamwayMapExportDB and DreamwayMapExportDB.completed then
        Print("The export completed at " .. tostring(DreamwayMapExportDB.completedAt) .. ". Run /reload if it has not yet been written to disk.")
    else
        Print("No scan is running. Use |cffffffff/qphit scan|r to begin.")
    end
end

local function HandleSlashCommand(message)
    local command = strtrim(message or ""):lower()
    if command == "scan" or command == "export" then
        StartScan()
    elseif command == "status" then
        ShowStatus()
    elseif command == "clear" then
        if scan then
            scan = nil
            exporter:SetScript("OnUpdate", nil)
        end
        DreamwayMapExportDB = nil
        Print("Saved export cleared.")
    else
        Print("Commands: |cffffffff/qphit scan|r, |cffffffff/qphit status|r, |cffffffff/qphit clear|r")
    end
end

exporter:RegisterEvent("ADDON_LOADED")
exporter:SetScript("OnEvent", function(_, _, loadedAddon)
    if loadedAddon ~= ADDON_NAME then
        return
    end
    DreamwayMapExportDB = DreamwayMapExportDB or {}
    SLASH_DREAMWAYMAPEXPORT1 = "/qphit"
    SlashCmdList.DREAMWAYMAPEXPORT = HandleSlashCommand
    Print("Ready. Use |cffffffff/qphit scan|r to export Kalimdor and Eastern Kingdoms zone/city hitboxes.")
end)
