local ADDON_NAME = ...

local MODE_QUESTIE = "Questie"
local MODE_DREAMWAY = "Dreamway"
local COMPLETE_TEXTURE = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local WARNING_INLINE_TEXTURE = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14:14:0:0|t"
local ProfileRecorder = {
    EVENT_QUEST_PICKUP = 1,
    EVENT_QUEST_TURNIN = 2,
    EVENT_KILL = 3,
    EVENT_DEATH = 4,
    EVENT_OBJECTIVE = 5,
    EVENT_QUEST_COMPLETE = 6,
    EVENT_LEVEL = 7,
    EVENT_LOGIN = 8,
    EVENT_LOGOUT = 9,
    questObjectiveState = {},
    questCompleteState = {},
    lastObjectiveEvents = {},
    refreshPending = false,
    refreshShouldRecord = false,
    refreshGeneration = 0,
    completedQuestIds = nil,
    batchRenderedFirstIndex = nil,
    batchRenderedLastIndex = nil,
    searchRenderedFirstIndex = nil,
    searchRenderedRowCount = nil,
    searchScrollRefreshPending = false,
    searchDisplayTextByKey = {},
    dreamwayUiRefreshPending = false,
    dreamwayUiRefreshPanel = false,
    questieCallbackRegistered = false,
    questieAnnounceHooked = false,
    pendingUiObjectiveMessage = nil,
    damagedNpcGuids = {},
    recordedKillGuids = {},
    recentNpcDeaths = {},
    lastCombatPrune = 0,
}
local MAX_PANEL_SEARCH_RESULTS = 120
local PANEL_SEARCH_ROW_HEIGHT = 22
local PANEL_SEARCH_ROW_TOP_PAD = 6
local PANEL_SEARCH_ROW_POOL_EXTRA = 3
local PANEL_BATCH_COLUMNS_PER_ROW = 4
local PANEL_BATCH_COLUMN_WIDTH = 154
local PANEL_BATCH_COLUMN_HEIGHT = 360
local PANEL_BATCH_COLUMN_STEP_X = 174
local PANEL_BATCH_ROW_STEP_Y = 372
local PANEL_BATCH_VISIBLE_ROW_EXTRA = 1
local function NormalizeDreamwayGameVersion(value)
    value = string.lower(tostring(value or ""))
    if value == "wotlk" or value == "wrath" then
        return "wotlk"
    end
    if value == "tbc" then
        return "tbc"
    end
    if value == "sod" then
        return "sod"
    end
    return "era"
end

local function CurrentDreamwayGameVersion()
    if Questie and Questie.IsWotlk then
        return "wotlk"
    end
    if Questie and Questie.IsTBC then
        return "tbc"
    end
    return Questie and Questie.IsSoD and "sod" or "era"
end

function DreamwayCurrentMaxLevel()
    local databaseLevel = DreamwayQuestZones and tonumber(DreamwayQuestZones.maxLevel)
    if databaseLevel and databaseLevel > 0 then
        return databaseLevel
    end

    local version = CurrentDreamwayGameVersion()
    if version == "wotlk" then
        return 80
    end
    if version == "tbc" then
        return 70
    end
    return 60
end

function DreamwayBitBand(a, b)
    if bit and bit.band then
        return bit.band(a, b)
    end
    if bit32 and bit32.band then
        return bit32.band(a, b)
    end

    local result = 0
    local place = 1
    a = tonumber(a) or 0
    b = tonumber(b) or 0
    while a > 0 and b > 0 do
        local abit = a % 2
        local bbit = b % 2
        if abit == 1 and bbit == 1 then
            result = result + place
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        place = place * 2
    end
    return result
end

local SECTION_ORDER = {
    { key = "prereq", label = "Finish prerequisite" },
    { key = "pickup", label = "Pick up" },
    { key = "progress", label = "In Progress" },
    { key = "turnin", label = "Complete" },
}

local mode = MODE_QUESTIE
local initialized = false
local pendingApply = false
local batchIndex = 1
local suppressedUnusedQuestStates = {}
local SUPPRESSED_ABSENT = {}
local SUPPRESSED_SAVED_ABSENT = "__DreamwayAbsent"

local baseFrame
local headerFrame
local questFrame
local dreamwayFrame
local toggleFrame
local questieButton
local dreamwayButton
local BatchExpectedLevel
local panelFrame
local panelImportArea
local panelImportEditBox
local panelExportArea
local panelExportEditBox
local panelStatusText
local panelBatchScroll
local panelBatchContent
local panelBatchColumns = {}
local panelPrerequisiteWarnings = {}
local panelSearchBox
local panelSearchResults
local panelShowAssignedCheck
local panelShowAssignedQuests = false
local panelSearchResultsScroll
local panelSearchResultsContent
local panelSearchResultRows = {}
local panelSearchResultButtons = {}
local panelSearchEmptyLabel
local panelSearchFooterLabel
local panelSearchText = ""
panelSearchFilters = {
    mode = "search",
    unknownZoneId = 0,
    starts = true,
    objectives = true,
    ends = true,
    factions = {},
    raceMasks = {},
    classMasks = {},
    typeIds = {},
    zoneIds = {},
    initialized = false,
    scopeChecks = {},
    factionChecks = {},
    raceChecks = {},
    classChecks = {},
    typeChecks = {},
    characterLabels = {},
    typeLabels = {},
    zoneChecks = {},
    filterButtons = {},
}
panelJourneyManager = {
    rows = {},
    selectedJourneyId = nil,
}
local panelDropTargets = {}
local panelDragState
local panelDragGhost
local allQuestSearchCache
local chainSortCache = {}
local HydrateQuestMetadata
local RefreshJourneyDerivedData
local RefreshPanelSearchResults
local UpdatePanelSearchVisibleRows
local JourneyPrerequisiteWarnings

local fallbackJourney = {
    id = "dreamway-sample",
    name = "Sample Darkshore Journey",
    batches = {
        {
            name = "Darkshore: Auberdine North Loop",
            zones = { "Darkshore" },
            quests = {
                { name = "Buzzbox 827", category = "pickup" },
                { name = "Cave Mushrooms", category = "pickup" },
                { name = "Washed Ashore 0/1", category = "progress" },
                { name = "Buzzbox 827: Tide Crawlers 3/6", category = "progress" },
                { name = "The Red Crystal 0/1", category = "progress" },
                { name = "Bashal'Aran", category = "turnin" },
                { name = "The Absent Minded Prospector", category = "turnin" },
            },
        },
        {
            name = "Darkshore: Bashal'Aran Sweep",
            zones = { "Darkshore" },
            quests = {
                { name = "Tools of the Highborne", category = "pickup" },
                { name = "For Love Eternal", category = "pickup" },
                { name = "The Tower of Althalaxx 2/6", category = "progress" },
                { name = "Deep Ocean, Vast Sea 0/2", category = "progress" },
                { name = "Cave Mushrooms", category = "turnin" },
            },
        },
        {
            name = "Darkshore: South Beach Return",
            zones = { "Darkshore" },
            quests = {
                { name = "Fruit of the Sea", category = "pickup" },
                { name = "Beached Sea Creature 0/1", category = "progress" },
                { name = "The Family and the Fishing Pole 4/6", category = "progress" },
                { name = "Buzzbox 411", category = "turnin" },
                { name = "Washed Ashore", category = "turnin" },
                { name = "Fruit of the Sea", category = "turnin" },
            },
        },
    },
}

local function CreateBackdropFrame(name, parent)
    return CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate")
end

local function SetFrameBackdrop(frame, r, g, b, a, borderAlpha)
    if not frame or not frame.SetBackdrop then
        return
    end

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(r, g, b, a)
    frame:SetBackdropBorderColor(1, 1, 1, borderAlpha or 0.35)
end

local function AnchorDreamwayTooltip(owner)
    if not GameTooltip or not owner then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMRIGHT", owner, "TOPLEFT", -2, 2)
end

function DreamwayCharacterSelection()
    DreamwayProfile = DreamwayProfile or {}
    DreamwayProfile.selection = DreamwayProfile.selection or {}
    return DreamwayProfile.selection
end

function DreamwayActiveJourneyId()
    return DreamwayCharacterSelection().activeJourneyId
end

function DreamwaySetActiveJourneyId(journeyId)
    DreamwayCharacterSelection().activeJourneyId = journeyId
end

local function NormalizeDb()
    DreamwayDB = DreamwayDB or {}
    DreamwayDB.journeys = DreamwayDB.journeys or {}
    DreamwayDB.mode = DreamwayDB.mode or MODE_QUESTIE
    DreamwayDB.currentBatch = tonumber(DreamwayDB.currentBatch) or 1
    local characterSelection = DreamwayCharacterSelection()
    if characterSelection.migratedSharedSelection ~= true then
        characterSelection.activeJourneyId = characterSelection.activeJourneyId or DreamwayDB.activeJourneyId
        characterSelection.currentBatch = tonumber(characterSelection.currentBatch) or DreamwayDB.currentBatch
        characterSelection.migratedSharedSelection = true
    end
    if characterSelection.activeJourneyId and not DreamwayDB.journeys[characterSelection.activeJourneyId] then
        characterSelection.activeJourneyId = nil
        characterSelection.currentBatch = 1
    end
    DreamwayDB.showAssignedQuests = DreamwayDB.showAssignedQuests == true
    DreamwayDB.showPreviousBatchQuests = DreamwayDB.showPreviousBatchQuests == true
    DreamwayDB.suppressedUnusedPrevious = DreamwayDB.suppressedUnusedPrevious or {}
    mode = DreamwayDB.mode == MODE_DREAMWAY and MODE_DREAMWAY or MODE_QUESTIE
    batchIndex = tonumber(characterSelection.currentBatch) or 1
    panelShowAssignedQuests = DreamwayDB.showAssignedQuests
    ProfileRecorder.showPreviousBatchQuests = DreamwayDB.showPreviousBatchQuests
end

function ProfileRecorder.EnsureCharacterProfile()
    DreamwayProfile = DreamwayProfile or {}
    DreamwayProfile.schemaVersion = 2
    DreamwayProfile.app = "Dreamway"
    DreamwayProfile.kind = "CharacterProfile"
    DreamwayProfile.gameVersion = CurrentDreamwayGameVersion()
    DreamwayProfile.eventSchemaVersion = 2
    DreamwayProfile.events = DreamwayProfile.events or {}
    DreamwayProfile.recordedCompleteQuestIds = DreamwayProfile.recordedCompleteQuestIds or {}
    DreamwayProfile.recordedCompleteObjectiveKeys = DreamwayProfile.recordedCompleteObjectiveKeys or {}
    DreamwayProfile.character = DreamwayProfile.character or {}

    local characterName = UnitName("player")
    local realmName = GetRealmName and GetRealmName() or nil
    local raceName, raceFile = UnitRace("player")
    local className, classFile = UnitClass("player")
    DreamwayProfile.character.name = characterName
    DreamwayProfile.character.realm = realmName
    DreamwayProfile.character.race = raceName
    DreamwayProfile.character.raceFile = raceFile
    DreamwayProfile.character.class = className
    DreamwayProfile.character.classFile = classFile
    DreamwayProfile.character.faction = UnitFactionGroup("player")
    return DreamwayProfile
end

function ProfileRecorder.ServerTimestamp()
    if GetServerTime then
        local ok, timestamp = pcall(GetServerTime)
        if ok and tonumber(timestamp) then
            return math.floor(tonumber(timestamp))
        end
    end
    return time and time() or 0
end

function ProfileRecorder.EventLocation()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then
        return 0, 0, 0
    end

    local okMap, mapId = pcall(C_Map.GetBestMapForUnit, "player")
    mapId = okMap and tonumber(mapId) or nil
    if not mapId then
        return 0, 0, 0
    end

    local okPosition, position = pcall(C_Map.GetPlayerMapPosition, mapId, "player")
    if not okPosition or not position or not position.GetXY then
        return mapId, 0, 0
    end

    local okCoordinates, x, y = pcall(position.GetXY, position)
    if not okCoordinates or not tonumber(x) or not tonumber(y) then
        return mapId, 0, 0
    end

    x = math.max(0, math.min(1, tonumber(x)))
    y = math.max(0, math.min(1, tonumber(y)))
    return mapId, math.floor((x * 10000) + 0.5), math.floor((y * 10000) + 0.5)
end

function ProfileRecorder.UpdatedAt(timestamp)
    if date then
        return date("!%Y-%m-%dT%H:%M:%SZ", timestamp)
    end
    return tostring(timestamp)
end

function ProfileRecorder.RecordEvent(eventType, ...)
    local profile = ProfileRecorder.EnsureCharacterProfile()
    local timestamp = ProfileRecorder.ServerTimestamp()
    local mapId, x, y = ProfileRecorder.EventLocation()
    local entry = { timestamp, eventType, mapId, x, y }
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        entry[#entry + 1] = tonumber(value) or 0
    end
    profile.events[#profile.events + 1] = entry
    profile.updatedAt = ProfileRecorder.UpdatedAt(timestamp)
end

function ProfileRecorder.RefreshCharacterProfile(completedQuestId)
    local profile = ProfileRecorder.EnsureCharacterProfile()

    local completed = {}
    for _, questId in ipairs(profile.completedQuestIds or {}) do
        questId = tonumber(questId)
        if questId and questId > 0 then
            completed[questId] = true
        end
    end

    local function MergeCompletedTable(source)
        if type(source) ~= "table" then
            return
        end
        for questId, isComplete in pairs(source) do
            questId = tonumber(questId)
            if questId and questId > 0 and isComplete then
                completed[questId] = true
            end
        end
    end

    if GetQuestsCompleted then
        local ok, serverCompleted = pcall(GetQuestsCompleted)
        if ok then
            MergeCompletedTable(serverCompleted)
        end
    end

    if Questie and Questie.db and Questie.db.char then
        MergeCompletedTable(Questie.db.char.complete)
    end

    completedQuestId = tonumber(completedQuestId)
    if completedQuestId and completedQuestId > 0 then
        completed[completedQuestId] = true
    end

    local completedQuestIds = {}
    for questId in pairs(completed) do
        completedQuestIds[#completedQuestIds + 1] = questId
    end
    table.sort(completedQuestIds)
    profile.completedQuestIds = completedQuestIds
    ProfileRecorder.completedQuestIds = completed
    local timestamp = ProfileRecorder.ServerTimestamp()
    profile.updatedAt = ProfileRecorder.UpdatedAt(timestamp)
end

local function SaveDb()
    DreamwayDB.mode = mode
    local characterSelection = DreamwayCharacterSelection()
    characterSelection.activeJourneyId = DreamwayActiveJourneyId()
    characterSelection.currentBatch = batchIndex
    DreamwayDB.showAssignedQuests = panelShowAssignedQuests == true
    DreamwayDB.showPreviousBatchQuests = ProfileRecorder.showPreviousBatchQuests == true
end

local moduleCache = {}

local function ImportQuestieModule(moduleName)
    if not QuestieLoader then
        return nil
    end

    if moduleCache[moduleName] ~= nil then
        return moduleCache[moduleName]
    end

    local ok, tracker = pcall(function()
        return QuestieLoader:ImportModule(moduleName)
    end)

    if ok and tracker then
        moduleCache[moduleName] = tracker
        return tracker
    end

    return nil
end

local function GetQuestieTracker()
    return ImportQuestieModule("QuestieTracker")
end

local function GetLSM()
    if LibStub then
        local ok, lsm = pcall(function()
            return LibStub("LibSharedMedia-3.0")
        end)
        if ok then
            return lsm
        end
    end
    return nil
end

local function GetQuestieDropDown()
    if not LibStub then
        return nil
    end

    local ok, lib = pcall(function()
        return LibStub:GetLibrary("LibUIDropDownMenuQuestie-4.0")
    end)
    if ok then
        return lib
    end

    return nil
end

local function TrackerProfile()
    return Questie and Questie.db and Questie.db.profile or {}
end

local function TrackerStyle()
    local profile = TrackerProfile()
    return {
        questPadding = math.max(0, tonumber(profile.trackerQuestPadding) or 4),
        hideCompletedObjectives = profile.hideCompletedQuestObjectives == true,
        headerSize = tonumber(profile.trackerFontSizeHeader) or 12,
        zoneSize = tonumber(profile.trackerFontSizeZone) or 12,
        manualWidth = tonumber(profile.TrackerWidth) or 0,
        widthRatio = tonumber(profile.trackerWidthRatio) or 0.20,
        manualHeight = tonumber(profile.TrackerHeight) or 0,
        heightRatio = tonumber(profile.trackerHeightRatio) or 0.50,
    }
end

local function TrackerFont(fontKey)
    local profile = TrackerProfile()
    local lsm = GetLSM()
    if lsm and lsm.Fetch then
        local ok, font = pcall(lsm.Fetch, lsm, "font", profile[fontKey] or "Friz Quadrata TT")
        if ok and font then
            return font
        end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function ApplyTrackerFont(fontString, fontKey, sizeKey)
    local profile = TrackerProfile()
    local size = tonumber(profile[sizeKey]) or 10
    local outline = profile.trackerFontOutline or ""
    fontString:SetFont(TrackerFont(fontKey), size, outline)
    fontString:SetHeight(size + 4)
end

local function ActiveJourney()
    local activeJourneyId = DreamwayActiveJourneyId()
    if DreamwayDB and activeJourneyId then
        local journey = DreamwayDB.journeys[activeJourneyId]
        if journey and journey.batches and #journey.batches > 0 then
            return journey
        end
    end

    return fallbackJourney
end

local function ClampBatchIndex(journey)
    local count = journey and journey.batches and #journey.batches or 1
    if count < 1 then
        count = 1
    end
    local previousIndex = batchIndex
    if batchIndex < 1 then
        batchIndex = 1
    elseif batchIndex > count then
        batchIndex = count
    end
    if batchIndex ~= previousIndex then
        SaveDb()
    end
end

local function CurrentBatch()
    local journey = ActiveJourney()
    ClampBatchIndex(journey)
    return journey, journey.batches[batchIndex], #journey.batches
end

local function JourneyUnusedQuestSet(journey)
    local set = {}

    for _, questId in ipairs(journey and journey.hiddenQuestIds or {}) do
        questId = tonumber(questId)
        if questId then
            set[questId] = true
        end
    end

    for _, questId in ipairs(journey and journey.unusedQuestIds or {}) do
        questId = tonumber(questId)
        if questId then
            set[questId] = true
        end
    end

    for _, quest in ipairs(journey and journey.hiddenQuests or {}) do
        local questId = tonumber(quest and quest.id)
        if questId then
            set[questId] = true
        end
    end

    for _, quest in ipairs(journey and journey.unusedQuests or {}) do
        local questId = tonumber(quest and quest.id)
        if questId then
            set[questId] = true
        end
    end

    return set
end

local function EnsureQuestieHiddenTable()
    if not Questie or not Questie.db or not Questie.db.char then
        return nil
    end

    Questie.db.char.hidden = Questie.db.char.hidden or {}
    return Questie.db.char.hidden
end

local function RemoveAvailableQuestIcon(questId)
    local AvailableQuests = ImportQuestieModule("AvailableQuests")
    if AvailableQuests and AvailableQuests.RemoveQuest then
        pcall(AvailableQuests.RemoveQuest, questId)
        return
    end

    local QuestieMap = ImportQuestieModule("QuestieMap")
    if QuestieMap and QuestieMap.UnloadQuestFrames then
        pcall(QuestieMap.UnloadQuestFrames, QuestieMap, questId)
    end
end

local function RecalculateAvailableQuestIcons()
    local AvailableQuests = ImportQuestieModule("AvailableQuests")
    if AvailableQuests and AvailableQuests.CalculateAndDrawAll then
        pcall(AvailableQuests.CalculateAndDrawAll)
    end
end

local function SavedSuppressionTable()
    if not DreamwayDB then
        return nil
    end

    DreamwayDB.suppressedUnusedPrevious = DreamwayDB.suppressedUnusedPrevious or {}
    return DreamwayDB.suppressedUnusedPrevious
end

local function SaveSuppressedQuestState(questId, previous)
    local saved = SavedSuppressionTable()
    if saved then
        saved[tostring(questId)] = previous == nil and SUPPRESSED_SAVED_ABSENT or previous
    end
end

local function ClearSuppressedQuestState(questId)
    local saved = SavedSuppressionTable()
    if saved then
        saved[tostring(questId)] = nil
    end
end

local function RestorePersistedSuppressionStates()
    local saved = SavedSuppressionTable()
    if not saved then
        return
    end

    for questId, previous in pairs(saved) do
        questId = tonumber(questId)
        if questId and suppressedUnusedQuestStates[questId] == nil then
            suppressedUnusedQuestStates[questId] = previous == SUPPRESSED_SAVED_ABSENT and SUPPRESSED_ABSENT or previous
        end
    end
end

local function RestoreUnusedQuestSuppression(skipRedraw)
    local hidden = EnsureQuestieHiddenTable()
    if not hidden then
        return
    end

    RestorePersistedSuppressionStates()

    local needsRecalculate = false
    for questId, previous in pairs(suppressedUnusedQuestStates) do
        if previous == SUPPRESSED_ABSENT then
            hidden[questId] = nil
            needsRecalculate = true
        else
            hidden[questId] = previous
            if previous then
                RemoveAvailableQuestIcon(questId)
            else
                needsRecalculate = true
            end
        end
        suppressedUnusedQuestStates[questId] = nil
        ClearSuppressedQuestState(questId)
    end

    if needsRecalculate and not skipRedraw then
        RecalculateAvailableQuestIcons()
    end
end

local function ApplyUnusedQuestSuppression()
    if mode ~= MODE_DREAMWAY then
        RestoreUnusedQuestSuppression()
        return
    end

    local hidden = EnsureQuestieHiddenTable()
    if not hidden then
        return
    end

    RestorePersistedSuppressionStates()

    local unusedSet = JourneyUnusedQuestSet(ActiveJourney())
    local needsRecalculate = false

    for questId, previous in pairs(suppressedUnusedQuestStates) do
        if not unusedSet[questId] then
            if previous == SUPPRESSED_ABSENT then
                hidden[questId] = nil
                needsRecalculate = true
            else
                hidden[questId] = previous
                if previous then
                    RemoveAvailableQuestIcon(questId)
                else
                    needsRecalculate = true
                end
            end
            suppressedUnusedQuestStates[questId] = nil
            ClearSuppressedQuestState(questId)
        end
    end

    for questId in pairs(unusedSet) do
        if suppressedUnusedQuestStates[questId] == nil then
            local previous = hidden[questId]
            suppressedUnusedQuestStates[questId] = previous == nil and SUPPRESSED_ABSENT or previous
            SaveSuppressedQuestState(questId, previous)
        end

        if hidden[questId] ~= true then
            hidden[questId] = true
        end
        RemoveAvailableQuestIcon(questId)
    end

    if needsRecalculate then
        RecalculateAvailableQuestIcons()
    end
end

local function IsQuestInLog(questId)
    questId = tonumber(questId)
    if not questId then
        return false
    end

    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questId)
        if ok and index then
            return index > 0
        end
    end

    if GetQuestLogIndexByID then
        local ok, index = pcall(GetQuestLogIndexByID, questId)
        if ok and index then
            return index > 0
        end
    end

    return false
end

local function IsQuestCompleteInLog(questId)
    questId = tonumber(questId)
    if not questId then
        return false
    end

    if C_QuestLog and C_QuestLog.IsComplete then
        local ok, complete = pcall(C_QuestLog.IsComplete, questId)
        if ok and complete then
            return true
        end
    end

    local QuestieDB = ImportQuestieModule("QuestieDB")
    if QuestieDB and QuestieDB.IsComplete then
        local ok, complete = pcall(QuestieDB.IsComplete, questId)
        if ok and complete == 1 then
            return true
        end
    end

    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo then
        local okIndex, index = pcall(C_QuestLog.GetLogIndexForQuestID, questId)
        if okIndex and index and index > 0 then
            local okInfo, info = pcall(C_QuestLog.GetInfo, index)
            if okInfo and info and info.isComplete then
                return true
            end
        end
    end

    local questLogIndex
    if GetQuestLogIndexByID then
        local ok, index = pcall(GetQuestLogIndexByID, questId)
        if ok then
            questLogIndex = index
        end
    end
    if questLogIndex and questLogIndex > 0 and GetQuestLogTitle then
        local ok, _, _, _, _, _, complete = pcall(GetQuestLogTitle, questLogIndex)
        if ok and (complete == true or complete == 1) then
            return true
        end
    end

    return false
end

local function IsQuestTurnedIn(questId)
    questId = tonumber(questId)
    if not questId then
        return false
    end

    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, complete = pcall(C_QuestLog.IsQuestFlaggedCompleted, questId)
        if ok and complete then
            return true
        end
    end

    if IsQuestFlaggedCompleted then
        local ok, complete = pcall(IsQuestFlaggedCompleted, questId)
        if ok and complete then
            return true
        end
    end

    if not ProfileRecorder.completedQuestIds then
        ProfileRecorder.completedQuestIds = {}
        for _, completedQuestId in ipairs(DreamwayProfile and DreamwayProfile.completedQuestIds or {}) do
            completedQuestId = tonumber(completedQuestId)
            if completedQuestId then
                ProfileRecorder.completedQuestIds[completedQuestId] = true
            end
        end
    end
    if ProfileRecorder.completedQuestIds[questId] then
        return true
    end

    if Questie and Questie.db and Questie.db.char and Questie.db.char.complete then
        if Questie.db.char.complete[questId] or Questie.db.char.complete[tostring(questId)] then
            return true
        end
    end

    return false
end

local function AnyQuestComplete(ids)
    if not ids then
        return false
    end

    for _, questId in ipairs(ids) do
        if IsQuestTurnedIn(questId) then
            return true
        end
    end

    return false
end

local function AllQuestsComplete(ids)
    if not ids or #ids == 0 then
        return true
    end

    for _, questId in ipairs(ids) do
        if not IsQuestTurnedIn(questId) then
            return false
        end
    end

    return true
end

local function HasUnmetPrerequisite(quest)
    if quest.preQuestGroup and #quest.preQuestGroup > 0 and not AllQuestsComplete(quest.preQuestGroup) then
        return true
    end

    if quest.preQuestSingle and #quest.preQuestSingle > 0 and not AnyQuestComplete(quest.preQuestSingle) then
        return true
    end

    return false
end

local function ClassifyQuest(quest)
    if quest.id and IsQuestTurnedIn(quest.id) then
        return nil
    end

    if HasUnmetPrerequisite(quest) then
        return "prereq"
    end

    if quest.id then
        if IsQuestCompleteInLog(quest.id) then
            return "turnin"
        end

        if IsQuestInLog(quest.id) then
            return "progress"
        end

    end

    if quest.category == "prereq" or quest.category == "pickup" or quest.category == "progress" or quest.category == "turnin" then
        return quest.category
    end

    return "pickup"
end

local function QuestDisplayName(quest)
    local name = quest.name or (quest.id and ("Quest #" .. tostring(quest.id))) or "Unknown quest"
    if quest.questLevel then
        return "[" .. tostring(quest.questLevel) .. "] " .. name
    end
    return name
end

local function GetQuestieQuest(quest)
    local questId = tonumber(quest and quest.id)
    if not questId then
        return nil
    end

    local QuestieDB = ImportQuestieModule("QuestieDB")
    if QuestieDB and QuestieDB.GetQuest then
        local ok, dbQuest = pcall(QuestieDB.GetQuest, questId)
        if ok and dbQuest then
            return dbQuest
        end
    end

    return {
        Id = questId,
        id = questId,
        name = quest.name or ("Quest #" .. tostring(questId)),
        level = quest.questLevel or quest.requiredLevel or 0,
    }
end

local function ColoredQuestDisplayName(quest, showState)
    local questId = tonumber(quest and quest.id)
    if questId then
        local QuestieLib = ImportQuestieModule("QuestieLib")
        if QuestieLib and QuestieLib.GetColoredQuestName and Questie and Questie.db and Questie.db.profile then
            local showLevel = Questie.db.profile.trackerShowQuestLevel
            if showLevel == nil then
                showLevel = true
            end

            local ok, text = pcall(QuestieLib.GetColoredQuestName, QuestieLib, questId, showLevel, showState)
            if ok and text then
                return text
            end
        end
    end

    local fallback = QuestDisplayName(quest)
    local level = tonumber(quest and quest.questLevel)
    local QuestieLib = ImportQuestieModule("QuestieLib")
    if QuestieLib and QuestieLib.PrintDifficultyColor and level then
        local ok, text = pcall(QuestieLib.PrintDifficultyColor, QuestieLib, level, fallback)
        if ok and text then
            return text
        end
    end

    return fallback
end

local function ColoredQuestSearchDisplayName(quest)
    local questId = tonumber(quest and quest.id) or 0
    local questLevel = tonumber(quest and quest.questLevel) or 0
    local playerLevel = UnitLevel and tonumber(UnitLevel("player")) or 0
    local cacheKey = tostring(questId) .. ":" .. tostring(questLevel) .. ":" .. tostring(playerLevel)
    local cached = ProfileRecorder.searchDisplayTextByKey[cacheKey]
    if cached then
        return cached
    end

    local isDungeon = false
    local isElite = false
    local isRepeatable = false
    local isEvent = false
    local isPvP = false
    for _, typeId in ipairs(quest and quest.typeIds or {}) do
        typeId = tostring(typeId)
        isDungeon = isDungeon or typeId == "dungeon" or typeId == "raid"
        isElite = isElite or typeId == "elite"
        isRepeatable = isRepeatable or typeId == "repeatable"
        isEvent = isEvent or typeId == "holiday" or typeId == "seasonal"
        isPvP = isPvP or typeId == "pvp"
    end
    local levelTag = tostring(questLevel)
    if isDungeon then
        levelTag = levelTag .. "D"
    elseif isElite then
        levelTag = levelTag .. "+"
    end
    local text = "[" .. levelTag .. "] " .. tostring(quest and quest.name or ("Quest #" .. tostring(questId)))
    local QuestieLib = ImportQuestieModule("QuestieLib")
    if QuestieLib and QuestieLib.PrintDifficultyColor and questLevel > 0 then
        local ok, colored = pcall(
            QuestieLib.PrintDifficultyColor,
            QuestieLib,
            questLevel,
            text,
            isRepeatable,
            isEvent,
            isPvP
        )
        if ok and colored then
            text = colored
        end
    end
    ProfileRecorder.searchDisplayTextByKey[cacheKey] = text
    return text
end

local function IsJourneyComplete(quest)
    local questId = tonumber(quest and quest.id)
    if not questId then
        return false
    end
    if not ProfileRecorder.completedQuestIds then
        ProfileRecorder.completedQuestIds = {}
        for _, completedQuestId in ipairs(DreamwayProfile and DreamwayProfile.completedQuestIds or {}) do
            completedQuestId = tonumber(completedQuestId)
            if completedQuestId then
                ProfileRecorder.completedQuestIds[completedQuestId] = true
            end
        end
    end
    if ProfileRecorder.completedQuestIds[questId] then
        return true
    end
    local questieCompleted = Questie
        and Questie.db
        and Questie.db.char
        and Questie.db.char.complete
    if questieCompleted and (questieCompleted[questId] or questieCompleted[tostring(questId)]) then
        ProfileRecorder.completedQuestIds[questId] = true
        return true
    end
    return false
end

local function GetQuestLogIndex(questId)
    questId = tonumber(questId)
    if not questId then
        return nil
    end

    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questId)
        if ok and index and index > 0 then
            return index
        end
    end

    if GetQuestLogIndexByID then
        local ok, index = pcall(GetQuestLogIndexByID, questId)
        if ok and index and index > 0 then
            return index
        end
    end

    return nil
end

local function GetQuestObjectiveLines(quest)
    local questId = tonumber(quest and quest.id)
    if not questId or not IsQuestInLog(questId) then
        return {}
    end

    local lines = {}
    local style = TrackerStyle()
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questId)
        if ok and type(objectives) == "table" then
            for _, objective in ipairs(objectives) do
                if objective and objective.text and objective.text ~= "" then
                    local finished = objective.finished == true
                    if not (style.hideCompletedObjectives and finished) then
                        lines[#lines + 1] = {
                            text = objective.text,
                            finished = finished,
                            collected = tonumber(objective.numFulfilled or objective.fulfilled),
                            needed = tonumber(objective.numRequired or objective.required),
                        }
                    end
                end
            end
        end
    end

    if #lines > 0 then
        return lines
    end

    local questLogIndex = GetQuestLogIndex(questId)
    if questLogIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local okCount, count = pcall(GetNumQuestLeaderBoards, questLogIndex)
        if okCount and count and count > 0 then
            for objectiveIndex = 1, count do
                local okObjective, text, _, finished = pcall(GetQuestLogLeaderBoard, objectiveIndex, questLogIndex)
                if okObjective and text and text ~= "" then
                    finished = finished == true
                    if not (style.hideCompletedObjectives and finished) then
                        local collected, needed = text:match("(%d+)%s*/%s*(%d+)")
                        lines[#lines + 1] = {
                            text = text,
                            finished = finished,
                            collected = tonumber(collected),
                            needed = tonumber(needed),
                        }
                    end
                end
            end
        end
    end

    return lines
end

function ProfileRecorder.QuestLogQuestIds()
    local questIds = {}
    local seen = {}
    local QuestiePlayer = ImportQuestieModule("QuestiePlayer")
    if QuestiePlayer and type(QuestiePlayer.currentQuestlog) == "table" then
        for questId in pairs(QuestiePlayer.currentQuestlog) do
            questId = tonumber(questId)
            if questId and questId > 0 and not seen[questId] then
                seen[questId] = true
                questIds[#questIds + 1] = questId
            end
        end
    end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local okCount, count = pcall(C_QuestLog.GetNumQuestLogEntries)
        if okCount and tonumber(count) then
            for index = 1, tonumber(count) do
                local okInfo, info = pcall(C_QuestLog.GetInfo, index)
                local questId = okInfo and info and not info.isHeader and tonumber(info.questID) or nil
                if questId and questId > 0 and not seen[questId] then
                    seen[questId] = true
                    questIds[#questIds + 1] = questId
                end
            end
        end
    end

    if #questIds == 0 and GetNumQuestLogEntries and GetQuestLogTitle then
        local okCount, count = pcall(GetNumQuestLogEntries)
        if okCount and tonumber(count) then
            for index = 1, tonumber(count) do
                local results = { pcall(GetQuestLogTitle, index) }
                local questId = results[1] and tonumber(results[9]) or nil
                local isHeader = results[1] and results[5]
                if questId and questId > 0 and not isHeader and not seen[questId] then
                    seen[questId] = true
                    questIds[#questIds + 1] = questId
                end
            end
        end
    end

    return questIds
end

function ProfileRecorder.ObjectiveCounts(text, finished, current, total)
    current = tonumber(current)
    total = tonumber(total)
    if current and total then
        return current, total
    end
    local parsedCurrent, parsedTotal = tostring(text or ""):match("(%d+)%s*/%s*(%d+)")
    if parsedCurrent and parsedTotal then
        return tonumber(parsedCurrent), tonumber(parsedTotal)
    end
    if finished then
        return 1, 1
    end
    return 0, 0
end

function ProfileRecorder.QuestObjectiveSnapshot(questId)
    local snapshot = {}
    local QuestLogCache = ImportQuestieModule("QuestLogCache")
    if QuestLogCache and type(QuestLogCache.questLog_DO_NOT_MODIFY) == "table" then
        local cacheEntry = QuestLogCache.questLog_DO_NOT_MODIFY[questId]
        local objectives = cacheEntry and cacheEntry.objectives
        if type(objectives) == "table" then
            for index, objective in ipairs(objectives) do
                local text = objective and tostring(objective.text or objective.raw_text or "") or ""
                local finished = objective and objective.finished and true or false
                local current, total = ProfileRecorder.ObjectiveCounts(
                    text,
                    finished,
                    objective and (objective.numFulfilled or objective.raw_numFulfilled),
                    objective and objective.numRequired
                )
                snapshot[index] = {
                    text = text,
                    current = current,
                    total = total,
                    finished = finished,
                }
            end
        end
    end

    if #snapshot > 0 then
        return snapshot
    end

    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questId)
        if ok and type(objectives) == "table" then
            for index, objective in ipairs(objectives) do
                local text = objective and tostring(objective.text or "") or ""
                local finished = objective and objective.finished and true or false
                local current, total = ProfileRecorder.ObjectiveCounts(
                    text,
                    finished,
                    objective and (objective.numFulfilled or objective.numCurrent),
                    objective and (objective.numRequired or objective.numNeeded)
                )
                snapshot[index] = {
                    text = text,
                    current = current,
                    total = total,
                    finished = finished,
                }
            end
        end
    end

    if #snapshot > 0 then
        return snapshot
    end

    for index, objective in ipairs(GetQuestObjectiveLines({ id = questId })) do
        local current, total = ProfileRecorder.ObjectiveCounts(objective.text, objective.finished)
        snapshot[index] = {
            text = tostring(objective.text or ""),
            current = current,
            total = total,
            finished = objective.finished and true or false,
        }
    end
    return snapshot
end

function ProfileRecorder.HasRecordedQuestComplete(questId)
    questId = tonumber(questId)
    if not questId then
        return false
    end
    local profile = ProfileRecorder.EnsureCharacterProfile()
    for _, completedQuestId in ipairs(profile.completedQuestIds or {}) do
        if tonumber(completedQuestId) == questId then
            return true
        end
    end
    for _, completedQuestId in ipairs(profile.recordedCompleteQuestIds or {}) do
        if tonumber(completedQuestId) == questId then
            return true
        end
    end
    for _, event in ipairs(profile.events or {}) do
        if tonumber(event[2]) == ProfileRecorder.EVENT_QUEST_COMPLETE and tonumber(event[6]) == questId then
            return true
        end
    end
    return false
end

function ProfileRecorder.RecordQuestCompleteEvent(questId)
    questId = tonumber(questId)
    if not questId or ProfileRecorder.HasRecordedQuestComplete(questId) then
        return
    end
    ProfileRecorder.RecordEvent(ProfileRecorder.EVENT_QUEST_COMPLETE, questId)
    local profile = ProfileRecorder.EnsureCharacterProfile()
    profile.recordedCompleteQuestIds[#profile.recordedCompleteQuestIds + 1] = questId
end

function ProfileRecorder.HasRecordedObjectiveComplete(questId, objectiveIndex)
    local key = tostring(tonumber(questId) or 0) .. ":" .. tostring(tonumber(objectiveIndex) or 0)
    local profile = ProfileRecorder.EnsureCharacterProfile()
    for _, recordedKey in ipairs(profile.recordedCompleteObjectiveKeys or {}) do
        if tostring(recordedKey) == key then
            return true
        end
    end
    for _, event in ipairs(profile.events or {}) do
        local eventCurrent = tonumber(event[8]) or 0
        local eventTotal = tonumber(event[9]) or 0
        if tonumber(event[2]) == ProfileRecorder.EVENT_OBJECTIVE
            and tonumber(event[6]) == tonumber(questId)
            and tonumber(event[7]) == tonumber(objectiveIndex)
            and eventTotal > 0
            and eventCurrent >= eventTotal
        then
            return true
        end
    end
    return false
end

function ProfileRecorder.RecordObjectiveEvent(questId, objectiveIndex, objective)
    questId = tonumber(questId)
    objectiveIndex = tonumber(objectiveIndex)
    if not questId or questId <= 0 or not objectiveIndex or objectiveIndex <= 0 then
        return
    end
    objective = objective or {}
    local current = tonumber(objective.current) or 0
    local total = tonumber(objective.total) or 0
    local isComplete = objective.finished == true or (total > 0 and current >= total)
    if isComplete and ProfileRecorder.HasRecordedObjectiveComplete(questId, objectiveIndex) then
        return
    end
    local signature = tostring(current) .. ":" .. tostring(total) .. ":" .. tostring(objective.text or "")
    local key = tostring(questId) .. ":" .. tostring(objectiveIndex)
    local timestamp = GetTime and GetTime() or 0
    local previous = ProfileRecorder.lastObjectiveEvents[key]
    if previous and previous.signature == signature and timestamp - previous.timestamp <= 3 then
        return
    end
    ProfileRecorder.lastObjectiveEvents[key] = {
        signature = signature,
        timestamp = timestamp,
    }
    ProfileRecorder.RecordEvent(
        ProfileRecorder.EVENT_OBJECTIVE,
        questId,
        objectiveIndex,
        current,
        total
    )
    if isComplete then
        local profile = ProfileRecorder.EnsureCharacterProfile()
        profile.recordedCompleteObjectiveKeys[#profile.recordedCompleteObjectiveKeys + 1] =
            tostring(questId) .. ":" .. tostring(objectiveIndex)
    end
end

function ProfileRecorder.NormalizeObjectiveText(text)
    text = string.lower(tostring(text or ""))
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("%d+%s*/%s*%d+", "")
    text = text:gsub("quest objective complete", "")
    text = text:gsub("objective complete", "")
    text = text:gsub("slain", "")
    text = text:gsub("found", "")
    text = text:gsub("[^%w]+", " ")
    return text:match("^%s*(.-)%s*$") or ""
end

function ProfileRecorder.RecordUiObjectiveMessage(errorType, message)
    local messageType = GetGameMessageInfo and GetGameMessageInfo(errorType) or nil
    local supported = messageType == "ERR_QUEST_OBJECTIVE_COMPLETE_S"
        or messageType == "ERR_QUEST_UNKNOWN_COMPLETE"
        or messageType == "ERR_QUEST_ADD_KILL_SII"
        or messageType == "ERR_QUEST_ADD_FOUND_SII"
        or messageType == "ERR_QUEST_ADD_ITEM_SII"
        or messageType == "ERR_QUEST_ADD_PLAYER_KILL_SII"
    if not supported then
        return
    end

    message = tostring(message or "")
    local messageCurrent, messageTotal = message:match("(%d+)%s*/%s*(%d+)")
    messageCurrent = tonumber(messageCurrent)
    messageTotal = tonumber(messageTotal)
    local messageLabel = ProfileRecorder.NormalizeObjectiveText(message)
    local pending = {
        label = messageLabel,
        current = messageCurrent,
        total = messageTotal,
        receivedAt = GetTime and GetTime() or 0,
    }
    ProfileRecorder.pendingUiObjectiveMessage = pending
    C_Timer.After(0.1, function()
        if ProfileRecorder.pendingUiObjectiveMessage ~= pending then
            return
        end
        local best
        for _, questId in ipairs(ProfileRecorder.QuestLogQuestIds()) do
            local objectives = ProfileRecorder.QuestObjectiveSnapshot(questId)
            for objectiveIndex, objective in ipairs(objectives) do
                local score = 0
                local objectiveLabel = ProfileRecorder.NormalizeObjectiveText(objective.text)
                if messageLabel ~= "" and objectiveLabel ~= "" then
                    if messageLabel == objectiveLabel then
                        score = score + 20
                    elseif messageLabel:find(objectiveLabel, 1, true) or objectiveLabel:find(messageLabel, 1, true) then
                        score = score + 12
                    end
                end
                if messageTotal and tonumber(objective.total) == messageTotal then
                    score = score + 4
                end
                if messageCurrent and tonumber(objective.current) == messageCurrent then
                    score = score + 2
                end
                if objective.finished then
                    score = score + 1
                end
                if score >= 6 and (not best or score > best.score) then
                    best = {
                        score = score,
                        questId = questId,
                        objectiveIndex = objectiveIndex,
                        objectives = objectives,
                        objective = objective,
                    }
                end
            end
        end
        if not best then
            return
        end
        if messageCurrent then
            best.objective.current = messageCurrent
        end
        if messageTotal then
            best.objective.total = messageTotal
        end
        best.objective.finished = best.objective.finished
            or (messageCurrent and messageTotal and messageCurrent >= messageTotal)
        ProfileRecorder.RecordObjectiveEvent(best.questId, best.objectiveIndex, best.objective)
        best.objectives[best.objectiveIndex] = best.objective
        ProfileRecorder.questObjectiveState[best.questId] = best.objectives
        ProfileRecorder.pendingUiObjectiveMessage = nil
        ProfileRecorder.ScheduleQuestObjectiveEventRefresh(true)
    end)
end

function ProfileRecorder.RecordQuestWatchUpdate(questId)
    questId = tonumber(questId)
    if not questId then
        ProfileRecorder.ScheduleQuestObjectiveEventRefresh(true)
        return
    end

    C_Timer.After(0.1, function()
        local objectives = ProfileRecorder.QuestObjectiveSnapshot(questId)
        local previousObjectives = ProfileRecorder.questObjectiveState[questId]
        local recorded = false

        if previousObjectives then
            for objectiveIndex, current in ipairs(objectives) do
                local previous = previousObjectives[objectiveIndex]
                if previous then
                    local progressed = current.current > previous.current
                        or (current.finished and not previous.finished)
                        or (current.text ~= previous.text and current.current == previous.current and current.total == previous.total)
                    if progressed then
                        ProfileRecorder.RecordObjectiveEvent(questId, objectiveIndex, current)
                        recorded = true
                    end
                end
            end
        end

        local pending = ProfileRecorder.pendingUiObjectiveMessage
        local now = GetTime and GetTime() or 0
        if not recorded and pending and now - (pending.receivedAt or 0) <= 3 then
            local bestIndex
            local bestScore = -1
            for objectiveIndex, objective in ipairs(objectives) do
                local score = 0
                local objectiveLabel = ProfileRecorder.NormalizeObjectiveText(objective.text)
                if pending.label ~= "" and objectiveLabel ~= "" then
                    if pending.label == objectiveLabel then
                        score = score + 20
                    elseif pending.label:find(objectiveLabel, 1, true) or objectiveLabel:find(pending.label, 1, true) then
                        score = score + 12
                    end
                end
                if pending.total and tonumber(objective.total) == pending.total then
                    score = score + 4
                end
                if pending.current and tonumber(objective.current) == pending.current then
                    score = score + 2
                end
                if score > bestScore then
                    bestScore = score
                    bestIndex = objectiveIndex
                end
            end

            if bestIndex and (bestScore >= 6 or (#objectives == 1 and pending.current)) then
                local objective = objectives[bestIndex]
                objective.current = pending.current or objective.current
                objective.total = pending.total or objective.total
                objective.finished = objective.finished
                    or (objective.total > 0 and objective.current >= objective.total)
                ProfileRecorder.RecordObjectiveEvent(questId, bestIndex, objective)
                objectives[bestIndex] = objective
                recorded = true
            end
        end

        if recorded then
            ProfileRecorder.pendingUiObjectiveMessage = nil
        end
        if #objectives > 0 then
            ProfileRecorder.questObjectiveState[questId] = objectives
        end

        local complete = IsQuestCompleteInLog(questId)
        if complete and ProfileRecorder.questCompleteState[questId] == false then
            ProfileRecorder.RecordQuestCompleteEvent(questId)
        end
        ProfileRecorder.questCompleteState[questId] = complete and true or false
    end)
end

function ProfileRecorder.RecordQuestieObjectiveUpdate(questId, objectiveIndex, attempt)
    questId = tonumber(questId)
    objectiveIndex = tonumber(objectiveIndex)
    if not questId or not objectiveIndex then
        return
    end
    attempt = tonumber(attempt) or 1
    local objectives = ProfileRecorder.QuestObjectiveSnapshot(questId)
    local objective = objectives[objectiveIndex]
    if not objective then
        if attempt < 4 then
            C_Timer.After(attempt * 0.2, function()
                ProfileRecorder.RecordQuestieObjectiveUpdate(questId, objectiveIndex, attempt + 1)
            end)
        end
        return
    end
    ProfileRecorder.RecordObjectiveEvent(questId, objectiveIndex, objective)
    ProfileRecorder.questObjectiveState[questId] = objectives

    local complete = IsQuestCompleteInLog(questId)
    if complete and ProfileRecorder.questCompleteState[questId] ~= true then
        ProfileRecorder.RecordQuestCompleteEvent(questId)
    end
    ProfileRecorder.questCompleteState[questId] = complete and true or false
end

function ProfileRecorder.ActiveQuestItemObjectives(itemId)
    local matches = {}
    local QuestieDB = ImportQuestieModule("QuestieDB")
    if not QuestieDB or not QuestieDB.GetQuest then
        return matches
    end
    for _, questId in ipairs(ProfileRecorder.QuestLogQuestIds()) do
        local ok, quest = pcall(QuestieDB.GetQuest, questId)
        if ok and quest and type(quest.ObjectiveData) == "table" then
            for objectiveIndex, objective in pairs(quest.ObjectiveData) do
                if objective and objective.Type == "item" and tonumber(objective.Id) == itemId then
                    matches[#matches + 1] = {
                        questId = questId,
                        objectiveIndex = objectiveIndex,
                    }
                end
            end
        end
    end
    return matches
end

function ProfileRecorder.RecordLootedQuestItem(message)
    message = tostring(message or "")
    if not message:find("^You ") then
        return
    end
    local itemId = tonumber(message:match("|Hitem:(%d+)"))
    if not itemId then
        return
    end
    local matches = ProfileRecorder.ActiveQuestItemObjectives(itemId)
    if #matches == 0 then
        return
    end
    C_Timer.After(0.2, function()
        local bagCount = GetItemCount and tonumber(GetItemCount(itemId, false)) or 0
        for _, match in ipairs(matches) do
            local objectives = ProfileRecorder.QuestObjectiveSnapshot(match.questId)
            local objective = objectives[match.objectiveIndex] or {
                text = "",
                current = 0,
                total = 0,
                finished = false,
            }
            local previousObjectives = ProfileRecorder.questObjectiveState[match.questId]
            local previous = previousObjectives and previousObjectives[match.objectiveIndex]
            local total = tonumber(objective.total) or 0
            local current = tonumber(objective.current) or 0
            if bagCount > current then
                current = total > 0 and math.min(bagCount, total) or bagCount
                objective.current = current
                objective.finished = total > 0 and current >= total
            end
            if not previous or current > (tonumber(previous.current) or 0) or (objective.finished and not previous.finished) then
                ProfileRecorder.RecordObjectiveEvent(match.questId, match.objectiveIndex, objective)
            end
            objectives[match.objectiveIndex] = objective
            ProfileRecorder.questObjectiveState[match.questId] = objectives
        end
    end)
end

function ProfileRecorder.RefreshQuestObjectiveEventState(recordChanges)
    local currentQuestIds = ProfileRecorder.QuestLogQuestIds()
    local present = {}
    for _, questId in ipairs(currentQuestIds) do
        present[questId] = true
        local currentObjectives = ProfileRecorder.QuestObjectiveSnapshot(questId)
        local previousObjectives = ProfileRecorder.questObjectiveState[questId]
        if #currentObjectives > 0 and recordChanges and previousObjectives then
            for objectiveIndex, current in ipairs(currentObjectives) do
                local previous = previousObjectives[objectiveIndex]
                if previous then
                    local progressed = current.current > previous.current
                        or (current.finished and not previous.finished)
                        or (current.text ~= previous.text and current.current == previous.current and current.total == previous.total)
                    if progressed then
                        ProfileRecorder.RecordObjectiveEvent(questId, objectiveIndex, current)
                    end
                end
            end
        end
        if #currentObjectives > 0 then
            ProfileRecorder.questObjectiveState[questId] = currentObjectives
        end

        local complete = IsQuestCompleteInLog(questId)
        if recordChanges and complete and ProfileRecorder.questCompleteState[questId] == false then
            ProfileRecorder.RecordQuestCompleteEvent(questId)
        end
        ProfileRecorder.questCompleteState[questId] = complete and true or false
    end

    for questId in pairs(ProfileRecorder.questObjectiveState) do
        if not present[questId] then
            ProfileRecorder.questObjectiveState[questId] = nil
            ProfileRecorder.questCompleteState[questId] = nil
        end
    end
end

function ProfileRecorder.ScheduleQuestObjectiveEventRefresh(recordChanges)
    ProfileRecorder.refreshShouldRecord = ProfileRecorder.refreshShouldRecord or recordChanges
    ProfileRecorder.refreshGeneration = ProfileRecorder.refreshGeneration + 1
    if ProfileRecorder.refreshPending then
        return
    end
    ProfileRecorder.refreshPending = true
    C_Timer.After(0.1, function()
        local shouldRecord = ProfileRecorder.refreshShouldRecord
        ProfileRecorder.refreshShouldRecord = false
        ProfileRecorder.refreshPending = false
        ProfileRecorder.RefreshQuestObjectiveEventState(shouldRecord)
        if shouldRecord then
            local settledGeneration = ProfileRecorder.refreshGeneration
            C_Timer.After(0.75, function()
                if settledGeneration == ProfileRecorder.refreshGeneration then
                    ProfileRecorder.RefreshQuestObjectiveEventState(true)
                end
            end)
            C_Timer.After(2, function()
                if settledGeneration == ProfileRecorder.refreshGeneration then
                    ProfileRecorder.RefreshQuestObjectiveEventState(true)
                end
            end)
        end
    end)
end

function ProfileRecorder.RegisterQuestieCallbacks()
    if not ProfileRecorder.questieCallbackRegistered
        and Questie
        and Questie.API
        and Questie.API.RegisterForQuestUpdates
    then
        Questie.API.RegisterForQuestUpdates(function(questId, objectiveIndex)
            if objectiveIndex then
                ProfileRecorder.RecordQuestieObjectiveUpdate(questId, objectiveIndex)
            end
        end)
        ProfileRecorder.questieCallbackRegistered = true
    end

    local QuestieAnnounce = ImportQuestieModule("QuestieAnnounce")
    if not ProfileRecorder.questieAnnounceHooked and QuestieAnnounce and QuestieAnnounce.ObjectiveChanged then
        hooksecurefunc(QuestieAnnounce, "ObjectiveChanged", function(_, questId, text, numFulfilled, numRequired)
            questId = tonumber(questId)
            if not questId then
                return
            end
            local objectives = ProfileRecorder.QuestObjectiveSnapshot(questId)
            local targetLabel = ProfileRecorder.NormalizeObjectiveText(text)
            for objectiveIndex, objective in ipairs(objectives) do
                local objectiveLabel = ProfileRecorder.NormalizeObjectiveText(objective.text)
                if targetLabel ~= "" and objectiveLabel == targetLabel then
                    local previousObjectives = ProfileRecorder.questObjectiveState[questId]
                    local previous = previousObjectives and previousObjectives[objectiveIndex]
                    objective.current = tonumber(numFulfilled) or objective.current
                    objective.total = tonumber(numRequired) or objective.total
                    objective.finished = objective.total > 0 and objective.current >= objective.total
                    if objective.current > 0 and (not previous or objective.current > (tonumber(previous.current) or 0)) then
                        ProfileRecorder.RecordObjectiveEvent(questId, objectiveIndex, objective)
                    end
                    objectives[objectiveIndex] = objective
                    ProfileRecorder.questObjectiveState[questId] = objectives
                    break
                end
            end
        end)
        ProfileRecorder.questieAnnounceHooked = true
    end
end

function ProfileRecorder.AcceptedQuestId(questLogIndex, questId)
    questId = tonumber(questId)
    if questId then
        return questId
    end
    questLogIndex = tonumber(questLogIndex)
    if questLogIndex and C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then
        local ok, resolved = pcall(C_QuestLog.GetQuestIDForLogIndex, questLogIndex)
        if ok then
            return tonumber(resolved)
        end
    end
    if questLogIndex and GetQuestLogTitle then
        local results = { pcall(GetQuestLogTitle, questLogIndex) }
        if results[1] then
            return tonumber(results[9])
        end
    end
    return nil
end

function ProfileRecorder.NpcIdFromGuid(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local unitType = guid:match("^([^-]+)")
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        return nil
    end
    local _, _, _, _, _, npcId = strsplit("-", guid)
    return tonumber(npcId)
end

function ProfileRecorder.RecordMobKill(guid, npcId, timestamp)
    local recordedAt = ProfileRecorder.recordedKillGuids[guid]
    if recordedAt and timestamp - recordedAt <= 10 then
        return
    end
    ProfileRecorder.recordedKillGuids[guid] = timestamp
    ProfileRecorder.damagedNpcGuids[guid] = nil
    ProfileRecorder.RecordEvent(ProfileRecorder.EVENT_KILL, npcId)
end

function ProfileRecorder.PruneCombatState(timestamp)
    if timestamp - ProfileRecorder.lastCombatPrune < 60 then
        return
    end
    ProfileRecorder.lastCombatPrune = timestamp
    for guid, seenAt in pairs(ProfileRecorder.damagedNpcGuids) do
        if timestamp - seenAt > 300 then
            ProfileRecorder.damagedNpcGuids[guid] = nil
        end
    end
    for guid, seenAt in pairs(ProfileRecorder.recordedKillGuids) do
        if timestamp - seenAt > 30 then
            ProfileRecorder.recordedKillGuids[guid] = nil
        end
    end
    for index = #ProfileRecorder.recentNpcDeaths, 1, -1 do
        if timestamp - ProfileRecorder.recentNpcDeaths[index].seenAt > 10 then
            table.remove(ProfileRecorder.recentNpcDeaths, index)
        end
    end
end

function ProfileRecorder.RecordRecentXpKill()
    local timestamp = GetTime and GetTime() or 0
    ProfileRecorder.PruneCombatState(timestamp)
    for index = #ProfileRecorder.recentNpcDeaths, 1, -1 do
        local death = ProfileRecorder.recentNpcDeaths[index]
        if timestamp - death.seenAt <= 5 then
            ProfileRecorder.RecordMobKill(death.guid, death.npcId, timestamp)
            table.remove(ProfileRecorder.recentNpcDeaths, index)
            return
        end
    end
    local targetGuid = UnitGUID("target")
    local targetNpcId = ProfileRecorder.NpcIdFromGuid(targetGuid)
    if targetNpcId and UnitIsDead("target") then
        ProfileRecorder.RecordMobKill(targetGuid, targetNpcId, timestamp)
    end
end

function ProfileRecorder.RecordCombatLogKill()
    if not CombatLogGetCurrentEventInfo then
        return
    end
    local timestamp, subevent, _, sourceGuid, _, sourceFlags, _, destGuid = CombatLogGetCurrentEventInfo()
    local npcId = ProfileRecorder.NpcIdFromGuid(destGuid)
    if not npcId then
        return
    end

    timestamp = GetTime and GetTime() or tonumber(timestamp) or 0
    ProfileRecorder.PruneCombatState(timestamp)
    local mineFlag = COMBATLOG_OBJECT_AFFILIATION_MINE or 1
    local isMine = sourceGuid == UnitGUID("player") or DreamwayBitBand(tonumber(sourceFlags) or 0, mineFlag) ~= 0

    local isDamage = subevent == "SWING_DAMAGE"
        or subevent == "RANGE_DAMAGE"
        or subevent == "RANGE_DRAIN"
        or subevent == "RANGE_INSTAKILL"
        or subevent == "RANGE_LEECH"
        or subevent == "SPELL_DAMAGE"
        or subevent == "SPELL_DRAIN"
        or subevent == "SPELL_INSTAKILL"
        or subevent == "SPELL_LEECH"
        or subevent == "SPELL_PERIODIC_DAMAGE"
        or subevent == "SPELL_PERIODIC_DRAIN"
        or subevent == "SPELL_PERIODIC_INSTAKILL"
        or subevent == "SPELL_PERIODIC_LEECH"
        or subevent == "SPELL_BUILDING_DAMAGE"
        or subevent == "SPELL_BUILDING_DRAIN"
        or subevent == "SPELL_BUILDING_INSTAKILL"
        or subevent == "SPELL_BUILDING_LEECH"
        or subevent == "DAMAGE_SHIELD"
    if isMine and isDamage then
        ProfileRecorder.damagedNpcGuids[destGuid] = timestamp
    end

    if subevent == "PARTY_KILL" then
        ProfileRecorder.RecordMobKill(destGuid, npcId, timestamp)
        return
    end

    local isDeath = subevent == "UNIT_DIED"
        or subevent == "UNIT_DESTROYED"
        or subevent == "UNIT_DISSIPATES"
    if isDeath then
        ProfileRecorder.recentNpcDeaths[#ProfileRecorder.recentNpcDeaths + 1] = {
            guid = destGuid,
            npcId = npcId,
            seenAt = timestamp,
        }
        if ProfileRecorder.damagedNpcGuids[destGuid] then
            ProfileRecorder.RecordMobKill(destGuid, npcId, timestamp)
        end
    end
end

local function InsertQuestChatLink(quest)
    local questId = tonumber(quest and quest.id)
    if not questId or not IsModifiedClick or not IsModifiedClick("CHATLINK") or not ChatEdit_GetActiveWindow or not ChatEdit_GetActiveWindow() then
        return false
    end

    local QuestieLink = ImportQuestieModule("QuestieLink")
    if QuestieLink and QuestieLink.GetQuestLinkStringById and ChatEdit_InsertLink then
        local ok, link = pcall(QuestieLink.GetQuestLinkStringById, QuestieLink, questId)
        if ok and link then
            ChatEdit_InsertLink(link)
            return true
        end
    end

    if ChatEdit_InsertLink then
        ChatEdit_InsertLink("[" .. QuestDisplayName(quest) .. " (" .. tostring(questId) .. ")]")
        return true
    end

    return false
end

local function OpenQuestieDetails(quest)
    local questId = tonumber(quest and quest.id)
    if not questId then
        return false
    end

    local QuestieLink = ImportQuestieModule("QuestieLink")
    if QuestieLink and QuestieLink.GetQuestHyperLink and ItemRefTooltip and ItemRefTooltip.SetHyperlink then
        local ok, link = pcall(QuestieLink.GetQuestHyperLink, QuestieLink, questId)
        if ok and link then
            local tooltipOk = pcall(ItemRefTooltip.SetHyperlink, ItemRefTooltip, link)
            if tooltipOk then
                return true
            end
        end
    end

    if ItemRefTooltip and ItemRefTooltip.SetHyperlink then
        local fallbackLink = "|Hquestie:" .. tostring(questId) .. ":" .. (UnitGUID and UnitGUID("player") or "") .. "|h" .. QuestDisplayName(quest) .. "|h"
        local tooltipOk = pcall(ItemRefTooltip.SetHyperlink, ItemRefTooltip, fallbackLink)
        if tooltipOk then
            return true
        end
    end

    return false
end

local function OpenQuestLogFallback(questId)
    local questLogIndex
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questId)
        if ok and index and index > 0 then
            questLogIndex = index
        end
    end

    if not questLogIndex and GetQuestLogIndexByID then
        local ok, index = pcall(GetQuestLogIndexByID, questId)
        if ok and index and index > 0 then
            questLogIndex = index
        end
    end

    if not questLogIndex then
        return false
    end

    if SelectQuestLogEntry then
        SelectQuestLogEntry(questLogIndex)
    end

    local questLogFrame = QuestLogExFrame or ClassicQuestLog or QuestLogFrame
    if questLogFrame and questLogFrame.IsShown and not questLogFrame:IsShown() and ShowUIPanel and (not InCombatLockdown or not InCombatLockdown()) then
        ShowUIPanel(questLogFrame)
    end

    if QuestLog_UpdateQuestDetails then
        QuestLog_UpdateQuestDetails()
    end
    if QuestLog_Update then
        QuestLog_Update()
    end

    return true
end

local function OpenQuestFromRow(quest)
    if InsertQuestChatLink(quest) then
        return
    end

    local questId = tonumber(quest and quest.id)
    if questId and IsQuestInLog(questId) then
        local trackerUtils = ImportQuestieModule("TrackerUtils")
        local dbQuest = GetQuestieQuest(quest)
        if trackerUtils and trackerUtils.ShowQuestLog and dbQuest then
            local ok = pcall(trackerUtils.ShowQuestLog, trackerUtils, dbQuest)
            if ok then
                return
            end
        end

        if OpenQuestLogFallback(questId) then
            return
        end
    end

    OpenQuestieDetails(quest)
end

local function ShowQuestieTrackerMenu(quest)
    local trackerMenu = ImportQuestieModule("TrackerMenu")
    local dropDown = GetQuestieDropDown()
    local dbQuest = GetQuestieQuest(quest)

    if not trackerMenu or not trackerMenu.GetMenuForQuest or not trackerMenu.menuFrame or not dropDown or not dropDown.EasyMenu or not dbQuest then
        return false
    end

    if trackerMenu.menuFrame.IsShown and trackerMenu.menuFrame:IsShown() and dropDown.CloseDropDownMenus then
        pcall(dropDown.CloseDropDownMenus, dropDown)
    end

    local ok, menu = pcall(trackerMenu.GetMenuForQuest, trackerMenu, dbQuest)
    if not ok or not menu then
        return false
    end

    local shown = pcall(dropDown.EasyMenu, dropDown, menu, trackerMenu.menuFrame, "cursor", 0, 0, "MENU")
    return shown
end

local function GroupBatchQuests(journey, batch, currentIndex)
    local grouped = {
        prereq = {},
        pickup = {},
        progress = {},
        turnin = {},
    }

    for _, quest in ipairs(batch.quests or {}) do
        local category = ClassifyQuest(quest)
        if category and grouped[category] then
            table.insert(grouped[category], quest)
        end
    end

    if ProfileRecorder.showPreviousBatchQuests and journey and currentIndex and currentIndex > 1 then
        local seen = {}
        for _, quest in ipairs(batch.quests or {}) do
            if quest.id then seen[tonumber(quest.id)] = true end
        end
        for index = 1, currentIndex - 1 do
            for _, quest in ipairs(journey.batches[index].quests or {}) do
                local questId = tonumber(quest.id)
                if questId and not seen[questId]
                    and IsQuestInLog(questId)
                    and not IsQuestCompleteInLog(questId)
                    and not IsQuestTurnedIn(questId)
                    and panelSearchFilters.PassesLevel(quest)
                then
                    grouped.progress[#grouped.progress + 1] = quest
                    seen[questId] = true
                end
            end
        end
    end

    return grouped
end

local function CreateLabel(parent, template)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    return label
end

local function CreateTextButton(parent, template)
    local button = CreateFrame("Button", nil, parent)
    button:EnableMouse(false)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    button.label = CreateLabel(button, template or "GameFontHighlightSmall")
    button.label:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.label:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    button.label:SetWordWrap(true)

    return button
end

local function ConfigurePanelTooltip(frame, title, body)
    if not frame then
        return
    end

    frame.tooltipTitle = title
    frame.tooltipBody = body
    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end

        AnchorDreamwayTooltip(self)
        if self.tooltipTitle and self.tooltipTitle ~= "" then
            GameTooltip:AddLine(self.tooltipTitle, 1, 0.82, 0.12)
        end
        if self.tooltipBody and self.tooltipBody ~= "" then
            GameTooltip:AddLine(self.tooltipBody, 0.72, 0.72, 0.72, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end

local function NextTrackerLine()
    dreamwayFrame.lineIndex = dreamwayFrame.lineIndex + 1
    local line = dreamwayFrame.lines[dreamwayFrame.lineIndex]
    if not line then
        line = CreateTextButton(dreamwayFrame)
        dreamwayFrame.lines[dreamwayFrame.lineIndex] = line
    end
    line:ClearAllPoints()
    line:SetScript("OnClick", nil)
    line:SetScript("OnEnter", nil)
    line:SetScript("OnLeave", nil)
    line:EnableMouse(false)
    line.quest = nil
    line.prerequisiteWarning = nil
    line.label:SetText("")
    line.label:SetTextColor(0.92, 0.92, 0.92)
    line.label:Show()
    line:Show()
    return line
end

local function HideUnusedTrackerLines()
    for index = dreamwayFrame.lineIndex + 1, #dreamwayFrame.lines do
        dreamwayFrame.lines[index]:Hide()
        dreamwayFrame.lines[index].label:SetText("")
    end
end

local function SetButtonText(button, width, text)
    button:SetWidth(width)
    button.label:SetWidth(width)
    button.label:SetText(text)

    local height = math.max(button.label:GetStringHeight() or 0, button.label:GetHeight() or 0, 12)
    button:SetHeight(height)
    return height
end

local function ConfigureQuestButton(button, quest, tooltipOwner, openQuestieOnly)
    button.quest = quest
    button:EnableMouse(true)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ShowQuestieTrackerMenu(quest)
            return
        end

        if openQuestieOnly then
            if not InsertQuestChatLink(quest) then
                OpenQuestieDetails(quest)
            end
        else
            OpenQuestFromRow(quest)
        end
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end

        AnchorDreamwayTooltip(self)
        GameTooltip:AddLine(quest.name or QuestDisplayName(quest), 1, 0.82, 0.12)
        if self.prerequisiteWarning then
            GameTooltip:AddLine("Prerequisite warning", 1, 0.55, 0.16)
            GameTooltip:AddLine(self.prerequisiteWarning, 0.95, 0.78, 0.48, true)
        end
        if openQuestieOnly then
            GameTooltip:AddLine("Click to open Questie quest details.", 0.75, 0.75, 0.75)
        elseif IsQuestInLog(quest.id) then
            GameTooltip:AddLine("Click to open this quest in your quest log.", 0.75, 0.75, 0.75)
        else
            GameTooltip:AddLine("Click to open Questie quest details.", 0.75, 0.75, 0.75)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end

function DreamwayUsableTrackerItems(quest)
    ProfileRecorder.trackerItemCandidates = ProfileRecorder.trackerItemCandidates or {}
    local questId = tonumber(quest and quest.id)
    local candidates = questId and ProfileRecorder.trackerItemCandidates[questId]
    if not candidates then
        candidates = {}
        local seen = {}
        local dbQuest = GetQuestieQuest(quest)
        local questieDb = ImportQuestieModule("QuestieDB")
        local function addCandidate(itemId)
            itemId = tonumber(itemId)
            if not itemId or seen[itemId] then return end
            seen[itemId] = true
            candidates[#candidates + 1] = itemId
        end
        if questieDb and questieDb.QueryQuestSingle and questId then
            local ok, sourceItemId = pcall(questieDb.QueryQuestSingle, questId, "sourceItemId")
            if ok then addCandidate(sourceItemId) end
        end
        for _, itemId in pairs(dbQuest and dbQuest.requiredSourceItems or {}) do addCandidate(itemId) end
        for _, objective in pairs(dbQuest and dbQuest.ObjectiveData or {}) do
            if objective.Type == "item" then addCandidate(objective.Id) end
        end
        if questId then
            ProfileRecorder.trackerItemCandidates[questId] = candidates
        end
    end

    local items = {}
    local trackerUtils = ImportQuestieModule("TrackerUtils")
    local getItemCount = C_Item and C_Item.GetItemCount or GetItemCount
    for _, itemId in ipairs(candidates) do
        if getItemCount and getItemCount(itemId) > 0 then
            local usable = true
            if trackerUtils and trackerUtils.IsQuestItemUsable then
                local ok, result = pcall(trackerUtils.IsQuestItemUsable, trackerUtils, itemId)
                usable = ok and result == true
            end
            if usable then
                items[#items + 1] = itemId
            end
        end
    end
    return items
end

function DreamwayConfigureTrackerItemButton(button, itemId, questId, size)
    if not button or not itemId then
        return false
    end

    ProfileRecorder.trackerItemTextures = ProfileRecorder.trackerItemTextures or {}
    local texture = ProfileRecorder.trackerItemTextures[itemId]
    if texture == nil then
        if C_Item and C_Item.GetItemIconByID then
            texture = C_Item.GetItemIconByID(itemId)
        end
        if not texture and GetItemIcon then
            texture = GetItemIcon(itemId)
        end
        if not texture and GetItemInfo then
            texture = select(10, GetItemInfo(itemId))
        end
        if texture then
            ProfileRecorder.trackerItemTextures[itemId] = texture
        end
    end

    if not texture then
        return false
    end

    if button.FakeHide then button:FakeHide() end
    button.itemId = itemId
    button.questID = questId
    local getItemCount = C_Item and C_Item.GetItemCount or GetItemCount
    button.charges = getItemCount and getItemCount(itemId, nil, true) or 0
    button.rangeTimer = -1
    button:SetNormalTexture(texture)
    button:SetPushedTexture(texture)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    button:SetSize(size, size)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetScript("OnEvent", button.OnEvent)
    button:SetScript("OnShow", button.OnShow)
    button:SetScript("OnHide", button.OnHide)
    button:SetScript("OnEnter", function(self)
        if self.OnEnter then
            self:OnEnter()
            AnchorDreamwayTooltip(self)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", button.OnLeave)
    button:SetAttribute("type1", "item")
    button:SetAttribute("item1", "item:" .. tostring(itemId))
    if button.range then
        button.range:SetText("\226\151\143")
        button.range:SetPoint("TOPRIGHT", button, "TOPRIGHT", 3, 0)
        button.range:Hide()
    end
    if button.count then
        button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 3)
        button.count:SetText(button.charges or 0)
        button.count:SetShown((button.charges or 0) > 1)
    end
    button:Show()
    return true
end

function DreamwayResetTrackerItemButtons()
    if not dreamwayFrame or not dreamwayFrame.itemButtons then return end
    for _, button in ipairs(dreamwayFrame.itemButtons) do
        if button.FakeHide then button:FakeHide() end
        button:ClearAllPoints()
        button:Hide()
    end
    dreamwayFrame.itemButtonIndex = 0
end

local function AddTrackerObjectiveLine(objective, y, width)
    local line = NextTrackerLine()
    ApplyTrackerFont(line.label, "trackerFontObjective", "trackerFontSizeObjective")
    line:SetPoint("TOPLEFT", dreamwayFrame, "TOPLEFT", 28, y)
    local objectiveText = objective.text
    local collected = tonumber(objective.collected)
    local needed = tonumber(objective.needed)
    if (not collected or not needed or needed <= 0) and objective.finished then
        collected = 1
        needed = 1
    end

    local QuestieLib = ImportQuestieModule("QuestieLib")
    if QuestieLib and QuestieLib.GetRGBForObjective and collected and needed and needed > 0 then
        local ok, colorPrefix = pcall(QuestieLib.GetRGBForObjective, QuestieLib, {
            Collected = collected,
            Needed = needed,
        })
        if ok and colorPrefix then
            objectiveText = colorPrefix .. objectiveText .. "|r"
        end
    end

    local lineHeight = SetButtonText(line, width - 44, objectiveText)
    if objectiveText == objective.text then
        if objective.finished then
            line.label:SetTextColor(0.35, 0.9, 0.35)
        else
            line.label:SetTextColor(0.78, 0.78, 0.78)
        end
    else
        line.label:SetTextColor(1, 1, 1)
    end
    return y - lineHeight - 1
end

local function AddTrackerSection(section, quests, y, width)
    if not quests or #quests == 0 then
        return y
    end

    local title = NextTrackerLine()
    ApplyTrackerFont(title.label, "trackerFontZone", "trackerFontSizeZone")
    title:SetPoint("TOPLEFT", dreamwayFrame, "TOPLEFT", 12, y)
    local titleHeight = SetButtonText(title, width - 24, section.label)
    title.label:SetTextColor(0.74, 0.74, 0.74)
    y = y - titleHeight - 2

    local style = TrackerStyle()
    for _, quest in ipairs(quests) do
        local itemOffset = 0
        local itemSize = 12 + (tonumber(TrackerProfile().trackerFontSizeQuest) or 10)
        if section.key == "progress" then
            for itemIndex, itemId in ipairs(DreamwayUsableTrackerItems(quest)) do
                if itemIndex > 2 then break end
                dreamwayFrame.itemButtonIndex = dreamwayFrame.itemButtonIndex + 1
                local itemButton = dreamwayFrame.itemButtons and dreamwayFrame.itemButtons[dreamwayFrame.itemButtonIndex]
                if itemButton then
                    itemButton:ClearAllPoints()
                    itemButton:SetParent(dreamwayFrame)
                    itemButton:SetPoint("TOPLEFT", dreamwayFrame, "TOPLEFT", 18 + itemOffset, y)
                    itemButton:SetAlpha(Questie and Questie.db and Questie.db.profile and Questie.db.profile.trackerFadeQuestItemButtons and 0 or 1)
                    if DreamwayConfigureTrackerItemButton(itemButton, itemId, quest.id, itemSize) then
                        itemOffset = itemOffset + itemSize + 2
                    end
                end
            end
        end
        local line = NextTrackerLine()
        ApplyTrackerFont(line.label, "trackerFontQuest", "trackerFontSizeQuest")
        line:SetPoint("TOPLEFT", dreamwayFrame, "TOPLEFT", 18 + itemOffset, y)
        local questText = ColoredQuestDisplayName(quest, section.key ~= "turnin")
        if section.key == "turnin" then
            questText = questText .. " |cff20ff20(Complete)|r"
        end
        local lineHeight = math.max(SetButtonText(line, width - 32 - itemOffset, questText), itemOffset > 0 and itemSize or 0)
        line.label:SetTextColor(1, 1, 1)
        ConfigureQuestButton(line, quest)
        y = y - lineHeight - 1

        if section.key == "progress" then
            for _, objective in ipairs(GetQuestObjectiveLines(quest)) do
                y = AddTrackerObjectiveLine(objective, y, width)
            end
        end
        y = y - math.max(0, style.questPadding - 1)
    end

    return y - 6
end

local function CreateTinyButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    button:SetSize(width, 18)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    SetFrameBackdrop(button, 0.05, 0.05, 0.05, 0.88, 0.45)

    button.label = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.label:SetText(text)

    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.82, 0.12, 0.9)
    end)
    button:SetScript("OnLeave", function(self)
        if self.active then
            self:SetBackdropBorderColor(1, 0.82, 0.12, 0.95)
        else
            self:SetBackdropBorderColor(1, 1, 1, 0.35)
        end
    end)

    button.SetActive = function(self, active)
        self.active = active
        if active then
            self:SetBackdropColor(0.28, 0.02, 0.02, 0.92)
            self:SetBackdropBorderColor(1, 0.82, 0.12, 0.95)
            self.label:SetTextColor(1, 0.82, 0.12)
        else
            self:SetBackdropColor(0.05, 0.05, 0.05, 0.88)
            self:SetBackdropBorderColor(1, 1, 1, 0.35)
            self.label:SetTextColor(0.75, 0.75, 0.75)
        end
    end

    return button
end

local function CreateToggleSegment(parent, text, side)
    local button = CreateFrame("Button", nil, parent)
    button.side = side
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")

    button.backgroundBody = button:CreateTexture(nil, "BACKGROUND")
    if side == "left" then
        button.backgroundBody:SetPoint("TOPLEFT", button, "TOPLEFT", 9, 0)
        button.backgroundBody:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    else
        button.backgroundBody:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        button.backgroundBody:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -9, 0)
    end

    if button.CreateMaskTexture then
        button.backgroundCap = button:CreateTexture(nil, "BACKGROUND")
        button.backgroundCap:SetSize(18, 18)
        button.backgroundCap:SetPoint(side == "left" and "LEFT" or "RIGHT", button, side == "left" and "LEFT" or "RIGHT", 0, 0)
        button.backgroundCapMask = button:CreateMaskTexture()
        button.backgroundCapMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        button.backgroundCapMask:SetAllPoints(button.backgroundCap)
        button.backgroundCap:AddMaskTexture(button.backgroundCapMask)
    else
        button.backgroundBody:SetAllPoints(button)
    end

    button.label = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.label:SetText(text)

    button:SetScript("OnEnter", function(self)
        if not self.active then
            self:SetFillColor(0.13, 0.13, 0.13, 0.98)
            self.label:SetTextColor(0.95, 0.95, 0.95)
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetActive(self.active)
    end)

    button.SetFillColor = function(self, red, green, blue, alpha)
        self.backgroundBody:SetColorTexture(red, green, blue, alpha)
        if self.backgroundCap then
            self.backgroundCap:SetColorTexture(red, green, blue, alpha)
        end
    end

    button.SetActive = function(self, active)
        self.active = active == true
        if self.active then
            self:SetFillColor(0.28, 0.025, 0.02, 0.96)
            self.label:SetTextColor(1, 0.82, 0.12)
        else
            self:SetFillColor(0.035, 0.035, 0.035, 0.94)
            self.label:SetTextColor(0.72, 0.72, 0.72)
        end
    end

    button:SetActive(false)
    return button
end

local function SetClippedTrackerTitle(fontString, fullText, maxWidth)
    fullText = tostring(fullText or "")
    fontString:SetText(fullText)
    if (fontString:GetStringWidth() or 0) <= maxWidth then
        return
    end

    local suffix = "..."
    local low = 0
    local high = #fullText
    while low < high do
        local middle = math.ceil((low + high) / 2)
        fontString:SetText(fullText:sub(1, middle) .. suffix)
        if (fontString:GetStringWidth() or 0) <= maxWidth then
            low = middle
        else
            high = middle - 1
        end
    end
    fontString:SetText(fullText:sub(1, low) .. suffix)
end

local function UpdateToggleButtons()
    if not questieButton or not dreamwayButton then
        return
    end

    questieButton:SetActive(mode == MODE_QUESTIE)
    dreamwayButton:SetActive(mode == MODE_DREAMWAY)
    if toggleFrame and toggleFrame.batchMeta then
        toggleFrame.batchMeta:SetShown(mode == MODE_DREAMWAY)
    end
end

local function ResizeTrackerToggle(height)
    if not toggleFrame then
        return
    end

    height = math.max(20, math.floor((tonumber(height) or 20) + 0.5))
    local radius = height / 2
    local innerSize = height - 2
    local innerRadius = innerSize / 2
    toggleFrame:SetHeight(height)

    toggleFrame.borderBody:ClearAllPoints()
    toggleFrame.borderBody:SetPoint("TOPLEFT", toggleFrame, "TOPLEFT", radius, 0)
    toggleFrame.borderBody:SetPoint("BOTTOMRIGHT", toggleFrame, "BOTTOMRIGHT", -radius, 0)
    toggleFrame.backgroundBody:ClearAllPoints()
    toggleFrame.backgroundBody:SetPoint("TOPLEFT", toggleFrame, "TOPLEFT", innerRadius + 1, -1)
    toggleFrame.backgroundBody:SetPoint("BOTTOMRIGHT", toggleFrame, "BOTTOMRIGHT", -innerRadius - 1, 1)

    for _, texture in ipairs({ toggleFrame.leftBorder, toggleFrame.rightBorder }) do
        if texture then
            texture:SetSize(height, height)
        end
    end
    for _, texture in ipairs({ toggleFrame.leftBackground, toggleFrame.rightBackground }) do
        if texture then
            texture:SetSize(innerSize, innerSize)
        end
    end

    for _, button in ipairs({ questieButton, dreamwayButton }) do
        if button then
            button.backgroundBody:ClearAllPoints()
            if button.side == "left" then
                button.backgroundBody:SetPoint("TOPLEFT", button, "TOPLEFT", innerRadius, 0)
                button.backgroundBody:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
            else
                button.backgroundBody:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
                button.backgroundBody:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -innerRadius, 0)
            end
            if button.backgroundCap then
                button.backgroundCap:SetSize(innerSize, innerSize)
            end
        end
    end
end

local function HideQuestieTrackerContent()
    if headerFrame then
        headerFrame:Hide()
        if headerFrame.questieIcon then
            headerFrame.questieIcon:Hide()
        end
        if headerFrame.trackedQuests then
            headerFrame.trackedQuests:Hide()
        end
    end

    if questFrame then
        questFrame:Hide()
        if questFrame.ScrollFrame then
            questFrame.ScrollFrame:Hide()
        end
        if questFrame.ScrollChildFrame then
            questFrame.ScrollChildFrame:Hide()
        end
    end
end

local function ShowQuestieTrackerContent()
    if questFrame and questFrame.ScrollFrame then
        questFrame.ScrollFrame:Show()
    end
    if questFrame and questFrame.ScrollChildFrame then
        questFrame.ScrollChildFrame:Show()
    end

    local tracker = GetQuestieTracker()
    if tracker and tracker.Update then
        tracker:Update()
    else
        if headerFrame then
            headerFrame:Show()
        end
        if questFrame then
            questFrame:Show()
        end
    end
end

local function TogglePanel()
    if not panelFrame then
        return
    end

    if panelFrame:IsShown() then
        panelFrame:Hide()
    else
        panelFrame:Show()
        if panelImportArea then
            panelImportArea:Hide()
        end
        if panelExportArea then
            panelExportArea:Hide()
        end
        if panelJourneyManager.frame then
            panelJourneyManager.frame:Hide()
        end
        if RefreshPanel then
            RefreshPanel()
        end
    end
end

local function RefreshDreamwayTracker()
    if not dreamwayFrame then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        pendingApply = true
        return
    end

    local journey, batch, count = CurrentBatch()
    local grouped = GroupBatchQuests(journey, batch, batchIndex)
    local profile = TrackerProfile()
    local style = TrackerStyle()
    local minimumWidth = 184
    local maximumWidth = math.max(minimumWidth, math.min(380, GetScreenWidth() * style.widthRatio))
    local requestedWidth = style.manualWidth > 0 and style.manualWidth or (baseFrame and baseFrame:GetWidth() or minimumWidth)
    local width = math.min(math.max(requestedWidth, minimumWidth), maximumWidth)
    dreamwayFrame:SetWidth(width)
    dreamwayFrame.lineIndex = 0
    DreamwayResetTrackerItemButtons()
    ResizeTrackerToggle(math.max(style.headerSize, style.zoneSize) + 8)

    dreamwayFrame.leftArrow:SetShown(count > 1)
    dreamwayFrame.rightArrow:SetShown(count > 1)
    local batchName = batch and batch.name or "No batch"

    local y = -1
    local headerSize = style.headerSize
    ApplyTrackerFont(dreamwayFrame.batchButton.text, "trackerFontHeader", "trackerFontSizeHeader")
    dreamwayFrame.batchButton.text:SetTextColor(0.35, 0.85, 1)
    dreamwayFrame.batchButton.text:SetWordWrap(false)

    local navigatorMargin = 12
    local navigatorWidth = width - (navigatorMargin * 2)
    local arrowWidth = headerSize + 16
    local arrowHeight = headerSize + 10
    local titleWidth = math.max(72, navigatorWidth - (arrowWidth * 2) - 4)

    dreamwayFrame.leftArrow:SetSize(arrowWidth, arrowHeight)
    dreamwayFrame.rightArrow:SetSize(arrowWidth, arrowHeight)
    dreamwayFrame.leftArrow:ClearAllPoints()
    dreamwayFrame.rightArrow:ClearAllPoints()
    dreamwayFrame.leftArrow:SetPoint("TOPLEFT", dreamwayFrame, "TOPLEFT", navigatorMargin, y)
    dreamwayFrame.rightArrow:SetPoint("TOPRIGHT", dreamwayFrame, "TOPRIGHT", -navigatorMargin, y)

    dreamwayFrame.batchButton:ClearAllPoints()
    dreamwayFrame.batchButton:SetPoint("TOPLEFT", dreamwayFrame, "TOPLEFT", navigatorMargin + arrowWidth + 2, y)
    dreamwayFrame.batchButton:SetSize(titleWidth, arrowHeight)
    dreamwayFrame.batchButton.text:SetWidth(titleWidth)
    SetClippedTrackerTitle(dreamwayFrame.batchButton.text, batchName, titleWidth - 4)
    dreamwayFrame.batchButton.fullTitle = batchName

    ApplyTrackerFont(toggleFrame.batchMeta, "trackerFontZone", "trackerFontSizeZone")
    local expectedLevel = BatchExpectedLevel(batch)
    local metaText = tostring(batchIndex) .. "/" .. tostring(count)
    if expectedLevel then
        metaText = metaText .. "  |  Lv " .. tostring(expectedLevel)
    end
    toggleFrame.batchMeta:SetText(metaText)
    toggleFrame.batchMeta:SetTextColor(0.72, 0.72, 0.72)
    toggleFrame.batchMeta:SetWidth(math.max(80, width - toggleFrame:GetWidth() - 8))

    y = y - headerSize - 15

    local anySection = false
    for _, section in ipairs(SECTION_ORDER) do
        if grouped[section.key] and #grouped[section.key] > 0 then
            anySection = true
            y = AddTrackerSection(section, grouped[section.key], y, width)
        end
    end

    if not anySection then
        local line = NextTrackerLine()
        ApplyTrackerFont(line.label, "trackerFontQuest", "trackerFontSizeQuest")
        line:SetPoint("TOPLEFT", dreamwayFrame, "TOPLEFT", 14, y)
        local text
        if journey == fallbackJourney then
            text = "Click the batch title to import a Journey."
        else
            text = "No open tasks in this batch."
        end
        local lineHeight = SetButtonText(line, width - 44, text)
        line.label:SetTextColor(0.92, 0.92, 0.92)
        y = y - lineHeight - 6
    end

    HideUnusedTrackerLines()

    local contentHeight = math.max(60, math.abs(y) + 12)
    local configuredHeight = style.manualHeight > 0
        and style.manualHeight
        or (GetScreenHeight() * style.heightRatio)
    local height = math.min(contentHeight, math.max(60, configuredHeight - 12))
    dreamwayFrame:SetHeight(height)
    if baseFrame then
        baseFrame:SetWidth(width)
        baseFrame:SetHeight(height + 12)
    end
end

local function SetMode(newMode)
    mode = newMode == MODE_DREAMWAY and MODE_DREAMWAY or MODE_QUESTIE
    pendingApply = true
    SaveDb()
end

local function ApplyMode()
    pendingApply = false

    if not initialized or InCombatLockdown() then
        pendingApply = true
        return
    end

    UpdateToggleButtons()
    ApplyUnusedQuestSuppression()

    if mode == MODE_DREAMWAY then
        if baseFrame then
            baseFrame:Show()
        end
        HideQuestieTrackerContent()
        if dreamwayFrame then
            dreamwayFrame:Show()
            RefreshDreamwayTracker()
        end
    else
        if dreamwayFrame then
            dreamwayFrame:Hide()
        end
        ShowQuestieTrackerContent()
    end
end

function DreamwayScheduleUiRefresh(refreshPanel)
    if not initialized or mode ~= MODE_DREAMWAY then
        return
    end

    ProfileRecorder.dreamwayUiRefreshPanel = ProfileRecorder.dreamwayUiRefreshPanel or refreshPanel == true
    if ProfileRecorder.dreamwayUiRefreshPending then
        return
    end

    ProfileRecorder.dreamwayUiRefreshPending = true
    C_Timer.After(0.05, function()
        ProfileRecorder.dreamwayUiRefreshPending = false
        local shouldRefreshPanel = ProfileRecorder.dreamwayUiRefreshPanel
        ProfileRecorder.dreamwayUiRefreshPanel = false

        if not initialized or mode ~= MODE_DREAMWAY then
            return
        end
        if InCombatLockdown() then
            pendingApply = true
            return
        end

        ApplyUnusedQuestSuppression()
        HideQuestieTrackerContent()
        RefreshDreamwayTracker()
        if shouldRefreshPanel and panelFrame and panelFrame:IsShown() and RefreshPanel then
            RefreshPanel()
        end
    end)
end

local function PreviousBatch()
    local journey = ActiveJourney()
    if not journey or not journey.batches or #journey.batches == 0 then
        return
    end

    batchIndex = batchIndex - 1
    if batchIndex < 1 then
        batchIndex = #journey.batches
    end
    SaveDb()
    RefreshDreamwayTracker()
    if panelFrame and panelFrame:IsShown() and RefreshPanelBatchSelection then
        RefreshPanelBatchSelection()
    end
end

local function NextBatch()
    local journey = ActiveJourney()
    if not journey or not journey.batches or #journey.batches == 0 then
        return
    end

    batchIndex = batchIndex + 1
    if batchIndex > #journey.batches then
        batchIndex = 1
    end
    SaveDb()
    RefreshDreamwayTracker()
    if panelFrame and panelFrame:IsShown() and RefreshPanelBatchSelection then
        RefreshPanelBatchSelection()
    end
end

local function CreateToggle()
    toggleFrame = CreateFrame("Frame", "Dreamway_Toggle", baseFrame, BackdropTemplateMixin and "BackdropTemplate")
    toggleFrame:SetSize(138, 20)
    toggleFrame:SetPoint("BOTTOMLEFT", baseFrame, "TOPLEFT", 0, 2)
    toggleFrame:SetFrameLevel((baseFrame:GetFrameLevel() or 0) + 80)

    toggleFrame.borderBody = toggleFrame:CreateTexture(nil, "BACKGROUND", nil, -2)
    toggleFrame.borderBody:SetPoint("TOPLEFT", toggleFrame, "TOPLEFT", 10, 0)
    toggleFrame.borderBody:SetPoint("BOTTOMRIGHT", toggleFrame, "BOTTOMRIGHT", -10, 0)
    toggleFrame.borderBody:SetColorTexture(0.5, 0.5, 0.5, 0.82)
    toggleFrame.backgroundBody = toggleFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
    toggleFrame.backgroundBody:SetPoint("TOPLEFT", toggleFrame, "TOPLEFT", 10, -1)
    toggleFrame.backgroundBody:SetPoint("BOTTOMRIGHT", toggleFrame, "BOTTOMRIGHT", -10, 1)
    toggleFrame.backgroundBody:SetColorTexture(0.025, 0.025, 0.025, 0.98)

    if toggleFrame.CreateMaskTexture then
        local function CreateRoundEnd(size, point, xOffset, colorRed, colorGreen, colorBlue, colorAlpha, subLevel)
            local texture = toggleFrame:CreateTexture(nil, "BACKGROUND", nil, subLevel)
            texture:SetSize(size, size)
            texture:SetPoint(point, toggleFrame, point, xOffset, 0)
            texture:SetColorTexture(colorRed, colorGreen, colorBlue, colorAlpha)
            local mask = toggleFrame:CreateMaskTexture()
            mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            mask:SetAllPoints(texture)
            texture:AddMaskTexture(mask)
            return texture, mask
        end

        toggleFrame.leftBorder, toggleFrame.leftBorderMask = CreateRoundEnd(20, "LEFT", 0, 0.5, 0.5, 0.5, 0.82, -2)
        toggleFrame.rightBorder, toggleFrame.rightBorderMask = CreateRoundEnd(20, "RIGHT", 0, 0.5, 0.5, 0.5, 0.82, -2)
        toggleFrame.leftBackground, toggleFrame.leftBackgroundMask = CreateRoundEnd(18, "LEFT", 1, 0.025, 0.025, 0.025, 0.98, -1)
        toggleFrame.rightBackground, toggleFrame.rightBackgroundMask = CreateRoundEnd(18, "RIGHT", -1, 0.025, 0.025, 0.025, 0.98, -1)
    else
        SetFrameBackdrop(toggleFrame, 0.025, 0.025, 0.025, 0.96, 0.55)
    end

    questieButton = CreateToggleSegment(toggleFrame, "Questie", "left")
    questieButton:SetPoint("TOPLEFT", toggleFrame, "TOPLEFT", 1, -1)
    questieButton:SetPoint("BOTTOMRIGHT", toggleFrame, "BOTTOM", 0, 1)
    questieButton:SetScript("OnClick", function()
        SetMode(MODE_QUESTIE)
        ApplyMode()
    end)

    dreamwayButton = CreateToggleSegment(toggleFrame, "Dreamway", "right")
    dreamwayButton:SetPoint("TOPLEFT", toggleFrame, "TOP", 0, -1)
    dreamwayButton:SetPoint("BOTTOMRIGHT", toggleFrame, "BOTTOMRIGHT", -1, 1)
    dreamwayButton:SetScript("OnClick", function()
        SetMode(MODE_DREAMWAY)
        ApplyMode()
    end)

    toggleFrame.divider = toggleFrame:CreateTexture(nil, "ARTWORK")
    toggleFrame.divider:SetColorTexture(0.45, 0.45, 0.45, 0.75)
    toggleFrame.divider:SetPoint("TOP", toggleFrame, "TOP", 0, -2)
    toggleFrame.divider:SetPoint("BOTTOM", toggleFrame, "BOTTOM", 0, 2)
    toggleFrame.divider:SetWidth(1)

    toggleFrame.batchMeta = toggleFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    toggleFrame.batchMeta:SetPoint("LEFT", toggleFrame, "RIGHT", 8, 0)
    toggleFrame.batchMeta:SetJustifyH("CENTER")
    toggleFrame.batchMeta:SetWordWrap(false)
    toggleFrame.batchMeta:Hide()
end

local function CreateDreamwayTracker()
    dreamwayFrame = CreateFrame("Frame", "Dreamway_TrackerFrame", baseFrame)
    dreamwayFrame:SetPoint("TOPLEFT", baseFrame, "TOPLEFT", 0, -4)
    dreamwayFrame:SetFrameLevel((baseFrame:GetFrameLevel() or 0) + 60)
    if dreamwayFrame.SetClipsChildren then
        dreamwayFrame:SetClipsChildren(true)
    end
    dreamwayFrame.lines = {}
    dreamwayFrame.lineIndex = 0
    dreamwayFrame.itemButtons = {}
    dreamwayFrame.itemButtonIndex = 0
    local trackerItemButton = ImportQuestieModule("TrackerItemButton")
    if trackerItemButton and trackerItemButton.New then
        for index = 1, 16 do
            dreamwayFrame.itemButtons[index] = trackerItemButton.New("Dreamway_TrackerItemButton" .. tostring(index))
            if dreamwayFrame.itemButtons[index] and dreamwayFrame.itemButtons[index].SetParent then
                dreamwayFrame.itemButtons[index]:SetParent(dreamwayFrame)
            end
        end
    end

    dreamwayFrame.leftArrow = CreateTinyButton(dreamwayFrame, "<", 20)
    dreamwayFrame.leftArrow:SetScript("OnClick", PreviousBatch)

    dreamwayFrame.rightArrow = CreateTinyButton(dreamwayFrame, ">", 20)
    dreamwayFrame.rightArrow:SetScript("OnClick", NextBatch)

    dreamwayFrame.batchButton = CreateFrame("Button", nil, dreamwayFrame)
    dreamwayFrame.batchButton:RegisterForClicks("LeftButtonUp")
    dreamwayFrame.batchButton:SetScript("OnClick", TogglePanel)
    dreamwayFrame.batchButton.text = dreamwayFrame.batchButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dreamwayFrame.batchButton.text:SetPoint("CENTER", dreamwayFrame.batchButton, "CENTER", 0, 0)
    dreamwayFrame.batchButton.text:SetJustifyH("CENTER")
    dreamwayFrame.batchButton:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        AnchorDreamwayTooltip(self)
        GameTooltip:AddLine(self.fullTitle or "No batch", 0.35, 0.85, 1)
        GameTooltip:AddLine("Click to open the Journey Planner.", 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    dreamwayFrame.batchButton:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    dreamwayFrame:Hide()
end

function JsonSkipWhitespace(text, position)
    while position <= #text and text:sub(position, position):match("%s") do
        position = position + 1
    end
    return position
end

function JsonParseStringAt(text, position)
    position = JsonSkipWhitespace(text, position)
    if text:sub(position, position) ~= '"' then
        return nil, position
    end

    local out = {}
    local index = position + 1
    while index <= #text do
        local char = text:sub(index, index)
        if char == '"' then
            return table.concat(out), index + 1
        elseif char == "\\" then
            local escaped = text:sub(index + 1, index + 1)
            if escaped == '"' or escaped == "\\" or escaped == "/" then
                out[#out + 1] = escaped
                index = index + 2
            elseif escaped == "n" then
                out[#out + 1] = "\n"
                index = index + 2
            elseif escaped == "r" then
                out[#out + 1] = "\r"
                index = index + 2
            elseif escaped == "t" then
                out[#out + 1] = "\t"
                index = index + 2
            elseif escaped == "u" then
                out[#out + 1] = "?"
                index = index + 6
            else
                index = index + 2
            end
        else
            out[#out + 1] = char
            index = index + 1
        end
    end

    return nil, index
end

function JsonFindFieldValue(text, field)
    local pattern = '"' .. field .. '"%s*:%s*()'
    return text:match(pattern)
end

function JsonStringField(text, field)
    local position = JsonFindFieldValue(text, field)
    if not position then
        return nil
    end

    return JsonParseStringAt(text, position)
end

function JsonNumberField(text, field)
    local position = JsonFindFieldValue(text, field)
    if not position then
        return nil
    end

    position = JsonSkipWhitespace(text, position)
    local numberText = text:match("^-?%d+", position)
    return numberText and tonumber(numberText) or nil
end

function JsonBoolField(text, field)
    local position = JsonFindFieldValue(text, field)
    if not position then
        return nil
    end

    position = JsonSkipWhitespace(text, position)
    local value = text:sub(position, position + 3)
    if value == "true" then
        return true
    end

    value = text:sub(position, position + 4)
    if value == "false" then
        return false
    end

    return nil
end

function JsonFindMatching(text, startPosition, openChar, closeChar)
    local depth = 0
    local inString = false
    local escaped = false

    for index = startPosition, #text do
        local char = text:sub(index, index)
        if inString then
            if escaped then
                escaped = false
            elseif char == "\\" then
                escaped = true
            elseif char == '"' then
                inString = false
            end
        else
            if char == '"' then
                inString = true
            elseif char == openChar then
                depth = depth + 1
            elseif char == closeChar then
                depth = depth - 1
                if depth == 0 then
                    return index
                end
            end
        end
    end

    return nil
end

function JsonArrayRange(text, field)
    local position = JsonFindFieldValue(text, field)
    if not position then
        return nil
    end
    position = JsonSkipWhitespace(text, position)
    if text:sub(position, position) ~= "[" then
        return nil
    end

    local finish = JsonFindMatching(text, position, "[", "]")
    if not finish then
        return nil
    end

    return position, finish
end

function JsonObjectArray(text, field)
    local startPosition, finish = JsonArrayRange(text, field)
    if not startPosition then
        return {}
    end

    local objects = {}
    local index = startPosition + 1
    while index < finish do
        local char = text:sub(index, index)
        if char == "{" then
            local objectFinish = JsonFindMatching(text, index, "{", "}")
            if not objectFinish or objectFinish > finish then
                break
            end
            objects[#objects + 1] = text:sub(index, objectFinish)
            index = objectFinish + 1
        else
            index = index + 1
        end
    end

    return objects
end

function JsonNumberArray(text, field)
    local startPosition, finish = JsonArrayRange(text, field)
    if not startPosition then
        return {}
    end

    local values = {}
    local body = text:sub(startPosition + 1, finish - 1)
    for numberText in body:gmatch("-?%d+") do
        values[#values + 1] = tonumber(numberText)
    end
    return values
end

function JsonStringArray(text, field)
    local startPosition, finish = JsonArrayRange(text, field)
    if not startPosition then
        return {}
    end

    local values = {}
    local index = startPosition + 1
    while index < finish do
        if text:sub(index, index) == '"' then
            local value, nextIndex = JsonParseStringAt(text, index)
            if value then
                values[#values + 1] = value
                index = nextIndex
            else
                index = index + 1
            end
        else
            index = index + 1
        end
    end
    return values
end

function DreamwayDenseSplit(value, separator)
    value = tostring(value or "")
    local parts = {}
    local startPosition = 1
    while true do
        local separatorPosition = string.find(value, separator, startPosition, true)
        if not separatorPosition then
            parts[#parts + 1] = string.sub(value, startPosition)
            break
        end
        parts[#parts + 1] = string.sub(value, startPosition, separatorPosition - 1)
        startPosition = separatorPosition + #separator
    end
    return parts
end

function DreamwayDenseEncode(value)
    return (tostring(value or ""):gsub("([^%w%._%-])", function(character)
        return string.format("%%%02X", string.byte(character))
    end))
end

function DreamwayDenseDecode(value)
    return (tostring(value or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

function DreamwayDenseNumberArray(value)
    local numbers = {}
    if not value or value == "" then
        return numbers
    end
    for _, token in ipairs(DreamwayDenseSplit(value, ",")) do
        local number = tonumber(token)
        if not number or number <= 0 then
            return nil
        end
        numbers[#numbers + 1] = number
    end
    return numbers
end

function ParseJourneyDense(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$") or ""
    local separator
    local prefix = string.sub(text, 1, 4)
    if (prefix == "DWJ2" or prefix == "QPJ2") and string.sub(text, 5, 5) == ":" then
        separator = ":"
    elseif (prefix == "DWJ2" or prefix == "QPJ2") and string.sub(text, 5, 5) == "|" then
        text = string.gsub(text, "||", "|")
        separator = "|"
    else
        return nil, "That is not a valid Dreamway Journey string."
    end
    local fields = DreamwayDenseSplit(text, separator)
    if (fields[1] ~= "DWJ2" and fields[1] ~= "QPJ2") or #fields < 7 or #fields > 10 then
        return nil, "That is not a valid Dreamway Journey string."
    end

    local journeyName = DreamwayDenseDecode(fields[3])
    local raceMask = tonumber(fields[4])
    local classMask = tonumber(fields[5])
    if journeyName == "" or not raceMask or not classMask then
        return nil, "The Journey string is missing its name, race, or class."
    end

    local batchTokens = fields[6] ~= "" and DreamwayDenseSplit(fields[6], ";") or {}
    if #batchTokens == 0 then
        return nil, "No batches were found in that Journey string."
    end

    local journeyId = DreamwayDenseDecode(fields[2])
    local journey = {
        id = journeyId ~= "" and journeyId or ("imported-" .. tostring(time())),
        name = journeyName,
        savedAt = fields[10] and DreamwayDenseDecode(fields[10]) or "",
        gameVersion = NormalizeDreamwayGameVersion(fields[8]),
        character = {
            raceMask = raceMask,
            classMask = classMask,
            faction = fields[9] == "a" and "Alliance" or fields[9] == "h" and "Horde" or "all",
        },
        batches = {},
        hiddenQuestIds = {},
        hiddenQuests = {},
        unusedQuestIds = {},
        unusedQuests = {},
    }

    for batchNumber, batchToken in ipairs(batchTokens) do
        local parts = DreamwayDenseSplit(batchToken, "~")
        if #parts ~= 3 then
            return nil, "Batch " .. tostring(batchNumber) .. " is malformed."
        end
        local storedName = DreamwayDenseDecode(parts[1])
        local expectedLevelOverride = tonumber(parts[2])
        if not expectedLevelOverride or expectedLevelOverride < 0 then
            return nil, "Batch " .. tostring(batchNumber) .. " has an invalid level."
        end
        local questIds = DreamwayDenseNumberArray(parts[3])
        if not questIds then
            return nil, "Batch " .. tostring(batchNumber) .. " has an invalid quest list."
        end
        local batch = {
            id = "batch-" .. tostring(batchNumber),
            name = storedName ~= "" and storedName or tostring(batchNumber),
            autoName = storedName == "",
            expectedLevelManual = expectedLevelOverride and expectedLevelOverride > 0 or false,
            expectedLevelOverride = expectedLevelOverride and expectedLevelOverride > 0 and expectedLevelOverride or nil,
            quests = {},
            zones = {},
        }
        for _, questId in ipairs(questIds) do
            batch.quests[#batch.quests + 1] = { id = questId }
        end
        journey.batches[#journey.batches + 1] = batch
    end

    local hiddenIds = DreamwayDenseNumberArray(fields[7])
    if not hiddenIds then
        return nil, "The Hidden quest list is invalid."
    end
    for _, questId in ipairs(hiddenIds) do
        journey.hiddenQuestIds[#journey.hiddenQuestIds + 1] = questId
        journey.hiddenQuests[#journey.hiddenQuests + 1] = { id = questId }
        journey.unusedQuestIds[#journey.unusedQuestIds + 1] = questId
        journey.unusedQuests[#journey.unusedQuests + 1] = { id = questId }
    end

    return journey
end

local function ParseJourneyJson(text)
    if not text or not text:find("{", 1, true) then
        return nil, "Paste a Journey string from the Dreamway web app."
    end

    local journeyName = JsonStringField(text, "name") or "Imported Journey"
    local journeyId = JsonStringField(text, "id") or ("imported-" .. tostring(time()))
    local batchObjects = JsonObjectArray(text, "batches")

    if #batchObjects == 0 then
        return nil, "No batches were found in that Journey export."
    end

    local journey = {
        id = journeyId,
        name = journeyName,
        savedAt = JsonStringField(text, "savedAt") or "",
        gameVersion = NormalizeDreamwayGameVersion(JsonStringField(text, "gameVersion") or CurrentDreamwayGameVersion()),
        character = {
            race = JsonStringField(text, "race"),
            raceMask = JsonNumberField(text, "raceMask"),
            faction = JsonStringField(text, "faction"),
            class = JsonStringField(text, "class"),
            classMask = JsonNumberField(text, "classMask"),
        },
        batches = {},
        hiddenQuestIds = {},
        hiddenQuests = {},
        unusedQuestIds = {},
        unusedQuests = {},
    }

    local hiddenSeen = {}
    local function AddHiddenQuest(quest)
        local questId = tonumber(quest and quest.id)
        if not questId or hiddenSeen[questId] then
            return
        end

        hiddenSeen[questId] = true
        journey.hiddenQuestIds[#journey.hiddenQuestIds + 1] = questId
        journey.hiddenQuests[#journey.hiddenQuests + 1] = {
            id = questId,
            name = quest.name or ("Quest #" .. tostring(questId)),
            requiredLevel = quest.requiredLevel,
            questLevel = quest.questLevel,
            chainId = quest.chainId,
            chainName = quest.chainName,
            chainStep = quest.chainStep,
            chainLength = quest.chainLength,
            chainGroupId = quest.chainGroupId,
            chainGroupStep = quest.chainGroupStep,
            chainGroupSize = quest.chainGroupSize,
            preQuestSingle = quest.preQuestSingle or {},
            preQuestGroup = quest.preQuestGroup or {},
            startZoneIds = quest.startZoneIds or {},
            objectiveZoneIds = quest.objectiveZoneIds or {},
            endZoneIds = quest.endZoneIds or {},
            zoneIds = quest.zoneIds or {},
            zones = quest.zones or {},
        }
        journey.unusedQuestIds[#journey.unusedQuestIds + 1] = questId
        journey.unusedQuests[#journey.unusedQuests + 1] = {
            id = questId,
            name = quest.name or ("Quest #" .. tostring(questId)),
            requiredLevel = quest.requiredLevel,
            questLevel = quest.questLevel,
            chainId = quest.chainId,
            chainName = quest.chainName,
            chainStep = quest.chainStep,
            chainLength = quest.chainLength,
            chainGroupId = quest.chainGroupId,
            chainGroupStep = quest.chainGroupStep,
            chainGroupSize = quest.chainGroupSize,
            preQuestSingle = quest.preQuestSingle or {},
            preQuestGroup = quest.preQuestGroup or {},
            startZoneIds = quest.startZoneIds or {},
            objectiveZoneIds = quest.objectiveZoneIds or {},
            endZoneIds = quest.endZoneIds or {},
            zoneIds = quest.zoneIds or {},
            zones = quest.zones or {},
        }
    end

    for batchNumber, batchText in ipairs(batchObjects) do
        local batch = {
            id = JsonStringField(batchText, "id") or ("batch-" .. tostring(batchNumber)),
            name = JsonStringField(batchText, "name") or tostring(batchNumber),
            expectedLevel = JsonNumberField(batchText, "expectedLevel"),
            expectedLevelManual = JsonBoolField(batchText, "expectedLevelManual"),
            expectedLevelOverride = JsonNumberField(batchText, "expectedLevelOverride"),
            autoName = JsonBoolField(batchText, "autoName"),
            zones = JsonStringArray(batchText, "zones"),
            quests = {},
        }

        local questObjects = JsonObjectArray(batchText, "quests")
        if #questObjects > 0 then
            for _, questText in ipairs(questObjects) do
                local questId = JsonNumberField(questText, "id")
                if questId then
                    batch.quests[#batch.quests + 1] = {
                        id = questId,
                        name = JsonStringField(questText, "name") or ("Quest #" .. tostring(questId)),
                        requiredLevel = JsonNumberField(questText, "requiredLevel"),
                        questLevel = JsonNumberField(questText, "questLevel"),
                        chainId = JsonNumberField(questText, "chainId"),
                        chainName = JsonStringField(questText, "chainName"),
                        chainStep = JsonNumberField(questText, "chainStep"),
                        chainLength = JsonNumberField(questText, "chainLength"),
                        chainGroupId = JsonNumberField(questText, "chainGroupId"),
                        chainGroupStep = JsonNumberField(questText, "chainGroupStep"),
                        chainGroupSize = JsonNumberField(questText, "chainGroupSize"),
                        preQuestSingle = JsonNumberArray(questText, "preQuestSingle"),
                        preQuestGroup = JsonNumberArray(questText, "preQuestGroup"),
                        startZoneIds = JsonNumberArray(questText, "startZoneIds"),
                        objectiveZoneIds = JsonNumberArray(questText, "objectiveZoneIds"),
                        endZoneIds = JsonNumberArray(questText, "endZoneIds"),
                        zoneIds = JsonNumberArray(questText, "zoneIds"),
                        zones = JsonStringArray(questText, "zones"),
                    }
                end
            end
        else
            local questIds = JsonNumberArray(batchText, "questIds")
            for _, questId in ipairs(questIds) do
                batch.quests[#batch.quests + 1] = {
                    id = questId,
                    name = "Quest #" .. tostring(questId),
                }
            end
        end

        journey.batches[#journey.batches + 1] = batch
    end

    for _, questText in ipairs(JsonObjectArray(text, "hiddenQuests")) do
        local questId = JsonNumberField(questText, "id")
        if questId then
            AddHiddenQuest({
                id = questId,
                name = JsonStringField(questText, "name") or ("Quest #" .. tostring(questId)),
                requiredLevel = JsonNumberField(questText, "requiredLevel"),
                questLevel = JsonNumberField(questText, "questLevel"),
                chainId = JsonNumberField(questText, "chainId"),
                chainName = JsonStringField(questText, "chainName"),
                chainStep = JsonNumberField(questText, "chainStep"),
                chainLength = JsonNumberField(questText, "chainLength"),
                chainGroupId = JsonNumberField(questText, "chainGroupId"),
                chainGroupStep = JsonNumberField(questText, "chainGroupStep"),
                chainGroupSize = JsonNumberField(questText, "chainGroupSize"),
                preQuestSingle = JsonNumberArray(questText, "preQuestSingle"),
                preQuestGroup = JsonNumberArray(questText, "preQuestGroup"),
                startZoneIds = JsonNumberArray(questText, "startZoneIds"),
                objectiveZoneIds = JsonNumberArray(questText, "objectiveZoneIds"),
                endZoneIds = JsonNumberArray(questText, "endZoneIds"),
                zoneIds = JsonNumberArray(questText, "zoneIds"),
                zones = JsonStringArray(questText, "zones"),
            })
        end
    end

    for _, questId in ipairs(JsonNumberArray(text, "hiddenQuestIds")) do
        AddHiddenQuest({
            id = questId,
            name = "Quest #" .. tostring(questId),
        })
    end

    for _, questText in ipairs(JsonObjectArray(text, "unusedQuests")) do
        local questId = JsonNumberField(questText, "id")
        if questId then
            AddHiddenQuest({
                id = questId,
                name = JsonStringField(questText, "name") or ("Quest #" .. tostring(questId)),
                requiredLevel = JsonNumberField(questText, "requiredLevel"),
                questLevel = JsonNumberField(questText, "questLevel"),
                chainId = JsonNumberField(questText, "chainId"),
                chainName = JsonStringField(questText, "chainName"),
                chainStep = JsonNumberField(questText, "chainStep"),
                chainLength = JsonNumberField(questText, "chainLength"),
                chainGroupId = JsonNumberField(questText, "chainGroupId"),
                chainGroupStep = JsonNumberField(questText, "chainGroupStep"),
                chainGroupSize = JsonNumberField(questText, "chainGroupSize"),
                preQuestSingle = JsonNumberArray(questText, "preQuestSingle"),
                preQuestGroup = JsonNumberArray(questText, "preQuestGroup"),
                startZoneIds = JsonNumberArray(questText, "startZoneIds"),
                objectiveZoneIds = JsonNumberArray(questText, "objectiveZoneIds"),
                endZoneIds = JsonNumberArray(questText, "endZoneIds"),
                zoneIds = JsonNumberArray(questText, "zoneIds"),
                zones = JsonStringArray(questText, "zones"),
            })
        end
    end

    for _, questId in ipairs(JsonNumberArray(text, "unusedQuestIds")) do
        AddHiddenQuest({
            id = questId,
            name = "Quest #" .. tostring(questId),
        })
    end

    return journey
end

function DreamwayInstallImportedJourney(journey)
    RefreshJourneyDerivedData(journey)
    DreamwayDB.journeys[journey.id] = journey
    DreamwaySetActiveJourneyId(journey.id)
    batchIndex = 1
    SaveDb()
    ApplyUnusedQuestSuppression()
    RefreshDreamwayTracker()
    if panelFrame and panelFrame:IsShown() and RefreshPanel then
        RefreshPanel()
    end
    local hiddenCount = journey.unusedQuestIds and #journey.unusedQuestIds or 0
    local hiddenText = hiddenCount > 0 and (", " .. tostring(hiddenCount) .. " hidden") or ""
    local prerequisiteWarnings = JourneyPrerequisiteWarnings and JourneyPrerequisiteWarnings(journey) or {}
    local warningCount = 0
    for _ in pairs(prerequisiteWarnings) do
        warningCount = warningCount + 1
    end
    local warningText = warningCount > 0 and (", " .. tostring(warningCount) .. " prerequisite warning" .. (warningCount == 1 and "" or "s")) or ""
    local importedVersion = NormalizeDreamwayGameVersion(journey.gameVersion)
    local currentVersion = CurrentDreamwayGameVersion()
    local versionText = importedVersion ~= currentVersion and (", version " .. importedVersion .. " loaded on " .. currentVersion) or ""
    panelJourneyManager.selectedJourneyId = journey.id
    if DreamwayRefreshJourneyManager then
        DreamwayRefreshJourneyManager()
    end
    return true, "Imported " .. journey.name .. " (" .. tostring(#journey.batches) .. " batches" .. hiddenText .. warningText .. versionText .. ")."
end

function DreamwayShowOlderJourneyImportWarning(journey)
    ProfileRecorder.pendingOlderJourney = journey
    StaticPopupDialogs.DREAMWAY_IMPORT_OLDER_JOURNEY = StaticPopupDialogs.DREAMWAY_IMPORT_OLDER_JOURNEY or {
        text = "This Journey was saved earlier than the copy already stored in Dreamway. Import the older version anyway?",
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function()
            local pending = ProfileRecorder.pendingOlderJourney
            ProfileRecorder.pendingOlderJourney = nil
            if not pending then return end
            local ok, message = DreamwayInstallImportedJourney(pending)
            PanelSetStatus(message, ok)
            if ok and panelImportEditBox then
                panelImportEditBox:SetText("")
                panelImportEditBox:ClearFocus()
                if panelImportArea then panelImportArea:Hide() end
            end
        end,
        OnCancel = function()
            ProfileRecorder.pendingOlderJourney = nil
        end,
    }
    StaticPopup_Show("DREAMWAY_IMPORT_OLDER_JOURNEY")
end

local function ImportJourneyText(text)
    local source = tostring(text or ""):match("^%s*(.-)%s*$") or ""
    local journey, errorMessage
    local prefix = string.sub(source, 1, 4)
    if (prefix == "DWJ2" or prefix == "QPJ2")
        and (string.sub(source, 5, 5) == "|" or string.sub(source, 5, 5) == ":")
    then
        journey, errorMessage = ParseJourneyDense(source)
    else
        journey, errorMessage = ParseJourneyJson(source)
    end
    if not journey then
        return false, errorMessage
    end

    local stored = DreamwayDB.journeys and DreamwayDB.journeys[journey.id]
    if stored and stored.savedAt and stored.savedAt ~= "" and journey.savedAt and journey.savedAt ~= "" and journey.savedAt < stored.savedAt then
        DreamwayShowOlderJourneyImportWarning(journey)
        return false, "Older Journey detected. Confirm the import in the warning dialog."
    end

    return DreamwayInstallImportedJourney(journey)
end

local function JourneyUnusedQuestRows(journey)
    local rows = {}
    local seen = {}

    local function addQuest(quest)
        local questId = tonumber(quest and quest.id)
        if not questId or seen[questId] then
            return
        end

        seen[questId] = true
        local row = {
            id = questId,
            name = quest.name,
            requiredLevel = quest.requiredLevel,
            questLevel = quest.questLevel,
            chainId = quest.chainId,
            chainName = quest.chainName,
            chainStep = quest.chainStep,
            chainLength = quest.chainLength,
            chainGroupId = quest.chainGroupId,
            chainGroupStep = quest.chainGroupStep,
            chainGroupSize = quest.chainGroupSize,
            preQuestSingle = quest.preQuestSingle or {},
            preQuestGroup = quest.preQuestGroup or {},
            startZoneIds = quest.startZoneIds or {},
            objectiveZoneIds = quest.objectiveZoneIds or {},
            endZoneIds = quest.endZoneIds or {},
            zoneIds = quest.zoneIds or {},
            zones = quest.zones or {},
        }

        if HydrateQuestMetadata then
            row = HydrateQuestMetadata(row)
        end

        if not row.name or row.name == "" or not row.questLevel then
            local dbQuest = GetQuestieQuest(row)
            if dbQuest then
                row.name = row.name ~= "" and row.name or dbQuest.name or dbQuest.Name or row.name
                row.questLevel = row.questLevel or dbQuest.level or dbQuest.Level
                row.requiredLevel = row.requiredLevel or dbQuest.requiredLevel or dbQuest.RequiredLevel
                row.preQuestSingle = (#(row.preQuestSingle or {}) > 0) and row.preQuestSingle or (dbQuest.preQuestSingle or dbQuest.PreQuestSingle or {})
                row.preQuestGroup = (#(row.preQuestGroup or {}) > 0) and row.preQuestGroup or (dbQuest.preQuestGroup or dbQuest.PreQuestGroup or {})
            end
        end

        row.name = row.name or ("Quest #" .. tostring(questId))
        rows[#rows + 1] = row
    end

    for _, quest in ipairs(journey and journey.hiddenQuests or {}) do
        addQuest(quest)
    end

    for _, quest in ipairs(journey and journey.unusedQuests or {}) do
        addQuest(quest)
    end

    for _, questId in ipairs(journey and journey.hiddenQuestIds or {}) do
        addQuest({ id = questId })
    end

    for _, questId in ipairs(journey and journey.unusedQuestIds or {}) do
        addQuest({ id = questId })
    end

    return rows
end

local function SynchronizeJourneyHiddenQuests(journey)
    if not journey then
        return
    end

    local rows = JourneyUnusedQuestRows(journey)
    journey.hiddenQuestIds = {}
    journey.hiddenQuests = {}
    journey.unusedQuestIds = {}
    journey.unusedQuests = {}
    for _, quest in ipairs(rows) do
        local questId = tonumber(quest and quest.id)
        if questId then
            journey.hiddenQuestIds[#journey.hiddenQuestIds + 1] = questId
            journey.hiddenQuests[#journey.hiddenQuests + 1] = quest
            journey.unusedQuestIds[#journey.unusedQuestIds + 1] = questId
            journey.unusedQuests[#journey.unusedQuests + 1] = quest
        end
    end
end

local function GetSortedPanelQuests(batch)
    if SortJourneyBatchQuests then
        SortJourneyBatchQuests(batch)
    end
    local rows = {}
    for index, quest in ipairs(batch.quests or {}) do
        rows[#rows + 1] = {
            quest = quest,
            index = index,
            complete = IsJourneyComplete(quest),
        }
    end
    return rows
end

BatchExpectedLevel = function(batch)
    local maxLevel = DreamwayCurrentMaxLevel()
    local explicitLevel = tonumber(batch and batch.expectedLevelOverride)
    if batch and batch.expectedLevelManual and explicitLevel and explicitLevel > 0 then
        return math.max(1, math.min(maxLevel, math.floor(explicitLevel + 0.5)))
    end

    local total = 0
    local count = 0
    for _, quest in ipairs(batch and batch.quests or {}) do
        local level = tonumber(quest.questLevel or quest.requiredLevel)
        if level and level > 0 then
            total = total + level
            count = count + 1
        end
    end

    if count == 0 then
        return nil
    end

    return math.max(1, math.min(maxLevel, math.floor((total / count) + 0.5)))
end

local function IsBatchComplete(batch)
    if not batch or not batch.quests or #batch.quests == 0 then
        return false
    end

    for _, quest in ipairs(batch.quests) do
        if not IsJourneyComplete(quest) then
            return false
        end
    end

    return true
end

function PanelSetStatus(message, ok)
    if not panelStatusText then
        return
    end

    panelStatusText:SetText(message or "")
    if ok == nil then
        panelStatusText:SetTextColor(0.75, 0.75, 0.75)
    elseif ok then
        panelStatusText:SetTextColor(0.35, 1, 0.35)
    else
        panelStatusText:SetTextColor(1, 0.25, 0.25)
    end
end

local function CloneNumberArray(values)
    local out = {}
    for _, value in ipairs(values or {}) do
        value = tonumber(value)
        if value then
            out[#out + 1] = value
        end
    end
    return out
end

local function CloneStringArray(values)
    local out = {}
    for _, value in ipairs(values or {}) do
        if value and value ~= "" then
            out[#out + 1] = tostring(value)
        end
    end
    return out
end

local function QuestZoneDbRecord(questId)
    questId = tonumber(questId)
    local db = DreamwayQuestZones
    return questId and db and db.quests and db.quests[questId] or nil
end

local function QuestChainDbRecord(chainId)
    chainId = tonumber(chainId)
    local db = DreamwayQuestZones
    return chainId and db and db.chains and db.chains[chainId] or nil
end

local function QuestChainName(chainId)
    local chain = QuestChainDbRecord(chainId)
    return chain and chain.n and tostring(chain.n) or nil
end

local function QuestChainSortInfo(chainId)
    chainId = tonumber(chainId)
    if not chainId then
        return nil
    end

    if chainSortCache[chainId] then
        return chainSortCache[chainId]
    end

    local chain = QuestChainDbRecord(chainId)
    local info = {
        name = QuestChainName(chainId) or ("Chain " .. tostring(chainId)),
        requiredLevel = tonumber(chain and chain.rl) or 999,
        questLevel = tonumber(chain and chain.ql) or 999,
    }

    chainSortCache[chainId] = info
    return info
end

local function ZoneNamesFromIds(zoneIds)
    local names = {}
    local zoneNames = DreamwayQuestZones and DreamwayQuestZones.zones or nil
    if not zoneNames then
        return names
    end

    for _, zoneId in ipairs(zoneIds or {}) do
        zoneId = tonumber(zoneId)
        local name = zoneId and zoneNames[zoneId]
        if name and name ~= "" then
            names[#names + 1] = tostring(name)
        end
    end
    return names
end

local function ApplyQuestZoneMetadata(quest)
    local record = QuestZoneDbRecord(quest and quest.id)
    if not record then
        return quest
    end

    quest.startZoneIds = CloneNumberArray(record.s)
    quest.objectiveZoneIds = CloneNumberArray(record.o)
    quest.endZoneIds = CloneNumberArray(record.e)
    quest.zoneIds = CloneNumberArray(record.a)
    quest.zones = ZoneNamesFromIds(quest.zoneIds)
    quest.chainId = tonumber(record.c) or quest.chainId
    quest.chainName = QuestChainName(quest.chainId) or quest.chainName
    quest.chainStep = tonumber(record.cs) or quest.chainStep
    quest.chainLength = tonumber(record.cl) or quest.chainLength
    quest.chainGroupId = tonumber(record.cg) or quest.chainGroupId
    quest.chainGroupStep = tonumber(record.cgs) or quest.chainGroupStep
    quest.chainGroupSize = tonumber(record.cgz) or quest.chainGroupSize
    if type(quest.preQuestGroup) ~= "table" or #quest.preQuestGroup == 0 then
        quest.preQuestGroup = CloneNumberArray(record.pg)
    end
    if type(quest.preQuestSingle) ~= "table" or #quest.preQuestSingle == 0 then
        quest.preQuestSingle = CloneNumberArray(record.ps)
    end
    quest.requiredLevel = quest.requiredLevel or tonumber(record.rl)
    quest.questLevel = quest.questLevel or tonumber(record.ql)
    quest.requiredRaceMask = tonumber(record.rm) or quest.requiredRaceMask or 0
    quest.requiredClassMask = tonumber(record.cm) or quest.requiredClassMask or 0
    quest.gameVersion = record.gv or quest.gameVersion
    quest.typeIds = CloneStringArray(record.t)
    if #quest.typeIds == 0 then
        quest.typeIds = { "general" }
    end
    return quest
end

function panelSearchFilters.FilterZones()
    local db = DreamwayQuestZones
    if db and type(db.zoneList) == "table" then
        return db.zoneList
    end

    local zones = {}
    if db and type(db.zones) == "table" then
        for zoneId, name in pairs(db.zones) do
            zoneId = tonumber(zoneId)
            if zoneId and name and name ~= "" then
                zones[#zones + 1] = { id = zoneId, n = tostring(name), r = "" }
            end
        end
        table.sort(zones, function(a, b)
            return (a.id or 0) < (b.id or 0)
        end)
    end

    return zones
end

function panelSearchFilters.FilterFactions()
    local db = DreamwayQuestZones
    if db and type(db.factions) == "table" then
        return db.factions
    end
    return {
        { id = "Alliance", n = "Alliance", d = true },
        { id = "Horde", n = "Horde", d = true },
    }
end

function panelSearchFilters.FilterRaces()
    local db = DreamwayQuestZones
    if db and type(db.races) == "table" then
        return db.races
    end
    return {
        { m = 1, n = "Human", f = "Alliance", d = true },
        { m = 4, n = "Dwarf", f = "Alliance", d = true },
        { m = 8, n = "Night Elf", f = "Alliance", d = true },
        { m = 64, n = "Gnome", f = "Alliance", d = true },
        { m = 2, n = "Orc", f = "Horde", d = true },
        { m = 16, n = "Undead", f = "Horde", d = true },
        { m = 32, n = "Tauren", f = "Horde", d = true },
        { m = 128, n = "Troll", f = "Horde", d = true },
    }
end

function panelSearchFilters.FilterClasses()
    local db = DreamwayQuestZones
    if db and type(db.classes) == "table" then
        return db.classes
    end
    return {
        { m = 1, n = "Warrior", d = true },
        { m = 2, n = "Paladin", d = true },
        { m = 4, n = "Hunter", d = true },
        { m = 8, n = "Rogue", d = true },
        { m = 16, n = "Priest", d = true },
        { m = 64, n = "Shaman", d = true },
        { m = 128, n = "Mage", d = true },
        { m = 256, n = "Warlock", d = true },
        { m = 1024, n = "Druid", d = true },
    }
end

function panelSearchFilters.FilterTypes()
    local db = DreamwayQuestZones
    if db and type(db.types) == "table" then
        local types = {}
        local gameVersion = CurrentDreamwayGameVersion()
        for _, typeInfo in ipairs(db.types) do
            if not typeInfo.v or tostring(typeInfo.v) == gameVersion then
                types[#types + 1] = typeInfo
            end
        end
        return types
    end
    return {
        { id = "general", n = "General progression", d = true },
    }
end

function panelSearchFilters.Ensure()
    if panelSearchFilters.initialized then
        return
    end

    panelSearchFilters.starts = true
    panelSearchFilters.objectives = true
    panelSearchFilters.ends = true
    panelSearchFilters.factions = {}
    panelSearchFilters.raceMasks = {}
    panelSearchFilters.classMasks = {}
    panelSearchFilters.typeIds = {}
    panelSearchFilters.zoneIds = {}

    local currentFaction = UnitFactionGroup and UnitFactionGroup("player") or nil
    local currentRaceId
    local currentClassId
    if UnitRace then
        local _, _, raceId = UnitRace("player")
        currentRaceId = raceId
    end
    if UnitClass then
        local _, _, classId = UnitClass("player")
        currentClassId = classId
    end
    local raceMaskById = {
        [1] = 1,
        [2] = 2,
        [3] = 4,
        [4] = 8,
        [5] = 16,
        [6] = 32,
        [7] = 64,
        [8] = 128,
        [10] = 512,
        [11] = 1024,
    }
    local currentRaceMask = raceMaskById[tonumber(currentRaceId)]
    local currentClassMask = currentClassId and (2 ^ (tonumber(currentClassId) - 1)) or nil

    for _, faction in ipairs(panelSearchFilters.FilterFactions()) do
        local id = faction and faction.id
        if id and ((currentFaction and tostring(id) == tostring(currentFaction)) or (not currentFaction and faction.d ~= false)) then
            panelSearchFilters.factions[tostring(id)] = true
        end
    end

    for _, race in ipairs(panelSearchFilters.FilterRaces()) do
        local mask = tonumber(race and race.m)
        if mask and ((currentRaceMask and mask == currentRaceMask) or (not currentRaceMask and race.d ~= false)) then
            panelSearchFilters.raceMasks[mask] = true
        end
    end

    for _, classInfo in ipairs(panelSearchFilters.FilterClasses()) do
        local mask = tonumber(classInfo and classInfo.m)
        if mask and ((currentClassMask and mask == currentClassMask) or (not currentClassMask and classInfo.d ~= false)) then
            panelSearchFilters.classMasks[mask] = true
        end
    end

    for _, typeInfo in ipairs(panelSearchFilters.FilterTypes()) do
        local id = typeInfo and typeInfo.id
        if id and typeInfo.d == true then
            panelSearchFilters.typeIds[tostring(id)] = true
        end
    end

    panelSearchFilters.zoneIds[panelSearchFilters.unknownZoneId] = true
    for _, zone in ipairs(panelSearchFilters.FilterZones()) do
        local zoneId = tonumber(zone and zone.id)
        if zoneId then
            panelSearchFilters.zoneIds[zoneId] = true
        end
    end

    panelSearchFilters.initialized = true
end

function panelSearchFilters.ZoneSetContainsAny(zoneIds)
    panelSearchFilters.Ensure()
    local hasZone = false
    for _, zoneId in ipairs(zoneIds or {}) do
        zoneId = tonumber(zoneId)
        if zoneId then
            hasZone = true
        end
        if zoneId and panelSearchFilters.zoneIds[zoneId] then
            return true
        end
    end
    if not hasZone then
        return panelSearchFilters.zoneIds[panelSearchFilters.unknownZoneId] == true
    end
    return false
end

function panelSearchFilters.SelectedSetHasAny(set)
    for _, enabled in pairs(set or {}) do
        if enabled then
            return true
        end
    end
    return false
end

function panelSearchFilters.QuestFactionAllowed(raceMask)
    raceMask = tonumber(raceMask) or 0
    if raceMask == 0 then
        return panelSearchFilters.factions.Alliance == true or panelSearchFilters.factions.Horde == true
    end

    for _, race in ipairs(panelSearchFilters.FilterRaces()) do
        local mask = tonumber(race and race.m)
        local faction = race and race.f
        if mask and faction and DreamwayBitBand(raceMask, mask) ~= 0 and panelSearchFilters.factions[tostring(faction)] then
            return true
        end
    end
    return false
end

function panelSearchFilters.MaskAllowed(requiredMask, selectedMasks)
    requiredMask = tonumber(requiredMask) or 0
    if requiredMask == 0 then
        return panelSearchFilters.SelectedSetHasAny(selectedMasks)
    end

    for selectedMask, enabled in pairs(selectedMasks or {}) do
        selectedMask = tonumber(selectedMask)
        if enabled and selectedMask and DreamwayBitBand(requiredMask, selectedMask) ~= 0 then
            return true
        end
    end
    return false
end

function panelSearchFilters.PassesCharacter(quest)
    quest = ApplyQuestZoneMetadata(quest)
    local raceMask = tonumber(quest and quest.requiredRaceMask) or 0
    local classMask = tonumber(quest and quest.requiredClassMask) or 0
    return panelSearchFilters.MaskAllowed(raceMask, panelSearchFilters.raceMasks)
        and panelSearchFilters.MaskAllowed(classMask, panelSearchFilters.classMasks)
        and panelSearchFilters.QuestFactionAllowed(raceMask)
end

function panelSearchFilters.PassesType(quest)
    quest = ApplyQuestZoneMetadata(quest)
    local typeIds = quest and quest.typeIds
    if type(typeIds) ~= "table" or #typeIds == 0 then
        typeIds = { "general" }
    end

    local standardTypeMatches = false
    for _, typeId in ipairs(typeIds) do
        if typeId and panelSearchFilters.typeIds[tostring(typeId)] then
            standardTypeMatches = true
            break
        end
    end
    if not standardTypeMatches then
        return false
    end
    if quest and quest.gameVersion == "sod" and CurrentDreamwayGameVersion() == "sod" then
        return panelSearchFilters.typeIds["sod-exclusive"] == true
    end
    return true
end

function panelSearchFilters.PassesLevel(quest)
    quest = ApplyQuestZoneMetadata(quest)
    local playerLevel = tonumber(UnitLevel and UnitLevel("player")) or 1
    local requiredLevel = tonumber(quest and quest.requiredLevel) or 0
    if requiredLevel > playerLevel then
        return false
    end

    local questLevel = tonumber(quest and (quest.questLevel or quest.level)) or playerLevel
    if questLevel < 0 then
        questLevel = playerLevel
    end
    local greenRange = 5
    if GetQuestGreenRange then
        local ok, value = pcall(GetQuestGreenRange, "player")
        if ok and tonumber(value) then
            greenRange = tonumber(value)
        end
    end
    return playerLevel - questLevel <= greenRange
end

function panelSearchFilters.PassesZones(quest)
    if not panelSearchFilters.starts and not panelSearchFilters.objectives and not panelSearchFilters.ends then
        return false
    end

    quest = ApplyQuestZoneMetadata(quest)
    if panelSearchFilters.starts and panelSearchFilters.ZoneSetContainsAny(quest and quest.startZoneIds) then
        return true
    end
    if panelSearchFilters.objectives and panelSearchFilters.ZoneSetContainsAny(quest and quest.objectiveZoneIds) then
        return true
    end
    if panelSearchFilters.ends and panelSearchFilters.ZoneSetContainsAny(quest and quest.endZoneIds) then
        return true
    end

    return false
end

function panelSearchFilters.PassesQuest(quest)
    panelSearchFilters.Ensure()
    quest = ApplyQuestZoneMetadata(quest)
    if quest.gameVersion == "sod" and CurrentDreamwayGameVersion() ~= "sod" then
        return false
    end
    if not panelSearchFilters.PassesCharacter(quest) then
        return false
    end
    if not panelSearchFilters.PassesType(quest) then
        return false
    end
    return true
end

HydrateQuestMetadata = function(quest)
    if not quest then
        return quest
    end

    quest.preQuestSingle = CloneNumberArray(quest.preQuestSingle)
    quest.preQuestGroup = CloneNumberArray(quest.preQuestGroup)
    quest.startZoneIds = CloneNumberArray(quest.startZoneIds)
    quest.objectiveZoneIds = CloneNumberArray(quest.objectiveZoneIds)
    quest.endZoneIds = CloneNumberArray(quest.endZoneIds)
    quest.zoneIds = CloneNumberArray(quest.zoneIds)
    quest.zones = CloneStringArray(quest.zones)
    quest.chainId = tonumber(quest.chainId)
    quest.chainName = quest.chainName and tostring(quest.chainName) or nil
    if quest.chainName == "" then
        quest.chainName = nil
    end
    quest.chainStep = tonumber(quest.chainStep)
    quest.chainLength = tonumber(quest.chainLength)
    quest.chainGroupId = tonumber(quest.chainGroupId)
    quest.chainGroupStep = tonumber(quest.chainGroupStep)
    quest.chainGroupSize = tonumber(quest.chainGroupSize)

    if not tonumber(quest.id) then
        return quest
    end

    local dbQuest = GetQuestieQuest(quest)
    if not dbQuest then
        ApplyQuestZoneMetadata(quest)
        return quest
    end

    local questName = quest.name and tostring(quest.name) or nil
    if not questName or questName == "" or questName:match("^Quest #%d+$") then
        quest.name = dbQuest.name or dbQuest.Name or quest.name
    end
    quest.questLevel = quest.questLevel or dbQuest.level or dbQuest.Level or dbQuest.questLevel
    quest.requiredLevel = quest.requiredLevel or dbQuest.requiredLevel or dbQuest.RequiredLevel
    if #quest.preQuestSingle == 0 then
        quest.preQuestSingle = CloneNumberArray(dbQuest.preQuestSingle or dbQuest.PreQuestSingle)
    end
    if #quest.preQuestGroup == 0 then
        quest.preQuestGroup = CloneNumberArray(dbQuest.preQuestGroup or dbQuest.PreQuestGroup)
    end

    ApplyQuestZoneMetadata(quest)
    return quest
end

local function CloneQuest(quest)
    return HydrateQuestMetadata({
        id = tonumber(quest and quest.id),
        name = quest and quest.name,
        requiredLevel = quest and quest.requiredLevel,
        questLevel = quest and quest.questLevel,
        category = quest and quest.category,
        preQuestSingle = CloneNumberArray(quest and quest.preQuestSingle),
        preQuestGroup = CloneNumberArray(quest and quest.preQuestGroup),
        startZoneIds = CloneNumberArray(quest and quest.startZoneIds),
        objectiveZoneIds = CloneNumberArray(quest and quest.objectiveZoneIds),
        endZoneIds = CloneNumberArray(quest and quest.endZoneIds),
        zoneIds = CloneNumberArray(quest and quest.zoneIds),
        zones = CloneStringArray(quest and quest.zones),
        chainId = tonumber(quest and quest.chainId),
        chainName = quest and quest.chainName,
        chainStep = tonumber(quest and quest.chainStep),
        chainLength = tonumber(quest and quest.chainLength),
        chainGroupId = tonumber(quest and quest.chainGroupId),
        chainGroupStep = tonumber(quest and quest.chainGroupStep),
        chainGroupSize = tonumber(quest and quest.chainGroupSize),
    })
end

local function BuildQuestFromQuestieId(questId)
    questId = tonumber(questId)
    if not questId then
        return nil
    end

    local quest = CloneQuest({ id = questId })
    if not quest or not quest.name or quest.name == "" or quest.name:match("^Quest #%d+$") then
        return nil
    end
    return quest
end

local function BuildAllQuestSearchCache()
    if allQuestSearchCache then
        return allQuestSearchCache
    end

    local records = DreamwayQuestZones and DreamwayQuestZones.quests
    if type(records) ~= "table" then
        return {}
    end

    local QuestieDB = ImportQuestieModule("QuestieDB")
    local cache = {}
    for questId, zoneRecord in pairs(records) do
        questId = tonumber(questId)
        if questId then
            local name = zoneRecord and zoneRecord.n
            local questLevel = tonumber(zoneRecord and zoneRecord.ql)
            local requiredLevel = tonumber(zoneRecord and zoneRecord.rl)
            local requiredRaceMask = tonumber(zoneRecord and zoneRecord.rm)
            local requiredClassMask = tonumber(zoneRecord and zoneRecord.cm)
            if (not name or name == "") and QuestieDB and QuestieDB.QueryQuestSingle then
                local ok, dbName = pcall(QuestieDB.QueryQuestSingle, questId, "name")
                if ok then
                    name = dbName
                end
            end
            if (not name or name == "") and QuestieDB and QuestieDB.GetQuest then
                local ok, dbQuest = pcall(QuestieDB.GetQuest, questId)
                if ok and dbQuest then
                    name = dbQuest.name or dbQuest.Name
                    questLevel = questLevel or tonumber(dbQuest.level or dbQuest.questLevel or dbQuest.Level)
                    requiredLevel = requiredLevel or tonumber(dbQuest.requiredLevel or dbQuest.RequiredLevel)
                    requiredRaceMask = requiredRaceMask or tonumber(dbQuest.requiredRaces or dbQuest.RequiredRaces)
                    requiredClassMask = requiredClassMask or tonumber(dbQuest.requiredClasses or dbQuest.RequiredClasses)
                end
            end
            if name and name ~= "" then
                local chainId = tonumber(zoneRecord and zoneRecord.c)
                local chainName = QuestChainName(chainId)
                cache[#cache + 1] = {
                    id = questId,
                    name = tostring(name),
                    questLevel = questLevel,
                    requiredLevel = requiredLevel,
                    chainId = chainId,
                    chainName = chainName,
                    chainStep = tonumber(zoneRecord and zoneRecord.cs),
                    chainLength = tonumber(zoneRecord and zoneRecord.cl),
                    chainGroupId = tonumber(zoneRecord and zoneRecord.cg),
                    chainGroupStep = tonumber(zoneRecord and zoneRecord.cgs),
                    chainGroupSize = tonumber(zoneRecord and zoneRecord.cgz),
                    preQuestGroup = CloneNumberArray(zoneRecord and zoneRecord.pg),
                    preQuestSingle = CloneNumberArray(zoneRecord and zoneRecord.ps),
                    startZoneIds = CloneNumberArray(zoneRecord and zoneRecord.s),
                    objectiveZoneIds = CloneNumberArray(zoneRecord and zoneRecord.o),
                    endZoneIds = CloneNumberArray(zoneRecord and zoneRecord.e),
                    zoneIds = CloneNumberArray(zoneRecord and zoneRecord.a),
                    requiredRaceMask = tonumber(zoneRecord and zoneRecord.rm) or requiredRaceMask or 0,
                    requiredClassMask = tonumber(zoneRecord and zoneRecord.cm) or requiredClassMask or 0,
                    typeIds = CloneStringArray(zoneRecord and zoneRecord.t),
                    gameVersion = zoneRecord and zoneRecord.gv,
                    normalized = string.lower(tostring(name)),
                }
            end
        end
    end

    table.sort(cache, function(a, b)
        local levelA = tonumber(a.questLevel or a.requiredLevel) or 999
        local levelB = tonumber(b.questLevel or b.requiredLevel) or 999
        if levelA ~= levelB then
            return levelA < levelB
        end
        if a.name == b.name then
            return a.id < b.id
        end
        return a.name < b.name
    end)

    allQuestSearchCache = cache
    return allQuestSearchCache
end

local function CloneBatch(batch)
    local clone = {
        id = batch and batch.id,
        name = batch and batch.name,
        autoName = batch and batch.autoName,
        expectedLevel = batch and batch.expectedLevel,
        expectedLevelManual = batch and batch.expectedLevelManual,
        expectedLevelOverride = batch and batch.expectedLevelOverride,
        zones = CloneStringArray(batch and batch.zones),
        quests = {},
    }

    for _, quest in ipairs(batch and batch.quests or {}) do
        clone.quests[#clone.quests + 1] = CloneQuest(quest)
    end

    return clone
end

local function CloneJourney(journey)
    local clone = {
        id = journey and journey.id,
        name = journey and journey.name,
        gameVersion = journey and journey.gameVersion,
        character = {
            race = journey and journey.character and journey.character.race,
            raceMask = journey and journey.character and journey.character.raceMask,
            faction = journey and journey.character and journey.character.faction,
            class = journey and journey.character and journey.character.class,
            classMask = journey and journey.character and journey.character.classMask,
        },
        batches = {},
        hiddenQuestIds = CloneNumberArray(journey and (journey.hiddenQuestIds or journey.unusedQuestIds)),
        hiddenQuests = {},
        unusedQuestIds = CloneNumberArray(journey and (journey.unusedQuestIds or journey.hiddenQuestIds)),
        unusedQuests = {},
    }

    for _, batch in ipairs(journey and journey.batches or {}) do
        clone.batches[#clone.batches + 1] = CloneBatch(batch)
    end

    for _, quest in ipairs(journey and journey.hiddenQuests or {}) do
        clone.hiddenQuests[#clone.hiddenQuests + 1] = CloneQuest(quest)
    end

    if #clone.hiddenQuests == 0 then
        for _, quest in ipairs(journey and journey.unusedQuests or {}) do
            clone.hiddenQuests[#clone.hiddenQuests + 1] = CloneQuest(quest)
        end
    end

    for _, quest in ipairs(journey and journey.unusedQuests or {}) do
        clone.unusedQuests[#clone.unusedQuests + 1] = CloneQuest(quest)
    end

    if #clone.unusedQuests == 0 then
        for _, quest in ipairs(clone.hiddenQuests) do
            clone.unusedQuests[#clone.unusedQuests + 1] = CloneQuest(quest)
        end
    end

    return clone
end

local function AddUniqueString(values, value)
    if not value or value == "" then
        return
    end

    for _, existing in ipairs(values) do
        if existing == value then
            return
        end
    end

    values[#values + 1] = value
end

local function QuestZoneNames(quest)
    quest = ApplyQuestZoneMetadata(quest)
    local names = {}
    for _, zoneName in ipairs(quest and quest.zones or {}) do
        AddUniqueString(names, tostring(zoneName))
    end
    if #names == 0 then
        for _, zoneName in ipairs(ZoneNamesFromIds(quest and (quest.zoneIds or quest.startZoneIds))) do
            AddUniqueString(names, zoneName)
        end
    end
    return names
end

local function BatchZoneNames(batch)
    local names = {}
    for _, quest in ipairs(batch and batch.quests or {}) do
        for _, zoneName in ipairs(QuestZoneNames(quest)) do
            AddUniqueString(names, zoneName)
        end
    end

    if #names == 0 then
        for _, zoneName in ipairs(batch and batch.zones or {}) do
            AddUniqueString(names, tostring(zoneName))
        end
    end

    return names
end

local function LooksLikeAutoBatchName(name)
    name = tostring(name or "")
    if name == "" then
        return true
    end
    if name:match("^%d+$") or name:match("^Batch%s+%d+$") then
        return true
    end
    return name:match("^.+%s+#%d+$") ~= nil
end

local function BatchAutoBaseName(batch)
    local zones = BatchZoneNames(batch)
    if #zones == 0 then
        return nil, zones
    elseif #zones == 1 then
        return zones[1], zones
    elseif #zones == 2 then
        return zones[1] .. " + " .. zones[2], zones
    end

    return zones[1] .. " + " .. zones[2] .. " + " .. tostring(#zones - 2) .. " more", zones
end

function SortJourneyBatchQuests(batch)
    if not batch or type(batch.quests) ~= "table" or #batch.quests < 2 then
        return
    end

    table.sort(batch.quests, function(a, b)
        local recordA = QuestZoneDbRecord(a and a.id)
        local recordB = QuestZoneDbRecord(b and b.id)
        local chainIdA = tonumber(a and a.chainId) or tonumber(recordA and recordA.c)
        local chainIdB = tonumber(b and b.chainId) or tonumber(recordB and recordB.c)
        local chainA = QuestChainSortInfo(chainIdA)
        local chainB = QuestChainSortInfo(chainIdB)
        local requiredA = tonumber(chainA and chainA.requiredLevel) or tonumber(a and a.requiredLevel) or 999
        local requiredB = tonumber(chainB and chainB.requiredLevel) or tonumber(b and b.requiredLevel) or 999
        if requiredA ~= requiredB then
            return requiredA < requiredB
        end

        local chainLevelA = tonumber(chainA and chainA.questLevel) or tonumber(a and a.questLevel) or 999
        local chainLevelB = tonumber(chainB and chainB.questLevel) or tonumber(b and b.questLevel) or 999
        if chainLevelA ~= chainLevelB then
            return chainLevelA < chainLevelB
        end

        local chainNameA = string.lower(tostring(chainA and chainA.name or a and a.chainName or a and a.name or ""))
        local chainNameB = string.lower(tostring(chainB and chainB.name or b and b.chainName or b and b.name or ""))
        if chainNameA ~= chainNameB then
            return chainNameA < chainNameB
        end

        local sortChainIdA = chainIdA or tonumber(a and a.id) or 999999
        local sortChainIdB = chainIdB or tonumber(b and b.id) or 999999
        if sortChainIdA ~= sortChainIdB then
            return sortChainIdA < sortChainIdB
        end

        local stepA = tonumber(a and a.chainStep) or tonumber(recordA and recordA.cs) or 9999
        local stepB = tonumber(b and b.chainStep) or tonumber(recordB and recordB.cs) or 9999
        if stepA ~= stepB then
            return stepA < stepB
        end

        local requiredQuestA = tonumber(a and a.requiredLevel) or tonumber(recordA and recordA.rl) or 999
        local requiredQuestB = tonumber(b and b.requiredLevel) or tonumber(recordB and recordB.rl) or 999
        if requiredQuestA ~= requiredQuestB then
            return requiredQuestA < requiredQuestB
        end

        return (tonumber(a and a.id) or 999999) < (tonumber(b and b.id) or 999999)
    end)
end

RefreshJourneyDerivedData = function(journey)
    if not journey or not journey.batches then
        return
    end

    SynchronizeJourneyHiddenQuests(journey)

    local rows = {}
    local baseCounts = {}
    for index, batch in ipairs(journey.batches) do
        for questIndex, quest in ipairs(batch.quests or {}) do
            batch.quests[questIndex] = HydrateQuestMetadata(quest)
        end
        SortJourneyBatchQuests(batch)
        batch.zones = BatchZoneNames(batch)
        batch.expectedLevel = BatchExpectedLevel(batch)

        local auto = batch.autoName == true or (batch.autoName ~= false and LooksLikeAutoBatchName(batch.name))
        if auto then
            local base, zones = BatchAutoBaseName(batch)
            rows[#rows + 1] = {
                batch = batch,
                index = index,
                base = base or "Batch",
                zones = zones,
            }
            baseCounts[base or "Batch"] = (baseCounts[base or "Batch"] or 0) + 1
        end
    end

    local seen = {}
    for _, row in ipairs(rows) do
        row.batch.autoName = true
        if row.base == "Batch" and (not row.zones or #row.zones == 0) then
            row.batch.name = "Batch " .. tostring(row.index)
        else
            local count = (seen[row.base] or 0) + 1
            seen[row.base] = count
            local needsNumber = (#row.zones == 1) or ((baseCounts[row.base] or 0) > 1)
            row.batch.name = needsNumber and (row.base .. " #" .. tostring(count)) or row.base
        end
    end

    for index, quest in ipairs(journey.hiddenQuests or {}) do
        journey.hiddenQuests[index] = HydrateQuestMetadata(quest)
    end
    for index, quest in ipairs(journey.unusedQuests or {}) do
        journey.unusedQuests[index] = HydrateQuestMetadata(quest)
    end
end

local function FindQuestInJourney(journey, questId)
    questId = tonumber(questId)
    if not questId then
        return nil
    end

    for batchIndexValue, batch in ipairs(journey and journey.batches or {}) do
        for questIndex, quest in ipairs(batch.quests or {}) do
            if tonumber(quest.id) == questId then
                return quest, "batch", batchIndexValue, questIndex
            end
        end
    end

    for questIndex, quest in ipairs(journey and journey.hiddenQuests or {}) do
        if tonumber(quest.id) == questId then
            return quest, "hidden", nil, questIndex
        end
    end

    for questIndex, quest in ipairs(journey and journey.unusedQuests or {}) do
        if tonumber(quest.id) == questId then
            return quest, "hidden", nil, questIndex
        end
    end

    return nil
end

local function QuestNameForValidation(journey, questId)
    local quest = FindQuestInJourney(journey, questId)
    if quest and quest.name and quest.name ~= "" then
        return quest.name .. " (#" .. tostring(questId) .. ")"
    end
    local dbQuest = GetQuestieQuest({ id = questId })
    local dbName = dbQuest and (dbQuest.name or dbQuest.Name)
    if dbName and dbName ~= "" then
        return tostring(dbName) .. " (#" .. tostring(questId) .. ")"
    end
    return "#" .. tostring(questId)
end

local function QuestNamesForValidation(journey, ids)
    local names = {}
    for _, questId in ipairs(ids or {}) do
        names[#names + 1] = QuestNameForValidation(journey, questId)
    end
    return table.concat(names, ", ")
end

local function QuestPrerequisiteFailure(journey, quest, availableIds)
    local missingGroup = {}
    for _, questId in ipairs(quest.preQuestGroup or {}) do
        questId = tonumber(questId)
        if questId and not availableIds[questId] then
            missingGroup[#missingGroup + 1] = questId
        end
    end

    if #missingGroup > 0 then
        return (quest.name or QuestDisplayName(quest)) .. " requires " .. QuestNamesForValidation(journey, missingGroup) .. " in the same or an earlier batch."
    end

    local singlePrereqs = CloneNumberArray(quest.preQuestSingle)
    if #singlePrereqs > 0 then
        local satisfied = false
        for _, questId in ipairs(singlePrereqs) do
            if availableIds[questId] then
                satisfied = true
                break
            end
        end

        if not satisfied then
            if #singlePrereqs == 1 then
                return (quest.name or QuestDisplayName(quest)) .. " requires " .. QuestNameForValidation(journey, singlePrereqs[1]) .. " in the same or an earlier batch."
            end
            return (quest.name or QuestDisplayName(quest)) .. " requires one of: " .. QuestNamesForValidation(journey, singlePrereqs) .. " in the same or an earlier batch."
        end
    end

    return nil
end

local function CompletedQuestIdSet()
    local completedIds = {}
    for _, questId in ipairs(DreamwayProfile and DreamwayProfile.completedQuestIds or {}) do
        questId = tonumber(questId)
        if questId then
            completedIds[questId] = true
        end
    end

    if Questie and Questie.db and Questie.db.char then
        for questId, isComplete in pairs(Questie.db.char.complete or {}) do
            questId = tonumber(questId)
            if questId and isComplete then
                completedIds[questId] = true
            end
        end
    end

    return completedIds
end

JourneyPrerequisiteWarnings = function(journey)
    local warnings = {}
    local firstMessage
    local availableIds = CompletedQuestIdSet()

    for _, batch in ipairs(journey and journey.batches or {}) do
        for _, quest in ipairs(batch.quests or {}) do
            local questId = tonumber(quest.id)
            if questId then
                availableIds[questId] = true
            end
        end

        for _, quest in ipairs(batch.quests or {}) do
            quest = HydrateQuestMetadata(quest)
            local questId = tonumber(quest.id)
            if questId then
                local message = QuestPrerequisiteFailure(journey, quest, availableIds)
                if message then
                    warnings[questId] = message
                    firstMessage = firstMessage or message
                end
            end
        end
    end

    return warnings, firstMessage
end

local function ValidateJourney(journey, baselineJourney)
    local allIds = {}
    local total = 0
    for _, batch in ipairs(journey and journey.batches or {}) do
        local batchSeen = {}
        for _, quest in ipairs(batch.quests or {}) do
            local questId = tonumber(quest.id)
            if questId then
                if batchSeen[questId] then
                    return false, 'Batch "' .. tostring(batch.name or "?") .. '" contains a duplicate quest.'
                end
                batchSeen[questId] = true
                allIds[questId] = (allIds[questId] or 0) + 1
                total = total + 1
            end
        end
    end

    for questId, count in pairs(allIds) do
        if count > 1 then
            return false, QuestNameForValidation(journey, questId) .. " is already assigned to another batch."
        end
    end

    for _, quest in ipairs(JourneyUnusedQuestRows(journey)) do
        local questId = tonumber(quest.id)
        if questId and allIds[questId] then
            return false, QuestNameForValidation(journey, questId) .. " cannot be both assigned and hidden."
        end
    end

    for index, batch in ipairs(journey and journey.batches or {}) do
        for _, quest in ipairs(batch.quests or {}) do
            quest = HydrateQuestMetadata(quest)
            if not quest.name or quest.name == "" then
                return false, "Unknown quest #" .. tostring(quest.id) .. " in Batch " .. tostring(index) .. "."
            end
        end
    end

    local warnings, firstMessage = JourneyPrerequisiteWarnings(journey)
    if baselineJourney then
        local baselineWarnings = JourneyPrerequisiteWarnings(baselineJourney)
        for _, batch in ipairs(journey and journey.batches or {}) do
            for _, quest in ipairs(batch.quests or {}) do
                local questId = tonumber(quest.id)
                if questId and warnings[questId] and not baselineWarnings[questId] then
                    return false, warnings[questId]
                end
            end
        end
    elseif firstMessage then
        return false, firstMessage
    end

    return true
end

local function RemoveQuestFromAssignedBatches(journey, questId)
    questId = tonumber(questId)
    if not questId then
        return
    end

    for _, batch in ipairs(journey and journey.batches or {}) do
        local nextQuests = {}
        for _, quest in ipairs(batch.quests or {}) do
            if tonumber(quest.id) ~= questId then
                nextQuests[#nextQuests + 1] = quest
            end
        end
        batch.quests = nextQuests
    end
end

local function RemoveQuestFromUnused(journey, questId)
    questId = tonumber(questId)
    if not questId then
        return
    end

    local nextIds = {}
    for _, id in ipairs(journey.unusedQuestIds or {}) do
        if tonumber(id) ~= questId then
            nextIds[#nextIds + 1] = tonumber(id)
        end
    end
    journey.unusedQuestIds = nextIds

    local nextQuests = {}
    for _, quest in ipairs(journey.unusedQuests or {}) do
        if tonumber(quest.id) ~= questId then
            nextQuests[#nextQuests + 1] = quest
        end
    end
    journey.unusedQuests = nextQuests

    nextIds = {}
    for _, id in ipairs(journey.hiddenQuestIds or {}) do
        if tonumber(id) ~= questId then
            nextIds[#nextIds + 1] = tonumber(id)
        end
    end
    journey.hiddenQuestIds = nextIds

    nextQuests = {}
    for _, quest in ipairs(journey.hiddenQuests or {}) do
        if tonumber(quest.id) ~= questId then
            nextQuests[#nextQuests + 1] = quest
        end
    end
    journey.hiddenQuests = nextQuests
end

local function AddQuestToUnused(journey, quest)
    local questId = tonumber(quest and quest.id)
    if not questId then
        return
    end

    journey.unusedQuestIds = journey.unusedQuestIds or {}
    journey.unusedQuests = journey.unusedQuests or {}
    journey.hiddenQuestIds = journey.hiddenQuestIds or {}
    journey.hiddenQuests = journey.hiddenQuests or {}
    RemoveQuestFromUnused(journey, questId)
    table.insert(journey.unusedQuestIds, 1, questId)
    table.insert(journey.unusedQuests, 1, CloneQuest(quest))
    table.insert(journey.hiddenQuestIds, 1, questId)
    table.insert(journey.hiddenQuests, 1, CloneQuest(quest))
end

local function EditableJourney()
    local activeJourneyId = DreamwayActiveJourneyId()
    if not DreamwayDB or not activeJourneyId then
        return nil, "Import a Journey before editing it in game."
    end

    local journey = DreamwayDB.journeys and DreamwayDB.journeys[activeJourneyId]
    if not journey or journey == fallbackJourney then
        return nil, "Import a Journey before editing it in game."
    end

    return journey
end

local function CommitJourneyCandidate(candidate, message)
    RefreshJourneyDerivedData(candidate)
    local baselineJourney = ActiveJourney()
    local ok, errorMessage = ValidateJourney(candidate, baselineJourney)
    if not ok then
        PanelSetStatus(errorMessage, false)
        return false
    end

    candidate.savedAt = ProfileRecorder.UpdatedAt(ProfileRecorder.ServerTimestamp())
    DreamwayDB.journeys[candidate.id] = candidate
    DreamwaySetActiveJourneyId(candidate.id)
    panelJourneyManager.selectedJourneyId = candidate.id
    SaveDb()
    ApplyUnusedQuestSuppression()
    RefreshDreamwayTracker()
    RefreshPanel()
    PanelSetStatus(message, true)
    return true
end

function DreamwayInsertBatchAfter(afterIndex, questId)
    local journey, errorMessage = EditableJourney()
    if not journey then
        PanelSetStatus(errorMessage, false)
        return false
    end

    local candidate = CloneJourney(journey)
    afterIndex = math.max(0, math.min(tonumber(afterIndex) or #candidate.batches, #candidate.batches))
    local newIndex = afterIndex + 1
    local batch = {
        id = "batch-" .. tostring(ProfileRecorder.ServerTimestamp()) .. "-" .. tostring(newIndex),
        name = tostring(newIndex),
        autoName = true,
        quests = {},
        zones = {},
    }

    questId = tonumber(questId)
    if questId then
        local existingQuest = FindQuestInJourney(candidate, questId)
        local quest = existingQuest or BuildQuestFromQuestieId(questId)
        if not quest then
            PanelSetStatus("Dreamway could not find that quest in Questie's database.", false)
            return false
        end
        RemoveQuestFromAssignedBatches(candidate, questId)
        RemoveQuestFromUnused(candidate, questId)
        batch.quests[1] = CloneQuest(quest)
    end

    table.insert(candidate.batches, newIndex, batch)
    batchIndex = newIndex
    return CommitJourneyCandidate(
        candidate,
        questId and ("Created Batch " .. tostring(newIndex) .. " and added " .. QuestDisplayName(batch.quests[1]) .. ".")
            or ("Created Batch " .. tostring(newIndex) .. ".")
    )
end

function DreamwayDeleteBatchAt(index)
    local journey, errorMessage = EditableJourney()
    if not journey then
        PanelSetStatus(errorMessage, false)
        return false
    end
    index = tonumber(index)
    if not index or not journey.batches[index] then
        PanelSetStatus("That batch no longer exists.", false)
        return false
    end

    local candidate = CloneJourney(journey)
    local removed = table.remove(candidate.batches, index)
    if #candidate.batches == 0 then
        candidate.batches[1] = {
            id = "batch-" .. tostring(ProfileRecorder.ServerTimestamp()),
            name = "1",
            autoName = true,
            quests = {},
            zones = {},
        }
    end
    batchIndex = math.max(1, math.min(index, #candidate.batches))
    return CommitJourneyCandidate(candidate, "Deleted " .. tostring(removed.name or ("Batch " .. tostring(index))) .. "; its quests are now unassigned.")
end

function DreamwayConfirmDeleteBatch(index)
    ProfileRecorder.pendingDeleteBatchIndex = index
    StaticPopupDialogs.DREAMWAY_DELETE_BATCH = StaticPopupDialogs.DREAMWAY_DELETE_BATCH or {
        text = "Delete this batch? Its quests will become unassigned. The deletion will be blocked if it breaks prerequisite ordering.",
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function()
            local pending = ProfileRecorder.pendingDeleteBatchIndex
            ProfileRecorder.pendingDeleteBatchIndex = nil
            if pending then DreamwayDeleteBatchAt(pending) end
        end,
        OnCancel = function()
            ProfileRecorder.pendingDeleteBatchIndex = nil
        end,
    }
    StaticPopup_Show("DREAMWAY_DELETE_BATCH")
end

local function MoveQuestInJourney(questId, targetType, targetIndex)
    local journey, errorMessage = EditableJourney()
    if not journey then
        PanelSetStatus(errorMessage, false)
        return false
    end

    questId = tonumber(questId)
    local existingQuest, sourceType, sourceBatchIndex = FindQuestInJourney(journey, questId)
    if targetType == "unassigned" and not existingQuest then
        PanelSetStatus("That quest is already unassigned.", nil)
        return false
    end

    local sourceQuest = existingQuest or BuildQuestFromQuestieId(questId)
    if not sourceQuest then
        PanelSetStatus("Dreamway could not find that quest in Questie's database.", false)
        return false
    end

    if sourceType == targetType and (targetType == "hidden" or sourceBatchIndex == targetIndex) then
        PanelSetStatus("That quest is already there.", nil)
        return false
    end

    local candidate = CloneJourney(journey)
    local quest = existingQuest and FindQuestInJourney(candidate, questId) or CloneQuest(sourceQuest)
    if not quest then
        PanelSetStatus("That quest could not be moved.", false)
        return false
    end

    RemoveQuestFromAssignedBatches(candidate, questId)
    RemoveQuestFromUnused(candidate, questId)

    if targetType == "unassigned" then
        return CommitJourneyCandidate(candidate, "Unassigned " .. (quest.name or QuestDisplayName(quest)) .. ".")
    end

    if targetType == "hidden" or targetType == "unused" then
        AddQuestToUnused(candidate, quest)
        return CommitJourneyCandidate(candidate, "Moved " .. (quest.name or QuestDisplayName(quest)) .. " to Hidden.")
    end

    local batch = candidate.batches and candidate.batches[targetIndex]
    if not batch then
        PanelSetStatus("That batch no longer exists.", false)
        return false
    end

    batch.quests[#batch.quests + 1] = CloneQuest(quest)
    batchIndex = targetIndex
    SaveDb()
    return CommitJourneyCandidate(candidate, "Moved " .. (quest.name or QuestDisplayName(quest)) .. " to " .. tostring(batch.name or ("Batch " .. tostring(targetIndex))) .. ".")
end

function PanelFrameIsMouseOver(frame)
    if not frame or not frame:IsShown() then
        return false
    end

    if frame.IsMouseOver then
        local ok, over = pcall(frame.IsMouseOver, frame)
        if ok and over then
            return true
        end
    end

    if MouseIsOver then
        local ok, over = pcall(MouseIsOver, frame)
        if ok and over then
            return true
        end
    end

    return false
end

function PanelDropTargetUnderCursor()
    for index = #panelDropTargets, 1, -1 do
        local target = panelDropTargets[index]
        if target and PanelFrameIsMouseOver(target.frame) then
            return target
        end
    end
    return nil
end

local function EnsurePanelDragGhost()
    if panelDragGhost then
        return panelDragGhost
    end

    panelDragGhost = CreateBackdropFrame("Dreamway_DragGhost", UIParent)
    panelDragGhost:SetFrameStrata("TOOLTIP")
    panelDragGhost:SetSize(180, 24)
    panelDragGhost:EnableMouse(false)
    SetFrameBackdrop(panelDragGhost, 0.02, 0.02, 0.025, 0.94, 0.75)

    panelDragGhost.label = CreateLabel(panelDragGhost, "GameFontHighlightSmall")
    panelDragGhost.label:SetPoint("LEFT", panelDragGhost, "LEFT", 8, 0)
    panelDragGhost.label:SetPoint("RIGHT", panelDragGhost, "RIGHT", -8, 0)
    panelDragGhost.label:SetWordWrap(false)
    panelDragGhost:Hide()

    return panelDragGhost
end

local function UpdatePanelDragGhost()
    if not panelDragGhost or not panelDragGhost:IsShown() then
        return
    end

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    panelDragGhost:ClearAllPoints()
    panelDragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (x / scale) + 14, (y / scale) - 12)
end

local function EndPanelQuestDrag()
    if panelDragGhost then
        panelDragGhost:Hide()
        panelDragGhost:SetScript("OnUpdate", nil)
    end

    local drag = panelDragState
    panelDragState = nil
    if not drag then
        return
    end

    local target = PanelDropTargetUnderCursor()
    if not target then
        PanelSetStatus("Drop a quest onto a batch or Hidden.", nil)
        return
    end

    if target.type == "newbatch" then
        DreamwayInsertBatchAfter(target.index, drag.questId)
    else
        MoveQuestInJourney(drag.questId, target.type, target.index)
    end
end

local function StartPanelQuestDrag(quest, source)
    local questId = tonumber(quest and quest.id)
    if not questId then
        return
    end

    panelDragState = {
        questId = questId,
        source = source,
    }

    if GameTooltip then
        GameTooltip:Hide()
    end

    local ghost = EnsurePanelDragGhost()
    ghost.label:SetText(quest.name or QuestDisplayName(quest))
    ghost:Show()
    ghost:SetScript("OnUpdate", UpdatePanelDragGhost)
    UpdatePanelDragGhost()
end

local function MakePanelQuestDraggable(button, quest, source)
    if not button or not quest or not quest.id then
        return
    end

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
        StartPanelQuestDrag(quest, source)
    end)
    button:SetScript("OnDragStop", EndPanelQuestDrag)
end

function JsonEncodeString(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\")
    value = value:gsub('"', '\\"')
    value = value:gsub("\n", "\\n")
    value = value:gsub("\r", "\\r")
    value = value:gsub("\t", "\\t")
    return '"' .. value .. '"'
end

function JsonEncodeNumber(value)
    value = tonumber(value)
    return value and tostring(value) or "null"
end

function JsonEncodeBoolean(value)
    return value and "true" or "false"
end

function JsonEncodeNumberArray(values)
    local parts = {}
    for _, value in ipairs(values or {}) do
        value = tonumber(value)
        if value then
            parts[#parts + 1] = tostring(value)
        end
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

function JsonEncodeStringArray(values)
    local parts = {}
    for _, value in ipairs(values or {}) do
        if value and value ~= "" then
            parts[#parts + 1] = JsonEncodeString(value)
        end
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

function JsonEncodeQuest(quest, flags)
    local hidden = flags == true or (type(flags) == "table" and flags.hidden)
    local unused = flags == true or (type(flags) == "table" and flags.unused)
    local parts = {
        '"id":' .. JsonEncodeNumber(quest.id),
        '"name":' .. JsonEncodeString(quest.name or ""),
        '"requiredLevel":' .. JsonEncodeNumber(quest.requiredLevel),
        '"questLevel":' .. JsonEncodeNumber(quest.questLevel),
        '"preQuestSingle":' .. JsonEncodeNumberArray(quest.preQuestSingle),
        '"preQuestGroup":' .. JsonEncodeNumberArray(quest.preQuestGroup),
        '"startZoneIds":' .. JsonEncodeNumberArray(quest.startZoneIds),
        '"objectiveZoneIds":' .. JsonEncodeNumberArray(quest.objectiveZoneIds),
        '"endZoneIds":' .. JsonEncodeNumberArray(quest.endZoneIds),
        '"zoneIds":' .. JsonEncodeNumberArray(quest.zoneIds),
        '"zones":' .. JsonEncodeStringArray(quest.zones),
    }

    if hidden then
        parts[#parts + 1] = '"hidden":true'
    end
    if unused then
        parts[#parts + 1] = '"unused":true'
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function JsonEncodeQuestArray(quests, flags)
    local parts = {}
    for _, quest in ipairs(quests or {}) do
        parts[#parts + 1] = JsonEncodeQuest(quest, flags)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

function JsonEncodeBatch(batch)
    local questIds = {}
    for _, quest in ipairs(batch.quests or {}) do
        local questId = tonumber(quest.id)
        if questId then
            questIds[#questIds + 1] = questId
        end
    end

    local expectedLevel = BatchExpectedLevel(batch)
    return table.concat({
        "{",
        '"id":' .. JsonEncodeString(batch.id or ""),
        ',"name":' .. JsonEncodeString(batch.name or ""),
        ',"autoName":' .. JsonEncodeBoolean(batch.autoName == true),
        ',"expectedLevel":' .. JsonEncodeNumber(expectedLevel),
        ',"expectedLevelManual":' .. JsonEncodeBoolean(batch.expectedLevelManual == true),
        ',"expectedLevelOverride":' .. JsonEncodeNumber(batch.expectedLevelOverride),
        ',"zones":' .. JsonEncodeStringArray(batch.zones),
        ',"questIds":' .. JsonEncodeNumberArray(questIds),
        ',"quests":' .. JsonEncodeQuestArray(batch.quests, false),
        "}",
    })
end

function JsonEncodeBatchArray(batches)
    local parts = {}
    for _, batch in ipairs(batches or {}) do
        parts[#parts + 1] = JsonEncodeBatch(batch)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function JourneyToJson(journey)
    RefreshJourneyDerivedData(journey)
    journey.savedAt = journey.savedAt or ProfileRecorder.UpdatedAt(ProfileRecorder.ServerTimestamp())

    local character = journey.character or {}
    local hiddenRows = JourneyUnusedQuestRows(journey)
    local hiddenIds = {}
    for _, quest in ipairs(hiddenRows) do
        local questId = tonumber(quest.id)
        if questId then
            hiddenIds[#hiddenIds + 1] = questId
        end
    end

    return table.concat({
        "{",
        '"schemaVersion":2',
        ',"app":"Dreamway"',
        ',"kind":"Journey"',
        ',"gameVersion":' .. JsonEncodeString(NormalizeDreamwayGameVersion(journey.gameVersion)),
        ',"savedAt":' .. JsonEncodeString(journey.savedAt),
        ',"id":' .. JsonEncodeString(journey.id or ("exported-" .. tostring(time()))),
        ',"name":' .. JsonEncodeString(journey.name or "Dreamway Journey"),
        ',"character":{',
            '"race":' .. JsonEncodeString(character.race or ""),
            ',"raceMask":' .. JsonEncodeNumber(character.raceMask),
            ',"faction":' .. JsonEncodeString(character.faction or ""),
            ',"class":' .. JsonEncodeString(character.class or ""),
            ',"classMask":' .. JsonEncodeNumber(character.classMask),
        "}",
        ',"hiddenQuestIds":' .. JsonEncodeNumberArray(hiddenIds),
        ',"hiddenQuests":' .. JsonEncodeQuestArray(hiddenRows, { hidden = true, unused = true }),
        ',"unusedQuestIds":' .. JsonEncodeNumberArray(hiddenIds),
        ',"unusedQuests":' .. JsonEncodeQuestArray(hiddenRows, { hidden = true, unused = true }),
        ',"batches":' .. JsonEncodeBatchArray(journey.batches),
        "}",
    })
end

function JourneyToDenseString(journey)
    RefreshJourneyDerivedData(journey)
    journey.savedAt = journey.savedAt or ProfileRecorder.UpdatedAt(ProfileRecorder.ServerTimestamp())
    local character = journey.character or {}
    local batchParts = {}
    for _, batch in ipairs(journey.batches or {}) do
        local questIds = {}
        for _, quest in ipairs(batch.quests or {}) do
            local questId = tonumber(quest and quest.id)
            if questId then
                questIds[#questIds + 1] = questId
            end
        end
        local storedName = batch.autoName == true and "" or tostring(batch.name or "")
        local expectedLevelOverride = batch.expectedLevelManual == true and tonumber(batch.expectedLevelOverride) or nil
        if not expectedLevelOverride or expectedLevelOverride <= 0 then
            expectedLevelOverride = 0
        end
        batchParts[#batchParts + 1] = table.concat({
            DreamwayDenseEncode(storedName),
            tostring(expectedLevelOverride),
            table.concat(questIds, ","),
        }, "~")
    end

    local hiddenIds = {}
    for _, quest in ipairs(JourneyUnusedQuestRows(journey)) do
        local questId = tonumber(quest and quest.id)
        if questId then
            hiddenIds[#hiddenIds + 1] = questId
        end
    end

    return table.concat({
        "DWJ2",
        DreamwayDenseEncode(journey.id or ("exported-" .. tostring(time()))),
        DreamwayDenseEncode(journey.name or "Dreamway Journey"),
        tostring(tonumber(character.raceMask) or 0),
        tostring(tonumber(character.classMask) or 0),
        table.concat(batchParts, ";"),
        table.concat(hiddenIds, ","),
        NormalizeDreamwayGameVersion(journey.gameVersion),
        character.faction == "Alliance" and "a" or character.faction == "Horde" and "h" or "*",
        DreamwayDenseEncode(journey.savedAt),
    }, ":")
end

local function ShowJourneyExportArea(selectedJourney)
    local journey, errorMessage = selectedJourney, nil
    if not journey then
        journey, errorMessage = EditableJourney()
    end
    if not journey then
        PanelSetStatus(errorMessage, false)
        return
    end
    local journeyId = journey.id
    local currentJourney = journeyId and DreamwayDB and DreamwayDB.journeys and DreamwayDB.journeys[journeyId]
    journey = currentJourney or journey
    SynchronizeJourneyHiddenQuests(journey)
    journey.savedAt = ProfileRecorder.UpdatedAt(ProfileRecorder.ServerTimestamp())
    SaveDb()

    if panelImportArea then
        panelImportArea:Hide()
    end

    local hiddenCount = #JourneyUnusedQuestRows(journey)
    local text = JourneyToDenseString(journey)
    if panelExportEditBox then
        panelExportEditBox:SetText(text)
        panelExportArea:Show()
        panelExportEditBox:SetFocus()
        panelExportEditBox:HighlightText()
    end

    PanelSetStatus(
        "Exported current " .. tostring(journey.name or "Journey") .. " state (" .. tostring(hiddenCount) .. " Hidden).",
        true
    )
end

function DreamwayGameVersionLabel(value)
    value = NormalizeDreamwayGameVersion(value)
    if value == "sod" then
        return "Season of Discovery"
    end
    if value == "tbc" then
        return "The Burning Crusade"
    end
    if value == "wotlk" then
        return "Wrath of the Lich King"
    end
    return "Classic Era"
end

function DreamwayJourneyRaceOptions(gameVersion)
    local options = {
        { n = "All races", m = 0, f = "all" },
        { n = "Human", m = 1, f = "Alliance" },
        { n = "Dwarf", m = 4, f = "Alliance" },
        { n = "Night Elf", m = 8, f = "Alliance" },
        { n = "Gnome", m = 64, f = "Alliance" },
        { n = "Orc", m = 2, f = "Horde" },
        { n = "Undead", m = 16, f = "Horde" },
        { n = "Tauren", m = 32, f = "Horde" },
        { n = "Troll", m = 128, f = "Horde" },
    }
    gameVersion = NormalizeDreamwayGameVersion(gameVersion)
    if gameVersion == "tbc" or gameVersion == "wotlk" then
        options[#options + 1] = { n = "Draenei", m = 1024, f = "Alliance" }
        options[#options + 1] = { n = "Blood Elf", m = 512, f = "Horde" }
    end
    return options
end

function DreamwayJourneyClassOptions(gameVersion)
    local options = {
        { n = "All classes", m = 0 },
        { n = "Warrior", m = 1 },
        { n = "Paladin", m = 2 },
        { n = "Hunter", m = 4 },
        { n = "Rogue", m = 8 },
        { n = "Priest", m = 16 },
        { n = "Shaman", m = 64 },
        { n = "Mage", m = 128 },
        { n = "Warlock", m = 256 },
        { n = "Druid", m = 1024 },
    }
    if NormalizeDreamwayGameVersion(gameVersion) == "wotlk" then
        table.insert(options, 7, { n = "Death Knight", m = 32 })
    end
    return options
end

function DreamwayJourneyRaceLabel(journey)
    local character = journey and journey.character or {}
    local mask = tonumber(character.raceMask) or 0
    for _, option in ipairs(DreamwayJourneyRaceOptions(journey and journey.gameVersion)) do
        if tonumber(option.m) == mask then
            return option.n
        end
    end
    return character.race and character.race ~= "" and character.race or (mask > 0 and ("Race mask " .. tostring(mask)) or "All races")
end

function DreamwayJourneyClassLabel(journey)
    local character = journey and journey.character or {}
    local mask = tonumber(character.classMask) or 0
    for _, option in ipairs(DreamwayJourneyClassOptions(journey and journey.gameVersion)) do
        if tonumber(option.m) == mask then
            return option.n
        end
    end
    return character.class and character.class ~= "" and character.class or (mask > 0 and ("Class mask " .. tostring(mask)) or "All classes")
end

function DreamwayJourneyFactionLabel(journey)
    local faction = journey and journey.character and journey.character.faction or "all"
    if faction == "Alliance" or faction == "Horde" then
        return faction
    end
    return "All factions"
end

function DreamwayJourneyMetadataSummary(journey)
    if not journey or journey == fallbackJourney then
        return "No imported Journey active"
    end
    return table.concat({
        DreamwayGameVersionLabel(journey.gameVersion),
        DreamwayJourneyFactionLabel(journey),
        DreamwayJourneyRaceLabel(journey),
        DreamwayJourneyClassLabel(journey),
    }, "  |  ")
end

function DreamwaySortedJourneys()
    local journeys = {}
    for _, journey in pairs(DreamwayDB and DreamwayDB.journeys or {}) do
        if journey and journey.id then
            journeys[#journeys + 1] = journey
        end
    end
    table.sort(journeys, function(a, b)
        local nameA = string.lower(tostring(a.name or a.id or ""))
        local nameB = string.lower(tostring(b.name or b.id or ""))
        if nameA == nameB then
            return tostring(a.id) < tostring(b.id)
        end
        return nameA < nameB
    end)
    return journeys
end

function DreamwayManagerSelectedJourney()
    local journeyId = panelJourneyManager.selectedJourneyId or DreamwayActiveJourneyId()
    local journey = journeyId and DreamwayDB and DreamwayDB.journeys and DreamwayDB.journeys[journeyId]
    if journey then
        panelJourneyManager.selectedJourneyId = journey.id
        return journey
    end
    local journeys = DreamwaySortedJourneys()
    journey = journeys[1]
    panelJourneyManager.selectedJourneyId = journey and journey.id or nil
    return journey
end

function DreamwayCloseJourneyMetadataMenu()
    local dropDown = GetQuestieDropDown()
    if dropDown and dropDown.CloseDropDownMenus then
        pcall(dropDown.CloseDropDownMenus, dropDown)
    end
    panelJourneyManager.openMenuButton = nil
    panelJourneyManager.openMenuKind = nil
end

function DreamwaySetJourneyMetadata(kind, option)
    local journey = DreamwayManagerSelectedJourney()
    if not journey or not option then
        return
    end
    DreamwayCloseJourneyMetadataMenu()
    journey.character = journey.character or {}

    if kind == "faction" then
        journey.character.faction = option.value
        local raceMask = tonumber(journey.character.raceMask) or 0
        if raceMask > 0 and option.value ~= "all" then
            for _, race in ipairs(DreamwayJourneyRaceOptions(journey.gameVersion)) do
                if tonumber(race.m) == raceMask and race.f ~= option.value then
                    journey.character.race = ""
                    journey.character.raceMask = 0
                    break
                end
            end
        end
    elseif kind == "race" then
        journey.character.race = option.m == 0 and "" or option.n
        journey.character.raceMask = option.m
        if option.f and option.f ~= "all" then
            journey.character.faction = option.f
        end
    elseif kind == "class" then
        journey.character.class = option.m == 0 and "" or option.n
        journey.character.classMask = option.m
    end

    journey.savedAt = ProfileRecorder.UpdatedAt(ProfileRecorder.ServerTimestamp())
    SaveDb()
    if RefreshPanel then
        RefreshPanel()
    end
    DreamwayRefreshJourneyManager()
    PanelSetStatus("Updated " .. tostring(journey.name or "Journey") .. " metadata.", true)
end

function DreamwayShowJourneyMetadataMenu(button, kind)
    local journey = DreamwayManagerSelectedJourney()
    local dropDown = GetQuestieDropDown()
    if not journey or not dropDown or not dropDown.EasyMenu then
        return
    end

    local toggleClosed = panelJourneyManager.openMenuButton == button
    DreamwayCloseJourneyMetadataMenu()
    if toggleClosed then
        return
    end

    if not panelJourneyManager.menuFrame then
        if dropDown.Create_UIDropDownMenu then
            panelJourneyManager.menuFrame = dropDown:Create_UIDropDownMenu("Dreamway_JourneyMetadataMenu", UIParent)
        else
            panelJourneyManager.menuFrame = CreateFrame("Frame", "Dreamway_JourneyMetadataMenu", UIParent, "UIDropDownMenuTemplate")
        end
    end

    local menu = {}
    if kind == "faction" then
        for _, option in ipairs({
            { text = "All factions", value = "all" },
            { text = "Alliance", value = "Alliance" },
            { text = "Horde", value = "Horde" },
        }) do
            local selectedOption = option
            menu[#menu + 1] = {
                text = option.text,
                checked = DreamwayJourneyFactionLabel(journey) == option.text,
                func = function()
                    DreamwaySetJourneyMetadata("faction", selectedOption)
                end,
            }
        end
    elseif kind == "race" then
        for _, option in ipairs(DreamwayJourneyRaceOptions(journey.gameVersion)) do
            local selectedOption = option
            menu[#menu + 1] = {
                text = option.n,
                checked = (tonumber(journey.character and journey.character.raceMask) or 0) == tonumber(option.m),
                func = function()
                    DreamwaySetJourneyMetadata("race", selectedOption)
                end,
            }
        end
    elseif kind == "class" then
        for _, option in ipairs(DreamwayJourneyClassOptions(journey.gameVersion)) do
            local selectedOption = option
            menu[#menu + 1] = {
                text = option.n,
                checked = (tonumber(journey.character and journey.character.classMask) or 0) == tonumber(option.m),
                func = function()
                    DreamwaySetJourneyMetadata("class", selectedOption)
                end,
            }
        end
    end

    panelJourneyManager.openMenuButton = button
    panelJourneyManager.openMenuKind = kind
    dropDown:EasyMenu(menu, panelJourneyManager.menuFrame, button, 0, 0, "MENU")
end

function DreamwayActivateManagedJourney()
    DreamwayCloseJourneyMetadataMenu()
    local journey = DreamwayManagerSelectedJourney()
    if not journey then
        return
    end
    DreamwaySetActiveJourneyId(journey.id)
    batchIndex = 1
    SaveDb()
    ApplyUnusedQuestSuppression()
    RefreshDreamwayTracker()
    RefreshPanel()
    DreamwayRefreshJourneyManager()
    PanelSetStatus("Activated " .. tostring(journey.name or "Journey") .. ".", true)
end

function DreamwayShowCreateJourney()
    DreamwayCloseJourneyMetadataMenu()
    if panelJourneyManager.confirmFrame then
        panelJourneyManager.confirmFrame:Hide()
    end
    if panelJourneyManager.createFrame then
        panelJourneyManager.createError:SetText("")
        panelJourneyManager.createEditBox:SetText("")
        panelJourneyManager.createFrame:Show()
        panelJourneyManager.createEditBox:SetFocus()
    end
end

function DreamwayCreateNewJourney()
    local name = panelJourneyManager.createEditBox and panelJourneyManager.createEditBox:GetText() or ""
    name = tostring(name):match("^%s*(.-)%s*$") or ""
    if name == "" then
        panelJourneyManager.createError:SetText("Enter a Journey name.")
        return
    end

    local idBase = "addon-" .. tostring(time and time() or 0)
    local id = idBase
    local suffix = 2
    while DreamwayDB.journeys[id] do
        id = idBase .. "-" .. tostring(suffix)
        suffix = suffix + 1
    end

    local raceName = UnitRace and select(1, UnitRace("player")) or ""
    local className = UnitClass and select(1, UnitClass("player")) or ""
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "all"
    local raceMask = 0
    local classMask = 0
    for _, option in ipairs(DreamwayJourneyRaceOptions(CurrentDreamwayGameVersion())) do
        if option.n == raceName then
            raceMask = option.m
            break
        end
    end
    for _, option in ipairs(DreamwayJourneyClassOptions(CurrentDreamwayGameVersion())) do
        if option.n == className then
            classMask = option.m
            break
        end
    end

    local journey = {
        id = id,
        name = name,
        savedAt = ProfileRecorder.UpdatedAt(ProfileRecorder.ServerTimestamp()),
        gameVersion = CurrentDreamwayGameVersion(),
        character = {
            race = raceName,
            raceMask = raceMask,
            faction = faction,
            class = className,
            classMask = classMask,
        },
        batches = {
            {
                id = "batch-1",
                name = "Batch 1",
                autoName = true,
                quests = {},
                zones = {},
            },
        },
        hiddenQuestIds = {},
        hiddenQuests = {},
        unusedQuestIds = {},
        unusedQuests = {},
    }

    RefreshJourneyDerivedData(journey)
    DreamwayDB.journeys[id] = journey
    DreamwaySetActiveJourneyId(id)
    panelJourneyManager.selectedJourneyId = id
    batchIndex = 1
    SaveDb()
    panelJourneyManager.createEditBox:ClearFocus()
    panelJourneyManager.createFrame:Hide()
    ApplyUnusedQuestSuppression()
    RefreshDreamwayTracker()
    RefreshPanel()
    DreamwayRefreshJourneyManager()
    PanelSetStatus("Created and activated " .. name .. ".", true)
end

function DreamwayShowDeleteJourneyConfirmation()
    local journey = DreamwayManagerSelectedJourney()
    if not journey or not panelJourneyManager.confirmFrame then
        return
    end
    DreamwayCloseJourneyMetadataMenu()
    if panelJourneyManager.createFrame then
        panelJourneyManager.createFrame:Hide()
    end
    panelJourneyManager.pendingDeleteJourneyId = journey.id
    panelJourneyManager.confirmText:SetText("Delete " .. tostring(journey.name or journey.id) .. "?\n\nThis cannot be undone unless you import the Journey again.")
    panelJourneyManager.confirmFrame:Show()
end

function DreamwayDeleteManagedJourney()
    local journeyId = panelJourneyManager.pendingDeleteJourneyId
    local journey = journeyId and DreamwayDB.journeys[journeyId]
    if not journey then
        if panelJourneyManager.confirmFrame then
            panelJourneyManager.confirmFrame:Hide()
        end
        return
    end

    local journeyName = tostring(journey.name or journeyId)
    local wasActive = DreamwayActiveJourneyId() == journeyId
    DreamwayDB.journeys[journeyId] = nil
    panelJourneyManager.pendingDeleteJourneyId = nil
    panelJourneyManager.selectedJourneyId = nil
    if wasActive then
        local remaining = DreamwaySortedJourneys()
        local nextJourneyId = remaining[1] and remaining[1].id or nil
        DreamwaySetActiveJourneyId(nextJourneyId)
        panelJourneyManager.selectedJourneyId = nextJourneyId
        batchIndex = 1
    end
    SaveDb()
    panelJourneyManager.confirmFrame:Hide()
    ApplyUnusedQuestSuppression()
    RefreshDreamwayTracker()
    RefreshPanel()
    DreamwayRefreshJourneyManager()
    PanelSetStatus("Deleted " .. journeyName .. ".", true)
end

function DreamwayRefreshJourneyManager()
    if not panelJourneyManager.frame then
        return
    end

    local journeys = DreamwaySortedJourneys()
    local selected = DreamwayManagerSelectedJourney()
    for index, journey in ipairs(journeys) do
        local journeyId = journey.id
        local row = panelJourneyManager.rows[index]
        if not row then
            row = CreateTinyButton(panelJourneyManager.listContent, "", 238)
            row:SetHeight(24)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.label:SetPoint("RIGHT", row, "RIGHT", -52, 0)
            row.label:SetJustifyH("LEFT")
            row.label:SetWordWrap(false)
            row.activeLabel = CreateLabel(row, "GameFontHighlightSmall")
            row.activeLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.activeLabel:SetWidth(40)
            row.activeLabel:SetJustifyH("RIGHT")
            row.activeLabel:SetText("Active")
            row.activeLabel:SetTextColor(0.35, 1, 0.35)
            panelJourneyManager.rows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panelJourneyManager.listContent, "TOPLEFT", 0, -((index - 1) * 28))
        row.label:SetText(tostring(journey.name or journeyId))
        row.activeLabel:SetShown(journeyId == DreamwayActiveJourneyId())
        row:SetActive(selected and journeyId == selected.id)
        row:SetScript("OnClick", function()
            DreamwayCloseJourneyMetadataMenu()
            panelJourneyManager.selectedJourneyId = journeyId
            DreamwayRefreshJourneyManager()
        end)
        row:Show()
    end
    for index = #journeys + 1, #panelJourneyManager.rows do
        panelJourneyManager.rows[index]:Hide()
    end
    panelJourneyManager.listContent:SetHeight(math.max(24, #journeys * 28))

    local hasSelected = selected ~= nil
    panelJourneyManager.emptyText:SetShown(#journeys == 0)
    panelJourneyManager.detailFrame:SetShown(hasSelected)
    if hasSelected then
        panelJourneyManager.exportButton:Enable()
    else
        panelJourneyManager.exportButton:Disable()
    end
    if hasSelected and selected.id ~= DreamwayActiveJourneyId() then
        panelJourneyManager.activateButton:Enable()
    else
        panelJourneyManager.activateButton:Disable()
    end
    if not hasSelected then
        return
    end

    selected.character = selected.character or {}
    local questCount = 0
    for _, batch in ipairs(selected.batches or {}) do
        questCount = questCount + #(batch.quests or {})
    end
    local hiddenCount = #(selected.hiddenQuestIds or selected.unusedQuestIds or {})
    panelJourneyManager.nameText:SetText(selected.name or selected.id)
    panelJourneyManager.idText:SetText("ID: " .. tostring(selected.id or "Unknown"))
    panelJourneyManager.versionValue:SetText(DreamwayGameVersionLabel(selected.gameVersion) .. " (fixed)")
    panelJourneyManager.factionButton.label:SetText(DreamwayJourneyFactionLabel(selected) .. "  v")
    panelJourneyManager.raceButton.label:SetText(DreamwayJourneyRaceLabel(selected) .. "  v")
    panelJourneyManager.classButton.label:SetText(DreamwayJourneyClassLabel(selected) .. "  v")
    local savedText = selected.savedAt and selected.savedAt ~= "" and ("  |  Saved " .. tostring(selected.savedAt)) or ""
    panelJourneyManager.countText:SetText(tostring(#(selected.batches or {})) .. " batches  |  " .. tostring(questCount) .. " assigned quests  |  " .. tostring(hiddenCount) .. " hidden" .. savedText)
    local isActive = selected.id == DreamwayActiveJourneyId()
    panelJourneyManager.activeText:SetText(isActive and "Currently active" or "Not active")
    panelJourneyManager.activeText:SetTextColor(isActive and 0.35 or 0.75, isActive and 1 or 0.75, isActive and 0.35 or 0.75)
end

function DreamwayCreateJourneyManager()
    local frame = CreateBackdropFrame("Dreamway_JourneyManager", panelFrame)
    frame:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 18, -58)
    frame:SetPoint("BOTTOMRIGHT", panelFrame, "BOTTOMRIGHT", -18, 24)
    frame:SetFrameLevel(panelFrame:GetFrameLevel() + 8)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", DreamwayCloseJourneyMetadataMenu)
    frame:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    SetFrameBackdrop(frame, 0.01, 0.01, 0.012, 0.98, 0.72)
    panelJourneyManager.frame = frame
    panelFrame:HookScript("OnMouseDown", DreamwayCloseJourneyMetadataMenu)
    if WorldFrame and not panelJourneyManager.worldMouseHooked then
        WorldFrame:HookScript("OnMouseDown", DreamwayCloseJourneyMetadataMenu)
        panelJourneyManager.worldMouseHooked = true
    end

    frame.title = CreateLabel(frame, "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    frame.title:SetText("Manage Journeys")
    frame.title:SetTextColor(1, 0.82, 0.12)

    panelJourneyManager.exportButton = CreateTinyButton(frame, "Export Selected", 104)
    panelJourneyManager.exportButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
    panelJourneyManager.exportButton:SetScript("OnClick", function()
        DreamwayCloseJourneyMetadataMenu()
        ShowJourneyExportArea(DreamwayManagerSelectedJourney())
    end)

    panelJourneyManager.importButton = CreateTinyButton(frame, "Import Journey", 96)
    panelJourneyManager.importButton:SetPoint("RIGHT", panelJourneyManager.exportButton, "LEFT", -8, 0)
    panelJourneyManager.importButton:SetScript("OnClick", function()
        DreamwayCloseJourneyMetadataMenu()
        if panelExportArea then
            panelExportArea:Hide()
        end
        panelImportArea:Show()
        panelImportEditBox:SetFocus()
    end)

    panelJourneyManager.createButton = CreateTinyButton(frame, "Create Journey", 96)
    panelJourneyManager.createButton:SetPoint("RIGHT", panelJourneyManager.importButton, "LEFT", -8, 0)
    panelJourneyManager.createButton:SetScript("OnClick", DreamwayShowCreateJourney)

    local listFrame = CreateBackdropFrame(nil, frame)
    listFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -42)
    listFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
    listFrame:SetWidth(292)
    listFrame:EnableMouse(true)
    listFrame:SetScript("OnMouseDown", DreamwayCloseJourneyMetadataMenu)
    SetFrameBackdrop(listFrame, 0.02, 0.02, 0.025, 0.88, 0.35)

    local listScroll = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 8, -8)
    listScroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -28, 8)
    panelJourneyManager.listContent = CreateFrame("Frame", nil, listScroll)
    panelJourneyManager.listContent:SetSize(238, 24)
    listScroll:SetScrollChild(panelJourneyManager.listContent)

    panelJourneyManager.emptyText = CreateLabel(listFrame, "GameFontDisableSmall")
    panelJourneyManager.emptyText:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 12, -12)
    panelJourneyManager.emptyText:SetText("No Journeys imported yet.")

    local detail = CreateBackdropFrame(nil, frame)
    detail:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 12, 0)
    detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    detail:EnableMouse(true)
    detail:SetScript("OnMouseDown", DreamwayCloseJourneyMetadataMenu)
    SetFrameBackdrop(detail, 0.02, 0.02, 0.025, 0.88, 0.35)
    panelJourneyManager.detailFrame = detail

    panelJourneyManager.nameText = CreateLabel(detail, "GameFontNormalLarge")
    panelJourneyManager.nameText:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -16)
    panelJourneyManager.nameText:SetPoint("RIGHT", detail, "RIGHT", -16, 0)
    panelJourneyManager.nameText:SetWordWrap(false)

    panelJourneyManager.idText = CreateLabel(detail, "GameFontDisableSmall")
    panelJourneyManager.idText:SetPoint("TOPLEFT", panelJourneyManager.nameText, "BOTTOMLEFT", 0, -5)

    local versionLabel = CreateLabel(detail, "GameFontHighlightSmall")
    versionLabel:SetPoint("TOPLEFT", panelJourneyManager.idText, "BOTTOMLEFT", 0, -22)
    versionLabel:SetText("Game version")
    versionLabel:SetTextColor(0.65, 0.65, 0.65)
    panelJourneyManager.versionValue = CreateLabel(detail, "GameFontHighlight")
    panelJourneyManager.versionValue:SetPoint("TOPLEFT", versionLabel, "BOTTOMLEFT", 0, -5)

    local factionLabel = CreateLabel(detail, "GameFontHighlightSmall")
    factionLabel:SetPoint("TOPLEFT", panelJourneyManager.versionValue, "BOTTOMLEFT", 0, -24)
    factionLabel:SetText("Faction")
    factionLabel:SetTextColor(0.65, 0.65, 0.65)
    panelJourneyManager.factionButton = CreateTinyButton(detail, "", 190)
    panelJourneyManager.factionButton:SetHeight(24)
    panelJourneyManager.factionButton:SetPoint("TOPLEFT", factionLabel, "BOTTOMLEFT", 0, -5)
    panelJourneyManager.factionButton:SetScript("OnClick", function(self)
        DreamwayShowJourneyMetadataMenu(self, "faction")
    end)

    local raceLabel = CreateLabel(detail, "GameFontHighlightSmall")
    raceLabel:SetPoint("TOPLEFT", factionLabel, "TOPLEFT", 220, 0)
    raceLabel:SetText("Race")
    raceLabel:SetTextColor(0.65, 0.65, 0.65)
    panelJourneyManager.raceButton = CreateTinyButton(detail, "", 190)
    panelJourneyManager.raceButton:SetHeight(24)
    panelJourneyManager.raceButton:SetPoint("TOPLEFT", raceLabel, "BOTTOMLEFT", 0, -5)
    panelJourneyManager.raceButton:SetScript("OnClick", function(self)
        DreamwayShowJourneyMetadataMenu(self, "race")
    end)

    local classLabel = CreateLabel(detail, "GameFontHighlightSmall")
    classLabel:SetPoint("TOPLEFT", raceLabel, "TOPLEFT", 220, 0)
    classLabel:SetText("Class")
    classLabel:SetTextColor(0.65, 0.65, 0.65)
    panelJourneyManager.classButton = CreateTinyButton(detail, "", 190)
    panelJourneyManager.classButton:SetHeight(24)
    panelJourneyManager.classButton:SetPoint("TOPLEFT", classLabel, "BOTTOMLEFT", 0, -5)
    panelJourneyManager.classButton:SetScript("OnClick", function(self)
        DreamwayShowJourneyMetadataMenu(self, "class")
    end)

    panelJourneyManager.countText = CreateLabel(detail, "GameFontHighlightSmall")
    panelJourneyManager.countText:SetPoint("TOPLEFT", factionLabel, "BOTTOMLEFT", 0, -58)
    panelJourneyManager.countText:SetTextColor(0.75, 0.75, 0.75)

    panelJourneyManager.activeText = CreateLabel(detail, "GameFontHighlight")
    panelJourneyManager.activeText:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 16, 18)

    panelJourneyManager.activateButton = CreateTinyButton(detail, "Make Active", 90)
    panelJourneyManager.activateButton:SetHeight(24)
    panelJourneyManager.activateButton:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -16, 14)
    panelJourneyManager.activateButton:SetScript("OnClick", DreamwayActivateManagedJourney)

    panelJourneyManager.deleteButton = CreateTinyButton(detail, "Delete Journey", 96)
    panelJourneyManager.deleteButton:SetHeight(24)
    panelJourneyManager.deleteButton:SetPoint("RIGHT", panelJourneyManager.activateButton, "LEFT", -8, 0)
    panelJourneyManager.deleteButton:SetBackdropColor(0.24, 0.025, 0.025, 0.92)
    panelJourneyManager.deleteButton:SetBackdropBorderColor(0.9, 0.2, 0.18, 0.8)
    panelJourneyManager.deleteButton.label:SetTextColor(1, 0.38, 0.32)
    panelJourneyManager.deleteButton:SetScript("OnClick", DreamwayShowDeleteJourneyConfirmation)

    local createFrame = CreateBackdropFrame(nil, frame)
    createFrame:SetSize(430, 176)
    createFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)
    createFrame:SetFrameLevel(frame:GetFrameLevel() + 4)
    createFrame:EnableMouse(true)
    SetFrameBackdrop(createFrame, 0.015, 0.015, 0.02, 0.99, 0.85)
    panelJourneyManager.createFrame = createFrame

    local createTitle = CreateLabel(createFrame, "GameFontNormalLarge")
    createTitle:SetPoint("TOPLEFT", createFrame, "TOPLEFT", 16, -14)
    createTitle:SetText("Create Journey")
    createTitle:SetTextColor(1, 0.82, 0.12)

    local createLabel = CreateLabel(createFrame, "GameFontHighlightSmall")
    createLabel:SetPoint("TOPLEFT", createTitle, "BOTTOMLEFT", 0, -14)
    createLabel:SetText("Journey name")

    panelJourneyManager.createEditBox = CreateFrame("EditBox", nil, createFrame, BackdropTemplateMixin and "BackdropTemplate")
    panelJourneyManager.createEditBox:SetPoint("TOPLEFT", createLabel, "BOTTOMLEFT", 0, -6)
    panelJourneyManager.createEditBox:SetPoint("RIGHT", createFrame, "RIGHT", -16, 0)
    panelJourneyManager.createEditBox:SetHeight(26)
    panelJourneyManager.createEditBox:SetAutoFocus(false)
    panelJourneyManager.createEditBox:SetFontObject(ChatFontNormal)
    panelJourneyManager.createEditBox:SetTextInsets(7, 7, 2, 2)
    panelJourneyManager.createEditBox:SetScript("OnEnterPressed", DreamwayCreateNewJourney)
    panelJourneyManager.createEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        createFrame:Hide()
    end)
    SetFrameBackdrop(panelJourneyManager.createEditBox, 0.01, 0.01, 0.012, 0.94, 0.45)

    panelJourneyManager.createError = CreateLabel(createFrame, "GameFontHighlightSmall")
    panelJourneyManager.createError:SetPoint("TOPLEFT", panelJourneyManager.createEditBox, "BOTTOMLEFT", 0, -6)
    panelJourneyManager.createError:SetTextColor(1, 0.25, 0.25)

    local createCancel = CreateTinyButton(createFrame, "Cancel", 64)
    createCancel:SetPoint("BOTTOMRIGHT", createFrame, "BOTTOMRIGHT", -16, 14)
    createCancel:SetScript("OnClick", function()
        panelJourneyManager.createEditBox:ClearFocus()
        createFrame:Hide()
    end)

    local createConfirm = CreateTinyButton(createFrame, "Create", 64)
    createConfirm:SetPoint("RIGHT", createCancel, "LEFT", -8, 0)
    createConfirm:SetScript("OnClick", DreamwayCreateNewJourney)
    createFrame:Hide()

    local confirmFrame = CreateBackdropFrame(nil, frame)
    confirmFrame:SetSize(430, 154)
    confirmFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)
    confirmFrame:SetFrameLevel(frame:GetFrameLevel() + 4)
    confirmFrame:EnableMouse(true)
    SetFrameBackdrop(confirmFrame, 0.04, 0.01, 0.01, 0.99, 0.9)
    panelJourneyManager.confirmFrame = confirmFrame

    local confirmTitle = CreateLabel(confirmFrame, "GameFontNormalLarge")
    confirmTitle:SetPoint("TOPLEFT", confirmFrame, "TOPLEFT", 16, -14)
    confirmTitle:SetText("Delete Journey")
    confirmTitle:SetTextColor(1, 0.38, 0.32)

    panelJourneyManager.confirmText = CreateLabel(confirmFrame, "GameFontHighlightSmall")
    panelJourneyManager.confirmText:SetPoint("TOPLEFT", confirmTitle, "BOTTOMLEFT", 0, -12)
    panelJourneyManager.confirmText:SetPoint("RIGHT", confirmFrame, "RIGHT", -16, 0)
    panelJourneyManager.confirmText:SetJustifyH("LEFT")

    local deleteCancel = CreateTinyButton(confirmFrame, "Cancel", 64)
    deleteCancel:SetPoint("BOTTOMRIGHT", confirmFrame, "BOTTOMRIGHT", -16, 14)
    deleteCancel:SetScript("OnClick", function()
        panelJourneyManager.pendingDeleteJourneyId = nil
        confirmFrame:Hide()
    end)

    local deleteConfirm = CreateTinyButton(confirmFrame, "Delete", 64)
    deleteConfirm:SetPoint("RIGHT", deleteCancel, "LEFT", -8, 0)
    deleteConfirm:SetBackdropColor(0.24, 0.025, 0.025, 0.92)
    deleteConfirm.label:SetTextColor(1, 0.38, 0.32)
    deleteConfirm:SetScript("OnClick", DreamwayDeleteManagedJourney)
    confirmFrame:Hide()

    frame:SetScript("OnShow", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
        if panelJourneyManager.toggleButton then
            panelJourneyManager.toggleButton.label:SetText("Return to Planner")
        end
        panelJourneyManager.selectedJourneyId = DreamwayActiveJourneyId()
        DreamwayRefreshJourneyManager()
    end)
    frame:SetScript("OnHide", function()
        DreamwayCloseJourneyMetadataMenu()
        createFrame:Hide()
        confirmFrame:Hide()
        if panelJourneyManager.toggleButton then
            panelJourneyManager.toggleButton.label:SetText("Manage Journeys")
        end
    end)
    frame:Hide()
end

function NormalizedPanelSearch()
    return string.lower(panelSearchText or "")
end

function PanelSearchMatchingChainIds(query)
    query = tostring(query or "")
    if query == "" then
        return {}
    end
    if ProfileRecorder.searchMatchingChainQuery == query and ProfileRecorder.searchMatchingChainIds then
        return ProfileRecorder.searchMatchingChainIds
    end

    local matchingChainIds = {}
    for _, entry in ipairs(BuildAllQuestSearchCache()) do
        if entry.chainId and string.find(entry.normalized or "", query, 1, true) then
            matchingChainIds[tonumber(entry.chainId)] = true
        end
    end
    ProfileRecorder.searchMatchingChainQuery = query
    ProfileRecorder.searchMatchingChainIds = matchingChainIds
    return matchingChainIds
end

function PanelQuestMatchesSearch(quest)
    local query = NormalizedPanelSearch()
    if query == "" then
        return true
    end
    local chainId = tonumber(quest and quest.chainId)
    if not chainId then
        local record = QuestZoneDbRecord(quest and quest.id)
        chainId = tonumber(record and record.c)
    end
    local name = string.lower(tostring(quest and (quest.name or QuestDisplayName(quest)) or ""))
    return string.find(name, query, 1, true) ~= nil
        or (chainId and PanelSearchMatchingChainIds(query)[chainId] == true)
end

function PanelSearchSourceBucket(row)
    local sourceType = row and row.source and row.source.type
    if sourceType == "batch" or sourceType == "completed" then
        return 1
    elseif sourceType == "hidden" or sourceType == "unused" then
        return 3
    end
    return 2
end

function PanelSearchBucket(row)
    return tonumber(row and row.chainSortBucket) or PanelSearchSourceBucket(row)
end

function PanelSearchLevel(row)
    local quest = row and row.quest
    return tonumber(quest and (quest.questLevel or quest.level or quest.requiredLevel)) or 999
end

function PanelQuestChainId(quest)
    local chainId = tonumber(quest and quest.chainId)
    if chainId then
        return chainId
    end

    local record = QuestZoneDbRecord(quest and quest.id)
    return tonumber(record and record.c)
end

function PanelQuestChainName(quest)
    local chainName = quest and quest.chainName
    if chainName and chainName ~= "" then
        return tostring(chainName)
    end

    return QuestChainName(PanelQuestChainId(quest)) or QuestDisplayName(quest)
end

function PanelQuestChainStep(quest)
    local chainStep = tonumber(quest and quest.chainStep)
    if chainStep then
        return chainStep
    end

    local record = QuestZoneDbRecord(quest and quest.id)
    return tonumber(record and record.cs) or 9999
end

function PanelQuestChainGroupId(quest)
    local groupId = tonumber(quest and quest.chainGroupId)
    if groupId then
        return groupId
    end

    local record = QuestZoneDbRecord(quest and quest.id)
    return tonumber(record and record.cg) or 9999
end

function PanelQuestChainGroupStep(quest)
    local groupStep = tonumber(quest and quest.chainGroupStep)
    if groupStep then
        return groupStep
    end

    local record = QuestZoneDbRecord(quest and quest.id)
    return tonumber(record and record.cgs) or 9999
end

function PanelQuestChainLength(quest)
    local length = tonumber(quest and quest.chainLength)
    if length then
        return length
    end

    local chain = QuestChainDbRecord(PanelQuestChainId(quest))
    if chain and type(chain.q) == "table" then
        return #chain.q
    end
    return 1
end

function PanelQuestChainAvailableLength(quest)
    local chain = QuestChainDbRecord(PanelQuestChainId(quest))
    if not chain or type(chain.q) ~= "table" then
        return 1
    end

    local gameVersion = CurrentDreamwayGameVersion()
    local count = 0
    for _, questId in ipairs(chain.q) do
        local record = QuestZoneDbRecord(questId)
        if not record or not record.gv or tostring(record.gv) == gameVersion or (gameVersion == "sod" and tostring(record.gv) == "era") then
            count = count + 1
        end
    end
    return math.max(1, count)
end

function PanelSearchChainSortInfo(row)
    local quest = row and row.quest
    local chainId = PanelQuestChainId(quest)
    local info = QuestChainSortInfo(chainId)
    if info then
        return info
    end

    local level = PanelSearchLevel(row)
    return {
        name = PanelQuestChainName(quest),
        requiredLevel = tonumber(quest and quest.requiredLevel) or level,
        questLevel = tonumber(quest and quest.questLevel) or level,
    }
end

function PanelSearchQuestRowLess(a, b)
    local chainA = PanelSearchChainSortInfo(a)
    local chainB = PanelSearchChainSortInfo(b)
    local requiredA = tonumber(chainA and chainA.requiredLevel) or 999
    local requiredB = tonumber(chainB and chainB.requiredLevel) or 999
    if requiredA ~= requiredB then
        return requiredA < requiredB
    end

    local questLevelA = tonumber(chainA and chainA.questLevel) or 999
    local questLevelB = tonumber(chainB and chainB.questLevel) or 999
    if questLevelA ~= questLevelB then
        return questLevelA < questLevelB
    end

    local chainNameA = string.lower(tostring(chainA and chainA.name or PanelQuestChainName(a.quest)))
    local chainNameB = string.lower(tostring(chainB and chainB.name or PanelQuestChainName(b.quest)))
    if chainNameA ~= chainNameB then
        return chainNameA < chainNameB
    end

    local chainIdA = PanelQuestChainId(a.quest) or tonumber(a.quest and a.quest.id) or 999999
    local chainIdB = PanelQuestChainId(b.quest) or tonumber(b.quest and b.quest.id) or 999999
    if chainIdA ~= chainIdB then
        return chainIdA < chainIdB
    end

    local stepA = PanelQuestChainStep(a.quest)
    local stepB = PanelQuestChainStep(b.quest)
    if stepA ~= stepB then
        return stepA < stepB
    end

    local groupA = PanelQuestChainGroupId(a.quest)
    local groupB = PanelQuestChainGroupId(b.quest)
    if groupA ~= groupB then
        return groupA < groupB
    end

    local groupStepA = PanelQuestChainGroupStep(a.quest)
    local groupStepB = PanelQuestChainGroupStep(b.quest)
    if groupStepA ~= groupStepB then
        return groupStepA < groupStepB
    end

    local levelA = PanelSearchLevel(a)
    local levelB = PanelSearchLevel(b)
    if levelA ~= levelB then
        return levelA < levelB
    end

    local nameA = string.lower(tostring(a.quest and (a.quest.name or QuestDisplayName(a.quest)) or ""))
    local nameB = string.lower(tostring(b.quest and (b.quest.name or QuestDisplayName(b.quest)) or ""))
    if nameA ~= nameB then
        return nameA < nameB
    end

    return (tonumber(a.quest and a.quest.id) or 999999) < (tonumber(b.quest and b.quest.id) or 999999)
end

function PanelSearchBucketName(row)
    local bucket = PanelSearchBucket(row)
    if bucket == 1 then
        return "Assigned"
    elseif bucket == 3 then
        return "Hidden"
    end
    return "Unassigned"
end

function PanelSearchQuestEntryById(questId)
    questId = tonumber(questId)
    if not questId then
        return nil
    end

    if not ProfileRecorder.searchQuestEntryById then
        ProfileRecorder.searchQuestEntryById = {}
        for _, entry in ipairs(BuildAllQuestSearchCache()) do
            ProfileRecorder.searchQuestEntryById[tonumber(entry.id)] = entry
        end
    end
    return ProfileRecorder.searchQuestEntryById[questId]
end

function PanelSearchQuestNameById(questId)
    local entry = PanelSearchQuestEntryById(questId)
    if entry and entry.name and entry.name ~= "" then
        return tostring(entry.name)
    end

    local quest = HydrateQuestMetadata({ id = tonumber(questId) })
    return quest and quest.name or ("Quest #" .. tostring(questId))
end

function PanelSearchCanonicalQuest(quest)
    local questId = tonumber(quest and quest.id)
    local entry = PanelSearchQuestEntryById(questId)
    if not entry then
        return ApplyQuestZoneMetadata(quest)
    end
    return {
        id = entry.id,
        name = entry.name,
        questLevel = entry.questLevel,
        requiredLevel = entry.requiredLevel,
        chainId = entry.chainId,
        chainName = entry.chainName,
        chainStep = entry.chainStep,
        chainLength = entry.chainLength,
        chainGroupId = entry.chainGroupId,
        chainGroupStep = entry.chainGroupStep,
        chainGroupSize = entry.chainGroupSize,
        preQuestGroup = CloneNumberArray(entry.preQuestGroup),
        preQuestSingle = CloneNumberArray(entry.preQuestSingle),
        startZoneIds = CloneNumberArray(entry.startZoneIds),
        objectiveZoneIds = CloneNumberArray(entry.objectiveZoneIds),
        endZoneIds = CloneNumberArray(entry.endZoneIds),
        zoneIds = CloneNumberArray(entry.zoneIds),
        requiredRaceMask = entry.requiredRaceMask,
        requiredClassMask = entry.requiredClassMask,
        typeIds = CloneStringArray(entry.typeIds),
        gameVersion = entry.gameVersion,
    }
end

function PanelSearchRequirementColorMap(chainId)
    chainId = tonumber(chainId)
    if not chainId then
        return {}
    end
    ProfileRecorder.searchRequirementColorMaps = ProfileRecorder.searchRequirementColorMaps or {}
    if ProfileRecorder.searchRequirementColorMaps[chainId] then
        return ProfileRecorder.searchRequirementColorMaps[chainId]
    end

    local prerequisiteIds = {}
    local seen = {}
    local chain = QuestChainDbRecord(chainId)
    for _, questId in ipairs(chain and chain.q or {}) do
        local record = QuestZoneDbRecord(questId)
        for _, prerequisiteId in ipairs(record and record.pg or {}) do
            prerequisiteId = tonumber(prerequisiteId)
            local prerequisiteRecord = QuestZoneDbRecord(prerequisiteId)
            if prerequisiteId and tonumber(prerequisiteRecord and prerequisiteRecord.c) == chainId and not seen[prerequisiteId] then
                seen[prerequisiteId] = true
                prerequisiteIds[#prerequisiteIds + 1] = prerequisiteId
            end
        end
        for _, prerequisiteId in ipairs(record and record.ps or {}) do
            prerequisiteId = tonumber(prerequisiteId)
            local prerequisiteRecord = QuestZoneDbRecord(prerequisiteId)
            if prerequisiteId and tonumber(prerequisiteRecord and prerequisiteRecord.c) == chainId and not seen[prerequisiteId] then
                seen[prerequisiteId] = true
                prerequisiteIds[#prerequisiteIds + 1] = prerequisiteId
            end
        end
    end
    table.sort(prerequisiteIds)

    local palette = {
        "6bd6ff", "f2758a", "86df6b", "c89cff",
        "ff9d45", "63dec6", "ff73d7", "b8d957",
        "8da2ff", "e1a66a", "79c47b", "d66f6f",
        "7ed4b7", "e6df72", "b892ff", "f5c542",
    }
    local colors = {}
    for index, prerequisiteId in ipairs(prerequisiteIds) do
        colors[prerequisiteId] = palette[((index - 1) % #palette) + 1]
    end
    ProfileRecorder.searchRequirementColorMaps[chainId] = colors
    return colors
end

function PanelSearchColoredRequirementName(chainId, questId)
    questId = tonumber(questId)
    local color = PanelSearchRequirementColorMap(chainId)[questId] or "fff2cf"
    return "|cff" .. color .. PanelSearchQuestNameById(questId) .. "|r"
end

function PanelSearchJoinRequirementNames(chainId, questIds, conjunction)
    local names = {}
    for _, questId in ipairs(questIds or {}) do
        names[#names + 1] = PanelSearchColoredRequirementName(chainId, questId)
    end
    if #names == 0 then
        return ""
    elseif #names == 1 then
        return names[1]
    elseif #names == 2 then
        return names[1] .. " " .. tostring(conjunction or "and") .. " " .. names[2]
    end
    return table.concat(names, ", ", 1, #names - 1) .. ", " .. tostring(conjunction or "and") .. " " .. names[#names]
end

function PanelSearchGroupRequirement(chainId, groupId, questRows)
    local allIds = {}
    local anyIds = {}
    local allSeen = {}
    local anySeen = {}

    local function addRequirement(target, targetSeen, prerequisiteId)
        prerequisiteId = tonumber(prerequisiteId)
        if not prerequisiteId or targetSeen[prerequisiteId] then
            return
        end
        local record = QuestZoneDbRecord(prerequisiteId)
        if tonumber(record and record.c) ~= tonumber(chainId) or tonumber(record and record.cg) == tonumber(groupId) then
            return
        end
        targetSeen[prerequisiteId] = true
        target[#target + 1] = prerequisiteId
    end

    for _, row in ipairs(questRows or {}) do
        local quest = row.quest or {}
        for _, prerequisiteId in ipairs(quest.preQuestGroup or {}) do
            addRequirement(allIds, allSeen, prerequisiteId)
        end
        for _, prerequisiteId in ipairs(quest.preQuestSingle or {}) do
            addRequirement(anyIds, anySeen, prerequisiteId)
        end
    end
    table.sort(allIds)
    table.sort(anyIds)

    local parts = {}
    if #allIds > 0 then
        parts[#parts + 1] = PanelSearchJoinRequirementNames(chainId, allIds, "and")
    end
    if #anyIds == 1 then
        parts[#parts + 1] = PanelSearchJoinRequirementNames(chainId, anyIds, "and")
    elseif #anyIds > 1 then
        parts[#parts + 1] = "any one of " .. PanelSearchJoinRequirementNames(chainId, anyIds, "or")
    end
    if #parts == 0 then
        return nil, {}
    end

    local requirementIds = {}
    for _, questId in ipairs(allIds) do requirementIds[#requirementIds + 1] = questId end
    for _, questId in ipairs(anyIds) do requirementIds[#requirementIds + 1] = questId end
    return "Complete " .. table.concat(parts, " and "), requirementIds
end

function PanelSearchRowsWithChainHeaders(questRows)
    local rows = {}
    local index = 1
    ProfileRecorder.panelCollapsedSearchChains = ProfileRecorder.panelCollapsedSearchChains or {}

    while index <= #(questRows or {}) do
        local firstRow = questRows[index]
        local chainId = PanelQuestChainId(firstRow.quest)
        local chainKey = tostring(chainId or (firstRow.quest and firstRow.quest.id) or "")
        local chainRows = {}
        while index <= #questRows do
            local candidate = questRows[index]
            local candidateChainId = PanelQuestChainId(candidate.quest)
            local candidateKey = tostring(candidateChainId or (candidate.quest and candidate.quest.id) or "")
            if candidateKey ~= chainKey then
                break
            end
            chainRows[#chainRows + 1] = candidate
            index = index + 1
        end

        if PanelQuestChainAvailableLength(firstRow.quest) <= 1 then
            firstRow.kind = "quest"
            firstRow.standalone = true
            rows[#rows + 1] = firstRow
        else
            local chainInfo = PanelSearchChainSortInfo(firstRow)
            local level = tonumber(chainInfo and (chainInfo.requiredLevel or chainInfo.questLevel))
            local label = PanelQuestChainName(firstRow.quest)
            if level and level < 999 then
                label = "[" .. tostring(level) .. "] " .. label
            end
            local chainLength = PanelQuestChainAvailableLength(firstRow.quest)
            label = label .. " |cff8f8f8f(" .. tostring(chainLength) .. ")|r"
            local collapsed = ProfileRecorder.panelCollapsedSearchChains[chainKey] == true
            rows[#rows + 1] = {
                kind = "chain",
                chainKey = chainKey,
                label = label,
                location = firstRow.location or PanelSearchBucketName(firstRow),
                collapsed = collapsed,
            }

            if not collapsed then
                local groupRows = {}
                local currentGroupId
                local groupIndex = 0
                local function appendGroup()
                    if #groupRows == 0 then
                        return
                    end
                    groupIndex = groupIndex + 1
                    local requirementText, requirementQuestIds = PanelSearchGroupRequirement(chainId, currentGroupId, groupRows)
                    if requirementText then
                        rows[#rows + 1] = {
                            kind = "requirement",
                            label = requirementText,
                            requirementQuestIds = requirementQuestIds,
                        }
                    end
                    for _, questRow in ipairs(groupRows) do
                        questRow.kind = "quest"
                        rows[#rows + 1] = questRow
                    end
                    groupRows = {}
                end

                for _, questRow in ipairs(chainRows) do
                    local groupId = PanelQuestChainGroupId(questRow.quest)
                    if currentGroupId ~= nil and groupId ~= currentGroupId then
                        appendGroup()
                    end
                    currentGroupId = groupId
                    groupRows[#groupRows + 1] = questRow
                end
                appendGroup()
            end
        end
    end

    return rows
end

local function HidePanelBatchColumn(column)
    if not column then
        return
    end

    column:Hide()
    column:SetScript("OnMouseDown", nil)
    if column.title then column.title:Hide() end
    if column.titleHitbox then column.titleHitbox:Hide() end
    if column.indexText then column.indexText:Hide() end
    if column.levelText then column.levelText:Hide() end
    if column.batchCheck then column.batchCheck:Hide() end
    if column.zoneText then column.zoneText:Hide() end
    if column.zoneHitbox then column.zoneHitbox:Hide() end
    if column.emptyLabel then column.emptyLabel:Hide() end
    if column.moreLabel then column.moreLabel:Hide() end
    if column.insertButton then column.insertButton:Hide() end
    if column.deleteButton then column.deleteButton:Hide() end

    for _, row in ipairs(column.questRows or {}) do
        row:Hide()
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:SetScript("OnDragStart", nil)
        row:SetScript("OnDragStop", nil)
        row.quest = nil
        row.prerequisiteWarning = nil
        if row.label then
            row.label:SetText("")
        end
        if row.check then
            row.check:Hide()
        end
    end
end

local function EnsurePanelBatchColumn(poolIndex)
    local column = panelBatchColumns[poolIndex]
    if column then
        return column
    end

    column = CreateBackdropFrame(nil, panelBatchContent)
    column:SetSize(PANEL_BATCH_COLUMN_WIDTH, PANEL_BATCH_COLUMN_HEIGHT)
    column:EnableMouse(true)
    column.questRows = {}

    column.title = CreateLabel(column, "GameFontNormal")
    column.title:SetPoint("TOPLEFT", column, "TOPLEFT", 10, -10)
    column.title:SetWordWrap(false)
    if column.title.SetNonSpaceWrap then
        column.title:SetNonSpaceWrap(false)
    end

    column.titleHitbox = CreateFrame("Frame", nil, column)
    column.titleHitbox:EnableMouse(true)

    column.indexText = CreateLabel(column, "GameFontDisableSmall")
    column.indexText:SetPoint("BOTTOMRIGHT", column, "BOTTOMRIGHT", -10, 8)
    column.indexText:SetJustifyH("RIGHT")

    column.levelText = CreateLabel(column, "GameFontNormalSmall")
    column.levelText:SetPoint("TOPRIGHT", column, "TOPRIGHT", -10, -12)
    column.levelText:SetWidth(38)
    column.levelText:SetJustifyH("RIGHT")

    column.batchCheck = column:CreateTexture(nil, "ARTWORK")
    column.batchCheck:SetSize(12, 12)

    column.zoneText = CreateLabel(column, "GameFontDisableSmall")
    column.zoneText:SetPoint("TOPLEFT", column.title, "BOTTOMLEFT", 0, -4)
    column.zoneText:SetWidth(152)
    column.zoneText:SetWordWrap(false)
    if column.zoneText.SetNonSpaceWrap then
        column.zoneText:SetNonSpaceWrap(false)
    end

    column.zoneHitbox = CreateFrame("Frame", nil, column)
    column.zoneHitbox:EnableMouse(true)

    column.emptyLabel = CreateLabel(column, "GameFontDisableSmall")
    column.emptyLabel:SetWidth(152)

    column.moreLabel = CreateLabel(column, "GameFontDisableSmall")
    column.moreLabel:SetText("...")

    column.insertButton = CreateTinyButton(column, "+", 14)
    column.insertButton:SetHeight(PANEL_BATCH_COLUMN_HEIGHT)
    column.insertButton:SetFrameLevel(column:GetFrameLevel() + 4)
    column.insertButton:SetBackdropColor(0.03, 0.03, 0.04, 0.7)
    column.insertButton:SetBackdropBorderColor(0.72, 0.58, 0.12, 0.7)

    column.deleteButton = CreateTinyButton(column, "x", 18)
    column.deleteButton:SetHeight(18)
    column.deleteButton:SetFrameLevel(column:GetFrameLevel() + 5)
    column.deleteButton:SetBackdropColor(0.24, 0.025, 0.025, 0.92)
    column.deleteButton:SetBackdropBorderColor(0.9, 0.2, 0.18, 0.8)
    column.deleteButton.label:SetTextColor(1, 0.38, 0.32)

    for index = 1, 18 do
        local row = CreateTextButton(column, "GameFontHighlightSmall")
        row.check = column:CreateTexture(nil, "ARTWORK")
        row.check:SetSize(12, 12)
        row.check:Hide()
        column.questRows[index] = row
    end

    panelBatchColumns[poolIndex] = column
    return column
end

local function RenderPanelBatchColumn(column, batch, index, total, options)
    options = options or {}
    local columnType = options.type or (options.unused and "hidden") or "batch"
    local isHidden = columnType == "hidden" or columnType == "unused"
    local columnIndex = (index - 1) % PANEL_BATCH_COLUMNS_PER_ROW
    local rowIndex = math.floor((index - 1) / PANEL_BATCH_COLUMNS_PER_ROW)

    HidePanelBatchColumn(column)
    column:SetParent(panelBatchContent)
    column:ClearAllPoints()
    column:SetPoint("TOPLEFT", panelBatchContent, "TOPLEFT", columnIndex * PANEL_BATCH_COLUMN_STEP_X, -(rowIndex * PANEL_BATCH_ROW_STEP_Y))
    column:Show()
    column:EnableMouse(true)

    if isHidden then
        SetFrameBackdrop(column, 0.12, 0.025, 0.025, 0.92, 0.75)
    else
        SetFrameBackdrop(column, index == batchIndex and 0.08 or 0.03, index == batchIndex and 0.10 or 0.03, 0.04, 0.9, index == batchIndex and 0.95 or 0.28)
    end

    panelDropTargets[#panelDropTargets + 1] = {
        frame = column,
        type = isHidden and "hidden" or "batch",
        index = isHidden and nil or index,
    }

    local expectedLevel = isHidden and nil or BatchExpectedLevel(batch)
    local batchComplete = (not isHidden) and IsBatchComplete(batch)

    column.title:Show()
    column.title:ClearAllPoints()
    column.title:SetPoint("TOPLEFT", column, "TOPLEFT", 10, -10)
    local titleText
    local titleWidth = expectedLevel and (batchComplete and 64 or 78) or (isHidden and 134 or 112)
    column.title:SetWidth(titleWidth)
    column.title:SetHeight(16)
    column.title:SetWordWrap(false)
    if isHidden then
        titleText = "Hidden"
        column.title:SetText(titleText)
        column.title:SetTextColor(1, 0.36, 0.32)
    else
        titleText = batch.name or tostring(index)
        column.title:SetText(titleText)
        column.title:SetTextColor(1, 0.82, 0.12)
    end
    local titleHeight = 16
    column.titleHitbox:ClearAllPoints()
    column.titleHitbox:SetPoint("TOPLEFT", column.title, "TOPLEFT", 0, 0)
    column.titleHitbox:SetSize(titleWidth, titleHeight)
    ConfigurePanelTooltip(column.titleHitbox, titleText, isHidden and "Hidden quests are suppressed while Dreamway view is active." or nil)
    column.titleHitbox:Show()

    if not isHidden then
        column.indexText:ClearAllPoints()
        column.indexText:SetPoint("BOTTOMRIGHT", column, "BOTTOMRIGHT", -10, 8)
        column.indexText:SetText("[" .. tostring(index) .. "/" .. tostring(total) .. "]")
        column.indexText:SetTextColor(0.56, 0.56, 0.56)
        column.indexText:Show()
    end

    if expectedLevel then
        column.levelText:ClearAllPoints()
        column.levelText:SetPoint("TOPRIGHT", column, "TOPRIGHT", batchComplete and -38 or -23, -12)
        column.levelText:SetText("Lv " .. tostring(expectedLevel))
        column.levelText:SetTextColor(0.74, 0.74, 0.74)
        column.levelText:Show()

        if batchComplete then
            column.batchCheck:ClearAllPoints()
            column.batchCheck:SetPoint("LEFT", column.levelText, "RIGHT", 3, 1)
            column.batchCheck:SetTexture(COMPLETE_TEXTURE)
            column.batchCheck:Show()
        end
    elseif batchComplete then
        column.batchCheck:ClearAllPoints()
        column.batchCheck:SetPoint("TOPRIGHT", column, "TOPRIGHT", -10, -11)
        column.batchCheck:SetTexture(COMPLETE_TEXTURE)
        column.batchCheck:Show()
    end

    column.zoneText:ClearAllPoints()
    column.zoneText:SetPoint("TOPLEFT", column.title, "BOTTOMLEFT", 0, -4)
    column.zoneText:SetWidth(PANEL_BATCH_COLUMN_WIDTH - 20)
    column.zoneText:SetHeight(12)
    column.zoneText:SetWordWrap(false)
    local zoneText
    if isHidden then
        local hiddenCount = batch.quests and #batch.quests or 0
        zoneText = tostring(hiddenCount) .. " quest" .. (hiddenCount == 1 and "" or "s") .. " hidden in Dreamway view"
    else
        zoneText = batch.zones and table.concat(batch.zones, ", ") or ""
    end
    column.zoneText:SetText(zoneText)
    column.zoneText:Show()
    local zoneHeight = 12
    column.zoneHitbox:ClearAllPoints()
    column.zoneHitbox:SetPoint("TOPLEFT", column.zoneText, "TOPLEFT", 0, 0)
    column.zoneHitbox:SetSize(PANEL_BATCH_COLUMN_WIDTH - 20, zoneHeight)
    ConfigurePanelTooltip(column.zoneHitbox, isHidden and "Hidden" or "Zones", zoneText)
    column.zoneHitbox:Show()

    local y = -10 - titleHeight - 4 - zoneHeight - 14
    local rows = {}
    for _, row in ipairs(GetSortedPanelQuests(batch)) do
        if PanelQuestMatchesSearch(row.quest) then
            rows[#rows + 1] = row
        end
    end

    if #rows == 0 and (isHidden or NormalizedPanelSearch() ~= "") then
        column.emptyLabel:ClearAllPoints()
        column.emptyLabel:SetPoint("TOPLEFT", column, "TOPLEFT", 10, y)
        if NormalizedPanelSearch() ~= "" then
            column.emptyLabel:SetText("No matching quests.")
        elseif isHidden then
            column.emptyLabel:SetText("No hidden quests.")
        else
            column.emptyLabel:SetText("No quests.")
        end
        column.emptyLabel:Show()
    else
        for questIndex, row in ipairs(rows) do
            local questRow = column.questRows[questIndex]
            if not questRow or questIndex > 18 or y < -318 then
                column.moreLabel:ClearAllPoints()
                column.moreLabel:SetPoint("TOPLEFT", column, "TOPLEFT", 14, y)
                column.moreLabel:Show()
                break
            end

            local quest = row.quest
            questRow:ClearAllPoints()
            questRow:SetPoint("TOPLEFT", column, "TOPLEFT", 10, y)
            local prerequisiteWarning = panelPrerequisiteWarnings[tonumber(quest.id)]
            local displayName = ColoredQuestDisplayName(quest, false)
            if prerequisiteWarning then
                displayName = WARNING_INLINE_TEXTURE .. " " .. displayName
            end
            local lineHeight = SetButtonText(questRow, row.complete and (PANEL_BATCH_COLUMN_WIDTH - 42) or (PANEL_BATCH_COLUMN_WIDTH - 20), displayName)
            questRow.label:SetTextColor(1, 1, 1)
            questRow.prerequisiteWarning = prerequisiteWarning
            ConfigureQuestButton(questRow, quest, column, true)
            MakePanelQuestDraggable(questRow, quest, {
                type = isHidden and "hidden" or "batch",
                index = isHidden and nil or index,
            })
            questRow:Show()

            if row.complete then
                questRow.check:ClearAllPoints()
                questRow.check:SetPoint("TOPRIGHT", column, "TOPRIGHT", -10, y + 1)
                questRow.check:SetTexture(COMPLETE_TEXTURE)
                questRow.check:Show()
            end

            y = y - lineHeight - 4
        end
    end

    local function selectColumn()
        if not isHidden then
            batchIndex = index
            SaveDb()
            RefreshDreamwayTracker()
            RefreshPanelBatchSelection()
        end
    end

    if not isHidden then
        column.deleteButton:ClearAllPoints()
        column.deleteButton:SetPoint("TOPRIGHT", column, "TOPRIGHT", -3, -3)
        column.deleteButton:SetScript("OnClick", function()
            DreamwayConfirmDeleteBatch(index)
        end)
        ConfigurePanelTooltip(column.deleteButton, "Delete batch", "Unassign every quest in this batch.")
        column.deleteButton:Show()

        column.insertButton:ClearAllPoints()
        column.insertButton:SetPoint("TOPLEFT", column, "TOPRIGHT", 3, 0)
        column.insertButton:SetScript("OnClick", function()
            DreamwayInsertBatchAfter(index)
        end)
        ConfigurePanelTooltip(column.insertButton, "Insert batch", "Create a new batch here, or drop a quest to create one containing it.")
        column.insertButton:Show()
        panelDropTargets[#panelDropTargets + 1] = {
            frame = column.insertButton,
            type = "newbatch",
            index = index,
        }

        column:SetScript("OnMouseDown", selectColumn)
        column.titleHitbox:SetScript("OnMouseDown", selectColumn)
        column.zoneHitbox:SetScript("OnMouseDown", selectColumn)
    else
        column.titleHitbox:SetScript("OnMouseDown", nil)
        column.zoneHitbox:SetScript("OnMouseDown", nil)
    end
end

function AddPanelSearchDropTarget()
    if panelSearchResults and panelSearchResults:IsShown() then
        panelDropTargets[#panelDropTargets + 1] = {
            frame = panelSearchResults,
            type = "unassigned",
        }
    end
    if panelJourneyManager.hiddenDrop and panelJourneyManager.hiddenDrop:IsShown() then
        panelDropTargets[#panelDropTargets + 1] = {
            frame = panelJourneyManager.hiddenDrop,
            type = "hidden",
        }
    end
end

local function UpdatePanelBatchVisibleColumns(force)
    if not panelBatchScroll or not panelBatchContent then
        return
    end

    local journey = ActiveJourney()
    local total = journey.batches and #journey.batches or 0
    local displayColumns = total + 1
    local contentRows = math.max(1, math.ceil(displayColumns / PANEL_BATCH_COLUMNS_PER_ROW))
    panelBatchContent:SetSize(710, math.max(PANEL_BATCH_COLUMN_HEIGHT + 5, contentRows * PANEL_BATCH_ROW_STEP_Y))

    local scrollOffset = panelBatchScroll:GetVerticalScroll() or 0
    local viewportHeight = panelBatchScroll:GetHeight() or 365
    local firstRow = math.max(0, math.floor(scrollOffset / PANEL_BATCH_ROW_STEP_Y) - PANEL_BATCH_VISIBLE_ROW_EXTRA)
    local visibleRows = math.ceil(viewportHeight / PANEL_BATCH_ROW_STEP_Y) + (PANEL_BATCH_VISIBLE_ROW_EXTRA * 2) + 1
    local firstIndex = (firstRow * PANEL_BATCH_COLUMNS_PER_ROW) + 1
    local lastIndex = math.min(displayColumns, (firstRow + visibleRows) * PANEL_BATCH_COLUMNS_PER_ROW)

    if not force
        and ProfileRecorder.batchRenderedFirstIndex == firstIndex
        and ProfileRecorder.batchRenderedLastIndex == lastIndex
    then
        return
    end
    ProfileRecorder.batchRenderedFirstIndex = firstIndex
    ProfileRecorder.batchRenderedLastIndex = lastIndex
    panelDropTargets = {}

    local poolIndex = 1
    for displayIndex = firstIndex, lastIndex do
        local column = EnsurePanelBatchColumn(poolIndex)
        if displayIndex <= total then
            RenderPanelBatchColumn(column, journey.batches[displayIndex], displayIndex, total)
        else
            RenderPanelBatchColumn(column, {
                name = "Hidden",
                quests = JourneyUnusedQuestRows(journey),
            }, displayIndex, total, { type = "hidden" })
        end
        poolIndex = poolIndex + 1
    end

    for index = poolIndex, #panelBatchColumns do
        HidePanelBatchColumn(panelBatchColumns[index])
    end

    AddPanelSearchDropTarget()
end

local function PanelAddBatchColumn(parent, batch, index, total, options)
    options = options or {}
    local columnType = options.type or (options.unused and "hidden") or "batch"
    local isHidden = columnType == "hidden" or columnType == "unused"
    local columnsPerRow = 4
    local columnIndex = (index - 1) % columnsPerRow
    local rowIndex = math.floor((index - 1) / columnsPerRow)
    local column = CreateBackdropFrame(nil, parent)
    column:SetSize(172, 360)
    column:EnableMouse(true)
    if isHidden then
        SetFrameBackdrop(column, 0.12, 0.025, 0.025, 0.92, 0.75)
    else
        SetFrameBackdrop(column, index == batchIndex and 0.08 or 0.03, index == batchIndex and 0.10 or 0.03, 0.04, 0.9, index == batchIndex and 0.95 or 0.28)
    end
    panelDropTargets[#panelDropTargets + 1] = {
        frame = column,
        type = isHidden and "hidden" or "batch",
        index = isHidden and nil or index,
    }
    column:SetPoint("TOPLEFT", parent, "TOPLEFT", columnIndex * 182, -(rowIndex * 372))

    local expectedLevel = isHidden and nil or BatchExpectedLevel(batch)
    local batchComplete = (not isHidden) and IsBatchComplete(batch)

    local title = CreateLabel(column, "GameFontNormal")
    title:SetPoint("TOPLEFT", column, "TOPLEFT", 10, -10)
    title:SetWidth(expectedLevel and 100 or 152)
    title:SetWordWrap(true)
    if isHidden then
        title:SetText("Hidden")
        title:SetTextColor(1, 0.36, 0.32)
    else
        title:SetText(batch.name or tostring(index))
        title:SetTextColor(1, 0.82, 0.12)
    end
    local titleHeight = math.max(title:GetStringHeight() or 0, title:GetHeight() or 0, 16)
    title:SetHeight(titleHeight)

    if not isHidden then
        local indexText = CreateLabel(column, "GameFontDisableSmall")
        indexText:SetPoint("BOTTOMRIGHT", column, "BOTTOMRIGHT", -10, 8)
        indexText:SetJustifyH("RIGHT")
        indexText:SetText("[" .. tostring(index) .. "/" .. tostring(total) .. "]")
        indexText:SetTextColor(0.56, 0.56, 0.56)
    end

    if expectedLevel then
        local levelText = CreateLabel(column, "GameFontNormalSmall")
        levelText:SetPoint("TOPRIGHT", column, "TOPRIGHT", batchComplete and -25 or -10, -12)
        levelText:SetWidth(38)
        levelText:SetJustifyH("RIGHT")
        levelText:SetText("Lv " .. tostring(expectedLevel))
        levelText:SetTextColor(0.74, 0.74, 0.74)

        if batchComplete then
            local batchCheck = column:CreateTexture(nil, "ARTWORK")
            batchCheck:SetSize(12, 12)
            batchCheck:SetPoint("LEFT", levelText, "RIGHT", 3, 1)
            batchCheck:SetTexture(COMPLETE_TEXTURE)
        end
    elseif batchComplete then
        local batchCheck = column:CreateTexture(nil, "ARTWORK")
        batchCheck:SetSize(12, 12)
        batchCheck:SetPoint("TOPRIGHT", column, "TOPRIGHT", -10, -11)
        batchCheck:SetTexture(COMPLETE_TEXTURE)
    end

    local zoneText = CreateLabel(column, "GameFontDisableSmall")
    zoneText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    zoneText:SetWidth(152)
    zoneText:SetWordWrap(true)
    if isHidden then
        local hiddenCount = batch.quests and #batch.quests or 0
        zoneText:SetText(tostring(hiddenCount) .. " quest" .. (hiddenCount == 1 and "" or "s") .. " hidden in Dreamway view")
    else
        zoneText:SetText(batch.zones and table.concat(batch.zones, ", ") or "")
    end
    local zoneHeight = math.max(zoneText:GetStringHeight() or 0, zoneText:GetHeight() or 0, 12)
    zoneText:SetHeight(zoneHeight)

    local y = -10 - titleHeight - 4 - zoneHeight - 14
    local rows = {}
    for _, row in ipairs(GetSortedPanelQuests(batch)) do
        if PanelQuestMatchesSearch(row.quest) then
            rows[#rows + 1] = row
        end
    end
    if #rows == 0 and (isHidden or NormalizedPanelSearch() ~= "") then
        local empty = CreateLabel(column, "GameFontDisableSmall")
        empty:SetPoint("TOPLEFT", column, "TOPLEFT", 10, y)
        empty:SetWidth(152)
        if NormalizedPanelSearch() ~= "" then
            empty:SetText("No matching quests.")
        elseif isHidden then
            empty:SetText("No hidden quests.")
        else
            empty:SetText("No quests.")
        end
        return column
    end

    for questIndex, row in ipairs(rows) do
        local quest = row.quest
        local line = CreateTextButton(column, "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", column, "TOPLEFT", 10, y)
        local lineHeight = SetButtonText(line, row.complete and 132 or 152, ColoredQuestDisplayName(quest, false))
        line.label:SetTextColor(1, 1, 1)
        ConfigureQuestButton(line, quest, column, true)
        MakePanelQuestDraggable(line, quest, {
            type = isHidden and "hidden" or "batch",
            index = isHidden and nil or index,
        })
        if row.complete then
            local check = column:CreateTexture(nil, "ARTWORK")
            check:SetSize(12, 12)
            check:SetPoint("TOPRIGHT", column, "TOPRIGHT", -10, y + 1)
            check:SetTexture(COMPLETE_TEXTURE)
        end
        y = y - lineHeight - 4
        if questIndex >= 18 or y < -318 then
            local more = CreateLabel(column, "GameFontDisableSmall")
            more:SetPoint("TOPLEFT", column, "TOPLEFT", 14, y)
            more:SetText("...")
            break
        end
    end

    if not isHidden then
        column:SetScript("OnMouseDown", function()
            batchIndex = index
            SaveDb()
            RefreshDreamwayTracker()
            RefreshPanelBatchSelection()
        end)
    end

    return column
end

function RefreshPanel()
    if not panelFrame or not panelBatchContent then
        return
    end

    local journey = ActiveJourney()
    ClampBatchIndex(journey)
    panelFrame.title:SetText("Dreamway - " .. (journey.name or "Journey"))
    if panelFrame.metadataText then
        panelFrame.metadataText:SetText(DreamwayJourneyMetadataSummary(journey))
    end
    panelPrerequisiteWarnings = JourneyPrerequisiteWarnings(journey)

    UpdatePanelBatchVisibleColumns(true)
    if RefreshPanelSearchResults then
        RefreshPanelSearchResults()
    end
end

function RefreshPanelBatchSelection()
    if not panelFrame or not panelBatchContent then
        return
    end

    local journey = ActiveJourney()
    ClampBatchIndex(journey)
    UpdatePanelBatchVisibleColumns(true)
end

function PanelSearchRows(journey)
    local query = NormalizedPanelSearch()
    local hasQuery = query ~= ""

    local rows = {}
    local seen = {}
    local assignedOrHidden = {}
    local completed = {}
    local function markAssignedOrHidden(quest)
        local questId = tonumber(quest and quest.id)
        if questId then
            assignedOrHidden[questId] = true
        end
    end

    local function addQuest(quest, location, source)
        local questId = tonumber(quest and quest.id)
        if not questId or seen[questId] then
            return
        end
        quest = PanelSearchCanonicalQuest(quest)
        if not PanelQuestMatchesSearch(quest) or not panelSearchFilters.PassesQuest(quest) then
            return
        end
        seen[questId] = true
        rows[#rows + 1] = {
            kind = "quest",
            quest = quest,
            location = location,
            source = source,
        }
    end

    for _, questId in ipairs(DreamwayProfile and DreamwayProfile.completedQuestIds or {}) do
        questId = tonumber(questId)
        if questId then
            completed[questId] = true
            assignedOrHidden[questId] = true
        end
    end

    for index, batch in ipairs(journey and journey.batches or {}) do
        local location = batch.name or ("Batch " .. tostring(index))
        for _, quest in ipairs(batch.quests or {}) do
            markAssignedOrHidden(quest)
            if panelShowAssignedQuests then
                addQuest(quest, location, { type = "batch", index = index })
            end
        end
    end

    for _, quest in ipairs(JourneyUnusedQuestRows(journey)) do
        markAssignedOrHidden(quest)
        if panelShowAssignedQuests then
            addQuest(quest, "Hidden", { type = "hidden" })
        end
    end

    for _, entry in ipairs(BuildAllQuestSearchCache()) do
        local quest = {
            id = entry.id,
            name = entry.name,
            questLevel = entry.questLevel,
            requiredLevel = entry.requiredLevel,
            chainId = entry.chainId,
            chainName = entry.chainName,
            chainStep = entry.chainStep,
            chainLength = entry.chainLength,
            chainGroupId = entry.chainGroupId,
            chainGroupStep = entry.chainGroupStep,
            chainGroupSize = entry.chainGroupSize,
            preQuestGroup = CloneNumberArray(entry.preQuestGroup),
            preQuestSingle = CloneNumberArray(entry.preQuestSingle),
            startZoneIds = entry.startZoneIds,
            objectiveZoneIds = entry.objectiveZoneIds,
            endZoneIds = entry.endZoneIds,
            zoneIds = entry.zoneIds,
            requiredRaceMask = entry.requiredRaceMask,
            requiredClassMask = entry.requiredClassMask,
            typeIds = entry.typeIds,
            gameVersion = entry.gameVersion,
        }
        local isAssignedOrHidden = assignedOrHidden[entry.id] == true
        if (panelShowAssignedQuests or not isAssignedOrHidden) and not seen[entry.id] and PanelQuestMatchesSearch(quest) and panelSearchFilters.PassesQuest(quest) then
            seen[entry.id] = true
            rows[#rows + 1] = {
                kind = "quest",
                quest = quest,
                location = completed[entry.id] and "Completed" or "Unassigned",
                source = { type = completed[entry.id] and "completed" or "unassigned" },
            }
        end
    end

    local zoneEligibleChains = {}
    local zoneEligibleStandalone = {}
    for _, row in ipairs(rows) do
        if panelSearchFilters.PassesZones(row.quest) then
            local chainId = PanelQuestChainId(row.quest)
            if chainId and PanelQuestChainAvailableLength(row.quest) > 1 then
                zoneEligibleChains[chainId] = true
            else
                zoneEligibleStandalone[tonumber(row.quest and row.quest.id)] = true
            end
        end
    end
    local zoneFilteredRows = {}
    for _, row in ipairs(rows) do
        local chainId = PanelQuestChainId(row.quest)
        local isChainQuest = chainId and PanelQuestChainAvailableLength(row.quest) > 1
        if (isChainQuest and zoneEligibleChains[chainId])
            or (not isChainQuest and zoneEligibleStandalone[tonumber(row.quest and row.quest.id)])
        then
            zoneFilteredRows[#zoneFilteredRows + 1] = row
        end
    end
    rows = zoneFilteredRows

    local levelEligibleChains = {}
    local levelEligibleStandalone = {}
    for _, row in ipairs(rows) do
        if panelSearchFilters.PassesLevel(row.quest) then
            local chainId = PanelQuestChainId(row.quest)
            if chainId and PanelQuestChainAvailableLength(row.quest) > 1 then
                levelEligibleChains[chainId] = true
            else
                levelEligibleStandalone[tonumber(row.quest and row.quest.id)] = true
            end
        end
    end
    local levelFilteredRows = {}
    for _, row in ipairs(rows) do
        local chainId = PanelQuestChainId(row.quest)
        local isChainQuest = chainId and PanelQuestChainAvailableLength(row.quest) > 1
        if (isChainQuest and levelEligibleChains[chainId])
            or (not isChainQuest and levelEligibleStandalone[tonumber(row.quest and row.quest.id)])
        then
            levelFilteredRows[#levelFilteredRows + 1] = row
        end
    end
    rows = levelFilteredRows

    table.sort(rows, PanelSearchQuestRowLess)

    local totalMatches = #rows
    if hasQuery and #rows > MAX_PANEL_SEARCH_RESULTS then
        for index = #rows, MAX_PANEL_SEARCH_RESULTS + 1, -1 do
            rows[index] = nil
        end
    end

    local shownMatches = #rows
    return PanelSearchRowsWithChainHeaders(rows), totalMatches, shownMatches
end

function ClearPanelSearchRequirementHighlights()
    for _, button in ipairs(panelSearchResultButtons or {}) do
        if button.requirementHighlight then
            button.requirementHighlight:Hide()
        end
    end
end

function SetPanelSearchRequirementHighlights(questIds)
    ClearPanelSearchRequirementHighlights()
    local highlighted = {}
    for _, questId in ipairs(questIds or {}) do
        questId = tonumber(questId)
        if questId then
            highlighted[questId] = true
        end
    end
    for _, button in ipairs(panelSearchResultButtons or {}) do
        local questId = tonumber(button.quest and button.quest.id)
        if questId and highlighted[questId] and button.requirementHighlight then
            button.requirementHighlight:Show()
        end
    end
end

function DreamwayPanelSearchRowOnClick(self, mouseButton)
    if self.rowKind == "chain" then
        if not self.chainKey then
            return
        end
        local scrollOffset = panelSearchResultsScroll and panelSearchResultsScroll:GetVerticalScroll() or 0
        ProfileRecorder.panelCollapsedSearchChains[self.chainKey] = not ProfileRecorder.panelCollapsedSearchChains[self.chainKey]
        RefreshPanelSearchResults()
        if panelSearchResultsScroll and panelSearchResultsScroll.SetVerticalScroll then
            panelSearchResultsScroll:SetVerticalScroll(scrollOffset)
            UpdatePanelSearchVisibleRows(true)
        end
        return
    end

    local quest = self.quest
    if self.rowKind ~= "quest" or not quest then
        return
    end
    if mouseButton == "RightButton" then
        ShowQuestieTrackerMenu(quest)
    elseif not InsertQuestChatLink(quest) then
        OpenQuestieDetails(quest)
    end
end

function DreamwayPanelSearchRowOnEnter(self)
    if self.rowKind == "requirement" then
        SetPanelSearchRequirementHighlights(self.requirementQuestIds)
        if GameTooltip then
            AnchorDreamwayTooltip(self)
            GameTooltip:SetText(self.label:GetText() or "Quest prerequisites")
            GameTooltip:AddLine("Complete these quests before beginning this section.", 0.72, 0.72, 0.72, true)
            GameTooltip:Show()
        end
        return
    end
    if self.rowKind == "chain" then
        if GameTooltip then
            AnchorDreamwayTooltip(self)
            GameTooltip:SetText(self.chainKey and (ProfileRecorder.panelCollapsedSearchChains[self.chainKey] and "Expand quest chain" or "Collapse quest chain") or "Quest chain")
            GameTooltip:Show()
        end
        return
    end

    local quest = self.quest
    if self.rowKind ~= "quest" or not quest or not GameTooltip then
        return
    end
    AnchorDreamwayTooltip(self)
    GameTooltip:AddLine(quest.name or QuestDisplayName(quest), 1, 0.82, 0.12)
    if self.prerequisiteWarning then
        GameTooltip:AddLine("Prerequisite warning", 1, 0.55, 0.16)
        GameTooltip:AddLine(self.prerequisiteWarning, 0.95, 0.78, 0.48, true)
    end
    GameTooltip:AddLine("Click to open Questie quest details.", 0.75, 0.75, 0.75)
    GameTooltip:Show()
end

function DreamwayPanelSearchRowOnLeave()
    ClearPanelSearchRequirementHighlights()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

function DreamwayPanelSearchRowOnDragStart(self)
    if self.rowKind == "quest" and self.quest and self.dragSource then
        StartPanelQuestDrag(self.quest, self.dragSource)
    end
end

function DreamwayPanelSearchRowOnDragStop()
    EndPanelQuestDrag()
end

local function EnsurePanelSearchButton(index)
    local button = panelSearchResultButtons[index]
    if button then
        return button
    end

    button = CreateFrame("Button", nil, panelSearchResultsContent)
    button:SetSize(238, 20)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", DreamwayPanelSearchRowOnClick)
    button:SetScript("OnEnter", DreamwayPanelSearchRowOnEnter)
    button:SetScript("OnLeave", DreamwayPanelSearchRowOnLeave)
    button:SetScript("OnDragStart", DreamwayPanelSearchRowOnDragStart)
    button:SetScript("OnDragStop", DreamwayPanelSearchRowOnDragStop)

    button.requirementHighlight = button:CreateTexture(nil, "BACKGROUND")
    button.requirementHighlight:SetAllPoints(button)
    button.requirementHighlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.requirementHighlight:SetVertexColor(1, 0.82, 0.12, 0.18)
    button.requirementHighlight:Hide()

    button.label = CreateLabel(button, "GameFontHighlightSmall")
    button.label:SetPoint("LEFT", button, "LEFT", 0, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -108, 0)
    button.label:SetWordWrap(false)

    button.disclosure = CreateLabel(button, "GameFontNormalSmall")
    button.disclosure:SetPoint("LEFT", button, "LEFT", 0, 0)
    button.disclosure:SetWidth(8)
    button.disclosure:SetJustifyH("LEFT")
    button.disclosure:Hide()

    button.completeMark = button:CreateTexture(nil, "ARTWORK")
    button.completeMark:SetSize(12, 12)
    button.completeMark:SetPoint("RIGHT", button, "RIGHT", -92, 0)
    button.completeMark:SetTexture(COMPLETE_TEXTURE)
    button.completeMark:Hide()

    button.location = CreateLabel(button, "GameFontDisableSmall")
    button.location:SetPoint("RIGHT", button, "RIGHT", 0, 0)
    button.location:SetWidth(88)
    button.location:SetJustifyH("RIGHT")
    button.location:SetWordWrap(false)

    panelSearchResultButtons[index] = button
    return button
end

UpdatePanelSearchVisibleRows = function(force)
    if not panelSearchResultsContent or not panelSearchResultsScroll then
        return
    end

    local rows = panelSearchResultRows or {}
    local scrollOffset = panelSearchResultsScroll:GetVerticalScroll() or 0
    local scrollHeight = panelSearchResultsScroll:GetHeight() or 390
    local firstIndex = math.max(1, math.floor(scrollOffset / PANEL_SEARCH_ROW_HEIGHT) + 1)
    local visibleCount = math.max(1, math.ceil(scrollHeight / PANEL_SEARCH_ROW_HEIGHT) + PANEL_SEARCH_ROW_POOL_EXTRA)
    local previousFirstIndex = ProfileRecorder.searchRenderedFirstIndex
    local previousRowCount = ProfileRecorder.searchRenderedRowCount

    if not force
        and previousFirstIndex == firstIndex
        and previousRowCount == #rows
    then
        return
    end

    if not force and previousRowCount == #rows and previousFirstIndex and #panelSearchResultButtons >= visibleCount then
        local rowDelta = firstIndex - previousFirstIndex
        if rowDelta > 0 and rowDelta < visibleCount then
            for _ = 1, rowDelta do
                local recycled = table.remove(panelSearchResultButtons, 1)
                table.insert(panelSearchResultButtons, visibleCount, recycled)
            end
        elseif rowDelta < 0 and -rowDelta < visibleCount then
            for _ = 1, -rowDelta do
                local recycled = table.remove(panelSearchResultButtons, visibleCount)
                table.insert(panelSearchResultButtons, 1, recycled)
            end
        end
    end

    ProfileRecorder.searchRenderedFirstIndex = firstIndex
    ProfileRecorder.searchRenderedRowCount = #rows

    for poolIndex = 1, visibleCount do
        local rowIndex = firstIndex + poolIndex - 1
        local row = rows[rowIndex]
        local button = EnsurePanelSearchButton(poolIndex)
        if row and not force and button.renderedRowIndex == rowIndex then
            button:Show()
        elseif row then
            button.renderedRowIndex = rowIndex
            local isChain = row.kind == "chain"
            local rowInset = isChain and 0 or (row.standalone == true and 10 or 26)
            local rowWidth = isChain and 246 or (row.standalone == true and 236 or 220)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", panelSearchResultsContent, "TOPLEFT", rowInset, -PANEL_SEARCH_ROW_TOP_PAD - ((rowIndex - 1) * PANEL_SEARCH_ROW_HEIGHT))
            button:SetWidth(rowWidth)
            button.quest = nil
            button.chainKey = nil
            button.requirementQuestIds = nil
            button.prerequisiteWarning = nil
            button.dragSource = nil
            button.rowKind = row.kind
            button.requirementHighlight:Hide()
            button.disclosure:Hide()
            button.label:ClearAllPoints()
            button.label:SetPoint("LEFT", button, "LEFT", 0, 0)
            button.location:Show()
            if row.kind == "chain" then
                button:EnableMouse(true)
                button.chainKey = row.chainKey
                button.disclosure:SetText(row.collapsed and "+" or "-")
                button.disclosure:Show()
                button.label:ClearAllPoints()
                button.label:SetPoint("LEFT", button, "LEFT", 10, 0)
                button.label:SetPoint("RIGHT", button, "RIGHT", -92, 0)
                button.label:SetText(row.label or "Quest Chain")
                button.label:SetTextColor(1, 0.82, 0.12)
                button.location:SetText(row.location or "")
                button.location:SetTextColor(0.55, 0.55, 0.55)
                button.completeMark:Hide()
            elseif row.kind == "requirement" then
                button:EnableMouse(true)
                button.requirementQuestIds = row.requirementQuestIds or {}
                button.label:SetPoint("RIGHT", button, "RIGHT", 0, 0)
                button.label:SetText(row.label or "")
                button.label:SetTextColor(0.86, 0.86, 0.86)
                button.location:Hide()
                button.completeMark:Hide()
            elseif row.kind == "spacer" then
                button:EnableMouse(false)
                button.label:SetPoint("RIGHT", button, "RIGHT", 0, 0)
                button.label:SetText("")
                button.location:Hide()
                button.completeMark:Hide()
            else
                button:EnableMouse(true)
                button.label:SetPoint("RIGHT", button, "RIGHT", -108, 0)
                if not row.renderText then
                    row.renderText = ColoredQuestSearchDisplayName(row.quest)
                    row.isComplete = IsJourneyComplete(row.quest) and true or false
                    row.prerequisiteWarning = panelPrerequisiteWarnings[tonumber(row.quest and row.quest.id)]
                    if row.prerequisiteWarning then
                        row.renderText = WARNING_INLINE_TEXTURE .. " " .. row.renderText
                    end
                end
                button.label:SetText(row.renderText)
                button.label:SetTextColor(1, 1, 1)
                button.location:SetText(row.location or "")
                button.location:SetTextColor(0.65, 0.65, 0.65)
                button.completeMark:SetShown(row.isComplete)
                button.quest = row.quest
                button.prerequisiteWarning = row.prerequisiteWarning
                if not row.source or row.source.type ~= "completed" then
                    button.dragSource = row.source
                end
            end
            button:Show()
        else
            button.renderedRowIndex = nil
            button.rowKind = nil
            button.quest = nil
            button.chainKey = nil
            button.requirementQuestIds = nil
            button.prerequisiteWarning = nil
            button.dragSource = nil
            button.completeMark:Hide()
            button.requirementHighlight:Hide()
            button.disclosure:Hide()
            button:Hide()
        end
    end

    for poolIndex = visibleCount + 1, #panelSearchResultButtons do
        panelSearchResultButtons[poolIndex].renderedRowIndex = nil
        panelSearchResultButtons[poolIndex]:Hide()
    end
end

function SchedulePanelSearchVisibleRowsUpdate()
    if ProfileRecorder.searchScrollRefreshPending then
        return
    end
    ProfileRecorder.searchScrollRefreshPending = true
    C_Timer.After(0, function()
        ProfileRecorder.searchScrollRefreshPending = false
        UpdatePanelSearchVisibleRows()
    end)
end

RefreshPanelSearchResults = function()
    if not panelSearchResults or not panelSearchResultsContent then
        return
    end

    local previousScroll = panelSearchResultsScroll and panelSearchResultsScroll:GetVerticalScroll() or 0
    local resetScroll = ProfileRecorder.resetSearchScroll == true
    ProfileRecorder.resetSearchScroll = false

    if panelSearchFilters.mode ~= "search" then
        for _, button in ipairs(panelSearchResultButtons) do
            button:Hide()
        end
        if panelSearchEmptyLabel then
            panelSearchEmptyLabel:Hide()
        end
        if panelSearchFooterLabel then
            panelSearchFooterLabel:Hide()
        end
        panelSearchResultRows = {}
        ProfileRecorder.searchRenderedFirstIndex = nil
        ProfileRecorder.searchRenderedRowCount = nil
        return
    end

    for _, child in ipairs({ panelSearchResultsContent:GetChildren() }) do
        child:Hide()
    end
    for _, region in ipairs({ panelSearchResultsContent:GetRegions() }) do
        region:Hide()
        if region.SetText then
            region:SetText("")
        end
    end

    local journey = ActiveJourney()
    local rows, totalMatches, shownMatches = PanelSearchRows(journey)
    panelSearchResultRows = rows
    panelSearchResults:Show()

    if #rows == 0 then
        panelSearchResultRows = {}
        panelSearchResultsContent:SetSize(256, math.max(34, panelSearchResultsScroll:GetHeight() or 390))
        if not panelSearchEmptyLabel then
            panelSearchEmptyLabel = CreateLabel(panelSearchResultsContent, "GameFontDisableSmall")
            panelSearchEmptyLabel:SetPoint("TOPLEFT", panelSearchResultsContent, "TOPLEFT", 8, -PANEL_SEARCH_ROW_TOP_PAD)
            panelSearchEmptyLabel:SetWidth(238)
        end
        if NormalizedPanelSearch() == "" then
            panelSearchEmptyLabel:SetText("No unassigned quests.")
        else
            panelSearchEmptyLabel:SetText("No matching quests.")
        end
        panelSearchEmptyLabel:Show()
        if panelSearchFooterLabel then
            panelSearchFooterLabel:Hide()
        end
        if panelSearchResultsScroll.SetVerticalScroll then
            panelSearchResultsScroll:SetVerticalScroll(0)
        end
        UpdatePanelSearchVisibleRows(true)
        return
    end

    if totalMatches and shownMatches and totalMatches > shownMatches then
        if not panelSearchFooterLabel then
            panelSearchFooterLabel = CreateLabel(panelSearchResultsContent, "GameFontDisableSmall")
            panelSearchFooterLabel:SetWidth(238)
        end
        panelSearchFooterLabel:ClearAllPoints()
        panelSearchFooterLabel:SetPoint("TOPLEFT", panelSearchResultsContent, "TOPLEFT", 8, -PANEL_SEARCH_ROW_TOP_PAD - (#rows * PANEL_SEARCH_ROW_HEIGHT) - 2)
        panelSearchFooterLabel:SetText("Showing " .. tostring(shownMatches) .. " of " .. tostring(totalMatches) .. " matches. Keep typing to narrow results.")
        panelSearchFooterLabel:Show()
    elseif panelSearchFooterLabel then
        panelSearchFooterLabel:Hide()
    end

    local contentHeight = (#rows * PANEL_SEARCH_ROW_HEIGHT) + (PANEL_SEARCH_ROW_TOP_PAD * 2)
    if totalMatches and shownMatches and totalMatches > shownMatches then
        contentHeight = contentHeight + 34
    end
    panelSearchResultsContent:SetSize(256, math.max(contentHeight, panelSearchResultsScroll:GetHeight() or 390))
    if panelSearchResultsScroll.SetVerticalScroll then
        local viewportHeight = panelSearchResultsScroll:GetHeight() or 390
        local maxScroll = math.max(0, contentHeight - viewportHeight)
        panelSearchResultsScroll:SetVerticalScroll(resetScroll and 0 or math.min(previousScroll, maxScroll))
    end
    UpdatePanelSearchVisibleRows(true)
end

function panelSearchFilters.CreateCheckButton(parent, labelText)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(20, 20)
    check.label = CreateLabel(parent, "GameFontHighlightSmall")
    check.label:SetPoint("LEFT", check, "RIGHT", 0, 0)
    check.label:SetText(labelText or "")
    check.label:SetTextColor(0.88, 0.88, 0.88)
    return check
end

function panelSearchFilters.ApplyHexLabelColor(label, color)
    color = tostring(color or ""):gsub("#", "")
    if not label or #color ~= 6 then
        return
    end
    local red = tonumber(color:sub(1, 2), 16)
    local green = tonumber(color:sub(3, 4), 16)
    local blue = tonumber(color:sub(5, 6), 16)
    if red and green and blue then
        label:SetTextColor(red / 255, green / 255, blue / 255)
    end
end

function panelSearchFilters.RefreshControls()
    panelSearchFilters.Ensure()

    if panelSearchFilters.scopeChecks.starts then
        panelSearchFilters.scopeChecks.starts:SetChecked(panelSearchFilters.starts)
    end
    if panelSearchFilters.scopeChecks.objectives then
        panelSearchFilters.scopeChecks.objectives:SetChecked(panelSearchFilters.objectives)
    end
    if panelSearchFilters.scopeChecks.ends then
        panelSearchFilters.scopeChecks.ends:SetChecked(panelSearchFilters.ends)
    end

    for zoneId, check in pairs(panelSearchFilters.zoneChecks) do
        check:SetChecked(panelSearchFilters.zoneIds[tonumber(zoneId)] == true)
    end
    for factionId, check in pairs(panelSearchFilters.factionChecks) do
        check:SetChecked(panelSearchFilters.factions[tostring(factionId)] == true)
    end
    for mask, check in pairs(panelSearchFilters.raceChecks) do
        check:SetChecked(panelSearchFilters.raceMasks[tonumber(mask)] == true)
    end
    for mask, check in pairs(panelSearchFilters.classChecks) do
        check:SetChecked(panelSearchFilters.classMasks[tonumber(mask)] == true)
    end
    for typeId, check in pairs(panelSearchFilters.typeChecks) do
        check:SetChecked(panelSearchFilters.typeIds[tostring(typeId)] == true)
    end
end

function panelSearchFilters.HideRows()
    for _, button in ipairs(panelSearchResultButtons) do
        button:Hide()
    end
    if panelSearchEmptyLabel then
        panelSearchEmptyLabel:Hide()
    end
    if panelSearchFooterLabel then
        panelSearchFooterLabel:Hide()
    end
end

function panelSearchFilters.SetAllChainsCollapsed(collapsed)
    ProfileRecorder.panelCollapsedSearchChains = ProfileRecorder.panelCollapsedSearchChains or {}
    for _, row in ipairs(panelSearchResultRows or {}) do
        if row.kind == "chain" and row.chainKey then
            ProfileRecorder.panelCollapsedSearchChains[row.chainKey] = collapsed and true or false
        end
    end
    RefreshPanelSearchResults()
end

function panelSearchFilters.SetRegionShown(region, shown)
    if not region then
        return
    end
    if shown then
        region:Show()
    else
        region:Hide()
    end
end

function panelSearchFilters.SetCheckGroupShown(checks, shown)
    for _, check in pairs(checks or {}) do
        panelSearchFilters.SetRegionShown(check, shown)
        panelSearchFilters.SetRegionShown(check.label, shown)
    end
end

function panelSearchFilters.SetLabelGroupShown(labels, shown)
    for _, label in ipairs(labels or {}) do
        panelSearchFilters.SetRegionShown(label, shown)
    end
end

function panelSearchFilters.SetAllForMode(checked)
    panelSearchFilters.Ensure()
    local modeName = panelSearchFilters.mode

    if modeName == "character" then
        for _, faction in ipairs(panelSearchFilters.FilterFactions()) do
            if faction and faction.id then
                panelSearchFilters.factions[tostring(faction.id)] = checked and true or false
            end
        end
        for _, race in ipairs(panelSearchFilters.FilterRaces()) do
            local mask = tonumber(race and race.m)
            if mask then
                panelSearchFilters.raceMasks[mask] = checked and true or false
            end
        end
        for _, classInfo in ipairs(panelSearchFilters.FilterClasses()) do
            local mask = tonumber(classInfo and classInfo.m)
            if mask then
                panelSearchFilters.classMasks[mask] = checked and true or false
            end
        end
    elseif modeName == "type" then
        for _, typeInfo in ipairs(panelSearchFilters.FilterTypes()) do
            if typeInfo and typeInfo.id then
                panelSearchFilters.typeIds[tostring(typeInfo.id)] = checked and true or false
            end
        end
    else
        panelSearchFilters.zoneIds[panelSearchFilters.unknownZoneId] = checked and true or false
        for _, zone in ipairs(panelSearchFilters.FilterZones()) do
            local zoneId = tonumber(zone and zone.id)
            if zoneId then
                panelSearchFilters.zoneIds[zoneId] = checked and true or false
            end
        end
    end

    panelSearchFilters.RefreshControls()
end

function panelSearchFilters.SetMode(modeName)
    if modeName ~= "character" and modeName ~= "zones" and modeName ~= "type" then
        modeName = "search"
    end
    panelSearchFilters.mode = modeName
    local isSearch = panelSearchFilters.mode == "search"
    local isCharacter = panelSearchFilters.mode == "character"
    local isZones = panelSearchFilters.mode == "zones"
    local isType = panelSearchFilters.mode == "type"

    if panelSearchFilters.headerLabel then
        panelSearchFilters.SetRegionShown(panelSearchFilters.headerLabel, isSearch)
        panelSearchFilters.headerLabel:SetText("Quest Search")
    end
    for key, button in pairs(panelSearchFilters.filterButtons or {}) do
        panelSearchFilters.SetRegionShown(button, (key == "open" and isSearch) or (key ~= "open" and not isSearch))
        if button.SetActive then
            button:SetActive(key == panelSearchFilters.mode)
        end
    end
    panelSearchFilters.SetRegionShown(panelSearchFilters.searchButton, not isSearch)
    panelSearchFilters.SetRegionShown(panelSearchFilters.collapseAllButton, isSearch)
    panelSearchFilters.SetRegionShown(panelSearchFilters.expandAllButton, isSearch)
    panelSearchFilters.SetRegionShown(panelSearchBox, isSearch)
    panelSearchFilters.SetRegionShown(panelSearchResultsScroll, isSearch)
    panelSearchFilters.SetRegionShown(panelSearchResultsContent, isSearch)

    if not isSearch then
        panelSearchFilters.HideRows()
    end

    panelSearchFilters.SetCheckGroupShown(panelSearchFilters.scopeChecks, isZones)
    panelSearchFilters.SetCheckGroupShown(panelSearchFilters.zoneChecks, isZones)
    panelSearchFilters.SetCheckGroupShown(panelSearchFilters.factionChecks, isCharacter)
    panelSearchFilters.SetCheckGroupShown(panelSearchFilters.raceChecks, isCharacter)
    panelSearchFilters.SetCheckGroupShown(panelSearchFilters.classChecks, isCharacter)
    panelSearchFilters.SetCheckGroupShown(panelSearchFilters.typeChecks, isType)
    panelSearchFilters.SetLabelGroupShown(panelSearchFilters.characterLabels, isCharacter)
    panelSearchFilters.SetLabelGroupShown(panelSearchFilters.typeLabels, isType)
    panelSearchFilters.SetRegionShown(panelSearchFilters.separator, not isSearch)
    panelSearchFilters.SetRegionShown(panelSearchFilters.checkAllButton, not isSearch)
    panelSearchFilters.SetRegionShown(panelSearchFilters.uncheckAllButton, not isSearch)
    panelSearchFilters.SetRegionShown(panelSearchFilters.scroll, not isSearch)
    panelSearchFilters.SetRegionShown(panelSearchFilters.content, not isSearch)

    if isZones then
        panelSearchFilters.scopeChecks.starts:ClearAllPoints()
        panelSearchFilters.scopeChecks.starts:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 8, -34)
        panelSearchFilters.scopeChecks.objectives:ClearAllPoints()
        panelSearchFilters.scopeChecks.objectives:SetPoint("LEFT", panelSearchFilters.scopeChecks.starts.label, "RIGHT", 8, 0)
        panelSearchFilters.scopeChecks.ends:ClearAllPoints()
        panelSearchFilters.scopeChecks.ends:SetPoint("LEFT", panelSearchFilters.scopeChecks.objectives.label, "RIGHT", 8, 0)
        panelSearchFilters.separator:ClearAllPoints()
        panelSearchFilters.separator:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 10, -62)
        panelSearchFilters.separator:SetPoint("TOPRIGHT", panelSearchResults, "TOPRIGHT", -10, -62)
        panelSearchFilters.checkAllButton:ClearAllPoints()
        panelSearchFilters.checkAllButton:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 10, -71)
        panelSearchFilters.scroll:ClearAllPoints()
        panelSearchFilters.scroll:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 8, -99)
    elseif not isSearch then
        panelSearchFilters.separator:ClearAllPoints()
        panelSearchFilters.separator:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 10, -34)
        panelSearchFilters.separator:SetPoint("TOPRIGHT", panelSearchResults, "TOPRIGHT", -10, -34)
        panelSearchFilters.checkAllButton:ClearAllPoints()
        panelSearchFilters.checkAllButton:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 10, -43)
        panelSearchFilters.scroll:ClearAllPoints()
        panelSearchFilters.scroll:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 8, -71)
    end
    if not isSearch then
        panelSearchFilters.scroll:SetPoint("BOTTOMRIGHT", panelSearchResults, "BOTTOMRIGHT", -28, 8)
    end

    if isSearch then
        RefreshPanelSearchResults()
    else
        panelSearchFilters.RefreshControls()
    end
end

function panelSearchFilters.CreateControls()
    panelSearchFilters.Ensure()

    panelSearchFilters.scopeChecks.starts = panelSearchFilters.CreateCheckButton(panelSearchResults, "Starts")
    panelSearchFilters.scopeChecks.starts:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 8, -9)
    panelSearchFilters.scopeChecks.starts:SetScript("OnClick", function(self)
        panelSearchFilters.starts = self:GetChecked() and true or false
    end)

    panelSearchFilters.scopeChecks.objectives = panelSearchFilters.CreateCheckButton(panelSearchResults, "Objectives")
    panelSearchFilters.scopeChecks.objectives:SetPoint("LEFT", panelSearchFilters.scopeChecks.starts.label, "RIGHT", 8, 0)
    panelSearchFilters.scopeChecks.objectives:SetScript("OnClick", function(self)
        panelSearchFilters.objectives = self:GetChecked() and true or false
    end)

    panelSearchFilters.scopeChecks.ends = panelSearchFilters.CreateCheckButton(panelSearchResults, "Ends")
    panelSearchFilters.scopeChecks.ends:SetPoint("LEFT", panelSearchFilters.scopeChecks.objectives.label, "RIGHT", 8, 0)
    panelSearchFilters.scopeChecks.ends:SetScript("OnClick", function(self)
        panelSearchFilters.ends = self:GetChecked() and true or false
    end)

    panelSearchFilters.separator = panelSearchResults:CreateTexture(nil, "ARTWORK")
    panelSearchFilters.separator:SetTexture("Interface\\Buttons\\WHITE8X8")
    panelSearchFilters.separator:SetVertexColor(0.55, 0.55, 0.55, 0.45)
    panelSearchFilters.separator:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 10, -39)
    panelSearchFilters.separator:SetPoint("TOPRIGHT", panelSearchResults, "TOPRIGHT", -10, -39)
    panelSearchFilters.separator:SetHeight(1)

    panelSearchFilters.checkAllButton = CreateTinyButton(panelSearchResults, "Check all", 74)
    panelSearchFilters.checkAllButton:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 10, -48)
    panelSearchFilters.checkAllButton:SetScript("OnClick", function()
        panelSearchFilters.SetAllForMode(true)
    end)

    panelSearchFilters.uncheckAllButton = CreateTinyButton(panelSearchResults, "Uncheck all", 88)
    panelSearchFilters.uncheckAllButton:SetPoint("LEFT", panelSearchFilters.checkAllButton, "RIGHT", 8, 0)
    panelSearchFilters.uncheckAllButton:SetScript("OnClick", function()
        panelSearchFilters.SetAllForMode(false)
    end)

    panelSearchFilters.scroll = CreateFrame("ScrollFrame", nil, panelSearchResults, "UIPanelScrollFrameTemplate")
    panelSearchFilters.scroll:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 8, -76)
    panelSearchFilters.scroll:SetPoint("BOTTOMRIGHT", panelSearchResults, "BOTTOMRIGHT", -28, 8)

    panelSearchFilters.content = CreateFrame("Frame", nil, panelSearchFilters.scroll)
    panelSearchFilters.content:SetWidth(244)
    panelSearchFilters.scroll:SetScrollChild(panelSearchFilters.content)

    local y = -2
    local unknownCheck = panelSearchFilters.CreateCheckButton(panelSearchFilters.content, "Unknown")
    unknownCheck:SetPoint("TOPLEFT", panelSearchFilters.content, "TOPLEFT", 0, y)
    unknownCheck.label:SetWidth(214)
    unknownCheck.label:SetWordWrap(false)
    unknownCheck:SetScript("OnClick", function(self)
        panelSearchFilters.zoneIds[panelSearchFilters.unknownZoneId] = self:GetChecked() and true or false
    end)
    panelSearchFilters.zoneChecks[panelSearchFilters.unknownZoneId] = unknownCheck
    y = y - 22

    for _, zone in ipairs(panelSearchFilters.FilterZones()) do
        local zoneId = tonumber(zone and zone.id)
        if zoneId then
            local name = tostring(zone.n or zone.name or ("Zone " .. tostring(zoneId)))
            local range = tostring(zone.r or zone.levelRange or "")
            local label = range ~= "" and (name .. " [" .. range .. "]") or name
            local check = panelSearchFilters.CreateCheckButton(panelSearchFilters.content, label)
            check:SetPoint("TOPLEFT", panelSearchFilters.content, "TOPLEFT", 0, y)
            check.label:SetWidth(214)
            check.label:SetWordWrap(false)
            check:SetScript("OnClick", function(self)
                panelSearchFilters.zoneIds[zoneId] = self:GetChecked() and true or false
            end)
            panelSearchFilters.zoneChecks[zoneId] = check
            y = y - 22
        end
    end
    local minY = y

    local function createHeading(text, yOffset)
        local label = CreateLabel(panelSearchFilters.content, "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", panelSearchFilters.content, "TOPLEFT", 0, yOffset)
        label:SetText(text)
        label:SetTextColor(1, 0.82, 0.12)
        panelSearchFilters.characterLabels[#panelSearchFilters.characterLabels + 1] = label
        return yOffset - 20
    end

    y = -2
    y = createHeading("Faction", y)
    for _, faction in ipairs(panelSearchFilters.FilterFactions()) do
        local id = faction and faction.id
        if id then
            local check = panelSearchFilters.CreateCheckButton(panelSearchFilters.content, tostring(faction.n or id))
            check:SetPoint("TOPLEFT", panelSearchFilters.content, "TOPLEFT", 0, y)
            check.label:SetWidth(214)
            check.label:SetWordWrap(false)
            panelSearchFilters.ApplyHexLabelColor(check.label, faction.c)
            check:SetScript("OnClick", function(self)
                panelSearchFilters.factions[tostring(id)] = self:GetChecked() and true or false
            end)
            panelSearchFilters.factionChecks[tostring(id)] = check
            y = y - 22
        end
    end

    y = y - 6
    y = createHeading("Race", y)
    for _, race in ipairs(panelSearchFilters.FilterRaces()) do
        local mask = tonumber(race and race.m)
        if mask then
            local name = tostring(race.n or ("Race " .. tostring(mask)))
            local faction = race.f and (" [" .. tostring(race.f) .. "]") or ""
            local check = panelSearchFilters.CreateCheckButton(panelSearchFilters.content, name .. faction)
            check:SetPoint("TOPLEFT", panelSearchFilters.content, "TOPLEFT", 0, y)
            check.label:SetWidth(214)
            check.label:SetWordWrap(false)
            panelSearchFilters.ApplyHexLabelColor(check.label, race.c)
            check:SetScript("OnClick", function(self)
                panelSearchFilters.raceMasks[mask] = self:GetChecked() and true or false
            end)
            panelSearchFilters.raceChecks[mask] = check
            y = y - 22
        end
    end

    y = y - 6
    y = createHeading("Class", y)
    for _, classInfo in ipairs(panelSearchFilters.FilterClasses()) do
        local mask = tonumber(classInfo and classInfo.m)
        if mask then
            local check = panelSearchFilters.CreateCheckButton(panelSearchFilters.content, tostring(classInfo.n or ("Class " .. tostring(mask))))
            check:SetPoint("TOPLEFT", panelSearchFilters.content, "TOPLEFT", 0, y)
            check.label:SetWidth(214)
            check.label:SetWordWrap(false)
            panelSearchFilters.ApplyHexLabelColor(check.label, classInfo.c)
            check:SetScript("OnClick", function(self)
                panelSearchFilters.classMasks[mask] = self:GetChecked() and true or false
            end)
            panelSearchFilters.classChecks[mask] = check
            y = y - 22
        end
    end
    minY = math.min(minY, y)

    local typeY = -2
    local typeHeading = CreateLabel(panelSearchFilters.content, "GameFontNormalSmall")
    typeHeading:SetPoint("TOPLEFT", panelSearchFilters.content, "TOPLEFT", 0, typeY)
    typeHeading:SetText("Quest Types")
    typeHeading:SetTextColor(1, 0.82, 0.12)
    panelSearchFilters.typeLabels[#panelSearchFilters.typeLabels + 1] = typeHeading
    typeY = typeY - 20
    for _, typeInfo in ipairs(panelSearchFilters.FilterTypes()) do
        local id = typeInfo and typeInfo.id
        if id then
            local check = panelSearchFilters.CreateCheckButton(panelSearchFilters.content, tostring(typeInfo.n or id))
            check:SetPoint("TOPLEFT", panelSearchFilters.content, "TOPLEFT", 0, typeY)
            check.label:SetWidth(214)
            check.label:SetWordWrap(false)
            check:SetScript("OnClick", function(self)
                panelSearchFilters.typeIds[tostring(id)] = self:GetChecked() and true or false
            end)
            panelSearchFilters.typeChecks[tostring(id)] = check
            typeY = typeY - 22
        end
    end
    minY = math.min(minY, typeY)

    panelSearchFilters.content:SetHeight(math.max(24, -minY + 8))

    panelSearchFilters.SetMode("search")
end

local function CreateJourneyPanel()
    panelFrame = CreateBackdropFrame("Dreamway_JourneyPanel", UIParent)
    panelFrame:SetSize(1080, 540)
    panelFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panelFrame:SetFrameStrata("DIALOG")
    panelFrame:SetMovable(true)
    panelFrame:EnableMouse(true)
    panelFrame:RegisterForDrag("LeftButton")
    panelFrame:SetScript("OnDragStart", panelFrame.StartMoving)
    panelFrame:SetScript("OnDragStop", panelFrame.StopMovingOrSizing)
    SetFrameBackdrop(panelFrame, 0.02, 0.02, 0.025, 0.94, 0.75)

    panelFrame.logo = panelFrame:CreateTexture(nil, "ARTWORK")
    panelFrame.logo:SetSize(30, 30)
    panelFrame.logo:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 14, -9)
    panelFrame.logo:SetTexture("Interface\\AddOns\\DreamwayQuestPlanner\\Media\\DreamwayIcon")

    panelFrame.title = CreateLabel(panelFrame, "GameFontNormalLarge")
    panelFrame.title:SetPoint("LEFT", panelFrame.logo, "RIGHT", 7, 0)
    panelFrame.title:SetWidth(330)
    panelFrame.title:SetWordWrap(false)
    panelFrame.title:SetText("Dreamway")
    panelFrame.title:SetTextColor(1, 0.82, 0.12)

    local closeButton = CreateTinyButton(panelFrame, "x", 22)
    closeButton:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -12, -10)
    closeButton:SetScript("OnClick", function()
        DreamwayCloseJourneyMetadataMenu()
        panelFrame:Hide()
    end)

    local manageButton = CreateTinyButton(panelFrame, "Manage Journeys", 124)
    panelJourneyManager.toggleButton = manageButton
    manageButton:SetPoint("TOPRIGHT", closeButton, "TOPLEFT", -8, 0)
    manageButton:SetScript("OnClick", function()
        DreamwayCloseJourneyMetadataMenu()
        if panelImportArea then
            panelImportArea:Hide()
        end
        if panelExportArea then
            panelExportArea:Hide()
        end
        if panelJourneyManager.frame then
            panelJourneyManager.frame:SetShown(not panelJourneyManager.frame:IsShown())
        end
    end)

    panelJourneyManager.hiddenDrop = CreateBackdropFrame(nil, panelFrame)
    panelJourneyManager.hiddenDrop:SetSize(86, 22)
    panelJourneyManager.hiddenDrop:SetPoint("RIGHT", manageButton, "LEFT", -8, 0)
    panelJourneyManager.hiddenDrop:EnableMouse(true)
    SetFrameBackdrop(panelJourneyManager.hiddenDrop, 0.24, 0.025, 0.025, 0.92, 0.8)
    panelJourneyManager.hiddenDrop.label = CreateLabel(panelJourneyManager.hiddenDrop, "GameFontNormalSmall")
    panelJourneyManager.hiddenDrop.label:SetPoint("CENTER", panelJourneyManager.hiddenDrop, "CENTER", 0, 0)
    panelJourneyManager.hiddenDrop.label:SetText("Hidden")
    panelJourneyManager.hiddenDrop.label:SetTextColor(1, 0.38, 0.32)

    panelStatusText = CreateLabel(panelFrame, "GameFontHighlightSmall")
    panelStatusText:SetPoint("LEFT", panelFrame.title, "RIGHT", 12, 0)
    panelStatusText:SetPoint("RIGHT", panelJourneyManager.hiddenDrop, "LEFT", -10, 0)
    panelStatusText:SetWordWrap(false)
    panelStatusText:SetText("Click a batch to make it current. Drag quests between batches or Hidden.")
    panelStatusText:SetTextColor(0.75, 0.75, 0.75)

    panelFrame.metadataText = CreateLabel(panelFrame, "GameFontDisableSmall")
    panelFrame.metadataText:SetPoint("TOPLEFT", panelFrame.title, "BOTTOMLEFT", 0, -5)
    panelFrame.metadataText:SetPoint("RIGHT", panelFrame, "RIGHT", -330, 0)
    panelFrame.metadataText:SetWordWrap(false)

    panelSearchResults = CreateBackdropFrame("Dreamway_JourneySearchColumn", panelFrame)
    panelSearchResults:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -18, -58)
    panelSearchResults:SetPoint("BOTTOMRIGHT", panelFrame, "BOTTOMRIGHT", -18, 24)
    panelSearchResults:SetWidth(286)
    panelSearchResults:SetFrameLevel(panelFrame:GetFrameLevel() + 2)
    SetFrameBackdrop(panelSearchResults, 0.01, 0.01, 0.012, 0.86, 0.4)

    panelShowAssignedCheck = panelSearchFilters.CreateCheckButton(panelFrame, "Hide assigned")
    panelShowAssignedCheck:SetPoint("BOTTOMLEFT", panelSearchResults, "TOPLEFT", 0, 3)
    panelShowAssignedCheck.label:SetWidth(105)
    panelShowAssignedCheck.label:SetWordWrap(false)
    panelShowAssignedCheck:SetChecked(not panelShowAssignedQuests)
    panelShowAssignedCheck:SetScript("OnClick", function(self)
        panelShowAssignedQuests = not (self:GetChecked() and true or false)
        SaveDb()
        RefreshPanelSearchResults()
    end)

    panelJourneyManager.previousBatchCheck = panelSearchFilters.CreateCheckButton(panelFrame, "Previous in progress")
    panelJourneyManager.previousBatchCheck:SetPoint("BOTTOMLEFT", panelSearchResults, "TOPLEFT", 132, 3)
    panelJourneyManager.previousBatchCheck.label:SetWidth(140)
    panelJourneyManager.previousBatchCheck.label:SetWordWrap(false)
    panelJourneyManager.previousBatchCheck:SetChecked(ProfileRecorder.showPreviousBatchQuests == true)
    panelJourneyManager.previousBatchCheck:SetScript("OnClick", function(self)
        ProfileRecorder.showPreviousBatchQuests = self:GetChecked() and true or false
        SaveDb()
        RefreshDreamwayTracker()
    end)
    ConfigurePanelTooltip(
        panelJourneyManager.previousBatchCheck,
        "Previous in progress",
        "Include level-appropriate quests from earlier batches when they are still incomplete and in your quest log."
    )

    panelSearchFilters.headerLabel = CreateLabel(panelSearchResults, "GameFontNormalSmall")
    panelSearchFilters.headerLabel:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 10, -10)
    panelSearchFilters.headerLabel:SetText("Quest Search")
    panelSearchFilters.headerLabel:SetTextColor(1, 0.82, 0.12)

    panelSearchFilters.expandAllButton = CreateTinyButton(panelSearchResults, "+", 22)
    panelSearchFilters.expandAllButton:SetPoint("TOPRIGHT", panelSearchResults, "TOPRIGHT", -10, -8)
    panelSearchFilters.expandAllButton:SetScript("OnClick", function()
        panelSearchFilters.SetAllChainsCollapsed(false)
    end)

    panelSearchFilters.collapseAllButton = CreateTinyButton(panelSearchResults, "-", 22)
    panelSearchFilters.collapseAllButton:SetPoint("RIGHT", panelSearchFilters.expandAllButton, "LEFT", -4, 0)
    panelSearchFilters.collapseAllButton:SetScript("OnClick", function()
        panelSearchFilters.SetAllChainsCollapsed(true)
    end)

    panelSearchFilters.filterButtons.open = CreateTinyButton(panelSearchResults, "Search filters", 94)
    panelSearchFilters.filterButtons.open:SetPoint("RIGHT", panelSearchFilters.collapseAllButton, "LEFT", -6, 0)
    panelSearchFilters.filterButtons.open:SetScript("OnClick", function()
        panelSearchFilters.SetMode("zones")
    end)

    panelSearchFilters.filterButtons.character = CreateTinyButton(panelSearchResults, "Character", 74)
    panelSearchFilters.filterButtons.character:SetPoint("TOPLEFT", panelSearchResults, "TOPLEFT", 10, -8)
    panelSearchFilters.filterButtons.character:SetScript("OnClick", function()
        panelSearchFilters.SetMode("character")
    end)

    panelSearchFilters.filterButtons.zones = CreateTinyButton(panelSearchResults, "Zones", 54)
    panelSearchFilters.filterButtons.zones:SetPoint("LEFT", panelSearchFilters.filterButtons.character, "RIGHT", 5, 0)
    panelSearchFilters.filterButtons.zones:SetScript("OnClick", function()
        panelSearchFilters.SetMode("zones")
    end)

    panelSearchFilters.filterButtons.type = CreateTinyButton(panelSearchResults, "Type", 46)
    panelSearchFilters.filterButtons.type:SetPoint("LEFT", panelSearchFilters.filterButtons.zones, "RIGHT", 5, 0)
    panelSearchFilters.filterButtons.type:SetScript("OnClick", function()
        panelSearchFilters.SetMode("type")
    end)

    panelSearchFilters.searchButton = CreateTinyButton(panelSearchResults, "Search", 58)
    panelSearchFilters.searchButton:SetPoint("TOPRIGHT", panelSearchResults, "TOPRIGHT", -10, -8)
    panelSearchFilters.searchButton:SetScript("OnClick", function()
        panelSearchFilters.SetMode("search")
    end)

    panelSearchBox = CreateFrame("EditBox", "Dreamway_JourneySearchBox", panelSearchResults, BackdropTemplateMixin and "BackdropTemplate")
    panelSearchBox:SetSize(246, 22)
    panelSearchBox:SetPoint("TOPLEFT", panelSearchFilters.headerLabel, "BOTTOMLEFT", 0, -6)
    panelSearchBox:SetAutoFocus(false)
    panelSearchBox:SetFontObject(ChatFontNormal)
    panelSearchBox:SetTextInsets(6, 6, 2, 2)
    panelSearchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    panelSearchBox:SetScript("OnTextChanged", function(self)
        panelSearchText = string.lower(self:GetText() or "")
        ProfileRecorder.resetSearchScroll = true
        if RefreshPanel then
            RefreshPanel()
        end
    end)
    SetFrameBackdrop(panelSearchBox, 0.01, 0.01, 0.012, 0.86, 0.38)

    panelSearchResultsScroll = CreateFrame("ScrollFrame", nil, panelSearchResults, "UIPanelScrollFrameTemplate")
    panelSearchResultsScroll:SetPoint("TOPLEFT", panelSearchBox, "BOTTOMLEFT", 0, -6)
    panelSearchResultsScroll:SetPoint("BOTTOMRIGHT", panelSearchResults, "BOTTOMRIGHT", -28, 8)
    panelSearchResultsScroll:HookScript("OnVerticalScroll", function()
        SchedulePanelSearchVisibleRowsUpdate()
    end)

    panelSearchResultsContent = CreateFrame("Frame", nil, panelSearchResultsScroll)
    panelSearchResultsContent:SetSize(256, 390)
    panelSearchResultsScroll:SetScrollChild(panelSearchResultsContent)
    panelSearchFilters.CreateControls()

    panelBatchScroll = CreateFrame("ScrollFrame", "Dreamway_JourneyScroll", panelFrame, "UIPanelScrollFrameTemplate")
    panelBatchScroll:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 18, -58)
    panelBatchScroll:SetPoint("BOTTOMRIGHT", panelFrame, "BOTTOMRIGHT", -326, 24)
    panelBatchScroll:HookScript("OnVerticalScroll", function()
        UpdatePanelBatchVisibleColumns()
    end)

    panelBatchContent = CreateFrame("Frame", nil, panelBatchScroll)
    panelBatchContent:SetSize(710, 365)
    panelBatchScroll:SetScrollChild(panelBatchContent)

    panelImportArea = CreateBackdropFrame(nil, panelFrame)
    panelImportArea:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 18, -58)
    panelImportArea:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -18, -58)
    panelImportArea:SetHeight(190)
    panelImportArea:SetFrameLevel(panelFrame:GetFrameLevel() + 12)
    SetFrameBackdrop(panelImportArea, 0.01, 0.01, 0.012, 0.98, 0.65)

    local importLabel = CreateLabel(panelImportArea, "GameFontNormal")
    importLabel:SetPoint("TOPLEFT", panelImportArea, "TOPLEFT", 12, -10)
    importLabel:SetText("Paste Journey string from the web app")

    local importScroll = CreateFrame("ScrollFrame", nil, panelImportArea, "UIPanelScrollFrameTemplate")
    importScroll:SetPoint("TOPLEFT", panelImportArea, "TOPLEFT", 12, -34)
    importScroll:SetPoint("BOTTOMRIGHT", panelImportArea, "BOTTOMRIGHT", -32, 42)

    panelImportEditBox = CreateFrame("EditBox", nil, importScroll)
    panelImportEditBox:SetMultiLine(true)
    panelImportEditBox:SetAutoFocus(false)
    panelImportEditBox:SetFontObject(ChatFontNormal)
    panelImportEditBox:SetWidth(990)
    panelImportEditBox:SetHeight(116)
    panelImportEditBox:SetTextInsets(4, 4, 4, 4)
    panelImportEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    importScroll:SetScrollChild(panelImportEditBox)

    local doImportButton = CreateTinyButton(panelImportArea, "Import", 62)
    doImportButton:SetPoint("BOTTOMRIGHT", panelImportArea, "BOTTOMRIGHT", -12, 12)
    doImportButton:SetScript("OnClick", function()
        local ok, message = ImportJourneyText(panelImportEditBox:GetText())
        panelStatusText:SetText(message)
        panelStatusText:SetTextColor(ok and 0.35 or 1, ok and 1 or 0.25, ok and 0.35 or 0.25)
        if ok then
            panelImportEditBox:SetText("")
            panelImportEditBox:ClearFocus()
            panelImportArea:Hide()
        end
    end)

    local clearButton = CreateTinyButton(panelImportArea, "Clear", 56)
    clearButton:SetPoint("RIGHT", doImportButton, "LEFT", -8, 0)
    clearButton:SetScript("OnClick", function()
        panelImportEditBox:SetText("")
    end)

    panelImportArea:Hide()

    panelExportArea = CreateBackdropFrame(nil, panelFrame)
    panelExportArea:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 18, -58)
    panelExportArea:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -18, -58)
    panelExportArea:SetHeight(190)
    panelExportArea:SetFrameLevel(panelFrame:GetFrameLevel() + 12)
    SetFrameBackdrop(panelExportArea, 0.01, 0.01, 0.012, 0.98, 0.65)

    local exportLabel = CreateLabel(panelExportArea, "GameFontNormal")
    exportLabel:SetPoint("TOPLEFT", panelExportArea, "TOPLEFT", 12, -10)
    exportLabel:SetText("Copy this Journey string into the web app")

    local exportScroll = CreateFrame("ScrollFrame", nil, panelExportArea, "UIPanelScrollFrameTemplate")
    exportScroll:SetPoint("TOPLEFT", panelExportArea, "TOPLEFT", 12, -34)
    exportScroll:SetPoint("BOTTOMRIGHT", panelExportArea, "BOTTOMRIGHT", -32, 42)

    panelExportEditBox = CreateFrame("EditBox", nil, exportScroll)
    panelExportEditBox:SetMultiLine(true)
    panelExportEditBox:SetAutoFocus(false)
    panelExportEditBox:SetFontObject(ChatFontNormal)
    panelExportEditBox:SetWidth(990)
    panelExportEditBox:SetHeight(116)
    panelExportEditBox:SetTextInsets(4, 4, 4, 4)
    panelExportEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    exportScroll:SetScrollChild(panelExportEditBox)

    local closeExportButton = CreateTinyButton(panelExportArea, "Close", 56)
    closeExportButton:SetPoint("BOTTOMRIGHT", panelExportArea, "BOTTOMRIGHT", -12, 12)
    closeExportButton:SetScript("OnClick", function()
        panelExportEditBox:ClearFocus()
        panelExportArea:Hide()
    end)

    local selectExportButton = CreateTinyButton(panelExportArea, "Select All", 76)
    selectExportButton:SetPoint("RIGHT", closeExportButton, "LEFT", -8, 0)
    selectExportButton:SetScript("OnClick", function()
        panelExportEditBox:SetFocus()
        panelExportEditBox:HighlightText()
    end)

    panelExportArea:Hide()
    DreamwayCreateJourneyManager()
    panelFrame:Hide()
end

local function HookQuestieUpdates()
    local tracker = GetQuestieTracker()
    if tracker and tracker.Update and not tracker.DreamwayHooked then
        hooksecurefunc(tracker, "Update", function()
            if mode == MODE_DREAMWAY and initialized then
                DreamwayScheduleUiRefresh(false)
            end
        end)
        tracker.DreamwayHooked = true
    end

    if tracker and tracker.UpdateFormatting and not tracker.DreamwayFormattingHooked then
        hooksecurefunc(tracker, "UpdateFormatting", function()
            if mode == MODE_DREAMWAY and initialized then
                DreamwayScheduleUiRefresh(false)
            end
        end)
        tracker.DreamwayFormattingHooked = true
    end

    if headerFrame and not headerFrame.DreamwayHooked then
        headerFrame:HookScript("OnShow", function(self)
            if mode == MODE_DREAMWAY then
                self:Hide()
            end
        end)
        headerFrame.DreamwayHooked = true
    end

    if questFrame and not questFrame.DreamwayHooked then
        questFrame:HookScript("OnShow", function(self)
            if mode == MODE_DREAMWAY then
                self:Hide()
            end
        end)
        questFrame.DreamwayHooked = true
    end
end

local function TryInitialize()
    if initialized then
        return
    end

    NormalizeDb()

    baseFrame = _G.Questie_BaseFrame
    headerFrame = _G.Questie_HeaderFrame
    questFrame = _G.TrackedQuests

    if not baseFrame or not headerFrame or not questFrame then
        C_Timer.After(0.5, TryInitialize)
        return
    end

    CreateToggle()
    CreateDreamwayTracker()
    CreateJourneyPanel()
    ProfileRecorder.RegisterQuestieCallbacks()
    HookQuestieUpdates()

    baseFrame:HookScript("OnShow", function()
        if mode == MODE_DREAMWAY then
            DreamwayScheduleUiRefresh(false)
        end
    end)

    initialized = true
    ApplyMode()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_WATCH_UPDATE")
events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("UI_INFO_MESSAGE")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, ...)
    local firstArgument = select(1, ...)
    if event == "PLAYER_LOGIN" then
        ProfileRecorder.RefreshCharacterProfile()
        C_Timer.After(1, function()
            ProfileRecorder.RefreshCharacterProfile()
            ProfileRecorder.RecordEvent(ProfileRecorder.EVENT_LOGIN)
            ProfileRecorder.RegisterQuestieCallbacks()
            ProfileRecorder.RefreshQuestObjectiveEventState(false)
        end)
        C_Timer.After(5, ProfileRecorder.RegisterQuestieCallbacks)
        TryInitialize()
    elseif event == "PLAYER_LOGOUT" then
        ProfileRecorder.RecordEvent(ProfileRecorder.EVENT_LOGOUT)
        ProfileRecorder.RefreshCharacterProfile()
        RestoreUnusedQuestSuppression(true)
    elseif event == "QUEST_ACCEPTED" then
        local questLogIndex, questId = ...
        questId = ProfileRecorder.AcceptedQuestId(questLogIndex, questId)
        if questId then
            ProfileRecorder.RecordEvent(ProfileRecorder.EVENT_QUEST_PICKUP, questId)
        end
        ProfileRecorder.ScheduleQuestObjectiveEventRefresh(false)
    elseif event == "QUEST_TURNED_IN" then
        local questId = ...
        questId = tonumber(questId)
        if questId then
            ProfileRecorder.RecordEvent(ProfileRecorder.EVENT_QUEST_TURNIN, questId)
        end
        ProfileRecorder.RefreshCharacterProfile(questId)
        C_Timer.After(0, ProfileRecorder.RefreshCharacterProfile)
    elseif event == "CHAT_MSG_LOOT" then
        ProfileRecorder.RecordLootedQuestItem(select(1, ...))
        ProfileRecorder.ScheduleQuestObjectiveEventRefresh(true)
    elseif event == "UI_INFO_MESSAGE" then
        local errorType, message = ...
        ProfileRecorder.RecordUiObjectiveMessage(errorType, message)
    elseif event == "QUEST_WATCH_UPDATE" then
        ProfileRecorder.RecordQuestWatchUpdate(select(1, ...))
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if firstArgument == nil or firstArgument == "player" then
            ProfileRecorder.ScheduleQuestObjectiveEventRefresh(true)
        end
    elseif event == "QUEST_LOG_UPDATE"
        or event == "BAG_UPDATE_DELAYED"
        or event == "LOOT_CLOSED"
        or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE"
    then
        ProfileRecorder.ScheduleQuestObjectiveEventRefresh(true)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        ProfileRecorder.RecordCombatLogKill()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        ProfileRecorder.RecordRecentXpKill()
    elseif event == "PLAYER_DEAD" then
        ProfileRecorder.RecordEvent(ProfileRecorder.EVENT_DEATH)
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = select(1, ...)
        newLevel = tonumber(newLevel) or UnitLevel("player")
        ProfileRecorder.RecordEvent(ProfileRecorder.EVENT_LEVEL, newLevel)
        if panelFrame and panelFrame:IsShown() and RefreshPanelSearchResults then
            RefreshPanelSearchResults()
        end
    elseif event == "PLAYER_REGEN_ENABLED" and pendingApply then
        ApplyMode()
    end

    local relevantQuestUiEvent = event == "QUEST_ACCEPTED"
        or event == "QUEST_TURNED_IN"
        or event == "QUEST_LOG_UPDATE"
        or event == "QUEST_WATCH_UPDATE"
        or (event == "UNIT_QUEST_LOG_CHANGED" and (firstArgument == nil or firstArgument == "player"))
    if initialized and mode == MODE_DREAMWAY and relevantQuestUiEvent then
        DreamwayScheduleUiRefresh(true)
    end
end)

SLASH_DREAMWAY1 = "/dw"
SLASH_DREAMWAY2 = "/dreamway"
SlashCmdList.DREAMWAY = function(input)
    input = string.lower(input or "")

    if input == "dreamway" or input == "tracker" then
        SetMode(MODE_DREAMWAY)
        ApplyMode()
    elseif input == "questie" then
        SetMode(MODE_QUESTIE)
        ApplyMode()
    elseif input == "panel" or input == "journey" then
        TogglePanel()
    else
        print("|cff54e33bDreamway|r: use /dw dreamway, /dw questie, or /dw panel")
    end
end
