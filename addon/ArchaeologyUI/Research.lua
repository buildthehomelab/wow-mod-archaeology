-- Research window: a side tab per race you can research. Each shows the race's current project
-- (name, lore and the artifact it gives), your fragments against its cost, a socket per keystone
-- the project takes, and Solve. /arch opens it, as does right-clicking the survey button.
--
-- Click a socket to put a keystone in or take it out; each one counts as KEYSTONE_VALUE
-- fragments. The server checks everything again when you press Solve.
--
-- The view (A.Research) can also live in another window: with DragonUI's professions window it
-- is a page of that (Hosted.lua), and without it a page of RetailProfessions' window
-- (HostedRetail.lua). Those move R.page and R.empty there and draw the races (in R.NewRaceRow's
-- lines) and the skill their own way.

local A = ArchaeologyUI
local WIDTH, HEIGHT = 400, 500
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

-- The Unearthed Relic along the bottom, inside the dialog border (it can run to two lines).
local relicText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
relicText:SetPoint("BOTTOMLEFT", 22, 20)
relicText:SetPoint("BOTTOMRIGHT", -22, 20)
relicText:SetJustifyH("LEFT")
relicText:SetJustifyV("BOTTOM")
-- Hover it for the relic's tooltip; shift-click links it.
local relicHit = CreateFrame("Frame", nil, window)
relicHit:SetPoint("TOPLEFT", relicText, "TOPLEFT")
relicHit:SetPoint("BOTTOMRIGHT", relicText, "BOTTOMRIGHT")
relicHit:EnableMouse(true)
relicHit:SetScript("OnEnter", function(self) A.ShowRelicTooltip(self) end)
relicHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
relicHit:SetScript("OnMouseUp", function() A.ClickRelic() end)

local empty = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
empty:SetPoint("CENTER")
empty:SetWidth(WIDTH - 60)
R.empty = empty

-- Everything below the title belongs to the selected race.
-- The page's place in our window, above the relic line (Hosted.lua gives it back here too).
function R.PlacePage(page)
    page:SetPoint("TOPLEFT", 20, -56)
    page:SetPoint("BOTTOMRIGHT", -20, 56)
end
local page = CreateFrame("Frame", nil, window)
R.PlacePage(page)
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
-- An options-box look: the stock tooltip border in the options box grey (0.4) over a faint grey
-- fill. A host with a parchment card takes it off (R.LoreBox(false)).
function R.LoreBox(on)
    if not on then
        loreBox:SetBackdrop(nil)
        return
    end
    loreBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    loreBox:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    loreBox:SetBackdropBorderColor(0.4, 0.4, 0.4)
end
R.LoreBox(true)
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

-- Progress toward the project's cost, on the stock skill bar (as the trade skill window's rank bar).
local bar = CreateFrame("StatusBar", nil, page)
bar:SetHeight(14)
bar:SetPoint("TOPLEFT", loreBox, "BOTTOMLEFT", 4, -14)
bar:SetPoint("RIGHT", page, "RIGHT", -4, 0)
bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
local barBg = bar:CreateTexture(nil, "BACKGROUND")
barBg:SetAllPoints()
barBg:SetTexture(1, 1, 1, 0.2)
local barBorder = CreateFrame("Frame", nil, bar)
barBorder:SetAllPoints()
local barEdge = barBorder:CreateTexture(nil, "ARTWORK")
barEdge:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder")
barEdge:SetPoint("TOPLEFT", -5, 7)
barEdge:SetPoint("BOTTOMRIGHT", 4, -6)
local barText = barBorder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
barText:SetPoint("CENTER", bar, "CENTER", 0, 1)
R.progress = { bar = bar, bg = barBg, border = barBorder, edge = barEdge, text = barText }

-- Keystone sockets.
local socketLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
socketLabel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -14)

local selected, used = nil, {}   -- shown race id; keystones put in, by race
local sockets = {}
local refresh

-- A separate bank slot keeps artifact socket selection independent of withdrawals.
StaticPopupDialogs["ARCHAEOLOGY_WITHDRAW_KEYSTONE"] = {
    text = "Withdraw %s from the reagent bank. How many?",
    button1 = "Withdraw", button2 = CANCEL,
    hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self)
        self.editBox:SetNumeric(true)
        self.editBox:SetMaxLetters(10)
        self.editBox:SetText("1")
        self.editBox:SetFocus()
        self.editBox:HighlightText()
    end,
    OnAccept = function(self, item)
        local amount = tonumber(self.editBox:GetText())
        if not item or not amount or amount < 1
            or amount ~= math.floor(amount) or amount > 4294967295 then
            return
        end
        -- "withdraw needed" answers with the transaction only; "withdraw item" also sends the
        -- bank's whole view, which pops the Reagent Bank window open.
        SendChatMessage(".rbank withdraw needed " .. item .. " " .. string.format("%.0f", amount), "SAY")
    end,
}
local bankSlot = CreateFrame("Button", nil, page)
bankSlot:SetSize(32, 32)
bankSlot:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -4, -38)
bankSlot.icon = bankSlot:CreateTexture(nil, "ARTWORK")
bankSlot.icon:SetAllPoints()
bankSlot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
local bankLabel = bankSlot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
bankLabel:SetPoint("BOTTOM", bankSlot, "TOP", 0, 4)
bankLabel:SetText("Bank")
bankSlot:SetScript("OnClick", function()
    local item = KEYSTONES[selected]
    if item then
        -- Capture the item: changing race while the prompt is open must not change the request.
        StaticPopup_Show("ARCHAEOLOGY_WITHDRAW_KEYSTONE", GetItemInfo(item) or "keystones", nil, item)
    end
end)
bankSlot:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Reagent bank keystones")
    GameTooltip:AddLine("Click to withdraw one or more into your bags.", 1, 1, 1, true)
    GameTooltip:Show()
end)
bankSlot:SetScript("OnLeave", function() GameTooltip:Hide() end)
-- Withdrawals and deposits change the bag count used by artifact sockets and Solve.
local bankEvents = CreateFrame("Frame")
bankEvents:RegisterEvent("BAG_UPDATE")
bankEvents:SetScript("OnEvent", function()
    if page:IsVisible() then A.Request("RACES", "RACES") end
end)

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
hint:SetPoint("BOTTOMLEFT", 4, 34)
hint:SetPoint("BOTTOMRIGHT", -4, 34)
hint:SetJustifyH("LEFT")

-- A race as a line of a host's list column (Hosted.lua, HostedRetail.lua): its icon, name and
-- fragments against the project's cost on a bar, lit while it's the race on show. A click shows it.
R.ROW_HEIGHT = 44

function R.NewRaceRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(R.ROW_HEIGHT)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -7)
    row.count:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetHeight(8)
    row.bar:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
    row.bar:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    local bg = row.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row.bar)
    bg:SetTexture(0, 0, 0, 0.65)
    row.lit = row:CreateTexture(nil, "BACKGROUND")
    row.lit:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.lit:SetBlendMode("ADD")
    row.lit:SetVertexColor(1, 0.82, 0, 0.3)
    row.lit:SetAllPoints(row)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(1, 1, 1, 0.35)
    hl:SetAllPoints(row)
    row:SetScript("OnClick", function(self)
        if self.race then R.Select(self.race) end
    end)
    row:SetScript("OnEnter", function(self)
        local race = self.race and A.races[self.race]
        if not race then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(race.name)
        GameTooltip:AddLine(string.format("%d fragments (holds up to %d)", race.fragments, race.cap), 1, 1, 1)
        GameTooltip:AddLine(string.format("%d %s", race.keystones, race.keystones == 1 and "keystone" or "keystones"), 1, 1, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- `race` on the line (nil: the line goes); `current` is the race on show.
function R.DrawRaceRow(row, race, current)
    if not race then
        row:Hide()
        row.race = nil
        return
    end
    row.race = race.id
    row.icon:SetTexture(A.RaceIcon(race.id))
    row.name:SetText(race.name)
    local cost = race.cost or 0
    if cost > 0 then
        row.count:SetText(string.format("%d / %d", math.min(race.fragments, cost), cost))
        row.bar:SetMinMaxValues(0, cost)
        row.bar:SetValue(math.min(race.fragments, cost))
    else
        row.count:SetText(race.fragments)
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(0)
    end
    -- Green once the project can be solved without keystones.
    if cost > 0 and race.fragments >= cost then
        row.bar:SetStatusBarColor(0.2, 0.8, 0.2)
    else
        row.bar:SetStatusBarColor(0.95, 0.6, 0.1)
    end
    if race.id == current then row.lit:Show() else row.lit:Hide() end
    row:Show()
end

-- The view and the empty-state text back in our own window, from a host's page.
function R.TakeBack()
    page:SetParent(window)
    page:ClearAllPoints()
    R.PlacePage(page)
    empty:SetParent(window)
    empty:ClearAllPoints()
    empty:SetPoint("CENTER")
    empty:SetWidth(WIDTH - 60)
    R.LoreBox(true)
end

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

    if KEYSTONES[race.id] then
        bankSlot.icon:SetTexture(A.KeystoneIcon(race.id))
        bankSlot:Show()
    else
        bankSlot:Hide()
    end

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

-- The relic line: "Unearthed Relic rank 7/29, item level 58 - Relic Power 120/550", or the note
-- the server sent (how to get it, what holds it back).
function A.RelicLine()
    local r = A.relic
    if not r then
        return ""
    end
    if r.rank == 0 then
        return string.format("|cffe6cc80Unearthed Relic|r  Relic Power %d. %s", r.power, r.note)
    end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.quality]
    local name = (color and color.hex or "|cffe6cc80") .. "Unearthed Relic|r"
    if r.form ~= "" then
        name = name .. " (" .. r.form .. ")"
    end
    local line = string.format("%s rank %d/%d, item level %d", name, r.rank, r.ranks, r.itemLevel)
    if r.cost > 0 then
        line = line .. string.format("  -  Relic Power %d/%d", r.power, r.cost)
    end
    return r.note ~= "" and (line .. "\n" .. r.note) or line
end

-- The relic's link: the one on the character or in the bags (with its enchants and gems), else
-- the plain item the server named (in the bank, say). An older server names none; then any relic
-- step found on the character will do.
local RELIC_FIRST, RELIC_LAST = 9505000, 9505899
function A.RelicLink()
    local r = A.relic
    if not (r and r.rank > 0) then
        return nil
    end
    local function wanted(link)
        local id = link and tonumber(link:match("item:(%d+)"))
        if not id then
            return false
        end
        if r.item and r.item > 0 then
            return id == r.item
        end
        return id >= RELIC_FIRST and id <= RELIC_LAST
    end
    for slot = 16, 18 do
        local link = GetInventoryItemLink("player", slot)
        if wanted(link) then
            return link
        end
    end
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if wanted(link) then
                return link
            end
        end
    end
    if r.item and r.item > 0 then
        return select(2, GetItemInfo(r.item)) or ("item:" .. r.item)
    end
end

function A.RelicIcon()
    local r = A.relic
    local link = A.RelicLink()
    local id = (r and r.item and r.item > 0 and r.item) or (link and tonumber(link:match("item:(%d+)")))
    return id and GetItemIcon(id) or nil
end

local function qualityText(quality, text)
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    return (color and color.hex or "") .. text .. (color and "|r" or "")
end

-- The relic's tooltip: the weapon itself (its stats), then rank, power, the next rank, what
-- holds it back and its traits.
function A.ShowRelicTooltip(owner)
    local r = A.relic
    if not r then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local link = A.RelicLink()
    -- Only a cached item: an uncached one would draw an empty tooltip under our lines.
    if link and GetItemInfo(link) then
        GameTooltip:SetHyperlink(link)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Unearthed Relic", 0.9, 0.8, 0.5)
    else
        GameTooltip:SetText("Unearthed Relic", 0.9, 0.8, 0.5)
    end
    if r.rank > 0 then
        if r.form ~= "" then
            GameTooltip:AddDoubleLine("Form", r.form, 1, 0.82, 0, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("Rank", string.format("%d of %d", r.rank, r.ranks), 1, 0.82, 0, 1, 1, 1)
        if r.cost > 0 then
            GameTooltip:AddDoubleLine("Relic Power", string.format("%d / %d  (%d to go)", r.power, r.cost,
                math.max(0, r.cost - r.power)), 1, 0.82, 0, 1, 1, 1)
        else
            GameTooltip:AddDoubleLine("Relic Power", tostring(r.power), 1, 0.82, 0, 1, 1, 1)
        end
        if r.nextItemLevel and r.nextItemLevel > 0 then
            GameTooltip:AddDoubleLine("Rank " .. (r.rank + 1),
                qualityText(r.nextQuality, "item level " .. r.nextItemLevel), 1, 0.82, 0, 1, 1, 1)
        end
        if r.held == 1 then
            GameTooltip:AddLine(string.format("Your level holds it back: at level %d it grows to item level %d.",
                r.heldLevel, r.heldItemLevel), 1, 0.5, 0.25, true)
        elseif r.held == 2 then
            GameTooltip:AddLine(string.format("Your progress through the ages holds it back; next it grows to item level %d.",
                r.heldItemLevel), 1, 0.5, 0.25, true)
        end
    else
        GameTooltip:AddDoubleLine("Relic Power", tostring(r.power), 1, 0.82, 0, 1, 1, 1)
    end
    if r.note ~= "" then
        GameTooltip:AddLine(r.note, 1, 1, 1, true)
    end

    -- Traits, once the server has sent them (asked for when the window opens).
    local traits, awake = {}, 0
    for _, id in ipairs(A.raceOrder) do
        local t = A.traits and A.traits[id]
        if t then
            tinsert(traits, t)
            if t.awake then awake = awake + 1 end
        end
    end
    if r.rank > 0 and #traits > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("Traits: %d of %d awake", awake, #traits), 1, 0.82, 0)
        for _, t in ipairs(traits) do
            if t.awake then
                GameTooltip:AddDoubleLine("  " .. t.name, t.strength .. "%", 0.3, 1, 0.3, 0.3, 1, 0.3)
            else
                GameTooltip:AddDoubleLine("  " .. t.name, string.format("%d/%d commons", math.min(t.commons, t.need), t.need),
                    0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
            end
        end
    end
    if link then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift-click to link it. Ctrl-click to try it on.", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

-- Shift-click links the relic in chat, Ctrl-click shows it in the dressing room.
function A.ClickRelic()
    local link = A.RelicLink()
    if not link then
        return
    end
    if IsModifiedClick("CHATLINK") then
        ChatEdit_InsertLink(select(2, GetItemInfo(link)) or link)
    elseif IsModifiedClick("DRESSUP") then
        DressUpItemLink(link)
    end
end

-- The relic under a list-column header (Hosted.lua, HostedRetail.lua): its icon, its form and item
-- level, Relic Power on the right and a thin bar of it underneath; hover for the full story.
function R.NewRelicRow(list, header)
    local row = CreateFrame("Frame", nil, list)
    row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -4)
    row:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    row:SetHeight(24)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("TOPLEFT", 0, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.power = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.power:SetPoint("TOPRIGHT", 0, -2)
    row.power:SetJustifyH("RIGHT")
    row.line = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.line:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 5, -2)
    row.line:SetPoint("RIGHT", row.power, "LEFT", -6, 0)
    row.line:SetJustifyH("LEFT")
    row.line:SetWordWrap(false)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", row.icon, "BOTTOMLEFT", 0, -3)
    row.bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.bar:SetHeight(4)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetStatusBarColor(0.9, 0.7, 0.2)
    row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.bg:SetAllPoints()
    row.bar.bg:SetTexture(0, 0, 0, 0.5)

    -- The header and the row both show the tooltip and take the clicks.
    for _, f in ipairs({ header, row }) do
        f:EnableMouse(true)
        f:SetScript("OnEnter", function(self) A.ShowRelicTooltip(self) end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:SetScript("OnMouseUp", function() A.ClickRelic() end)
    end
    header.row = row
    return row
end

function R.DrawRelicRow(header)
    local r, row = A.relic, header.row
    local color = r.rank > 0 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.quality]
    if color then
        header.label:SetTextColor(color.r, color.g, color.b)
    else
        header.label:SetTextColor(0.9, 0.8, 0.5)
    end
    header.note:SetText(r.rank > 0 and string.format("Rank %d/%d", r.rank, r.ranks) or "")
    local icon = A.RelicIcon()
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    if r.rank > 0 then
        local form = r.form ~= "" and r.form or "No form yet"
        row.line:SetText(string.format("%s, item level %d", form, r.itemLevel))
        if r.held and r.held > 0 then
            row.line:SetTextColor(1, 0.5, 0.25)   -- held back: the tooltip says why
        else
            row.line:SetTextColor(1, 1, 1)
        end
    else
        row.line:SetText(r.note)
        row.line:SetTextColor(1, 1, 1)
    end
    if r.cost > 0 then
        row.power:SetText(string.format("%d/%d", r.power, r.cost))
        row.bar:SetMinMaxValues(0, r.cost)
        row.bar:SetValue(math.min(r.power, r.cost))
    else
        row.power:SetText(r.rank > 0 and "Max" or tostring(r.power))
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(r.rank > 0 and 1 or 0)
    end
end

-- How our own window shows the skill and the races; Hosted.lua swaps these for its own.
R.shown = function() return window:IsShown() end
R.drawRelic = function(text)
    relicText:SetText(text or "")
end
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
    R.drawRelic(A.skill > 0 and A.RelicLine() or nil)
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
    -- The relic's tooltip lists its traits.
    if A.relic and A.relic.rank > 0 then
        A.Request("TRAITS", "TRAITS")
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

-- Archaeology in the spellbook (the client patch's rank spells, 90500-90505, all named like
-- 90500) opens the research window, as Cooking's spell opens its window. The patch names the
-- spells in English only: another locale's client sees "" for all of them, so it matches nothing.
local spellbookCast = CreateFrame("Frame")
spellbookCast:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
spellbookCast:SetScript("OnEvent", function(_, _, unit, spell)
    local name = GetSpellInfo(90500)
    if unit == "player" and name and name ~= "" and spell == name then
        A.OpenWindow()
    end
end)

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
A.On("RELIC", refresh)
