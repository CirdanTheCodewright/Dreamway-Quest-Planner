local ADDON_NAME = ...

local MODE_QUESTIE = "Questie"
local MODE_TEST = "Test"

local mode = MODE_QUESTIE
local initialized = false
local pendingApply = false
local batchIndex = 1

local baseFrame
local headerFrame
local questFrame
local mockFrame
local toggleFrame
local questieButton
local testButton

local batches = {
    {
        name = "Darkshore: Auberdine North Loop",
        pickup = {
            "Buzzbox 827",
            "Cave Mushrooms",
        },
        progress = {
            "Washed Ashore 0/1",
            "Buzzbox 827: Tide Crawlers 3/6",
            "The Red Crystal 0/1",
        },
        ready = {
            "Bashal'Aran",
            "The Absent Minded Prospector",
        },
    },
    {
        name = "Darkshore: Bashal'Aran Sweep",
        pickup = {
            "Tools of the Highborne",
            "For Love Eternal",
        },
        progress = {
            "The Tower of Althalaxx 2/6",
            "Deep Ocean, Vast Sea 0/2",
        },
        ready = {
            "Cave Mushrooms",
        },
    },
    {
        name = "Darkshore: South Beach Return",
        pickup = {
            "Fruit of the Sea",
        },
        progress = {
            "Beached Sea Creature 0/1",
            "The Family and the Fishing Pole 4/6",
        },
        ready = {
            "Buzzbox 411",
            "Washed Ashore",
            "Fruit of the Sea",
        },
    },
}

local function CreateBackdropFrame(name, parent)
    return CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate")
end

local function SetPanelBackdrop(frame, r, g, b, a)
    if not frame.SetBackdrop then
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
    frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.9)
end

local function GetQuestieTracker()
    if not QuestieLoader then
        return nil
    end

    local ok, tracker = pcall(function()
        return QuestieLoader:ImportModule("QuestieTracker")
    end)

    if ok then
        return tracker
    end

    return nil
end

local function AddText(parent, text, point, relTo, relPoint, x, y, template)
    local fontString = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
    fontString:SetPoint(point, relTo or parent, relPoint or point, x or 0, y or 0)
    fontString:SetJustifyH("LEFT")
    fontString:SetText(text)
    return fontString
end

local function AddSection(parent, title, items, y)
    parent.dynamicIndex = parent.dynamicIndex + 1
    local titleText = parent.dynamicText[parent.dynamicIndex]
    if not titleText then
        titleText = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        parent.dynamicText[parent.dynamicIndex] = titleText
    end
    titleText:ClearAllPoints()
    titleText:SetFontObject(GameFontNormalSmall)
    titleText:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
    titleText:SetJustifyH("LEFT")
    titleText:SetText(title)
    titleText:SetTextColor(1, 0.82, 0.25)
    titleText:Show()

    local currentY = y - 16
    for _, item in ipairs(items) do
        parent.dynamicIndex = parent.dynamicIndex + 1
        local line = parent.dynamicText[parent.dynamicIndex]
        if not line then
            line = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            parent.dynamicText[parent.dynamicIndex] = line
        end
        line:ClearAllPoints()
        line:SetFontObject(GameFontHighlightSmall)
        line:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, currentY)
        line:SetJustifyH("LEFT")
        line:SetText("- " .. item)
        line:SetTextColor(0.9, 0.9, 0.9)
        line:Show()
        currentY = currentY - 15
    end

    return currentY - 8
end

local function RefreshMock()
    if not mockFrame then
        return
    end

    local batch = batches[batchIndex]
    mockFrame.title:SetText(batch.name)

    for _, child in ipairs(mockFrame.dynamicText) do
        child:Hide()
        child:SetText("")
    end
    mockFrame.dynamicIndex = 0

    local y = -42
    y = AddSection(mockFrame, "Pick Up", batch.pickup, y)
    y = AddSection(mockFrame, "In Progress", batch.progress, y)
    AddSection(mockFrame, "Ready / Turn In", batch.ready, y)
end

local function SetMode(newMode)
    mode = newMode
    pendingApply = true
end

local function UpdateToggleButtons()
    if not questieButton or not testButton then
        return
    end

    questieButton:SetEnabled(mode ~= MODE_QUESTIE)
    testButton:SetEnabled(mode ~= MODE_TEST)
end

local function ApplyMode()
    pendingApply = false

    if not initialized or InCombatLockdown() then
        pendingApply = true
        return
    end

    UpdateToggleButtons()

    if mode == MODE_TEST then
        if baseFrame then
            baseFrame:Show()
            baseFrame:SetWidth(math.max(baseFrame:GetWidth() or 0, 260))
            baseFrame:SetHeight(math.max(baseFrame:GetHeight() or 0, 225))
        end
        if headerFrame then
            headerFrame:Hide()
        end
        if questFrame then
            questFrame:Hide()
        end
        if mockFrame then
            RefreshMock()
            mockFrame:Show()
        end
    else
        if mockFrame then
            mockFrame:Hide()
        end
        if headerFrame then
            headerFrame:Show()
        end

        local tracker = GetQuestieTracker()
        if tracker and tracker.Update then
            tracker:Update()
        elseif questFrame then
            questFrame:Show()
        end
    end
end

local function CreateToggle()
    toggleFrame = CreateFrame("Frame", "QuestiePlus_Toggle", baseFrame)
    toggleFrame:SetSize(122, 20)
    toggleFrame:SetPoint("BOTTOMLEFT", baseFrame, "TOPLEFT", 0, 4)
    toggleFrame:SetFrameLevel((baseFrame:GetFrameLevel() or 0) + 50)

    questieButton = CreateFrame("Button", nil, toggleFrame, "UIPanelButtonTemplate")
    questieButton:SetSize(66, 20)
    questieButton:SetPoint("LEFT", toggleFrame, "LEFT", 0, 0)
    questieButton:SetText("Questie")
    questieButton:SetScript("OnClick", function()
        SetMode(MODE_QUESTIE)
        ApplyMode()
    end)

    testButton = CreateFrame("Button", nil, toggleFrame, "UIPanelButtonTemplate")
    testButton:SetSize(52, 20)
    testButton:SetPoint("LEFT", questieButton, "RIGHT", 4, 0)
    testButton:SetText("Test")
    testButton:SetScript("OnClick", function()
        SetMode(MODE_TEST)
        ApplyMode()
    end)
end

local function CreateMock()
    mockFrame = CreateBackdropFrame("QuestiePlus_MockTracker", baseFrame)
    mockFrame:SetSize(260, 210)
    mockFrame:SetPoint("TOPLEFT", baseFrame, "TOPLEFT", 0, -4)
    mockFrame:SetFrameLevel((baseFrame:GetFrameLevel() or 0) + 40)
    mockFrame:EnableMouse(false)
    SetPanelBackdrop(mockFrame, 0.04, 0.04, 0.05, 0.86)

    mockFrame.dynamicText = {}

    local leftArrow = CreateFrame("Button", nil, mockFrame, "UIPanelButtonTemplate")
    leftArrow:SetSize(24, 20)
    leftArrow:SetPoint("TOPLEFT", mockFrame, "TOPLEFT", 8, -10)
    leftArrow:SetText("<")
    leftArrow:SetScript("OnClick", function()
        batchIndex = batchIndex - 1
        if batchIndex < 1 then
            batchIndex = #batches
        end
        RefreshMock()
    end)

    local rightArrow = CreateFrame("Button", nil, mockFrame, "UIPanelButtonTemplate")
    rightArrow:SetSize(24, 20)
    rightArrow:SetPoint("TOPRIGHT", mockFrame, "TOPRIGHT", -8, -10)
    rightArrow:SetText(">")
    rightArrow:SetScript("OnClick", function()
        batchIndex = batchIndex + 1
        if batchIndex > #batches then
            batchIndex = 1
        end
        RefreshMock()
    end)

    mockFrame.title = AddText(mockFrame, "", "TOPLEFT", leftArrow, "TOPRIGHT", 8, -2, "GameFontNormal")
    mockFrame.title:SetPoint("RIGHT", rightArrow, "LEFT", -8, 0)
    mockFrame.title:SetJustifyH("CENTER")
    mockFrame.title:SetTextColor(0.35, 0.85, 1)

    mockFrame:Hide()
    RefreshMock()
end

local function HookQuestieUpdates()
    local tracker = GetQuestieTracker()
    if tracker and tracker.Update and not tracker.QuestiePlusHooked then
        hooksecurefunc(tracker, "Update", function()
            if mode == MODE_TEST and initialized then
                C_Timer.After(0, ApplyMode)
            end
        end)
        tracker.QuestiePlusHooked = true
    end
end

local function TryInitialize()
    if initialized then
        return
    end

    baseFrame = _G.Questie_BaseFrame
    headerFrame = _G.Questie_HeaderFrame
    questFrame = _G.TrackedQuests

    if not baseFrame or not headerFrame or not questFrame then
        C_Timer.After(0.5, TryInitialize)
        return
    end

    CreateToggle()
    CreateMock()
    HookQuestieUpdates()

    baseFrame:HookScript("OnShow", function()
        if mode == MODE_TEST then
            C_Timer.After(0, ApplyMode)
        end
    end)

    initialized = true
    ApplyMode()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        TryInitialize()
    elseif event == "PLAYER_REGEN_ENABLED" and pendingApply then
        ApplyMode()
    end
end)

SLASH_QUESTIEPLUS1 = "/qp"
SLASH_QUESTIEPLUS2 = "/questieplus"
SlashCmdList.QUESTIEPLUS = function(input)
    input = string.lower(input or "")

    if input == "test" then
        SetMode(MODE_TEST)
        ApplyMode()
    elseif input == "questie" then
        SetMode(MODE_QUESTIE)
        ApplyMode()
    else
        print("|cff54e33bQuestiePlus|r: use /qp test or /qp questie")
    end
end
