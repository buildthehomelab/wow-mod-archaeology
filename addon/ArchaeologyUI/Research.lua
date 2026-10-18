-- Research window: a side tab per race you can research. Each shows the race's current project
-- (name, lore and the artifact it gives), your fragments against its cost, a socket per keystone
-- the project takes, and Solve. /arch opens it, as does right-clicking the survey button.
--
-- Click a socket to put a keystone in or take it out; each one counts as KEYSTONE_VALUE
-- fragments. The server checks everything again when you press Solve.
--
-- The view (A.Research) can also live in another window: with DragonUI's professions window it
-- is a page of that (Hosted.lua), which moves R.page and R.empty there and draws the races and
-- the skill its own way.

local A = ArchaeologyUI
local WIDTH, HEIGHT = 400, 470
local MAX_SOCKETS = 4
-- The stock socketing window's art (3.3.5 has no UI-EmptySocket-Prismatic: that drew nothing).
local SOCKET_ART = "Interface\\ItemSocketingFrame\\UI-ItemSockets"
local KEYSTONE = "Interface\\Icons\\INV_Misc_Rune_01"
-- Each race's keystone item (mod_archaeology_race.keystone_item); Fossil has none.
local KEYSTONES = { [1] = 9504010, [4] = 9504011, [8] = 9504012, [2] = 9504014, [6] = 9504015,
    [5] = 9504016, [27] = 9504017 }
local RACE_ICONS = {
    [1] = "Interface\\Icons\\Achievement_Character_Dwarf_Male",
    [2] = "Interface\\Icons\\Achievement_Character_Draenei_Male",
    [3] = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    [4] = "Interface\\Icons\\Achievement_Character_Nightelf_Female",
    [5] = "Interface\\Icons\\INV_Misc_MonsterSpiderCarapace_01",
    [6] = "Interface\\Icons\\Achievement_Character_Orc_Male",
    [8] = "Interface\\Icons\\Achievement_Character_Troll_Male",
    [27] = "Interface\\Icons\\Achievement_Dungeon_UtgardePinnacle_Normal",
}

function A.RaceIcon(id)
    return RACE_ICONS[id] or A.SHOVEL
end

-- The race's keystone icon (Troll Tablet, Highborne Scroll...) from the realm's client patch.
function A.KeystoneIcon(id)
    local item = KEYSTONES[id]
    return item and GetItemIcon(item) or KEYSTONE
end

-- The skill's icon: Trade_Archaeology from the realm's client patch (it names rank 1, spell
-- 90500), the shovel without the patch.
function A.Icon()
    local _, _, icon = GetSpellInfo(90500)
    return icon or A.SHOVEL
end

local R = {}
A.Research = R

local window = CreateFrame("Frame", "ArchaeologyUIFrame", UIParent)
window:SetSize(WIDTH, HEIGHT)
window:SetPoint("CENTER")
window:SetFrameStrata("HIGH")
window:SetToplevel(true)
window:SetMovable(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:SetClampedToScreen(true)
window:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
window:Hide()
tinsert(UISpecialFrames, "ArchaeologyUIFrame")

local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)

local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -20)
title:SetText("Archaeology")

local skillText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
skillText:SetPoint("TOP", title, "BOTTOM", 0, -4)

local empty = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
empty:SetPoint("CENTER")
empty:SetWidth(WIDTH - 60)
R.empty = empty

-- Everything below the title belongs to the selected race.
local page = CreateFrame("Frame", nil, window)
page:SetPoint("TOPLEFT", 20, -56)
page:SetPoint("BOTTOMRIGHT", -20, 18)
R.page = page

local raceIcon = page:CreateTexture(nil, "ARTWORK")
raceIcon:SetSize(36, 36)
raceIcon:SetPoint("TOPLEFT", 4, 0)

local raceName = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
raceName:SetPoint("TOPLEFT", raceIcon, "TOPRIGHT", 10, -2)

local raceFragments = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
raceFragments:SetPoint("TOPLEFT", raceName, "BOTTOMLEFT", 0, -4)

-- The project: artifact icon (item tooltip on hover), name, lore.
local artifact = CreateFrame("Button", nil, page)
artifact:SetSize(40, 40)
artifact:SetPoint("TOPLEFT", raceIcon, "BOTTOMLEFT", 0, -18)
artifact.icon = artifact:CreateTexture(nil, "ARTWORK")
artifact.icon:SetAllPoints()
artifact:SetScript("OnEnter", function(self)
    if self.item then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.item)
        GameTooltip:Show()
    end
end)
artifact:SetScript("OnLeave", function() GameTooltip:Hide() end)

local projectName = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
projectName:SetPoint("TOPLEFT", artifact, "TOPRIGHT", 10, -2)
projectName:SetPoint("RIGHT", page, "RIGHT", -4, 0)
projectName:SetJustifyH("LEFT")

local projectTag = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
projectTag:SetPoint("TOPLEFT", projectName, "BOTTOMLEFT", 0, -4)

local loreBox = CreateFrame("Frame", nil, page)
loreBox:SetPoint("TOPLEFT", artifact, "BOTTOMLEFT", -4, -10)
loreBox:SetPoint("RIGHT", page, "RIGHT", 0, 0)
loreBox:SetHeight(160)
loreBox:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
loreBox:SetBackdropColor(0, 0, 0, 0.5)
loreBox:SetBackdropBorderColor(0.6, 0.6, 0.6)
R.loreBox = loreBox

local scroll = CreateFrame("ScrollFrame", "ArchaeologyUILoreScroll", loreBox, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)
R.loreScroll = scroll
local loreContent = CreateFrame("Frame", nil, scroll)
loreContent:SetSize(WIDTH - 90, 10)
scroll:SetScrollChild(loreContent)
local lore = loreContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
lore:SetPoint("TOPLEFT")
lore:SetWidth(WIDTH - 90)
lore:SetJustifyH("LEFT")
lore:SetJustifyV("TOP")

-- The lore takes whatever height the page has over the rest, and the scroll frame's width.
local REST_HEIGHT = 248
page:SetScript("OnSizeChanged", function(self, width, height)
    loreBox:SetHeight(math.max(100, (height or self:GetHeight()) - REST_HEIGHT))
end)
scroll:SetScript("OnSizeChanged", function(self, width)
    width = width or self:GetWidth()
    if width and width > 0 then
        loreContent:SetWidth(width)
        lore:SetWidth(width)
        loreContent:SetHeight(math.max(10, lore:GetStringHeight() + 4))
    end
end)

-- Progress toward the project's cost.
local bar = CreateFrame("StatusBar", nil, page)
bar:SetHeight(16)
bar:SetPoint("TOPLEFT", loreBox, "BOTTOMLEFT", 4, -14)
bar:SetPoint("RIGHT", page, "RIGHT", -4, 0)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
local barBg = bar:CreateTexture(nil, "BACKGROUND")
barBg:SetAllPoints()
barBg:SetTexture(0, 0, 0, 0.5)
local barBorder = CreateFrame("Frame", nil, bar)
barBorder:SetPoint("TOPLEFT", -3, 3)
barBorder:SetPoint("BOTTOMRIGHT", 3, -3)
barBorder:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
barBorder:SetBackdropBorderColor(0.6, 0.6, 0.6)
local barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
barText:SetPoint("CENTER")

-- Keystone sockets.
local socketLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
socketLabel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -14)

local selected, used = nil, {}   -- shown race id; keystones put in, by race
local sockets = {}
local refresh

for i = 1, MAX_SOCKETS do
    local s = CreateFrame("Button", nil, page)
    s:SetSize(32, 32)
    s:SetPoint("TOPLEFT", socketLabel, "BOTTOMLEFT", 8 + (i - 1) * 52, -12)
    -- The stock prismatic socket (GEM_TYPE_INFO.Socket in Blizzard_ItemSocketingUI), scaled to
    -- the icon: the hole shows while the socket is empty.
    s.ring = s:CreateTexture(nil, "BORDER")
    s.ring:SetTexture(SOCKET_ART)
    s.ring:SetTexCoord(0.171875, 0.3984375, 0.40234375, 0.609375)
    s.ring:SetSize(48, 44)
    s.ring:SetPoint("CENTER")
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(28, 28)
    s.icon:SetPoint("CENTER")
    s.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    s:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    s:SetScript("OnClick", function()
        local race = A.races[selected]
        if not race then
            return
        end
        local n = used[selected] or 0
        if i <= n then
            used[selected] = i - 1
        else
            used[selected] = math.min(i, race.keystones, race.sockets)
        end
        refresh()
    end)
    s:SetScript("OnEnter", function(self)
        local race = A.races[selected]
        local item = race and KEYSTONES[race.id]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(item and GetItemInfo(item) or "Keystone socket")
        GameTooltip:AddLine(string.format("A keystone counts as %d fragments.", A.KEYSTONE_VALUE), 1, 1, 1, true)
        if race then
            GameTooltip:AddLine(string.format("You have %d.", race.keystones), 1, 1, 1)
            if i <= (used[race.id] or 0) then
                GameTooltip:AddLine("Click to take it out.", 0, 1, 0)
            elseif race.keystones > (used[race.id] or 0) then
                GameTooltip:AddLine("Click to put one in.", 0, 1, 0)
            end
        end
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sockets[i] = s
end

local solve = CreateFrame("Button", "ArchaeologyUISolveButton", page, "UIPanelButtonTemplate")
R.solve = solve
solve:SetSize(120, 24)
solve:SetPoint("BOTTOMRIGHT", -4, 4)
solve:SetText("Solve")
solve:SetScript("OnClick", function()
    local race = A.races[selected]
    if race and race.project > 0 then
        A.Solve(race.id, used[selected] or 0)
        used[selected] = 0
    end
end)

local hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("BOTTOMLEFT", 4, 10)
hint:SetPoint("RIGHT", solve, "LEFT", -8, 0)
hint:SetJustifyH("LEFT")

-- Race tabs down the right side, spellbook style (in our own window).
local tabs = {}
local function tab(i)
    local t = tabs[i]
    if not t then
        t = CreateFrame("CheckButton", "ArchaeologyUIRaceTab" .. i, window, "SpellBookSkillLineTabTemplate")
        t:SetPoint("TOPLEFT", window, "TOPRIGHT", -4, -48 - (i - 1) * 46)
        t:SetScript("OnClick", function(self)
            R.Select(self.race)
        end)
        tabs[i] = t
    end
    return t
end

local function drawRace(race)
    raceIcon:SetTexture(A.RaceIcon(race.id))
    raceName:SetText(race.name)
    raceFragments:SetText(string.format("%d fragments (holds up to %d)   %d %s", race.fragments, race.cap,
        race.keystones, race.keystones == 1 and "keystone" or "keystones"))

    local p = race.project > 0 and A.projects[race.project]
    if race.project == 0 then
        artifact.item = nil
        artifact.icon:SetTexture(A.RaceIcon(race.id))
        projectName:SetText("No project yet")
        projectTag:SetText("")
        lore:SetText("Dig up some " .. race.name .. " fragments to start a project.")
    else
        if not (p and p.complete) then
            A.RequestProject(race.project)
        end
        artifact.item = p and p.item
        artifact.icon:SetTexture(p and GetItemIcon(p.item) or A.RaceIcon(race.id))
        projectName:SetText((race.rare and "|cffa335ee" or "|cffffffff") .. (p and p.name or "...") .. "|r")
        projectTag:SetText(race.rare and "|cffa335eeRare artifact|r" or "Common artifact")
        lore:SetText(p and p.text or "")
    end
    loreContent:SetHeight(math.max(10, lore:GetStringHeight() + 4))
    scroll:SetVerticalScroll(0)

    local n = math.min(used[race.id] or 0, race.sockets, race.keystones)
    used[race.id] = n
    local cost = race.cost
    local have = race.fragments + n * A.KEYSTONE_VALUE
    bar:SetMinMaxValues(0, math.max(cost, 1))
    bar:SetValue(math.min(have, cost))
    if cost > 0 and have >= cost then
        bar:SetStatusBarColor(0.2, 0.8, 0.2)
    else
        bar:SetStatusBarColor(0.8, 0.55, 0.15)
    end
    barText:SetText(cost > 0 and string.format("%d / %d", have, cost) or "")

    if race.sockets > 0 then
        socketLabel:SetText("Keystones")
    else
        socketLabel:SetText(race.project > 0 and KEYSTONES[race.id] and "This artifact takes no keystones." or "")
    end
    for i, s in ipairs(sockets) do
        if i <= race.sockets then
            -- In: the keystone. Empty: the socket's hole, with the keystone faded in while you
            -- have one to put there.
            s.icon:SetTexture(A.KeystoneIcon(race.id))
            if i <= n then
                s.icon:SetDesaturated(nil)
                s.icon:SetAlpha(1)
                s.icon:Show()
            elseif i <= race.keystones then
                s.icon:SetDesaturated(1)
                s.icon:SetAlpha(0.45)
                s.icon:Show()
            else
                s.icon:Hide()
            end
            s:Show()
        else
            s:Hide()
        end
    end

    local need = A.FragmentsNeeded(race, n)
    if race.project == 0 then
        hint:SetText("")
        solve:Disable()
    elseif need > 0 then
        hint:SetText(string.format("%d more fragments needed.", need))
        solve:Disable()
    else
        hint:SetText("Ready to solve.")
        solve:Enable()
    end
end

-- How our own window shows the skill and the races; Hosted.lua swaps these for its own.
R.shown = function() return window:IsShown() end
R.drawSkill = function(skill, maxSkill)
    skillText:SetText(skill and string.format("Skill %d / %d", skill, maxSkill) or "")
end
R.drawRaces = function(races, current)
    for i, t in ipairs(tabs) do
        if i > #races then
            t:Hide()
        end
    end
    for i, race in ipairs(races) do
        local t = tab(i)
        t.race = race.id
        t.tooltip = race.name
        t:SetNormalTexture(A.RaceIcon(race.id))
        t:SetChecked(race.id == current)
        t:Show()
    end
end
-- Opens the view (or, open already, closes it); open = true only opens it.
R.toggle = function(open)
    if window:IsShown() and not open then
        window:Hide()
    else
        window:Show()
    end
end

refresh = function()
    if not R.shown() then
        return
    end
    local races = A.UnlockedRaces()
    if A.skill == 0 or #races == 0 then
        R.drawSkill(nil)
        R.drawRaces({}, nil)
        empty:SetText(A.connected and "You don't know Archaeology yet. Find an archaeology trainer to learn it."
            or "Waiting for the server. Archaeology needs mod-archaeology on the realm.")
        empty:Show()
        page:Hide()
        return
    end
    empty:Hide()
    page:Show()
    R.drawSkill(A.skill, A.maxSkill)

    if not (selected and A.races[selected] and A.races[selected].unlocked) then
        selected = races[1].id
    end
    R.drawRaces(races, selected)
    drawRace(A.races[selected])
end
R.Refresh = refresh

function R.Select(id)
    selected = id
    refresh()
end

-- The view opens (and asks the server once more if it hasn't answered yet).
function R.Opened()
    if not A.connected then
        A.Request("HELLO", "HELLO")
    end
    refresh()
end

function A.ToggleWindow()
    R.toggle()
end

-- Opens the research window (or its page), leaving it open if it is.
function A.OpenWindow()
    R.toggle(true)
    refresh()
end

function A.ShowRace(id)
    selected = id
    R.toggle(true)
    refresh()
end

window:SetScript("OnShow", function()
    PlaySound("igCharacterInfoOpen")
    R.Opened()
end)
window:SetScript("OnHide", function()
    PlaySound("igCharacterInfoClose")
end)

A.On("STATE", refresh)
A.On("RACES", function()
    -- Fetch every project's name and lore ahead of time; the queue spaces the requests out.
    for _, race in ipairs(A.UnlockedRaces()) do
        A.RequestProject(race.project)
    end
    refresh()
end)
A.On("PROJECT", function(id)
    local race = selected and A.races[selected]
    if race and race.project == id then
        refresh()
    end
end)
A.On("FRAGMENTS", refresh)
