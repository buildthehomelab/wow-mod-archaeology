-- Collection & Bonuses: every artifact of every race, which ones you have solved (the server keeps
-- the history, so selling or deleting a reward doesn't lose it), each race's progress and its
-- relic trait. /arch collection opens it, as does the button on the research page.
--
-- Two pieces: C.list, the races down a column with their crests, and C.card, the selected race's
-- page (its big crest, progress, trait and artifacts; a click on an artifact shows its lore and,
-- for a rare, its sketch). They live in our own window, a stock dialog box with Cataclysm's book
-- page behind the card. With DragonUI's professions window they are a page of that window in its
-- art (Hosted.lua). The crests, sketches and book come from the realm's client patch
-- (tools/build_patch.py); without them the crests are the race icons and the page has no art.

local A = ArchaeologyUI
local C = {}
A.Collection = C

local ART = "Interface\\Archeology\\"
-- Cataclysm's research art by race (Arch-Race-<name>, Arch-Race-<name>Big) and by rare project.
local CRESTS = { [1] = "Dwarf", [2] = "Draenei", [3] = "Fossil", [4] = "NightElf", [5] = "Nerubian",
    [6] = "Orc", [7] = "Tolvir", [8] = "Troll", [27] = "Vrykul" }
local SKETCHES = {
    [106] = "TinyDinosaurSkeleton", [173] = "HighborneSoulMirror", [175] = "DruidAndPriestStatue",
    [187] = "ClockworkGnome", [189] = "ChaliceMountainKings", [195] = "ZinRokhDestroyer",
    [205] = "KaldoreiWindChimes", [207] = "QueenAzsharaGown", [213] = "DinosaurSkeleton",
    [237] = "AncientShamanHeaddress", [256] = "DraeneiRelic", [258] = "DraeneiRelic",
    [295] = "OldGodTrinket", [297] = "CthunsPuzzleBox", [313] = "TheInnkeepersDaughter",
    [315] = "StaffOfSorcererThanThaurissan", [317] = "TyrandesFavoriteDoll",
    [319] = "BonesOfTransformation", [329] = "WispAmulet", [628] = "TurtleShield", [633] = "TrollDrum",
    [635] = "Amberfly", [637] = "VrykulDrinkingHorn", [639] = "BabyPterrodax", [641] = "TrollGolem",
}
-- Rares Cataclysm drew no sketch for (Nifflevar Bearded Axe) get its placeholder sketch.
local SKETCH_NONE = "Arch-TempRareSketch"
-- The drawn part of each texture: small crest 128x128, big crest 256x512, sketch 512x256.
local CREST_COORDS = { 0, 0.5625, 0, 0.65 }
local BIG_COORDS = { 0, 0.9375, 0, 0.6 }
local SKETCH_COORDS = { 0, 0.875, 0, 1 }
local SKETCH_ASPECT = 448 / 256
local PER_PAGE = 7
local ROW_HEIGHT = 30
C.RACE_ROW_HEIGHT = 46

-- Frame:SetShown is newer than 3.3.5.
local function show(region, on)
    if on then region:Show() else region:Hide() end
end

-- Sets one of the Archeology textures, or `fallback` (an icon) when the client hasn't got it.
local function art(texture, file, coords, fallback)
    if file and texture:SetTexture(ART .. file) then
        texture:SetTexCoord(unpack(coords))
        return true
    end
    texture:SetTexture(fallback)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    return false
end

function C.Crest(texture, race)
    return art(texture, CRESTS[race] and ("Arch-Race-" .. CRESTS[race]), CREST_COORDS, A.RaceIcon(race))
end

-- Text on the page: light on DragonUI's card and the dialog box, dark ink on the book page.
local LIGHT = { head = { 1, 0.82, 0 }, body = { 1, 1, 1 }, muted = { 0.65, 0.65, 0.65 } }
local DARK = { head = { 0.29, 0.13, 0 }, body = { 0.18, 0.1, 0.04 }, muted = { 0.42, 0.32, 0.22 } }
local ink, inked = LIGHT, {}
local function text(parent, font, role)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs.role = role
    fs:SetTextColor(unpack(ink[role]))
    tinsert(inked, fs)
    return fs
end
function C.SetInk(dark)
    ink = dark and DARK or LIGHT
    for _, fs in ipairs(inked) do fs:SetTextColor(unpack(ink[fs.role])) end
end

C.buttons = {}
local function button(parent, label, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(label)
    tinsert(C.buttons, b)
    return b
end

local probe = UIParent:CreateTexture(nil, "BACKGROUND")
probe:Hide()
local hasFill = probe:SetTexture(ART .. "Arch-Progress-Fill") and true or false

-- Progress on Cataclysm's archaeology bar, or the stock skill bar without the patch.
local function progressBar(parent, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    if bg:SetTexture(ART .. "Arch-Progress-BG") then
        bg:SetTexCoord(0, 432 / 512, 0, 44 / 64)
        bg:SetPoint("TOPLEFT", -4, 4)
        bg:SetPoint("BOTTOMRIGHT", 4, -6)
    else
        bg:SetTexture(0, 0, 0, 0.6)
        bg:SetAllPoints()
    end
    if hasFill then
        bar:SetStatusBarTexture(ART .. "Arch-Progress-Fill")
    else
        bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
        bar:SetStatusBarColor(0.95, 0.6, 0.1)
    end
    bar:SetMinMaxValues(0, 1)
    return bar
end

local selected, filter, offset, shown = nil, "All", 0, nil   -- race, filter, first row, artifact on show
local redraw

-- The race list --------------------------------------------------------------------------------

local list = CreateFrame("Frame")
C.list = list
local raceRows = {}

local function raceRow(i)
    local row = raceRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list)
    row:SetHeight(C.RACE_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * C.RACE_ROW_HEIGHT)
    row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
    row.crest = row:CreateTexture(nil, "ARTWORK")
    row.crest:SetSize(36, 42)
    row.crest:SetPoint("LEFT", 2, 0)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("TOPRIGHT", -4, -8)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.crest, "TOPRIGHT", 8, -4)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.bar = progressBar(row, 8)
    row.bar:SetPoint("BOTTOMLEFT", row.crest, "BOTTOMRIGHT", 8, 4)
    row.bar:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.lit = row:CreateTexture(nil, "BACKGROUND")
    row.lit:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.lit:SetBlendMode("ADD")
    row.lit:SetVertexColor(1, 0.82, 0, 0.3)
    row.lit:SetAllPoints()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(1, 1, 1, 0.35)
    hl:SetAllPoints()
    row:SetScript("OnClick", function(self)
        selected, offset, shown = self.race, 0, nil
        redraw()
    end)
    raceRows[i] = row
    return row
end

-- The page ---------------------------------------------------------------------------------------

local card = CreateFrame("Frame")
C.card = card

local bigCrest = card:CreateTexture(nil, "ARTWORK")
bigCrest:SetSize(74, 95)
bigCrest:SetPoint("TOPLEFT", 0, 0)
local raceTitle = text(card, "GameFontNormalLarge", "head")
raceTitle:SetPoint("TOPLEFT", bigCrest, "TOPRIGHT", 10, -4)
raceTitle:SetPoint("RIGHT", card, "RIGHT", -4, 0)
raceTitle:SetJustifyH("LEFT")
local summary = text(card, "GameFontHighlightSmall", "body")
summary:SetPoint("TOPLEFT", raceTitle, "BOTTOMLEFT", 0, -6)
summary:SetPoint("RIGHT", card, "RIGHT", -4, 0)
summary:SetJustifyH("LEFT")
local raceBar = progressBar(card, 14)
raceBar:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 2, -8)
raceBar:SetPoint("RIGHT", card, "RIGHT", -8, 0)
local lockText = text(card, "GameFontHighlightSmall", "muted")
lockText:SetPoint("TOPLEFT", raceBar, "BOTTOMLEFT", -2, -8)
lockText:SetPoint("RIGHT", card, "RIGHT", -4, 0)
lockText:SetJustifyH("LEFT")

-- The race's relic trait.
local traitTitle = text(card, "GameFontNormal", "head")
traitTitle:SetPoint("TOPLEFT", 2, -104)
traitTitle:SetPoint("RIGHT", card, "RIGHT", -4, 0)
traitTitle:SetJustifyH("LEFT")
local traitText = text(card, "GameFontHighlightSmall", "body")
traitText:SetPoint("TOPLEFT", traitTitle, "BOTTOMLEFT", 0, -4)
traitText:SetPoint("RIGHT", card, "RIGHT", -4, 0)
traitText:SetHeight(52)
traitText:SetJustifyH("LEFT")
traitText:SetJustifyV("TOP")

-- The artifacts: a filter, a page of rows, Previous / Next.
local browse = CreateFrame("Frame", nil, card)
browse:SetPoint("TOPLEFT", 0, -178)
browse:SetPoint("BOTTOMRIGHT")
local filters = {}
for i, label in ipairs({ "All", "Collected", "Missing" }) do
    local b = button(browse, label, 80)
    b:SetHeight(20)
    b:SetPoint("TOPLEFT", (i - 1) * 84, 0)
    b:SetScript("OnClick", function() filter, offset = label, 0; redraw() end)
    filters[label] = b
end

local rows = {}
for i = 1, PER_PAGE do
    local row = CreateFrame("Button", nil, browse)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -26 - (i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", browse, "RIGHT", 0, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 2, 0)
    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    row.check:SetSize(14, 14)
    row.check:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 4, -3)
    row.count = text(row, "GameFontHighlightSmall", "muted")
    row.count:SetPoint("RIGHT", -6, 0)
    row.name = text(row, "GameFontHighlightSmall", "body")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(1, 0.82, 0, 0.35)
    hl:SetAllPoints()
    row:SetScript("OnEnter", function(self)
        local p = self.project
        if not p then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(p.name)
        GameTooltip:AddLine((p.rare and "Rare" or "Common") .. " - " .. (p.solves > 0 and "Collected" or "Missing"), 1, 1, 1)
        GameTooltip:AddLine("Times solved: " .. p.solves, 1, 1, 1)
        GameTooltip:AddLine("Click for its lore; Shift-click to link the reward.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local p = self.project
        if not p then return end
        if IsShiftKeyDown() then
            local _, link = GetItemInfo(p.item)
            if link and ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. p.item)
            GameTooltip:Show()
            return
        end
        GameTooltip:Hide()
        shown = p.id
        A.RequestProject(p.id)
        redraw()
    end)
    rows[i] = row
end

local previous = button(browse, PREV or "Previous", 80)
previous:SetPoint("BOTTOMLEFT", 0, 0)
previous:SetScript("OnClick", function() offset = math.max(0, offset - PER_PAGE); redraw() end)
local nextPage = button(browse, NEXT or "Next", 80)
nextPage:SetPoint("BOTTOMRIGHT", 0, 0)
nextPage:SetScript("OnClick", function() offset = offset + PER_PAGE; redraw() end)
local pageText = text(browse, "GameFontHighlightSmall", "muted")
pageText:SetPoint("BOTTOM", 0, 6)

-- One artifact: its sketch (a rare) or the race's crest, its name and lore.
local detail = CreateFrame("Frame", nil, card)
detail:SetPoint("TOPLEFT", 0, -104)
detail:SetPoint("BOTTOMRIGHT")
detail:Hide()
local sketch = detail:CreateTexture(nil, "ARTWORK")
sketch:SetPoint("TOP", 0, -2)
local artifact = CreateFrame("Button", nil, detail)
artifact:SetSize(32, 32)
artifact.icon = artifact:CreateTexture(nil, "ARTWORK")
artifact.icon:SetAllPoints()
artifact:SetScript("OnEnter", function(self)
    if not self.item then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. self.item)
    GameTooltip:Show()
end)
artifact:SetScript("OnLeave", function() GameTooltip:Hide() end)
artifact:SetScript("OnClick", function(self)
    if not self.item then return end
    local _, link = GetItemInfo(self.item)
    if link and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
end)
local artifactName = text(detail, "GameFontNormal", "head")
artifactName:SetPoint("TOPLEFT", artifact, "TOPRIGHT", 8, -1)
artifactName:SetPoint("RIGHT", detail, "RIGHT", -4, 0)
artifactName:SetJustifyH("LEFT")
local artifactTag = text(detail, "GameFontHighlightSmall", "muted")
artifactTag:SetPoint("TOPLEFT", artifactName, "BOTTOMLEFT", 0, -3)
local lore = text(detail, "GameFontHighlightSmall", "body")
lore:SetPoint("TOPLEFT", artifact, "BOTTOMLEFT", 0, -10)
lore:SetPoint("BOTTOMRIGHT", -4, 30)
lore:SetJustifyH("LEFT")
lore:SetJustifyV("TOP")
local back = button(detail, BACK or "Back", 80)
back:SetPoint("BOTTOMLEFT", 0, 0)
back:SetScript("OnClick", function() shown = nil; redraw() end)

local function drawDetail(p)
    local width = detail:GetWidth()
    if not width or width <= 0 then width = 320 end
    local file = p.rare and ("ArchRare-" .. (SKETCHES[p.id] or "")) or nil
    if p.rare and not SKETCHES[p.id] then file = SKETCH_NONE end
    local drawn
    if file then
        local w = math.min(width, 150 * SKETCH_ASPECT)
        sketch:SetSize(w, w / SKETCH_ASPECT)
        drawn = art(sketch, file, SKETCH_COORDS, nil)
    end
    if not drawn then
        sketch:SetSize(94, 120)
        drawn = art(sketch, CRESTS[p.race] and ("Arch-Race-" .. CRESTS[p.race] .. "Big"), BIG_COORDS, nil)
    end
    sketch:SetAlpha(p.rare and 1 or 0.85)
    show(sketch, drawn)
    artifact:ClearAllPoints()
    if drawn then
        artifact:SetPoint("TOPLEFT", sketch, "BOTTOMLEFT", 0, -8)
        artifact:SetPoint("LEFT", detail, "LEFT", 2, 0)
    else
        artifact:SetPoint("TOPLEFT", 2, -2)
    end
    artifact.item = p.item
    artifact.icon:SetTexture(GetItemIcon(p.item) or A.SHOVEL)
    artifactName:SetText((p.rare and "|cffa335ee" or "") .. p.name .. (p.rare and "|r" or ""))
    artifactTag:SetText((p.rare and "Rare artifact" or "Common artifact") .. " - "
        .. (p.solves > 0 and ("solved " .. p.solves .. (p.solves == 1 and " time" or " times")) or "not solved yet"))
    local info = A.projects[p.id]
    lore:SetText(info and info.text or "...")
end

-- Drawing ----------------------------------------------------------------------------------------

-- Totals over every race; a host draws them (our window: the line under its title).
C.drawTotals = function() end

redraw = function()
    if not card:IsVisible() then return end
    local catalogue = A.collection or {}
    local done, count, rareDone, rareCount = 0, 0, 0, 0
    local summaries = {}
    for _, p in pairs(catalogue) do
        local c = summaries[p.race] or { done = 0, count = 0, rareDone = 0, rareCount = 0 }
        summaries[p.race] = c
        count, c.count = count + 1, c.count + 1
        if p.solves > 0 then done, c.done = done + 1, c.done + 1 end
        if p.rare then
            rareCount, c.rareCount = rareCount + 1, c.rareCount + 1
            if p.solves > 0 then rareDone, c.rareDone = rareDone + 1, c.rareDone + 1 end
        end
    end
    C.drawTotals(A.collection ~= nil, done, count, rareDone, rareCount)

    if not (selected and A.races[selected]) then selected = A.raceOrder[1] end
    for i, id in ipairs(A.raceOrder) do
        local race, row = A.races[id], raceRow(i)
        local c = summaries[id] or { done = 0, count = 0 }
        row.race = id
        if C.Crest(row.crest, id) then row.crest:SetSize(36, 42) else row.crest:SetSize(32, 32) end
        row.crest:SetDesaturated(not race.unlocked)
        row.name:SetText(race.name)
        if race.unlocked then row.name:SetTextColor(1, 0.82, 0) else row.name:SetTextColor(0.6, 0.6, 0.6) end
        row.count:SetText(c.done .. "/" .. c.count)
        row.bar:SetValue(c.count > 0 and c.done / c.count or 0)
        show(row.lit, id == selected)
        row:Show()
    end
    for i = #A.raceOrder + 1, #raceRows do raceRows[i]:Hide() end

    local race = selected and A.races[selected]
    local c = summaries[selected] or { done = 0, count = 0, rareDone = 0, rareCount = 0 }
    if art(bigCrest, race and CRESTS[selected] and ("Arch-Race-" .. CRESTS[selected] .. "Big"), BIG_COORDS, nil) then
        bigCrest:SetSize(74, 95)
    else
        bigCrest:SetSize(56, 56)
        art(bigCrest, nil, nil, race and A.RaceIcon(selected) or nil)
    end
    bigCrest:SetDesaturated(race and not race.unlocked)
    raceTitle:SetText(race and race.name or "")
    if not A.collection then
        summary:SetText("Loading the collection from the realm...")
    else
        summary:SetText(string.format("%d/%d discovered  -  Rares %d/%d%s", c.done, c.count, c.rareDone,
            c.rareCount, c.count > 0 and c.done == c.count and "  -  Race complete!" or ""))
    end
    raceBar:SetValue(c.count > 0 and c.done / c.count or 0)
    local unlock = (A.unlocks or {})[selected]
    local lock = ""
    if race and not race.unlocked then lock = "Unlocks at Archaeology skill " .. (unlock and unlock.skill or "?") end
    if unlock and not unlock.era then
        lock = (lock ~= "" and lock .. "; " or "") .. "needs progression stage " .. unlock.state
    end
    lockText:SetText(lock)

    local t = (A.traits or {})[selected]
    if t then
        traitTitle:SetText(t.name .. "  -  " .. t.status)
        traitText:SetText((t.effect and t.effect ~= "" and (t.effect .. "\n") or "")
            .. (t.awake and ("Unlocked: relic strength " .. t.strength .. "%.")
                or ("Unlock: solve one rare or " .. t.need .. " commons (" .. t.commons .. "/" .. t.need .. ")."))
            .. " Completion bonus " .. t.bonus .. "x. Equip the relic to use it.")
    else
        traitTitle:SetText("Race bonus")
        traitText:SetText(A.collection and "No relic trait on this realm for this race." or "")
    end

    local p = shown and catalogue[shown]
    if p and p.race == selected then
        browse:Hide()
        detail:Show()
        drawDetail(p)
        return
    end
    shown = nil
    detail:Hide()
    browse:Show()
    for label, b in pairs(filters) do
        if label == filter then b:Disable() else b:Enable() end
    end
    local items = {}
    for _, q in pairs(catalogue) do
        if q.race == selected and (filter == "All" or (filter == "Collected" and q.solves > 0)
                or (filter == "Missing" and q.solves == 0)) then
            tinsert(items, q)
        end
    end
    table.sort(items, function(a, b)
        if a.rare ~= b.rare then return a.rare end
        return a.name < b.name
    end)
    offset = math.min(offset, math.max(0, math.floor((#items - 1) / PER_PAGE) * PER_PAGE))
    for i, row in ipairs(rows) do
        local q = items[offset + i]
        row.project = q
        if q then
            row.icon:SetTexture(GetItemIcon(q.item) or A.SHOVEL)
            row.icon:SetDesaturated(q.solves == 0)
            show(row.check, q.solves > 0)
            row.name:SetText((q.rare and "|cffa335ee" or "") .. q.name .. (q.rare and "|r" or ""))
            row.name:SetTextColor(unpack(q.solves > 0 and ink.body or ink.muted))
            row.count:SetText(q.solves > 1 and ("x" .. q.solves) or "")
            row:Show()
        else
            row:Hide()
        end
    end
    pageText:SetText(#items > PER_PAGE and string.format("%d / %d", offset / PER_PAGE + 1, math.ceil(#items / PER_PAGE)) or "")
    if offset > 0 then previous:Enable() else previous:Disable() end
    if offset + PER_PAGE < #items then nextPage:Enable() else nextPage:Disable() end
end
C.Refresh = redraw

card:SetScript("OnShow", function()
    A.Request("COLLECTION", "COLLECTION")
    redraw()
end)
-- Trait progress moves as you fight; ask again while the page is open.
local elapsed = 0
card:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= 5 then
        elapsed = 0
        A.Request("TRAITS", "TRAITS")
    end
end)

-- Our own window -----------------------------------------------------------------------------------

local window = CreateFrame("Frame", "ArchaeologyUICollection", UIParent)
window:SetSize(660, 580)
window:SetPoint("CENTER")
window:SetFrameStrata("DIALOG")
window:SetToplevel(true)
window:SetClampedToScreen(true)
window:SetMovable(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
window:Hide()
tinsert(UISpecialFrames, "ArchaeologyUICollection")
local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)
local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -20)
title:SetText("Archaeology Collection & Race Bonuses")
local total = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
total:SetPoint("TOP", title, "BOTTOM", 0, -6)

-- The book page behind the card (its right edge is a texture of its own), as Cataclysm's window had.
local book = CreateFrame("Frame", nil, window)
book:SetPoint("TOPLEFT", 214, -54)
book:SetPoint("BOTTOMRIGHT", -36, 18)
local pageLeft = book:CreateTexture(nil, "BACKGROUND")
local pageRight = book:CreateTexture(nil, "BACKGROUND")
local hasBook = pageLeft:SetTexture(ART .. "Arch-BookCompletedLeft") and pageRight:SetTexture(ART .. "Arch-BookCompletedRight")
if hasBook then
    -- Without the binding and ribbon on the left.
    pageLeft:SetTexCoord(40 / 512, 1, 0, 494 / 512)
    pageLeft:SetPoint("TOPLEFT")
    pageLeft:SetPoint("BOTTOMRIGHT")
    pageRight:SetTexCoord(0, 21 / 32, 0, 494 / 512)
    pageRight:SetWidth(18)
    pageRight:SetPoint("TOPLEFT", pageLeft, "TOPRIGHT")
    pageRight:SetPoint("BOTTOMLEFT", pageLeft, "BOTTOMRIGHT")
else
    pageLeft:Hide()
    pageRight:Hide()
end

local function ownTotals(loaded, done, count, rareDone, rareCount)
    total:SetText(loaded and string.format("Discovered %d/%d artifacts  -  Rares %d/%d  -  %d left", done, count,
        rareDone, rareCount, count - done) or "")
end

-- The pieces back in our window, from a host's page.
function C.TakeBack()
    list:SetParent(window)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", 20, -60)
    list:SetPoint("BOTTOMLEFT", 20, 20)
    list:SetWidth(186)
    card:SetParent(book)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", 22, -24)
    card:SetPoint("BOTTOMRIGHT", -14, 22)
    C.SetInk(hasBook)
    C.drawTotals = ownTotals
end
C.TakeBack()

-- A host's way to open the page (Hosted.lua); false when it can't, and our window opens.
C.openHosted = nil

function A.OpenCollection()
    if C.openHosted and C.openHosted() then return end
    if list:GetParent() ~= window then C.TakeBack() end
    window:Show()
    redraw()
end

-- Below the research page's lore, beside Solve, in whichever window holds that page.
local entry = CreateFrame("Button", nil, A.Research.page, "UIPanelButtonTemplate")
entry:SetSize(160, 22)
entry:SetText("Collection & Bonuses")
entry:SetPoint("BOTTOMLEFT", 4, 4)
entry:SetScript("OnClick", A.OpenCollection)
C.entry = entry

A.On("COLLECTION", redraw)
A.On("RACES", redraw)
A.On("PROJECT", function(id)
    if shown == id then redraw() end
end)
A.On("SOLVED", function()
    if card:IsVisible() then A.Request("COLLECTION", "COLLECTION") end
end)
